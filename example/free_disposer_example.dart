import 'dart:async';
import 'dart:io';
import 'package:free_disposer/free_disposer.dart';

void main() async {
  print('Free Disposer Examples\n');

  await basicUsageExample();
  await autoCleanupExample();
  await manualCleanupExample();
  await complexScenarioExample();

  print('\nAll examples completed!');
}

/// Basic usage with DisposableMixin
Future<void> basicUsageExample() async {
  print('Example 1: Basic Usage - DisposableMixin');

  final service = MyService();

  final timer = Timer.periodic(
    Duration(seconds: 1),
    (_) => print('  Timer tick'),
  );
  final controller = StreamController<String>();
  controller.stream.listen((data) => print('  Received: $data'));

  // Attach resources to service
  timer.disposeWith(service);
  controller.disposeWith(service);

  controller.add('Hello');
  controller.add('World');

  await Future.delayed(Duration(seconds: 2));

  // Dispose all resources
  await service.dispose();
  print('  Resources disposed\n');
}

/// Auto cleanup when object is GC'd
Future<void> autoCleanupExample() async {
  print('Example 2: Auto Cleanup - GC Finalizer');

  var finalizerExecuted = false;

  void createAutoCleanupObject() {
    final object = Object();
    final timer = Timer.periodic(
      Duration(milliseconds: 500),
      (_) => print('  Auto timer tick'),
    );

    object.attachDisposer(() {
      timer.cancel();
      finalizerExecuted = true;
      print('  Finalizer executed: Timer auto-cleaned!');
    });
  }

  createAutoCleanupObject();

  await Future.delayed(Duration(seconds: 2));

  // Force GC
  await _forceGC();
  await Future.delayed(Duration(milliseconds: 500));

  if (finalizerExecuted) {
    print('  Auto cleanup successful!');
  } else {
    print('  Finalizer may not have executed yet (normal)');
  }
  print('');
}

/// Manual cleanup using AutoDisposer
Future<void> manualCleanupExample() async {
  print('Example 3: Manual Cleanup - AutoDisposer');

  final object = Object();
  final httpClient = HttpClient();
  final timer = Timer.periodic(
    Duration(seconds: 1),
    (_) => print('  HTTP timer tick'),
  );

  // Attach disposers
  object.attachDisposer(() {
    httpClient.close();
    print('  HTTP Client closed');
  });

  object.attachDisposer(() {
    timer.cancel();
    print('  Timer cancelled');
  });

  print('  Attached ${object.attachedDisposerCount} disposers');

  await Future.delayed(Duration(seconds: 2));

  // Manual dispose
  await object.disposeAttached();
  print('  Manual cleanup completed\n');
}

/// Complex scenario with multiple resource layers
Future<void> complexScenarioExample() async {
  print('Example 4: Complex Scenario - Multi-layer Resources');

  final app = MyApp();
  await app.start();

  await Future.delayed(Duration(seconds: 3));

  await app.stop();
  print('  Complex scenario completed\n');
}

class MyService with DisposableMixin {
  MyService() {
    print('  MyService created');
  }

  @override
  Future<void> dispose() async {
    print('  MyService disposing...');
    await super.dispose();
    print('  MyService disposed');
  }
}

class MyApp with DisposableMixin {
  late StreamController<String> _messageController;
  late Timer _heartbeatTimer;
  late HttpClient _httpClient;
  late StreamSubscription _messageSubscription;

  Future<void> start() async {
    print('  Starting app...');

    _messageController = StreamController<String>();
    _messageController.disposeWith(this);

    _heartbeatTimer = Timer.periodic(Duration(seconds: 1), (_) {
      _messageController.add('heartbeat');
    });
    _heartbeatTimer.disposeWith(this);

    _httpClient = HttpClient();
    _httpClient.disposeWith(this);

    _messageSubscription = _messageController.stream.listen((message) {
      print('  $message');
    });
    _messageSubscription.disposeWith(this);

    onDispose(() => print('  Custom cleanup executed'));

    print('  App started');
  }

  Future<void> stop() async {
    await dispose();
  }

  @override
  Future<void> dispose() async {
    print('  MyApp disposing...');
    await super.dispose();
    print('  MyApp disposed');
  }
}

/// Force GC for demonstration
Future<void> _forceGC() async {
  for (int i = 0; i < 1000; i++) {
    final temp = List.generate(1000, (index) => i * index);
    temp.clear();
  }

  await Future.delayed(Duration(milliseconds: 100));

  for (int i = 0; i < 500; i++) {
    final temp = List.generate(2000, (index) => i * index);
    temp.clear();
  }

  await Future.delayed(Duration(milliseconds: 200));
}
