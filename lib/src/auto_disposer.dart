part of '../free_disposer.dart';

/// Automatic resource disposal using Finalizers.
///
/// This class provides static methods to attach disposers to objects.
/// When objects are garbage collected, their associated disposers
/// will be executed automatically.
///
/// Example:
/// ```dart
/// final object = Object();
/// final timer = Timer.periodic(Duration(seconds: 1), (_) {});
///
/// // Attach disposer - timer will be cancelled when object is GC'd
/// AutoDisposer.attachDisposer(object, () => timer.cancel());
///
/// // Or dispose manually
/// await AutoDisposer.disposeObject(object);
/// ```
class AutoDisposer {
  static final Expando<Set<Disposer>> _disposers = Expando<Set<Disposer>>();

  static final Finalizer<Set<Disposer>> _finalizer = Finalizer<Set<Disposer>>(
    (disposers) {
      if (disposers.isEmpty) return;
      for (final d in disposers) {
        try {
          final result = d();
          if (result is Future) {
            result.catchError(
              (e, st) => Zone.current.handleUncaughtError(e, st),
            );
          }
        } catch (e, st) {
          Zone.current.handleUncaughtError(e, st);
        }
      }
    },
  );

  static final Expando<Object> _detachToken = Expando<Object>();

  static final Set<WeakReference<Object>> _pendingAttach =
      <WeakReference<Object>>{};
  static final Expando<WeakReference<Object>> _objectToWeakRef =
      Expando<WeakReference<Object>>();
  static bool _batchScheduled = false;

  /// Attach a disposer to an object.
  ///
  /// When [object] is garbage collected, [disposer] will be executed
  /// automatically. The same disposer can only be attached once to
  /// the same object (Set semantics prevent duplicates).
  ///
  /// **Performance Notes:**
  /// - Uses `Set<Disposer>` for O(1) average attachment time
  /// - Batches Finalizer operations for improved performance
  /// - Blacklisted types are rejected to prevent runtime errors
  ///
  /// **Parameters:**
  /// - [object]: The object to attach the disposer to
  /// - [disposer]: The cleanup function to execute
  ///
  /// **Throws:**
  /// - [UnsupportedError] if [object] is a blacklisted type (primitive types,
  ///   null, enums, symbols, or Type objects)
  ///
  /// **Example:**
  /// ```dart
  /// final obj = Object();
  /// final timer = Timer.periodic(Duration(seconds: 1), (_) {});
  ///
  /// AutoDisposer.attachDisposer(obj, () => timer.cancel());
  /// // Timer will be cancelled when obj is garbage collected
  /// ```
  static void attachDisposer(Object object, Disposer disposer) {
    if (_isBlacklisted(object)) {
      throw UnsupportedError(
        'Cannot attach disposer to object of type ${object.runtimeType}',
      );
    }

    final disposers = _disposers[object] ??= <Disposer>{};
    disposers.add(disposer);

    if (_detachToken[object] == null) {
      final weakRef = WeakReference(object);
      _pendingAttach.add(weakRef);
      _objectToWeakRef[object] = weakRef;
      _scheduleBatchAttach();
    }
  }

  static void _scheduleBatchAttach() {
    if (_batchScheduled) return;
    _batchScheduled = true;

    Timer.run(_processBatchAttach);
  }

  static void _processBatchAttach() {
    _batchScheduled = false;

    if (_pendingAttach.isEmpty) return;

    final toRemove = <WeakReference<Object>>{};
    for (final weakRef in _pendingAttach) {
      final object = weakRef.target;
      if (object == null) {
        toRemove.add(weakRef);
        continue;
      }

      final disposers = _disposers[object];
      if (disposers != null && _detachToken[object] == null) {
        _detachToken[object] = disposers;
        _finalizer.attach(object, disposers, detach: _detachToken[object]);

        _objectToWeakRef[object] = null;
      }
    }

    _pendingAttach.removeAll(toRemove);
    _pendingAttach.clear();
  }

  /// Immediately process all pending Finalizer attachments.
  ///
  /// This method can be called to ensure all pending Finalizer operations
  /// are processed immediately, rather than waiting for the next event loop
  /// iteration. Useful for testing or when immediate attachment is required.
  ///
  /// **Example:**
  /// ```dart
  /// // Attach many disposers
  /// for (int i = 0; i < 1000; i++) {
  ///   final obj = Object();
  ///   obj.attachDisposer(() => print('disposed $i'));
  /// }
  ///
  /// // Ensure all finalizers are attached immediately
  /// AutoDisposer.flushPendingAttachments();
  /// ```
  static void flushPendingAttachments() {
    if (_pendingAttach.isNotEmpty) {
      _processBatchAttach();
    }
  }

  /// Manually dispose an object by executing all its disposers.
  ///
  /// This detaches the finalizer and executes all registered disposers
  /// immediately. After calling this method, no automatic cleanup will
  /// occur when the object is garbage collected.
  ///
  /// **Execution Details:**
  /// - Detaches the finalizer to prevent double-execution
  /// - Executes all disposers in the order they were added
  /// - Handles both sync and async disposers appropriately
  /// - Collects all async disposers and waits for completion
  /// - Errors are caught and forwarded to the zone error handler
  ///
  /// **Parameters:**
  /// - [object]: The object to dispose
  ///
  /// **Returns:**
  /// A [Future] that completes when all disposers have finished executing,
  /// or completes synchronously if there are no async disposers.
  ///
  /// **Example:**
  /// ```dart
  /// final obj = Object();
  /// obj.attachDisposer(() => print('sync cleanup'));
  /// obj.attachDisposer(() async => await asyncCleanup());
  ///
  /// await AutoDisposer.disposeObject(obj);
  /// // Both disposers executed, finalizer detached
  /// ```
  static FutureOr<void> disposeObject(Object object) {
    final disposers = _disposers[object];
    if (disposers == null || disposers.isEmpty) return null;

    // Detach finalizer to prevent automatic execution
    final token = _detachToken[object];
    if (token != null) {
      try {
        _finalizer.detach(token);
      } catch (_) {
        // Ignore detach errors (finalizer might not be attached yet)
      }
      _detachToken[object] = null;
    }

    Future<void>? future;
    final futures = <Future<void>>[];

    for (final d in disposers) {
      try {
        final result = d();
        if (result is Future<void>) {
          futures.add(
            result.catchError(
              (e, st) => Zone.current.handleUncaughtError(e, st),
            ),
          );
        }
      } catch (e, st) {
        Zone.current.handleUncaughtError(e, st);
      }
    }

    disposers.clear();
    _disposers[object] = null;

    if (futures.isNotEmpty) {
      future = Future.wait(futures, eagerError: false);
    }

    return future;
  }

  /// Detach all disposers from an object without executing them.
  ///
  /// This removes the finalizer and clears all registered disposers
  /// without executing them. Use this when you want to prevent
  /// automatic cleanup from occurring (e.g., when transferring
  /// ownership of resources).
  ///
  /// **Performance Notes:**
  /// - Uses reverse mapping for O(1) removal from pending batch
  /// - Efficiently cleans up all associated data structures
  ///
  /// **Parameters:**
  /// - [object]: The object to detach disposers from
  ///
  /// **Example:**
  /// ```dart
  /// final obj = Object();
  /// obj.attachDisposer(() => print('this will not execute'));
  ///
  /// AutoDisposer.detachDisposers(obj);
  /// // No cleanup will occur when obj is GC'd
  /// ```
  static void detachDisposers(Object object) {
    final weakRef = _objectToWeakRef[object];
    if (weakRef != null) {
      _pendingAttach.remove(weakRef);
      _objectToWeakRef[object] = null;
    }

    final token = _detachToken[object];
    if (token != null) {
      try {
        _finalizer.detach(token);
      } catch (_) {
        // Ignore detach errors
      }
      _detachToken[object] = null;
    }

    _disposers[object]?.clear();
    _disposers[object] = null;
  }

  /// Detach a specific disposer from an object.
  ///
  /// **Note:** This is a simplified implementation that detaches the entire
  /// finalizer. In practice, removing individual disposers while maintaining
  /// the finalizer would require more complex bookkeeping.
  ///
  /// **Parameters:**
  /// - [object]: The object to detach the disposer from
  /// - [disposer]: The specific disposer to detach (currently unused)
  static void detachDisposer(Object object, Disposer disposer) {
    final token = _detachToken[object];
    if (token != null) {
      _finalizer.detach(token);
    }
    _detachToken[object] = null;
  }

  /// Check if an object has any attached disposers.
  ///
  /// **Parameters:**
  /// - [object]: The object to check
  ///
  /// **Returns:**
  /// `true` if the object has one or more disposers, `false` otherwise
  ///
  /// **Example:**
  /// ```dart
  /// final obj = Object();
  /// print(AutoDisposer.hasDisposers(obj)); // false
  ///
  /// obj.attachDisposer(() {});
  /// print(AutoDisposer.hasDisposers(obj)); // true
  /// ```
  static bool hasDisposers(Object object) =>
      _disposers[object]?.isNotEmpty ?? false;

  /// Get the number of disposers attached to an object.
  ///
  /// **Parameters:**
  /// - [object]: The object to check
  ///
  /// **Returns:**
  /// The number of attached disposers (0 if none)
  ///
  /// **Example:**
  /// ```dart
  /// final obj = Object();
  /// print(AutoDisposer.disposerCount(obj)); // 0
  ///
  /// obj.attachDisposer(() {});
  /// obj.attachDisposer(() {});
  /// print(AutoDisposer.disposerCount(obj)); // 2
  /// ```
  static int disposerCount(Object object) => _disposers[object]?.length ?? 0;
}
