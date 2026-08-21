import 'dart:async';

import 'package:scheduler/scheduler.dart';
import 'package:scheduler/tasks.dart';
import 'package:test/test.dart';

void main() {
  group("InlineTask", () {
    test("id reflects the constructor argument", () {
      final task = InlineTask<int, int>(id: "myInline", invoke: (i, p) => i);
      expect(task.id, "myInline");
    });

    test("allowRestoration is always false", () {
      final task = InlineTask<int, int>(id: "myInline", invoke: (i, p) => i);
      expect(task.allowRestoration, isFalse);
    });

    test("forwards displayName, allowSimultaneous, timeout and metadata", () {
      final task = InlineTask<int, int>(
        id: "myInline",
        invoke: (i, p) => i,
        displayName: "My Inline",
        allowSimultaneous: true,
        timeout: const Duration(seconds: 1),
        metadata: const {"priority": "2"},
      );
      expect(task.displayName, "My Inline");
      expect(task.allowSimultaneous, isTrue);
      expect(task.timeout, const Duration(seconds: 1));
      expect(task.metadata, {"priority": "2"});
    });

    test("defaults allowSimultaneous, timeout and metadata", () {
      final task = InlineTask<int, int>(id: "myInline", invoke: (i, p) => i);
      expect(task.allowSimultaneous, isFalse);
      expect(task.timeout, isNull);
      expect(task.metadata, isEmpty);
    });

    test("throws ArgumentError for a non-camelCase id", () {
      expect(
        () => InlineTask<int, int>(id: "Not Camel", invoke: (i, p) => i),
        throwsArgumentError,
      );
    });

    test("throws ArgumentError for an empty displayName", () {
      expect(
        () => InlineTask<int, int>(
          id: "myInline",
          invoke: (i, p) => i,
          displayName: "",
        ),
        throwsArgumentError,
      );
    });

    test("throws ArgumentError for an empty metadata value", () {
      expect(
        () => InlineTask<int, int>(
          id: "myInline",
          invoke: (i, p) => i,
          metadata: const {"priority": ""},
        ),
        throwsArgumentError,
      );
    });

    test("toString includes the id", () {
      final task = InlineTask<int, int>(id: "myInline", invoke: (i, p) => i);
      expect(task.toString(), contains("myInline"));
    });

    test("two instances with the same id are equal, regardless of invoke", () {
      final a = InlineTask<int, int>(id: "myInline", invoke: (i, p) => i);
      final b = InlineTask<int, int>(id: "myInline", invoke: (i, p) => i * 2);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test("toBundle wraps the task in a single-task TaskBundle", () {
      final task = InlineTask<int, int>(id: "myInline", invoke: (i, p) => i);
      expect(task.toBundle().tasks, {task});
    });

    test(
      "invoke delegates to the provided function and forwards input",
      () async {
        final task = InlineTask<int, int>(
          id: "doubler",
          invoke: (input, progress) => input * 2,
        );
        final instance = await task.spawn();
        addTearDown(instance.close);

        final (_, future) = instance.invoke(21);
        expect(await future, 42);
      },
    );

    test("invoke supports async functions", () async {
      final task = InlineTask<int, int>(
        id: "asyncDoubler",
        invoke: (input, progress) async {
          await Future.delayed(Duration.zero);
          return input * 2;
        },
      );
      final instance = await task.spawn();
      addTearDown(instance.close);

      final (_, future) = instance.invoke(21);
      expect(await future, 42);
    });

    test("invoke can report progress via the communicator", () async {
      final task = InlineTask<int, int>(
        id: "reporter",
        invoke: (input, progress) {
          progress.set(TaskProgress.complete());
          return input;
        },
      );
      final instance = await task.spawn();
      addTearDown(instance.close);

      final received = <TaskProgress>[];
      final (_, future) = instance.invoke(
        5,
        progressBroadcaster: (b) => b.addListener(received.add),
      );
      await future;

      expect(received, contains(TaskProgress.complete()));
    });

    test("works end-to-end through a Scheduler", () async {
      final scheduler = Scheduler([
        InlineTask<String, String>(
          id: "greeter",
          invoke: (input, progress) => "Hello, $input!",
        ),
      ]);
      addTearDown(() => scheduler.close(silent: true));

      final status = await scheduler.invokeNamed<String, String>(
        "greeter",
        "World",
      );
      expect((await status.future).success?.output, "Hello, World!");
    });
  });
}
