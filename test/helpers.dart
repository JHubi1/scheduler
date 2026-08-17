/// @docImport "package:scheduler/scheduler.dart";
library;

import 'dart:async';
import 'package:scheduler/tasks.dart';

/// Simple task that returns its input unchanged.
class EchoTask extends Task<String, String> {
  @override
  String get id => "echoTask";
  @override
  bool get allowSimultaneous => true;

  @override
  FutureOr<String> invoke(String input, TaskProgressCommunicator progress) =>
      input;
}

/// Task that waits for the given [Duration], then returns "done".
class DelayedTask extends Task<Duration, String> {
  @override
  String get id => "delayedTask";
  @override
  bool get allowSimultaneous => true;

  @override
  Future<String> invoke(
    Duration delay,
    TaskProgressCommunicator progress,
  ) async {
    await Future.delayed(delay);
    return "done";
  }
}

/// Task that always throws an [Exception].
class FailingTask extends Task<String, String> {
  @override
  String get id => "failingTask";
  @override
  bool get allowSimultaneous => true;

  @override
  FutureOr<String> invoke(String input, TaskProgressCommunicator progress) =>
      throw Exception("Task failed: $input");
}

/// Task that emits [TaskProgress.steps] progress updates, then returns
/// [TaskProgress.steps].
class ProgressTask extends Task<int, int> {
  @override
  String get id => "progressTask";
  @override
  bool get allowSimultaneous => true;

  @override
  Future<int> invoke(int steps, TaskProgressCommunicator progress) async {
    for (var i = 0; i < steps; i++) {
      progress.set(TaskProgress(progress: i / steps));
      await Future.delayed(Duration.zero);
    }
    return steps;
  }
}

/// Non-simultaneous task that echoes its input.
class ExclusiveTask extends Task<String, String> {
  @override
  String get id => "exclusiveTask";

  @override
  FutureOr<String> invoke(String input, TaskProgressCommunicator progress) =>
      input;
}

/// Non-simultaneous task that delays, used to hold a slot open in tests.
class SlowExclusiveTask extends Task<Duration, String> {
  @override
  String get id => "slowExclusiveTask";

  @override
  Future<String> invoke(
    Duration delay,
    TaskProgressCommunicator progress,
  ) async {
    await Future.delayed(delay);
    return "done";
  }
}

/// Task that exercises communicator.get() by modifying the returned progress
/// and calling set().
class GetSetTask extends Task<String, String> {
  @override
  String get id => "getSetTask";
  @override
  bool get allowSimultaneous => true;

  @override
  FutureOr<String> invoke(String input, TaskProgressCommunicator progress) {
    progress.get().copyWith(progress: () => 0.5).set();
    return input;
  }
}

/// Task exposing all standard metadata fields plus one custom key.
class RichMetadataTask extends Task<String, String> {
  @override
  String get id => "richMetadataTask";
  @override
  bool get allowSimultaneous => true;
  @override
  Map<String, String> get metadata => const {
    "priority": "3",
    "version": "1.0.0",
    "author": "Test Author",
    "maintainer": "Test Maintainer",
    "description": "A test task",
    "icon": "pack:flower",
    "license": "MIT",
    "repository": "https://example.com/repo",
    "documentation": "https://example.com/docs",
    "homepage": "https://example.com",
    "keywords": "foo, bar, baz",
    "customKey": "customValue",
  };

  @override
  FutureOr<String> invoke(String input, TaskProgressCommunicator progress) =>
      input;
}

/// Echo task with a non-zero default priority declared in its metadata.
class PriorityEchoTask extends Task<String, String> {
  @override
  String get id => "priorityEchoTask";
  @override
  bool get allowSimultaneous => true;
  @override
  Map<String, String> get metadata => const {"priority": "5"};

  @override
  FutureOr<String> invoke(String input, TaskProgressCommunicator progress) =>
      input;
}

/// Task that fails on its first two invocations, then succeeds.
///
/// Used to exercise [RetryOptions] retry behavior. Fails permanently after
/// [permanentFailure] is set to `true`, regardless of attempt count.
class RetryableTask extends Task<String, String> {
  int attempts = 0;
  bool permanentFailure = false;

  @override
  String get id => "retryableTask";
  @override
  bool get allowSimultaneous => true;

  @override
  FutureOr<String> invoke(String input, TaskProgressCommunicator progress) {
    attempts++;
    if (permanentFailure || attempts < 3) {
      throw Exception("Attempt $attempts failed");
    }
    return input;
  }
}

/// Task that always throws, used to exercise retry exhaustion.
class AlwaysFailingRetryableTask extends Task<String, String> {
  int attempts = 0;

  @override
  String get id => "alwaysFailingRetryableTask";
  @override
  bool get allowSimultaneous => true;

  @override
  FutureOr<String> invoke(String input, TaskProgressCommunicator progress) {
    attempts++;
    throw Exception("Attempt $attempts failed");
  }
}

/// Echo task that allows its state to be restored, used for
/// [Scheduler.restorableState] / [Scheduler.fromRestorableState] tests.
class RestorableTask extends Task<String, String> {
  @override
  String get id => "restorableTask";
  @override
  bool get allowSimultaneous => true;
  @override
  bool get allowRestoration => true;

  @override
  FutureOr<String> invoke(String input, TaskProgressCommunicator progress) =>
      input;
}

/// Restorable, delay-based task, used to hold a slot open in restorableState
/// tests so an invocation can be captured mid-flight.
class SlowRestorableTask extends Task<Duration, String> {
  @override
  String get id => "slowRestorableTask";
  @override
  bool get allowSimultaneous => true;
  @override
  bool get allowRestoration => true;

  @override
  Future<String> invoke(
    Duration delay,
    TaskProgressCommunicator progress,
  ) async {
    await Future.delayed(delay);
    return "done";
  }
}

/// Waits for the given [Duration] input, then returns "done". Has a
/// configurable [Task.timeout], used to exercise timeout enforcement.
class TimeoutTask extends Task<Duration, String> {
  final Duration timeoutDuration;
  TimeoutTask(this.timeoutDuration);

  @override
  String get id => "timeoutTask";
  @override
  bool get allowSimultaneous => true;
  @override
  Duration? get timeout => timeoutDuration;

  @override
  Future<String> invoke(
    Duration delay,
    TaskProgressCommunicator progress,
  ) async {
    await Future.delayed(delay);
    return "done";
  }
}

/// Loops up to `iterations` times, checking [TaskProgressCommunicator.isClosed]
/// between iterations and returning "cancelled" early if it becomes true.
/// Used to exercise [TaskStatus.cancel].
class CancellableTask extends Task<int, String> {
  @override
  String get id => "cancellableTask";
  @override
  bool get allowSimultaneous => true;

  @override
  Future<String> invoke(
    int iterations,
    TaskProgressCommunicator progress,
  ) async {
    for (var i = 0; i < iterations; i++) {
      if (progress.isClosed) return "cancelled";
      await Future.delayed(const Duration(milliseconds: 20));
    }
    return "completed";
  }
}

/// Schedules an uncaught, asynchronous error outside of the normal
/// request-handling try/catch, crashing the whole isolate. Used to exercise
/// unexpected isolate death. Never sends a normal response itself, so the
/// crash always wins the race against a regular completion.
class CrashingTask extends Task<int, String> {
  @override
  String get id => "crashingTask";
  @override
  bool get allowSimultaneous => true;

  @override
  Future<String> invoke(int input, TaskProgressCommunicator progress) {
    Future.delayed(Duration.zero, () => throw StateError("Simulated crash."));
    return Completer<String>().future;
  }
}
