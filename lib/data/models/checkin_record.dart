class CheckinRecord {
  final int? id;
  final String scanRequestId;
  final String encryptedCode;
  final String code;
  final int entranceId;
  final String entranceLocation;
  final String scanType; // 'check_in' or 'check_out'
  final String section; // 'entrances', 'hall', 'agenda', 'session'
  final DateTime timestamp;
  final bool isSynced;
  final bool isNotExist;
  final String? userId;
  final int eventId;

  const CheckinRecord({
    this.id,
    required this.scanRequestId,
    required this.encryptedCode,
    required this.code,
    required this.entranceId,
    required this.entranceLocation,
    required this.scanType,
    this.section = 'entrances',
    required this.timestamp,
    this.isSynced = false,
    this.isNotExist = false,
    this.userId,
    this.eventId = 1,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'scan_request_id': scanRequestId,
      'encrypted_code': encryptedCode,
      'code': code,
      'entrance_id': entranceId,
      'entrance_location': entranceLocation,
      'scan_type': scanType,
      'section': section,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'is_synced': isSynced ? 1 : 0,
      'is_not_exist': isNotExist ? 1 : 0,
      'user_id': userId,
      'event_id': eventId,
    };
  }

  factory CheckinRecord.fromMap(Map<String, dynamic> map) {
    return CheckinRecord(
      id: map['id'] as int?,
      scanRequestId: map['scan_request_id'] as String? ?? '',
      encryptedCode: map['encrypted_code'] as String? ?? '',
      code: map['code'] as String? ?? '',
      entranceId: map['entrance_id'] as int? ?? 1,
      entranceLocation: map['entrance_location'] as String? ?? '',
      scanType: map['scan_type'] as String? ?? 'check_in',
      section: map['section'] as String? ?? 'entrances',
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        map['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      ),
      isSynced: (map['is_synced'] as int? ?? 0) == 1,
      isNotExist: (map['is_not_exist'] as int? ?? 0) == 1,
      userId: map['user_id'] as String?,
      eventId: map['event_id'] as int? ?? 1,
    );
  }

  CheckinRecord copyWith({
    int? id,
    String? scanRequestId,
    String? encryptedCode,
    String? code,
    int? entranceId,
    String? entranceLocation,
    String? scanType,
    String? section,
    DateTime? timestamp,
    bool? isSynced,
    bool? isNotExist,
    String? userId,
    int? eventId,
  }) {
    return CheckinRecord(
      id: id ?? this.id,
      scanRequestId: scanRequestId ?? this.scanRequestId,
      encryptedCode: encryptedCode ?? this.encryptedCode,
      code: code ?? this.code,
      entranceId: entranceId ?? this.entranceId,
      entranceLocation: entranceLocation ?? this.entranceLocation,
      scanType: scanType ?? this.scanType,
      section: section ?? this.section,
      timestamp: timestamp ?? this.timestamp,
      isSynced: isSynced ?? this.isSynced,
      isNotExist: isNotExist ?? this.isNotExist,
      userId: userId ?? this.userId,
      eventId: eventId ?? this.eventId,
    );
  }
}
