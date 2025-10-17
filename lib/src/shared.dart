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
