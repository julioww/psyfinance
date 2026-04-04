import 'package:psyfinance_app/core/api_client.dart';
import 'package:psyfinance_app/features/revenue_share/revenue_share_model.dart';
import 'patient_model.dart';
import 'patient_summary_model.dart';
import 'rate_history_model.dart';

class PatientsRepository {
  final ApiClient _client;

  PatientsRepository(this._client);

  Future<List<Patient>> getPatients({
    String? status,
    String? location,
    String? currency,
    String? paymentModel,
    String? q,
  }) async {
    final params = <String, dynamic>{};
    if (status != null) params['status'] = status;
    if (location != null) params['location'] = location;
    if (currency != null) params['currency'] = currency;
    if (paymentModel != null) params['paymentModel'] = paymentModel;
    if (q != null && q.isNotEmpty) params['q'] = q;

    final data = await _client.get('/api/patients', queryParameters: params);
    return (data as List).map((e) => Patient.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Patient> createPatient(CreatePatientDto dto) async {
    final data = await _client.post('/api/patients', data: dto.toJson());
    return Patient.fromJson(data as Map<String, dynamic>);
  }

  Future<Patient> updatePatient(String id, UpdatePatientDto dto) async {
    final data = await _client.put('/api/patients/$id', data: dto.toJson());
    return Patient.fromJson(data as Map<String, dynamic>);
  }

  Future<void> archivePatient(String id) async {
    await _client.delete('/api/patients/$id');
  }

  Future<List<RateHistory>> getRateHistory(String patientId) async {
    final data = await _client.get('/api/patients/$patientId/rates');
    return (data as List)
        .map((e) => RateHistory.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<PatientSummary> getPatientSummary(String patientId, int year) async {
    final data = await _client.get(
      '/api/patients/$patientId/summary',
      queryParameters: {'year': year},
    );
    return PatientSummary.fromJson(data as Map<String, dynamic>);
  }

  Future<RateHistory> addRate(
    String patientId,
    double rate,
    DateTime effectiveFrom,
  ) async {
    final data = await _client.post(
      '/api/patients/$patientId/rates',
      data: {
        'rate': rate,
        'effectiveFrom': effectiveFrom.toIso8601String().split('T').first,
      },
    );
    return RateHistory.fromJson(data as Map<String, dynamic>);
  }

  Future<RevenueShareConfig?> getRevenueShare(String patientId) async {
    final data = await _client.get('/api/patients/$patientId/revenue-share');
    return RevenueShareConfig.fromJson(data as Map<String, dynamic>);
  }

  Future<RevenueShareConfig> saveRevenueShare(
    String patientId,
    RevenueShareDto dto,
  ) async {
    final data = await _client.post(
      '/api/patients/$patientId/revenue-share',
      data: dto.toJson(),
    );
    return RevenueShareConfig.fromJson(data as Map<String, dynamic>);
  }

  Future<void> deleteRevenueShare(String patientId) async {
    await _client.delete('/api/patients/$patientId/revenue-share');
  }
}
