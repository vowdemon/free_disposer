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
/// - [StreamSink] → calls `close()`
/// - [Sink] → calls `close()`
extension DisposableExtension on Object {
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

  /// Register this object with a [AutoDisposer] for automatic disposal.
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
  /// timer.disposeBy(service);        // will work (built-in support)
  /// customObject.disposeBy(service); // safe even if no adapter exists
  /// await service.dispose(); // Timer cancelled, customObject ignored
  /// ```
  void disposeBy(Object? disposable) {
    if (disposable == null) return;

    AutoDisposer.attachDisposer(disposable, toDisposer);
  }

  /// Attach a disposer function to this object.
  ///
  /// When this object is garbage collected (or manually disposed via
  /// [disposeAttached]), the provided [disposer] will be executed.
  ///
  /// **Parameters:**
  /// - [disposer]: The cleanup function to attach (can be `null`)
  ///
  /// **Returns:**
  /// A function that, when invoked, detaches the specific [disposer]
  /// from this object. Returns `null` if [disposer] is `null`.
  ///
  /// **Example:**
  /// ```dart
  /// final obj = Object();
  /// final detach = obj.disposeWith(() => print('cleanup'));
  ///
  /// // Later, if needed
  /// detach?.call();
  /// ```
  Disposer? disposeWith(Disposer? disposer) {
    AutoDisposer.attachDisposer(this, disposer);
    return () => AutoDisposer.detachDisposer(this, disposer);
  }

  /// Attach multiple disposer functions to this object.
  ///
  /// **Parameters:**
  /// - [disposers]: Iterable of disposer functions (null entries are ignored)
  ///
  /// **Returns:**
  /// A function that detaches all the specified [disposers] from this object.
  Disposer? disposeWithAll(Iterable<Disposer?> disposers) {
    for (final d in disposers) {
      if (d == null) continue;
      AutoDisposer.attachDisposer(this, d);
    }
    return () {
      for (final d in disposers) {
        if (d == null) continue;
        AutoDisposer.detachDisposer(this, d);
      }
    };
  }

  /// Detach all disposers from this object without executing them.
  ///
  /// **Example:**
  /// ```dart
  /// final obj = Object();
  /// obj.disposeWith(() => print('disposed'));
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
  /// obj.disposeWith(() => print('disposed'));
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

/// Extension for batch disposal operations on iterables.
///
/// This extension allows disposing multiple objects at once.
extension DisposableIterableExtension on Iterable<Object> {
  /// Register all objects in this iterable with a [AutoDisposer].
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
  /// resources.disposeAllBy(service);
  /// await service.dispose(); // All resources will be disposed
  /// ```
  void disposeAllBy(Object? disposable) {
    if (disposable == null) return;

    final s = <Disposer>{};
    for (final e in this) {
      final d = e.toDisposer;

      if (d != null) {
        s.add(d);
      }
    }
    AutoDisposer.attachDisposers(disposable, s);
  }
}
