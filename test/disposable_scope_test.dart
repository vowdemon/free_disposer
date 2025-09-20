import 'dart:async';

import 'package:free_disposer/free_disposer.dart';
import 'package:test/test.dart';

class TestDisposable with DisposableMixin {}

void main() {
  group('ResourceScope Basic Functionality', () {
    test('should create empty scope', () {
      final scope = DisposableScope();
      expect(scope.isDisposed, false);
      scope.dispose();
      expect(scope.isDisposed, true);
    });

    test('should register and dispose resources', () async {
      final scope = DisposableScope();
      final resource = TestDisposable();

      final disposer = scope.register(resource);
      expect(resource.isDisposed, false);

      await scope.dispose();
      expect(scope.isDisposed, true);
      expect(resource.isDisposed, true);
    });

    test('should work with run method', () async {
      late TestDisposable disposable;
      final scope = DisposableScope();

      final x = scope.run(() {
        expect(DisposableScope.currentScope, scope);
        disposable = TestDisposable();
        DisposableScope.currentScope?.register(disposable);
        return TestDisposable();
      });

      expect(x == disposable, isFalse);
      expect(x, isA<TestDisposable>());
      expect(x == disposable, isFalse);

      expect(DisposableScope.currentScope, null);
      expect(disposable.isDisposed, false);

      await scope.dispose();

      expect(disposable.isDisposed, true);
      expect(scope.isDisposed, true);
    });

    test('should handle async resource registration', () async {
      final scope = DisposableScope();

      final a = TestDisposable();
      final b = TestDisposable();
      final x = scope.registerAsync(Future.value(a));
      expect(x, isA<Future<Disposer>>());

      final y = scope.register(b);
      expect(y, isA<Disposer>());

      await Future.microtask(() {});

      await scope.dispose();

      expect(scope.isDisposed, true);
      expect(a.isDisposed, true);
      expect(b.isDisposed, true);
    });
  });

  group('Nested ResourceScope', () {
    test('should work with nested scopes', () async {
      final parentScope = DisposableScope();
      final childScope = DisposableScope();

      final parentResource = TestDisposable();
      final childResource = TestDisposable();

      parentScope.register(parentResource);
      childScope.register(childResource);

      // Dispose child first
      await childScope.dispose();
      expect(childScope.isDisposed, true);
      expect(childResource.isDisposed, true);
      expect(parentScope.isDisposed, false);
      expect(parentResource.isDisposed, false);

      // Then dispose parent
      await parentScope.dispose();
      expect(parentScope.isDisposed, true);
      expect(parentResource.isDisposed, true);
    });

    test('should handle scope within run method', () async {
      final outerScope = DisposableScope();
      late DisposableScope innerScope;
      late TestDisposable outerResource;
      late TestDisposable innerResource;

      final result = outerScope.run(() {
        expect(DisposableScope.currentScope, outerScope);
        outerResource = TestDisposable();
        outerScope.register(outerResource);
        innerScope = DisposableScope();
        expect(innerScope.zone.parent, DisposableScope.currentScope?.zone);

        return innerScope.run(() {
          expect(DisposableScope.currentScope, innerScope);

          innerResource = TestDisposable();
          innerScope.register(innerResource);
          return 'test';
        });
      });

      expect(result, 'test');
      expect(DisposableScope.currentScope, null);

      await innerScope.dispose();
      expect(innerResource.isDisposed, true);
      expect(outerResource.isDisposed, false);

      await outerScope.dispose();
      expect(outerResource.isDisposed, true);
    });
  });

  group('Zone Integration', () {
    test('should maintain current scope in zone', () async {
      final scope = DisposableScope();
      DisposableScope? capturedScope;

      final result = scope.run(() {
        capturedScope = DisposableScope.currentScope;
        return 'test';
      });

      expect(result, 'test');
      expect(capturedScope, scope);
      expect(DisposableScope.currentScope, null);
    });

    test('should work with custom zone', () {
      final customZone = Zone.current.fork();
      final scope = DisposableScope(parent: customZone);

      expect(scope.zone, isNot(Zone.current));
      expect(scope.zone, isA<Zone>());
    });
  });

  group('Error Handling', () {
    test('should handle disposal errors gracefully', () async {
      final scope = DisposableScope();
      bool errorHandled = false;

      runZoned(() {
        scope.register(TestDisposable());
      }, onError: (error, stackTrace) {
        errorHandled = true;
      });

      await scope.dispose();
      expect(scope.isDisposed, true);
    });

    test('should handle async registration after disposal', () async {
      final scope = DisposableScope();
      final resource = TestDisposable();

      await scope.dispose();
      expect(scope.isDisposed, true);

      final disposer = await scope.registerAsync(Future.value(resource));
      expect(disposer, isA<Disposer>());

      // Resource should be disposed immediately since scope is already disposed
      expect(resource.isDisposed, true);
    });
  });

  group('Resource Management', () {
    test('should handle multiple resource types', () async {
      final scope = DisposableScope();
      final timer = Timer.periodic(Duration(seconds: 1), (_) {});
      final controller = StreamController<int>();
      final subscription = controller.stream.listen((_) {});

      scope.register(timer);
      scope.register(controller);
      scope.register(subscription);

      await scope.dispose();

      expect(timer.isActive, false);
      expect(controller.isClosed, true);
      expect(subscription.isPaused, false); // Subscription should be cancelled
    });

    test('should handle weak references correctly', () async {
      final scope = DisposableScope();
      TestDisposable? resource;

      // Create and register resource
      resource = TestDisposable();
      scope.register(resource);

      // Clear reference to allow GC
      resource = null;

      // Force garbage collection (this is a best-effort operation)
      await Future.delayed(Duration(milliseconds: 10));

      await scope.dispose();
    });

    test('should handle disposal order', () async {
      final scope = DisposableScope();
      final disposedOrder = <String>[];

      final resource1 = TestDisposable();
      final resource2 = TestDisposable();

      // Add custom disposers to track order
      resource1.disposeWith(() => disposedOrder.add('resource1'));
      resource2.disposeWith(() => disposedOrder.add('resource2'));

      scope.register(resource1);
      scope.register(resource2);

      await scope.dispose();

      // Both should be disposed
      expect(resource1.isDisposed, true);
      expect(resource2.isDisposed, true);
      expect(disposedOrder.length, 2);
    });
  });

  group('Edge Cases', () {
    test('should handle null resources', () {
      final scope = DisposableScope();
      expect(() => scope.register(null as Object), throwsA(isA<TypeError>()));
    });

    test('should handle multiple dispose calls', () async {
      final scope = DisposableScope();
      final resource = TestDisposable();
      scope.register(resource);

      await scope.dispose();
      expect(scope.isDisposed, true);
      expect(resource.isDisposed, true);

      // Second dispose should be safe
      await scope.dispose();
      expect(scope.isDisposed, true);
      expect(resource.isDisposed, true);
    });

    test('should handle empty scope disposal', () async {
      final scope = DisposableScope();

      await scope.dispose();
      expect(scope.isDisposed, true);
    });
  });

  group('Performance and Concurrency', () {
    test('should handle concurrent registrations', () async {
      final scope = DisposableScope();
      final futures = <Future>[];

      // Register multiple resources concurrently
      for (int i = 0; i < 10; i++) {
        futures.add(Future(() {
          final resource = TestDisposable();
          scope.register(resource);
          return resource;
        }));
      }

      final resources = await Future.wait(futures);

      await scope.dispose();

      for (final resource in resources) {
        expect(resource.isDisposed, true);
      }
    });

    test('should handle mixed sync and async disposers', () async {
      final scope = DisposableScope();
      final syncResource = TestDisposable();
      final asyncResource = TestDisposable();

      // Add async disposer
      syncResource.disposeWith(() async {
        await Future.delayed(Duration(milliseconds: 1));
      });

      scope.register(syncResource);
      scope.register(asyncResource);

      final stopwatch = Stopwatch()..start();
      await scope.dispose();
      stopwatch.stop();

      expect(syncResource.isDisposed, true);
      expect(asyncResource.isDisposed, true);
      expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(1));
    });
  });
}
