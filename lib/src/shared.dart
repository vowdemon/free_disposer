part of '../free_disposer.dart';

/// An error thrown when attempting to use a disposed object.
///
/// This error indicates that an operation was attempted on an object
/// that has already been disposed and its resources have been cleaned up.
///
/// **Example:**
/// ```dart
/// final service = MyService();
/// await service.dispose();
///
/// // This might throw DisposedError if the service checks disposal state
/// service.doSomething(); // throws DisposedError
/// ```
class DisposedError extends Error {
  /// Creates a new [DisposedError].
  DisposedError();

  @override
  String toString() => 'DisposedError: Object has been disposed';
}

/// A function that performs cleanup operations.
///
/// Can be either synchronous (returning `void`) or asynchronous
/// (returning `Future<void>`). This flexibility allows disposers to
/// handle both simple cleanup tasks and complex async operations.
///
/// **Example:**
/// ```dart
/// // Synchronous disposer
/// Disposer syncDisposer = () => print('cleaned up');
///
/// // Asynchronous disposer
/// Disposer asyncDisposer = () async {
///   await someAsyncCleanup();
/// };
/// ```
typedef Disposer = FutureOr<void> Function();

/// Interface for objects that can be disposed.
///
/// Implementing classes should clean up resources in the [dispose] method.
/// The disposal process should be idempotent and safe to call multiple times.
///
/// **Contract:**
/// - [dispose] must be idempotent (safe to call multiple times)
/// - After disposal, the object should be in a clean, unusable state
/// - Resources should be properly released to prevent memory leaks
///
/// **Example:**
/// ```dart
/// class MyResource implements Disposable {
///   Timer? _timer;
///
///   MyResource() {
///     _timer = Timer.periodic(Duration(seconds: 1), (_) {});
///   }
///
///   @override
///   Future<void> dispose() async {
///     _timer?.cancel();
///     _timer = null;
///   }
/// }
/// ```
abstract class Disposable {
  /// Dispose this object and clean up its resources.
  ///
  /// This method should be idempotent - calling it multiple times
  /// should be safe and not cause errors. After disposal, the object
  /// should not be used for any operations.
  ///
  /// **Returns:**
  /// A [Future] that completes when cleanup is finished, or completes
  /// synchronously if no async operations are needed.
  ///
  /// **Implementation Guidelines:**
  /// - Always check if already disposed before doing work
  /// - Clean up in reverse order of initialization when possible
  /// - Handle exceptions gracefully to prevent partial cleanup
  /// - Set disposed flag to prevent further use
  FutureOr<void> dispose();
}
