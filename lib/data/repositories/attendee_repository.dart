import '../datasources/attendee_remote_datasource.dart';
import '../models/attendee_details_model.dart';
import '../models/attendee_list_item_model.dart';

class AttendeeRepository {
  final AttendeeRemoteDatasource _remoteDatasource;

  AttendeeRepository({required AttendeeRemoteDatasource remoteDatasource})
      : _remoteDatasource = remoteDatasource;

  Future<AttendeeDetailsModel?> getAttendeeDetails(int attendeeId) {
    return _remoteDatasource.getAttendeeDetails(attendeeId: attendeeId);
  }

  Future<AttendeePaginatedResult> getEventAttendees({
    required int eventId,
    required String endPoint,
    int pageNo = 1,
    int count = 20,
    String keyword = '',
    Map<String, dynamic>? filterObj,
  }) {
    return _remoteDatasource.getEventAttendees(
      eventId: eventId,
      endPoint: endPoint,
      pageNo: pageNo,
      count: count,
      keyword: keyword,
      filterObj: filterObj,
    );
  }

  Future<AttendeePaginatedResult> getSessionAttendees({
    required int eventId,
    required String pageType,
    required String actionType,
    int pageNo = 1,
    int count = 20,
    String keyword = '',
    int? agendaId,
    int? hallId,
    int? entranceId,
  }) {
    return _remoteDatasource.getSessionAttendees(
      eventId: eventId,
      pageType: pageType,
      actionType: actionType,
      pageNo: pageNo,
      count: count,
      keyword: keyword,
      agendaId: agendaId,
      hallId: hallId,
      entranceId: entranceId,
    );
  }

  Future<AttendeePunchResult> punchAttendee({
    required String endpoint,
    required Map<String, dynamic> payload,
  }) {
    return _remoteDatasource.punchAttendee(
      endpoint: endpoint,
      payload: payload,
    );
  }
}
