import 'package:apex_lsp/cancellation_tracker.dart';
import 'package:test/test.dart';

void main() {
  group('CancellationTracker', () {
    late CancellationTracker tracker;

    setUp(() {
      tracker = CancellationTracker();
    });

    test('marks request as cancelled', () {
      tracker.cancel(42);
      expect(tracker.isCancelled(42), isTrue);
    });

    test('returns false for non-cancelled request', () {
      expect(tracker.isCancelled(42), isFalse);
    });

    test('removes request ID after checking cancellation', () {
      tracker.cancel(42);
      expect(tracker.isCancelled(42), isTrue);
      // Second check should return false (ID was removed).
      expect(tracker.isCancelled(42), isFalse);
    });

    test('handles string IDs', () {
      tracker.cancel('abc-123');
      expect(tracker.isCancelled('abc-123'), isTrue);
      expect(tracker.isCancelled('abc-123'), isFalse);
    });

    test('handles multiple concurrent cancellations', () {
      tracker.cancel(1);
      tracker.cancel(2);
      tracker.cancel(3);

      expect(tracker.isCancelled(1), isTrue);
      expect(tracker.isCancelled(2), isTrue);
      expect(tracker.isCancelled(3), isTrue);
    });

    test('enforces maximum queue size with FIFO eviction', () {
      final customTracker = CancellationTracker(maxQueueSize: 3);

      // Fill the queue.
      customTracker.cancel(1);
      customTracker.cancel(2);
      customTracker.cancel(3);

      // Add one more - should evict ID 1.
      customTracker.cancel(4);

      // ID 1 should have been evicted.
      expect(customTracker.isCancelled(1), isFalse);
      // IDs 2, 3, 4 should still be there.
      expect(customTracker.isCancelled(2), isTrue);
      expect(customTracker.isCancelled(3), isTrue);
      expect(customTracker.isCancelled(4), isTrue);
    });

    test('default max queue size is 1000', () {
      // Fill beyond a reasonable number to ensure it's bounded.
      for (var i = 0; i < 1500; i++) {
        tracker.cancel(i);
      }

      // First 500 should have been evicted.
      expect(tracker.isCancelled(0), isFalse);
      expect(tracker.isCancelled(499), isFalse);

      // Last 1000 should still be present.
      expect(tracker.isCancelled(500), isTrue);
      expect(tracker.isCancelled(1499), isTrue);
    });
  });
}
