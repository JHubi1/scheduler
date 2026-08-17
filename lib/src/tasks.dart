/// @docImport "scheduler_base.dart";
library;

import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'progress_snatcher.dart';

int _idCounter = 0;

/// A class that represents the progress of a task.
class TaskProgress {
  /// The progress of the task, represented as a value between 0.0 and 1.0, -1.0,
  /// or `null`
  ///
  /// The value should be between 0.0 and 1.0 to indicate a completion in
  /// percentage. 0.0 means the task has just started, 1.0 means the task is
  /// complete or almost complete.
  ///
  /// A value of -1.0 indicates that the progress is indeterminate, meaning that
  /// the task is running but the progress cannot be determined. In a UI, this
  /// may be represented by a spinning progress indicator.
  ///
  /// A value of `null` indicates that the progress is unknown, meaning that the
  /// task is running but the progress is not being tracked. In a UI, this may
  /// be represented by not showing any progress indicator at all.
  final double? progress;

  /// The current step of the task, represented as a string.
  ///
  /// This should be in [steps] if provided. If not provided, it can be any
  /// string that describes the current step of the task.
  final String? step;

  /// A list of all steps of the task.
  ///
  /// Each step should be a string that describes a step in the task. This can
  /// be used to provide a more detailed progress indication in a UI.
  ///
  /// The step names should be unique and should not be empty. They're shown in
  /// the order they are provided in the list.
  final List<String>? steps;

  /// An additional message about the task's progress.
  ///
  /// This can be used to provide more information about the task's progress,
  /// such as an overview over gathered information.
  final String? message;

  TaskProgress({this.progress, this.step, this.steps, this.message}) {
    if (progress != null &&
        progress != -1.0 &&
        (progress! < 0.0 || progress! > 1.0)) {
      throw ArgumentError(
        "Progress must be between 0.0 and 1.0, or -1.0 for indeterminate progress.",
        "progress",
      );
    }
    if (step != null && steps != null && !steps!.contains(step)) {
      throw ArgumentError("Step must be one of the provided steps.", "step");
    }
  }

  TaskProgress copyWith({
    double? Function()? progress,
    String? Function()? step,
    List<String>? Function()? steps,
    String? Function()? message,
  }) => TaskProgress(
    progress: progress == null ? this.progress : progress.call(),
    step: step == null ? this.step : step.call(),
    steps: steps == null ? this.steps : steps.call(),
    message: message == null ? this.message : message.call(),
  ).._parent ??= _parent;

  factory TaskProgress.indeterminate({
    String? step,
    List<String>? steps,
    String? message,
  }) {
    return TaskProgress(
      progress: -1.0,
      step: step,
      steps: steps,
      message: message,
    );
  }

  factory TaskProgress.unknown({
    String? step,
    List<String>? steps,
    String? message,
  }) {
    return TaskProgress(
      progress: null,
      step: step,
      steps: steps,
      message: message,
    );
  }

  Map<String, Object?> toJson() => {
    "progress": progress,
    "step": step,
    "steps": steps,
    "message": message,
  };

  factory TaskProgress.fromJson(Map<String, Object?> json) {
    return TaskProgress(
      progress: json["progress"] as double?,
      step: json["step"] as String?,
      steps: (json["steps"] as List<Object?>?)?.cast<String>(),
      message: json["message"] as String?,
    );
  }

  @override
  String toString() {
    if (this == TaskProgress.unknown()) {
      return "TaskProgress.unknown()";
    } else if (this == TaskProgress.indeterminate()) {
      return "TaskProgress.indeterminate()";
    } else {
      final buffer = StringBuffer()
        ..write("TaskProgress(")
        ..write("progress: $progress");
      if (step != null) {
        buffer.write(", step: $step");
      }
      if (steps != null) {
        buffer.write(", steps: $steps");
      }
      if (message != null) {
        buffer.write(", message: $message");
      }
      buffer.write(")");
      return buffer.toString();
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! TaskProgress) return false;
    return progress == other.progress &&
        step == other.step &&
        const ListEquality<String>().equals(steps, other.steps) &&
        message == other.message;
  }

  @override
  int get hashCode => Object.hash(
    progress,
    step,
    const ListEquality<String>().hash(steps),
    message,
  );

  TaskProgressCommunicator? _parent;
  void _setParent(TaskProgressCommunicator parent) => _parent = parent;
  void _removeParent() => _parent = null;

  /// Sets this as the current progress of the task in the parent
  /// [TaskProgressCommunicator].
  ///
  /// Note that this method only works inside a [Task] implementation. Calling
  /// this method outside of a [Task] will throw a [StateError].
  void set() {
    if (_parent == null) {
      throw StateError(
        "TaskProgressCommunicator is not attached to a parent. This method can only be called inside a Task implementation.",
      );
    }
    _parent!.set(this);
  }
}

/// A class that allows a task to communicate its progress back to the caller.
class TaskProgressCommunicator {
  TaskProgress _progress = TaskProgress.unknown();
  final bool Function(TaskProgress progress) _setProgress;

  /// Gets the current progress of the task.
  ///
  /// See [TaskProgress] for more information about the progress values.
  TaskProgress get() => _progress.copyWith().._setParent(this);

  /// Sets the current progress of the task.
  ///
  /// The [progress] parameter is the new progress of the task. It should be a
  /// [TaskProgress] object that describes the current progress of the task.
  ///
  /// See [TaskProgress] for more information about the progress values.
  void set(TaskProgress progress) {
    if (_setProgress(progress)) _progress = progress;
  }

  TaskProgressCommunicator._({required this._setProgress});

  @override
  String toString() {
    final buffer = StringBuffer()
      ..write("TaskProgressCommunicator(")
      ..write("progress: $_progress")
      ..write(")");
    return buffer.toString();
  }
}

/// A class that allows a task to broadcast its progress to multiple listeners.
class TaskProgressBroadcaster {
  bool _closed = false;

  TaskProgress _progress = TaskProgress.unknown();
  TaskProgress get progress => _progress.copyWith();

  final int invocationId;
  TaskProgressBroadcaster({required this.invocationId});

  late final _controller = StreamController<TaskProgress>.broadcast(sync: true)
    ..stream.listen((p) => _progress = p);
  final Map<void Function(TaskProgress), StreamSubscription> _listeners = {};

  void addListener(void Function(TaskProgress p) listener) => _closed
      ? null
      : _listeners[listener] = _controller.stream.listen(listener.call);
  void removeListener(void Function(TaskProgress p) listener) =>
      _closed ? null : _listeners.remove(listener)?.cancel();

  late final _closureController = StreamController.broadcast(sync: true);
  final Map<void Function(), StreamSubscription> _closureListeners = {};

  void addClosureListener(void Function() listener) => _closed
      ? null
      : _closureListeners[listener] = _closureController.stream.listen(
          (_) => listener.call(),
        );
  void removeClosureListener(void Function() listener) =>
      _closed ? null : _closureListeners.remove(listener)?.cancel();

  void _close() {
    if (_closed) return;
    _closed = true;

    _closureController.add(null);
    for (final subscription in _closureListeners.values.toList()) {
      subscription.cancel();
    }
    _closureController.close();

    for (final subscription in _listeners.values.toList()) {
      subscription.cancel();
    }
    _controller.close();
  }
}

class TaskMetadata {
  final int? priority;
  final String? version;

  final String? author;
  final String? maintainer;
  final String? description;
  final String? license;

  final Uri? repository;
  final Uri? documentation;
  final Uri? homepage;

  final List<String>? keywords;
  final Map<String, String> additionalMetadata;

  TaskMetadata._({
    this.priority,
    this.version,
    this.author,
    this.maintainer,
    this.description,
    this.license,
    this.repository,
    this.documentation,
    this.homepage,
    this.keywords,
    this.additionalMetadata = const {},
  });

  factory TaskMetadata._fromMap(Map<String, String> map) {
    final data = Map.of(map);
    return TaskMetadata._(
      priority: int.tryParse(data.remove("priority") ?? ""),
      version: data.remove("version"),
      author: data.remove("author"),
      maintainer: data.remove("maintainer"),
      description: data.remove("description"),
      license: data.remove("license"),
      repository: Uri.tryParse(data.remove("repository") ?? ""),
      documentation: Uri.tryParse(data.remove("documentation") ?? ""),
      homepage: Uri.tryParse(data.remove("homepage") ?? ""),
      keywords: data
          .remove("keywords")
          ?.split(",")
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(),
      additionalMetadata: data,
    );
  }
}

/// A class that represents a task that can be executed in a separate isolate.
///
/// The [Task] class is a generic class that takes three type parameters:
/// - [I]: The type of the input that the task will receive.
/// - [O]: The type of the output that the task will produce.
///
/// The [Task] class is designed to be subclassed by concrete task
/// implementations. Subclasses must implement the [id] and [invoke] methods.
///
/// Make sure to set [allowSimultaneous] appropriately for your task. Depending
/// on your way of handling state, you may want to allow multiple invocations of
/// the task to run simultaneously. Defaults to `false`.
///
/// ***NOTE:*** A task should not cause failures if it gets closed unexpectedly
/// while it is running and should be able to run again after being closed. A
/// corrupted state from the last should be recovered in the following run.
abstract class Task<I extends Object, O extends Object> {
  bool _closed = false;

  /// The unique identifier for the task.
  ///
  /// The id must be in camelCase format. The format is checked during the
  /// construction of the Task instance.
  ///
  /// This id is used to identify the task in the system and compare it to other
  /// tasks. If two tasks have the same id, they are considered to be the same
  /// task, even if they have different implementations.
  ///
  /// This should be the same as the class name of the task, but in camelCase
  /// format. For example, if the class name is `JsonDecoder`, the id should
  /// have a value of `jsonDecoder`.
  String get id;

  /// The display name of the task.
  ///
  /// This is an optional human-readable name for the task. If provided, it
  /// should be non-empty. If not provided, it will default to `null`.
  ///
  /// This can be used to provide a more user-friendly name for the task that
  /// may be shown in a UI or used for documentation purposes.
  String? get displayName => null;

  /// Whether multiple invocations of the task are allowed to run
  /// simultaneously.
  ///
  /// If `true`, multiple invocations of the task may run at the same time. If
  /// `false`, only one invocation of the task may run at a time.
  ///
  /// This field may be used by [TaskBundle] and similar to determine whether to
  /// allow a new invocation of the task or not.
  bool get allowSimultaneous => false;

  /// Metadata about the task, such as version, author, etc.
  ///
  /// This can be used to provide additional information about the task that
  /// may be shown in a UI or used for documentation purposes.
  ///
  /// Standardized keys for metadata include:
  /// - `priority`: Used by [Scheduler], etc. to determine fallback priority.
  /// - `version`: The version of the task.
  /// - `author`: The author of the task.
  /// - `maintainer`: The maintainer of the task.
  /// - `description`: A brief description of the task.
  /// - `license`: The license under which the task is released.
  /// - `repository`: URL where the source code of the task can be found.
  /// - `documentation`: URL where documentation doe the task can be found.
  /// - `homepage`: URL for the homepage of the task.
  ///   Shouldn't be same as `repository` or `documentation`.
  /// - `keywords`: Comma-separated keywords describing the task.
  ///
  /// All fields are optional. If they're provided, they must be non-empty.
  ///
  /// [metadataObject] is a convenience getter that converts this map into a
  /// [TaskMetadata] object, making all fields accessible in a structured way.
  Map<String, String> get metadata => const {};

  /// Returns a [TaskMetadata] object that contains the metadata of the task in
  /// a structured format.
  ///
  /// This is a convenience getter that converts the [metadata] map into a
  /// [TaskMetadata] object. It can be used to access the metadata in a more
  /// structured way, with proper types and default values.
  TaskMetadata get metadataObject => TaskMetadata._fromMap(metadata);

  @override
  String toString() {
    final buffer = StringBuffer()..write("Task(id: ${jsonEncode(id)}");
    if (displayName != null) {
      buffer.write(", displayName: ${jsonEncode(displayName)}");
    }
    if (allowSimultaneous) {
      buffer.write(", allowMultipleInstances: $allowSimultaneous");
    }
    if (metadata.isNotEmpty) {
      buffer.write(", metadata: ${jsonEncode(metadata)}");
    }
    buffer.write(")");
    return buffer.toString();
  }

  Task() {
    if (!RegExp(r"^[a-z][a-z0-9]*(?:[A-Z][a-z0-9]+)*$").hasMatch(id)) {
      throw ArgumentError("Task id must be in camelCase format.", "id");
    }
    assert(
      displayName == null || displayName!.isNotEmpty,
      "Task display name must be non-empty if provided.",
    );
    assert(
      metadata.values.every((value) => value.isNotEmpty),
      "Task metadata values must be non-empty if provided.",
    );
  }

  /// Creates a new instance of the task in a separate isolate.
  ///
  /// The returned [TaskInstance] can be used to invoke the task with input and
  /// receive the output asynchronously.
  @nonVirtual
  Future<TaskInstance<I, O>> spawn() async {
    final initPort = RawReceivePort();
    final connection = Completer<(ReceivePort, SendPort)>.sync();
    initPort.handler = (initialMessage) {
      final commandPort = initialMessage as SendPort;
      connection.complete((
        ReceivePort.fromRawReceivePort(initPort),
        commandPort,
      ));
    };

    Isolate isolate;
    try {
      isolate = await Isolate.spawn(_startRemoteIsolate, initPort.sendPort);
    } on Object {
      initPort.close();
      rethrow;
    }

    final (ReceivePort responses, SendPort commands) = await connection.future;

    return TaskInstance<I, O>._(
      responses: responses,
      commands: commands,
      isolate: isolate,
      task: this,
    );
  }

  @visibleForOverriding
  FutureOr<O> invoke(I input, TaskProgressCommunicator progress);

  void _handleCommandsToIsolate(ReceivePort receivePort, SendPort sendPort) =>
      receivePort.listen((message) async {
        if (message == "shutdown") {
          receivePort.close();
          _closed = true;
          sendPort.send("shutdown_ack");
          return;
        }

        final (int id, I input) = message as (int, I);
        try {
          final output = await Future.value(
            invoke(
              input,
              TaskProgressCommunicator._(
                setProgress: (progress) {
                  if (_closed) return false;
                  sendPort.send((
                    id,
                    progress: progress.copyWith().._removeParent(),
                  ));
                  return true;
                },
              ),
            ),
          ).catchError(Error.throwWithStackTrace);
          if (_closed) return;
          sendPort.send((id, output));
        } catch (e, s) {
          if (_closed) return;
          sendPort.send((id, RemoteError(e.toString(), s.toString())));
        }
      });

  void _startRemoteIsolate(SendPort sendPort) {
    final receivePort = ReceivePort();
    sendPort.send(receivePort.sendPort);
    _handleCommandsToIsolate(receivePort, sendPort);
  }

  /// Converts this task into a [TaskBundle] containing only this task.
  TaskBundle toBundle() => TaskBundle([this]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Task) return false;
    return id == other.id;
  }

  @override
  int get hashCode => id.hashCode;
}

final class TaskInstance<I extends Object, O extends Object> {
  final Completer<void> _closed = Completer<void>.sync();
  final Map<int, Completer<O>> _activeRequests = {};
  final Map<int, TaskProgressBroadcaster> _activeProgressBroadcasters = {};

  final SendPort _commands;
  final ReceivePort _responses;
  final Isolate _isolate;
  final Task<I, O> _task;

  TaskInstance._({
    required this._commands,
    required this._responses,
    required this._isolate,
    required this._task,
  }) {
    _responses.listen(_handleResponsesFromIsolate);
  }

  @override
  String toString() {
    final buffer = StringBuffer()..write("TaskInstance(task: $_task)");
    return buffer.toString();
  }

  /// Invokes the task with the given input and returns after receiving the
  /// output asynchronously.
  ///
  /// The [progressBroadcaster] parameter will be called with a
  /// [TaskProgressBroadcaster] that can be used to listen to progress updates.
  /// By default, the [ProgressSnatcher] singleton will automatically be used.
  ///
  /// If the task instance has been closed before, this method will throw a
  /// [StateError]. If the task instance is closed while waiting for a response,
  /// this method will also throw a [StateError].
  ///
  /// If the [Task.invoke] method throws an error, this method will throw a
  /// [RemoteError] with the error converted to a string and the stack trace
  /// from the isolate.
  (int, Future<O>) invoke(
    I input, {
    void Function(TaskProgressBroadcaster progress)? progressBroadcaster,
  }) {
    if (_closed.isCompleted) {
      throw StateError("Cannot send inputs to a closed TaskInstance.");
    }

    final id = _idCounter++;
    final completer = Completer<O>.sync();
    final broadcaster = TaskProgressBroadcaster(invocationId: id);

    _activeRequests[id] = completer;
    _activeProgressBroadcasters[id] = broadcaster;
    _commands.send((id, input));

    runZonedGuarded(
      () => (progressBroadcaster ?? ProgressSnatcher.instance.auto).call(
        broadcaster,
      ),
      Error.throwWithStackTrace,
    );
    return (id, completer.future.catchError(Error.throwWithStackTrace));
  }

  void _handleResponsesFromIsolate(dynamic message) {
    if (message == "shutdown_ack") {
      _closed.complete();
      return;
    } else if (message case (
      final int id,
      progress: final TaskProgress progress,
    )) {
      if (!_activeProgressBroadcasters.containsKey(id)) return;
      _activeProgressBroadcasters[id]!._controller.add(progress);
      return;
    }

    final (int id, Object response) = message as (int, Object);
    if (!_activeRequests.containsKey(id)) return;
    final completer = _activeRequests.remove(id)!;
    _activeProgressBroadcasters.remove(id)?._close();

    if (response case final RemoteError error) {
      completer.completeError(error, error.stackTrace);
    } else {
      completer.complete(response as O);
    }
  }

  /// Closes the task instance and terminates the isolate.
  ///
  /// If there are any active requests when this method is called, they will be
  /// completed with a [StateError] indicating that the task instance was closed
  /// before a response was received.
  Future<void> close() async {
    if (!_closed.isCompleted) {
      _commands.send("shutdown");
      await _closed.future;

      for (final completer in _activeRequests.values) {
        completer.completeError(
          StateError("TaskInstance closed before response was received."),
          StackTrace.current,
        );
      }
      for (final broadcaster in _activeProgressBroadcasters.values) {
        broadcaster._close();
      }

      _responses.close();
      _isolate.kill(priority: Isolate.immediate);
    }
  }
}

/// A registry of tasks that can be invoked by their id or type.
///
/// The [TaskBundle] class is a collection of tasks that can be invoked by their
/// unique id or by their type. It manages the lifecycle of task instances and
/// provides a convenient way to invoke tasks without having to manage
/// individual task instances.
///
/// It is recommended to use a single [TaskBundle] instance for the entire
/// application, rather than creating multiple instances. This allows for better
/// resource management and avoids unnecessary overhead from creating multiple
/// task instances for the same task.
///
/// Culling should be enabled for performance reasons, and it is by default. See
/// [startCulling] for more information. To disable culling, pass
/// `startCulling: false` to the [TaskBundle.new] constructor.
final class TaskBundle {
  bool _closed = false;

  /// The tasks that are registered in the bundle.
  final Set<Task> tasks;

  /// A list of task ids that are currently running in the bundle.
  List<String> get running =>
      List.unmodifiable(_running.map((t) => t._task.id));
  final List<TaskInstance> _running = [];

  Map<int, String> get runningInvocations => Map.unmodifiable(
    _runningInvocations.map((key, value) => MapEntry(key, value.id)),
  );
  final Map<int, Task> _runningInvocations = {};

  TaskBundle(Iterable<Task> tasks, {bool startCulling = true})
    : assert(
        tasks.toSet().length == tasks.length,
        "TaskBundle must not contain tasks with duplicate ids.",
      ),
      tasks = Set.unmodifiable(tasks.toSet()) {
    if (startCulling) this.startCulling();
  }

  /// Invokes a task by its id with the given input and returns the output
  /// asynchronously.
  ///
  /// If the task id is not found in the bundle, this method will throw an
  /// [ArgumentError].
  ///
  /// See [invoke] for more information about the parameters.
  Future<O> invokeNamed<I extends Object, O extends Object>(
    String taskId,
    I input, {
    void Function(TaskProgressBroadcaster progress)? progressBroadcaster,
  }) async {
    if (_closed) {
      throw StateError("Cannot invoke tasks on a closed TaskBundle.");
    }
    if (!tasks.any((t) => t.id == taskId)) {
      throw ArgumentError(
        "TaskBundle does not contain a task with id '$taskId'.",
      );
    }

    final task = tasks.singleWhere((t) => t.id == taskId) as Task<I, O>;
    return invoke(
      task.runtimeType,
      input,
      progressBroadcaster: progressBroadcaster,
    );
  }

  /// Invokes a task by its type with the given input and returns the output
  /// asynchronously.
  ///
  /// {@template com.jhubi1.scheduler.TaskBundle.invoke}
  ///
  /// The [taskType] parameter is the type of the task to invoke. It must be part
  /// of the current [tasks] in the bundle.
  ///
  /// The [progressBroadcaster] parameter will be called with a
  /// [TaskProgressBroadcaster] that can be used to listen to progress updates.
  /// By default, the [ProgressSnatcher] singleton will automatically be used.
  ///
  /// ---
  ///
  /// If the task type is not found in the bundle, this method will throw an
  /// [ArgumentError].
  ///
  /// If the task instance has been closed before, this method will throw a
  /// [StateError]. If the task instance is closed while waiting for a response,
  /// this method will also throw a [StateError].
  ///
  /// If the [Task.invoke] method throws an error, this method will throw a
  /// [RemoteError] with the error converted to a string and the stack trace
  /// from the isolate.
  ///
  /// {@endtemplate}
  ///
  /// ---
  ///
  /// Example usage:
  ///
  /// ```dart
  /// final result = TaskBundle([MyTask()]).invoke(MyTask, "input");
  /// ```
  Future<O> invoke<I extends Object, O extends Object>(
    Type taskType,
    I input, {
    void Function(TaskProgressBroadcaster progress)? progressBroadcaster,
  }) async {
    if (_closed) {
      throw StateError("Cannot invoke tasks on a closed TaskBundle.");
    }

    final task =
        tasks.singleWhere(
              (t) => t.runtimeType == taskType,
              orElse: () => throw ArgumentError(
                "TaskBundle does not contain a task of type '$taskType'.",
              ),
            )
            as Task<I, O>;
    if (!task.allowSimultaneous && _runningInvocations.values.contains(task)) {
      throw StateError(
        "Task '${task.id}' does not allow multiple instances and is already running.",
      );
    }

    final tmpId = -task.id.hashCode.abs() - 1;
    _runningInvocations[tmpId] = task;

    var instance =
        _running.singleWhereOrNull(
              (i) => i._task == task && !i._closed.isCompleted,
            )
            as TaskInstance<I, O>?;
    // instance ??= await task.spawn();
    if (instance == null) {
      instance = await task.spawn();
      _running.add(instance);
    }

    int? id;
    O result;
    try {
      Future<O> data;
      (id, data) = instance.invoke(
        input,
        progressBroadcaster: progressBroadcaster,
      );

      _runningInvocations[id] = task;
      _runningInvocations.remove(tmpId);
      result = await data;
    } finally {
      if (id != null) _runningInvocations.remove(id);
      _runningInvocations.remove(tmpId);
      _update.add(task.id);
    }

    return result;
  }

  final _update = StreamController<String>.broadcast(sync: true);
  final Map<void Function(String), StreamSubscription<void>> _listeners = {};
  void addListener(void Function(String id) listener) => _closed
      ? null
      : _listeners[listener] = _update.stream.listen(listener.call);
  void removeListener(void Function(String id) listener) =>
      _closed ? null : _listeners.remove(listener)?.cancel();

  /// Closes all running task instances in the bundle and terminates their
  /// isolates.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;

    if (_cullingTimer != null) stopCulling();
    for (final subscription in _listeners.values.toList()) {
      await subscription.cancel();
    }
    for (final instance in List.of(_running)) {
      await instance.close();
    }
    _update.close();
  }

  Timer? _cullingTimer;
  final Map<TaskInstance, DateTime> _cullingSuspects = {};
  bool get isCulling => _cullingTimer != null;

  /// Starts the automatic culling of idle task instances in the bundle.
  ///
  /// The [interval] parameter specifies how often the bundle should check for
  /// idle task instances.
  ///
  /// The [idleTime] parameter specifies how long a task instance must be idle
  /// before it is culled, i.e., closed and removed from the bundle.
  void startCulling({
    Duration interval = const Duration(seconds: 10),
    Duration idleTime = const Duration(minutes: 1),
  }) {
    _cullingTimer = Timer.periodic(interval, (_) async {
      final toRemove = <TaskInstance>[];
      for (final instance in _running) {
        if (instance._closed.isCompleted ||
            (instance._activeRequests.isEmpty &&
                _cullingSuspects[instance] != null &&
                DateTime.now().difference(_cullingSuspects[instance]!) >
                    idleTime)) {
          toRemove.add(instance);
        }

        if (instance._activeRequests.isEmpty) {
          _cullingSuspects[instance] ??= DateTime.now();
        } else {
          _cullingSuspects.remove(instance);
        }
      }
      for (final instance in toRemove) {
        await instance.close().catchError(Error.throwWithStackTrace);
        _running.remove(instance);
        _cullingSuspects.remove(instance);
      }
    });
  }

  /// Stops the automatic culling of idle task instances in the bundle.
  ///
  /// See [startCulling] for more information about culling.
  void stopCulling() {
    _cullingTimer?.cancel();
    _cullingTimer = null;
    _cullingSuspects.clear();
  }
}
