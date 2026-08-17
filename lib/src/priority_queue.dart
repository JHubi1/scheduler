import 'package:collection/collection.dart' as collections;

class _Stamped<E> {
  final E element;
  final int stamp;
  const _Stamped(this.element, this.stamp);
}

class PriorityQueue<E> extends collections.HeapPriorityQueue<E> {
  PriorityQueue({int Function(E a, E b)? comparator})
    : super(
        comparator ??
            (a, b) =>
                (b as dynamic).priority.compareTo((a as dynamic).priority),
      );
}

class StablePriorityQueue<E> implements collections.PriorityQueue<E> {
  late final collections.HeapPriorityQueue<_Stamped<E>> _heap;
  late final int Function(_Stamped<E>, _Stamped<E>) _stampedComparator;
  final int Function(E, E) _comparator;
  final bool Function(E)? _postponeExecution;
  int _counter = 0;

  StablePriorityQueue({
    int Function(E a, E b)? comparator,
    this._postponeExecution,
  }) : _comparator =
           comparator ??
           ((a, b) =>
               (b as dynamic).priority.compareTo((a as dynamic).priority)) {
    _stampedComparator = (a, b) {
      final cmp = _comparator(a.element, b.element);
      return cmp != 0 ? cmp : a.stamp.compareTo(b.stamp);
    };
    _heap = collections.HeapPriorityQueue<_Stamped<E>>(_stampedComparator);
  }

  @override
  void add(E element) => _heap.add(_Stamped(element, _counter++));

  @override
  void addAll(Iterable<E> elements) => elements.forEach(add);

  @override
  bool contains(E object) =>
      _heap.toUnorderedList().any((s) => s.element == object);

  @override
  E get first => _heap.first.element;

  @override
  bool get isEmpty => _heap.isEmpty;

  @override
  bool get isNotEmpty => _heap.isNotEmpty;

  @override
  int get length => _heap.length;

  @override
  bool remove(E element) {
    final unordered = _heap.toUnorderedList();
    final idx = unordered.indexWhere((s) => s.element == element);
    if (idx < 0) return false;
    unordered.removeAt(idx);
    _heap.clear();
    unordered.forEach(_heap.add);
    return true;
  }

  @override
  Iterable<E> removeAll() {
    final result = toList();
    _heap.clear();
    _counter = 0;
    return result;
  }

  E? removeFirstSafe() {
    if (_postponeExecution == null) return _heap.removeFirst().element;
    final attempts = _heap.length;
    final postponed = <_Stamped<E>>[];
    E? result;
    for (var i = 0; i < attempts; i++) {
      final stamped = _heap.removeFirst();
      if (!_postponeExecution(stamped.element)) {
        result = stamped.element;
        break;
      }
      postponed.add(stamped);
    }
    postponed.forEach(_heap.add);
    return result;
  }

  @override
  E removeFirst() => removeFirstSafe() ?? _heap.removeFirst().element;

  @override
  List<E> toList() {
    final copy = collections.HeapPriorityQueue<_Stamped<E>>(_stampedComparator)
      ..addAll(_heap.toUnorderedList());
    return [for (; copy.isNotEmpty;) copy.removeFirst().element];
  }

  @override
  List<E> toUnorderedList() =>
      _heap.toUnorderedList().map((s) => s.element).toList();

  @override
  Iterable<E> get unorderedElements =>
      _heap.unorderedElements.map((s) => s.element);

  @override
  Set<E> toSet() => toUnorderedList().toSet();

  @override
  void clear() {
    _heap.clear();
    _counter = 0;
  }

  @override
  String toString() => 'StablePriorityQueue(${toList()})';
}
