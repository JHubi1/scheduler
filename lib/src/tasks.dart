/// @docImport "scheduler_base.dart";
library;

import 'dart:async';
import 'dart:convert';
import 'dart:isolate' hide RemoteError;

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'package:retry/retry.dart';
import 'progress_snatcher.dart';
import 'remote_exception.dart';
import 'retry_options.dart';

int _idCounter = 0;

/// A class that represents the progress of a task.
final class TaskProgress {
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

  factory TaskProgress.complete({
    String? step,
    List<String>? steps,
    String? message,
  }) {
    return TaskProgress(
      progress: 1.0,
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
    } else if (this == TaskProgress.complete()) {
      return "TaskProgress.complete()";
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
final class TaskProgressCommunicator {
  TaskProgress _progress = TaskProgress.unknown();
  final bool Function(TaskProgress progress) _setProgress;
  final bool Function() _getIsClosed;

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

  /// Returns `true` if the application has requested the closure of the
  /// invocation.
  ///
  /// This should be honored and checked after every major asynchronous
  /// operation in the task. If this returns `true`, the task should stop its
  /// work and return as soon as possible. The task should not throw an
  /// exception or return an error, but should return a normal result if,
  /// possible, or a default value if not.
  bool get isClosed => _getIsClosed();

  TaskProgressCommunicator._({
    required this._setProgress,
    required this._getIsClosed,
  });

  @override
  String toString() {
    final buffer = StringBuffer()
      ..write("TaskProgressCommunicator(")
      ..write("progress: $_progress")
      ..write(", isClosed: $isClosed")
      ..write(")");
    return buffer.toString();
  }
}

/// A class that allows a task to broadcast its progress to multiple listeners.
final class TaskProgressBroadcaster {
  /// Returns `true` if the broadcaster has been closed and can no longer be
  /// used.
  bool get isClosed => _closed;
  bool _closed = false;

  /// The current progress of the task.
  TaskProgress get progress => _progress.copyWith();
  TaskProgress _progress = TaskProgress.unknown();

  /// A list of all progress updates that have been broadcasted.
  ///
  /// The value of [progress] is not yet part of this list, as it is only added
  /// after the next broadcast.
  List<TaskProgress> get progressHistory => List.unmodifiable(_progressHistory);
  final List<TaskProgress> _progressHistory = [];

  final int invocationId;
  TaskProgressBroadcaster._({required this.invocationId});

  late final _controller = StreamController<TaskProgress>.broadcast(sync: true)
    ..stream.listen((p) {
      final tmp = _progress;
      _progress = p;
      _progressHistory.add(tmp.copyWith().._removeParent());
    });
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

  @override
  String toString() {
    final buffer = StringBuffer()
      ..write("TaskProgressBroadcaster(")
      ..write("invocationId: $invocationId")
      ..write(", progress: $progress")
      ..write(")");
    return buffer.toString();
  }
}

final class _TaskStatusResultCapsule<I extends Object?, O extends Object?> {
  TaskResult<I, O>? _output;
  TaskResult<I, O>? get output => _output;
  bool get isCompleted => _output != null;

  void complete(TaskResult<I, O> output) {
    if (isCompleted) throw StateError("Output has already been completed.");
    _output = output;
  }
}

/// Helpers for working with [TaskStatus] futures.
extension TaskStatusFutureExtension<I extends Object?, O extends Object?>
    on Future<TaskStatus<I, O>> {
  Future<TaskResult<I, O>> get result async => (await this).future;
  Future<TaskResultSuccess<I, O>?> get success async => (await result).success;
  Future<TaskResultError<I, O>?> get error async => (await result).error;
  Future<O> get output async => (await this).output;
}

/// A class that represents the status of a task invocation.
///
/// The [TaskStatus] class contains information about the task invocation, such
/// as the invocation id, the task, the progress, and the result of the
/// invocation.
///
/// This class is the primary way to interact with a task invocation, and to get
/// information about its progress and result.
final class TaskStatus<I extends Object?, O extends Object?> {
  /// The unique identifier for the task invocation.
  late final int invocationId;

  /// The task that is being invoked.
  late final Task<I, O> task;

  /// The current progress of the task invocation.
  late final TaskProgressBroadcaster progress;

  /// The result of the task invocation.
  ///
  /// This will be `null` if the task has not yet completed. Use [future] to
  /// wait for the task to complete and get the result.
  ///
  /// The shortcuts [success], [error], and [output] can be used to get the
  /// result in a more convenient way.
  TaskResult<I, O>? get result => _result?.output;
  final _TaskStatusResultCapsule<I, O>? _result;

  /// A future that completes when the task invocation is complete.
  Future<TaskResult<I, O>> get future => _future.future;
  final _future = Completer<TaskResult<I, O>>();

  /// A shortcut to get the success result of the task invocation.
  ///
  /// This will be `null` if the task has not yet completed or if the task did
  /// not complete successfully.
  TaskResultSuccess<I, O>? get success => result?.success;

  /// A shortcut to get the error result of the task invocation.
  ///
  /// This will be `null` if the task has not yet completed or if the task did
  /// not complete with an error.
  TaskResultError<I, O>? get error => result?.error;

  /// A shortcut to get the output of the task invocation.
  ///
  /// ***NOTE:*** This will throw the otherwise safely contained exception from
  /// [TaskResultError] if the task did not complete successfully. Use [error]
  /// to safely access the error result without throwing.
  Future<O> get output async {
    final result = await future;
    return switch (result) {
      TaskResultSuccess<I, O>(:final output) => output,
      TaskResultError<I, O>(:final exception, :final stackTrace) =>
        Error.throwWithStackTrace(exception, stackTrace ?? StackTrace.current),
    };
  }

  /// Cancels the invocation of the task.
  ///
  /// ***NOTE:*** This does not actually cancel the invocation, but rather sends
  /// a friendly signal to the task that it should stop its work and return as
  /// soon as possible. The task is fully able to ignore this request though. To
  /// fully stop execution, use [TaskInstance.close] or similar.
  ///
  /// The task should not throw an exception or return an error, but should
  /// return a normal result if possible, or a default value if not.
  ///
  /// The returned value is indistinguishable from a normal result, so the
  /// caller should not assume that the task has actually stopped its work. The
  /// task may still be running in the background.
  void cancel() => _cancelCurrentAttempt?.call();
  void Function()? _cancelCurrentAttempt;

  @override
  String toString() {
    final buffer = StringBuffer()
      ..write("TaskStatus(")
      ..write("invocationId: $invocationId")
      ..write(", task: $task")
      ..write(", progress: $progress")
      ..write(", result: $result")
      ..write(")");
    return buffer.toString();
  }

  TaskStatus._() : _result = _TaskStatusResultCapsule<I, O>();
  static Future<TaskStatus<I, O>> _create<I extends Object?, O extends Object?>(
    Task<I, O> task,
    I input, {
    required TaskBundle bundle,
    void Function(TaskProgressBroadcaster progress)? progressBroadcaster,
    void Function(int id)? invocationId,
    RetryOptions? retryOptions,
  }) async {
    final idCompleter = Completer<int>();
    final progressCompleter = Completer<TaskProgressBroadcaster>();
    return TaskStatus<I, O>._()
      .._invoke(
        task,
        input,
        bundle: bundle,
        progressBroadcaster: (progress) {
          if (!progressCompleter.isCompleted) {
            progressCompleter.complete(progress);
          }
          (progressBroadcaster ?? ProgressSnatcher.instance.auto).call(
            progress,
          );
        },
        invocationId: (id) {
          if (!idCompleter.isCompleted) {
            idCompleter.complete(id);
          }
          invocationId?.call(id);
        },
        retryOptions: retryOptions,
      )
      ..task = task
      ..invocationId = await idCompleter.future
      ..progress = await progressCompleter.future;
  }

  Future<void> _invoke(
    Task<I, O> task,
    I input, {
    required TaskBundle bundle,
    void Function(TaskProgressBroadcaster progress)? progressBroadcaster,
    void Function(int id)? invocationId,
    RetryOptions? retryOptions,
  }) async {
    final tmpId = --bundle._tmpInvocationIdCounter;
    bundle._runningInvocations[tmpId] = this;

    var instance =
        bundle._running.singleWhereOrNull(
              (i) => i._task == task && !i._closed.isCompleted,
            )
            as TaskInstance<I, O>?;
    if (instance == null) {
      instance = await task.spawn();
      bundle._running.add(instance);
    }

    int? id;
    int? previousId;
    TaskResult<I, O>? result;
    final startTime = DateTime.timestamp();
    var retryCount = 0;

    try {
      O resultData;
      Future<O> compute() async {
        if (bundle._closed) {
          throw StateError("Cannot invoke tasks on a closed TaskBundle.");
        }

        Future<O> data;
        (id, data) = instance!.invoke(
          input,
          progressBroadcaster: progressBroadcaster,
          invocationId: invocationId,
        );
        _cancelCurrentAttempt = () => instance!._cancel(id!);

        bundle._runningInvocations[id!] = this;
        bundle._runningInvocations.remove(tmpId);
        bundle._runningInvocations.remove(previousId);

        var future = data.catchError(Error.throwWithStackTrace);
        if (task.timeout != null) {
          future = future.timeout(task.timeout!);
        }
        return future;
      }

      if (retryOptions != null) {
        resultData = await retryOptions.retry(
          compute,
          onRetry: (_) {
            retryCount++;
            previousId = id ?? tmpId;
            bundle._update.add(task.id);
          },
        );
      } else {
        resultData = await compute();
      }

      final evalTime = DateTime.timestamp();
      result = TaskResultSuccess<I, O>._(
        output: resultData,
        executionTime: evalTime.difference(startTime),
        startTime: startTime,
        endTime: evalTime,
      );
    } catch (e, s) {
      result = TaskResultError<I, O>._(
        exception: e,
        stackTrace: s,
        startTime: startTime,
        throwTime: DateTime.timestamp(),
        retryCount: retryCount,
        retryOptions: retryOptions,
      );
    } finally {
      _result?.complete(result!);
      _future.complete(result);

      if (id != null) bundle._runningInvocations.remove(id);
      bundle._runningInvocations.remove(tmpId);
      if (!bundle._closed) bundle._update.add(task.id);
    }
  }
}

/// A class that represents the result of a task invocation.
///
/// The result can either be a success or an error. The result contains the
/// invocation id, the task, the progress, and the start time of the invocation.
///
/// See [TaskResultSuccess] and [TaskResultError] for more information about the
/// success and error results.
///
/// Use [success] and [error] for quick access to the success or error result.
/// Both will return `null` if the result is not of the respective type.
sealed class TaskResult<I extends Object?, O extends Object?> {
  final DateTime? startTime;

  TaskResult._({required this.startTime});

  TaskResultSuccess<I, O>? get success =>
      this is TaskResultSuccess<I, O> ? this as TaskResultSuccess<I, O> : null;
  TaskResultError<I, O>? get error =>
      this is TaskResultError<I, O> ? this as TaskResultError<I, O> : null;

  @override
  @mustBeOverridden
  String toString() {
    final buffer = StringBuffer()..write("TaskResult(");
    if (startTime != null) {
      buffer.write("startTime: $startTime");
    }
    buffer.write(")");
    return buffer.toString();
  }
}

/// A class that represents the result of a task invocation that completed
/// successfully.
final class TaskResultSuccess<I extends Object?, O extends Object?>
    extends TaskResult<I, O> {
  final O output;
  final DateTime? endTime;
  final Duration? executionTime;

  TaskResultSuccess._({
    required this.output,
    required this.executionTime,
    required super.startTime,
    required this.endTime,
  }) : super._();

  @override
  String toString() {
    final buffer = StringBuffer()
      ..write("TaskResultSuccess(")
      ..write("output: $output");
    if (startTime != null) {
      buffer.write(", startTime: $startTime");
    }
    if (endTime != null) {
      buffer.write(", endTime: $endTime");
    }
    if (executionTime != null) {
      buffer.write(", executionTime: $executionTime");
    }
    buffer.write(")");
    return buffer.toString();
  }
}

/// A class that represents the result of a task invocation that resulted in an
/// error or exception.
final class TaskResultError<I extends Object?, O extends Object?>
    extends TaskResult<I, O> {
  final Object exception;
  final StackTrace? stackTrace;
  final DateTime? throwTime;

  final int? retryCount;
  final RetryOptions? retryOptions;

  TaskResultError._({
    required this.exception,
    required this.stackTrace,
    required super.startTime,
    required this.throwTime,
    required this.retryCount,
    required this.retryOptions,
  }) : super._();

  @override
  String toString() {
    final buffer = StringBuffer()
      ..write("TaskResultError(")
      ..write("exception: $exception");
    if (stackTrace != null) {
      buffer.write(", stackTrace: ...");
    }
    if (startTime != null) {
      buffer.write(", startTime: $startTime");
    }
    if (throwTime != null) {
      buffer.write(", throwTime: $throwTime");
    }
    if (retryCount != null) {
      buffer.write(", retryCount: $retryCount");
    }
    if (retryOptions != null) {
      buffer.write(", retryOptions: ${retryOptions!.toPrettyString()}");
    }
    buffer.write(")");
    return buffer.toString();
  }
}

/// A class that represents the metadata of a task.
class TaskMetadata {
  final int? priority;
  final String? version;

  final String? author;
  final String? maintainer;
  final String? description;
  final Uri? icon;
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
    this.icon,
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
      icon: Uri.tryParse(data.remove("icon") ?? ""),
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
/// corrupted state from the last should be recovered in the following run. See
/// [allowRestoration] for more information.
///
/// ---
///
/// When defining a task with no input or output, or with only one of them, you
/// use `Null` as input or output type, that's the safest option. For output,
/// `void` could be used as well:
///
/// ```dart
/// class MyTask extends Task<Null, Null> {
/// // or
/// class MyTask extends Task<Null, void> {
/// ```
///
/// Using `void` as input type is not recommended, because then the input
/// generic has to be set to `void` manually, like:
/// `scheduler.invoke<void, void>(...)`.
abstract class Task<I extends Object?, O extends Object?> {
  bool _closed = false;
  final Map<int, bool> _invocationClosed = {};

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

  /// Whether the task allows its state to be restored after a crash or restart.
  ///
  /// This is useful for tasks that do something in the background, like
  /// downloading or labeling data, and can resume where they left off after a
  /// crash or restart. If the task is used to just get a value from the invoke
  /// functions, this should be set to `false`.
  bool get allowRestoration => false;

  /// The timeout for the task.
  ///
  /// This is the maximum duration that the task is allowed to run before it is
  /// considered to have failed. If the task takes longer than this duration to
  /// complete, it will be terminated and an error will be returned.
  Duration? get timeout => null;

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
  /// - `icon`: URI that points to an icon. This has to be interpreted by the
  ///   application as it sees fit. It might be a URL, a icon pack resource
  ///   locator or similar.
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

  Task() {
    if (!kCamelCasePattern.hasMatch(id)) {
      throw ArgumentError("Task id must be in camelCase format.", "id");
    } else if (displayName != null && displayName!.isEmpty) {
      throw ArgumentError(
        "Task display name must be non-empty if provided.",
        "displayName",
      );
    } else if (metadata.values.any((value) => value.isEmpty)) {
      throw ArgumentError(
        "Task metadata values must be non-empty if provided.",
        "metadata",
      );
    }
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
      isolate =
          await Isolate.spawn(
              _startRemoteIsolate,
              initPort.sendPort,
              errorsAreFatal: true,
              onError: initPort.sendPort,
            )
            ..addOnExitListener(initPort.sendPort, response: "shutdown_ack");
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
        } else if (message case ("cancel", final int id)) {
          _invocationClosed[id] = true;
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
                getIsClosed: () => _invocationClosed[id] == true || _closed,
              ),
            ),
          );
          if (_closed) return;
          _invocationClosed.remove(id);
          sendPort.send((id, output));
        } catch (e, s) {
          if (_closed) return;
          _invocationClosed.remove(id);
          sendPort.send((id, RemoteException(e.toString(), s.toString())));
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
  String toString() {
    final buffer = StringBuffer()..write("Task(id: ${jsonEncode(id)}");
    if (displayName != null) {
      buffer.write(", displayName: ${jsonEncode(displayName)}");
    }
    if (allowSimultaneous) {
      buffer.write(", allowSimultaneous: $allowSimultaneous");
    }
    if (allowRestoration) {
      buffer.write(", allowRestoration: $allowRestoration");
    }
    if (metadata.isNotEmpty) {
      buffer.write(", metadata: ${jsonEncode(metadata)}");
    }
    buffer.write(")");
    return buffer.toString();
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Task) return false;
    return id == other.id;
  }

  @override
  int get hashCode => id.hashCode;
}

final class TaskInstance<I extends Object?, O extends Object?> {
  final Completer<void> _closed = Completer<void>.sync();
  bool _closingProcess = false;
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
  /// [RemoteException] with the error converted to a string and the stack trace
  /// from the isolate.
  (int, Future<O>) invoke(
    I input, {
    void Function(TaskProgressBroadcaster progress)? progressBroadcaster,
    void Function(int id)? invocationId,
  }) {
    if (_closed.isCompleted) {
      throw StateError("Cannot send inputs to a closed TaskInstance.");
    }

    final id = _idCounter++;
    final completer = Completer<O>.sync();
    final broadcaster = TaskProgressBroadcaster._(invocationId: id);

    _activeRequests[id] = completer;
    _activeProgressBroadcasters[id] = broadcaster;
    _commands.send((id, input));

    runZonedGuarded(() {
      invocationId?.call(id);
      (progressBroadcaster ?? ProgressSnatcher.instance.auto).call(broadcaster);
    }, Error.throwWithStackTrace);
    return (id, completer.future.catchError(Error.throwWithStackTrace));
  }

  void _cancel(int id) {
    if (_closed.isCompleted) return;
    _commands.send(("cancel", id));
  }

  void _handleResponsesFromIsolate(dynamic message) {
    if (message == "shutdown_ack") {
      if (!_closingProcess) {
        _failAllActiveRequests(
          StateError(
            "TaskInstance was closed unexpectedly. The isolate was shut down before a response was received.",
          ),
          StackTrace.current,
        );
        return;
      }
      _closed.complete();
      return;
    } else if (message case [final String e, final String s]) {
      final error = RemoteException(e, s);
      _failAllActiveRequests(error, error.stackTrace);
      return;
    } else if (message case (
      final int id,
      progress: final TaskProgress progress,
    )) {
      if (!_activeProgressBroadcasters.containsKey(id)) return;
      _activeProgressBroadcasters[id]!._controller.add(progress);
      return;
    }

    final (id, response) = message as (int, dynamic);
    if (!_activeRequests.containsKey(id)) return;
    final completer = _activeRequests.remove(id)!;
    _activeProgressBroadcasters.remove(id)?._close();

    if (response case final RemoteException error) {
      completer.completeError(error, error.stackTrace);
    } else {
      completer.complete(response as O);
    }
  }

  void _failAllActiveRequests(Object error, StackTrace stackTrace) {
    for (final broadcaster in _activeProgressBroadcasters.values) {
      broadcaster._close();
    }
    _responses.close();
    _isolate.kill(priority: Isolate.immediate);
    if (!_closed.isCompleted) _closed.complete();

    for (final completer in _activeRequests.values) {
      completer.completeError(error, stackTrace);
    }
    _activeRequests.clear();
    _activeProgressBroadcasters.clear();
  }

  /// Closes the task instance and terminates the isolate.
  ///
  /// If there are any active requests when this method is called, they will be
  /// completed with a [StateError] indicating that the task instance was closed
  /// before a response was received.
  ///
  /// Note that this method fill kill the whole isolate, meaning other instances
  /// will become unusable as well.
  Future<void> close({bool silent = false, bool kill = false}) async {
    if (!_closed.isCompleted && !kill) {
      _closingProcess = true;
      _commands.send("shutdown");
      await _closed.future.timeout(Duration(seconds: 10), onTimeout: () {});

      if (!silent) {
        for (final completer in _activeRequests.values) {
          completer.completeError(
            StateError("TaskInstance closed before response was received."),
            StackTrace.current,
          );
        }
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

  /// Currently running invocations.
  Map<int, TaskStatus> get runningInvocations =>
      Map.unmodifiable(_runningInvocations);
  final Map<int, TaskStatus> _runningInvocations = {};
  int _tmpInvocationIdCounter = 0;

  TaskBundle(Iterable<Task> tasks, {bool startCulling = true})
    : tasks = Set.unmodifiable(tasks.toSet()) {
    if (tasks.toSet().length != tasks.length) {
      throw ArgumentError(
        "TaskBundle must not contain tasks with duplicate ids.",
      );
    }
    if (startCulling) this.startCulling();
  }

  /// Invokes a task by its id with the given input and returns the output
  /// asynchronously.
  ///
  /// If the task id is not found in the bundle, this method will throw an
  /// [ArgumentError].
  ///
  /// See [invoke] for more information about the parameters.
  Future<TaskStatus<I, O>> invokeNamed<I extends Object?, O extends Object?>(
    String taskId,
    I input, {
    void Function(TaskProgressBroadcaster progress)? progressBroadcaster,
    void Function(int id)? invocationId,
    RetryOptions? retryOptions,
  }) async {
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
      invocationId: invocationId,
      retryOptions: retryOptions,
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
  /// [RemoteException] with the error converted to a string and the stack trace
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
  Future<TaskStatus<I, O>> invoke<I extends Object?, O extends Object?>(
    Type taskType,
    I input, {
    void Function(TaskProgressBroadcaster progress)? progressBroadcaster,
    void Function(int id)? invocationId,
    RetryOptions? retryOptions,
  }) async {
    if (_closed) {
      throw StateError("Cannot invoke tasks on a closed TaskBundle.");
    }

    late final Task<I, O> task;
    try {
      task =
          tasks.singleWhere(
                (t) => t.runtimeType == taskType,
                orElse: () => throw ArgumentError(
                  "TaskBundle does not contain a task of type '$taskType'.",
                ),
              )
              as Task<I, O>;
    } catch (e, s) {
      Error.throwWithStackTrace(castErrorParser(e) ?? e, s);
    }
    if (!task.allowSimultaneous &&
        _runningInvocations.values.any((i) => i.task == task)) {
      throw StateError(
        "Task '${task.id}' does not allow multiple instances and is already running.",
      );
    }

    return TaskStatus._create<I, O>(
      task,
      input,
      bundle: this,
      progressBroadcaster: progressBroadcaster,
      invocationId: invocationId,
      retryOptions: retryOptions,
    );
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
  Future<void> close({bool silent = false, bool kill = false}) async {
    if (_closed) return;
    _closed = true;

    if (_cullingTimer != null) stopCulling();
    for (final subscription in _listeners.values.toList()) {
      await subscription.cancel();
    }
    for (final instance in List.of(_running)) {
      await instance.close(silent: silent, kill: kill);
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
      final evalTime = DateTime.timestamp();
      for (final instance in _running) {
        if (instance._closed.isCompleted ||
            (instance._activeRequests.isEmpty &&
                _cullingSuspects[instance] != null &&
                evalTime.difference(_cullingSuspects[instance]!) > idleTime)) {
          toRemove.add(instance);
        }

        if (instance._activeRequests.isEmpty) {
          _cullingSuspects[instance] ??= evalTime;
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

/// A task that is defined inline with a function.
///
/// This should not be used for anything important as it a rather messy way of
/// defining a task. It is mainly intended for testing and prototyping. For
/// production code, it is recommended to define a task as a subclass of [Task].
final class InlineTask<I extends Object?, O extends Object?>
    extends Task<I, O> {
  final FutureOr<O> Function(I input, TaskProgressCommunicator progress)
  _invokeFunction;

  @override
  final String id;
  @override
  final String? displayName;
  @override
  final bool allowSimultaneous;
  @override
  bool get allowRestoration => false;
  @override
  final Duration? timeout;
  @override
  final Map<String, String> metadata;

  InlineTask({
    required this.id,
    required FutureOr<O> Function(I input, TaskProgressCommunicator progress)
    invoke,
    this.displayName,
    this.allowSimultaneous = false,
    this.timeout,
    Map<String, String> metadata = const {},
  }) : _invokeFunction = invoke,
       metadata = Map.unmodifiable(metadata);

  @override
  FutureOr<O> invoke(I input, TaskProgressCommunicator progress) =>
      _invokeFunction.call(input, progress);
}
