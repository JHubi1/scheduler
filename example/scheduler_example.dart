import 'dart:convert';

import 'package:scheduler/scheduler.dart';
import 'package:scheduler/tasks.dart';

void main() async {
  final scheduler = Scheduler([JsonDecoder()]);

  ProgressSnatcher.instance.addListener((progress) => print("> $progress"));

  print(await scheduler.invoke(JsonDecoder, '{"key": "value"}'));
  print(await scheduler.invoke(JsonDecoder, '"banana"'));
  print(
    await scheduler.invoke(JsonDecoder, '[true, false, null, 1, "string"]'),
  );
  print(
    await Future.wait([
      scheduler.invoke(JsonDecoder, '"yes"', processQueue: false),
      scheduler.invoke(JsonDecoder, '"no"', priority: 100),
    ]),
  );

  scheduler.close();
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
