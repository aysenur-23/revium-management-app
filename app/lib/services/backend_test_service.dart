import 'package:http/http.dart' as http;
import '../services/upload_service.dart';
import '../utils/app_logger.dart';
import '../config/app_config.dart';

/// Backend endpoint test servisi
/// Backend'in çalışıp çalışmadığını ve download endpoint'inin erişilebilir olup olmadığını test eder
class BackendTestService {
  /// Backend health check endpoint'ini test eder
  static Future<bool> testHealthCheck() async {
    try {
      final baseUrl = await getBackendBaseUrl();
      String healthUrl;
      
      if (baseUrl.contains('supabase.co')) {
        // Supabase Edge Function için
        if (baseUrl.endsWith('/upload')) {
          healthUrl = '${baseUrl.substring(0, baseUrl.length - 6)}health';
        } else {
          healthUrl = baseUrl.endsWith('/') ? '${baseUrl}health' : '$baseUrl/health';
        }
      } else {
        healthUrl = baseUrl.endsWith('/') ? '${baseUrl}health' : '$baseUrl/health';
      }
      
      AppLogger.info('🔍 Health check test ediliyor: $healthUrl');
      
      final request = http.Request('GET', Uri.parse(healthUrl));
      
      // Supabase için header ekle
      if (baseUrl.contains('supabase.co')) {
        request.headers['apikey'] = AppConfig.supabaseAnonKey;
        request.headers['Authorization'] = 'Bearer ${AppConfig.supabaseAnonKey}';
      }
      
      final response = await request.send().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Health check zaman aşımı');
        },
      );
      
      final responseBody = await http.Response.fromStream(response).timeout(
        const Duration(seconds: 10),
      );
      
      AppLogger.info('📊 Health check yanıtı: Status=${response.statusCode}');
      AppLogger.info('📊 Health check body: ${responseBody.body}');
      
      if (response.statusCode == 200) {
        AppLogger.success('✅ Backend health check başarılı');
        return true;
      } else {
        AppLogger.warning('⚠️ Backend health check başarısız: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      AppLogger.error('❌ Health check hatası', e);
      return false;
    }
  }
  
  /// Backend download endpoint'ini test eder (gerçek dosya indirmeden)
  static Future<Map<String, dynamic>> testDownloadEndpoint(String testFileId) async {
    try {
      final baseUrl = await getBackendBaseUrl();
      String downloadUrl;
      
      if (baseUrl.contains('supabase.co')) {
        if (baseUrl.endsWith('/upload')) {
          downloadUrl = '${baseUrl.substring(0, baseUrl.length - 6)}download';
        } else {
          downloadUrl = baseUrl.replaceAll('/upload', '/download');
        }
      } else if (baseUrl.endsWith('/upload')) {
        downloadUrl = '${baseUrl.substring(0, baseUrl.length - 6)}download';
      } else {
        downloadUrl = baseUrl.endsWith('/') ? '${baseUrl}download' : '$baseUrl/download';
      }
      
      final uri = Uri.parse('$downloadUrl?fileId=$testFileId');
      AppLogger.info('🔍 Download endpoint test ediliyor: $uri');
      AppLogger.info('🔍 Test File ID: $testFileId');
      
      final request = http.Request('GET', uri);
      
      // Supabase için header ekle
      if (baseUrl.contains('supabase.co')) {
        request.headers['apikey'] = AppConfig.supabaseAnonKey;
        request.headers['Authorization'] = 'Bearer ${AppConfig.supabaseAnonKey}';
      }
      
      final stopwatch = Stopwatch()..start();
      final response = await request.send().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('Download endpoint zaman aşımı');
        },
      );
      
      final responseBody = await http.Response.fromStream(response).timeout(
        const Duration(seconds: 30),
      );
      stopwatch.stop();
      
      final result = {
        'success': response.statusCode == 200,
        'statusCode': response.statusCode,
        'responseTime': stopwatch.elapsedMilliseconds,
        'contentLength': responseBody.bodyBytes.length,
        'contentType': response.headers['content-type'] ?? 'unknown',
        'body': response.statusCode != 200 ? responseBody.body : null,
      };
      
      AppLogger.info('📊 Download endpoint yanıtı:');
      AppLogger.info('   → Status: ${result['statusCode']}');
      AppLogger.info('   → Response Time: ${result['responseTime']}ms');
      AppLogger.info('   → Content Length: ${result['contentLength']} bytes');
      AppLogger.info('   → Content Type: ${result['contentType']}');
      
      if (result['success'] as bool) {
        AppLogger.success('✅ Download endpoint çalışıyor!');
      } else {
        AppLogger.warning('⚠️ Download endpoint başarısız');
        if (result['body'] != null) {
          AppLogger.warning('   → Hata mesajı: ${result['body']}');
        }
      }
      
      return result;
    } catch (e) {
      AppLogger.error('❌ Download endpoint test hatası', e);
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }
  
  /// Backend URL'ini ve endpoint'lerini kontrol eder
  static Future<Map<String, dynamic>> testAllEndpoints() async {
    AppLogger.info('🔍 Backend endpointleri test ediliyor...');
    
    final baseUrl = await getBackendBaseUrl();
    AppLogger.info('📡 Backend Base URL: $baseUrl');
    
    final results = <String, dynamic>{
      'baseUrl': baseUrl,
      'healthCheck': await testHealthCheck(),
    };
    
    return results;
  }
}

