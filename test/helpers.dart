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
