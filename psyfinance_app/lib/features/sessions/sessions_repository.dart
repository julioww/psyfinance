import 'package:psyfinance_app/core/api_client.dart';
import 'session_record_model.dart';

class SessionsRepository {
  final ApiClient _client;

  SessionsRepository(this._client);

  /// Returns the session record for [patientId]/[year]/[month], or null if none exists (404).
  Future<SessionRecord?> getSession(
      String patientId, int year, int month) async {
    try {
      final data =
          await _client.get('/api/sessions/$patientId/$year/$month');
      return SessionRecord.fromJson(data as Map<String, dynamic>);
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Upserts the session record and returns the saved result.
  Future<SessionRecord> saveSession(
    String patientId,
    int year,
    int month,
    SaveSessionDto dto,
  ) async {
    final data = await _client.post(
      '/api/sessions/$patientId/$year/$month',
      data: dto.toJson(),
    );
    return SessionRecord.fromJson(data as Map<String, dynamic>);
  }

  /// Appends [date] to the session record for [patientId] in that month.
  ///
  /// Sends `{ appendDate: "DD/MM" }` to the backend, which merges the date
  /// into any existing sessionDates without requiring the caller to know the
  /// full current list.  Throws [ApiException] with statusCode 409 when the
  /// date is already registered for that patient and month.
  Future<SessionRecord> quickAddSession(
    String patientId,
    DateTime date, {
    String? observations,
  }) async {
    final year = date.year;
    final month = date.month;
    final day = date.day.toString().padLeft(2, '0');
    final monthStr = date.month.toString().padLeft(2, '0');
    final appendDate = '$day/$monthStr';

    final body = <String, dynamic>{'appendDate': appendDate};
    if (observations != null && observations.isNotEmpty) {
      body['observations'] = observations;
    }

    final data = await _client.post(
      '/api/sessions/$patientId/$year/$month',
      data: body,
    );
    return SessionRecord.fromJson(data as Map<String, dynamic>);
  }
}
