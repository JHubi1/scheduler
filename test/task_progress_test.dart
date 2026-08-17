import 'package:scheduler/tasks.dart';
import 'package:test/test.dart';

void main() {
  group("TaskProgress", () {
    group("constructor validation", () {
      test("allows progress 0.0", () {
        expect(() => TaskProgress(progress: 0.0), returnsNormally);
      });

      test("allows progress 0.5", () {
        expect(() => TaskProgress(progress: 0.5), returnsNormally);
      });

      test("allows progress 1.0", () {
        expect(() => TaskProgress(progress: 1.0), returnsNormally);
      });

      test("allows indeterminate sentinel -1.0", () {
        expect(() => TaskProgress(progress: -1.0), returnsNormally);
      });

      test("allows null progress", () {
        expect(() => TaskProgress(progress: null), returnsNormally);
      });

      test("throws ArgumentError for progress below 0 (not -1.0)", () {
        expect(() => TaskProgress(progress: -0.5), throwsArgumentError);
      });

      test("throws ArgumentError for progress above 1.0", () {
        expect(() => TaskProgress(progress: 1.1), throwsArgumentError);
      });

      test("allows step that is in steps", () {
        expect(
          () => TaskProgress(step: "a", steps: ["a", "b"]),
          returnsNormally,
        );
      });

      test("throws ArgumentError when step is not in steps", () {
        expect(
          () => TaskProgress(step: "c", steps: ["a", "b"]),
          throwsArgumentError,
        );
      });

      test("allows null step when steps is provided", () {
        expect(() => TaskProgress(steps: ["a", "b"]), returnsNormally);
      });
    });

    group("factories", () {
      test("indeterminate() sets progress to -1.0", () {
        expect(TaskProgress.indeterminate().progress, -1.0);
      });

      test("indeterminate() forwards optional fields", () {
        final p = TaskProgress.indeterminate(
          step: "a",
          steps: ["a", "b"],
          message: "msg",
        );
        expect(p.step, "a");
        expect(p.steps, ["a", "b"]);
        expect(p.message, "msg");
      });

      test("unknown() sets progress to null", () {
        expect(TaskProgress.unknown().progress, isNull);
      });

      test("unknown() forwards optional fields", () {
        final p = TaskProgress.unknown(message: "msg");
        expect(p.message, "msg");
      });
    });

    group("copyWith", () {
      test("preserves all fields when no overrides are given", () {
        final original = TaskProgress(
          progress: 0.5,
          step: "step1",
          steps: ["step1", "step2"],
          message: "hello",
        );
        expect(original.copyWith(), equals(original));
      });

      test("overrides individual fields", () {
        final original = TaskProgress(progress: 0.5, message: "old");
        final copy = original.copyWith(
          progress: () => 0.8,
          message: () => "new",
        );
        expect(copy.progress, 0.8);
        expect(copy.message, "new");
      });

      test("can clear a nullable field via null-returning lambda", () {
        final original = TaskProgress(progress: 0.5, message: "msg");
        final copy = original.copyWith(message: () => null);
        expect(copy.message, isNull);
      });
    });

    group("equality", () {
      test("equal for identical field values", () {
        expect(
          TaskProgress(progress: 0.5, message: "test"),
          equals(TaskProgress(progress: 0.5, message: "test")),
        );
      });

      test("not equal when progress differs", () {
        expect(
          TaskProgress(progress: 0.4),
          isNot(equals(TaskProgress(progress: 0.5))),
        );
      });

      test("steps list compared by content, not reference", () {
        expect(
          TaskProgress(steps: ["a", "b"]),
          equals(TaskProgress(steps: ["a", "b"])),
        );
        expect(
          TaskProgress(steps: ["a", "b"]),
          isNot(equals(TaskProgress(steps: ["a", "c"]))),
        );
      });

      test("identical instance short-circuits the equality check", () {
        final p = TaskProgress(progress: 0.5);
        expect(p == p, isTrue);
      });

      test("hashCode is consistent with equality", () {
        final a = TaskProgress(progress: 0.5, message: "test");
        final b = TaskProgress(progress: 0.5, message: "test");
        expect(a.hashCode, b.hashCode);
      });
    });

    group("serialization", () {
      test("toJson / fromJson round-trip preserves all fields", () {
        final original = TaskProgress(
          progress: 0.5,
          step: "step1",
          steps: ["step1", "step2"],
          message: "hello",
        );
        expect(TaskProgress.fromJson(original.toJson()), equals(original));
      });

      test("round-trip preserves null progress", () {
        final original = TaskProgress.unknown();
        expect(TaskProgress.fromJson(original.toJson()), equals(original));
      });

      test("round-trip preserves indeterminate progress", () {
        final original = TaskProgress.indeterminate();
        expect(TaskProgress.fromJson(original.toJson()), equals(original));
      });
    });

    group("toString", () {
      test("unknown() uses compact form", () {
        expect(TaskProgress.unknown().toString(), "TaskProgress.unknown()");
      });

      test("indeterminate() uses compact form", () {
        expect(
          TaskProgress.indeterminate().toString(),
          "TaskProgress.indeterminate()",
        );
      });

      test("normal progress includes the progress value", () {
        expect(TaskProgress(progress: 0.5).toString(), contains("0.5"));
      });

      test("includes optional fields when set", () {
        final s = TaskProgress(progress: 0.5, message: "hi").toString();
        expect(s, contains("hi"));
      });
    });

    group("set()", () {
      test("throws StateError when not attached to a parent", () {
        final p = TaskProgress(progress: 0.5);
        expect(p.set, throwsStateError);
      });
    });
  });

  group("TaskProgressBroadcaster", () {
    test("initial progress is unknown", () {
      final broadcaster = TaskProgressBroadcaster(invocationId: 1);
      expect(broadcaster.progress, equals(TaskProgress.unknown()));
    });

    test("addListener does not throw", () {
      final broadcaster = TaskProgressBroadcaster(invocationId: 1);
      expect(() => broadcaster.addListener((_) {}), returnsNormally);
    });

    test("removeListener does not throw for a registered listener", () {
      final broadcaster = TaskProgressBroadcaster(invocationId: 1);
      void listener(TaskProgress p) {}
      broadcaster.addListener(listener);
      expect(() => broadcaster.removeListener(listener), returnsNormally);
    });

    test("removeListener is a no-op for an unknown listener", () {
      final broadcaster = TaskProgressBroadcaster(invocationId: 1);
      expect(() => broadcaster.removeListener((_) {}), returnsNormally);
    });
  });
}
