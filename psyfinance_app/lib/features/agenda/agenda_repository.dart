import 'package:psyfinance_app/core/api_client.dart';
import 'agenda_session_model.dart';

class AgendaRepository {
  final ApiClient _client;

  AgendaRepository(this._client);

  /// GET /api/agenda?year=Y&month=M
  ///
  /// Returns all session dates for active patients in the given month,
  /// one entry per date per patient.
  Future<List<AgendaSession>> getAgenda(int year, int month) async {
    final data = await _client.get(
      '/api/agenda',
      queryParameters: {
        'year': year.toString(),
        'month': month.toString(),
      },
    );
    final list = (data['sessions'] as List).cast<Map<String, dynamic>>();
    return list.map(AgendaSession.fromJson).toList();
  }
}
