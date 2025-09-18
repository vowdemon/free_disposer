part of '../free_disposer.dart';

/// A function that converts an object of type [T] to a [Disposer].
///
/// Adapter functions are used by [DisposerAdapterManager] to provide
/// automatic disposal support for custom types.
///
/// **Parameters:**
/// - [object]: The object to create a disposer for
///
/// **Returns:**
/// A [Disposer] function that will clean up the object
///
/// **Example:**
/// ```dart
/// DisposerAdapter<HttpClient> httpAdapter = (client) => client.close;
/// ```
typedef DisposerAdapter<T> = Disposer Function(T object);

/// Manages disposer adapters for automatic resource cleanup.
///
/// This class allows registration of custom adapters that can convert
/// objects to appropriate disposer functions. It provides both user-defined
/// adapters and built-in adapters for common Dart types.
///
/// **Features:**
/// - Type-safe adapter registration
/// - Efficient caching for repeated lookups
/// - Built-in support for common types
/// - Priority system (built-in adapters take precedence)
///
/// **Example:**
/// ```dart
/// // Register a custom adapter
/// DisposerAdapterManager.register<HttpClient>((client) => client.close);
///
/// // Use the adapter
/// final client = HttpClient();
/// final disposer = DisposerAdapterManager.getDisposer(client);
/// await disposer(); // Closes the HTTP client
/// ```
class DisposerAdapterManager {
  DisposerAdapterManager._();

  /// List of user-registered adapter entries.
  static final List<_Entry> _userEntries = [];

  /// Cache mapping types to their corresponding adapter entries.
  ///
  /// This cache significantly improves lookup performance by avoiding
  /// repeated linear searches through the adapter list.
  static final Map<Type, _Entry?> _typeCache = {};

  /// Register a custom disposer adapter for type [T].
  ///
  /// The adapter will be used to create disposers for objects of type [T].
  /// If an adapter for the same type already exists, both will be kept
  /// (the first match will be used).
  ///
  /// **Type Parameters:**
  /// - [T]: The type to register an adapter for
  ///
  /// **Parameters:**
  /// - [adapter]: The function that converts objects of type [T] to disposers
  ///
  /// **Example:**
  /// ```dart
  /// // Register adapter for custom type
  /// class MyResource {
  ///   void cleanup() => print('cleaned up');
  /// }
  ///
  /// DisposerAdapterManager.register<MyResource>((resource) => resource.cleanup);
  /// ```
  static void register<T>(DisposerAdapter<T> adapter) {
    _userEntries.add(_Entry<T>(adapter));
    _typeCache.clear(); // Clear cache when adapters change
  }

  /// Unregister all adapters for type [T].
  ///
  /// This removes all previously registered adapters for the specified type.
  /// The type cache is cleared to ensure consistency.
  ///
  /// **Type Parameters:**
  /// - [T]: The type to unregister adapters for
  ///
  /// **Example:**
  /// ```dart
  /// DisposerAdapterManager.unregister<MyResource>();
  /// ```
  static void unregister<T>() {
    _userEntries.removeWhere((e) => e.type == T);
    _typeCache.clear();
  }

  /// Clear all registered adapters and cache.
  ///
  /// This removes all user-registered adapters and clears the type cache.
  /// Built-in adapters are not affected.
  ///
  /// **Example:**
  /// ```dart
  /// DisposerAdapterManager.clear(); // Remove all custom adapters
  /// ```
  static void clear() {
    _userEntries.clear();
    _typeCache.clear();
  }

  /// Get a disposer for the given object.
  ///
  /// This method first checks for built-in disposers, then searches through
  /// user-registered adapters. Results are cached for improved performance.
  ///
  /// **Parameters:**
  /// - [object]: The object to get a disposer for
  ///
  /// **Returns:**
  /// A [Disposer] function appropriate for the object, or `null` if no
  /// adapter is found for the object type.
  ///
  /// **Example:**
  /// ```dart
  /// final timer = Timer.periodic(Duration(seconds: 1), (_) {});
  /// final disposer = DisposerAdapterManager.getDisposer(timer);
  /// if (disposer != null) {
  ///   await disposer(); // Timer is cancelled
  /// }
  /// ```
  static Disposer? getDisposer(Object? object) {
    if (object != null) {
      // Check built-in disposers first (higher priority)
      final d = getBuiltinDisposer(object);
      if (d != null) return d;

      // Check user-registered adapters with caching
      final type = object.runtimeType;
      var entry = _typeCache[type];

      // Cache miss - search through registered adapters
      if (entry == null && !_typeCache.containsKey(type)) {
        for (final e in _userEntries) {
          if (e.matches(object)) {
            entry = e;
            break;
          }
        }
        _typeCache[type] = entry; // Cache the result (even if null)
      }

      if (entry != null) return entry.invoke(object);
    }
    return null;
  }

  /// Get a built-in disposer for common Dart types.
  ///
  /// This method provides disposers for commonly used Dart types without
  /// requiring explicit adapter registration.
  ///
  /// **Supported built-in types:**
  /// - [Disposable] → calls `dispose()`
  /// - [StreamSubscription] → calls `cancel()`
  /// - [Timer] → calls `cancel()`
  /// - [StreamController] → calls `close()` with timeout and error handling
  /// - [StreamSink] → calls `close()` with timeout and error handling
  /// - [Sink] → calls `close()`
  ///
  /// **Parameters:**
  /// - [object]: The object to get a built-in disposer for
  ///
  /// **Returns:**
  /// A [Disposer] function if the type is supported, `null` otherwise
  ///
  /// **Example:**
  /// ```dart
  /// final controller = StreamController<int>();
  /// final disposer = DisposerAdapterManager.getBuiltinDisposer(controller);
  /// if (disposer != null) {
  ///   await disposer(); // StreamController is closed
  /// }
  /// ```
  @pragma('vm:prefer-inline')
  static Disposer? getBuiltinDisposer(Object? object) => switch (object) {
        Function() f => f,
        Disposable d => d.dispose,
        StreamSubscription s => s.cancel,
        Timer t => t.cancel,
        StreamController c => () => c
            .close()
            .timeout(Duration(milliseconds: 10), onTimeout: () {})
            .catchError((_) {}),
        StreamSink s => () => s
            .close()
            .timeout(Duration(milliseconds: 10), onTimeout: () {})
            .catchError((_) {}),
        Sink s => s.close,
        _ => null,
      };
}

class _Entry<T> {
  final DisposerAdapter<T> adapter;

  Type get type => T;

  _Entry(this.adapter);
  bool matches(Object object) => object is T;
  Disposer invoke(Object object) => adapter(object as T);
}
