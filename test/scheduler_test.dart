import 'dart:async';

import 'package:scheduler/scheduler.dart';
import 'package:scheduler/tasks.dart' show TaskProgressBroadcaster;
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

      test(
        "throws a friendly StateError for a task id/type mismatch",
        () async {
          await expectLater(
            scheduler.invokeNamed<int, int>("echoTask", 5),
            throwsA(isA<StateError>()),
          );
        },
      );

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
          ], config: const SchedulerConfig(simultaneousInvocations: 5));
          addTearDown(scheduler.close);

          final pending = scheduler
              .invoke<String, String>(
                EchoTask,
                "hello",
                processQueue: false,
                processQueueLockAssert: false,
              )
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
          addTearDown(() => scheduler.close(silent: true));

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

      test("does not assert when processQueueLockAssert is false", () async {
        final scheduler = Scheduler([EchoTask()]);
        addTearDown(scheduler.close);

        Object? caughtError;
        runZonedGuarded(() {
          scheduler.invoke<String, String>(
            EchoTask,
            "stuck",
            processQueue: false,
            processQueueLockAssert: false,
          );
        }, (error, stack) => caughtError = error);

        await Future.delayed(const Duration(seconds: 6));
        expect(caughtError, isNull);
      }, timeout: const Timeout(Duration(seconds: 15)));
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
                ], config: const SchedulerConfig(simultaneousInvocations: 1))
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
          addTearDown(() => scheduler.close(silent: true));

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
                "allowRestoration": true,
                "queueExpiration": null,
                "wasRunning": false,
                "_addedToQueue": null,
              },
            ],
            "waitList": <Object?>[],
          };

          final scheduler = Scheduler.fromRestorableState(tasks, state);
          addTearDown(scheduler.close);

          expect(scheduler.runningInvocations.values.map((s) => s.task.id), [
            "restorableTask",
          ]);
        },
      );

      test("fromRestorableState restores an invocation's queueExpiration and "
          "_addedToQueue values", () async {
        final tasks = [RestorableTask()];
        final now = DateTime.now();
        final state = {
          "config": const SchedulerConfig().toJson(),
          "taskIds": ["restorableTask"],
          "invocations": [
            {
              "task": "restorableTask",
              "input": "restored",
              "priority": 0,
              "allowRestoration": true,
              "queueExpiration": 30000,
              "wasRunning": false,
              "_addedToQueue": now.toIso8601String(),
            },
          ],
          "waitList": <Object?>[],
        };

        final scheduler = Scheduler.fromRestorableState(tasks, state);
        addTearDown(() => scheduler.close(silent: true));

        expect(scheduler.runningInvocations.values.map((s) => s.task.id), [
          "restorableTask",
        ]);
      });

      test(
        "fromRestorableState throws ArgumentError for an unknown task id",
        () {
          final tasks = [RestorableTask()];
          final state = {
            "config": const SchedulerConfig().toJson(),
            "taskIds": ["restorableTask", "noSuchTask"],
            "invocations": <Object?>[],
            "waitList": <Object?>[],
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
                "allowRestoration": true,
                "queueExpiration": null,
                "wasRunning": false,
                "_addedToQueue": null,
              },
            ],
            "waitList": <Object?>[],
          };

          expect(
            () => Scheduler.fromRestorableState(tasks, state),
            throwsArgumentError,
          );
        },
      );

      test("fromRestorableState throws ArgumentError when an invocation's "
          "allowRestoration flag is false, even for a restorable task", () {
        final tasks = [RestorableTask()];
        final state = {
          "config": const SchedulerConfig().toJson(),
          "taskIds": ["restorableTask"],
          "invocations": [
            {
              "task": "restorableTask",
              "input": "x",
              "priority": 0,
              "allowRestoration": false,
              "queueExpiration": null,
              "wasRunning": false,
              "_addedToQueue": null,
            },
          ],
          "waitList": <Object?>[],
        };

        expect(
          () => Scheduler.fromRestorableState(tasks, state),
          throwsArgumentError,
        );
      });

      test("fromRestorableState throws ArgumentError for an invocation "
          "referencing a task id absent from taskIds", () {
        final tasks = [RestorableTask()];
        final state = {
          "config": const SchedulerConfig().toJson(),
          "taskIds": ["restorableTask"],
          "invocations": [
            {
              "task": "someOtherTask",
              "input": "x",
              "priority": 0,
              "allowRestoration": true,
              "queueExpiration": null,
              "wasRunning": false,
              "_addedToQueue": null,
            },
          ],
          "waitList": <Object?>[],
        };

        expect(
          () => Scheduler.fromRestorableState(tasks, state),
          throwsArgumentError,
        );
      });

      test(
        "fromRestorableState throws ArgumentError for a malformed invocation entry",
        () {
          final tasks = [RestorableTask()];
          final state = {
            "config": const SchedulerConfig().toJson(),
            "taskIds": ["restorableTask"],
            "invocations": [
              {"task": "restorableTask"},
            ],
            "waitList": <Object?>[],
          };

          expect(
            () => Scheduler.fromRestorableState(tasks, state),
            throwsArgumentError,
          );
        },
      );

      test(
        "fromRestorableState throws ArgumentError for an invalid config",
        () {
          final tasks = [RestorableTask()];
          final state = {
            "config": {"simultaneousInvocations": 0},
            "taskIds": ["restorableTask"],
            "invocations": <Object?>[],
            "waitList": <Object?>[],
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

      test("restorableState serializes a still-waiting delayed invocation", () {
        final scheduler = Scheduler([RestorableTask()]);
        addTearDown(() => scheduler.close(silent: true));

        scheduler.delayed<String, String>(
          RestorableTask,
          "x",
          const Duration(minutes: 1),
        );

        final state = scheduler.restorableState();
        final waitList = state["waitList"]! as List;
        expect(waitList, hasLength(1));
        final entry = waitList.single! as Map;
        expect(entry["task"], "restorableTask");
        expect(entry["input"], "x");
        expect(entry["cron"], isNull);
        expect(entry["delay"], const Duration(minutes: 1).inMilliseconds);
      });
    });

    group("fromRestorableState wait list", () {
      test("restores a queued delayed invocation and lets it run", () async {
        final tasks = [RestorableTask()];
        final now = DateTime.now();
        final state = {
          "config": const SchedulerConfig().toJson(),
          "taskIds": ["restorableTask"],
          "invocations": <Object?>[],
          "waitList": [
            {
              "task": "restorableTask",
              "input": "restored",
              "priority": 0,
              "allowRestoration": true,
              "queueExpiration": null,
              "wasRunning": false,
              "_addedToQueue": null,
              "delay": 200,
              "dateTime": now
                  .add(const Duration(milliseconds: 200))
                  .toIso8601String(),
              "cron": null,
              "cronId": null,
              "cronReoccurrencesRemaining": null,
              "cronIsUtc": null,
              "_addedToWaitList": now.toIso8601String(),
            },
          ],
        };

        final scheduler = Scheduler.fromRestorableState(tasks, state);
        addTearDown(() => scheduler.close(silent: true));

        expect(scheduler.queueWaitList, hasLength(1));
        await _waitUntil(() => scheduler.running.contains("restorableTask"));
        expect(scheduler.queueWaitList, isEmpty);
      });

      test("restores a cron wait list entry with its Cron expression", () {
        final tasks = [RestorableTask()];
        final now = DateTime.now();
        final state = {
          "config": const SchedulerConfig().toJson(),
          "taskIds": ["restorableTask"],
          "invocations": <Object?>[],
          "waitList": [
            {
              "task": "restorableTask",
              "input": "restored",
              "priority": 0,
              "allowRestoration": true,
              "queueExpiration": null,
              "wasRunning": false,
              "_addedToQueue": null,
              "delay": 60000,
              "dateTime": now.add(const Duration(minutes: 1)).toIso8601String(),
              "cron": "* * * * * *",
              "cronId": "restoredCron",
              "cronReoccurrencesRemaining": 3,
              "cronIsUtc": false,
              "_addedToWaitList": now.toIso8601String(),
            },
          ],
        };

        final scheduler = Scheduler.fromRestorableState(tasks, state);
        addTearDown(() => scheduler.close(silent: true));

        expect(scheduler.cronTasks, hasLength(1));
        final task = scheduler.cronTasks.single;
        expect(task.cron, Cron.parse("* * * * * *"));
        expect(task.reoccurrencesRemaining, 3);
      });

      test("blocks the cronId of a restored cron entry from being reused", () {
        final tasks = [RestorableVoidTask()];
        final now = DateTime.now();
        final state = {
          "config": const SchedulerConfig().toJson(),
          "taskIds": ["restorableVoidTask"],
          "invocations": <Object?>[],
          "waitList": [
            {
              "task": "restorableVoidTask",
              "input": 1,
              "priority": 0,
              "allowRestoration": true,
              "queueExpiration": null,
              "wasRunning": false,
              "_addedToQueue": null,
              "delay": 60000,
              "dateTime": now.add(const Duration(minutes: 1)).toIso8601String(),
              "cron": "* * * * * *",
              "cronId": "restoredCron",
              "cronReoccurrencesRemaining": null,
              "cronIsUtc": false,
              "_addedToWaitList": now.toIso8601String(),
            },
          ],
        };

        final scheduler = Scheduler.fromRestorableState(tasks, state);
        addTearDown(() => scheduler.close(silent: true));

        expect(
          () => scheduler.cron<int>(
            RestorableVoidTask,
            1,
            Cron.parse("* * * * * *"),
            cronId: "restoredCron",
          ),
          throwsArgumentError,
        );
      });

      test(
        "throws ArgumentError when the wait list contains a duplicate cronId",
        () {
          final tasks = [RestorableVoidTask()];
          final now = DateTime.now();
          final entry = {
            "task": "restorableVoidTask",
            "input": 1,
            "priority": 0,
            "allowRestoration": true,
            "queueExpiration": null,
            "wasRunning": false,
            "_addedToQueue": null,
            "delay": 60000,
            "dateTime": now.add(const Duration(minutes: 1)).toIso8601String(),
            "cron": "* * * * * *",
            "cronId": "duplicateCron",
            "cronReoccurrencesRemaining": null,
            "cronIsUtc": false,
            "_addedToWaitList": now.toIso8601String(),
          };
          final state = {
            "config": const SchedulerConfig().toJson(),
            "taskIds": ["restorableVoidTask"],
            "invocations": <Object?>[],
            "waitList": [entry, entry],
          };

          expect(
            () => Scheduler.fromRestorableState(tasks, state),
            throwsArgumentError,
          );
        },
      );

      test("throws ArgumentError when 'cron' is set but 'cronId' is null", () {
        final tasks = [RestorableVoidTask()];
        final now = DateTime.now();
        final state = {
          "config": const SchedulerConfig().toJson(),
          "taskIds": ["restorableVoidTask"],
          "invocations": <Object?>[],
          "waitList": [
            {
              "task": "restorableVoidTask",
              "input": 1,
              "priority": 0,
              "allowRestoration": true,
              "queueExpiration": null,
              "wasRunning": false,
              "_addedToQueue": null,
              "delay": 60000,
              "dateTime": now.add(const Duration(minutes: 1)).toIso8601String(),
              "cron": "* * * * * *",
              "cronId": null,
              "cronReoccurrencesRemaining": null,
              "cronIsUtc": false,
              "_addedToWaitList": now.toIso8601String(),
            },
          ],
        };

        expect(
          () => Scheduler.fromRestorableState(tasks, state),
          throwsArgumentError,
        );
      });

      test("throws ArgumentError when 'cronId' is set but 'cron' is null", () {
        final tasks = [RestorableVoidTask()];
        final now = DateTime.now();
        final state = {
          "config": const SchedulerConfig().toJson(),
          "taskIds": ["restorableVoidTask"],
          "invocations": <Object?>[],
          "waitList": [
            {
              "task": "restorableVoidTask",
              "input": 1,
              "priority": 0,
              "allowRestoration": true,
              "queueExpiration": null,
              "wasRunning": false,
              "_addedToQueue": null,
              "delay": 60000,
              "dateTime": now.add(const Duration(minutes: 1)).toIso8601String(),
              "cron": null,
              "cronId": "orphanCronId",
              "cronReoccurrencesRemaining": null,
              "cronIsUtc": null,
              "_addedToWaitList": now.toIso8601String(),
            },
          ],
        };

        expect(
          () => Scheduler.fromRestorableState(tasks, state),
          throwsArgumentError,
        );
      });

      test("skips a wait list entry whose scheduled time already passed", () {
        final tasks = [RestorableTask()];
        final now = DateTime.now();
        final state = {
          "config": const SchedulerConfig().toJson(),
          "taskIds": ["restorableTask"],
          "invocations": <Object?>[],
          "waitList": [
            {
              "task": "restorableTask",
              "input": "restored",
              "priority": 0,
              "allowRestoration": true,
              "queueExpiration": null,
              "wasRunning": false,
              "_addedToQueue": null,
              "delay": 1000,
              "dateTime": now
                  .subtract(const Duration(seconds: 5))
                  .toIso8601String(),
              "cron": null,
              "cronId": null,
              "cronReoccurrencesRemaining": null,
              "cronIsUtc": null,
              "_addedToWaitList": now
                  .subtract(const Duration(seconds: 6))
                  .toIso8601String(),
            },
          ],
        };

        final scheduler = Scheduler.fromRestorableState(tasks, state);
        addTearDown(() => scheduler.close(silent: true));

        expect(scheduler.queueWaitList, isEmpty);
      });

      test(
        "recomputes the next run for an overdue cron wait list entry instead "
        "of skipping it",
        () {
          final tasks = [RestorableVoidTask()];
          final now = DateTime.now();
          final state = {
            "config": const SchedulerConfig().toJson(),
            "taskIds": ["restorableVoidTask"],
            "invocations": <Object?>[],
            "waitList": [
              {
                "task": "restorableVoidTask",
                "input": 1,
                "priority": 0,
                "allowRestoration": true,
                "queueExpiration": null,
                "wasRunning": false,
                "_addedToQueue": null,
                "delay": 1000,
                // Overdue: the scheduled dateTime is in the past.
                "dateTime": now
                    .subtract(const Duration(minutes: 5))
                    .toIso8601String(),
                "cron": "0 0 0 1 1 *", // once a year, so never overdue again
                "cronId": "overdueCron",
                "cronReoccurrencesRemaining": null,
                "cronIsUtc": false,
                "_addedToWaitList": now
                    .subtract(const Duration(minutes: 6))
                    .toIso8601String(),
              },
            ],
          };

          final scheduler = Scheduler.fromRestorableState(tasks, state);
          addTearDown(() => scheduler.close(silent: true));

          expect(scheduler.queueWaitList, hasLength(1));
          expect(scheduler.queueWaitList.single.delay.isNegative, isFalse);
        },
      );

      test("throws ArgumentError for an unknown task id in the wait list", () {
        final tasks = [RestorableTask()];
        final now = DateTime.now();
        final state = {
          "config": const SchedulerConfig().toJson(),
          "taskIds": ["restorableTask"],
          "invocations": <Object?>[],
          "waitList": [
            {
              "task": "unknownTask",
              "input": "x",
              "priority": 0,
              "allowRestoration": true,
              "queueExpiration": null,
              "wasRunning": false,
              "_addedToQueue": null,
              "delay": 1000,
              "dateTime": now.add(const Duration(seconds: 5)).toIso8601String(),
              "cron": null,
              "cronId": null,
              "cronReoccurrencesRemaining": null,
              "cronIsUtc": null,
              "_addedToWaitList": now.toIso8601String(),
            },
          ],
        };

        expect(
          () => Scheduler.fromRestorableState(tasks, state),
          throwsArgumentError,
        );
      });

      test(
        "throws ArgumentError for a non-restorable task in the wait list",
        () {
          final tasks = [EchoTask()];
          final now = DateTime.now();
          final state = {
            "config": const SchedulerConfig().toJson(),
            "taskIds": ["echoTask"],
            "invocations": <Object?>[],
            "waitList": [
              {
                "task": "echoTask",
                "input": "x",
                "priority": 0,
                "allowRestoration": true,
                "queueExpiration": null,
                "wasRunning": false,
                "_addedToQueue": null,
                "delay": 1000,
                "dateTime": now
                    .add(const Duration(seconds: 5))
                    .toIso8601String(),
                "cron": null,
                "cronId": null,
                "cronReoccurrencesRemaining": null,
                "cronIsUtc": null,
                "_addedToWaitList": now.toIso8601String(),
              },
            ],
          };

          expect(
            () => Scheduler.fromRestorableState(tasks, state),
            throwsArgumentError,
          );
        },
      );

      test("throws ArgumentError for a malformed wait list entry", () {
        final tasks = [RestorableTask()];
        final state = {
          "config": const SchedulerConfig().toJson(),
          "taskIds": ["restorableTask"],
          "invocations": <Object?>[],
          "waitList": [
            {"task": "restorableTask"},
          ],
        };

        expect(
          () => Scheduler.fromRestorableState(tasks, state),
          throwsArgumentError,
        );
      });
    });

    group("delayed", () {
      late Scheduler scheduler;
      setUp(() => scheduler = Scheduler([EchoTask()]));
      tearDown(() => scheduler.close());

      test(
        "queues the invocation immediately but only runs it after the delay",
        () async {
          final future = scheduler.delayed<String, String>(
            EchoTask,
            "hello",
            const Duration(milliseconds: 200),
          );

          expect(scheduler.queueWaitList, hasLength(1));
          expect(scheduler.running, isEmpty);

          final status = await future;
          expect(await status.output, "hello");
          expect(scheduler.queueWaitList, isEmpty);
        },
      );

      test(
        "throws ArgumentError when delay is not greater than zero",
        () async {
          await expectLater(
            scheduler.delayed<String, String>(EchoTask, "x", Duration.zero),
            throwsArgumentError,
          );
        },
      );

      test("throws ArgumentError for an unknown task type", () async {
        await expectLater(
          scheduler.delayed<Duration, String>(
            DelayedTask,
            Duration.zero,
            const Duration(seconds: 1),
          ),
          throwsArgumentError,
        );
      });

      test(
        "throws a friendly StateError for a task type/generic mismatch",
        () async {
          await expectLater(
            scheduler.delayed<int, int>(
              EchoTask,
              5,
              const Duration(milliseconds: 200),
            ),
            throwsA(isA<StateError>()),
          );
        },
      );

      test(
        "supports a catchError callback alongside a successful invocation",
        () async {
          var catchErrorCalled = false;
          final status = await scheduler.delayed<String, String>(
            EchoTask,
            "x",
            const Duration(milliseconds: 50),
            catchError: (error, stackTrace) {
              catchErrorCalled = true;
              throw error;
            },
          );

          expect(await status.output, "x");
          expect(catchErrorCalled, isFalse);
        },
      );
    });

    group("cron", () {
      late Scheduler scheduler;
      setUp(() => scheduler = Scheduler([VoidTask()]));
      // cron() doesn't expose a future to the caller, so a still-recurring
      // invocation is left uncompleted; close silently to avoid an unhandled
      // completer error on teardown.
      tearDown(() => scheduler.close(silent: true));

      test("schedules the task and exposes it via cronTasks immediately", () {
        scheduler.cron<int>(
          VoidTask,
          1,
          Cron.parse("* * * * * *"),
          cronId: "myCron",
          cronReoccurrences: 2,
        );

        expect(scheduler.cronTasks, hasLength(1));
        final task = scheduler.cronTasks.single;
        expect(task.cronId, "myCron");
        expect(task.cron, Cron.parse("* * * * * *"));
        expect(task.reoccurrencesRemaining, 2);
      });

      group("timezone handling", () {
        late Scheduler restorableScheduler;
        setUp(() => restorableScheduler = Scheduler([RestorableVoidTask()]));
        tearDown(() => restorableScheduler.close(silent: true));

        // Reschedules must keep matching the cron fields against the same
        // timezone the chain started in (see SchedulerDelayedPackage's
        // cronIsUtc field/_startTimer) instead of always switching to UTC
        // after the first run, since DateTime.timestamp() (used to compute
        // "now" for every run after the first) is always UTC.
        test(
          "records cronIsUtc: false in restorableState for a local startTime",
          () {
            restorableScheduler.cron<int>(
              RestorableVoidTask,
              1,
              Cron.parse("* * * * * *"),
              cronId: "localStartTime",
              allowRestoration: true,
              startTime: DateTime.now().add(const Duration(minutes: 1)),
            );

            final entry =
                (restorableScheduler.restorableState()["waitList"]! as List)
                        .single
                    as Map;
            expect(entry["cronIsUtc"], isFalse);
          },
        );

        test(
          "records cronIsUtc: true in restorableState for a UTC startTime",
          () {
            restorableScheduler.cron<int>(
              RestorableVoidTask,
              1,
              Cron.parse("* * * * * *"),
              cronId: "utcStartTime",
              allowRestoration: true,
              startTime: DateTime.now().toUtc().add(const Duration(minutes: 1)),
            );

            final entry =
                (restorableScheduler.restorableState()["waitList"]! as List)
                        .single
                    as Map;
            expect(entry["cronIsUtc"], isTrue);
          },
        );

        test("records cronIsUtc: true by default, since DateTime.timestamp() "
            "(the default startTime) is always UTC", () {
          restorableScheduler.cron<int>(
            RestorableVoidTask,
            1,
            Cron.parse("* * * * * *"),
            cronId: "defaultStartTime",
            allowRestoration: true,
          );

          final entry =
              (restorableScheduler.restorableState()["waitList"]! as List)
                      .single
                  as Map;
          expect(entry["cronIsUtc"], isTrue);
        });

        test(
          "fromRestorableState preserves cronIsUtc: false through a restore",
          () {
            final now = DateTime.now();
            final state = {
              "config": const SchedulerConfig().toJson(),
              "taskIds": ["restorableVoidTask"],
              "invocations": <Object?>[],
              "waitList": [
                {
                  "task": "restorableVoidTask",
                  "input": 1,
                  "priority": 0,
                  "allowRestoration": true,
                  "queueExpiration": null,
                  "wasRunning": false,
                  "_addedToQueue": null,
                  "delay": 60000,
                  "dateTime": now
                      .add(const Duration(minutes: 1))
                      .toIso8601String(),
                  "cron": "* * * * * *",
                  "cronId": "restoredLocalCron",
                  "cronReoccurrencesRemaining": null,
                  "cronIsUtc": false,
                  "_addedToWaitList": now.toIso8601String(),
                },
              ],
            };

            final restored = Scheduler.fromRestorableState([
              RestorableVoidTask(),
            ], state);
            addTearDown(() => restored.close(silent: true));

            final entry =
                (restored.restorableState()["waitList"]! as List).single as Map;
            expect(entry["cronIsUtc"], isFalse);
          },
        );
      });

      test("recurs the configured number of times, then stops", () async {
        scheduler.cron<int>(
          VoidTask,
          1,
          Cron.parse("* * * * * *"),
          cronId: "recursTheConfiguredNumberOfTimesThenStops",
          cronReoccurrences: 2,
        );
        expect(scheduler.cronTasks.single.reoccurrencesRemaining, 2);

        await _waitUntil(() => scheduler.cronTasks.isEmpty);
        expect(scheduler.cronTasks, isEmpty);
      }, timeout: const Timeout(Duration(seconds: 10)));

      test("recurs indefinitely when cronReoccurrences is null", () {
        scheduler.cron<int>(
          VoidTask,
          1,
          Cron.parse("* * * * * *"),
          cronId: "recursIndefinitelyWhenCronReoccurrencesIsNull",
        );
        expect(scheduler.cronTasks.single.reoccurrencesRemaining, isNull);
      });

      test("throws ArgumentError for an unknown task type", () {
        expect(
          () => scheduler.cron<Duration>(
            DelayedTask,
            Duration.zero,
            Cron.parse("* * * * * *"),
            cronId: "throwsArgumentErrorForAnUnknownTaskType",
          ),
          throwsArgumentError,
        );
      });

      test("throws a friendly StateError for a task type/generic mismatch", () {
        final mismatchScheduler = Scheduler([VoidTask(), EchoTask()]);
        addTearDown(() => mismatchScheduler.close(silent: true));

        expect(
          () => mismatchScheduler.cron<int>(
            EchoTask,
            1,
            Cron.parse("* * * * * *"),
            cronId: "throwsAFriendlyStateErrorForATaskTypeGenericMismatch",
          ),
          throwsA(isA<StateError>()),
        );
      });

      test("throws ArgumentError when startTime is not in the future", () {
        expect(
          () => scheduler.cron<int>(
            VoidTask,
            1,
            Cron.parse("* * * * * *"),
            startTime: DateTime.now().subtract(const Duration(seconds: 1)),
            cronId: "throwsArgumentErrorWhenStartTimeIsNotInTheFuture",
          ),
          throwsArgumentError,
        );
      });

      test("throws ArgumentError when cronId is not camelCase", () {
        expect(
          () => scheduler.cron<int>(
            VoidTask,
            1,
            Cron.parse("* * * * * *"),
            cronId: "Throws ArgumentError when cronId is not camelCase",
          ),
          throwsArgumentError,
        );
      });

      test("throws ArgumentError when cronReoccurrences is not positive", () {
        expect(
          () => scheduler.cron<int>(
            VoidTask,
            1,
            Cron.parse("* * * * * *"),
            cronId: "throwsArgumentErrorWhenCronReoccurrencesIsNotPositive",
            cronReoccurrences: 0,
          ),
          throwsArgumentError,
        );
      });

      test(
        "stops recurring once the scheduler is closed while the cron task is waiting",
        () async {
          scheduler.cron<int>(
            VoidTask,
            1,
            Cron.parse("* * * * * *"),
            cronId:
                "stopsRecurringOnceTheSchedulerIsClosedWhileTheCronTaskIsWaiting",
          );
          expect(scheduler.cronTasks, hasLength(1));

          await scheduler.close(silent: true);
          expect(scheduler.queueWaitList, isEmpty);
        },
      );

      test(
        "allowRestoration defaults to false and is excluded from restorableState",
        () {
          scheduler.cron<int>(
            VoidTask,
            1,
            Cron.parse("* * * * * *"),
            cronId:
                "allowRestorationDefaultsToFalseAndIsExcludedFromRestorableState",
          );

          final state = scheduler.restorableState();
          expect(state["waitList"], isEmpty);
        },
      );
    });

    group("CronTaskStatus", () {
      late Scheduler scheduler;
      setUp(() => scheduler = Scheduler([VoidTask()]));
      tearDown(() => scheduler.close(silent: true));

      test("cronId exposes the id passed to cron()", () {
        final status = scheduler.cron<int>(
          VoidTask,
          1,
          Cron.parse("* * * * * *"),
          cronId: "cronIdExposesTheIdPassedToCron",
        );

        expect(status.cronId, "cronIdExposesTheIdPassedToCron");
      });

      test("isRunning is true after scheduling and false after cancel()", () {
        final status = scheduler.cron<int>(
          VoidTask,
          1,
          Cron.parse("* * * * * *"),
          cronId: "isRunningReflectsScheduledAndCancelledState",
        );

        expect(status.isRunning, isTrue);
        status.cancel();
        expect(status.isRunning, isFalse);
      });

      test(
        "isRunning becomes false once all reoccurrences complete, without calling cancel()",
        () async {
          final status = scheduler.cron<int>(
            VoidTask,
            1,
            Cron.parse("* * * * * *"),
            cronId: "isRunningBecomesFalseOnceReoccurrencesComplete",
            cronReoccurrences: 1,
          );

          expect(status.isRunning, isTrue);
          await _waitUntil(() => !status.isRunning);
          expect(status.isRunning, isFalse);
        },
        timeout: const Timeout(Duration(seconds: 10)),
      );

      test(
        "reoccurrencesRemaining is null when cronReoccurrences is unset",
        () {
          final status = scheduler.cron<int>(
            VoidTask,
            1,
            Cron.parse("* * * * * *"),
            cronId: "reoccurrencesRemainingIsNullWhenUnbounded",
          );

          expect(status.reoccurrencesRemaining, isNull);
        },
      );

      test(
        "reoccurrencesRemaining decreases as the cron task recurs",
        () async {
          final status = scheduler.cron<int>(
            VoidTask,
            1,
            Cron.parse("* * * * * *"),
            cronId: "reoccurrencesRemainingDecreasesAsTheCronTaskRecurs",
            cronReoccurrences: 3,
          );

          expect(status.reoccurrencesRemaining, 3);
          await _waitUntil(() => status.reoccurrencesRemaining != 3);
          expect(status.reoccurrencesRemaining, lessThan(3));

          await _waitUntil(() => !status.isRunning);
          expect(status.reoccurrencesRemaining, isNull);
        },
        timeout: const Timeout(Duration(seconds: 10)),
      );

      test(
        "nextRun returns an upcoming DateTime while scheduled, and null after cancel()",
        () {
          final before = DateTime.now();
          final status = scheduler.cron<int>(
            VoidTask,
            1,
            Cron.parse("* * * * * *"),
            cronId: "nextRunReturnsAnUpcomingDateTimeAndNullAfterCancel",
          );

          final nextRun = status.nextRun;
          expect(nextRun, isNotNull);
          expect(
            nextRun!.isBefore(before.add(const Duration(seconds: 2))),
            isTrue,
          );

          status.cancel();
          expect(status.nextRun, isNull);
        },
      );

      test("cancel() unblocks the cronId so it can be reused", () {
        final status = scheduler.cron<int>(
          VoidTask,
          1,
          Cron.parse("* * * * * *"),
          cronId: "cancelUnblocksTheCronIdSoItCanBeReused",
        )..cancel();
        expect(status.isRunning, isFalse);

        expect(
          () => scheduler.cron<int>(
            VoidTask,
            1,
            Cron.parse("* * * * * *"),
            cronId: "cancelUnblocksTheCronIdSoItCanBeReused",
          ),
          returnsNormally,
        );
      });

      test("cronId is unblocked once all reoccurrences complete naturally, "
          "without calling cancel()", () async {
        final status = scheduler.cron<int>(
          VoidTask,
          1,
          Cron.parse("* * * * * *"),
          cronId: "naturalCompletionUnblocksTheCronId",
          cronReoccurrences: 1,
        );

        await _waitUntil(() => !status.isRunning);

        expect(
          () => scheduler.cron<int>(
            VoidTask,
            1,
            Cron.parse("* * * * * *"),
            cronId: "naturalCompletionUnblocksTheCronId",
          ),
          returnsNormally,
        );
      }, timeout: const Timeout(Duration(seconds: 10)));

      test("progress records the broadcaster of each invocation", () async {
        final status = scheduler.cron<int>(
          VoidTask,
          1,
          Cron.parse("* * * * * *"),
          cronId: "progressRecordsTheBroadcasterOfEachInvocation",
          cronReoccurrences: 1,
        );

        expect(status.progress, isEmpty);
        await _waitUntil(() => !status.isRunning);
        expect(status.progress, hasLength(1));
        expect(status.progress.single, isA<TaskProgressBroadcaster>());
      });

      test(
        "progress forwards updates to the user-provided progressBroadcaster",
        () async {
          TaskProgressBroadcaster? captured;
          final status = scheduler.cron<int>(
            VoidTask,
            1,
            Cron.parse("* * * * * *"),
            cronId: "progressForwardsToUserProvidedProgressBroadcaster",
            cronReoccurrences: 1,
            progressBroadcaster: (b) => captured = b,
          );

          await _waitUntil(() => !status.isRunning);
          expect(captured, isNotNull);
          expect(status.progress, contains(captured));
        },
      );

      test(
        "cancel() stops future reoccurrences even while the current invocation is still running",
        () async {
          final slowScheduler = Scheduler([SlowVoidTask()]);
          addTearDown(() => slowScheduler.close(silent: true));

          final status = slowScheduler.cron<int>(
            SlowVoidTask,
            1,
            Cron.parse("* * * * * *"),
            cronId: "cancelStopsReoccurrencesWhileTheInvocationIsRunning",
          );

          await _waitUntil(
            () => slowScheduler.runningInvocations.values.any(
              (s) => s.task.id == "slowVoidTask",
            ),
          );
          status.cancel();
          expect(status.isRunning, isFalse);

          await _waitUntil(() => slowScheduler.runningInvocations.isEmpty);
          // Give a would-be (buggy) reschedule a chance to fire.
          await Future.delayed(const Duration(milliseconds: 1500));

          expect(slowScheduler.cronTasks, isEmpty);
        },
        timeout: const Timeout(Duration(seconds: 10)),
      );

      test(
        "toString() includes cronId, isRunning, reoccurrencesRemaining and nextRun",
        () {
          final status = scheduler.cron<int>(
            VoidTask,
            1,
            Cron.parse("* * * * * *"),
            cronId: "toStringIncludesAllFields",
            cronReoccurrences: 1,
          );

          final output = status.toString();
          expect(output, startsWith("CronTaskStatus("));
          expect(output, contains("cronId: toStringIncludesAllFields"));
          expect(output, contains("isRunning: true"));
          expect(output, contains("reoccurrencesRemaining: 1"));
          expect(output, contains("nextRun:"));
        },
      );
    });
  });
}

/// Polls [condition] until it returns `true`, or throws a [TimeoutException]
/// if it doesn't within [timeout].
Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
  Duration interval = const Duration(milliseconds: 50),
}) async {
  final stopwatch = Stopwatch()..start();
  while (!condition()) {
    if (stopwatch.elapsed > timeout) {
      throw TimeoutException("Condition not met within $timeout.");
    }
    await Future.delayed(interval);
  }
}
