part of '../free_disposer.dart';

/// Automatic resource disposal using Finalizers.
///
/// This class provides static methods to attach disposers to objects.
/// When objects are garbage collected, their associated disposers
/// will be executed automatically.
///
/// Example:
/// ```dart
/// final object = Object();
/// final timer = Timer.periodic(Duration(seconds: 1), (_) {});
///
/// AutoDisposer.attachDisposer(object, () => timer.cancel());
/// // Timer will be cancelled when object is GC'd
/// ```
class AutoDisposer {
  static final Expando<List<Disposer>> _disposers = Expando<List<Disposer>>();

  static final Finalizer<List<Disposer>> _finalizer = Finalizer<List<Disposer>>(
    (disposers) {
      if (disposers.isEmpty) return;
      for (final d in List<Disposer>.from(disposers)) {
        try {
          final result = d();
          if (result is Future) {
            result.catchError(
              (e, st) => Zone.current.handleUncaughtError(e, st),
            );
          }
        } catch (e, st) {
          Zone.current.handleUncaughtError(e, st);
        }
      }
    },
  );

  static final Expando<Object> _detachToken = Expando<Object>();

  /// Attach a disposer to an object.
  ///
  /// When [object] is garbage collected, [disposer] will be executed
  /// automatically. The same disposer can only be attached once to
  /// the same object.
  ///
  /// **Parameters:**
  /// - [object]: The object to attach the disposer to
  /// - [disposer]: The cleanup function to execute
  ///
  /// **Throws:**
  /// - [UnsupportedError] if [object] is a blacklisted type
  ///
  /// **Example:**
  /// ```dart
  /// final obj = Object();
  /// final timer = Timer.periodic(Duration(seconds: 1), (_) {});
  ///
  /// AutoDisposer.attachDisposer(obj, () => timer.cancel());
  /// ```
  static void attachDisposer(Object object, Disposer disposer) {
    if (_isBlacklisted(object)) {
      throw UnsupportedError(
        'Cannot attach disposer to object of type ${object.runtimeType}',
      );
    }

    final disposers = _disposers[object] ??= <Disposer>[];
    if (!disposers.contains(disposer)) {
      disposers.add(disposer);
    }

    if (_detachToken[object] == null) {
      _detachToken[object] = disposers;
      _finalizer.attach(object, disposers, detach: _detachToken[object]);
    }
  }

  /// Manually dispose an object by executing all its disposers.
  ///
  /// This detaches the finalizer and executes all registered disposers
  /// immediately. After calling this method, no automatic cleanup will
  /// occur when the object is garbage collected.
  ///
  /// **Parameters:**
  /// - [object]: The object to dispose
  ///
  /// **Returns:**
  /// A [Future] that completes when all disposers have finished executing.
  ///
  /// **Example:**
  /// ```dart
  /// final obj = Object();
  /// obj.attachDisposer(() => print('disposed'));
  ///
  /// await AutoDisposer.disposeObject(obj); // prints 'disposed'
  /// ```
  static FutureOr<void> disposeObject(Object object) {
    final disposers = _disposers[object];
    if (disposers == null || disposers.isEmpty) return null;

    final token = _detachToken[object];
    if (token != null) {
      try {
        _finalizer.detach(token);
      } catch (_) {}
      _detachToken[object] = null;
    }

    Future<void>? future;
    final futures = <Future<void>>[];

    for (final d in List<Disposer>.from(disposers)) {
      try {
        final result = d();
        if (result is Future<void>) {
          futures.add(
            result.catchError(
              (e, st) => Zone.current.handleUncaughtError(e, st),
            ),
          );
        }
      } catch (e, st) {
        Zone.current.handleUncaughtError(e, st);
      }
    }

    disposers.clear();
    _disposers[object] = null;

    if (futures.isNotEmpty) {
      future = Future.wait(futures, eagerError: false);
    }

    return future;
  }

  /// Detach all disposers from an object without executing them.
  ///
  /// This removes the finalizer and clears all registered disposers
  /// without executing them. Use this when you want to prevent
  /// automatic cleanup from occurring.
  ///
  /// **Parameters:**
  /// - [object]: The object to detach disposers from
  ///
  /// **Example:**
  /// ```dart
  /// final obj = Object();
  /// obj.attachDisposer(() => print('disposed'));
  ///
  /// AutoDisposer.detachDisposers(obj); // No cleanup will occur
  /// ```
  static void detachDisposers(Object object) {
    final token = _detachToken[object];
    if (token != null) {
      try {
        _finalizer.detach(token);
      } catch (_) {}
      _detachToken[object] = null;
    }
    _disposers[object]?.clear();
    _disposers[object] = null;
  }

  static void detachDisposer(Object object, Disposer disposer) {
    final token = _detachToken[object];
    if (token != null) {
      _finalizer.detach(token);
    }
    _detachToken[object] = null;
  }

  /// Check if an object has any attached disposers.
  ///
  /// **Parameters:**
  /// - [object]: The object to check
  ///
  /// **Returns:**
  /// `true` if the object has disposers, `false` otherwise.
  static bool hasDisposers(Object object) =>
      _disposers[object]?.isNotEmpty ?? false;

  /// Get the number of disposers attached to an object.
  ///
  /// **Parameters:**
  /// - [object]: The object to check
  ///
  /// **Returns:**
  /// The number of attached disposers.
  static int disposerCount(Object object) => _disposers[object]?.length ?? 0;
}
