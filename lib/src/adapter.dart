part of '../free_disposer.dart';

typedef DisposerAdapter<T> = Disposer Function(T object);

class DisposerAdapterManager {
  static final List<_Entry> _userEntries = [];

  static void register<T>(DisposerAdapter<T> adapter) {
    _userEntries.add(_Entry<T>(adapter));
  }

  static void unregister<T>() {
    _userEntries.removeWhere((e) => e.type == T);
  }

  static Disposer getDisposer(Object? object) {
    if (object != null) {
      final d = getBuiltinDisposer(object);
      if (d != null) return d;

      for (final e in _userEntries) {
        if (e.matches(object)) return e.invoke(object);
      }
    }
    throw UnsupportedError(
      'Unsupported type: ${object.runtimeType}, must be Disposable',
    );
  }

  @pragma('vm:prefer-inline')
  static Disposer? getBuiltinDisposer(Object? object) => switch (object) {
        Disposable d => d.dispose,
        StreamSubscription s => s.cancel,
        Timer t => t.cancel,
        StreamController c => () async {
            try {
              if (!c.isClosed) {
                if (c.hasListener || c.stream.isBroadcast) {
                  await c.close().timeout(
                        const Duration(milliseconds: 500),
                        onTimeout: () {},
                      );
                } else {
                  await c.close().timeout(
                        const Duration(milliseconds: 100),
                        onTimeout: () {},
                      );
                }
              }
            } catch (e, st) {
              Zone.current.handleUncaughtError(e, st);
            }
          },
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
