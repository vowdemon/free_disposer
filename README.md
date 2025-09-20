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

### DisposableScope (Zone-based Resource Management)

```dart
import 'dart:async';
import 'package:free_disposer/free_disposer.dart'; 

Future<void> main() async {
  final scope = DisposableScope();

  final res1 = MyResource('res1');
  scope.register(res1.dispose);

  await scope.registerAsync(
    Future.delayed(
      Duration(seconds: 1),
      () => MyResource('res2'),
    ),
  );

  print('Resources registered.');

  scope.run(() {
    final res3 = MyResource('res3');
    print('Running code with ${res3.name}');
    return res3; // run 会自动注册 res3
  });

  print('All resources created. Disposing scope...');

  await scope.dispose();

  print('Scope disposed, all resources cleaned. ${scope.isDisposed}');
}

class MyResource implements Disposable {
  final String name;
  MyResource(this.name);
  @override
  void dispose() => print('MyResource $name disposed');
}
```

## Important: Don't Capture `this` in Disposers

**⚠️ Never reference `this` inside disposer functions - it will prevent garbage collection:**

```dart
import 'dart:async';

import 'package:free_disposer/free_disposer.dart';

import 'dart:async';

import 'package:free_disposer/free_disposer.dart';

class BadExample with DisposableMixin {
  BadExample(this.name);
  final String name;
  Timer timer1 = Timer.periodic(Duration(seconds: 1), (_) {
    print('Bad timer1 tick');
  });

  void setup() {
    final name = this.name;
    // ❌ WRONG: captures `this`, prevents GC
    disposeWith(() {
      this.timer1.cancel(); // Don't do this!
      print('$name timer1 cancelled A');
    });

    // ❌ WRONG: captures property of `this`, prevents GC
    disposeWith(() {
      timer1.cancel(); // Don't do this!
      print('$name timer1 cancelled B');
    });

    // ❌ WRONG: captures method of `this`, prevents GC
    disposeWith(dispose);
  }

  @override
  FutureOr<void> dispose() {
    print('$name dispose');
    timer1.cancel();
    return super.dispose();
  }
}

class GoodExample with DisposableMixin {
  Timer? timer1 = Timer.periodic(Duration(seconds: 1), (_) {
    print('Good timer1 tick');
  });

  void setup() {
    Timer? timer2 = Timer.periodic(Duration(seconds: 1), (_) {
      print('Good timer2 tick');
    });

    // ✅ CORRECT: no `this` reference
    disposeWith(() {
      timer2?.cancel(); // Direct variable access
      timer2 = null;
      print('Good timer2 cancelled');
    });

    // ✅ CORRECT: no `this` reference
    disposeWith(this.timer1!.cancel);
  }

  @override
  FutureOr<void> dispose() {
    print('not be called by GC');
    timer1?.cancel();
    return super.dispose();
  }
}

void main() async {
  BadExample? badExample = BadExample('Bad A');
  badExample.setup();
  BadExample? badExample2 = BadExample('Bad B');
  badExample2.setup();

  GoodExample? goodExample = GoodExample();
  goodExample.setup();

  badExample = null;
  goodExample = null;

  await Future.delayed(Duration(seconds: 2));

  forceGC();

  badExample2.dispose();
}

void forceGC() {
  final objs = <Object>[];
  for (var i = 0; i < 1000000; i++) {
    objs.add(Object());
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
