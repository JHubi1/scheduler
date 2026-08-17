import 'package:scheduler/scheduler.dart';
import 'package:test/test.dart';

void main() {
  group("SchedulerConfig", () {
    test("simultaneousTasks defaults to 5", () {
      expect(const SchedulerConfig().simultaneousTasks, 5);
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
        const config = SchedulerConfig(simultaneousTasks: 3);
        final copy = config.copyWith();
        expect(copy.simultaneousTasks, 3);
        expect(copy.cullingInterval, config.cullingInterval);
        expect(copy.cullingIdle, config.cullingIdle);
      });

      test("overrides simultaneousTasks", () {
        expect(
          const SchedulerConfig()
              .copyWith(simultaneousTasks: 10)
              .simultaneousTasks,
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
          simultaneousTasks: 2,
          cullingInterval: const Duration(seconds: 1),
        );
        expect(copy.simultaneousTasks, 2);
        expect(copy.cullingInterval, const Duration(seconds: 1));
        expect(copy.cullingIdle, config.cullingIdle);
      });
    });
  });
}
