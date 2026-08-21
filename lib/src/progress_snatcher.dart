import 'dart:async';
import 'tasks.dart';

/// A pattern that matches camelCase strings, which are used for task IDs.
final kCamelCasePattern = RegExp(r"^[a-z][a-z0-9]*(?:[A-Z][a-z0-9]+)*$");

/// A singleton that automatically listens to all TaskProgressBroadcasters and
/// forwards their progress updates to its own listeners.
///
/// This is useful for displaying the progress of all tasks in a single place,
/// such as a progress bar in a UI.
///
/// [ProgressSnatcher] automatically listens to all [TaskProgressBroadcaster]s
/// that are passed to it via [auto]. It then also automatically cancels the
/// listeners when the [TaskProgressBroadcaster] is closed, returning one last
/// progress update with `null` to indicate that the task is done.
///
/// ---
///
/// Example usage:
///
/// ```dart
/// (await JsonDecoder().spawn()).invoke(
///     '{"key":"value"}',
///     progressBroadcaster: ProgressSnatcher.instance.auto,
///   );
/// ```
class ProgressSnatcher {
  bool _closed = false;

  static ProgressSnatcher? _instance;
  static ProgressSnatcher get instance {
    _instance ??= ProgressSnatcher._();
    return _instance!;
  }

  ProgressSnatcher._();

  final Map<int, TaskProgressBroadcaster> _activeProgressBroadcasters = {};
  final Map<int, void Function(TaskProgress)> _activeListeners = {};
  final Map<int, void Function()> _activeClosureListeners = {};

  final Map<int, TaskProgress> _lastProgress = {};
  Map<int, TaskProgress> get lastProgress => Map.unmodifiable(_lastProgress);

  void auto(TaskProgressBroadcaster progress) {
    if (_closed) return;
    _activeProgressBroadcasters[progress.invocationId] = progress;
    progress
      ..addListener(_autoBoilerplate(progress))
      ..addClosureListener(_autoBoilerplateClosure(progress));
  }

  void Function(TaskProgress progress) _autoBoilerplate(
    TaskProgressBroadcaster progress,
  ) {
    void tmp(TaskProgress p) {
      _lastProgress[progress.invocationId] = p;
      _controller.add((progress.invocationId, p));
    }

    _activeListeners[progress.invocationId] = tmp;
    return tmp;
  }

  void Function() _autoBoilerplateClosure(TaskProgressBroadcaster progress) {
    void tmp() {
      _controller.add((progress.invocationId, null));
      _activeProgressBroadcasters.remove(progress.invocationId)
        ?..removeListener(_activeListeners.remove(progress.invocationId)!)
        ..removeClosureListener(
          _activeClosureListeners.remove(progress.invocationId)!,
        );
      _lastProgress.remove(progress.invocationId);
    }

    _activeClosureListeners[progress.invocationId] = tmp;
    return tmp;
  }

  late final _controller = StreamController<(int, TaskProgress?)>.broadcast(
    sync: true,
  );
  final Map<void Function((int, TaskProgress?)), StreamSubscription>
  _listeners = {};

  void addListener(void Function((int, TaskProgress?)) listener) => _closed
      ? null
      : _listeners[listener] = _controller.stream.listen(listener.call);
  void removeListener(void Function((int, TaskProgress?)) listener) =>
      _closed ? null : _listeners.remove(listener)?.cancel();

  void close() {
    if (_closed) return;
    _closed = true;

    for (final subscription in _listeners.values.toList()) {
      subscription.cancel();
    }
    _controller.close();

    for (final progress in _activeProgressBroadcasters.values.toList()) {
      progress
        ..removeListener(_activeListeners.remove(progress.invocationId)!)
        ..removeClosureListener(
          _activeClosureListeners.remove(progress.invocationId)!,
        );
    }

    _activeProgressBroadcasters.clear();
    _instance = null;
  }
}

StateError? castErrorParser(Object? error) {
  final parts = error.toString().split("'");
  if (parts.length != 5 ||
      parts[0] != "type " ||
      parts[2] != " is not a subtype of type " ||
      parts[4] != " in type cast") {
    return null;
  }

  final type = parts[1];
  final subtype = "<${parts[3].split("<").last.split(">").first}>";

  return StateError(
    "Task $type does not match <I, O> of $subtype, the passed input and output types.",
  );
}
