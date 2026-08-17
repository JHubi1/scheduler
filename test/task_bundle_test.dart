import 'package:scheduler/tasks.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group("TaskBundle", () {
    test("accepts a set of distinct tasks", () {
      final bundle = TaskBundle([
        EchoTask(),
        ExclusiveTask(),
      ], startCulling: false);
      addTearDown(bundle.close);
      expect(bundle.tasks.length, 2);
    });

    test("throws AssertionError for duplicate task ids", () {
      expect(
        () => TaskBundle([EchoTask(), EchoTask()], startCulling: false),
        throwsA(isA<AssertionError>()),
      );
    });

    group("invokeNamed", () {
      late TaskBundle bundle;
      setUp(() => bundle = TaskBundle([EchoTask()], startCulling: false));
      tearDown(() => bundle.close());

      test("returns the correct output for a known task id", () async {
        expect(
          await bundle.invokeNamed<String, String>("echoTask", "hello").output,
          "hello",
        );
      });

      test("throws ArgumentError for an unknown task id", () async {
        await expectLater(
          bundle.invokeNamed<String, String>("noSuchTask", "x"),
          throwsArgumentError,
        );
      });
    });

    group("invoke (by type)", () {
      late TaskBundle bundle;
      setUp(() => bundle = TaskBundle([EchoTask()], startCulling: false));
      tearDown(() => bundle.close());

      test("returns the correct output for a known task type", () async {
        expect(
          await bundle.invoke<String, String>(EchoTask, "world").output,
          "world",
        );
      });

      test("throws ArgumentError for an unknown task type", () async {
        await expectLater(
          bundle.invoke<String, String>(ExclusiveTask, "x"),
          throwsArgumentError,
        );
      });
    });

    group("running", () {
      test("includes task ids of spawned instances", () async {
        final bundle = TaskBundle([EchoTask()], startCulling: false);
        addTearDown(bundle.close);

        await bundle.invoke<String, String>(EchoTask, "test").output;
        expect(bundle.running, contains("echoTask"));
      });
    });

    group("allowSimultaneous = false", () {
      test(
        "throws StateError on concurrent invocation of the same task",
        () async {
          final bundle = TaskBundle([ExclusiveTask()], startCulling: false);
          addTearDown(bundle.close);

          final first = bundle.invoke<String, String>(ExclusiveTask, "first");

          await expectLater(
            bundle.invoke<String, String>(ExclusiveTask, "second"),
            throwsStateError,
          );

          await first.output;
        },
      );
    });

    group("closed bundle", () {
      test("invoke throws StateError after close", () async {
        final bundle = TaskBundle([EchoTask()], startCulling: false);
        await bundle.close();
        await expectLater(
          bundle.invoke<String, String>(EchoTask, "x"),
          throwsStateError,
        );
      });

      test("close() is idempotent", () async {
        final bundle = TaskBundle([EchoTask()], startCulling: false);
        await bundle.close();
        expect(bundle.close(), completes);
      });
    });

    group("culling", () {
      test("isCulling is false when startCulling: false is passed", () {
        final bundle = TaskBundle([EchoTask()], startCulling: false);
        addTearDown(bundle.close);
        expect(bundle.isCulling, isFalse);
      });

      test("startCulling() sets isCulling to true", () {
        final bundle = TaskBundle([EchoTask()], startCulling: false);
        addTearDown(bundle.close);
        bundle.startCulling();
        expect(bundle.isCulling, isTrue);
      });

      test("stopCulling() sets isCulling to false", () {
        final bundle = TaskBundle([EchoTask()], startCulling: false);
        addTearDown(bundle.close);
        bundle
          ..startCulling()
          ..stopCulling();
        expect(bundle.isCulling, isFalse);
      });

      test(
        "suspect timer is reset when an instance is active during a culling tick",
        () async {
          final bundle = TaskBundle([DelayedTask()], startCulling: false);
          addTearDown(bundle.close);

          bundle.startCulling(
            interval: const Duration(milliseconds: 15),
            idleTime: const Duration(milliseconds: 60),
          );

          await bundle
              .invoke<Duration, String>(
                DelayedTask,
                const Duration(milliseconds: 50),
              )
              .output;

          bundle.stopCulling();
          expect(bundle.running, contains("delayedTask"));
        },
      );

      test("task can be reinvoked after idle instance is culled", () async {
        final bundle = TaskBundle([EchoTask()], startCulling: false);
        addTearDown(bundle.close);

        await bundle.invoke<String, String>(EchoTask, "before").output;

        bundle.startCulling(
          interval: const Duration(milliseconds: 10),
          idleTime: Duration.zero,
        );
        await Future.delayed(const Duration(milliseconds: 60));
        bundle.stopCulling();

        expect(
          await bundle.invoke<String, String>(EchoTask, "after").output,
          "after",
        );
      });
    });

    group("listeners", () {
      test("listener is notified when a task completes", () async {
        final bundle = TaskBundle([EchoTask()], startCulling: false);
        addTearDown(bundle.close);

        final updates = <String>[];
        bundle.addListener(updates.add);

        await bundle.invoke<String, String>(EchoTask, "test").output;
        expect(updates, contains("echoTask"));
      });

      test("removed listener is no longer notified", () async {
        final bundle = TaskBundle([EchoTask()], startCulling: false);
        addTearDown(bundle.close);

        final updates = <String>[];
        void listener(String id) => updates.add(id);
        bundle
          ..addListener(listener)
          ..removeListener(listener);

        await bundle.invoke<String, String>(EchoTask, "test").output;
        expect(updates, isEmpty);
      });
    });

    group("progress", () {
      test("progress updates are forwarded through bundle invoke", () async {
        final bundle = TaskBundle([ProgressTask()], startCulling: false);
        addTearDown(bundle.close);

        final received = <TaskProgress>[];
        await bundle
            .invoke<int, int>(
              ProgressTask,
              3,
              progressBroadcaster: (b) => b.addListener(received.add),
            )
            .output;

        expect(received, isNotEmpty);
      });
    });
  });
}
