import 'package:flutter/foundation.dart';

/// Ultra-low latency In-Memory cache for O(1) duplicate scan detection
/// and instantaneous queue depth tracking without touching disk I/O.
class ScanMemoryCache {
  final Set<String> _admittedCodes = <String>{};
  int _pendingCount = 0;

  /// Get pending unsynced count with zero disk read overhead
  int get pendingCount => _pendingCount;

  /// Fast O(1) in-memory check to see if token was already scanned
  bool isKnownScanned(String code) {
    if (code.isEmpty) return false;
    return _admittedCodes.contains(code.trim());
  }

  /// Record scan in RAM cache
  void recordScan(String code) {
    if (code.isNotEmpty) {
      _admittedCodes.add(code.trim());
    }
  }

  /// Bulk populate admitted codes (called once on app start from SQLite)
  void populate(Iterable<String> codes) {
    for (final c in codes) {
      if (c.isNotEmpty) _admittedCodes.add(c.trim());
    }
    debugPrint('[ScanMemoryCache] 🚀 Initialized with ${_admittedCodes.length} cached scan codes in RAM');
  }

  void incrementPending() {
    _pendingCount++;
  }

  void decrementPending(int count) {
    _pendingCount = (_pendingCount - count).clamp(0, 9999999);
  }

  void setPendingCount(int count) {
    _pendingCount = count.clamp(0, 9999999);
  }

  void clear() {
    _admittedCodes.clear();
    _pendingCount = 0;
  }
}
