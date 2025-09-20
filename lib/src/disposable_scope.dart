part of '../free_disposer.dart';

/// Zone extension for accessing the associated DisposableScope
///
/// This extension allows accessing the DisposableScope instance associated
/// with any Zone. Primarily used for internal implementation, developers
/// typically don't need to use this directly.
extension DisposableScopeZoneExtension on Zone {
  /// Gets the DisposableScope associated with the current Zone
  ///
  /// Returns null if the current Zone has no associated DisposableScope.
  DisposableScope? get disposableScope => this[#fd_scope] as DisposableScope?;
}

/// Zone-based scoped resource management class
///
/// DisposableScope provides a Dart Zone-based resource management mechanism
/// that allows registering and managing resources within a specific execution
/// context. When the scope is disposed, all registered resources are automatically cleaned up.
///
/// ## Usage Examples
///
/// ```dart
/// // Basic usage
/// final scope = DisposableScope();
/// final timer = Timer.periodic(Duration(seconds: 1), (_) {});
/// scope.register(timer);
/// await scope.dispose(); // Automatically cleans up timer
///
/// // Execute code within scope
/// final result = scope.run(() {
///   // In this function, DisposableScope.currentScope points to current scope
///   final controller = StreamController<int>();
///   DisposableScope.currentScope?.register(controller);
///   return 'Hello World';
/// });
///
/// // Async resource registration
/// final asyncResource = Future.delayed(Duration(seconds: 1), () {
///   return Timer.periodic(Duration(seconds: 1), (_) {});
/// });
/// final disposer = await scope.registerAsync(asyncResource);
/// ```
///
/// ## Best Practices
///
/// ```dart
/// Future<void> processData() async {
///   final scope = DisposableScope();
///
///   try {
///     // Use scope to manage resources
///     final timer = Timer.periodic(Duration(seconds: 1), (_) {});
///     scope.register(timer);
///
///     // Process business logic...
///     await processDataInternal();
///
///   } finally {
///     // Ensure all resources are cleaned up
///     await scope.dispose();
///   }
/// }
/// ```
class DisposableScope with DisposableMixin {
  /// Creates a new DisposableScope instance
  ///
  /// The [parent] parameter specifies the parent Zone, defaults to the current Zone.
  /// If a parent Zone is provided, the new scope will become its child scope.
  ///
  /// Example:
  /// ```dart
  /// // Use default parent Zone
  /// final scope = DisposableScope();
  ///
  /// // Use custom parent Zone
  /// final customZone = Zone.current.fork();
  /// final scope = DisposableScope(parent: customZone);
  /// ```
  DisposableScope({Zone? parent}) {
    parent ??= Zone.current;
    zone = parent.fork(zoneValues: {#fd_scope: this});
    parent.disposableScope?.register(this);
  }

  /// The Zone instance associated with the current scope
  ///
  /// This Zone contains the scope's context information and can be accessed via [currentScope].
  /// All code executed within the [run] method will run in this Zone.
  late final Zone zone;

  /// Synchronously registers a resource to the current scope
  ///
  /// When the scope is disposed, all resources registered through this method
  /// will be automatically cleaned up.
  ///
  /// Parameters:
  /// - [resource]: The resource object to register
  ///
  /// Returns:
  /// A [Disposer] function that can be called to unregister the resource
  ///
  /// Example:
  /// ```dart
  /// final scope = DisposableScope();
  /// final timer = Timer.periodic(Duration(seconds: 1), (_) {});
  ///
  /// // Use default cleanup method
  /// final disposer = scope.register(timer);
  ///
  /// // Use custom cleanup method
  /// final customDisposer = scope.register(someObject, () {
  ///   print('Custom cleanup for someObject');
  /// });
  ///
  /// // Unregister
  /// disposer();
  /// ```
  Disposer register(Object resource) {
    final disposer = resource.toDisposer;

    AutoDisposer.attachDisposer(this, disposer);
    return () => AutoDisposer.detachDisposer(this, disposer);
  }

  /// Asynchronously registers a resource to the current scope
  ///
  /// This method is used for handling resources that need to be created asynchronously.
  /// If the scope is disposed before the async resource completes, the resource
  /// will be immediately cleaned up.
  ///
  /// Parameters:
  /// - [resource]: Async resource Future
  ///
  /// Returns:
  /// A Future that completes with a cleanup function
  ///
  /// Example:
  /// ```dart
  /// final scope = DisposableScope();
  ///
  /// // Create resource asynchronously
  /// final futureResource = Future.delayed(Duration(seconds: 1), () {
  ///   return Timer.periodic(Duration(seconds: 1), (_) {});
  /// });
  ///
  /// final disposer = await scope.registerAsync(futureResource);
  /// ```
  ///
  /// Notes:
  /// - If the scope is disposed before the async resource completes, the resource will be immediately cleaned up
  /// - The returned disposer function can be safely called multiple times
  Future<Disposer> registerAsync(
    Future<Object> resource,
  ) async {
    final result = await resource;

    final disposer = result.toDisposer;

    if (disposer == null) return () {};
    if (isDisposed) {
      await disposer();
      return () {};
    }

    AutoDisposer.attachDisposer(this, disposer);
    return () => AutoDisposer.detachDisposer(this, disposer);
  }

  /// Executes a function within the scope's Zone and automatically registers returned resources
  ///
  /// Code executed within this method can access the current scope via [currentScope].
  /// If the function returns a Disposable object, it will be automatically registered to the scope.
  ///
  /// Parameters:
  /// - [fn]: The function to execute
  ///
  /// Returns:
  /// The return value of the function
  ///
  /// Example:
  /// ```dart
  /// final scope = DisposableScope();
  ///
  /// final result = scope.run(() {
  ///   // In this function, DisposableScope.currentScope points to current scope
  ///   final timer = Timer.periodic(Duration(seconds: 1), (_) {});
  ///   final controller = StreamController<int>();
  ///
  ///   // Can manually register resources
  ///   DisposableScope.currentScope?.register(timer);
  ///   DisposableScope.currentScope?.register(controller);
  ///
  ///   return 'Hello World';
  /// });
  ///
  /// // result is 'Hello World'
  /// // If result is a Disposable object, it will be automatically registered
  /// ```
  T run<T>(T Function() fn) {
    final result = zone.run(fn);
    if (!_isBlacklisted(result)) register(result!);
    return result;
  }

  /// Gets the DisposableScope instance in the current Zone
  ///
  /// This static method allows accessing the DisposableScope associated with the current Zone
  /// from anywhere. Primarily used to access the current scope within the [run] method.
  ///
  /// Returns:
  /// The current scope, or null if none exists
  ///
  /// Example:
  /// ```dart
  /// final scope = DisposableScope();
  ///
  /// scope.run(() {
  ///   // Within scope, can access current scope
  ///   final current = DisposableScope.currentScope;
  ///   assert(current == scope);
  /// });
  ///
  /// // Outside scope
  /// final current = DisposableScope.currentScope;
  /// assert(current == null);
  /// ```
  static DisposableScope? get currentScope =>
      Zone.current[#fd_scope] as DisposableScope?;
}
