import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:scheduler/scheduler.dart';
import 'package:scheduler/tasks.dart';

final mode = "json";

void main() async {
  final tasks = <Task>[JsonDecoder(), DelayedEchoTask(), ThreeTimesTheCharm()];
  final scheduler = Scheduler(tasks);
  ProgressSnatcher.instance.addListener((progress) => print("> $progress"));

  if (mode == "restoreIn") {
    for (var i = 0; i < 10; i++) {
      scheduler.invoke(DelayedEchoTask, "Hello $i");
    }
    await Future.delayed(const Duration(seconds: 1)).then((_) {
      print("State: ${jsonEncode(scheduler.restorableState())}");
      exit(1);
    });
  } else if (mode == "restoreOut") {
    final state =
        '{"config":{"simultaneousInvocations":5,"cullingInterval":5000,"cullingIdle":60000,"retryOptions":{"delayFactor":200,"randomizationFactor":0.25,"maxDelay":30000,"maxAttempts":3}},"taskIds":["jsonDecoder","delayedEcho","threeTimesTheCharm"],"invocations":[{"task":"delayedEcho","input":"Hello 0","priority":0,"wasRunning":true},{"task":"delayedEcho","input":"Hello 1","priority":0,"wasRunning":true},{"task":"delayedEcho","input":"Hello 2","priority":0,"wasRunning":true},{"task":"delayedEcho","input":"Hello 3","priority":0,"wasRunning":true},{"task":"delayedEcho","input":"Hello 4","priority":0,"wasRunning":true},{"task":"delayedEcho","input":"Hello 5","priority":0,"wasRunning":false},{"task":"delayedEcho","input":"Hello 6","priority":0,"wasRunning":false},{"task":"delayedEcho","input":"Hello 7","priority":0,"wasRunning":false},{"task":"delayedEcho","input":"Hello 8","priority":0,"wasRunning":false},{"task":"delayedEcho","input":"Hello 9","priority":0,"wasRunning":false}]}';
    final restoredScheduler = Scheduler.fromRestorableState(
      tasks,
      Map.from(jsonDecode(state)),
    );
    await restoredScheduler.close(); // is graceful by default
  } else if (mode == "threeTimes") {
    final invocation = await scheduler.invoke(ThreeTimesTheCharm, "Hello");
    print("+ ${(await invocation.future).success}");
    print("- ${(await invocation.future).error}");
  } else if (mode == "error") {
    final newScheduler = Scheduler(
      tasks,
      config: scheduler.config.copyWith(
        retryOptions: RetryOptions(maxAttempts: 1),
      ),
    );
    print(
      await (await newScheduler.invoke(ThreeTimesTheCharm, "Hello")).future,
    );
    await newScheduler.close();
  } else if (mode == "invocation") {
    final invocation = await scheduler.invoke(DelayedEchoTask, "Hello");
    await Future.delayed(const Duration(seconds: 1)).then((_) {
      print(
        // external getter
        "Invocation: ${scheduler.runningInvocations[invocation.invocationId]}",
      );
      exit(1);
    });
  } else {
    print(
      (await (await scheduler.invoke(
        JsonDecoder,
        '{"key": "value"}',
      )).future).success?.output,
    );
    print(
      (await (await scheduler.invoke(
        JsonDecoder,
        '"banana"',
      )).future).success?.output,
    );
    print(
      (await (await scheduler.invoke(
        JsonDecoder,
        '[true, false, null, 1, "string"]',
      )).future).success?.output,
    );
    print(
      (await Future.wait(
        (await Future.wait([
          scheduler.invoke(JsonDecoder, '"yes"', processQueue: false),
          scheduler.invoke(JsonDecoder, '"no"', priority: 10),
        ])).map((e) => e.future),
      )).map((e) => e.success?.output).toList(),
    );
  }

  await scheduler.close();
  ProgressSnatcher.instance.close();
}

class JsonDecoder extends Task<String, Object> {
  @override
  String get id => "jsonDecoder";
  @override
  bool get allowSimultaneous => true;

  @override
  Future<Object> invoke(input, progress) async {
    progress.get().copyWith(step: () => "Decoding JSON ($input)").set();
    return jsonDecode(input);
  }
}

class DelayedEchoTask extends Task<String, String> {
  @override
  String get id => "delayedEcho";
  @override
  bool get allowSimultaneous => true;
  @override
  bool get allowRestoration => true;

  @override
  Future<String> invoke(input, progress) async {
    progress.get().copyWith(step: () => "Waiting...").set();
    await Future.delayed(const Duration(seconds: 2));
    return input;
  }
}

class ThreeTimesTheCharm extends Task<String, String> {
  @override
  String get id => "threeTimesTheCharm";
  @override
  bool get allowSimultaneous => true;

  int _attempts = 0;

  @override
  String invoke(input, progress) {
    _attempts++;
    progress.get().copyWith(step: () => "Attempt $_attempts").set();
    if (_attempts < 3) {
      throw Exception("Not yet!");
    }
    progress.get().copyWith(step: () => "Success!").set();
    return input;
  }
}
