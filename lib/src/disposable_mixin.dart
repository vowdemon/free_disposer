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

  /// Whether this object has been disposed.
  bool get isDisposed => _isDisposed;

  /// Dispose this object and execute all registered disposers.
  ///
  /// Safe to call multiple times. Handles both sync and async disposers.
  @override
  @mustCallSuper
  FutureOr<void> dispose() {
    if (_isDisposed) return null;

    _isDisposed = true;

    onDispose();
    return AutoDisposer.disposeObject(this);
  }

  @mustCallSuper
  void onDispose() {}
}
