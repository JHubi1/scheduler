import 'dart:async';

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
          await scheduler.invoke<String, String>(EchoTask, "hello").output,
          "hello",
        );
      });

      test(
        "resolves once the invocation starts, before it completes",
        () async {
          final status = await scheduler.invoke<String, String>(
            EchoTask,
            "hello",
          );
          expect(status.task.id, "echoTask");
          expect(status.invocationId, isNonNegative);
          await status.future;
        },
      );

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
          await scheduler
              .invokeNamed<String, String>("echoTask", "world")
              .output,
          "world",
        );
      });

      test("throws ArgumentError for an unknown task id", () async {
        await expectLater(
          scheduler.invokeNamed<String, String>("noSuchTask", "x"),
          throwsArgumentError,
        );
      });

      test("forwards processQueueLockAssert to invoke", () async {
        final queued = scheduler.invokeNamed<String, String>(
          "echoTask",
          "queued",
          processQueue: false,
          processQueueLockAssert: false,
        );
        expect(
          await scheduler
              .invokeNamed<String, String>("echoTask", "trigger")
              .output,
          "trigger",
        );
        expect(await queued.output, "queued");
      });
    });

    group("priority ordering", () {
      test(
        "higher-priority tasks execute before lower-priority ones",
        () async {
          final scheduler = Scheduler([
            DelayedTask(),
            EchoTask(),
          ], config: const SchedulerConfig(simultaneousInvocations: 1));
          addTearDown(scheduler.close);

          final completionOrder = <String>[];

          final blocking = scheduler
              .invoke<Duration, String>(
                DelayedTask,
                const Duration(milliseconds: 150),
              )
              .output;

          final low = scheduler
              .invoke<String, String>(EchoTask, "low", priority: 1)
              .output
              .then((v) {
                completionOrder.add(v);
                return v;
              });
          final high = scheduler
              .invoke<String, String>(EchoTask, "high", priority: 10)
              .output
              .then((v) {
                completionOrder.add(v);
                return v;
              });

          await Future.wait([blocking, low, high]);
          expect(completionOrder, ["high", "low"]);
        },
      );
    });

    group("simultaneousInvocations", () {
      test(
        "all invocations complete even with a concurrency limit of 1",
        () async {
          final scheduler = Scheduler([
            EchoTask(),
          ], config: const SchedulerConfig(simultaneousInvocations: 1));
          addTearDown(scheduler.close);

          final results = await Future.wait([
            scheduler.invoke<String, String>(EchoTask, "a").output,
            scheduler.invoke<String, String>(EchoTask, "b").output,
            scheduler.invoke<String, String>(EchoTask, "c").output,
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
          ], config: const SchedulerConfig(simultaneousInvocations: 5));
          addTearDown(scheduler.close);

          final results = await Future.wait([
            scheduler
                .invokeNamed<String, String>("exclusiveTask", "first")
                .output,
            scheduler
                .invokeNamed<String, String>("exclusiveTask", "second")
                .output,
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
          await scheduler.invoke<String, String>(EchoTask, "test").output;
          expect(scheduler.running, contains("echoTask"));
        },
      );
    });

    group("runningInvocations", () {
      test("reflects active invocation id and task id while running", () async {
        final scheduler = Scheduler([EchoTask()]);
        addTearDown(scheduler.close);

        final invocation = scheduler.invoke<String, String>(EchoTask, "test");
        expect(
          scheduler.runningInvocations.values.map((s) => s.task.id),
          contains("echoTask"),
        );

        await invocation.output;
        expect(scheduler.runningInvocations, isEmpty);
      });
    });

    group("config setter", () {
      test("updating config replaces the current config", () {
        final scheduler = Scheduler([
          EchoTask(),
        ], config: const SchedulerConfig(simultaneousInvocations: 3));
        addTearDown(scheduler.close);

        scheduler.config = const SchedulerConfig(simultaneousInvocations: 7);
        expect(scheduler.config.simultaneousInvocations, 7);
      });

      test(
        "setting config re-runs the queue loop, unblocking queued tasks",
        () async {
          final scheduler = Scheduler([
            EchoTask(),
          ], config: const SchedulerConfig(simultaneousInvocations: 0));
          addTearDown(scheduler.close);

          final pending = scheduler
              .invoke<String, String>(EchoTask, "hello")
              .output;

          scheduler.config = const SchedulerConfig(simultaneousInvocations: 5);
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
              .invoke<String, String>(
                EchoTask,
                "queued",
                processQueue: false,
                processQueueLockAssert: false,
              )
              .then((_) => completed = true);

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
          ], config: const SchedulerConfig(simultaneousInvocations: 5));
          addTearDown(scheduler.close);

          final queued = scheduler
              .invoke<String, String>(EchoTask, "queued", processQueue: false)
              .output;
          final trigger = scheduler
              .invoke<String, String>(EchoTask, "trigger")
              .output;

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
                processQueueLockAssert: false,
              )
              .then((_) => completed = true);

          await Future.delayed(Duration.zero);
          expect(completed, isFalse);
          expect(scheduler.running, isEmpty);

          expect(
            await scheduler
                .invokeNamed<String, String>("echoTask", "trigger")
                .output,
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
          ], config: const SchedulerConfig(simultaneousInvocations: 1));
          addTearDown(scheduler.close);

          final blocking = scheduler
              .invoke<Duration, String>(
                DelayedTask,
                const Duration(milliseconds: 100),
              )
              .output;
          await Future.delayed(const Duration(milliseconds: 20));

          final queued = scheduler
              .invoke<String, String>(EchoTask, "later", processQueue: false)
              .output;

          expect(await Future.wait([blocking, queued]), ["done", "later"]);
        },
      );
    });

    group("queueExpiration", () {
      test(
        "an invocation that expires in the queue fails with a TimeoutException "
        "instead of hanging forever",
        () async {
          final scheduler = Scheduler([
            DelayedTask(),
            EchoTask(),
          ], config: const SchedulerConfig(simultaneousInvocations: 1));
          addTearDown(scheduler.close);

          scheduler.invoke<Duration, String>(
            DelayedTask,
            const Duration(milliseconds: 200),
          );

          final future = scheduler.invoke<String, String>(
            EchoTask,
            "expired",
            queueExpiration: const Duration(milliseconds: 20),
          );

          await expectLater(future, throwsA(isA<TimeoutException>()));
        },
      );

      test(
        "an invocation started before it expires completes normally",
        () async {
          final scheduler = Scheduler([EchoTask()]);
          addTearDown(scheduler.close);

          expect(
            await scheduler
                .invoke<String, String>(
                  EchoTask,
                  "hello",
                  queueExpiration: const Duration(seconds: 5),
                )
                .output,
            "hello",
          );
        },
      );

      test("no expiration is applied when queueExpiration is null", () async {
        final scheduler = Scheduler([
          DelayedTask(),
          EchoTask(),
        ], config: const SchedulerConfig(simultaneousInvocations: 1));
        addTearDown(scheduler.close);

        scheduler.invoke<Duration, String>(
          DelayedTask,
          const Duration(milliseconds: 100),
        );

        expect(
          await scheduler.invoke<String, String>(EchoTask, "eventually").output,
          "eventually",
        );
      });
    });

    group("processQueueLockAssert", () {
      test(
        "asserts if the queue loop is never triggered after processQueue: false",
        () async {
          final scheduler = Scheduler([EchoTask()]);
          addTearDown(scheduler.close);

          Object? caughtError;
          final done = Completer<void>();
          runZonedGuarded(
            () {
              scheduler.invoke<String, String>(
                EchoTask,
                "stuck",
                processQueue: false,
              );
            },
            (error, stack) {
              caughtError = error;
              if (!done.isCompleted) done.complete();
            },
          );

          await done.future.timeout(const Duration(seconds: 8));
          expect(caughtError, isA<AssertionError>());
        },
        timeout: const Timeout(Duration(seconds: 15)),
      );

      test(
        "does not assert when processQueueLockAssert is false",
        () async {
          final scheduler = Scheduler([EchoTask()]);
          addTearDown(scheduler.close);

          Object? caughtError;
          runZonedGuarded(
            () {
              scheduler.invoke<String, String>(
                EchoTask,
                "stuck",
                processQueue: false,
                processQueueLockAssert: false,
              );
            },
            (error, stack) => caughtError = error,
          );

          await Future.delayed(const Duration(seconds: 6));
          expect(caughtError, isNull);
        },
        timeout: const Timeout(Duration(seconds: 15)),
      );
    });

    group("error propagation", () {
      test(
        "task errors surface through TaskStatus.future, not the invoke() future",
        () async {
          final scheduler = Scheduler([FailingTask()]);
          addTearDown(scheduler.close);

          final status = await scheduler.invoke<String, String>(
            FailingTask,
            "trigger",
          );
          final result = await status.future;
          expect(result.error, isNotNull);
          expect(result.success, isNull);
        },
      );

      test("the .output helper rethrows the original task error", () async {
        final scheduler = Scheduler([FailingTask()]);
        addTearDown(scheduler.close);
        await expectLater(
          scheduler.invoke<String, String>(FailingTask, "trigger").output,
          throwsA(anything),
        );
      });
    });

    group("retryOptions", () {
      test(
        "a task that fails twice succeeds on the third attempt with default retryOptions",
        () async {
          final scheduler = Scheduler([RetryableTask()]);
          addTearDown(scheduler.close);

          final status = await scheduler.invoke<String, String>(
            RetryableTask,
            "hello",
          );
          final result = await status.future;
          expect(result.success?.output, "hello");
        },
      );

      test(
        "a permanently-failing task exhausts retryOptions.maxAttempts",
        () async {
          final scheduler = Scheduler(
            [AlwaysFailingRetryableTask()],
            config: const SchedulerConfig(
              retryOptions: RetryOptions(maxAttempts: 2),
            ),
          );
          addTearDown(scheduler.close);

          final status = await scheduler.invoke<String, String>(
            AlwaysFailingRetryableTask,
            "hello",
          );
          final result = await status.future;
          expect(result.error, isNotNull);
          expect(result.error!.retryCount, 1);
        },
      );
    });

    group("completeRunningInvocations", () {
      test("resolves immediately when nothing is running", () async {
        final scheduler = Scheduler([EchoTask()]);
        addTearDown(scheduler.close);
        await expectLater(scheduler.completeRunningInvocations, completes);
      });

      test("resolves once all running invocations have completed", () async {
        final scheduler = Scheduler([DelayedTask()]);
        addTearDown(scheduler.close);

        scheduler.invoke<Duration, String>(
          DelayedTask,
          const Duration(milliseconds: 100),
        );
        final completeFuture = scheduler.completeRunningInvocations;
        var completed = false;
        completeFuture.then((_) => completed = true);

        await Future.delayed(const Duration(milliseconds: 20));
        expect(completed, isFalse);

        await completeFuture;
        expect(completed, isTrue);
      });
    });

    group("close", () {
      test("close() completes without error", () async {
        final scheduler = Scheduler([EchoTask()]);
        expect(scheduler.close(), completes);
      });

      test(
        "graceful close waits for running invocations to complete",
        () async {
          final scheduler = Scheduler([DelayedTask()]);
          final invocation = scheduler
              .invoke<Duration, String>(
                DelayedTask,
                const Duration(milliseconds: 100),
              )
              .output;

          await scheduler.close();
          expect(await invocation, "done");
        },
      );

      test(
        "gracefulTimeout stops waiting for slow invocations after the timeout",
        () async {
          final scheduler = Scheduler([DelayedTask()])
            ..invoke<Duration, String>(DelayedTask, const Duration(seconds: 5));

          final stopwatch = Stopwatch()..start();
          await scheduler.close(
            gracefulTimeout: const Duration(milliseconds: 100),
          );
          stopwatch.stop();

          expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
        },
      );

      test("graceful: false closes immediately without waiting", () async {
        final scheduler = Scheduler([DelayedTask()])
          ..invoke<Duration, String>(DelayedTask, const Duration(seconds: 5));

        final stopwatch = Stopwatch()..start();
        await scheduler.close(graceful: false, silent: true);
        stopwatch.stop();

        expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
      });
    });

    group("restorableState / fromRestorableState", () {
      test(
        "restorableState only includes invocations from restoration-allowed tasks",
        () async {
          final scheduler =
              Scheduler([
                  RestorableTask(),
                  EchoTask(),
                ], config: const SchedulerConfig(simultaneousInvocations: 0))
                ..invoke<String, String>(
                  RestorableTask,
                  "keep",
                  processQueue: false,
                  processQueueLockAssert: false,
                )
                ..invoke<String, String>(
                  EchoTask,
                  "drop",
                  processQueue: false,
                  processQueueLockAssert: false,
                );
          addTearDown(scheduler.close);

          final state = scheduler.restorableState();
          final invocations = state["invocations"]! as List;
          expect(invocations, hasLength(1));
          expect((invocations.single! as Map)["task"], "restorableTask");
        },
      );

      test(
        "fromRestorableState restores queued invocations and runs them",
        () async {
          final tasks = [RestorableTask()];
          final state = {
            "config": const SchedulerConfig().toJson(),
            "taskIds": ["restorableTask"],
            "invocations": [
              {
                "task": "restorableTask",
                "input": "restored",
                "priority": 0,
                "wasRunning": false,
              },
            ],
          };

          final scheduler = Scheduler.fromRestorableState(tasks, state);
          addTearDown(scheduler.close);

          expect(scheduler.runningInvocations.values.map((s) => s.task.id), [
            "restorableTask",
          ]);
        },
      );

      test(
        "fromRestorableState throws ArgumentError for an unknown task id",
        () {
          final tasks = [RestorableTask()];
          final state = {
            "config": const SchedulerConfig().toJson(),
            "taskIds": ["restorableTask", "noSuchTask"],
            "invocations": <Object?>[],
          };

          expect(
            () => Scheduler.fromRestorableState(tasks, state),
            throwsArgumentError,
          );
        },
      );

      test(
        "fromRestorableState throws ArgumentError for a non-restorable task",
        () {
          final tasks = [EchoTask()];
          final state = {
            "config": const SchedulerConfig().toJson(),
            "taskIds": ["echoTask"],
            "invocations": [
              {
                "task": "echoTask",
                "input": "x",
                "priority": 0,
                "wasRunning": false,
              },
            ],
          };

          expect(
            () => Scheduler.fromRestorableState(tasks, state),
            throwsArgumentError,
          );
        },
      );

      test("fromRestorableState throws ArgumentError for malformed state", () {
        expect(
          () => Scheduler.fromRestorableState(
            [RestorableTask()],
            {"not": "valid"},
          ),
          throwsArgumentError,
        );
      });

      test(
        "restorableState round-trips through SchedulerConfig.toJson/fromJson",
        () {
          final scheduler = Scheduler([
            RestorableTask(),
          ], config: const SchedulerConfig(simultaneousInvocations: 2));
          addTearDown(scheduler.close);

          final state = scheduler.restorableState();
          final config = SchedulerConfig.fromJson(
            state["config"]! as Map<String, Object?>,
          );
          expect(config.simultaneousInvocations, 2);
        },
      );
    });
  });
}
