import 'dart:collection';

/// Tracks cancelled request IDs for the LSP server.
///
/// Uses a [LinkedHashSet] to provide O(1) lookup, insertion, and removal
/// while preserving insertion order for FIFO eviction when the set grows
/// beyond [maxQueueSize].
///
/// The bounded size prevents unbounded memory growth in the case where
/// cancellations arrive for requests that have already been processed and
/// can therefore never be consumed by [isCancelled].
final class CancellationTracker {
  final int _maxQueueSize;
  final LinkedHashSet<Object> _cancelled = LinkedHashSet();

  CancellationTracker({int maxQueueSize = 1000}) : _maxQueueSize = maxQueueSize;

  /// Marks a request ID as cancelled.
  ///
  /// If the set is at capacity, the oldest ID is evicted (FIFO) before the
  /// new one is added.
  void cancel(Object id) {
    if (_cancelled.contains(id)) return;

    if (_cancelled.length >= _maxQueueSize) {
      // LinkedHashSet iterates in insertion order, so the first element is
      // the oldest — remove it to make room.
      _cancelled.remove(_cancelled.first);
    }

    _cancelled.add(id);
  }

  /// Returns `true` if [id] was cancelled and removes it from tracking.
  ///
  /// Returns `false` if the ID was not marked as cancelled.
  /// Consuming the ID on first check prevents the set from growing due to
  /// requests that completed normally before their cancellation was checked.
  bool isCancelled(Object id) => _cancelled.remove(id);
}
