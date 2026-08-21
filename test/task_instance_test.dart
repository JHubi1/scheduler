import 'dart:async';

import 'package:scheduler/tasks.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Lets tests construct a Task with an arbitrary id to exercise validation.
class _ValidatableTask extends Task<String, String> {
  @override
  final String id;
  _ValidatableTask(this.id);
  @override
  FutureOr<String> invoke(String input, TaskProgressCommunicator progress) =>
      input;
}

/// Lets tests construct a Task with an arbitrary displayName/metadata to
/// exercise validation.
class _ValidatableMetadataTask extends Task<String, String> {
  @override
  String get id => "validatableMetadataTask";
  @override
  final String? displayName;
  @override
  final Map<String, String> metadata;
  _ValidatableMetadataTask({this.displayName, this.metadata = const {}});
  @override
  FutureOr<String> invoke(String input, TaskProgressCommunicator progress) =>
      input;
}

/// Task for testing the keywords edge-case in [TaskMetadata._fromMap].
class _SparseKeywordsTask extends Task<String, String> {
  @override
  String get id => "sparseKeywordsTask";

  @override
  bool get allowSimultaneous => true;

  @override
  Map<String, String> get metadata => const {"keywords": "foo, , bar"};

  @override
  FutureOr<String> invoke(String input, TaskProgressCommunicator progress) =>
      input;
}

void main() {
  group("Task", () {
    group("id validation", () {
      test("accepts valid camelCase id", () {
        expect(() => _ValidatableTask("myTask"), returnsNormally);
      });

      test("accepts single lowercase word", () {
        expect(() => _ValidatableTask("task"), returnsNormally);
      });

      test("accepts id that contains digits", () {
        expect(() => _ValidatableTask("myTask123"), returnsNormally);
      });

      test("rejects id starting with uppercase", () {
        expect(() => _ValidatableTask("MyTask"), throwsArgumentError);
      });

      test("rejects id containing underscore", () {
        expect(() => _ValidatableTask("my_task"), throwsArgumentError);
      });

      test("rejects id containing hyphen", () {
        expect(() => _ValidatableTask("my-task"), throwsArgumentError);
      });

      test("rejects id starting with a digit", () {
        expect(() => _ValidatableTask("123task"), throwsArgumentError);
      });

      test("rejects empty id", () {
        expect(() => _ValidatableTask(""), throwsArgumentError);
      });
    });

    group("displayName/metadata validation", () {
      test("accepts a null displayName", () {
        expect(_ValidatableMetadataTask.new, returnsNormally);
      });

      test("accepts a non-empty displayName", () {
        expect(
          () => _ValidatableMetadataTask(displayName: "My Task"),
          returnsNormally,
        );
      });

      test("rejects an empty (non-null) displayName", () {
        expect(
          () => _ValidatableMetadataTask(displayName: ""),
          throwsArgumentError,
        );
      });

      test("accepts metadata with non-empty values", () {
        expect(
          () => _ValidatableMetadataTask(metadata: const {"priority": "1"}),
          returnsNormally,
        );
      });

      test("rejects metadata containing an empty value", () {
        expect(
          () => _ValidatableMetadataTask(metadata: const {"priority": ""}),
          throwsArgumentError,
        );
      });
    });

    group("properties", () {
      test("allowSimultaneous defaults to false", () {
        expect(ExclusiveTask().allowSimultaneous, isFalse);
      });

      test("allowSimultaneous can be overridden to true", () {
        expect(EchoTask().allowSimultaneous, isTrue);
      });

      test("displayName defaults to null", () {
        expect(EchoTask().displayName, isNull);
      });

      test("metadataObject.priority is parsed from the metadata map", () {
        expect(PriorityEchoTask().metadataObject.priority, 5);
      });

      test("metadataObject.priority is null when not in metadata", () {
        expect(EchoTask().metadataObject.priority, isNull);
      });
    });

    group("metadataObject (_fromMap)", () {
      late TaskMetadata meta;
      setUpAll(() => meta = RichMetadataTask().metadataObject);

      test("parses priority as int", () => expect(meta.priority, 3));
      test("parses version", () => expect(meta.version, "1.0.0"));
      test("parses author", () => expect(meta.author, "Test Author"));
      test(
        "parses maintainer",
        () => expect(meta.maintainer, "Test Maintainer"),
      );
      test("parses description", () => expect(meta.description, "A test task"));
      test("parses icon", () => expect(meta.icon, Uri.parse("pack:flower")));
      test("parses license", () => expect(meta.license, "MIT"));
      test(
        "parses repository",
        () => expect(meta.repository, Uri.parse("https://example.com/repo")),
      );
      test(
        "parses documentation",
        () => expect(meta.documentation, Uri.parse("https://example.com/docs")),
      );
      test(
        "parses homepage",
        () => expect(meta.homepage, Uri.parse("https://example.com")),
      );

      test("parses keywords from comma-separated string", () {
        expect(meta.keywords, ["foo", "bar", "baz"]);
      });

      test("filters empty entries from keywords", () {
        final m = _SparseKeywordsTask().metadataObject;
        expect(m.keywords, ["foo", "bar"]);
      });

      test("collects unrecognised keys in additionalMetadata", () {
        expect(meta.additionalMetadata, {"customKey": "customValue"});
      });

      test("recognised keys are absent from additionalMetadata", () {
        expect(meta.additionalMetadata.keys, isNot(contains("priority")));
      });
    });

    group("equality", () {
      test("two instances with the same id are equal", () {
        expect(EchoTask(), equals(EchoTask()));
      });

      test("instances with different ids are not equal", () {
        expect(EchoTask(), isNot(equals(ExclusiveTask())));
      });

      test("hashCode is consistent with equality", () {
        expect(EchoTask().hashCode, EchoTask().hashCode);
      });
    });

    test("toString contains the task id", () {
      expect(EchoTask().toString(), contains("echoTask"));
    });

    test("toBundle returns a TaskBundle that contains the task", () async {
      final task = EchoTask();
      final bundle = task.toBundle();
      addTearDown(bundle.close);
      expect(bundle.tasks, contains(task));
    });
  });

  group("TaskInstance", () {
    test("spawn() creates a TaskInstance", () async {
      final instance = await EchoTask().spawn();
      addTearDown(instance.close);
      expect(instance, isNotNull);
    });

    test("invoke returns the correct output", () async {
      final instance = await EchoTask().spawn();
      addTearDown(instance.close);

      final (_, future) = instance.invoke("hello");
      expect(await future, "hello");
    });

    test(
      "multiple concurrent invocations on an allowSimultaneous task complete correctly",
      () async {
        final instance = await EchoTask().spawn();
        addTearDown(instance.close);

        final (_, f1) = instance.invoke("a");
        final (_, f2) = instance.invoke("b");
        final (_, f3) = instance.invoke("c");

        expect(await Future.wait([f1, f2, f3]), ["a", "b", "c"]);
      },
    );

    test("invoke propagates task errors as RemoteException", () async {
      final instance = await FailingTask().spawn();
      addTearDown(instance.close);

      final (_, future) = instance.invoke("trigger");
      await expectLater(future, throwsA(isA<RemoteException>()));
    });

    test(
      "invoke on a closed instance throws StateError synchronously",
      () async {
        final instance = await EchoTask().spawn();
        await instance.close();
        expect(() => instance.invoke("hello"), throwsStateError);
      },
    );

    test(
      "pending futures complete with StateError when instance is closed",
      () async {
        final instance = await DelayedTask().spawn();
        final (_, future) = instance.invoke(const Duration(milliseconds: 300));
        final expectation = expectLater(future, throwsA(isA<StateError>()));
        await instance.close();
        await expectation;
      },
    );

    test("toString contains the task id", () async {
      final instance = await EchoTask().spawn();
      addTearDown(instance.close);
      expect(instance.toString(), contains("echoTask"));
    });

    test("progress updates are delivered via progressBroadcaster", () async {
      final instance = await ProgressTask().spawn();
      addTearDown(instance.close);

      final received = <TaskProgress>[];
      final (_, future) = instance.invoke(
        3,
        progressBroadcaster: (b) => b.addListener(received.add),
      );
      await future;

      expect(received, isNotEmpty);
      expect(received.map((p) => p.progress), everyElement(isNonNegative));
    });

    test("progressBroadcaster.progress reflects the latest update", () async {
      final instance = await ProgressTask().spawn();
      addTearDown(instance.close);

      TaskProgressBroadcaster? captured;
      final (_, future) = instance.invoke(
        3,
        progressBroadcaster: (b) => captured = b,
      );
      await future;

      expect(captured!.progress.progress, isNotNull);
    });

    test(
      "communicator.get() returns a parented TaskProgress that can set() back",
      () async {
        final instance = await GetSetTask().spawn();
        addTearDown(instance.close);

        final received = <TaskProgress>[];
        final (_, future) = instance.invoke(
          "test",
          progressBroadcaster: (b) => b.addListener(received.add),
        );
        await future;

        expect(received, contains(TaskProgress(progress: 0.5)));
      },
    );
  });
}
