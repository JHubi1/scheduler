/// @docImport "progress_snatcher.dart";
/// @docImport "remote_exception.dart";
library;

import 'dart:async';

import 'package:meta/meta.dart';
import 'package:retry/retry.dart';

import 'priority_queue.dart';
import 'retry_options.dart';
import 'tasks.dart';

class _SchedulerPackage<I extends Object, O extends Object> {
  final Task<I, O> task;
  final I input;
  final Completer<TaskStatus<I, O>> completer;
  final int priority;
  final Duration? queueExpiration;
  final void Function(TaskProgressBroadcaster progress)? progressBroadcaster;

  late final DateTime _addedToQueue;

  _SchedulerPackage({
    required this.task,
    required this.input,
    required this.completer,
    required this.priority,
    required this.queueExpiration,
    required this.progressBroadcaster,
    DateTime? addedToQueue,
  }) : _addedToQueue = addedToQueue ?? DateTime.now();

  Map<String, Object?> toJson({bool wasRunning = false}) {
    return {
      "task": task.id,
      "input": input,
      "priority": priority,
      "queueExpiration": queueExpiration?.inMilliseconds,
      "wasRunning": wasRunning,
      "_addedToQueue": _addedToQueue.toIso8601String(),
    };
  }

  Future<TaskStatus<I, O>> _invoke(
    TaskBundle taskBundle, {
    required void Function(int id) invocationId,
    RetryOptions? retryOptions,
  }) => taskBundle.invokeNamed<I, O>(
    task.id,
    input,
    progressBroadcaster: progressBroadcaster,
    invocationId: invocationId,
    retryOptions: retryOptions,
  );
}

class SchedulerConfig {
  final int simultaneousInvocations;

  final Duration cullingInterval;
  final Duration cullingIdle;

  final RetryOptions retryOptions;

  const SchedulerConfig({
    this.simultaneousInvocations = 5,
    this.cullingInterval = const Duration(seconds: 5),
    this.cullingIdle = const Duration(minutes: 1),
    this.retryOptions = const RetryOptions(maxAttempts: 3),
  });

  void _validate() {
    assert(
      simultaneousInvocations > 0,
      "simultaneousInvocations must be greater than 0",
    );
    assert(
      cullingInterval > Duration.zero,
      "cullingInterval must be greater than 0",
    );
    assert(
      cullingIdle > Duration.zero && cullingIdle >= cullingInterval,
      "cullingIdle must be greater than 0",
    );

    if (!(simultaneousInvocations > 0)) {
      throw ArgumentError.value(
        simultaneousInvocations,
        "simultaneousInvocations",
        "simultaneousInvocations must be greater than 0",
      );
    } else if (!(cullingInterval > Duration.zero)) {
      throw ArgumentError.value(
        cullingInterval,
        "cullingInterval",
        "cullingInterval must be greater than 0",
      );
    } else if (!(cullingIdle > Duration.zero &&
        cullingIdle >= cullingInterval)) {
      throw ArgumentError.value(
        cullingIdle,
        "cullingIdle",
        "cullingIdle must be greater than 0 and greater than or equal to cullingInterval",
      );
    }
  }

  SchedulerConfig copyWith({
    int? simultaneousInvocations,
    Duration? cullingInterval,
    Duration? cullingIdle,
    RetryOptions? retryOptions,
  }) {
    return SchedulerConfig(
      simultaneousInvocations:
          simultaneousInvocations ?? this.simultaneousInvocations,
      cullingInterval: cullingInterval ?? this.cullingInterval,
      cullingIdle: cullingIdle ?? this.cullingIdle,
      retryOptions: retryOptions ?? this.retryOptions,
    );
  }

  Map<String, Object> toJson() {
    return {
      "simultaneousInvocations": simultaneousInvocations,
      "cullingInterval": cullingInterval.inMilliseconds,
      "cullingIdle": cullingIdle.inMilliseconds,
      "retryOptions": retryOptions.toJson(),
    };
  }

  factory SchedulerConfig.fromJson(Map<String, Object?> json) {
    return SchedulerConfig(
      simultaneousInvocations: json["simultaneousInvocations"] as int? ?? 5,
      cullingInterval: Duration(
        milliseconds: json["cullingInterval"] as int? ?? 5000,
      ),
      cullingIdle: Duration(milliseconds: json["cullingIdle"] as int? ?? 60000),
      retryOptions: RetryOptionsSerializer.fromJson(
        json["retryOptions"] as Map<String, dynamic>? ?? {},
      ),
    );
  }
}

/// A scheduler that manages the execution of tasks in isolates.
///
/// This is the main entry point for using the scheduler. It allows you to
/// invoke tasks by their type or id, and manages the execution of tasks based
/// on their priority and the number of simultaneous tasks allowed.
///
/// ---
///
/// Example usage:
///
/// ```dart
/// final scheduler = Scheduler([EchoTask()]);
/// final status = await scheduler.invoke(EchoTask, "hello");
/// print((await status.future).success?.output); // prints "hello"
/// ```
///
/// See [`example/scheduler_example.dart`](https://github.com/JHubi1/scheduler/blob/main/example/scheduler_example.dart)
/// for a more detailed usage example and consult the documentation
/// (`dart doc --validate-links .`) for help.
class Scheduler {
  final TaskBundle _taskBundle;
  late final StablePriorityQueue<_SchedulerPackage> _queue;
  int _queueLockState = 0;

  SchedulerConfig _config;

  /// The current configuration that is applied to this [Scheduler].
  ///
  /// When the configuration is updated, the options are applied the next run
  /// respectively. Meaning, the culling settings are applied in the next
  /// culling cycle and retry options on the next invocation, for example.
  ///
  /// Currently running invocations are not cancelled if the number of
  /// [SchedulerConfig.simultaneousInvocations] is below the current amount.
  SchedulerConfig get config => _config;
  set config(SchedulerConfig value) {
    _config = value;
    _taskBundle
      ..stopCulling()
      ..startCulling(
        interval: _config.cullingInterval,
        idleTime: _config.cullingIdle,
      );
    _queueLoop();
  }

  /// Tasks that the scheduler can invoke.
  Set<Task> get tasks => _taskBundle.tasks;

  /// All currently running task ids.
  ///
  /// Running here means that they are either currently executing or idle but
  /// still have an active isolate. Once a task has been idle for longer than
  /// [SchedulerConfig.cullingIdle], it will be culled and removed.
  ///
  /// There tasks can be looked up in [tasks] to get their metadata and other
  /// information.
  List<String> get running => _taskBundle.running;

  /// Currently running invocations, mapped by their invocation id.
  ///
  /// The invocation id is a unique identifier for each invocation of a task. It
  /// can be used to track the progress of a specific invocation using the
  /// [ProgressSnatcher] for example.
  Map<int, TaskStatus> get runningInvocations => _taskBundle.runningInvocations;
  final Map<int, _SchedulerPackage> _runningPackages = {};
  int _tmpInvocationIdCounter = 0;

  /// Completes when all currently running invocations have completed.
  ///
  /// This can be useful when you want to wait for all tasks to finish before
  /// closing the scheduler or performing some other action.
  Future<void> get completeRunningInvocations =>
      _taskBundle.runningInvocations.isEmpty
      ? Future.value()
      : _completeRunningInvocations.stream.first;
  final _completeRunningInvocations = StreamController.broadcast(sync: true);
  late int _completeRunningInvocationsLastLength = _runningPackages.length;

  Scheduler(Iterable<Task> tasks, {this._config = const SchedulerConfig()})
    : _taskBundle = TaskBundle(tasks, startCulling: false) {
    _config._validate();
    _queue = StablePriorityQueue(
      postponeExecution: (package) =>
          !package.task.allowSimultaneous &&
          _taskBundle.runningInvocations.values.any(
            (i) => i.task.id == package.task.id,
          ),
    );
    _taskBundle
      ..addListener(_onUpdate)
      ..startCulling(
        interval: config.cullingInterval,
        idleTime: config.cullingIdle,
      );
  }

  void _onUpdate(String taskId) {
    if (_completeRunningInvocationsLastLength > 0 &&
        _taskBundle.runningInvocations.isEmpty) {
      _completeRunningInvocations.add(null);
    }
    _completeRunningInvocationsLastLength =
        _taskBundle.runningInvocations.length;

    _queueLoop();
  }

  /// Closes all running task instances in the scheduler and terminates their
  /// isolates.
  ///
  /// The [silent] flag can be set to true to prevent the scheduler from
  /// throwing an exception to the running invocations' futures.
  ///
  /// The [graceful] flag can be set to false to immediately terminate all
  /// running invocations without waiting for them to complete. If set to true,
  /// the scheduler will wait for all running invocations to complete before
  /// closing. The [gracefulTimeout] can be set to limit the time the scheduler
  /// will wait for running invocations to complete before closing.
  ///
  /// The [saveRestorableState] callback can be provided to save the current
  /// state of the scheduler before closing. This function is called after all
  /// running invocations have completed with the [graceful] flag set to true.
  Future<void> close({
    bool silent = false,
    bool graceful = true,
    Duration? gracefulTimeout = const Duration(seconds: 30),
    FutureOr<void> Function()? saveRestorableState,
  }) async {
    if (graceful && _completeRunningInvocationsLastLength > 0) {
      runningInvocations.forEach((_, status) => status.cancel());

      var future = completeRunningInvocations;
      if (gracefulTimeout != null) {
        future = future.timeout(gracefulTimeout, onTimeout: () {});
      }
      await future.catchError((_) {});
    }
    if (!silent) {
      for (var package in List.from(_runningPackages.values)) {
        if (!package.completer.isCompleted) {
          package.completer.completeError(
            StateError(
              "Scheduler is closing gracefully, cancelling invocation of '${package.task.id}' with input '${package.input}'.",
            ),
            StackTrace.current,
          );
        }
        _runningPackages.removeWhere((_, p) => p == package);
      }
    }

    await Future.value(saveRestorableState?.call());
    _taskBundle.removeListener(_onUpdate);
    await _taskBundle.close(silent: silent);
  }

  /// Creates a representation of the currently running and queued invocations
  /// that can be restored using [Scheduler.fromRestorableState].
  ///
  /// {@template com.jhubi1.scheduler.Scheduler.restorableState}
  /// This is the persistent storage of the scheduler package so to speak,
  /// though the developer is responsible for storing and loading this state.
  ///
  /// The used Map is meant to be encoded into and decoded from JSON. Other
  /// forms of storage may be used.
  /// {@endtemplate}
  @nonVirtual
  Map<String, Object> restorableState() => {
    "config": config.toJson(),
    "taskIds": tasks.map((t) => t.id).toList(),
    "invocations": [
      ..._runningPackages.entries
          .where((p) => p.value.task.allowRestoration)
          .map((e) => e.value.toJson(wasRunning: true)),
      ..._queue
          .toList()
          .where((p) => p.task.allowRestoration)
          .map((e) => e.toJson(wasRunning: false)),
    ],
  };

  /// Restores a representation of the [Scheduler] and starts back up all the
  /// invocations that were running or queued.
  ///
  /// {@macro com.jhubi1.scheduler.Scheduler.restorableState}
  ///
  /// The invocations that were running when the [restorableState] method was
  /// called get a 100 priority point boost so they should be started first,
  /// even when higher priority tasks are queued.
  factory Scheduler.fromRestorableState(
    Iterable<Task> tasks,
    Map<String, Object?> state,
  ) {
    if (state case {
      "config": final Map<String, Object?> configJson,
      "taskIds": final List<Object?> taskIdsRaw,
      "invocations": final List<Object?> invocations,
    }) {
      final taskIds = taskIdsRaw.cast<String>().toList();
      if (!taskIds.every((id) => tasks.any((t) => t.id == id))) {
        throw ArgumentError.value(
          state,
          "state",
          "Restorable state contains task ids that are not present in the provided tasks.",
        );
      }

      Scheduler scheduler;
      try {
        final config = SchedulerConfig.fromJson(configJson);
        scheduler = Scheduler(tasks, config: config);
      } catch (_) {
        throw ArgumentError.value(
          state,
          "state",
          "Invalid config in restorable state.",
        );
      }

      for (final invocation in invocations) {
        if (invocation case {
          "task": final String taskId,
          "input": final Object input,
          "priority": final int priority,
          "wasRunning": final bool wasRunning,
        }) {
          if (!taskIds.contains(taskId)) {
            throw ArgumentError.value(
              state,
              "state",
              "Restorable state contains a task id '$taskId' that is not present in the provided tasks.",
            );
          }

          final task = tasks.singleWhere((t) => t.id == taskId);
          if (!task.allowRestoration) {
            throw ArgumentError.value(
              state,
              "state",
              "Restorable state contains a task id '$taskId' that does not allow restoration.",
            );
          }

          scheduler._queue.add(
            _SchedulerPackage(
              task: task,
              input: input,
              completer: Completer(),
              priority: wasRunning ? priority + 100 : priority,
              queueExpiration: invocation["queueExpiration"] != null
                  ? Duration(
                      milliseconds: invocation["queueExpiration"]! as int,
                    )
                  : null,
              progressBroadcaster: null,
              addedToQueue: invocation["_addedToQueue"] != null
                  ? DateTime.parse(invocation["_addedToQueue"]! as String)
                  : null,
            ),
          );
        } else {
          throw ArgumentError.value(
            state,
            "state",
            "Invalid invocation format in restorable state.",
          );
        }
      }

      scheduler._queueLoop();
      return scheduler;
    } else {
      throw ArgumentError.value(state, "state", "Invalid restorable state");
    }
  }

  /// Invokes a task by its id with the given input and returns the output
  /// asynchronously.
  ///
  /// {@macro com.jhubi1.scheduler.TaskBundle.invoke}
  ///
  /// Set [processQueue] to false to prevent the scheduler from automatically
  /// starting the queue loop after adding the task to the queue. This can be
  /// useful if you want to add multiple tasks to the queue before starting the
  /// loop. ***Careful:*** If the last call to [invoke] has [processQueue] set
  /// to false, this function will not return until the queue loop has been
  /// started by another invocation and the task has been executed.
  ///
  /// See [invoke] for more information about [processQueueLockAssert].
  ///
  /// ---
  ///
  /// Example usage:
  ///
  /// ```dart
  /// final scheduler = Scheduler([EchoTask()]);
  /// final status = await scheduler.invokeNamed("echoTask", "hello");
  /// print((await status.future).success?.output); // prints "hello"
  /// ```
  Future<TaskStatus<I, O>> invokeNamed<I extends Object, O extends Object>(
    String taskId,
    I input, {
    int? priority,
    Duration? queueExpiration,
    bool processQueue = true,
    bool processQueueLockAssert = true,
    void Function(TaskProgressBroadcaster progress)? progressBroadcaster,
  }) async {
    if (!tasks.any((t) => t.id == taskId)) {
      throw ArgumentError(
        "Scheduler does not contain a task with id '$taskId'.",
      );
    }

    final task = tasks.singleWhere((t) => t.id == taskId) as Task<I, O>;
    return invoke<I, O>(
      task.runtimeType,
      input,
      priority: priority ?? task.metadataObject.priority ?? 0,
      queueExpiration: queueExpiration,
      processQueue: processQueue,
      processQueueLockAssert: processQueueLockAssert,
      progressBroadcaster: progressBroadcaster,
    );
  }

  /// Invokes a task by its type with the given input and returns the output
  /// asynchronously.
  ///
  /// {@macro com.jhubi1.scheduler.TaskBundle.invoke}
  ///
  /// Set [processQueue] to false to prevent the scheduler from automatically
  /// starting the queue loop after adding the task to the queue. This can be
  /// useful if you want to add multiple tasks to the queue before starting the
  /// loop. ***Careful:*** If the last call to [invoke] has [processQueue] set
  /// to false, this function will not return until the queue loop has been
  /// started by another invocation and the task has been executed.
  ///
  /// To prevent difficulties during development, the [processQueueLockAssert]
  /// flag is enabled by default. If it is set to `true` and [processQueue] is
  /// set to `false`, the function will assert after 5 seconds if no queue run
  /// has been triggered.
  ///
  /// ---
  ///
  /// Example usage:
  ///
  /// ```dart
  /// final scheduler = Scheduler([EchoTask()]);
  /// final status = await scheduler.invoke(EchoTask, "hello");
  /// print((await status.future).success?.output); // prints "hello"
  /// ```
  Future<TaskStatus<I, O>> invoke<I extends Object, O extends Object>(
    Type taskType,
    I input, {
    int? priority,
    Duration? queueExpiration,
    bool processQueue = true,
    bool processQueueLockAssert = true,
    void Function(TaskProgressBroadcaster progress)? progressBroadcaster,
    void Function(Object error, StackTrace stackTrace)? catchError,
  }) async {
    final task =
        tasks.singleWhere(
              (t) => t.runtimeType == taskType,
              orElse: () => throw ArgumentError(
                "Scheduler does not contain a task of type '$taskType'.",
              ),
            )
            as Task<I, O>;

    final completer = Completer<TaskStatus<I, O>>();
    _queue.add(
      _SchedulerPackage<I, O>(
        task: task,
        input: input,
        completer: completer,
        priority: priority ?? task.metadataObject.priority ?? 0,
        queueExpiration: queueExpiration,
        progressBroadcaster: progressBroadcaster,
      ),
    );

    if (processQueue) {
      _queueLoop();
    } else if (processQueueLockAssert) {
      assert(() {
        final queueLockStateAtInvocation = _queueLockState;
        final stackTrace = StackTrace.current;
        Future.delayed(Duration(seconds: 5)).then((_) {
          try {
            assert(
              _queueLockState != queueLockStateAtInvocation,
              "Because processQueue was set to false (for ${task.id} with input '$input'), and the queue loop was not started after 5 seconds, Scheduler believes the invoke call may be stuck.\n"
              "Usually, the queue loop for an invocation with processQueue set to false should be started by another invocation of any task, but it seems that this did not happen in time.\n"
              "If you are sure that this is not the case, you can disable this assertion by setting processQueueLockAssert to false.",
            );
            // rerouting stacktrace for clearer error message, ik anti pattern
            // ignore: avoid_catching_errors
          } on AssertionError catch (e) {
            Error.throwWithStackTrace(e, stackTrace);
          }
        });
        return true;
      }(), "");
    }
    return completer.future;
  }

  void _queueLoop() {
    _queueLockState++;
    while (_queue.isNotEmpty &&
        _runningPackages.length < config.simultaneousInvocations) {
      final package = _queue.removeFirstSafe();
      if (package == null) break;
      if (package.queueExpiration != null &&
          DateTime.now().difference(package._addedToQueue) >
              package.queueExpiration!) {
        package.completer.completeError(
          TimeoutException(
            "Invocation of '${package.task.id}' expired in the queue after ${package.queueExpiration}.",
          ),
          StackTrace.current,
        );
        continue;
      }

      final tmpId = --_tmpInvocationIdCounter;
      var id = tmpId;
      _runningPackages[tmpId] = package;

      package
          ._invoke(
            _taskBundle,
            invocationId: (newId) {
              _runningPackages.remove(id);
              id = newId;
              _runningPackages[newId] = package;
            },
            retryOptions: config.retryOptions,
          )
          .then((status) async {
            package.completer.complete(status);
            await status.future;
            _runningPackages.remove(id);
            _queueLoop();
          })
          .catchError((e, s) {
            package.completer.completeError(e, s);
            _runningPackages.remove(id);
            _queueLoop();
          });
    }
  }
}
