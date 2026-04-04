import 'package:psyfinance_app/core/api_client.dart';
import 'payment_model.dart';

class PaymentsRepository {
  final ApiClient _client;

  PaymentsRepository(this._client);

  Future<Payment> getPayment(String sessionRecordId) async {
    final data = await _client.get('/api/payments/$sessionRecordId');
    return Payment.fromJson(data as Map<String, dynamic>);
  }

  Future<Payment> updatePayment(String sessionRecordId, double amountPaid) async {
    final data = await _client.put(
      '/api/payments/$sessionRecordId',
      data: {'amountPaid': amountPaid},
    );
    return Payment.fromJson(data as Map<String, dynamic>);
  }
}
