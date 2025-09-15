# Free Disposer

A Dart resource management library using Finalizer to automatically dispose resources when objects are garbage collected.

## Usage

### DisposableMixin (Recommended)

```dart
import 'dart:async';
import 'package:free_disposer/free_disposer.dart';

class MyService with DisposableMixin {
  late Timer _timer;
  late StreamController _controller;

  MyService() {
    _timer = Timer.periodic(Duration(seconds: 1), (_) => print('tick'));
    _controller = StreamController<String>();

    // Attach resources to this object
    _timer.disposeWith(this);
    _controller.disposeWith(this);
  }

  // All attached resources will be disposed automatically
}

void main() async {
  final service = MyService();
  // Use service...
  await service.dispose(); // Dispose all resources
}
```

### AutoDisposer

```dart
void example() async {
  final object = Object();
  final timer = Timer.periodic(Duration(seconds: 1), (_) {});

  // Attach disposer
  object.attachDisposer(() => timer.cancel());

  // Manual dispose
  await object.disposeAttached();
}
```

### Auto Cleanup with Finalizer

```dart
void createResource() {
  final object = Object();
  final timer = Timer.periodic(Duration(seconds: 1), (_) => print('tick'));

  // Timer will be cancelled automatically when object is GC'd
  object.attachDisposer(() => timer.cancel());

  // object goes out of scope, will be cleaned up by GC
}
```

## Important: Don't Capture `this` in Disposers

**⚠️ Never reference `this` inside disposer functions - it will prevent garbage collection:**

```dart
class BadExample with DisposableMixin {
  late Timer timer;

  void setup() {
    timer = Timer.periodic(Duration(seconds: 1), (_) {});

    // ❌ WRONG: captures `this`, prevents GC
    onDispose(() {
      this.timer.cancel(); // Don't do this!
    });

    // ✅ CORRECT: no `this` reference
    onDispose(() {
      timer.cancel(); // Direct variable access
    });
  }
}
```

## Supported Types

Built-in support for common resource types:

```dart
Timer timer;                    // → timer.cancel()
StreamSubscription subscription; // → subscription.cancel()
StreamController controller;     // → controller.close()
HttpClient client;              // → client.close()
Disposable disposable;          // → disposable.dispose()

// Usage
timer.disposeWith(myService);
subscription.disposeWith(myService);
```

## Custom Adapters

Register custom adapters for third-party types:

```dart
class DatabaseConnection {
  void close() => print('Database closed');
}

// Register adapter
DisposerAdapterManager.register<DatabaseConnection>(
  (db) => db.close,
);

// Now it works with the disposal system
final service = MyService();
final db = DatabaseConnection();

db.disposeWith(service);    // Works!
await service.dispose();   // Database closed
```

## License

MIT
