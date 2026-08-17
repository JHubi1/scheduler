/// @docImport "progress_snatcher.dart";
library;

import 'dart:async';
// needed for RemoteError, @docImport doesn't work for some reason
// ignore: unused_import
import 'dart:isolate' show RemoteError;

import 'priority_queue.dart';
import 'tasks.dart';

class _SchedulerPackage<I extends Object, O extends Object> {
  final Task<I, O> task;
  final I input;
  final Completer<O> completer;
  final int priority;
  final void Function(TaskProgressBroadcaster progress)? progressBroadcaster;

  _SchedulerPackage({
    required this.task,
    required this.input,
    required this.completer,
    required this.priority,
    required this.progressBroadcaster,
  });
}

class SchedulerConfig {
  final int simultaneousTasks;

  final Duration cullingInterval;
  final Duration cullingIdle;

  const SchedulerConfig({
    this.simultaneousTasks = 5,
    this.cullingInterval = const Duration(seconds: 5),
    this.cullingIdle = const Duration(minutes: 1),
  });

  SchedulerConfig copyWith({
    int? simultaneousTasks,
    Duration? cullingInterval,
    Duration? cullingIdle,
  }) {
    return SchedulerConfig(
      simultaneousTasks: simultaneousTasks ?? this.simultaneousTasks,
      cullingInterval: cullingInterval ?? this.cullingInterval,
      cullingIdle: cullingIdle ?? this.cullingIdle,
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
/// final result = await scheduler.invoke(EchoTask, "hello");
/// print(result); // prints "hello"
/// ```
///
/// See [`example/scheduler_example.dart`](https://github.com/JHubi1/scheduler/blob/main/example/scheduler_example.dart)
/// for a more detailed usage example and consult the documentation
/// (`dart doc.`) for help.
class Scheduler {
  final TaskBundle _taskBundle;
  late final StablePriorityQueue<_SchedulerPackage> _queue;

  SchedulerConfig _config;
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
  ///
  /// The values are task ids, which can be looked up in [tasks] to get their
  /// metadata and other information.
  Map<int, String> get runningInvocations => _taskBundle.runningInvocations;

  Scheduler(Iterable<Task> tasks, {this._config = const SchedulerConfig()})
    : _taskBundle = TaskBundle(tasks, startCulling: false) {
    _queue = StablePriorityQueue(
      postponeExecution: (package) =>
          !package.task.allowSimultaneous &&
          _taskBundle.runningInvocations.values.contains(package.task.id),
    );
    _taskBundle
      ..addListener(_onUpdate)
      ..startCulling(
        interval: config.cullingInterval,
        idleTime: config.cullingIdle,
      );
  }

  void _onUpdate(String taskId) => _queueLoop();

  /// Closes all running task instances in the scheduler and terminates their
  /// isolates.
  Future<void> close() async {
    _taskBundle.removeListener(_onUpdate);
    await _taskBundle.close();
  }

  /// Invokes a task by its id with the given input and returns the output
  /// asynchronously.
  ///
  /// {@macro com.jhubi1.scheduler.TaskBundle.invoke}
  ///
  /// Set [processQueue] to false to prevent the scheduler from automatically
  /// starting the queue loop after adding the task to the queue. This can be
  /// useful if you want to add multiple tasks to the queue before starting the
  /// loop. *Careful:* If the last call to [invoke] has [processQueue] set to
  /// false, this function will not return until the queue loop has been started
  /// again and the task has been executed.
  ///
  /// ---
  ///
  /// Example usage:
  ///
  /// ```dart
  /// final scheduler = Scheduler([EchoTask()]);
  /// final result = await scheduler.invokeNamed("echoTask", "hello");
  /// print(result); // prints "hello"
  /// ```
  Future<O> invokeNamed<I extends Object, O extends Object>(
    String taskId,
    I input, {
    int? priority,
    bool processQueue = true,
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
      processQueue: processQueue,
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
  /// loop. *Careful:* If the last call to [invoke] has [processQueue] set to
  /// false, this function will not return until the queue loop has been started
  /// again and the task has been executed.
  ///
  /// ---
  ///
  /// Example usage:
  ///
  /// ```dart
  /// final scheduler = Scheduler([EchoTask()]);
  /// final result = await scheduler.invoke(EchoTask, "hello");
  /// print(result); // prints "hello"
  /// ```
  Future<O> invoke<I extends Object, O extends Object>(
    Type taskType,
    I input, {
    int? priority,
    bool processQueue = true,
    void Function(TaskProgressBroadcaster progress)? progressBroadcaster,
  }) async {
    final task =
        tasks.singleWhere(
              (t) => t.runtimeType == taskType,
              orElse: () => throw ArgumentError(
                "Scheduler does not contain a task of type '$taskType'.",
              ),
            )
            as Task<I, O>;

    final completer = Completer<O>();
    _queue.add(
      _SchedulerPackage<I, O>(
        task: task,
        input: input,
        completer: completer,
        priority: priority ?? task.metadataObject.priority ?? 0,
        progressBroadcaster: progressBroadcaster,
      ),
    );

    if (processQueue) _queueLoop();
    return completer.future;
  }

  void _queueLoop() {
    while (_queue.isNotEmpty &&
        _taskBundle.runningInvocations.length < config.simultaneousTasks) {
      final package = _queue.removeFirstSafe();
      if (package == null) break;

      _taskBundle
          .invokeNamed(
            package.task.id,
            package.input,
            progressBroadcaster: package.progressBroadcaster,
          )
          .then((result) {
            package.completer.complete(result);
          })
          .catchError((e, s) {
            package.completer.completeError(e, s);
          });
    }
  }
}
