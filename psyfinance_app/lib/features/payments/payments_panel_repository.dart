import 'package:psyfinance_app/core/api_client.dart';
import 'payment_panel_model.dart';

class PaymentsPanelRepository {
  final ApiClient _client;

  PaymentsPanelRepository(this._client);

  Future<PaymentPanel> getPaymentPanel(int year, int month,
      {String status = 'all'}) async {
    final data = await _client.get(
      '/api/payments',
      queryParameters: {'year': year, 'month': month, 'status': status},
    );
    return PaymentPanel.fromJson(data as Map<String, dynamic>);
  }
}
