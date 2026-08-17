import 'package:scheduler/src/priority_queue.dart';
import 'package:test/test.dart';

void main() {
  group("StablePriorityQueue", () {
    late StablePriorityQueue<int> queue;

    setUp(() {
      queue = StablePriorityQueue(comparator: (a, b) => b.compareTo(a));
    });

    test("isEmpty on a fresh queue", () {
      expect(queue.isEmpty, isTrue);
      expect(queue.isNotEmpty, isFalse);
    });

    test("length tracks the number of added elements", () {
      queue
        ..add(1)
        ..add(2);
      expect(queue.length, 2);
    });

    test("contains returns true for an added element", () {
      queue.add(5);
      expect(queue.contains(5), isTrue);
    });

    test("contains returns false for an absent element", () {
      queue.add(5);
      expect(queue.contains(3), isFalse);
    });

    test("first returns the highest-priority element without removal", () {
      queue.addAll([1, 5, 3]);
      expect(queue.first, 5);
      expect(queue.length, 3);
    });

    test("removeFirst returns the highest-priority element", () {
      queue.addAll([1, 5, 3]);
      expect(queue.removeFirst(), 5);
    });

    test("toList returns all elements in priority order", () {
      queue.addAll([3, 1, 4, 1, 5, 9, 2, 6]);
      expect(queue.toList(), [9, 6, 5, 4, 3, 2, 1, 1]);
    });

    test("equal-priority elements are returned in insertion (FIFO) order", () {
      final stable = StablePriorityQueue<String>(comparator: (a, b) => 0)
        ..addAll(["first", "second", "third"]);
      expect(stable.toList(), ["first", "second", "third"]);
    });

    test("remove deletes the specified element", () {
      queue
        ..addAll([1, 2, 3])
        ..remove(2);
      expect(queue.toList(), [3, 1]);
    });

    test("remove returns false for an absent element", () {
      queue.add(1);
      expect(queue.remove(99), isFalse);
    });

    test("removeAll returns all elements and leaves the queue empty", () {
      queue.addAll([3, 1, 2]);
      final removed = queue.removeAll();
      expect(removed.toSet(), {1, 2, 3});
      expect(queue.isEmpty, isTrue);
    });

    test("clear empties the queue", () {
      queue
        ..addAll([1, 2, 3])
        ..clear();
      expect(queue.isEmpty, isTrue);
    });

    test("toUnorderedList contains all elements (any order)", () {
      queue.addAll([1, 2, 3]);
      expect(queue.toUnorderedList().toSet(), {1, 2, 3});
    });

    test("toSet contains all distinct elements", () {
      queue.addAll([1, 2, 3]);
      expect(queue.toSet(), {1, 2, 3});
    });

    test("unorderedElements contains all elements", () {
      queue.addAll([1, 2, 3]);
      expect(queue.unorderedElements.toSet(), {1, 2, 3});
    });

    test("addAll adds multiple elements at once", () {
      queue.addAll([10, 20, 30]);
      expect(queue.length, 3);
      expect(queue.first, 30);
    });

    group("postponeExecution", () {
      test("removeFirstSafe skips postponed elements", () {
        final q = StablePriorityQueue<int>(
          comparator: (a, b) => b.compareTo(a),
          postponeExecution: (e) => e == 5,
        )..addAll([5, 3, 1]);
        expect(q.removeFirstSafe(), 3);
      });

      test("postponed elements remain in the queue after safe removal", () {
        final q =
            StablePriorityQueue<int>(
                comparator: (a, b) => b.compareTo(a),
                postponeExecution: (e) => e == 5,
              )
              ..addAll([5, 3, 1])
              ..removeFirstSafe();
        expect(q.toSet(), {1, 5});
      });

      test("removeFirstSafe returns null when all elements are postponed", () {
        final q = StablePriorityQueue<int>(
          comparator: (a, b) => b.compareTo(a),
          postponeExecution: (_) => true,
        )..addAll([1, 2, 3]);
        expect(q.removeFirstSafe(), isNull);
        expect(q.length, 3);
      });

      test("removeFirstSafe returns the element when none are postponed", () {
        final q = StablePriorityQueue<int>(
          comparator: (a, b) => b.compareTo(a),
          postponeExecution: (_) => false,
        )..addAll([1, 5, 3]);
        expect(q.removeFirstSafe(), 5);
      });
    });
  });

  group("PriorityQueue", () {
    test("uses element.priority field via the default comparator", () {
      final queue = PriorityQueue<_Item>()
        ..add(_Item(priority: 1))
        ..add(_Item(priority: 5))
        ..add(_Item(priority: 3));
      expect(queue.removeFirst().priority, 5);
    });
  });
}

class _Item {
  final int priority;
  _Item({required this.priority});
}
