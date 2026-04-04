import 'dart:io';
import 'dart:typed_data';
import 'package:psyfinance_app/core/api_client.dart';
import 'dashboard_model.dart';

class DashboardRepository {
  final ApiClient _client;

  DashboardRepository(this._client);

  Future<DashboardData> getDashboard(int year) async {
    final data = await _client.get(
      '/api/dashboard',
      queryParameters: {'year': year},
    );
    return DashboardData.fromJson(data as Map<String, dynamic>);
  }

  Future<List<YearlyComparison>> getComparison(List<int> years) async {
    final data = await _client.get(
      '/api/dashboard/comparison',
      queryParameters: {'years': years.join(',')},
    );
    return (data as List)
        .map((e) => YearlyComparison.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Downloads a CSV export and saves it to the user's Downloads folder.
  /// Returns the saved file path on success.
  Future<String> downloadExport(String endpoint, int year, String filename) async {
    final Uint8List bytes = await _client.getBytes(
      '/api/dashboard/export/$endpoint',
      queryParameters: {'year': year},
    );

    final String downloadsDir = _resolveDownloadsDir();
    final file = File('$downloadsDir${Platform.pathSeparator}$filename');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  String _resolveDownloadsDir() {
    if (Platform.isWindows) {
      return '${Platform.environment['USERPROFILE'] ?? ''}\\Downloads';
    } else if (Platform.isMacOS || Platform.isLinux) {
      return '${Platform.environment['HOME'] ?? ''}/Downloads';
    }
    return Directory.systemTemp.path;
  }
}
