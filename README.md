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
final status = await scheduler.invoke(JsonDecoder, '{"key": "value"}');
print((await status.future).success?.output); // {key: value}
```

### Delayed and recurring (cron) tasks

Besides `invoke`, a task can be run after a delay with `delayed`, or on a repeating schedule with `cron`. Cron tasks must have `void` (or `Null`) output, since their result isn't returned to the caller:

```dart
class Logger extends Task<String, void> {
  @override
  String get id => "logger";

  @override
  void invoke(input, _) => print(input);
}

// runs once, after 10 seconds
await scheduler.delayed(Logger, "Hello!", const Duration(seconds: 10));

// runs every day at midnight, indefinitely
final cronTask = scheduler.cron(
  Logger,
  "Good morning!",
  Cron.parse("0 0 * * *"),
  cronId: "dailyGreeting",
);

print(cronTask.isRunning); // true
cronTask.cancel(); // stops future reoccurrences
```

`cron` returns a `CronTaskStatus`, which lets you inspect (`nextRun`, `reoccurrencesRemaining`, `progress`) or `cancel()` the recurring schedule. See the `Cron.parse` documentation for the supported cron expression syntax.

### Tracking progress

Tasks can report progress back to the caller through the `TaskProgressCommunicator` passed as the second argument to `invoke`:

```dart
class JsonDecoder extends Task<String, Object> {
  ...
  @override
  Object invoke(input, progress) {
    progress.get().copyWith(step: () => "Decoding").set();
    return jsonDecode(input);
  }
}

final status = await scheduler.invoke(
  JsonDecoder,
  '{"key": "value"}',
  progressBroadcaster: (broadcaster) => broadcaster.addListener(print),
);
```

### Restoring state after a restart

`Scheduler.restorableState()` serializes currently running, queued, and scheduled invocations (for tasks with `allowRestoration` set to `true`) into a JSON-compatible map, which can be persisted and later passed to `Scheduler.fromRestorableState()` to pick up where you left off.

The recommended place to call `restorableState()` is inside `close()`'s `saveRestorableState` callback, since it runs after all running invocations have finished gracefully, giving you a consistent snapshot to persist:

```dart
await scheduler.close(
  saveRestorableState: () => saveToDisk(scheduler.restorableState()),
);

// ...on the next start:
final restored = Scheduler.fromRestorableState(tasks, await loadFromDisk());
```

### Inline tasks

For simple, one-off tasks you don't want to declare a full class for, use `InlineTask`:

```dart
final scheduler = Scheduler([
  InlineTask<String, String>(
    id: "greet",
    invoke: (input, _) => "Hello, $input!",
  ),
]);
```

See [`example/scheduler_example.dart`](https://github.com/JHubi1/scheduler/blob/main/example/scheduler_example.dart) for a more detailed usage example and consult the documentation (`dart doc --validate-links .`) for help.
