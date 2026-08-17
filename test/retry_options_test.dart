import 'package:retry/retry.dart';
import 'package:scheduler/src/retry_options.dart';
import 'package:test/test.dart';

void main() {
  group("RetryOptionsSerializer", () {
    group("toJson", () {
      test("encodes all fields with durations as milliseconds", () {
        const options = RetryOptions(
          delayFactor: Duration(milliseconds: 100),
          randomizationFactor: 0.5,
          maxDelay: Duration(seconds: 10),
          maxAttempts: 4,
        );
        expect(options.toJson(), {
          "delayFactor": 100,
          "randomizationFactor": 0.5,
          "maxDelay": 10000,
          "maxAttempts": 4,
        });
      });

      test("encodes the default RetryOptions", () {
        const options = RetryOptions();
        final json = options.toJson();
        expect(json["delayFactor"], options.delayFactor.inMilliseconds);
        expect(json["randomizationFactor"], options.randomizationFactor);
        expect(json["maxDelay"], options.maxDelay.inMilliseconds);
        expect(json["maxAttempts"], options.maxAttempts);
      });
    });

    group("fromJson", () {
      test("decodes all fields from milliseconds back to Durations", () {
        final options = RetryOptionsSerializer.fromJson({
          "delayFactor": 250,
          "randomizationFactor": 0.1,
          "maxDelay": 5000,
          "maxAttempts": 7,
        });
        expect(options.delayFactor, const Duration(milliseconds: 250));
        expect(options.randomizationFactor, 0.1);
        expect(options.maxDelay, const Duration(milliseconds: 5000));
        expect(options.maxAttempts, 7);
      });
    });

    test("toJson / fromJson round-trips all fields", () {
      const original = RetryOptions(
        delayFactor: Duration(milliseconds: 333),
        randomizationFactor: 0.42,
        maxDelay: Duration(seconds: 3),
        maxAttempts: 9,
      );
      final restored = RetryOptionsSerializer.fromJson(original.toJson());

      expect(restored.delayFactor, original.delayFactor);
      expect(restored.randomizationFactor, original.randomizationFactor);
      expect(restored.maxDelay, original.maxDelay);
      expect(restored.maxAttempts, original.maxAttempts);
    });

    group("toPrettyString", () {
      test("contains the class name and all field values", () {
        const options = RetryOptions(
          delayFactor: Duration(milliseconds: 111),
          randomizationFactor: 0.25,
          maxDelay: Duration(seconds: 2),
          maxAttempts: 5,
        );
        final pretty = options.toPrettyString();

        expect(pretty, startsWith("RetryOptions("));
        expect(pretty, endsWith(")"));
        expect(pretty, contains("delayFactor: 0:00:00.111000"));
        expect(pretty, contains("randomizationFactor: 0.25"));
        expect(pretty, contains("maxDelay: 0:00:02.000000"));
        expect(pretty, contains("maxAttempts: 5"));
      });

      test("differs for different options (not a constant string)", () {
        const a = RetryOptions(maxAttempts: 1);
        const b = RetryOptions(maxAttempts: 2);
        expect(a.toPrettyString(), isNot(b.toPrettyString()));
      });
    });
  });
}
