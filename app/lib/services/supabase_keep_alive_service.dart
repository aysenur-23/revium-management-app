/**
 * Supabase Keep-Alive Servisi
 * Uygulama açıldığında ve belirli aralıklarla Supabase Edge Function'ını çağırarak
 * projenin duraklatılmasını önler
 */

import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/app_config.dart';
import '../utils/app_logger.dart';

class SupabaseKeepAliveService {
  static Timer? _keepAliveTimer;
  static bool _isRunning = false;

  /// Keep-alive servisini başlatır
  /// Uygulama açıldığında bir kez çağrılmalıdır
  static void start() {
    if (_isRunning) {
      AppLogger.warning('Supabase keep-alive zaten çalışıyor');
      return;
    }

    _isRunning = true;
    AppLogger.info('🔄 Supabase keep-alive servisi başlatılıyor...');

    // İlk çağrıyı hemen yap
    _performKeepAlive();

    // Her 6 saatte bir (21600 saniye) çağrı yap
    _keepAliveTimer = Timer.periodic(
      const Duration(hours: 6),
      (_) => _performKeepAlive(),
    );

    AppLogger.success('✅ Supabase keep-alive servisi başlatıldı (her 6 saatte bir)');
  }

  /// Keep-alive servisini durdurur
  static void stop() {
    if (!_isRunning) {
      return;
    }

    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    _isRunning = false;
    AppLogger.info('🛑 Supabase keep-alive servisi durduruldu');
  }

  /// Tek seferlik keep-alive çağrısı yapar
  static Future<bool> performKeepAliveOnce() async {
    return await _performKeepAlive();
  }

  /// Keep-alive işlemini gerçekleştirir
  static Future<bool> _performKeepAlive() async {
    try {
      final url = AppConfig.productionBackendUrl;
      final uri = Uri.parse(url);

      AppLogger.info('📡 Supabase keep-alive isteği gönderiliyor...');

      final request = http.Request('GET', uri);
      request.headers['apikey'] = AppConfig.supabaseAnonKey;
      request.headers['Authorization'] = 'Bearer ${AppConfig.supabaseAnonKey}';

      final response = await request.send().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Keep-alive zaman aşımı');
        },
      );

      final responseBody = await http.Response.fromStream(response).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        try {
          final json = jsonDecode(responseBody.body) as Map<String, dynamic>;
          if (json['status'] == 'ok') {
            AppLogger.success('✅ Supabase keep-alive başarılı: ${json['message'] ?? 'OK'}');
            return true;
          } else {
            AppLogger.warning('⚠️  Supabase keep-alive beklenmeyen yanıt: ${responseBody.body}');
            return false;
          }
        } catch (e) {
          AppLogger.warning('⚠️  Supabase keep-alive JSON parse hatası: $e');
          // JSON parse edilemese bile 200 döndüyse başarılı say
          return true;
        }
      } else {
        AppLogger.warning('⚠️  Supabase keep-alive başarısız: HTTP ${response.statusCode}');
        return false;
      }
    } catch (e) {
      // Network hataları için özel kontrol
      final errorString = e.toString().toLowerCase();
      if (errorString.contains('socketexception') || 
          errorString.contains('failed host lookup') ||
          errorString.contains('no address associated with hostname') ||
          errorString.contains('network is unreachable')) {
        // İnternet bağlantısı yok - bu normal bir durum, sadece debug log'u
        AppLogger.debug('📡 Supabase keep-alive: İnternet bağlantısı yok (normal)');
        return false;
      }
      
      // Diğer hatalar için warning
      AppLogger.warning('⚠️ Supabase keep-alive hatası: ${e.toString()}');
      return false;
    }
  }

  /// Servisin çalışıp çalışmadığını kontrol eder
  static bool get isRunning => _isRunning;
}

