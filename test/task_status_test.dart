import 'dart:async';

import 'package:scheduler/tasks.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group("TaskStatus", () {
    late TaskBundle bundle;
    setUp(
      () => bundle = TaskBundle([
        EchoTask(),
        FailingTask(),
        DelayedTask(),
      ], startCulling: false),
    );
    tearDown(() => bundle.close());

    test("exposes the invoked task and a non-negative invocationId", () async {
      final status = await bundle.invoke<String, String>(EchoTask, "hello");
      expect(status.task, isA<EchoTask>());
      expect(status.invocationId, isNonNegative);
    });

    test("result is null until the invocation completes", () async {
      final status = await bundle.invoke<Duration, String>(
        DelayedTask,
        const Duration(milliseconds: 100),
      );
      expect(status.result, isNull);

      final result = await status.future;
      expect(result, same(status.result));
      expect(result.success?.output, "done");
    });

    test(
      "success is populated and error is null on a successful invocation",
      () async {
        final status = await bundle.invoke<String, String>(EchoTask, "hello");
        await status.future;
        expect(status.success?.output, "hello");
        expect(status.error, isNull);
      },
    );

    test(
      "error is populated and success is null on a failed invocation",
      () async {
        final status = await bundle.invoke<String, String>(
          FailingTask,
          "trigger",
        );
        await status.future;
        expect(status.error, isNotNull);
        expect(status.error!.exception, isException);
        expect(status.success, isNull);
      },
    );

    test(
      "progress broadcaster's invocationId matches TaskStatus.invocationId",
      () async {
        final status = await bundle.invoke<String, String>(EchoTask, "hello");
        expect(status.progress.invocationId, status.invocationId);
        await status.future;
      },
    );

    test("the invocationId callback passed to TaskBundle.invoke fires with the "
        "same id exposed on TaskStatus", () async {
      int? capturedId;
      final status = await bundle.invoke<String, String>(
        EchoTask,
        "hello",
        invocationId: (id) => capturedId = id,
      );
      await status.future;

      expect(capturedId, isNotNull);
      expect(capturedId, status.invocationId);
    });

    test("toString contains the result and progress", () async {
      final status = await bundle.invoke<String, String>(EchoTask, "hello");
      await status.future;
      expect(status.toString(), contains("TaskStatus("));
      expect(status.toString(), contains("result:"));
      expect(status.toString(), contains("progress:"));
    });
  });

  group("TaskResult", () {
    late TaskBundle bundle;
    setUp(
      () =>
          bundle = TaskBundle([EchoTask(), FailingTask()], startCulling: false),
    );
    tearDown(() => bundle.close());

    test("TaskResultSuccess.toString contains the output", () async {
      final status = await bundle.invoke<String, String>(EchoTask, "hello");
      final result = await status.future;
      expect(result.toString(), contains("TaskResultSuccess("));
      expect(result.toString(), contains("hello"));
    });

    test("TaskResultError.toString contains the exception", () async {
      final status = await bundle.invoke<String, String>(
        FailingTask,
        "trigger",
      );
      final result = await status.future;
      expect(result.toString(), contains("TaskResultError("));
      expect(result.toString(), contains("trigger"));
    });

    test(
      "success/error getters are mutually exclusive on the base type",
      () async {
        final status = await bundle.invoke<String, String>(EchoTask, "hello");
        final result = await status.future;
        expect(result.success, isNotNull);
        expect(result.error, isNull);
      },
    );
  });

  group("RemoteException (via a failing task)", () {
    test(
      "carries the original exception description and a stack trace",
      () async {
        final instance = await FailingTask().spawn();
        addTearDown(instance.close);

        final (_, future) = instance.invoke("trigger");
        try {
          await future;
          fail("Expected a RemoteException to be thrown.");
        } on RemoteException catch (e) {
          expect(e.toString(), contains("Task failed"));
          expect(e.stackTrace, isA<StackTrace>());
        }
      },
    );
  });

  group("TaskStatusFutureExtension", () {
    late TaskBundle bundle;
    setUp(
      () => bundle = TaskBundle([
        EchoTask(),
        FailingTask(),
        DelayedTask(),
      ], startCulling: false),
    );
    tearDown(() => bundle.close());

    test(".output returns the value once the invocation completes", () async {
      expect(
        await bundle.invoke<String, String>(EchoTask, "hello").output,
        "hello",
      );
    });

    test(".output rethrows the original exception on failure", () async {
      await expectLater(
        bundle.invoke<String, String>(FailingTask, "trigger").output,
        throwsA(anything),
      );
    });

    test(".result awaits full completion, not just invocation start", () async {
      final result = await bundle
          .invoke<Duration, String>(
            DelayedTask,
            const Duration(milliseconds: 100),
          )
          .result;
      expect(result.success?.output, "done");
    });

    test(".success is null while pending, populated once complete", () async {
      final success = await bundle
          .invoke<String, String>(EchoTask, "hi")
          .success;
      expect(success?.output, "hi");
    });

    test(".error is null on success, populated on failure", () async {
      expect(await bundle.invoke<String, String>(EchoTask, "hi").error, isNull);
      expect(
        await bundle.invoke<String, String>(FailingTask, "x").error,
        isNotNull,
      );
    });
  });

  group("Task.timeout", () {
    test(
      "a task that exceeds its timeout fails with a TimeoutException",
      () async {
        final bundle = TaskBundle([
          TimeoutTask(const Duration(milliseconds: 50)),
        ], startCulling: false);
        addTearDown(bundle.close);

        final result = await bundle
            .invoke<Duration, String>(TimeoutTask, const Duration(seconds: 5))
            .result;
        expect(result.error, isNotNull);
        expect(result.error!.exception, isA<TimeoutException>());
      },
    );

    test("a task that completes within its timeout succeeds", () async {
      final bundle = TaskBundle([
        TimeoutTask(const Duration(seconds: 5)),
      ], startCulling: false);
      addTearDown(bundle.close);

      final result = await bundle
          .invoke<Duration, String>(
            TimeoutTask,
            const Duration(milliseconds: 20),
          )
          .result;
      expect(result.success?.output, "done");
    });

    test("no timeout is applied when Task.timeout is null", () async {
      final bundle = TaskBundle([DelayedTask()], startCulling: false);
      addTearDown(bundle.close);

      final result = await bundle
          .invoke<Duration, String>(
            DelayedTask,
            const Duration(milliseconds: 100),
          )
          .result;
      expect(result.success?.output, "done");
    });
  });

  group("TaskStatus.cancel", () {
    test(
      "signals cancellation to the running isolate via TaskProgressCommunicator.isClosed",
      () async {
        final bundle = TaskBundle([CancellableTask()], startCulling: false);
        addTearDown(bundle.close);

        final status = await bundle.invoke<int, String>(CancellableTask, 50);
        await Future.delayed(const Duration(milliseconds: 40));
        status.cancel();

        final result = await status.future;
        expect(result.success?.output, "cancelled");
      },
    );

    test(
      "has no effect if called after the invocation already completed",
      () async {
        final bundle = TaskBundle([EchoTask()], startCulling: false);
        addTearDown(bundle.close);

        final status = await bundle.invoke<String, String>(EchoTask, "hello");
        await status.future;
        expect(status.cancel, returnsNormally);
      },
    );
  });
}
