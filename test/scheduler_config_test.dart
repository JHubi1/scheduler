import 'package:scheduler/scheduler.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group("SchedulerConfig", () {
    test("simultaneousInvocations defaults to 5", () {
      expect(const SchedulerConfig().simultaneousInvocations, 5);
    });

    test("cullingInterval defaults to 5 seconds", () {
      expect(
        const SchedulerConfig().cullingInterval,
        const Duration(seconds: 5),
      );
    });

    test("cullingIdle defaults to 1 minute", () {
      expect(const SchedulerConfig().cullingIdle, const Duration(minutes: 1));
    });

    group("copyWith", () {
      test("preserves all fields when no overrides are given", () {
        const config = SchedulerConfig(simultaneousInvocations: 3);
        final copy = config.copyWith();
        expect(copy.simultaneousInvocations, 3);
        expect(copy.cullingInterval, config.cullingInterval);
        expect(copy.cullingIdle, config.cullingIdle);
      });

      test("overrides simultaneousInvocations", () {
        expect(
          const SchedulerConfig()
              .copyWith(simultaneousInvocations: 10)
              .simultaneousInvocations,
          10,
        );
      });

      test("overrides cullingInterval", () {
        final interval = const Duration(seconds: 30);
        expect(
          const SchedulerConfig()
              .copyWith(cullingInterval: interval)
              .cullingInterval,
          interval,
        );
      });

      test("overrides cullingIdle", () {
        final idle = const Duration(minutes: 5);
        expect(
          const SchedulerConfig().copyWith(cullingIdle: idle).cullingIdle,
          idle,
        );
      });

      test("overrides multiple fields simultaneously", () {
        const config = SchedulerConfig();
        final copy = config.copyWith(
          simultaneousInvocations: 2,
          cullingInterval: const Duration(seconds: 1),
        );
        expect(copy.simultaneousInvocations, 2);
        expect(copy.cullingInterval, const Duration(seconds: 1));
        expect(copy.cullingIdle, config.cullingIdle);
      });
    });

    group("validation", () {
      test(
        "throws ArgumentError for a non-positive simultaneousInvocations",
        () {
          expect(
            () => Scheduler([
              EchoTask(),
            ], config: const SchedulerConfig(simultaneousInvocations: 0)),
            throwsArgumentError,
          );
        },
      );

      test("throws ArgumentError for a non-positive cullingInterval", () {
        expect(
          () => Scheduler([
            EchoTask(),
          ], config: const SchedulerConfig(cullingInterval: Duration.zero)),
          throwsArgumentError,
        );
      });

      test(
        "throws ArgumentError when cullingIdle is less than cullingInterval",
        () {
          expect(
            () => Scheduler([
              EchoTask(),
            ], config: const SchedulerConfig(cullingIdle: Duration.zero)),
            throwsArgumentError,
          );
        },
      );
    });
  });
}
