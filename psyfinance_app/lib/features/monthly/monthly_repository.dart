import 'package:psyfinance_app/core/api_client.dart';
import 'monthly_view_model.dart';

class MonthlyRepository {
  final ApiClient _client;

  MonthlyRepository(this._client);

  Future<MonthlyView> getMonthlyView(int year, int month) async {
    final data = await _client.get(
      '/api/monthly-view',
      queryParameters: {'year': year, 'month': month},
    );
    return MonthlyView.fromJson(data as Map<String, dynamic>);
  }
}
