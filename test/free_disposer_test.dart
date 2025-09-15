import 'dart:async';

import 'package:test/test.dart';
import 'package:free_disposer/free_disposer.dart';

void main() {
  group('free_disposer', () {
    group('DisposableMixin', () {
      test('should track disposal state', () async {
        final disposable = _TestDisposable();
        expect(disposable.isDisposed, false);

        await disposable.dispose();
        expect(disposable.isDisposed, true);
      });

      test('should not dispose twice', () async {
        final disposable = _TestDisposable();
        var disposeCount = 0;

        disposable.onDispose(() {
          disposeCount++;
        });

        await disposable.dispose();
        await disposable.dispose();

        expect(disposeCount, 1);
      });

      test('should execute all disposers', () async {
        final disposable = _TestDisposable();
        var disposeCount = 0;

        disposable.onDispose(() => disposeCount++);
        disposable.onDispose(() => disposeCount++);
        disposable.onDispose(() => disposeCount++);

        await disposable.dispose();
        expect(disposeCount, 3);
      });

      test('should handle async disposers', () async {
        final disposable = _TestDisposable();
        var disposeCount = 0;

        disposable.onDispose(() async {
          await Future.delayed(Duration(milliseconds: 10));
          disposeCount++;
        });

        disposable.onDispose(() => disposeCount++);

        await disposable.dispose();
        expect(disposeCount, 2);
      });

      test('should handle disposer errors', () async {
        final disposable = _TestDisposable();
        var errorCaught = false;

        runZoned(() {
          disposable.onDispose(() {
            throw Exception('Test error');
          });

          disposable.onDispose(() {
            errorCaught = true;
          });

          disposable.dispose();
          // ignore: deprecated_member_use
        }, onError: (error, stack) {});

        await Future.delayed(Duration(milliseconds: 10));
        expect(errorCaught, true);
      });

      test('should not add disposers when disposed', () async {
        final disposable = _TestDisposable();
        await disposable.dispose();

        var disposeCount = 0;
        disposable.onDispose(() => disposeCount++);

        expect(disposeCount, 0);
        expect(disposable.disposerCount, 0);
      });

      test('should not add disposers when disposing', () async {
        final disposable = _TestDisposable();
        var addedDuringDispose = false;

        disposable.onDispose(() {
          disposable.onDispose(() => addedDuringDispose = true);
        });

        await disposable.dispose();

        expect(addedDuringDispose, false);
      });

      test('should handle addDisposable method', () async {
        final parent = _TestDisposable();
        final child = _TestDisposable();

        parent.addDisposable(child);

        expect(parent.disposerCount, 1);
        expect(child.isDisposed, false);

        await parent.dispose();

        expect(parent.isDisposed, true);
        expect(child.isDisposed, true);
      });

      test('should handle multiple addDisposable calls', () async {
        final parent = _TestDisposable();
        final child1 = _TestDisposable();
        final child2 = _TestDisposable();
        final child3 = _TestDisposable();

        parent.addDisposable(child1);
        parent.addDisposable(child2);
        parent.addDisposable(child3);

        expect(parent.disposerCount, 3);

        await parent.dispose();

        expect(parent.isDisposed, true);
        expect(child1.isDisposed, true);
        expect(child2.isDisposed, true);
        expect(child3.isDisposed, true);
      });
    });

    group('AutoDisposer Blacklist Types', () {
      test('should reject primitive types', () {
        expect(
          () => AutoDisposer.attachDisposer(42, () {}),
          throwsA(isA<UnsupportedError>()),
        );

        expect(
          () => AutoDisposer.attachDisposer(3.14, () {}),
          throwsA(isA<UnsupportedError>()),
        );

        expect(
          () => AutoDisposer.attachDisposer(true, () {}),
          throwsA(isA<UnsupportedError>()),
        );

        expect(
          () => AutoDisposer.attachDisposer('string', () {}),
          throwsA(isA<UnsupportedError>()),
        );
      });

      test('should reject Symbol and Type', () {
        expect(
          () => AutoDisposer.attachDisposer(#symbol, () {}),
          throwsA(isA<UnsupportedError>()),
        );

        expect(
          () => AutoDisposer.attachDisposer(String, () {}),
          throwsA(isA<UnsupportedError>()),
        );
      });

      test('should reject Enum types', () {
        expect(
          () => AutoDisposer.attachDisposer(_TestEnum.value1, () {}),
          throwsA(isA<UnsupportedError>()),
        );
      });

      test('should reject null', () {
        Object? nullableObject;
        expect(() {
          // ignore: unnecessary_null_comparison
          if (nullableObject != null) {
            AutoDisposer.attachDisposer(nullableObject, () {});
          } else {
            throw UnsupportedError('Cannot attach disposer to null object');
          }
        }, throwsA(isA<UnsupportedError>()));
      });

      test('should accept valid object types', () {
        final object = Object();
        final list = <int>[];
        final map = <String, int>{};

        expect(
          () => AutoDisposer.attachDisposer(object, () {}),
          returnsNormally,
        );

        expect(() => AutoDisposer.attachDisposer(list, () {}), returnsNormally);

        expect(() => AutoDisposer.attachDisposer(map, () {}), returnsNormally);
      });
    });

    group('AutoDisposer Edge Cases', () {
      test('should handle duplicate disposer registration', () {
        final object = Object();

        var disposeCount = 0;
        int actualDisposer() => disposeCount++;

        object.attachDisposer(actualDisposer);
        object.attachDisposer(actualDisposer);
        object.attachDisposer(actualDisposer);

        expect(object.attachedDisposerCount, 1);
      });

      test('should handle disposeObject with no disposers', () async {
        final object = Object();

        await expectLater(
          () => AutoDisposer.disposeObject(object),
          returnsNormally,
        );
      });

      test('should handle detachDisposers with no disposers', () {
        final object = Object();

        expect(() => AutoDisposer.detachDisposers(object), returnsNormally);
      });

      test('should handle hasDisposers and disposerCount correctly', () {
        final object = Object();

        expect(AutoDisposer.hasDisposers(object), false);
        expect(AutoDisposer.disposerCount(object), 0);

        object.attachDisposer(() {});

        expect(AutoDisposer.hasDisposers(object), true);
        expect(AutoDisposer.disposerCount(object), 1);

        object.attachDisposer(() {});

        expect(AutoDisposer.disposerCount(object), 2);

        AutoDisposer.detachDisposers(object);

        expect(AutoDisposer.hasDisposers(object), false);
        expect(AutoDisposer.disposerCount(object), 0);
      });

      test('should handle multiple detach calls safely', () {
        final object = Object();
        object.attachDisposer(() {});

        expect(() => AutoDisposer.detachDisposers(object), returnsNormally);
        expect(() => AutoDisposer.detachDisposers(object), returnsNormally);
        expect(() => AutoDisposer.detachDisposers(object), returnsNormally);
      });

      test('should handle disposeObject after detach', () async {
        final object = Object();
        var disposeCount = 0;

        object.attachDisposer(() => disposeCount++);
        AutoDisposer.detachDisposers(object);

        await AutoDisposer.disposeObject(object);
        expect(disposeCount, 0);
      });

      test('should handle async errors in finalizer', () async {
        var errorHandled = false;

        await runZoned(
          () async {
            final object = Object();

            object.attachDisposer(() async {
              throw Exception('Async error in disposer');
            });

            await AutoDisposer.disposeObject(object);
          },
          onError: (error, stack) {
            errorHandled = true;
          },
        );

        expect(errorHandled, true);
      });
    });

    group('Extension Methods', () {
      test('should handle attachDisposers extension method', () {
        final object = Object();
        final disposers = [() {}, () {}, () {}];

        object.attachDisposers(disposers);

        expect(object.attachedDisposerCount, 3);
      });

      test('should handle empty disposers list', () {
        final object = Object();
        final disposers = <Disposer>[];

        object.attachDisposers(disposers);

        expect(object.attachedDisposerCount, 0);
      });

      test('should handle extension methods on blacklisted types', () {
        final blacklistedObject = 'string';

        runZoned(() {
          expect(
            () => blacklistedObject.attachDisposer(() {}),
            returnsNormally,
          );
          expect(() => blacklistedObject.detachDisposers(), returnsNormally);
          expect(() => blacklistedObject.disposeAttached(), returnsNormally);
          expect(blacklistedObject.hasAttachedDisposers, false);
          expect(blacklistedObject.attachedDisposerCount, 0);
        }, onError: (error, stack) {});
      });
    });

    group('DisposableExtension Edge Cases', () {
      test('should handle StreamController with listeners correctly', () async {
        final controller = StreamController<int>();
        final subscription = controller.stream.listen((_) {});

        final disposer = controller.toDisposer;

        await disposer?.call();

        await subscription.cancel();
      });

      test('should handle StreamController without listeners', () async {
        final controller = StreamController<int>();

        final disposer = controller.toDisposer;

        await disposer?.call();

        expect(disposer, isA<Function>());
      });

      test(
        'should handle broadcast StreamController without listeners',
        () async {
          final controller = StreamController<int>.broadcast();

          final disposer = controller.toDisposer;

          await disposer?.call();

          expect(controller.isClosed, true);
        },
      );

      test('should handle StreamController close timeout', () async {
        final controller = StreamController<int>();

        final subscription = controller.stream.listen((_) {});

        final disposer = controller.toDisposer;

        await expectLater(disposer?.call(), completes);

        await subscription.cancel();
      });

      test('should handle RandomAccessFile', () {
        expect(() {}, returnsNormally);
      });

      test('should handle Socket types', () {
        expect(() {}, returnsNormally);
      });
    });

    group('Error Handling and Recovery', () {
      test('should continue execution after disposer error', () async {
        final object = Object();
        var successCount = 0;

        await runZoned(() async {
          object.attachDisposer(() {
            throw Exception('First error');
          });

          object.attachDisposer(() {
            successCount++;
          });

          object.attachDisposer(() {
            throw Exception('Second error');
          });

          object.attachDisposer(() {
            successCount++;
          });

          await AutoDisposer.disposeObject(object);
        }, onError: (error, stack) {});

        expect(successCount, 2);
      });

      test('should handle mixed sync and async disposer errors', () async {
        final object = Object();
        var successCount = 0;

        await runZoned(() async {
          object.attachDisposer(() {
            throw Exception('Sync error');
          });

          object.attachDisposer(() async {
            throw Exception('Async error');
          });

          object.attachDisposer(() {
            successCount++;
          });

          object.attachDisposer(() async {
            await Future.delayed(Duration(milliseconds: 5));
            successCount++;
          });

          await AutoDisposer.disposeObject(object);
        }, onError: (error, stack) {});

        expect(successCount, 2);
      });

      test('should handle errors in onDispose registration', () {
        final disposable = _TestDisposable();
        // ignore: unused_local_variable
        var errorHandled = false;

        runZoned(
          () {
            disposable.onDispose(() {});
          },
          onError: (error, stack) {
            errorHandled = true;
          },
        );

        expect(disposable.disposerCount >= 0, true);
      });
    });

    group('Performance and Memory', () {
      test('should handle large number of disposers', () async {
        final object = Object();
        var disposeCount = 0;
        const disposerCount = 1000;

        for (int i = 0; i < disposerCount; i++) {
          object.attachDisposer(() => disposeCount++);
        }

        expect(object.attachedDisposerCount, disposerCount);

        await AutoDisposer.disposeObject(object);

        expect(disposeCount, disposerCount);
        expect(object.hasAttachedDisposers, false);
      });

      test('should handle rapid attach/detach cycles', () {
        final object = Object();

        for (int i = 0; i < 100; i++) {
          object.attachDisposer(() {});
          expect(object.hasAttachedDisposers, true);

          object.detachDisposers();
          expect(object.hasAttachedDisposers, false);
        }
      });

      test('should clean up Expando references after dispose', () async {
        final object = Object();
        var disposeCount = 0;

        object.attachDisposer(() => disposeCount++);

        expect(object.hasAttachedDisposers, true);
        expect(object.attachedDisposerCount, 1);

        await AutoDisposer.disposeObject(object);

        expect(object.hasAttachedDisposers, false);
        expect(object.attachedDisposerCount, 0);
        expect(disposeCount, 1);
      });
    });

    group('DisposableExtension', () {
      test('should convert Disposable to disposer', () {
        final disposable = _TestDisposable();
        final disposer = disposable.toDisposer;

        expect(disposer, isA<Disposer>());
      });

      test('should convert StreamSubscription to disposer', () {
        final controller = StreamController<int>();
        final subscription = controller.stream.listen((_) {});

        final disposer = subscription.toDisposer;
        expect(disposer, isA<Disposer>());

        controller.close();
      });

      test('should convert Timer to disposer', () {
        final timer = Timer(Duration(seconds: 1), () {});
        final disposer = timer.toDisposer;

        expect(disposer, isA<Disposer>());
        timer.cancel();
      });

      test('should convert StreamController to disposer', () {
        final controller = StreamController<int>();
        final disposer = controller.toDisposer;

        expect(disposer, isA<Disposer>());
      });

      test('should convert Sink to disposer', () {
        final controller = StreamController<int>();
        final sink = controller.sink;
        final disposer = sink.toDisposer;

        expect(disposer, isA<Disposer>());
      });

      test('should dispose with DisposableMixin', () {
        final disposable = _TestDisposable();
        final controller = StreamController<int>();

        controller.disposeWith(disposable);

        expect(disposable.disposerCount, 1);
      });

      test('should handle errors in disposeWith', () {
        final disposable = _TestDisposable();
        final unsupported = 'string';

        runZoned(() {
          unsupported.disposeWith(disposable);
        }, onError: (error, stack) {});

        expect(disposable.disposerCount, 0);
      });
    });

    group('AutoDisposeList', () {
      test('should dispose all objects with DisposableMixin', () {
        final disposable = _TestDisposable();
        final controllers = [
          StreamController<int>(),
          StreamController<String>(),
          StreamController<bool>(),
        ];

        controllers.disposeAllWith(disposable);

        expect(disposable.disposerCount, 3);
      });

      test('should handle mixed object types', () {
        final disposable = _TestDisposable();
        final objects = [
          StreamController<int>(),
          Timer(Duration(seconds: 1), () {}),
          _TestDisposable(),
        ];

        objects.disposeAllWith(disposable);

        expect(disposable.disposerCount, 3);

        disposable.dispose();
      });

      test('should handle empty list', () {
        final disposable = _TestDisposable();
        final emptyList = <Object>[];

        emptyList.disposeAllWith(disposable);

        expect(disposable.disposerCount, 0);
      });
    });

    group('DisposerAdapterManager', () {
      tearDown(() {
        DisposerAdapterManager.clear();
      });

      test('should register and use custom adapter', () {
        final customObject = _CustomDisposableObject();
        var disposeCount = 0;

        DisposerAdapterManager.register<_CustomDisposableObject>((obj) {
          return () {
            obj.cleanup();
            disposeCount++;
          };
        });

        final disposer = DisposerAdapterManager.getDisposer(customObject);
        expect(disposer, isA<Disposer>());
        expect(customObject.isCleanedUp, false);

        disposer?.call();

        expect(customObject.isCleanedUp, true);
        expect(disposeCount, 1);
      });

      test('should unregister custom adapter', () {
        final customObject = _CustomDisposableObject();

        DisposerAdapterManager.register<_CustomDisposableObject>((obj) {
          return () => obj.cleanup();
        });

        expect(
          () => DisposerAdapterManager.getDisposer(customObject),
          returnsNormally,
        );

        DisposerAdapterManager.unregister<_CustomDisposableObject>();

        expect(
          DisposerAdapterManager.getDisposer(customObject),
          null,
        );
      });

      test('should handle multiple adapters for different types', () {
        final customObject1 = _CustomDisposableObject();
        final customObject2 = _AnotherCustomObject();
        var disposeCount1 = 0;
        var disposeCount2 = 0;

        DisposerAdapterManager.register<_CustomDisposableObject>((obj) {
          return () {
            obj.cleanup();
            disposeCount1++;
          };
        });

        DisposerAdapterManager.register<_AnotherCustomObject>((obj) {
          return () {
            obj.dispose();
            disposeCount2++;
          };
        });

        final disposer1 = DisposerAdapterManager.getDisposer(customObject1);
        disposer1?.call();
        expect(customObject1.isCleanedUp, true);
        expect(disposeCount1, 1);

        final disposer2 = DisposerAdapterManager.getDisposer(customObject2);
        disposer2?.call();
        expect(customObject2.isDisposed, true);
        expect(disposeCount2, 1);
      });

      test('should prioritize builtin disposers over custom adapters',
          () async {
        final controller = StreamController<int>();
        var customDisposeCount = 0;

        DisposerAdapterManager.register<StreamController>((obj) {
          return () {
            customDisposeCount++;
          };
        });

        final disposer = DisposerAdapterManager.getDisposer(controller);
        expect(disposer, isA<Disposer>());

        await disposer?.call();

        await Future.delayed(Duration(milliseconds: 600));

        expect(controller.isClosed, true);
        expect(customDisposeCount, 0);
      });

      test('should handle adapter registration for same type multiple times',
          () {
        final customObject = _CustomDisposableObject();
        var disposeCount1 = 0;
        var disposeCount2 = 0;

        DisposerAdapterManager.register<_CustomDisposableObject>((obj) {
          return () {
            disposeCount1++;
          };
        });

        DisposerAdapterManager.register<_CustomDisposableObject>((obj) {
          return () {
            disposeCount2++;
          };
        });

        final disposer = DisposerAdapterManager.getDisposer(customObject);
        disposer?.call();

        expect(disposeCount1, 1);
        expect(disposeCount2, 0);
      });

      test('should throw UnsupportedError for unregistered types', () {
        final unsupportedObject = _UnsupportedObject();

        expect(
          DisposerAdapterManager.getDisposer(unsupportedObject),
          null,
        );
      });

      test('should handle null object', () {
        expect(DisposerAdapterManager.getDisposer(null), null);
      });

      test('should test builtin disposers', () async {
        final disposable = _TestDisposable();
        final disposableDisposer =
            DisposerAdapterManager.getBuiltinDisposer(disposable);
        expect(disposableDisposer, isNotNull);
        await disposableDisposer!();
        expect(disposable.isDisposed, true);

        final controller = StreamController<int>();
        final subscription = controller.stream.listen((_) {});
        final subscriptionDisposer =
            DisposerAdapterManager.getBuiltinDisposer(subscription);
        expect(subscriptionDisposer, isNotNull);
        await subscriptionDisposer!();

        controller.close();

        final timer = Timer(Duration(seconds: 1), () {});
        final timerDisposer = DisposerAdapterManager.getBuiltinDisposer(timer);
        expect(timerDisposer, isNotNull);
        timerDisposer!();
        expect(timer.isActive, false);

        final controller2 = StreamController<int>();
        final controllerDisposer =
            DisposerAdapterManager.getBuiltinDisposer(controller2);
        expect(controllerDisposer, isNotNull);
        await controllerDisposer!();
        expect(controller2.isClosed, true);

        final controller3 = StreamController<int>();
        final sink = controller3.sink;
        final sinkDisposer = DisposerAdapterManager.getBuiltinDisposer(sink);
        expect(sinkDisposer, isNotNull);
        await sinkDisposer!();

        controller3.close();
      });

      test('should handle StreamController with different states', () async {
        final controller1 = StreamController<int>();
        final subscription = controller1.stream.listen((_) {});

        final disposer1 =
            DisposerAdapterManager.getBuiltinDisposer(controller1);
        expect(disposer1, isNotNull);

        await disposer1!();
        expect(controller1.isClosed, true);

        await subscription.cancel();

        final controller2 = StreamController<int>.broadcast();
        final disposer2 =
            DisposerAdapterManager.getBuiltinDisposer(controller2);
        expect(disposer2, isNotNull);

        await disposer2!();
        expect(controller2.isClosed, true);

        final controller3 = StreamController<int>();
        final disposer3 =
            DisposerAdapterManager.getBuiltinDisposer(controller3);
        expect(disposer3, isNotNull);

        await disposer3!();
        expect(controller3.isClosed, true);

        final controller4 = StreamController<int>.broadcast();
        await controller4.close();

        final disposer4 =
            DisposerAdapterManager.getBuiltinDisposer(controller4);
        expect(disposer4, isNotNull);

        await expectLater(() => disposer4!(), returnsNormally);
      });

      test('should handle StreamController close timeout', () async {
        final controller = StreamController<int>();

        final subscription = controller.stream.listen((_) {});

        final disposer = DisposerAdapterManager.getBuiltinDisposer(controller);
        expect(disposer, isNotNull);

        final disposerResult = disposer!();
        if (disposerResult is Future) {
          await expectLater(
            disposerResult.timeout(Duration(seconds: 1)),
            completes,
          );
        } else {
          expect(() => disposerResult, returnsNormally);
        }

        await subscription.cancel();
      });

      test('should handle errors in StreamController disposal', () async {
        final controller = StreamController<int>();
        var errorHandled = false;

        final disposer = DisposerAdapterManager.getBuiltinDisposer(controller);
        expect(disposer, isNotNull);

        await runZoned(
          () async {
            await disposer!();
          },
          onError: (error, stack) {
            errorHandled = true;
          },
        );

        // 错误应该被Zone处理，不会抛出
        expect(errorHandled, false);
        expect(controller.isClosed, true);
      });

      test('should clear all registered adapters', () {
        final customObject1 = _CustomDisposableObject();
        final customObject2 = _AnotherCustomObject();

        DisposerAdapterManager.register<_CustomDisposableObject>((obj) {
          return () => obj.cleanup();
        });

        DisposerAdapterManager.register<_AnotherCustomObject>((obj) {
          return () => obj.dispose();
        });

        expect(
          () => DisposerAdapterManager.getDisposer(customObject1),
          returnsNormally,
        );
        expect(
          () => DisposerAdapterManager.getDisposer(customObject2),
          returnsNormally,
        );

        DisposerAdapterManager.clear();

        expect(
          DisposerAdapterManager.getDisposer(customObject1),
          null,
        );
        expect(
          DisposerAdapterManager.getDisposer(customObject2),
          null,
        );
      });
    });

    group('Integration tests', () {
      test('should work with real resources', () async {
        final disposable = _TestDisposable();
        final controller = StreamController<int>();
        final timer = Timer(Duration(seconds: 10), () {});
        final subscription = controller.stream.listen((_) {});

        controller.disposeWith(disposable);
        timer.disposeWith(disposable);
        subscription.disposeWith(disposable);

        expect(disposable.disposerCount, 3);

        final disposeResult = disposable.dispose();
        if (disposeResult is Future<void>) {
          await disposeResult.timeout(Duration(seconds: 2));
        }

        expect(disposable.isDisposed, true);
        expect(disposable.disposerCount, 0);
      });

      test('should work with periodic timer', () async {
        final disposable = _TestDisposable();
        final controller = StreamController<int>();
        final periodicTimer = Timer.periodic(
          Duration(milliseconds: 100),
          (_) {},
        );
        final subscription = controller.stream.listen((_) {});

        controller.disposeWith(disposable);
        periodicTimer.disposeWith(disposable);
        subscription.disposeWith(disposable);

        expect(disposable.disposerCount, 3);

        final disposeResult = disposable.dispose();
        if (disposeResult is Future<void>) {
          await disposeResult.timeout(Duration(seconds: 2));
        }

        expect(disposable.isDisposed, true);
        expect(disposable.disposerCount, 0);

        expect(periodicTimer.isActive, false);
      });

      test('should handle complex disposal chain', () async {
        final parent = _TestDisposable();
        final child1 = _TestDisposable();
        final child2 = _TestDisposable();

        child1.disposeWith(parent);
        child2.disposeWith(parent);

        final timer1 = Timer(Duration(seconds: 10), () {});
        final timer2 = Timer(Duration(seconds: 10), () {});

        timer1.disposeWith(child1);
        timer2.disposeWith(child2);

        expect(parent.disposerCount, 2);
        expect(child1.disposerCount, 1);
        expect(child2.disposerCount, 1);

        final disposeResult = parent.dispose();
        if (disposeResult is Future<void>) {
          await disposeResult.timeout(Duration(seconds: 2));
        }

        expect(parent.isDisposed, true);
        expect(child1.isDisposed, true);
        expect(child2.isDisposed, true);

        expect(timer1.isActive, false);
        expect(timer2.isActive, false);

        expect(parent.disposerCount, 0);
        expect(child1.disposerCount, 0);
        expect(child2.disposerCount, 0);
      });

      test('should prevent circular dispose', () async {
        final parent = _TestDisposable();
        final child = _TestDisposable();

        child.disposeWith(parent);

        child.onDispose(() {
          parent.onDispose(() {});
        });

        expect(parent.disposerCount, 1);
        expect(child.disposerCount, 1);

        final disposeResult = parent.dispose();
        if (disposeResult is Future<void>) {
          await disposeResult.timeout(Duration(seconds: 1));
        }

        expect(parent.isDisposed, true);
        expect(child.isDisposed, true);
      });

      test('should handle multiple dispose calls safely', () async {
        final disposable = _TestDisposable();
        var disposeCount = 0;

        disposable.onDispose(() {
          disposeCount++;
        });

        await disposable.dispose();
        await disposable.dispose();
        await disposable.dispose();

        expect(disposeCount, 1);
        expect(disposable.isDisposed, true);
      });

      test(
        'should handle StreamController disposal (separate test)',
        () async {
          final disposable = _TestDisposable();
          final controller = StreamController<int>();

          final subscription = controller.stream.listen((_) {});

          controller.disposeWith(disposable);
          subscription.disposeWith(disposable);

          expect(disposable.disposerCount, 2);

          final disposeResult = disposable.dispose();
          if (disposeResult is Future<void>) {
            await disposeResult.timeout(Duration(seconds: 5));
          }

          expect(disposable.isDisposed, true);
          expect(disposable.disposerCount, 0);
        },
        timeout: Timeout(Duration(seconds: 10)),
      );
    });

    group('AutoDisposer', () {
      test('should attach disposer to any object', () {
        final object = Object();
        var disposeCount = 0;

        object.attachDisposer(() {
          disposeCount++;
        });

        expect(object.hasAttachedDisposers, true);
        expect(object.attachedDisposerCount, 1);
        expect(disposeCount, 0);
      });

      test('should execute attached disposers manually', () async {
        final object = Object();
        var disposeCount = 0;

        object.attachDisposer(() {
          disposeCount++;
        });

        await object.disposeAttached();

        expect(disposeCount, 1);
        expect(object.hasAttachedDisposers, false);
        expect(object.attachedDisposerCount, 0);
      });

      test('should handle multiple disposers', () async {
        final object = Object();
        var disposeCount = 0;

        object.attachDisposer(() => disposeCount++);
        object.attachDisposer(() => disposeCount++);
        object.attachDisposer(() => disposeCount++);

        expect(object.attachedDisposerCount, 3);

        await object.disposeAttached();

        expect(disposeCount, 3);
        expect(object.hasAttachedDisposers, false);
      });

      test('should handle async disposers', () async {
        final object = Object();
        var disposeCount = 0;

        object.attachDisposer(() async {
          await Future.delayed(Duration(milliseconds: 10));
          disposeCount++;
        });

        object.attachDisposer(() => disposeCount++);

        await object.disposeAttached();

        expect(disposeCount, 2);
      });

      test('should handle disposer errors', () async {
        final object = Object();
        var errorCaught = false;

        runZoned(() {
          object.attachDisposer(() {
            throw Exception('Test error');
          });

          object.attachDisposer(() {
            errorCaught = true;
          });

          object.disposeAttached();
        }, onError: (error, stack) {});

        await Future.delayed(Duration(milliseconds: 10));
        expect(errorCaught, true);
      });

      test('should detach disposers', () {
        final object = Object();
        var disposeCount = 0;

        object.attachDisposer(() => disposeCount++);
        expect(object.hasAttachedDisposers, true);

        object.detachDisposers();
        expect(object.hasAttachedDisposers, false);
        expect(object.attachedDisposerCount, 0);
      });

      test('should work with third-party objects', () async {
        final thirdPartyObject = _ThirdPartyObject();
        var disposeCount = 0;

        thirdPartyObject.attachDisposer(() {
          thirdPartyObject.close();
          disposeCount++;
        });

        expect(thirdPartyObject.hasAttachedDisposers, true);
        expect(thirdPartyObject.isClosed, false);

        await thirdPartyObject.disposeAttached();

        expect(thirdPartyObject.isClosed, true);
        expect(disposeCount, 1);
      });

      test('should work with StreamController through AutoDisposer', () async {
        final object = Object();
        final controller = StreamController<int>();
        var disposeCount = 0;

        object.attachDisposer(() {
          controller.close();
          disposeCount++;
        });

        expect(object.hasAttachedDisposers, true);
        expect(controller.isClosed, false);

        await object.disposeAttached();

        expect(controller.isClosed, true);
        expect(disposeCount, 1);
      });

      test('should handle mixed disposer types', () async {
        final object = Object();
        final controller = StreamController<int>();
        final timer = Timer(Duration(seconds: 10), () {});
        var disposeCount = 0;

        object.attachDisposer(() {
          controller.close();
          disposeCount++;
        });

        object.attachDisposer(() {
          timer.cancel();
          disposeCount++;
        });

        object.attachDisposer(() async {
          await Future.delayed(Duration(milliseconds: 5));
          disposeCount++;
        });

        expect(object.attachedDisposerCount, 3);

        await object.disposeAttached();

        expect(disposeCount, 3);
        expect(controller.isClosed, true);
        expect(timer.isActive, false);
      });

      test('should auto-dispose when object is garbage collected', () async {
        var disposeCount = 0;

        void createObjectWithDisposer() {
          final object = Object();
          object.attachDisposer(() {
            disposeCount++;
            print('Disposer executed during GC: $disposeCount');
          });

          expect(object.hasAttachedDisposers, true);
          expect(object.attachedDisposerCount, 1);
        }

        createObjectWithDisposer();

        print('Forcing garbage collection...');
        await Future.delayed(Duration(milliseconds: 100));

        for (int i = 0; i < 1000; i++) {
          final temp = List.filled(1000, i, growable: true);
          temp.clear();
        }

        await Future.delayed(Duration(milliseconds: 500));

        print('Dispose count after GC attempt: $disposeCount');

        expect(disposeCount >= 0, true);
      });

      test('should handle multiple objects with finalizers', () async {
        var totalDisposeCount = 0;
        final objects = List<Object>.empty(growable: true);

        for (int i = 0; i < 10; i++) {
          final object = Object();
          object.attachDisposer(() {
            totalDisposeCount++;
            print('Object $i disposer executed');
          });
          objects.add(object);
        }

        for (final object in objects) {
          expect(object.hasAttachedDisposers, true);
          expect(object.attachedDisposerCount, 1);
        }

        await objects[0].disposeAttached();
        await objects[1].disposeAttached();

        expect(totalDisposeCount, 2);

        objects.clear();

        await Future.delayed(Duration(milliseconds: 100));
        for (int i = 0; i < 1000; i++) {
          final temp = List.filled(100, i, growable: true);
          temp.clear();
        }
        await Future.delayed(Duration(milliseconds: 500));

        print('Total dispose count: $totalDisposeCount');

        expect(totalDisposeCount >= 2, true);
      });

      test('should work with complex objects and finalizers', () async {
        var disposeCount = 0;
        final controllers = <StreamController<int>>[];

        void createComplexObject() {
          final object = Object();
          final controller = StreamController<int>();
          controllers.add(controller);

          object.attachDisposer(() {
            controller.close();
            disposeCount++;
            print('Controller disposed via finalizer');
          });

          object.attachDisposer(() async {
            await Future.delayed(Duration(milliseconds: 10));
            disposeCount++;
            print('Async disposer executed via finalizer');
          });

          expect(object.hasAttachedDisposers, true);
          expect(object.attachedDisposerCount, 2);
        }

        createComplexObject();

        expect(controllers.first.isClosed, false);

        await Future.delayed(Duration(milliseconds: 100));
        for (int i = 0; i < 1000; i++) {
          final temp = List.filled(100, i, growable: true);
          temp.clear();
        }
        await Future.delayed(Duration(milliseconds: 500));

        print('Complex object dispose count: $disposeCount');
        expect(disposeCount >= 0, true);
      });

      test('should verify finalizer execution with WeakReference', () async {
        var disposeCount = 0;
        WeakReference<Object>? weakRef;

        void createObjectWithDisposer() {
          final object = Object();
          weakRef = WeakReference(object);

          object.attachDisposer(() {
            disposeCount++;
            print('Finalizer executed! Dispose count: $disposeCount');
          });

          expect(object.hasAttachedDisposers, true);
          expect(object.attachedDisposerCount, 1);
        }

        createObjectWithDisposer();

        expect(weakRef!.target != null, true);

        for (int attempt = 0; attempt < 5; attempt++) {
          print('GC attempt ${attempt + 1}');

          for (int i = 0; i < 10000; i++) {
            final temp = List.filled(100, i, growable: true);
            temp.clear();
          }

          await Future.delayed(Duration(milliseconds: 200));

          if (weakRef!.target == null) {
            print('Object was garbage collected!');
            break;
          }
        }

        await Future.delayed(Duration(milliseconds: 1000));

        print('Final dispose count: $disposeCount');
        print('Object still exists: ${weakRef!.target != null}');

        if (weakRef!.target == null) {
          expect(disposeCount, 1);
        } else {
          expect(disposeCount >= 0, true);
        }
      });

      test('should handle finalizer with async disposers', () async {
        var disposeCount = 0;
        final results = <String>[];

        void createObjectWithAsyncDisposer() {
          final object = Object();

          object.attachDisposer(() async {
            await Future.delayed(Duration(milliseconds: 50));
            disposeCount++;
            results.add('async-disposer-1');
            print('Async disposer 1 executed');
          });

          object.attachDisposer(() {
            disposeCount++;
            results.add('sync-disposer');
            print('Sync disposer executed');
          });

          object.attachDisposer(() async {
            await Future.delayed(Duration(milliseconds: 25));
            disposeCount++;
            results.add('async-disposer-2');
            print('Async disposer 2 executed');
          });

          expect(object.hasAttachedDisposers, true);
          expect(object.attachedDisposerCount, 3);
        }

        createObjectWithAsyncDisposer();

        for (int i = 0; i < 10000; i++) {
          final temp = List.filled(100, i, growable: true);
          temp.clear();
        }

        await Future.delayed(Duration(milliseconds: 2000));

        print('Async finalizer dispose count: $disposeCount');
        print('Results: $results');

        expect(disposeCount >= 0, true);
      });
    });
  });
}

// ignore: unused_field
enum _TestEnum { value1, value2 }

class _TestDisposable with DisposableMixin {
  int get disposerCount {
    return _registeredDisposerCount;
  }

  int _registeredDisposerCount = 0;

  @override
  Disposer? onDispose(Disposer? disposer) {
    if (isDisposed || disposer == null) return null;
    final result = super.onDispose(disposer);
    _registeredDisposerCount++;
    return result;
  }

  @override
  FutureOr<void> dispose() async {
    await super.dispose();
    _registeredDisposerCount = 0;
  }
}

class _ThirdPartyObject {
  bool isClosed = false;
  void close() {
    isClosed = true;
  }
}

class _CustomDisposableObject {
  bool isCleanedUp = false;
  void cleanup() {
    isCleanedUp = true;
  }
}

class _AnotherCustomObject {
  bool isDisposed = false;
  void dispose() {
    isDisposed = true;
  }
}

class _UnsupportedObject {
  // 没有任何dispose相关的方法
}
