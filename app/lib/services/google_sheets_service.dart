/**
 * Google Sheets Servisi
 * Supabase Edge Function üzerinden Google Sheets'ten sabit giderleri okur
 */

import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/app_config.dart';
import '../models/fixed_expense.dart';
import '../utils/app_logger.dart';

class GoogleSheetsService {
  /// Google Sheets'ten sabit giderleri getirir
  static Future<List<FixedExpense>> getFixedExpenses() async {
    try {
      final baseUrl = AppConfig.productionBackendUrl;
      final uri = Uri.parse('$baseUrl?endpoint=fixed-expenses');

      AppLogger.info('📊 Google Sheets\'ten sabit giderler yükleniyor...');

      final request = http.Request('GET', uri);
      request.headers['apikey'] = AppConfig.supabaseAnonKey;
      request.headers['Authorization'] = 'Bearer ${AppConfig.supabaseAnonKey}';

      final response = await request.send().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('Google Sheets okuma zaman aşımı');
        },
      );

      final responseBody = await http.Response.fromStream(response).timeout(
        const Duration(seconds: 30),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(responseBody.body) as Map<String, dynamic>;
        final expensesList = json['expenses'] as List<dynamic>? ?? [];

        final expenses = expensesList.map((expenseJson) {
          try {
            // Google Sheets'ten gelen veriyi FixedExpense'ye dönüştür
            return FixedExpense(
              id: expenseJson['id'] as String?,
              ownerId: expenseJson['ownerId'] as String? ?? 'system',
              ownerName: expenseJson['ownerName'] as String? ?? 'Sistem',
              description: expenseJson['description'] as String? ?? '',
              amount: (expenseJson['amount'] as num?)?.toDouble() ?? 0.0,
              category: expenseJson['category'] as String?,
              recurrence: expenseJson['recurrence'] as String?,
              notes: expenseJson['notes'] as String?,
              isActive: expenseJson['isActive'] as bool? ?? true,
              createdAt: expenseJson['createdAt'] != null
                  ? DateTime.tryParse(expenseJson['createdAt'] as String)
                  : DateTime.now(),
            );
          } catch (e) {
            AppLogger.warning('Sabit gider parse hatası: $e');
            return null;
          }
        }).whereType<FixedExpense>().toList();

        AppLogger.success('✅ ${expenses.length} sabit gider Google Sheets\'ten yüklendi');
        return expenses;
      } else {
        String errorMessage = 'Google Sheets okuma hatası: ${response.statusCode}';
        try {
          final errorJson = jsonDecode(responseBody.body) as Map<String, dynamic>?;
          if (errorJson != null) {
            errorMessage = errorJson['error'] as String? ?? errorJson['message'] as String? ?? errorMessage;
          }
        } catch (_) {
          // JSON parse edilemezse body'yi kullan
          if (responseBody.body.length < 500) {
            errorMessage += ' - ${responseBody.body}';
          }
        }
        AppLogger.error('Google Sheets okuma hatası', Exception(errorMessage));
        throw Exception(errorMessage);
      }
    } catch (e) {
      AppLogger.error('Google Sheets servisi hatası', e);
      if (e is Exception) {
        rethrow;
      }
      throw Exception('Google Sheets okuma hatası: ${e.toString()}');
    }
  }
}

