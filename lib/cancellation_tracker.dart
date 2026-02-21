import 'dart:collection';

/// Tracks cancelled request IDs for the LSP server.
///
/// This class provides a hybrid cleanup strategy:
/// - Immediate removal when a request completes or errors
/// - Bounded FIFO queue (default 1000 IDs) to handle race conditions
///
/// The queue prevents unbounded memory growth while handling the case where
/// a cancellation arrives after the request has already been processed.
final class CancellationTracker {
  final int _maxQueueSize;
  final Queue<Object> _cancelledIds = Queue();
  final Set<Object> _cancelledSet = {};

  CancellationTracker({int maxQueueSize = 1000}) : _maxQueueSize = maxQueueSize;

  /// Marks a request ID as cancelled.
  ///
  /// If the queue is at capacity, the oldest ID is evicted (FIFO).
  void cancel(Object id) {
    if (_cancelledSet.contains(id)) return;

    if (_cancelledIds.length >= _maxQueueSize) {
      final evicted = _cancelledIds.removeFirst();
      _cancelledSet.remove(evicted);
    }

    _cancelledIds.add(id);
    _cancelledSet.add(id);
  }

  /// Checks if a request ID has been cancelled and removes it.
  ///
  /// Returns `true` if the ID was cancelled, `false` otherwise.
  /// The ID is removed from tracking after this check (immediate cleanup).
  bool isCancelled(Object id) {
    if (_cancelledSet.remove(id)) {
      _cancelledIds.remove(id);
      return true;
    }
    return false;
  }
}
