part of '../free_disposer.dart';

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
extension DisposableExtension<T extends Object> on T {
  /// Convert this object to a disposer function.
  ///
  /// **Returns:**
  /// A [Disposer] function appropriate for this object type, or `null`
  /// if no adapter is available for this type.
  ///
  /// **Example:**
  /// ```dart
  /// final timer = Timer.periodic(Duration(seconds: 1), (_) {});
  /// final disposer = timer.toDisposer;
  /// if (disposer != null) {
  ///   await disposer(); // Timer is cancelled
  /// }
  /// ```
  Disposer? get toDisposer => DisposerAdapterManager.getDisposer(this);

  /// Register this object with a [DisposableMixin] for automatic disposal.
  ///
  /// When the [disposable] is disposed, this object will be disposed too.
  /// If no disposer can be created for this object (toDisposer returns null),
  /// the registration is silently ignored.
  ///
  /// **Parameters:**
  /// - [disposable]: The disposable object to register with
  ///
  /// **Example:**
  /// ```dart
  /// final service = MyService();
  /// final timer = Timer.periodic(Duration(seconds: 1), (_) {});
  /// final customObject = SomeCustomObject(); // might not have adapter
  ///
  /// timer.disposeWith(service);        // will work (built-in support)
  /// customObject.disposeWith(service); // safe even if no adapter exists
  /// await service.dispose(); // Timer cancelled, customObject ignored
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
/// directly on object instances. All methods handle null disposers gracefully.
extension AutoDisposeExtension on Object {
  /// Attach a disposer to this object.
  ///
  /// If [disposer] is null, this method does nothing. This allows for
  /// convenient chaining with nullable disposers.
  ///
  /// **Parameters:**
  /// - [disposer]: The cleanup function to attach, or null to ignore
  ///
  /// **Throws:**
  /// - [UnsupportedError] if this object is a blacklisted type
  ///
  /// **Example:**
  /// ```dart
  /// final obj = Object();
  /// final disposer = someObject.toDisposer; // might be null
  /// obj.attachDisposer(disposer); // safe even if disposer is null
  /// ```
  void attachDisposer(Disposer? disposer) {
    if (disposer != null) {
      AutoDisposer.attachDisposer(this, disposer);
    }
  }

  /// Attach multiple disposers to this object.
  ///
  /// Null disposers in the list are automatically filtered out and ignored.
  /// This allows for convenient bulk attachment of potentially nullable disposers.
  ///
  /// **Parameters:**
  /// - [disposers]: The list of cleanup functions to attach (nulls are ignored)
  ///
  /// **Example:**
  /// ```dart
  /// final obj = Object();
  /// obj.attachDisposers([
  ///   timer.toDisposer,        // might be null
  ///   controller.toDisposer,   // might be null
  ///   () => print('cleanup'),  // non-null
  /// ]); // Only non-null disposers are attached
  /// ```
  void attachDisposers(List<Disposer?> disposers) {
    for (final d in disposers) {
      if (d != null) {
        AutoDisposer.attachDisposer(this, d);
      }
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
  FutureOr<void> disposeAttached() => AutoDisposer.disposeObject(this);

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
