library;

import 'dart:async';
import 'dart:io'
    show HttpClient, ServerSocket, RawSocket, RawServerSocket, RandomAccessFile;

/// A function that performs cleanup operations.
///
/// Can be synchronous or asynchronous.
typedef Disposer = FutureOr<void> Function();

/// Interface for objects that can be disposed.
///
/// Implementing classes should clean up resources in the [dispose] method.
abstract class Disposable {
  /// Dispose this object and clean up its resources.
  ///
  /// This method should be idempotent - calling it multiple times
  /// should be safe and not cause errors.
  FutureOr<void> dispose();
}

/// Blacklisted types that cannot have Finalizers attached
const Set<Type> _blacklistedTypes = {int, double, num, bool, String};

bool _isBlacklisted(Object? object) {
  if (object == null) return true;
  final type = object.runtimeType;
  return _blacklistedTypes.contains(type) ||
      object is Enum ||
      object is Symbol ||
      object is Type;
}

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
  static Future<void> disposeObject(Object object) async {
    final disposers = _disposers[object];
    if (disposers == null || disposers.isEmpty) return;

    final token = _detachToken[object];
    if (token != null) {
      try {
        _finalizer.detach(token);
      } catch (_) {}
      _detachToken[object] = null;
    }

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

    if (futures.isNotEmpty) {
      await Future.wait(futures, eagerError: false);
    }

    disposers.clear();
    _disposers[object] = null;
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

/// A mixin that provides automatic resource disposal capabilities.
///
/// Classes that mix in [DisposableMixin] can register disposers using
/// [onDispose] and clean up all resources by calling [dispose].
///
/// **Example:**
/// ```dart
/// class MyService with DisposableMixin {
///   late Timer _timer;
///
///   MyService() {
///     _timer = Timer.periodic(Duration(seconds: 1), (_) {});
///     onDispose(() => _timer.cancel());
///   }
/// }
///
/// final service = MyService();
/// await service.dispose(); // Timer will be cancelled
/// ```
mixin DisposableMixin implements Disposable {
  bool _isDisposed = false;
  bool _isDisposing = false;

  /// Whether this object has been disposed.
  bool get isDisposed => _isDisposed;

  /// Add a disposer that will be executed when [dispose] is called.
  ///
  /// **WARNING:** Don't capture `this` in the disposer closure as it
  /// will prevent garbage collection.
  ///
  /// **Parameters:**
  /// - [disposer]: The cleanup function to register
  ///
  /// **Example:**
  /// ```dart
  /// class MyClass with DisposableMixin {
  ///   late Timer timer;
  ///
  ///   void setup() {
  ///     timer = Timer.periodic(Duration(seconds: 1), (_) {});
  ///
  ///     // ✅ Correct: no `this` reference
  ///     onDispose(() => timer.cancel());
  ///
  ///     // ❌ Wrong: captures `this`
  ///     // onDispose(() => this.timer.cancel());
  ///   }
  /// }
  /// ```
  void onDispose(Disposer disposer) {
    if (_isDisposed || _isDisposing) return;

    try {
      AutoDisposer.attachDisposer(this, disposer);
    } catch (e, st) {
      Zone.current.handleUncaughtError(e, st);
    }
  }

  /// Add a child [Disposable] that will be disposed when this object is disposed.
  ///
  /// **Parameters:**
  /// - [disposable]: The disposable object to add
  ///
  /// **Example:**
  /// ```dart
  /// final parent = MyDisposable();
  /// final child = MyDisposable();
  ///
  /// parent.addDisposable(child);
  /// await parent.dispose(); // child.dispose() will be called
  /// ```
  void addDisposable(Disposable disposable) => onDispose(disposable.dispose);

  /// Dispose this object and execute all registered disposers.
  ///
  /// This method is idempotent - calling it multiple times is safe.
  /// Once disposed, no new disposers can be added.
  ///
  /// **Returns:**
  /// A [Future] that completes when all disposers have finished executing.
  ///
  /// **Example:**
  /// ```dart
  /// final disposable = MyDisposable();
  /// await disposable.dispose(); // Clean up all resources
  /// ```
  @override
  FutureOr<void> dispose() async {
    if (_isDisposed || _isDisposing) return;
    _isDisposing = true;

    try {
      await AutoDisposer.disposeObject(this);
    } finally {
      _isDisposed = true;
      _isDisposing = false;
    }
  }
}

/// Extension that provides disposer conversion for common resource types.
///
/// This extension automatically converts various resource types to
/// appropriate disposer functions.
///
/// **Supported types:**
/// - [Disposable] → calls `dispose()`
/// - [StreamSubscription] → calls `cancel()`
/// - [Timer] → calls `cancel()`
/// - [StreamController] → calls `close()`
/// - [Sink] → calls `close()`
/// - [HttpClient] → calls `close()`
/// - [ServerSocket] → calls `close()`
/// - [RawSocket] → calls `close()`
/// - [RawServerSocket] → calls `close()`
/// - [RandomAccessFile] → calls `close()`
extension DisposableExtension<T extends Object> on T {
  /// Convert this object to a disposer function.
  ///
  /// **Returns:**
  /// A [Disposer] function appropriate for this object type.
  ///
  /// **Throws:**
  /// - [UnsupportedError] if the object type is not supported
  ///
  /// **Example:**
  /// ```dart
  /// final timer = Timer.periodic(Duration(seconds: 1), (_) {});
  /// final disposer = timer.toDisposer; // Returns () => timer.cancel()
  /// await disposer(); // Timer is cancelled
  /// ```
  Disposer get toDisposer => switch (this) {
    Disposable d => d.dispose,
    StreamSubscription s => s.cancel,
    Timer t => t.cancel,
    StreamController c => () async {
      try {
        if (!c.isClosed) {
          if (c.hasListener || c.stream.isBroadcast) {
            await c.close().timeout(
              const Duration(milliseconds: 500),
              onTimeout: () {},
            );
          } else {
            await c.close().timeout(
              const Duration(milliseconds: 100),
              onTimeout: () {},
            );
          }
        }
      } catch (e, st) {
        Zone.current.handleUncaughtError(e, st);
      }
    },
    Sink s => s.close,
    HttpClient c => c.close,
    ServerSocket s => s.close,
    RawSocket s => s.close,
    RawServerSocket s => s.close,
    RandomAccessFile f => f.close,
    _ => throw UnsupportedError(
      'Unsupported type: $runtimeType, must be Disposable',
    ),
  };

  /// Register this object with a [DisposableMixin] for automatic disposal.
  ///
  /// When the [disposable] is disposed, this object will be disposed too.
  ///
  /// **Parameters:**
  /// - [disposable]: The disposable object to register with
  ///
  /// **Example:**
  /// ```dart
  /// final service = MyService();
  /// final timer = Timer.periodic(Duration(seconds: 1), (_) {});
  ///
  /// timer.disposeWith(service);
  /// await service.dispose(); // Timer will be cancelled
  /// ```
  void disposeWith(DisposableMixin disposable) {
    try {
      disposable.onDispose(toDisposer);
    } catch (e, st) {
      Zone.current.handleUncaughtError(e, st);
    }
  }
}

/// Extension for batch disposal operations on iterables.
///
/// This extension allows disposing multiple objects at once.
extension AutoDisposeList on Iterable<Object> {
  /// Register all objects in this iterable with a [DisposableMixin].
  ///
  /// Each object in the iterable will be registered for disposal
  /// when [disposable] is disposed.
  ///
  /// **Parameters:**
  /// - [disposable]: The disposable object to register with
  ///
  /// **Example:**
  /// ```dart
  /// final service = MyService();
  /// final resources = [
  ///   Timer.periodic(Duration(seconds: 1), (_) {}),
  ///   StreamController<int>(),
  ///   HttpClient(),
  /// ];
  ///
  /// resources.disposeAllWith(service);
  /// await service.dispose(); // All resources will be disposed
  /// ```
  void disposeAllWith(DisposableMixin disposable) {
    for (final o in this) {
      o.disposeWith(disposable);
    }
  }
}

/// Extension that provides [AutoDisposer] operations on any object.
///
/// This extension adds convenient methods for working with [AutoDisposer]
/// directly on object instances.
extension AutoDisposeExtension on Object {
  /// Attach a disposer to this object.
  ///
  /// **Parameters:**
  /// - [disposer]: The cleanup function to attach
  ///
  /// **Throws:**
  /// - [UnsupportedError] if this object is a blacklisted type
  ///
  /// **Example:**
  /// ```dart
  /// final obj = Object();
  /// obj.attachDisposer(() => print('disposed'));
  /// ```
  void attachDisposer(Disposer disposer) =>
      AutoDisposer.attachDisposer(this, disposer);

  /// Attach multiple disposers to this object.
  ///
  /// **Parameters:**
  /// - [disposers]: The list of cleanup functions to attach
  ///
  /// **Example:**
  /// ```dart
  /// final obj = Object();
  /// obj.attachDisposers([
  ///   () => print('cleanup 1'),
  ///   () => print('cleanup 2'),
  /// ]);
  /// ```
  void attachDisposers(List<Disposer> disposers) {
    for (final d in disposers) {
      AutoDisposer.attachDisposer(this, d);
    }
  }

  /// Detach all disposers from this object without executing them.
  ///
  /// **Example:**
  /// ```dart
  /// final obj = Object();
  /// obj.attachDisposer(() => print('disposed'));
  /// obj.detachDisposers(); // No cleanup will occur
  /// ```
  void detachDisposers() => AutoDisposer.detachDisposers(this);

  /// Execute all disposers attached to this object.
  ///
  /// **Returns:**
  /// A [Future] that completes when all disposers have finished executing.
  ///
  /// **Example:**
  /// ```dart
  /// final obj = Object();
  /// obj.attachDisposer(() => print('disposed'));
  /// await obj.disposeAttached(); // prints 'disposed'
  /// ```
  Future<void> disposeAttached() => AutoDisposer.disposeObject(this);

  /// Check if this object has any attached disposers.
  ///
  /// **Returns:**
  /// `true` if this object has disposers, `false` otherwise.
  bool get hasAttachedDisposers => AutoDisposer.hasDisposers(this);

  /// Get the number of disposers attached to this object.
  ///
  /// **Returns:**
  /// The number of attached disposers.
  int get attachedDisposerCount => AutoDisposer.disposerCount(this);
}
