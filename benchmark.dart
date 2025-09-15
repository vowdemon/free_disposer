import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:free_disposer/free_disposer.dart';

void main() async {
  print('Free Disposer Performance Benchmark');
  print('=====================================\n');

  await benchmarkDisposableMixin();
  await benchmarkAutoDisposer();
  await benchmarkAdapterManager();
  await benchmarkMemoryUsage();
  await benchmarkConcurrency();
  await benchmarkBottleneckAnalysis();

  print('\nBenchmark completed!');
}

Future<void> benchmarkDisposableMixin() async {
  print('📊 DisposableMixin Performance');
  print('------------------------------');

  _TestDisposable.resetCounters();

  final createdObjects = <_TestDisposable>[];
  _measureTimeSync('Create 10,000 Disposable objects', () {
    for (int i = 0; i < 10000; i++) {
      createdObjects.add(_TestDisposable());
    }
    return createdObjects.length;
  });
  print(
      '  ✓ After creation - Created: ${_TestDisposable.createdCount}, Disposed: ${_TestDisposable.disposedCount}, Alive: ${_TestDisposable.aliveCount}');

  await _measureTimeAsync('Dispose 10,000 Disposable objects', () async {
    for (final disposable in createdObjects) {
      await disposable.dispose();
    }
    return createdObjects.length;
  });
  print(
      '  ✓ After disposal - Created: ${_TestDisposable.createdCount}, Disposed: ${_TestDisposable.disposedCount}, Alive: ${_TestDisposable.aliveCount}');

  createdObjects.clear();

  await _measureTimeAsync('Add 1,000 disposers to single object', () async {
    final initialCreated = _TestDisposable.createdCount;
    final disposable = _TestDisposable();
    for (int i = 0; i < 1000; i++) {
      disposable.onDispose(() {});
    }
    await disposable.dispose();
    return _TestDisposable.createdCount - initialCreated;
  });
  print(
      '  ✓ Created: ${_TestDisposable.createdCount}, Disposed: ${_TestDisposable.disposedCount}, Alive: ${_TestDisposable.aliveCount}');

  await _measureTimeAsync('Dispose 1,000 objects with 10 disposers each',
      () async {
    final initialCreated = _TestDisposable.createdCount;
    final disposables = <_TestDisposable>[];

    for (int i = 0; i < 1000; i++) {
      final disposable = _TestDisposable();
      for (int j = 0; j < 10; j++) {
        disposable.onDispose(() {});
      }
      disposables.add(disposable);
    }

    for (final disposable in disposables) {
      await disposable.dispose();
    }

    return _TestDisposable.createdCount - initialCreated;
  });
  print(
      '  ✓ Created: ${_TestDisposable.createdCount}, Disposed: ${_TestDisposable.disposedCount}, Alive: ${_TestDisposable.aliveCount}');

  await _measureTimeAsync('Dispose with 100 async disposers', () async {
    final initialCreated = _TestDisposable.createdCount;
    final disposable = _TestDisposable();

    for (int i = 0; i < 100; i++) {
      disposable.onDispose(() async {
        await Future.delayed(Duration(microseconds: 10));
      });
    }

    await disposable.dispose();
    return _TestDisposable.createdCount - initialCreated;
  });
  print(
      '  ✓ Created: ${_TestDisposable.createdCount}, Disposed: ${_TestDisposable.disposedCount}, Alive: ${_TestDisposable.aliveCount}');

  if (_TestDisposable.aliveCount == 0) {
    print('  ✅ All DisposableMixin objects were properly disposed!');
  } else {
    print(
        '  ❌ Warning: ${_TestDisposable.aliveCount} objects were not disposed!');
  }

  print('');
}

Future<void> benchmarkAutoDisposer() async {
  print('🔄 AutoDisposer Performance');
  print('---------------------------');

  _measureTimeSync('Attach disposers to 5,000 objects', () {
    final objects = <Object>[];
    for (int i = 0; i < 5000; i++) {
      final obj = Object();
      obj.attachDisposer(() {});
      objects.add(obj);
    }
    return objects.length;
  });

  _measureTimeSync('Attach 500 disposers to single object', () {
    final obj = Object();
    for (int i = 0; i < 500; i++) {
      obj.attachDisposer(() {});
    }
    return 500;
  });

  await _measureTimeAsync('Dispose 1,000 objects with attached disposers',
      () async {
    final objects = <Object>[];

    for (int i = 0; i < 1000; i++) {
      final obj = Object();
      for (int j = 0; j < 5; j++) {
        obj.attachDisposer(() {});
      }
      objects.add(obj);
    }

    for (final obj in objects) {
      await obj.disposeAttached();
    }

    return objects.length * 5;
  });

  _measureTimeSync('Detach disposers from 2,000 objects', () {
    final objects = <Object>[];

    for (int i = 0; i < 2000; i++) {
      final obj = Object();
      obj.attachDisposer(() {});
      obj.attachDisposer(() {});
      objects.add(obj);
    }

    for (final obj in objects) {
      obj.detachDisposers();
    }

    return objects.length * 2;
  });

  print('');
}

Future<void> benchmarkAdapterManager() async {
  print('⚙️ AdapterManager Performance');
  print('-----------------------------');

  _CustomObject1.resetCounters();
  _CustomObject2.resetCounters();
  _CustomObject3.resetCounters();

  DisposerAdapterManager.register<_CustomObject1>((obj) => () => obj.dispose());
  DisposerAdapterManager.register<_CustomObject2>((obj) => () => obj.dispose());
  DisposerAdapterManager.register<_CustomObject3>((obj) => () => obj.dispose());

  await _measureTimeAsync('Get and execute disposers for 10,000 custom objects',
      () async {
    final objects = <Object>[
      for (int i = 0; i < 3333; i++) _CustomObject1(),
      for (int i = 0; i < 3333; i++) _CustomObject2(),
      for (int i = 0; i < 3334; i++) _CustomObject3(),
    ];

    var count = 0;
    for (final obj in objects) {
      final disposer = DisposerAdapterManager.getDisposer(obj);
      await disposer?.call();
      count++;
    }

    return count;
  });
  print(
      '  ✓ CustomObject1 - Created: ${_CustomObject1.createdCount}, Disposed: ${_CustomObject1.disposedCount}, Alive: ${_CustomObject1.aliveCount}');
  print(
      '  ✓ CustomObject2 - Created: ${_CustomObject2.createdCount}, Disposed: ${_CustomObject2.disposedCount}, Alive: ${_CustomObject2.aliveCount}');
  print(
      '  ✓ CustomObject3 - Created: ${_CustomObject3.createdCount}, Disposed: ${_CustomObject3.disposedCount}, Alive: ${_CustomObject3.aliveCount}');

  _measureTimeSync('Get builtin disposers for 5,000 objects', () {
    final objects = <Object>[
      for (int i = 0; i < 1000; i++) StreamController<int>(),
      for (int i = 0; i < 1000; i++) Timer(Duration(seconds: 10), () {}),
      for (int i = 0; i < 1000; i++) _TestDisposable(),
      for (int i = 0; i < 1000; i++) StreamController<String>.broadcast(),
      for (int i = 0; i < 1000; i++) StreamController<bool>().sink,
    ];

    var count = 0;
    for (final obj in objects) {
      final disposer = DisposerAdapterManager.getBuiltinDisposer(obj);
      if (disposer != null) count++;
    }

    objects.whereType<Timer>().forEach((timer) => timer.cancel());

    return count;
  });

  _measureTimeSync('Register and unregister 1,000 adapters', () {
    for (int i = 0; i < 1000; i++) {
      DisposerAdapterManager.register<Object>((obj) => () {});
    }

    DisposerAdapterManager.clear();

    return 1000;
  });

  final totalAlive = _CustomObject1.aliveCount +
      _CustomObject2.aliveCount +
      _CustomObject3.aliveCount;
  if (totalAlive == 0) {
    print('  ✅ All custom objects were properly disposed via adapters!');
  } else {
    print('  ❌ Warning: $totalAlive custom objects were not disposed!');
  }

  DisposerAdapterManager.clear();
  print('');
}

Future<void> benchmarkMemoryUsage() async {
  print('💾 Memory Usage Benchmark');
  print('-------------------------');

  final initialMemory = ProcessInfo.currentRss;
  print('Initial memory: ${_formatBytes(initialMemory)}');

  final objects = <Object>[];
  for (int i = 0; i < 10000; i++) {
    final obj = Object();
    obj.attachDisposer(() {});
    obj.attachDisposer(() async {
      await Future.delayed(Duration(microseconds: 1));
    });
    objects.add(obj);
  }

  final afterCreationMemory = ProcessInfo.currentRss;
  print(
      'After creating 10,000 objects with disposers: ${_formatBytes(afterCreationMemory)}');
  print(
      'Memory increase: ${_formatBytes(afterCreationMemory - initialMemory)}');

  for (int i = 0; i < 5000; i++) {
    await objects[i].disposeAttached();
  }

  final afterHalfDisposal = ProcessInfo.currentRss;
  print('After disposing 5,000 objects: ${_formatBytes(afterHalfDisposal)}');

  for (int i = 5000; i < 10000; i++) {
    await objects[i].disposeAttached();
  }
  objects.clear();

  // Force garbage collection
  for (int i = 0; i < 5; i++) {
    final temp = List.filled(1000000, i, growable: true);
    temp.clear();
  }

  final finalMemory = ProcessInfo.currentRss;
  print('After disposing all objects: ${_formatBytes(finalMemory)}');
  print('Final memory increase: ${_formatBytes(finalMemory - initialMemory)}');

  print('');
}

Future<void> benchmarkConcurrency() async {
  print('🚀 Concurrency Performance');
  print('--------------------------');

  await _measureTimeAsync('Concurrent disposal of 1,000 objects (10 isolates)',
      () async {
    final futures = <Future<void>>[];

    for (int isolate = 0; isolate < 10; isolate++) {
      futures.add(_concurrentDisposal(100));
    }

    await Future.wait(futures);
    return 1000;
  });

  await _measureTimeAsync(
      'Concurrent AutoDisposer operations (500 objects each isolate)',
      () async {
    final futures = <Future<void>>[];

    for (int isolate = 0; isolate < 4; isolate++) {
      futures.add(_concurrentAutoDisposer(500));
    }

    await Future.wait(futures);
    return 2000;
  });

  print('');
}

Future<void> _concurrentDisposal(int count) async {
  final disposables = <_TestDisposable>[];

  for (int i = 0; i < count; i++) {
    final disposable = _TestDisposable();
    for (int j = 0; j < 5; j++) {
      disposable.onDispose(() async {
        await Future.delayed(Duration(microseconds: Random().nextInt(100)));
      });
    }
    disposables.add(disposable);
  }

  final disposeFutures = <Future<void>>[];
  for (final disposable in disposables) {
    final result = disposable.dispose();
    if (result is Future<void>) {
      disposeFutures.add(result);
    }
  }
  await Future.wait(disposeFutures);
}

Future<void> _concurrentAutoDisposer(int count) async {
  final objects = <Object>[];

  for (int i = 0; i < count; i++) {
    final obj = Object();
    for (int j = 0; j < 3; j++) {
      obj.attachDisposer(() async {
        await Future.delayed(Duration(microseconds: Random().nextInt(50)));
      });
    }
    objects.add(obj);
  }

  final disposeFutures = <Future<void>>[];
  for (final obj in objects) {
    final result = obj.disposeAttached();
    if (result is Future<void>) {
      disposeFutures.add(result);
    }
  }
  if (disposeFutures.isNotEmpty) {
    await Future.wait(disposeFutures);
  }
}

Future<void> benchmarkBottleneckAnalysis() async {
  print('🔍 Bottleneck Analysis');
  print('---------------------');

  print('1. Single Object with Many Disposers:');
  for (final count in [100, 500, 1000, 5000, 10000]) {
    await _measureTimeAsync('  $count disposers on single object', () async {
      final disposable = _TestDisposable();
      for (int i = 0; i < count; i++) {
        disposable.onDispose(() {});
      }
      await disposable.dispose();
      return count;
    });
  }

  print('\n1.5. Async Disposer Bottleneck Analysis:');

  for (final count in [10, 50, 100, 200, 500]) {
    await _measureTimeAsync('  $count async disposers (10μs each)', () async {
      final disposable = _TestDisposable();
      for (int i = 0; i < count; i++) {
        disposable.onDispose(() async {
          await Future.delayed(Duration(microseconds: 10));
        });
      }
      await disposable.dispose();
      return count;
    });
  }

  print('  Testing different delay times:');
  for (final delayMicros in [1, 5, 10, 50, 100]) {
    await _measureTimeAsync('    100 async disposers (${delayMicros}μs each)',
        () async {
      final disposable = _TestDisposable();
      for (int i = 0; i < 100; i++) {
        disposable.onDispose(() async {
          await Future.delayed(Duration(microseconds: delayMicros));
        });
      }
      await disposable.dispose();
      return 100;
    });
  }

  await _measureTimeAsync('  100 pure async disposers (no delay)', () async {
    final disposable = _TestDisposable();
    for (int i = 0; i < 100; i++) {
      disposable.onDispose(() async {});
    }
    await disposable.dispose();
    return 100;
  });

  print('\n2. Adapter Lookup Performance:');
  DisposerAdapterManager.clear();

  final testCounts = [1, 5, 10, 50, 100];
  for (final adapterCount in testCounts) {
    DisposerAdapterManager.clear();
    for (int i = 0; i < adapterCount; i++) {
      DisposerAdapterManager.register<Object>((obj) => () {});
    }

    _measureTimeSync('  Lookup with $adapterCount adapters (1000 calls)', () {
      final obj = Object();
      var foundCount = 0;
      for (int i = 0; i < 1000; i++) {
        final disposer = DisposerAdapterManager.getDisposer(obj);
        if (disposer != null) foundCount++;
      }
      return 1000;
    });
  }

  print('\n3. Builtin Type Recognition:');
  final builtinObjects = [
    _TestDisposable(),
    StreamController<int>(),
    Timer(Duration(seconds: 10), () {}),
    StreamController<String>.broadcast(),
  ];

  _measureTimeSync('  Builtin type recognition (10000 calls)', () {
    var count = 0;
    for (int i = 0; i < 10000; i++) {
      for (final obj in builtinObjects) {
        final disposer = DisposerAdapterManager.getBuiltinDisposer(obj);
        if (disposer != null) count++;
      }
    }
    builtinObjects.whereType<Timer>().forEach((t) => t.cancel());
    return count;
  });

  print('\n4. Finalizer Operations:');
  _measureTimeSync('  Attach finalizers (10000 objects)', () {
    final objects = <Object>[];
    for (int i = 0; i < 10000; i++) {
      final obj = Object();
      obj.attachDisposer(() {});
      objects.add(obj);
    }
    return objects.length;
  });

  await _measureTimeAsync('  Batch finalizer processing (10000 objects)',
      () async {
    final objects = <Object>[];
    for (int i = 0; i < 10000; i++) {
      final obj = Object();
      obj.attachDisposer(() {});
      objects.add(obj);
    }
    await Future.microtask(() {});
    return objects.length;
  });

  print('  Comparing single vs batch operations:');

  _measureTimeSync('    Single attach operations (1000 objects)', () {
    final objects = <Object>[];
    for (int i = 0; i < 1000; i++) {
      final obj = Object();
      obj.attachDisposer(() {});
      AutoDisposer.flushPendingAttachments();
      objects.add(obj);
    }
    return objects.length;
  });

  _measureTimeSync('    Batch attach operations (1000 objects)', () {
    final objects = <Object>[];
    for (int i = 0; i < 1000; i++) {
      final obj = Object();
      obj.attachDisposer(() {});
      objects.add(obj);
    }
    AutoDisposer.flushPendingAttachments();
    return objects.length;
  });

  print('\n5. Async vs Sync Disposers:');

  await _measureTimeAsync('  1000 sync disposers', () async {
    final disposable = _TestDisposable();
    for (int i = 0; i < 1000; i++) {
      disposable.onDispose(() {});
    }
    await disposable.dispose();
    return 1000;
  });

  await _measureTimeAsync('  1000 async disposers (no delay)', () async {
    final disposable = _TestDisposable();
    for (int i = 0; i < 1000; i++) {
      disposable.onDispose(() async {});
    }
    await disposable.dispose();
    return 1000;
  });

  print('\n6. Memory Allocation Overhead:');
  _measureTimeSync('  Create 10000 empty Sets', () {
    final sets = <Set<Function>>[];
    for (int i = 0; i < 10000; i++) {
      sets.add(<Function>{});
    }
    return sets.length;
  });

  _measureTimeSync('  Create 10000 empty Lists', () {
    final lists = <List<Function>>[];
    for (int i = 0; i < 10000; i++) {
      lists.add(<Function>[]);
    }
    return lists.length;
  });

  DisposerAdapterManager.clear();
  print('');
}

Future<T> _measureTimeAsync<T>(
    String description, Future<T> Function() operation) async {
  final stopwatch = Stopwatch()..start();
  final result = await operation();
  stopwatch.stop();

  final duration = stopwatch.elapsedMilliseconds;
  String rate;

  if (result is int) {
    if (duration == 0) {
      rate = 'Infinity';
    } else {
      final opsPerSec = (result / (duration / 1000)).round();
      rate = '$opsPerSec';
    }
  } else {
    rate = 'N/A';
  }

  print('$description: ${duration}ms ($rate ops/sec)');
  return result;
}

T _measureTimeSync<T>(String description, T Function() operation) {
  final stopwatch = Stopwatch()..start();
  final result = operation();
  stopwatch.stop();

  final duration = stopwatch.elapsedMilliseconds;
  String rate;

  if (result is int) {
    if (duration == 0) {
      rate = 'Infinity';
    } else {
      final opsPerSec = (result / (duration / 1000)).round();
      rate = '$opsPerSec';
    }
  } else {
    rate = 'N/A';
  }

  print('$description: ${duration}ms ($rate ops/sec)');
  return result;
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '${bytes}B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
  if (bytes < 1024 * 1024 * 1024)
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
}

// Test classes
class _TestDisposable with DisposableMixin {
  static int _createdCount = 0;
  static int _disposedCount = 0;

  static int get createdCount => _createdCount;
  static int get disposedCount => _disposedCount;
  static int get aliveCount => _createdCount - _disposedCount;

  static void resetCounters() {
    _createdCount = 0;
    _disposedCount = 0;
  }

  _TestDisposable() {
    _createdCount++;
    onDispose(() {
      _disposedCount++;
    });
  }
}

class _CustomObject1 {
  static int _createdCount = 0;
  static int _disposedCount = 0;

  static int get createdCount => _createdCount;
  static int get disposedCount => _disposedCount;
  static int get aliveCount => _createdCount - _disposedCount;

  static void resetCounters() {
    _createdCount = 0;
    _disposedCount = 0;
  }

  _CustomObject1() {
    _createdCount++;
  }

  void dispose() {
    _disposedCount++;
  }
}

class _CustomObject2 {
  static int _createdCount = 0;
  static int _disposedCount = 0;

  static int get createdCount => _createdCount;
  static int get disposedCount => _disposedCount;
  static int get aliveCount => _createdCount - _disposedCount;

  static void resetCounters() {
    _createdCount = 0;
    _disposedCount = 0;
  }

  _CustomObject2() {
    _createdCount++;
  }

  void dispose() {
    _disposedCount++;
  }
}

class _CustomObject3 {
  static int _createdCount = 0;
  static int _disposedCount = 0;

  static int get createdCount => _createdCount;
  static int get disposedCount => _disposedCount;
  static int get aliveCount => _createdCount - _disposedCount;

  static void resetCounters() {
    _createdCount = 0;
    _disposedCount = 0;
  }

  _CustomObject3() {
    _createdCount++;
  }

  void dispose() {
    _disposedCount++;
  }
}
