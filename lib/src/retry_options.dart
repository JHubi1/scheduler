import 'package:retry/retry.dart';

extension RetryOptionsSerializer on RetryOptions {
  Map<String, dynamic> toJson() {
    return {
      "delayFactor": delayFactor.inMilliseconds,
      "randomizationFactor": randomizationFactor,
      "maxDelay": maxDelay.inMilliseconds,
      "maxAttempts": maxAttempts,
    };
  }

  static RetryOptions fromJson(Map<String, dynamic> json) {
    return RetryOptions(
      delayFactor: Duration(milliseconds: json["delayFactor"]),
      randomizationFactor: json["randomizationFactor"],
      maxDelay: Duration(milliseconds: json["maxDelay"]),
      maxAttempts: json["maxAttempts"],
    );
  }

  String toPrettyString() {
    final builder = StringBuffer()
      ..write("RetryOptions(")
      ..write("delayFactor: $delayFactor, ")
      ..write("randomizationFactor: $randomizationFactor, ")
      ..write("maxDelay: $maxDelay, ")
      ..write("maxAttempts: $maxAttempts")
      ..write(")");
    return builder.toString();
  }
}
