part of '../free_disposer.dart';

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
  Disposer? onDispose(Disposer? disposer) {
    if (_isDisposed || _isDisposing || disposer == null) return null;

    try {
      AutoDisposer.attachDisposer(this, disposer);
    } catch (e, st) {
      Zone.current.handleUncaughtError(e, st);
    }

    return () {
      if (_isDisposed) return;
      AutoDisposer.detachDisposer(this, disposer);
    };
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
  Disposer? addDisposable(Disposable disposable) =>
      onDispose(disposable.dispose);

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
  FutureOr<void> dispose() {
    if (_isDisposed || _isDisposing) return null;
    _isDisposing = true;

    try {
      final result = AutoDisposer.disposeObject(this);
      if (result is Future) {
        return result;
      }
    } catch (e, st) {
      Zone.current.handleUncaughtError(e, st);
    } finally {
      _isDisposed = true;
      _isDisposing = false;
    }
  }
}
