import 'package:scheduler/scheduler.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group("Scheduler", () {
    group("invoke (by type)", () {
      late Scheduler scheduler;
      setUp(() => scheduler = Scheduler([EchoTask(), ExclusiveTask()]));
      tearDown(() => scheduler.close());

      test("returns correct output for a known task type", () async {
        expect(
          await scheduler.invoke<String, String>(EchoTask, "hello"),
          "hello",
        );
      });

      test("throws ArgumentError for an unknown task type", () async {
        await expectLater(
          scheduler.invoke<Duration, String>(DelayedTask, Duration.zero),
          throwsArgumentError,
        );
      });
    });

    group("invokeNamed", () {
      late Scheduler scheduler;
      setUp(() => scheduler = Scheduler([EchoTask()]));
      tearDown(() => scheduler.close());

      test("returns correct output for a known task id", () async {
        expect(
          await scheduler.invokeNamed<String, String>("echoTask", "world"),
          "world",
        );
      });

      test("throws ArgumentError for an unknown task id", () async {
        await expectLater(
          scheduler.invokeNamed<String, String>("noSuchTask", "x"),
          throwsArgumentError,
        );
      });
    });

    group("priority ordering", () {
      test(
        "higher-priority tasks execute before lower-priority ones",
        () async {
          final scheduler = Scheduler([
            DelayedTask(),
            EchoTask(),
          ], config: const SchedulerConfig(simultaneousTasks: 1));
          addTearDown(scheduler.close);

          final completionOrder = <String>[];

          final blocking = scheduler.invoke<Duration, String>(
            DelayedTask,
            const Duration(milliseconds: 150),
          );

          final low = scheduler
              .invoke<String, String>(EchoTask, "low", priority: 1)
              .then((v) {
                completionOrder.add(v);
                return v;
              });
          final high = scheduler
              .invoke<String, String>(EchoTask, "high", priority: 10)
              .then((v) {
                completionOrder.add(v);
                return v;
              });

          await Future.wait([blocking, low, high]);
          expect(completionOrder, ["high", "low"]);
        },
      );
    });

    group("simultaneousTasks", () {
      test(
        "all invocations complete even with a concurrency limit of 1",
        () async {
          final scheduler = Scheduler([
            EchoTask(),
          ], config: const SchedulerConfig(simultaneousTasks: 1));
          addTearDown(scheduler.close);

          final results = await Future.wait([
            scheduler.invoke<String, String>(EchoTask, "a"),
            scheduler.invoke<String, String>(EchoTask, "b"),
            scheduler.invoke<String, String>(EchoTask, "c"),
          ]);
          expect(results.toSet(), {"a", "b", "c"});
        },
      );
    });

    group("non-simultaneous tasks", () {
      test(
        "concurrent invocations are queued (not rejected) by the scheduler",
        () async {
          final scheduler = Scheduler([
            ExclusiveTask(),
          ], config: const SchedulerConfig(simultaneousTasks: 5));
          addTearDown(scheduler.close);

          final results = await Future.wait([
            scheduler.invokeNamed<String, String>("exclusiveTask", "first"),
            scheduler.invokeNamed<String, String>("exclusiveTask", "second"),
          ]);
          expect(results.toSet(), {"first", "second"});
        },
      );
    });

    group("tasks and running", () {
      test("tasks exposes the full registered task set", () {
        final scheduler = Scheduler([EchoTask(), ExclusiveTask()]);
        addTearDown(scheduler.close);
        expect(
          scheduler.tasks.map((t) => t.id),
          containsAll(["echoTask", "exclusiveTask"]),
        );
      });

      test(
        "running contains task id after an invocation spawns an instance",
        () async {
          final scheduler = Scheduler([EchoTask()]);
          addTearDown(scheduler.close);
          await scheduler.invoke<String, String>(EchoTask, "test");
          expect(scheduler.running, contains("echoTask"));
        },
      );
    });

    group("runningInvocations", () {
      test("reflects active invocation id and task id while running", () async {
        final scheduler = Scheduler([EchoTask()]);
        addTearDown(scheduler.close);

        final invocation = scheduler.invoke<String, String>(EchoTask, "test");
        expect(scheduler.runningInvocations.values, contains("echoTask"));

        await invocation;
        expect(scheduler.runningInvocations, isEmpty);
      });
    });

    group("config setter", () {
      test("updating config replaces the current config", () {
        final scheduler = Scheduler([
          EchoTask(),
        ], config: const SchedulerConfig(simultaneousTasks: 3));
        addTearDown(scheduler.close);

        scheduler.config = const SchedulerConfig(simultaneousTasks: 7);
        expect(scheduler.config.simultaneousTasks, 7);
      });

      test(
        "setting config re-runs the queue loop, unblocking queued tasks",
        () async {
          final scheduler = Scheduler([
            EchoTask(),
          ], config: const SchedulerConfig(simultaneousTasks: 0));
          addTearDown(scheduler.close);

          final pending = scheduler.invoke<String, String>(EchoTask, "hello");

          scheduler.config = const SchedulerConfig(simultaneousTasks: 5);
          expect(await pending, "hello");
        },
      );
    });

    group("processQueue parameter", () {
      test(
        "task is not started and its future stays pending when processQueue is false",
        () async {
          final scheduler = Scheduler([EchoTask()]);
          addTearDown(scheduler.close);

          var completed = false;
          scheduler
              .invoke<String, String>(EchoTask, "queued", processQueue: false)
              .then((_) => completed = true);

          // Flush pending microtasks; nothing should have run the queue loop.
          await Future.delayed(Duration.zero);
          expect(completed, isFalse);
          expect(scheduler.running, isEmpty);
        },
      );

      test(
        "a later invoke with processQueue: true processes previously queued tasks",
        () async {
          final scheduler = Scheduler([
            EchoTask(),
          ], config: const SchedulerConfig(simultaneousTasks: 5));
          addTearDown(scheduler.close);

          final queued = scheduler.invoke<String, String>(
            EchoTask,
            "queued",
            processQueue: false,
          );
          final trigger = scheduler.invoke<String, String>(EchoTask, "trigger");

          expect(await Future.wait([queued, trigger]), ["queued", "trigger"]);
        },
      );

      test(
        "invokeNamed forwards processQueue: false without starting the task",
        () async {
          final scheduler = Scheduler([EchoTask()]);
          addTearDown(scheduler.close);

          var completed = false;
          scheduler
              .invokeNamed<String, String>(
                "echoTask",
                "queued",
                processQueue: false,
              )
              .then((_) => completed = true);

          await Future.delayed(Duration.zero);
          expect(completed, isFalse);
          expect(scheduler.running, isEmpty);

          expect(
            await scheduler.invokeNamed<String, String>("echoTask", "trigger"),
            "trigger",
          );
        },
      );

      test(
        "a queued task with processQueue: false is picked up automatically once a slot frees up",
        () async {
          final scheduler = Scheduler([
            DelayedTask(),
            EchoTask(),
          ], config: const SchedulerConfig(simultaneousTasks: 1));
          addTearDown(scheduler.close);

          final blocking = scheduler.invoke<Duration, String>(
            DelayedTask,
            const Duration(milliseconds: 100),
          );
          await Future.delayed(const Duration(milliseconds: 20));

          final queued = scheduler.invoke<String, String>(
            EchoTask,
            "later",
            processQueue: false,
          );

          expect(await Future.wait([blocking, queued]), ["done", "later"]);
        },
      );
    });

    group("error propagation", () {
      test(
        "task errors are forwarded to the invoke future via _queueLoop",
        () async {
          final scheduler = Scheduler([FailingTask()]);
          addTearDown(scheduler.close);
          await expectLater(
            scheduler.invoke<String, String>(FailingTask, "trigger"),
            throwsA(anything),
          );
        },
      );
    });

    group("close", () {
      test("close() completes without error", () async {
        final scheduler = Scheduler([EchoTask()]);
        expect(scheduler.close(), completes);
      });
    });
  });
}
