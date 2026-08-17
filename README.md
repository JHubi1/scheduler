# scheduler.dart

Scheduler is a modern, class-based task scheduling system, primarily for a Dart server environment.

## Installation

To install this package, add it directly to your `pubspec.yaml` file. You should lookup the latest released tag in this repository and use it as `ref`; if that is not wanted, remove the `ref` property all together.

```yaml
dependencies:
  scheduler:
    git:
      url: https://github.com/JHubi1/scheduler.git
      ref: <latestTag>
```

You may alternatively run the following command:

```bash
dart pub add "scheduler@{git:{url: https://github.com/JHubi1/scheduler.git, ref: <latestTag>}}"
```

## Usage

Usage is simple. You first have to define a Task:

```dart
class JsonDecoder extends Task<String, Object> {
  @override
  String get id => "jsonDecoder";
  @override
  bool get allowSimultaneous => true;

  @override
  Object invoke(input, _) => jsonDecode(input);
}
```

Then that Task has to be registered to a Scheduler:

```dart
final scheduler = Scheduler([JsonDecoder()]);
```

Finally, invoke the Task by running:

```dart
final result = await scheduler.invoke(JsonDecoder, '{"key":"value"}');
print(result); // {key: value}
```

See [`example/scheduler_example.dart`](https://github.com/JHubi1/scheduler/blob/main/example/scheduler_example.dart) for a more detailed usage example and consult the documentation (`dart doc .`) for help.
