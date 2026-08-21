/// @docImport "progress_snatcher.dart";
/// @docImport "remote_exception.dart";
library;

import 'dart:async';

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'package:retry/retry.dart';

import '../cron.dart';
import 'priority_queue.dart';
import 'progress_snatcher.dart';
import 'retry_options.dart';
import 'tasks.dart';

/// Container class for a task invocation inside the scheduler.
final class SchedulerPackage<I extends Object?, O extends Object?> {
  final Task<I, O> task;
  final I input;
  final Completer<TaskStatus<I, O>> completer;
  final int priority;
  final bool allowRestoration;
  final Duration? queueExpiration;
  final void Function(TaskProgressBroadcaster progress)? progressBroadcaster;

  DateTime _addedToQueue;

  SchedulerPackage._({
    required this.task,
    required this.input,
    required this.completer,
    required this.priority,
    required this.allowRestoration,
    required this.queueExpiration,
    required this.progressBroadcaster,
    DateTime? addedToQueue,
  }) : _addedToQueue = addedToQueue ?? DateTime.timestamp();

  Map<String, Object?> toJson({bool wasRunning = false}) {
    return {
      "task": task.id,
      "input": input,
      "priority": priority,
      "allowRestoration": allowRestoration,
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

  void _close({required bool silent}) {
    if (!silent && !completer.isCompleted) {
      completer.completeError(
        StateError(
          "Scheduler is closing gracefully, cancelling invocation of '${task.id}' with input '$input'.",
        ),
        StackTrace.current,
      );
    }
  }
}

/// A container class for a delayed task invocation inside the scheduler.
final class SchedulerDelayedPackage<I extends Object?, O extends Object?>
    extends SchedulerPackage<I, O> {
  Timer? _timer;
  final Duration delay;

  final Cron? cron;
  final String? cronId;
  final int? cronReoccurrencesRemaining;
  final bool? cronIsUtc;

  TaskStatus<I, O>? _status;
  final DateTime _addedToWaitList;

  SchedulerDelayedPackage._({
    required super.task,
    required super.input,
    required this.delay,
    required super.completer,
    required super.priority,
    required super.allowRestoration,
    required super.progressBroadcaster,
    this.cron,
    this.cronId,
    this.cronReoccurrencesRemaining,
    this.cronIsUtc,
    DateTime? addedToWaitList,
  }) : _addedToWaitList = addedToWaitList ?? DateTime.timestamp(),
       super._(
         queueExpiration: null,
         addedToQueue: DateTime.fromMillisecondsSinceEpoch(0),
       );

  SchedulerDelayedPackage<I, O> _copyWith({
    required Duration delay,
    required int? cronReoccurrencesRemaining,
  }) => SchedulerDelayedPackage<I, O>._(
    task: task,
    input: input,
    delay: delay,
    completer: Completer(),
    priority: priority,
    allowRestoration: allowRestoration,
    progressBroadcaster: progressBroadcaster,
    cron: cron,
    cronId: cronId,
    cronReoccurrencesRemaining: cronReoccurrencesRemaining,
    cronIsUtc: cronIsUtc,
    addedToWaitList: _addedToWaitList,
  );

  @override
  Map<String, Object?> toJson({bool wasRunning = false}) {
    return {
      ...super.toJson(wasRunning: wasRunning),
      "delay": delay.inMilliseconds,
      "dateTime": _addedToWaitList.add(delay).toIso8601String(),
      "cronId": cronId,
      "cron": cron?.toString(),
      "cronReoccurrencesRemaining": cronReoccurrencesRemaining,
      "cronIsUtc": cronIsUtc,
      "_addedToWaitList": _addedToWaitList.toIso8601String(),
    };
  }

  Timer _startTimer(
    List<SchedulerDelayedPackage> queueWaitList,
    StablePriorityQueue<SchedulerPackage> queue,
    void Function() queueLoop, {
    CronTaskStatus<I>? cronStatus,
    Scheduler? scheduler,
    required bool Function() isClosed,
  }) {
    void unblockCronId() => (cronStatus?._scheduler ?? scheduler)
      ?.._blockedCronIds.remove(cronId)
      .._cronStatuses.remove(cronId);

    _timer = Timer(delay, () async {
      final packageRemoved = queueWaitList.remove(this);
      if (!packageRemoved) {
        completer.completeError(
          StateError(
            "Scheduler delayed invocation of '${task.id}' with input '$input' was not found in the wait list.",
          ),
          StackTrace.current,
        );
        return;
      }

      queue.add(this.._addedToQueue = DateTime.timestamp());
      queueLoop();

      final cronReoccurrencesRemaining = this.cronReoccurrencesRemaining != null
          ? this.cronReoccurrencesRemaining! - 1
          : null;
      if (cron != null &&
          (cronReoccurrencesRemaining == null ||
              cronReoccurrencesRemaining > 0)) {
        try {
          _status = await completer.future;
          await _status!.future.catchError(Error.throwWithStackTrace);
        } catch (_) {}
        if (isClosed() || (cronStatus?._cancelled ?? false)) {
          unblockCronId();
          return;
        }

        final Duration nextDelay;
        try {
          final now = (cronIsUtc ?? false)
              ? DateTime.timestamp()
              : DateTime.now();
          nextDelay = cron!.next(now).delay;
        } on SchedulerOutOfReachException {
          unblockCronId();
          return;
        }

        final newPackage = _copyWith(
          delay: nextDelay,
          cronReoccurrencesRemaining: cronReoccurrencesRemaining,
        );
        queueWaitList.add(newPackage);
        newPackage._startTimer(
          queueWaitList,
          queue,
          queueLoop,
          cronStatus: cronStatus,
          scheduler: scheduler,
          isClosed: isClosed,
        );
      } else if (cron != null) {
        unblockCronId();
      }
    });
    return _timer!;
  }

  @override
  void _close({required bool silent}) {
    _status?.cancel();
    _timer?.cancel();
    return super._close(silent: silent);
  }
}

/// A class that manages the execution of tasks in isolates.
final class CronTaskStatus<I extends Object?> {
  /// Whether the cron task is currently registered or already cancelled.
  bool get isRunning => !_cancelled && _package != null;
  bool _cancelled = false;

  final Scheduler _scheduler;
  SchedulerDelayedPackage<I, void>? get _package =>
      _scheduler._cronPackages.firstWhereOrNull((p) => p.cronId == cronId)
          as SchedulerDelayedPackage<I, void>?;

  /// The unique identifier for the cron task.
  final String cronId;

  /// The task that is being executed by the cron task.
  final Task<I, void> task;

  /// The cron expression driving this task.
  Cron? get cron => _package?.cron;

  /// List of progress broadcasters for the last invocations of the cron task.
  ///
  /// The length of this is restricted to 16, meaning this list has a length of
  /// 16 or less.
  List<TaskProgressBroadcaster> get progress => _progress;
  final List<TaskProgressBroadcaster> _progress = [];

  /// The number of remaining reoccurrences for the cron task.
  ///
  /// This is null if the cron task is set to run indefinitely or if the cron
  /// task has already completed all its reoccurrences.
  int? get reoccurrencesRemaining => _package?.cronReoccurrencesRemaining;

  /// The next scheduled run time for the cron task.
  ///
  /// This is null if the cron task has completed all its reoccurrences or if
  /// the cron task is not currently scheduled to run (e.g., if it has been
  /// cancelled).
  DateTime? get nextRun => _package != null
      ? _package!.delay.isNegative
            ? DateTime.timestamp()
            : _package!._addedToWaitList.add(_package!.delay)
      : null;

  CronTaskStatus({
    required this._scheduler,
    required this.cronId,
    required this.task,
  });

  /// Wraps [progressBroadcaster] so each invocation's broadcaster is also
  /// recorded into [progress], capped at the last 16 invocations.
  void Function(TaskProgressBroadcaster broadcaster) _recordProgress(
    void Function(TaskProgressBroadcaster progress)? progressBroadcaster,
  ) {
    return (broadcaster) {
      progressBroadcaster?.call(broadcaster);
      while (_progress.length >= 16) {
        _progress.removeAt(0);
      }
      _progress.add(broadcaster);
    };
  }

  /// Cancels the cron task, stopping any further reoccurrences.
  ///
  /// This also sends a signal into the task's [TaskProgressCommunicator] so it
  /// can end its execution gracefully. See [TaskStatus.cancel] for more
  /// information.
  void cancel() {
    _cancelled = true;
    final package = _package;
    if (package != null) {
      package._close(silent: true);
      _scheduler._queueWaitList.remove(package);
      _scheduler._queue.remove(package);
    }
    _scheduler._blockedCronIds.remove(cronId);
    _scheduler._cronStatuses.remove(cronId);
  }

  @override
  String toString() {
    final buffer = StringBuffer()
      ..write("CronTaskStatus(")
      ..write("isRunning: $isRunning")
      ..write(", cronId: $cronId")
      ..write(", task: $task")
      ..write(", progress: $progress")
      ..write(", reoccurrencesRemaining: $reoccurrencesRemaining")
      ..write(", nextRun: $nextRun")
      ..write(")");
    return buffer.toString();
  }
}

/// A configuration class for the [Scheduler].
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
    if (simultaneousInvocations <= 0) {
      throw ArgumentError.value(
        simultaneousInvocations,
        "simultaneousInvocations",
        "simultaneousInvocations must be greater than 0",
      );
    } else if (cullingInterval <= Duration.zero) {
      throw ArgumentError.value(
        cullingInterval,
        "cullingInterval",
        "cullingInterval must be greater than 0",
      );
    } else if (cullingIdle <= Duration.zero || cullingIdle < cullingInterval) {
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
/// for a more detailed usage example and consult the documentation for help.
class Scheduler {
  bool _closed = false;

  final TaskBundle _taskBundle;
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

  /// Scheduled or running cron tasks that are currently in the scheduler.
  List<CronTaskStatus> get cronTasks => List.unmodifiable(
    _cronPackages.map(
      (p) => _cronStatuses[p.cronId!] ??= CronTaskStatus(
        scheduler: this,
        cronId: p.cronId!,
        task: p.task,
      ),
    ),
  );

  /// The raw wait-list/queue/running packages that back a cron chain, used
  /// internally by [CronTaskStatus] instead of the [CronTaskStatus]-typed
  /// [cronTasks] getter.
  List<SchedulerDelayedPackage> get _cronPackages => [
    ..._runningPackages.values.whereType<SchedulerDelayedPackage>(),
    ..._queue.toList().whereType<SchedulerDelayedPackage>(),
    ..._queueWaitList,
  ].where((p) => p.cron != null).toList();

  final Map<String, CronTaskStatus> _cronStatuses = {};
  final List<String> _blockedCronIds = [];

  /// The current queue of tasks that are waiting to be executed.
  List<SchedulerPackage> get queue => List.unmodifiable(_queue.toList());
  late final StablePriorityQueue<SchedulerPackage> _queue;
  int _queueLockState = 0;

  /// The current queue of tasks that are waiting to be executed after a delay.
  List<SchedulerDelayedPackage> get queueWaitList =>
      List.unmodifiable(_queueWaitList);
  final _queueWaitList = <SchedulerDelayedPackage>[];

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
  final Map<int, SchedulerPackage> _runningPackages = {};
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
  /// throwing an exception to the running invocations' futures. Note that this
  /// could lead to memory leaks if the invocations are not handled properly.
  ///
  /// The [graceful] flag can be set to false to immediately terminate all
  /// running invocations without waiting for them to complete. If set to true,
  /// the scheduler will wait for all running invocations to complete before
  /// closing. The [gracefulTimeout] can be set to limit the time the scheduler
  /// will wait for running invocations to complete before closing.
  ///
  /// The [saveRestorableState] callback can be provided to save the current
  /// state of the scheduler before closing. It is called first, before any
  /// cancellation signal is sent to running invocations and before the queue
  /// or wait list are touched, so [restorableState] reflects everything that
  /// was running, queued, or delayed/cron-waiting at the moment [close] was
  /// called — including invocations that go on to exit early because they
  /// cooperate with the graceful cancellation below.
  Future<void> close({
    bool silent = false,
    bool graceful = true,
    Duration? gracefulTimeout = const Duration(seconds: 30),
    bool kill = false,
    FutureOr<void> Function()? saveRestorableState,
  }) async {
    if (_closed) return;
    _closed = true;

    await Future.value(saveRestorableState?.call());

    if (graceful && _completeRunningInvocationsLastLength > 0) {
      runningInvocations.forEach((_, status) => status.cancel());

      var future = completeRunningInvocations;
      if (gracefulTimeout != null) {
        future = future.timeout(gracefulTimeout, onTimeout: () {});
      }
      await future.catchError((_) {});
    }

    for (var package in List.of(_queue.toList())) {
      package._close(silent: silent);
    }
    for (var package in List.of(_queueWaitList.toList())) {
      package._close(silent: silent);
    }
    _queue.clear();
    _queueWaitList.clear();
    if (!silent) {
      for (var package in List.of(_runningPackages.values)) {
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

    _taskBundle.removeListener(_onUpdate);
    await _taskBundle.close(silent: silent, kill: kill);
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
  Map<String, Object> restorableState() {
    final runningPackages = _runningPackages.values;
    final queue = _queue.toList();
    return {
      "config": config.toJson(),
      "taskIds": tasks.map((t) => t.id).toList(),
      "invocations": [
        ...(runningPackages
                .where((p) => p.allowRestoration && p.task.allowRestoration)
                .toList()
              ..removeWhere((p) => p is SchedulerDelayedPackage))
            .map((e) => e.toJson(wasRunning: true)),
        ...(queue
                .where((p) => p.allowRestoration && p.task.allowRestoration)
                .toList()
              ..removeWhere((p) => p is SchedulerDelayedPackage))
            .map((e) => e.toJson(wasRunning: false)),
      ],
      "waitList": [
        ...(runningPackages
                .where((p) => p.allowRestoration && p.task.allowRestoration)
                .toList()
              ..removeWhere((p) => p is! SchedulerDelayedPackage))
            .map((e) => e.toJson(wasRunning: true)),
        ...(queue
                .where((p) => p.allowRestoration && p.task.allowRestoration)
                .toList()
              ..removeWhere((p) => p is! SchedulerDelayedPackage))
            .map((e) => e.toJson(wasRunning: false)),
        ..._queueWaitList
            .where((p) => p.allowRestoration && p.task.allowRestoration)
            .map((e) => e.toJson(wasRunning: false)),
      ],
    };
  }

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
      "waitList": final List<Object?> waitList,
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

      for (final package in invocations) {
        if (package case {
          "task": final String taskId,
          "input": final Object input,
          "priority": final int priority,
          "allowRestoration": final bool allowRestoration,
          "queueExpiration": final int? queueExpiration,
          "wasRunning": final bool wasRunning,
          "_addedToQueue": final String? addedToQueue,
        }) {
          if (!taskIds.contains(taskId)) {
            throw ArgumentError.value(
              state,
              "state",
              "Restorable state contains a task id '$taskId' that is not present in the provided tasks.",
            );
          }

          final task = tasks.singleWhere((t) => t.id == taskId);
          if (!allowRestoration || !task.allowRestoration) {
            throw ArgumentError.value(
              state,
              "state",
              "Restorable state contains a task id '$taskId' that does not allow restoration.",
            );
          }

          scheduler._queue.add(
            SchedulerPackage._(
              task: task,
              input: input,
              completer: Completer(),
              priority: wasRunning ? priority + 100 : priority,
              allowRestoration: allowRestoration,
              queueExpiration: queueExpiration != null
                  ? Duration(milliseconds: queueExpiration)
                  : null,
              progressBroadcaster: null,
              addedToQueue: addedToQueue != null
                  ? DateTime.parse(addedToQueue)
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
      for (final package in waitList) {
        if (package case {
          "task": final String taskId,
          "input": final Object input,
          "priority": final int priority,
          "allowRestoration": final bool allowRestoration,
          "queueExpiration": final int? _,
          "wasRunning": final bool wasRunning,
          "_addedToQueue": final String? _,
          "delay": final int _,
          "dateTime": final String dateTime,
          "cron": final String? cron,
          "cronId": final String? cronId,
          "cronReoccurrencesRemaining": final int? cronReoccurrencesRemaining,
          "cronIsUtc": final bool? cronIsUtc,
          "_addedToWaitList": final String? addedToWaitList,
        }) {
          if (!taskIds.contains(taskId)) {
            throw ArgumentError.value(
              state,
              "state",
              "Restorable state contains a task id '$taskId' that is not present in the provided tasks.",
            );
          }

          if ((cron == null) != (cronId == null)) {
            throw ArgumentError.value(
              state,
              "state",
              "Restorable state contains a wait list entry where 'cron' and 'cronId' are not both null or both non-null.",
            );
          }

          if (cronId != null && scheduler._blockedCronIds.contains(cronId)) {
            throw ArgumentError.value(
              state,
              "state",
              "Restorable state contains a cron task with id '$cronId' that is already running.",
            );
          }

          final task = tasks.singleWhere((t) => t.id == taskId);
          if (!allowRestoration || !task.allowRestoration) {
            throw ArgumentError.value(
              state,
              "state",
              "Restorable state contains a task id '$taskId' that does not allow restoration.",
            );
          }

          final cronParsed = cron != null ? Cron.parse(cron) : null;
          final cronIsUtcResolved = cronIsUtc ?? false;
          final evalTime = DateTime.timestamp();

          var newDelay = DateTime.parse(dateTime).difference(evalTime);
          if (newDelay.isNegative) {
            if (cronParsed != null) {
              try {
                final now = cronIsUtcResolved
                    ? DateTime.timestamp()
                    : DateTime.now();
                newDelay = cronParsed.next(now).delay;
              } on SchedulerOutOfReachException {
                continue;
              }
            } else {
              continue;
            }
          }

          scheduler._queueWaitList.add(
            SchedulerDelayedPackage._(
              task: task,
              input: input,
              delay: newDelay,
              completer: Completer(),
              priority: wasRunning ? priority + 100 : priority,
              allowRestoration: allowRestoration,
              progressBroadcaster: null,
              cron: cronParsed,
              cronId: cronId,
              cronReoccurrencesRemaining: cronReoccurrencesRemaining,
              cronIsUtc: cronIsUtcResolved,
              addedToWaitList: addedToWaitList != null
                  ? DateTime.parse(addedToWaitList)
                  : null,
            ).._startTimer(
              scheduler._queueWaitList,
              scheduler._queue,
              scheduler._queueLoop,
              scheduler: scheduler,
              isClosed: () => scheduler._closed,
            ),
          );
          if (cronId != null) scheduler._blockedCronIds.add(cronId);
        } else {
          throw ArgumentError.value(
            state,
            "state",
            "Invalid wait list format in restorable state.",
          );
        }
      }

      scheduler._queueLoop();
      return scheduler;
    } else {
      throw ArgumentError.value(state, "state", "Invalid restorable state.");
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
  /// ***NOTE:*** If the task's input type is `void`, calling this with a bare
  /// `null` fails at runtime, since `null` infers as `Null`, not `void`. Either
  /// declare the task with `Null` as its input type instead, or specify the
  /// type arguments explicitly, e.g. `invokeNamed<void, void>(...)`. See
  /// [Task] for details.
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
  Future<TaskStatus<I, O>> invokeNamed<I extends Object?, O extends Object?>(
    String taskId,
    I input, {
    int? priority,
    bool allowRestoration = true,
    Duration? queueExpiration,
    bool processQueue = true,
    bool processQueueLockAssert = true,
    void Function(TaskProgressBroadcaster progress)? progressBroadcaster,
    FutureOr<TaskStatus<I, O>> Function(Object error, StackTrace stackTrace)?
    catchError,
  }) async {
    if (!tasks.any((t) => t.id == taskId)) {
      throw ArgumentError(
        "Scheduler does not contain a task with id '$taskId'.",
      );
    }

    late final Task<I, O> task;
    try {
      task = tasks.singleWhere((t) => t.id == taskId) as Task<I, O>;
    } catch (e, s) {
      Error.throwWithStackTrace(castErrorParser(e) ?? e, s);
    }

    return invoke<I, O>(
      task.runtimeType,
      input,
      priority: priority ?? task.metadataObject.priority ?? 0,
      allowRestoration: allowRestoration,
      queueExpiration: queueExpiration,
      processQueue: processQueue,
      processQueueLockAssert: processQueueLockAssert,
      progressBroadcaster: progressBroadcaster,
      catchError: catchError,
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
  /// ***NOTE:*** If the task's input type is `void`, calling this with a bare
  /// `null` fails at runtime, since `null` infers as `Null`, not `void`. Either
  /// declare the task with `Null` as its input type instead, or specify the
  /// type arguments explicitly, e.g. `invoke<void, void>(...)`. See [Task] for
  /// details.
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
  Future<TaskStatus<I, O>> invoke<I extends Object?, O extends Object?>(
    Type taskType,
    I input, {
    int? priority,
    bool allowRestoration = true,
    Duration? queueExpiration,
    bool processQueue = true,
    bool processQueueLockAssert = true,
    void Function(TaskProgressBroadcaster progress)? progressBroadcaster,
    FutureOr<TaskStatus<I, O>> Function(Object error, StackTrace stackTrace)?
    catchError,
  }) async {
    late final Task<I, O> task;
    try {
      task =
          tasks.singleWhere(
                (t) => t.runtimeType == taskType,
                orElse: () => throw ArgumentError(
                  "Scheduler does not contain a task of type '$taskType'.",
                ),
              )
              as Task<I, O>;
    } catch (e, s) {
      Error.throwWithStackTrace(castErrorParser(e) ?? e, s);
    }

    final completer = Completer<TaskStatus<I, O>>();
    _queue.add(
      SchedulerPackage<I, O>._(
        task: task,
        input: input,
        completer: completer,
        priority: priority ?? task.metadataObject.priority ?? 0,
        allowRestoration: allowRestoration,
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

    var future = completer.future;
    if (catchError != null) {
      future = future.catchError(catchError);
    }
    return future;
  }

  /// Invokes a task by its type with the given input after a specified delay
  /// and returns the output asynchronously.
  ///
  /// This function returns the [TaskStatus] of the invocation after waiting for
  /// for [delay] duration.
  ///
  /// ***NOTE:*** If the task's input type is `void`, calling this with a bare
  /// `null` fails at runtime, since `null` infers as `Null`, not `void`. Either
  /// declare the task with `Null` as its input type instead, or specify the
  /// type arguments explicitly, e.g. `delayed<void, void>(...)`. See [Task]
  /// for details.
  Future<TaskStatus<I, O>> delayed<I extends Object?, O extends Object?>(
    Type taskType,
    I input,
    Duration delay, {
    int? priority,
    bool allowRestoration = true,
    void Function(TaskProgressBroadcaster progress)? progressBroadcaster,
    FutureOr<TaskStatus<I, O>> Function(Object error, StackTrace stackTrace)?
    catchError,
  }) async {
    late final Task<I, O> task;
    try {
      task =
          tasks.singleWhere(
                (t) => t.runtimeType == taskType,
                orElse: () => throw ArgumentError(
                  "Scheduler does not contain a task of type '$taskType'.",
                ),
              )
              as Task<I, O>;
    } catch (e, s) {
      Error.throwWithStackTrace(castErrorParser(e) ?? e, s);
    }

    if (delay <= Duration.zero) {
      throw ArgumentError.value(
        delay,
        "delay",
        "Delay must be greater than zero.",
      );
    }

    final completer = Completer<TaskStatus<I, O>>();
    final package = SchedulerDelayedPackage<I, O>._(
      task: task,
      input: input,
      delay: delay,
      completer: completer,
      priority: priority ?? task.metadataObject.priority ?? 0,
      allowRestoration: allowRestoration,
      progressBroadcaster: progressBroadcaster,
    ).._startTimer(_queueWaitList, _queue, _queueLoop, isClosed: () => _closed);
    _queueWaitList.add(package);

    var future = completer.future;
    if (catchError != null) {
      future = future.catchError(catchError);
    }
    return future;
  }

  /// Adds a cron execution of a task to the scheduler with the given input.
  ///
  /// The task will be executed according to the provided [Cron] expression. The
  /// function does not return the output of the task though, the task has to be
  /// of type [Task<dynamic, void>] though. You can use the [cronTasks] getter
  /// to get a list of all currently scheduled or running cron tasks and their
  /// status.
  ///
  /// The next invocation of this cron task invocation will be scheduled after
  /// the previous invocation has completed, meaning if an invocation takes
  /// longer than the cron interval, as many invocations will be skipped until
  /// the next invocation can be scheduled.
  ///
  /// If an invocation fails or is cancelled (e.g. because the scheduler was
  /// closed while it was queued), the cron schedule keeps recurring regardless;
  /// only an unsatisfiable [Cron] expression or exhausting [cronReoccurrences]
  /// stops it.
  ///
  /// [startTime] can be UTC as well as local time, both work. But local time
  /// might cause unexpected behavior when the local time changes (e.g. daylight
  /// saving time). If you want to avoid this, use UTC time for [startTime].
  /// [startTime] uses [DateTime.timestamp] by default.
  ///
  /// ---
  ///
  /// [cronId] can be set to identify the cron task. It us not used by Scheduler
  /// itself, but can be used by your application logic to identify the cron
  /// task. It must be in camelCase and should be unique for each cron task.
  ///
  /// [cronReoccurrences] can be set to limit the number of times the cron task
  /// is executed. If set to null, the cron task will be executed indefinitely.
  ///
  /// [allowRestoration] is set to false by default, meaning that the cron
  /// is not automatically restored when the scheduler is restored from a
  /// restorable state.
  /// Scheduler doesn't want to interfere with application logic, which usually
  /// registers cron tasks on each application start. If you want to restore the
  /// cron anyway, set [allowRestoration] to true.
  ///
  /// ***NOTE:*** If the task's input type is `void`, calling this with a bare
  /// `null` fails at runtime, since `null` infers as `Null`, not `void`. Either
  /// declare the task with `Null` as its input type instead, or specify the
  /// type argument explicitly, e.g. `cron<void>(...)`. See [Task] for details.
  ///
  /// This function is executed synchronously.
  CronTaskStatus<I> cron<I extends Object?>(
    Type taskType,
    I input,
    Cron expression, {
    DateTime? startTime,
    int? priority,
    bool allowRestoration = false,
    required String cronId,
    int? cronReoccurrences,
    void Function(TaskProgressBroadcaster progress)? progressBroadcaster,
    FutureOr<TaskStatus<I, void>> Function(Object error, StackTrace stackTrace)?
    catchError,
  }) {
    late final Task<I, void> task;
    try {
      task =
          tasks.singleWhere(
                (t) => t.runtimeType == taskType,
                orElse: () => throw ArgumentError(
                  "Scheduler does not contain a task of type '$taskType'.",
                ),
              )
              as Task<I, void>;
    } catch (e, s) {
      Error.throwWithStackTrace(castErrorParser(e) ?? e, s);
    }

    final evalTime = DateTime.timestamp();
    if (startTime != null && !startTime.isAfter(evalTime)) {
      throw ArgumentError.value(
        startTime,
        "startTime",
        "Start time must be in the future.",
      );
    }
    final startTimeCanonical = startTime ?? evalTime;

    if (!kCamelCasePattern.hasMatch(cronId)) {
      throw ArgumentError.value(
        cronId,
        "cronId",
        "Cron id must be in camelCase.",
      );
    } else if (_blockedCronIds.any((id) => id == cronId)) {
      throw ArgumentError.value(
        cronId,
        "cronId",
        "Cron id '$cronId' is already in use.",
      );
    }

    if (cronReoccurrences != null && cronReoccurrences <= 0) {
      throw ArgumentError.value(
        cronReoccurrences,
        "reoccurrences",
        "Reoccurrences must be greater than zero.",
      );
    }

    final delay = expression.next(startTimeCanonical).delay;

    _blockedCronIds.add(cronId);
    final status = CronTaskStatus<I>(
      scheduler: this,
      cronId: cronId,
      task: task,
    );
    _cronStatuses[cronId] = status;
    final progressBroadcasterCanonical = status._recordProgress(
      progressBroadcaster,
    );

    final completer = Completer<TaskStatus<I, void>>();
    final package =
        SchedulerDelayedPackage<I, void>._(
          task: task,
          input: input,
          delay: delay,
          completer: completer,
          priority: priority ?? task.metadataObject.priority ?? 0,
          allowRestoration: allowRestoration,
          progressBroadcaster: progressBroadcasterCanonical,
          cron: expression,
          cronId: cronId,
          cronReoccurrencesRemaining: cronReoccurrences,
          cronIsUtc: startTimeCanonical.isUtc,
        ).._startTimer(
          _queueWaitList,
          _queue,
          _queueLoop,
          cronStatus: status,
          isClosed: () => _closed,
        );
    _queueWaitList.add(package);
    return status;
  }

  void _queueLoop() {
    _queueLockState++;
    while (_queue.isNotEmpty &&
        _runningPackages.length < config.simultaneousInvocations) {
      final package = _queue.removeFirstSafe();
      if (package == null) break;
      if (package.queueExpiration != null &&
          DateTime.timestamp().difference(package._addedToQueue) >
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
            _runningPackages.remove(id);
            if (!package.completer.isCompleted) {
              package.completer.completeError(e, s);
            } else {
              Error.throwWithStackTrace(e, s);
            }
            _queueLoop();
          });
    }
  }
}
