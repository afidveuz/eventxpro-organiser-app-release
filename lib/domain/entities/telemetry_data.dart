import 'dart:math';

/// Telemetry and service-level health metrics as mandated by Section 11.
class TelemetryData {
  int totalScans;
  int acceptedCount;
  int rejectedCount;
  int warningCount;
  int duplicateSuppressedCount;
  int queueDropCount;
  int networkTimeoutCount;
  final List<int> _latenciesMs;
  int lastDecodeToEventMs;
  String currentAdapter;
  bool isOnline;
  int pendingQueueDepth;

  TelemetryData({
    this.totalScans = 0,
    this.acceptedCount = 0,
    this.rejectedCount = 0,
    this.warningCount = 0,
    this.duplicateSuppressedCount = 0,
    this.queueDropCount = 0,
    this.networkTimeoutCount = 0,
    List<int>? latenciesMs,
    this.lastDecodeToEventMs = 12,
    this.currentAdapter = 'Zebra DataWedge Native',
    this.isOnline = true,
    this.pendingQueueDepth = 0,
  }) : _latenciesMs = latenciesMs ?? [];

  List<int> get latencies => List.unmodifiable(_latenciesMs);

  void recordLatency(int latencyMs) {
    _latenciesMs.add(latencyMs);
    // Keep bounded rolling window of last 200 scans for accurate responsive percentiles
    if (_latenciesMs.length > 200) {
      _latenciesMs.removeAt(0);
    }
  }

  /// 50th percentile (median) latency in milliseconds
  double get p50 {
    if (_latenciesMs.isEmpty) return 0.0;
    final sorted = List<int>.from(_latenciesMs)..sort();
    final index = (sorted.length * 0.50).floor();
    return sorted[min(index, sorted.length - 1)].toDouble();
  }

  /// 95th percentile latency in milliseconds
  double get p95 {
    if (_latenciesMs.isEmpty) return 0.0;
    final sorted = List<int>.from(_latenciesMs)..sort();
    final index = (sorted.length * 0.95).floor();
    return sorted[min(index, sorted.length - 1)].toDouble();
  }

  /// 99th percentile latency in milliseconds
  double get p99 {
    if (_latenciesMs.isEmpty) return 0.0;
    final sorted = List<int>.from(_latenciesMs)..sort();
    final index = (sorted.length * 0.99).floor();
    return sorted[min(index, sorted.length - 1)].toDouble();
  }

  double get averageLatency {
    if (_latenciesMs.isEmpty) return 0.0;
    final sum = _latenciesMs.reduce((a, b) => a + b);
    return sum / _latenciesMs.length;
  }

  TelemetryData copyWith({
    int? totalScans,
    int? acceptedCount,
    int? rejectedCount,
    int? warningCount,
    int? duplicateSuppressedCount,
    int? queueDropCount,
    int? networkTimeoutCount,
    int? lastDecodeToEventMs,
    String? currentAdapter,
    bool? isOnline,
    int? pendingQueueDepth,
  }) {
    final copy = TelemetryData(
      totalScans: totalScans ?? this.totalScans,
      acceptedCount: acceptedCount ?? this.acceptedCount,
      rejectedCount: rejectedCount ?? this.rejectedCount,
      warningCount: warningCount ?? this.warningCount,
      duplicateSuppressedCount:
          duplicateSuppressedCount ?? this.duplicateSuppressedCount,
      queueDropCount: queueDropCount ?? this.queueDropCount,
      networkTimeoutCount: networkTimeoutCount ?? this.networkTimeoutCount,
      latenciesMs: List<int>.from(_latenciesMs),
      lastDecodeToEventMs: lastDecodeToEventMs ?? this.lastDecodeToEventMs,
      currentAdapter: currentAdapter ?? this.currentAdapter,
      isOnline: isOnline ?? this.isOnline,
      pendingQueueDepth: pendingQueueDepth ?? this.pendingQueueDepth,
    );
    return copy;
  }
}
