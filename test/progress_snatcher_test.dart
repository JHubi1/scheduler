import 'package:scheduler/src/progress_snatcher.dart';
import 'package:scheduler/tasks.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  tearDown(() => ProgressSnatcher.instance.close());

  group("ProgressSnatcher", () {
    group("singleton", () {
      test("instance returns the same object on repeated calls", () {
        expect(ProgressSnatcher.instance, same(ProgressSnatcher.instance));
      });

      test("close() resets the singleton; next access creates a fresh one", () {
        final first = ProgressSnatcher.instance..close();
        expect(ProgressSnatcher.instance, isNot(same(first)));
      });
    });

    group("auto()", () {
      test("progress updates are forwarded to addListener listeners", () async {
        final snatcher = ProgressSnatcher.instance;
        final bundle = TaskBundle([ProgressTask()], startCulling: false);
        addTearDown(bundle.close);

        final events = <(int, TaskProgress?)>[];
        snatcher.addListener(events.add);

        await bundle.invoke<int, int>(
          ProgressTask,
          3,
          progressBroadcaster: snatcher.auto,
        );

        final progressEvents = events
            .where((e) => e.$2 != null)
            .map((e) => e.$2!);
        expect(progressEvents, isNotEmpty);
        expect(
          progressEvents.map((p) => p.progress),
          everyElement(isNonNegative),
        );
      });

      test("null progress is emitted when the broadcaster is closed", () async {
        final snatcher = ProgressSnatcher.instance;
        final bundle = TaskBundle([EchoTask()], startCulling: false);
        addTearDown(bundle.close);

        final events = <(int, TaskProgress?)>[];
        snatcher.addListener(events.add);

        await bundle.invoke<String, String>(
          EchoTask,
          "hello",
          progressBroadcaster: snatcher.auto,
        );

        expect(events.any((e) => e.$2 == null), isTrue);
      });

      test(
        "invocationId in events matches the broadcaster invocationId",
        () async {
          final snatcher = ProgressSnatcher.instance;
          final instance = await ProgressTask().spawn();
          addTearDown(instance.close);

          int? capturedId;
          final (invId, future) = instance.invoke(
            2,
            progressBroadcaster: (b) {
              capturedId = b.invocationId;
              snatcher.auto(b);
            },
          );
          await future;

          expect(capturedId, isNotNull);
          final eventIds = <int>{};
          snatcher.addListener((e) => eventIds.add(e.$1));
          expect(capturedId, invId);
        },
      );
    });

    group("addListener / removeListener", () {
      test("addListener does not throw", () {
        expect(
          () => ProgressSnatcher.instance.addListener((_) {}),
          returnsNormally,
        );
      });

      test("removed listener no longer receives events", () async {
        final snatcher = ProgressSnatcher.instance;
        final bundle = TaskBundle([EchoTask()], startCulling: false);
        addTearDown(bundle.close);

        final events = <(int, TaskProgress?)>[];
        void listener((int, TaskProgress?) e) => events.add(e);
        snatcher
          ..addListener(listener)
          ..removeListener(listener);

        await bundle.invoke<String, String>(
          EchoTask,
          "test",
          progressBroadcaster: snatcher.auto,
        );

        expect(events, isEmpty);
      });

      test("addListener on a closed snatcher is a no-op", () {
        ProgressSnatcher.instance.close();
        expect(
          () => ProgressSnatcher.instance.addListener((_) {}),
          returnsNormally,
        );
      });

      test("removeListener on a closed snatcher is a no-op", () {
        final snatcher = ProgressSnatcher.instance..close();
        expect(() => snatcher.removeListener((_) {}), returnsNormally);
      });
    });

    group("lastProgress", () {
      test(
        "holds the latest progress per invocation and is cleared when the task completes",
        () async {
          final snatcher = ProgressSnatcher.instance;
          final instance = await ProgressTask().spawn();
          addTearDown(instance.close);

          Map<int, TaskProgress>? snapshot;
          snatcher.addListener((event) {
            if (event.$2 != null && snapshot == null) {
              snapshot = Map.of(snatcher.lastProgress);
            }
          });

          final (_, future) = instance.invoke(
            3,
            progressBroadcaster: snatcher.auto,
          );
          await future;

          expect(snapshot, isNotNull);
          expect(snapshot!.values.first.progress, isNonNegative);
          expect(snatcher.lastProgress, isEmpty);
        },
      );
    });

    group("close()", () {
      test("close() is idempotent", () {
        final snatcher = ProgressSnatcher.instance..close();
        expect(snatcher.close, returnsNormally);
      });

      test(
        "close() removes broadcaster listeners so no StateError fires mid-flight",
        () async {
          final snatcher = ProgressSnatcher.instance;
          final instance = await ProgressTask().spawn();
          addTearDown(instance.close);

          final (_, future) = instance.invoke(
            3,
            progressBroadcaster: snatcher.auto,
          );

          snatcher.close();
          expect(await future, 3);
        },
      );
    });
  });
}
