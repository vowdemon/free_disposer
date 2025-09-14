part of '../free_disposer.dart';

class DisposedError extends Error {}

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
