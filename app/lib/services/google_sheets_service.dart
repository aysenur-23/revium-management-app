/**
 * Google Sheets Servisi
 * Supabase Edge Function üzerinden Google Sheets'ten sabit giderleri okur
 */

import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import '../config/app_config.dart';
import '../models/fixed_expense.dart';
import '../utils/app_logger.dart';

class GoogleSheetsService {
  // Cache mekanizması: Aynı anda gelen istekler aynı Future'i paylaşır
  static Future<List<FixedExpense>>? _cachedRequest;
  static DateTime? _lastCacheTime;
  static const Duration _cacheDuration = Duration(seconds: 10); // 10 saniye cache
  static bool _isRequestInProgress = false; // İstek devam ediyor mu?

  /// Google Sheets'ten sabit giderleri getirir
  /// Aynı anda gelen istekler aynı Future'i paylaşır (duplicate request önleme)
  static Future<List<FixedExpense>> getFixedExpenses({bool forceRefresh = false}) async {
    // Eğer zaten bir istek devam ediyorsa, onu kullan (duplicate request önleme)
    if (!forceRefresh && _cachedRequest != null && _isRequestInProgress) {
      AppLogger.debug('📊 Devam eden istek kullanılıyor (duplicate request önlendi)');
      try {
        return await _cachedRequest!;
      } catch (e) {
        // Devam eden istek hata verdi, yeni istek başlat
        AppLogger.warning('⚠️ Devam eden istek hata verdi, yeni istek başlatılıyor: $e');
        _cachedRequest = null;
        _isRequestInProgress = false;
      }
    }

    // Cache kontrolü: Eğer cache'de başarılı bir sonuç varsa ve süresi dolmamışsa kullan
    if (!forceRefresh && 
        _cachedRequest != null && 
        !_isRequestInProgress &&
        _lastCacheTime != null &&
        DateTime.now().difference(_lastCacheTime!) < _cacheDuration) {
      AppLogger.debug('📊 Cache\'den sabit giderler döndürülüyor');
      try {
        // Cache'deki sonucu kontrol et (eğer hata varsa yakalanır)
        return await _cachedRequest!;
      } catch (e) {
        // Cache'deki sonuç hatalı, temizle ve yeni istek başlat
        AppLogger.warning('⚠️ Cache\'deki sonuç hatalı, yeni istek başlatılıyor: $e');
        _cachedRequest = null;
        _lastCacheTime = null;
      }
    }

    // Yeni istek başlat
    _isRequestInProgress = true;
    _cachedRequest = _fetchFixedExpenses();
    _lastCacheTime = DateTime.now();
    
    try {
      final result = await _cachedRequest!;
      // Başarılı istek sonrası cache süresini uzat
      _lastCacheTime = DateTime.now();
      _isRequestInProgress = false;
      return result;
    } catch (e) {
      // Hata durumunda cache'i temizle
      AppLogger.error('Google Sheets isteği başarısız, cache temizleniyor', e);
      _cachedRequest = null;
      _lastCacheTime = null;
      _isRequestInProgress = false;
      rethrow;
    }
  }

  /// Gerçek API çağrısını yapar (retry mekanizması ile)
  static Future<List<FixedExpense>> _fetchFixedExpenses() async {
    const maxRetries = 2; // Toplam 3 deneme (1 ilk + 2 retry)
    const timeoutDuration = Duration(seconds: 60);
    
    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        if (attempt > 0) {
          AppLogger.info('📊 Retry attempt $attempt/$maxRetries');
          await Future.delayed(Duration(seconds: 2 * attempt)); // Exponential backoff
        }
        
        final baseUrl = AppConfig.productionBackendUrl;
        final uri = Uri.parse('$baseUrl?endpoint=fixed-expenses');

        AppLogger.info('📊 Google Sheets\'ten sabit giderler yükleniyor... (attempt ${attempt + 1}/${maxRetries + 1})');
        AppLogger.debug('📊 Endpoint URL: $uri');

        final request = http.Request('GET', uri);
        request.headers['apikey'] = AppConfig.supabaseAnonKey;
        request.headers['Authorization'] = 'Bearer ${AppConfig.supabaseAnonKey}';
        
        AppLogger.debug('📊 Request headers: apikey ve Authorization eklendi');

        final response = await request.send().timeout(
          timeoutDuration,
          onTimeout: () {
            throw TimeoutException('Google Sheets okuma zaman aşımı (60 saniye)', timeoutDuration);
          },
        );

        final responseBody = await http.Response.fromStream(response).timeout(
          timeoutDuration,
          onTimeout: () {
            throw TimeoutException('Yanıt alma zaman aşımı (60 saniye)', timeoutDuration);
          },
        );

        if (response.statusCode == 200) {
        AppLogger.debug('📊 Response body: ${responseBody.body.substring(0, responseBody.body.length > 500 ? 500 : responseBody.body.length)}');
        
        final json = jsonDecode(responseBody.body) as Map<String, dynamic>;
        final expensesList = json['expenses'] as List<dynamic>? ?? [];

        AppLogger.info('📊 Google Sheets\'ten ${expensesList.length} sabit gider verisi alındı');
        if (expensesList.isNotEmpty) {
          AppLogger.debug('📊 İlk sabit gider örneği: ${expensesList[0]}');
        }

        if (expensesList.isEmpty) {
          AppLogger.warning('⚠️ Google Sheets\'te sabit gider bulunamadı');
          return [];
        }

        final expenses = expensesList.map((expenseJson) {
          try {
            // Google Sheets'ten gelen veriyi FixedExpense'ye dönüştür
            final expense = FixedExpense(
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
            AppLogger.debug('✅ Sabit gider parse edildi: ${expense.description} - ${expense.amount}₺');
            return expense;
          } catch (e) {
            AppLogger.warning('⚠️ Sabit gider parse hatası: $e - Data: $expenseJson');
            return null;
          }
        }).whereType<FixedExpense>().toList();

          AppLogger.success('✅ ${expenses.length} sabit gider Google Sheets\'ten başarıyla yüklendi');
          return expenses;
        } else {
          String errorMessage = 'Google Sheets okuma hatası: ${response.statusCode}';
          String errorBody = responseBody.body;
          try {
            final errorJson = jsonDecode(errorBody) as Map<String, dynamic>?;
            if (errorJson != null) {
              errorMessage = errorJson['error'] as String? ?? errorJson['message'] as String? ?? errorMessage;
              if (errorJson['detail'] != null) {
                errorMessage += ' - ${errorJson['detail']}';
              }
            }
          } catch (_) {
            // JSON parse edilemezse body'yi kullan
            if (errorBody.length < 500) {
              errorMessage += ' - ${errorBody}';
            }
          }
          
          // 504 (Gateway Timeout) veya timeout hataları için retry yap
          if (response.statusCode == 504 || errorMessage.toLowerCase().contains('timeout')) {
            if (attempt < maxRetries) {
              AppLogger.warning('⚠️ Timeout hatası, retry yapılıyor...');
              continue; // Retry yap
            }
          }
          
          AppLogger.error('Google Sheets okuma hatası', Exception(errorMessage));
          AppLogger.error('Response status: ${response.statusCode}, body: $errorBody');
          throw Exception(errorMessage);
        }
      } catch (e) {
        // Son deneme ise hatayı fırlat
        if (attempt >= maxRetries) {
          AppLogger.error('Google Sheets servisi hatası (tüm denemeler başarısız)', e);
          
          // Timeout hataları için özel mesaj
          if (e is TimeoutException) {
            throw Exception('Google Sheets okuma zaman aşımı. İnternet bağlantınızı kontrol edin ve tekrar deneyin.');
          }
          
          // Network hataları için özel mesajlar
          final errorString = e.toString().toLowerCase();
          if (errorString.contains('socketexception') || 
              errorString.contains('failed host lookup') ||
              errorString.contains('no address associated with hostname') ||
              errorString.contains('network is unreachable')) {
            throw Exception('Supabase\'e bağlanılamıyor. İnternet bağlantınızı kontrol edin veya daha sonra tekrar deneyin.');
          }
          
          if (e is Exception) {
            rethrow;
          }
          throw Exception('Google Sheets okuma hatası: ${e.toString()}');
        }
        
        // Retry yapılacak
        AppLogger.warning('⚠️ İstek başarısız, retry yapılıyor... (${e.toString()})');
      }
    }
    
    // Buraya gelmemeli (tüm denemeler başarısız olursa yukarıda exception fırlatılır)
    throw Exception('Google Sheets okuma hatası: Tüm denemeler başarısız');
  }

  /// Cache'i temizler (manuel refresh için)
  static void clearCache() {
    _cachedRequest = null;
    _lastCacheTime = null;
    _isRequestInProgress = false;
    AppLogger.debug('📊 Google Sheets cache temizlendi');
  }
}

