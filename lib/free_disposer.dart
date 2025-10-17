/// A powerful and efficient resource disposal library for Dart.
///
/// Free Disposer provides automatic resource management through multiple
/// strategies: mixin-based disposal, finalizer-based cleanup, and adapter
/// pattern for custom types. It's designed for high performance with
/// optimizations like batch processing and efficient caching.
///
/// ## Key Features
///
/// - **Automatic Cleanup**: Resources are disposed when objects are garbage collected
/// - **Manual Control**: Explicit disposal methods for immediate cleanup
/// - **Type Safety**: Compile-time safety with generic adapters
/// - **High Performance**: Optimized with batching, caching, and efficient data structures
/// - **Flexible API**: Multiple approaches to fit different use cases
/// - **Error Handling**: Robust error handling with zone integration
///
/// ## Usage Patterns
///
/// ### 1. DisposableMixin - For Classes You Control
///
/// ```dart
/// class MyService with DisposableMixin {
///   late Timer _timer;
///   late StreamSubscription _subscription;
///
///   MyService() {
///     _timer = Timer.periodic(Duration(seconds: 1), (_) {});
///     _subscription = someStream.listen((_) {});
///
///     // Register resources using extension methods
///     _timer.disposeBy(this);
///     _subscription.disposeBy(this);
///   }
/// }
///
/// final service = MyService();
/// await service.dispose(); // All resources cleaned up
/// ```
///
/// ### 2. AutoDisposer - For Any Object
///
/// ```dart
/// final obj = Object();
/// final timer = Timer.periodic(Duration(seconds: 1), (_) {});
/// final subscription = stream.listen((_) {});
///
/// // Attach disposers - cleanup happens automatically on GC
/// obj.disposeWith(() => timer.cancel());
/// obj.disposeWith(() => subscription.cancel());
///
/// // Or dispose manually
/// await obj.disposeAttached();
/// ```
///
/// ### 3. Extension Methods - Convenient Syntax
///
/// ```dart
/// final service = MyService();
/// final timer = Timer.periodic(Duration(seconds: 1), (_) {});
/// final controller = StreamController<int>();
///
/// // Automatic disposal with service using built-in adapters
/// timer.disposeBy(service);
/// controller.disposeBy(service);
///
/// await service.dispose(); // Timer and controller cleaned up
/// ```
///
/// ### 4. Custom Adapters - For Third-Party Types
///
/// ```dart
/// class DatabaseConnection {
///   void close() => print('Database closed');
/// }
///
/// // Register adapter
/// DisposerAdapterManager.register<DatabaseConnection>(
///   (db) => db.close,
/// );
///
/// // Now DatabaseConnection works with disposal system
/// final service = MyService();
/// final db = DatabaseConnection();
/// db.disposeBy(service); // Works automatically with adapter
/// await service.dispose(); // Database closed
/// ```
///
/// ## Built-in Type Support
///
/// The library automatically supports these common Dart types:
///
/// - `Disposable` - calls `dispose()`
/// - `StreamSubscription` - calls `cancel()`
/// - `Timer` - calls `cancel()`
/// - `StreamController` - calls `close()` with timeout handling (10ms)
/// - `StreamSink` - calls `close()` with timeout handling (10ms)
/// - `Sink` - calls `close()`
///
/// ## Performance Characteristics
///
/// - **O(1)** disposer attachment (uses Set internally)
/// - **Batch processing** for finalizer operations
/// - **Efficient caching** for adapter lookups
/// - **Memory optimized** with weak references and cleanup
/// - **Concurrent safe** with proper error handling
///
/// ## Error Handling
///
/// All errors during disposal are caught and forwarded to the current
/// zone's error handler, ensuring that cleanup failures don't crash
/// your application.
///
/// ```dart
/// runZoned(() {
///   // Your application code
/// }, onError: (error, stackTrace) {
///   print('Disposal error: $error');
/// });
/// ```
///
/// ## Thread Safety
///
/// The library is designed to work safely in concurrent environments.
/// All operations are atomic and disposal can happen from any isolate.
///
/// ## Important Notes
///
/// **⚠️ Blacklisted Types**: Cannot attach disposers to primitive types
/// (`int`, `double`, `num`, `bool`, `String`), `null`, enums, symbols, or `Type` objects.
///
/// **⚠️ Memory Leaks**: Avoid capturing `this` in disposer functions when using
/// with `DisposableMixin`, as it prevents garbage collection.
library;

import 'dart:async';
import 'package:shared_interfaces/shared_interfaces.dart';

export 'package:shared_interfaces/shared_interfaces.dart'
    show Disposable, Disposer, ChainedDisposable;

part 'src/utils.dart';
part 'src/shared.dart';
part 'src/extension.dart';
part 'src/disposable_mixin.dart';
part 'src/auto_disposer.dart';
part 'src/adapter.dart';
