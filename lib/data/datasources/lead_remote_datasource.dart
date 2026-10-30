import 'dart:convert';
import '../../core/network/api_client.dart';
import '../models/lead_model.dart';

class LeadCaptureResult {
  final bool isSuccess;
  final LeadModel? lead;
  final String? message;

  const LeadCaptureResult({
    required this.isSuccess,
    this.lead,
    this.message,
  });
}

class LeadPaginatedResult {
  final List<LeadModel> leads;
  final bool hasNextPage;
  final int? nextPage;
  final int totalCount;

  const LeadPaginatedResult({
    required this.leads,
    required this.hasNextPage,
    this.nextPage,
    required this.totalCount,
  });
}

class LeadRemoteDatasource {
  final ApiClient _apiClient;

  LeadRemoteDatasource({required ApiClient apiClient}) : _apiClient = apiClient;

  /// Captures an attendee as a lead via 'organizer/lead-capture-attendee'
  Future<LeadCaptureResult> captureLead({
    required String uniqueId,
    int scanType = 0,
  }) async {
    final response = await _apiClient.dio.post(
      'organizer/lead-capture-attendee',
      data: {
        'unique_id': uniqueId,
        'scan_type': scanType,
      },
    );

    final data = response.data is Map<String, dynamic>
        ? response.data as Map<String, dynamic>
        : jsonDecode(response.data.toString()) as Map<String, dynamic>;

    final status = data['status'] == true;
    final message = data['message']?.toString();

    if (status && data['attendee_details'] is List) {
      final list = data['attendee_details'] as List;
      if (list.isNotEmpty && list.first is Map<String, dynamic>) {
        final map = Map<String, dynamic>.from(list.first as Map<String, dynamic>);
        if (map['lead_id'] == null && data['lead_id'] != null) {
          map['lead_id'] = data['lead_id'];
        }
        final lead = LeadModel.fromJson(map);
        return LeadCaptureResult(
          isSuccess: true,
          lead: lead,
          message: message ?? 'Lead captured successfully',
        );
      }
    }

    return LeadCaptureResult(
      isSuccess: false,
      message: message ?? 'Failed to capture lead',
    );
  }

  /// Fetches paginated list of leads via 'organizer/lead-list'
  Future<LeadPaginatedResult> getLeads({
    int pageNo = 1,
    int count = 20,
    String keyword = '',
    int? eventId,
  }) async {
    final eventParam = eventId != null ? eventId.toString() : '';
    final url =
        'organizer/lead-list?count=$count&page_no=$pageNo&key_word=$keyword&event_id=$eventParam';

    final response = await _apiClient.dio.get(url);

    final data = response.data is Map<String, dynamic>
        ? response.data as Map<String, dynamic>
        : jsonDecode(response.data.toString()) as Map<String, dynamic>;

    final rawList = (data['lead_list'] as List<dynamic>?) ?? [];
    final leads = rawList
        .whereType<Map<String, dynamic>>()
        .map((e) => LeadModel.fromJson(e))
        .toList();

    final nextPage = (data['next_page'] as num?)?.toInt();
    final hasNext = nextPage != null;
    final totalCount = (data['total_count'] as num?)?.toInt() ?? leads.length;

    return LeadPaginatedResult(
      leads: leads,
      hasNextPage: hasNext,
      nextPage: nextPage,
      totalCount: totalCount,
    );
  }

  /// Fetches full details for a single lead via 'organizer/lead-details?id=...'
  Future<LeadModel?> getLeadDetails(int id) async {
    final response = await _apiClient.dio.get('organizer/lead-details?id=$id');

    final data = response.data is Map<String, dynamic>
        ? response.data as Map<String, dynamic>
        : jsonDecode(response.data.toString()) as Map<String, dynamic>;

    if (data['attendee_details'] is List) {
      final list = data['attendee_details'] as List;
      if (list.isNotEmpty && list.first is Map<String, dynamic>) {
        final map = Map<String, dynamic>.from(list.first as Map<String, dynamic>);
        if (map['lead_id'] == null) {
          map['lead_id'] = id;
        }
        return LeadModel.fromJson(map);
      }
    }

    return null;
  }

  /// Updates lead type ('HOT' | 'WARM' | 'COLD') and notes via 'organizer/lead-update'
  Future<Map<String, dynamic>> updateLead({
    required int id,
    required String leadType,
    required String notes,
  }) async {
    final response = await _apiClient.dio.post(
      'organizer/lead-update',
      data: {
        'id': id,
        'lead_type': leadType,
        'notes': notes,
      },
    );

    return response.data is Map<String, dynamic>
        ? response.data as Map<String, dynamic>
        : jsonDecode(response.data.toString()) as Map<String, dynamic>;
  }

  /// Requests the remote Excel blob via 'organizer/lead-export-organizer'
  Future<Map<String, dynamic>> exportLeads() async {
    final response = await _apiClient.dio.get('organizer/lead-export-organizer');
    return response.data is Map<String, dynamic>
        ? response.data as Map<String, dynamic>
        : jsonDecode(response.data.toString()) as Map<String, dynamic>;
  }
}
