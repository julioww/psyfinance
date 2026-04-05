import 'package:dio/dio.dart';

class AuthRepository {
  final Dio _dio;

  AuthRepository({String baseUrl = 'http://localhost:3000'})
      : _dio = Dio(
          BaseOptions(
            baseUrl: baseUrl,
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 30),
          ),
        );

  /// Returns { token: String, expiresAt: String (ISO8601) }
  Future<Map<String, dynamic>> login({
    required String usuario,
    required String senha,
    bool lembrar = false,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/auth/login',
      data: {'usuario': usuario, 'senha': senha, 'lembrar': lembrar},
    );
    return response.data!;
  }

  Future<void> logout(String token) async {
    try {
      await _dio.post<void>(
        '/auth/logout',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } catch (_) {
      // Best-effort — local state is cleared regardless
    }
  }
}
