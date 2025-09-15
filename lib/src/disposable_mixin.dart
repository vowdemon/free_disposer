part of '../free_disposer.dart';

/// A mixin that provides automatic resource disposal capabilities.
///
/// Classes can register resources for automatic cleanup using extension
/// methods and dispose all resources by calling [dispose].
///
/// ```dart
/// class MyService with DisposableMixin {
///   late Timer _timer;
///   late StreamController<String> _controller;
///
///   MyService() {
///     _timer = Timer.periodic(Duration(milliseconds: 500), (_) {
///       print('Timer tick');
///     });
///     _controller = StreamController<String>();
///
///     // Register resources
///     _timer.disposeBy(this);
///     _controller.disposeBy(this);
///
///     // Custom cleanup
///     disposeWith(() => print('Custom cleanup'));
///   }
/// }
///
/// final service = MyService();
/// await service.dispose(); // All resources cleaned up
/// ```
mixin DisposableMixin implements Disposable {
  bool _isDisposed = false;
  bool _isDisposing = false;

  /// Whether this object has been disposed.
  bool get isDisposed => _isDisposed;

  /// Dispose this object and execute all registered disposers.
  ///
  /// Safe to call multiple times. Handles both sync and async disposers.
  @override
  FutureOr<void> dispose() {
    if (_isDisposed || _isDisposing) return null;

    _isDisposing = true;

    try {
      final result = AutoDisposer.disposeObject(this);
      if (result is Future) {
        return result.whenComplete(() {
          _isDisposed = true;
          _isDisposing = false;
        });
      } else {
        _isDisposed = true;
        _isDisposing = false;
        return null;
      }
    } catch (e, st) {
      _isDisposed = true;
      _isDisposing = false;
      Zone.current.handleUncaughtError(e, st);
      rethrow;
    }
  }
}
