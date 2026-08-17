import 'dart:async';

import 'package:scheduler/scheduler.dart';
import 'package:scheduler/tasks.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group("Race conditions", () {
    test("100 identical invocations with priorities 0..99 on a single "
        "simultaneous slot all complete, highest priority first", () async {
      final scheduler = Scheduler([
        EchoTask(),
      ], config: const SchedulerConfig(simultaneousInvocations: 1));
      addTearDown(scheduler.close);

      final completionOrder = <int>[];
      final futures = <Future<void>>[];
      for (var priority = 0; priority < 100; priority++) {
        futures.add(
          scheduler
              .invoke<String, String>(
                EchoTask,
                "$priority",
                priority: priority,
                processQueue: false,
              )
              .output
              .then((_) => completionOrder.add(priority)),
        );
      }
      scheduler.invoke<String, String>(EchoTask, "kick");

      await Future.wait(futures);

      expect(completionOrder, hasLength(100));
      expect(completionOrder, orderedEquals(List.generate(100, (i) => 99 - i)));
    }, timeout: const Timeout(Duration(seconds: 30)));

    test("100 simultaneous identical invocations on an allowSimultaneous task "
        "all complete with the correct per-invocation output", () async {
      final scheduler = Scheduler([
        EchoTask(),
      ], config: const SchedulerConfig(simultaneousInvocations: 100));
      addTearDown(scheduler.close);

      final results = await Future.wait([
        for (var i = 0; i < 100; i++)
          scheduler.invoke<String, String>(EchoTask, "$i").output,
      ]);

      expect(results, List.generate(100, (i) => "$i"));
    }, timeout: const Timeout(Duration(seconds: 30)));

    test("changing config while a job is running does not lose or duplicate "
        "queued invocations", () async {
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

      final queued = [
        for (var i = 0; i < 20; i++)
          scheduler
              .invoke<String, String>(EchoTask, "$i", processQueue: false)
              .output,
      ];

      for (final limit in [0, 5, 1, 10, 2, 20]) {
        scheduler.config = SchedulerConfig(simultaneousInvocations: limit);
      }

      final results = await Future.wait([blocking, ...queued]);
      expect(results.toSet(), {"done", for (var i = 0; i < 20; i++) "$i"});
    }, timeout: const Timeout(Duration(seconds: 30)));

    test("closing the scheduler while invocations are still queued fails them "
        "instead of leaving them pending forever", () async {
      final scheduler = Scheduler([
        EchoTask(),
      ], config: const SchedulerConfig(simultaneousInvocations: 0));
      addTearDown(scheduler.close);

      final queued = [
        for (var i = 0; i < 10; i++)
          scheduler.invoke<String, String>(
            EchoTask,
            "$i",
            processQueue: false,
            processQueueLockAssert: false,
          ),
      ];

      await scheduler.close(graceful: false, silent: true);
      for (final future in queued) {
        expect(future, isA<Future<TaskStatus<String, String>>>());
      }
    }, timeout: const Timeout(Duration(seconds: 10)));

    test("an isolate crash during one invocation doesn't hang concurrent or "
        "subsequent invocations of the same task", () async {
      final bundle = TaskBundle([CrashingTask()], startCulling: false);
      addTearDown(bundle.close);

      final crashed = bundle.invoke<int, String>(CrashingTask, 0);
      final result = await crashed.result;
      expect(result.error, isNotNull);

      final recovered = await bundle
          .invoke<int, String>(CrashingTask, 1)
          .result;
      expect(recovered.error, isNotNull);
    }, timeout: const Timeout(Duration(seconds: 10)));

    test("many concurrent invocations of a non-simultaneous task never overlap "
        "in execution", () async {
      final scheduler = Scheduler([SlowExclusiveTask()]);
      addTearDown(scheduler.close);

      final results = await Future.wait([
        for (var i = 0; i < 20; i++)
          scheduler
              .invoke<Duration, String>(
                SlowExclusiveTask,
                const Duration(milliseconds: 5),
              )
              .result,
      ]);

      final intervals =
          results
              .map((r) => r.success!)
              .map((s) => (s.startTime!, s.endTime!))
              .toList()
            ..sort((a, b) => a.$1.compareTo(b.$1));

      expect(intervals, hasLength(20));
      for (var i = 1; i < intervals.length; i++) {
        expect(
          intervals[i].$1.isBefore(intervals[i - 1].$2),
          isFalse,
          reason:
              "Invocation $i (${intervals[i]}) overlapped with the "
              "previous one (${intervals[i - 1]}).",
        );
      }
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
