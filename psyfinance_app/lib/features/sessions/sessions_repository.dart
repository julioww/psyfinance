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
}
