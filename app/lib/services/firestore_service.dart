/**
 * Firestore servisi
 * Firestore veritabanı işlemlerini yönetir
 */

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../models/expense_entry.dart';
import '../utils/app_logger.dart';
import '../config/app_config.dart';

class FirestoreService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Kullanıcıyı Firestore'a kaydeder (varsa güncellemez, sadece oluşturur)
  /// userId artık Firebase Auth UID olmalı
  static Future<void> createUserIfNotExists(
      String userId, String fullName) async {
    try {
      final userRef = _firestore.collection('users').doc(userId);
      
      // Timeout ile get işlemi
      final userDoc = await userRef.get().timeout(
        Duration(seconds: AppConfig.firestoreTimeoutSeconds),
        onTimeout: () {
          throw Exception('Firestore bağlantı zaman aşımı. İnternet bağlantınızı kontrol edin.');
        },
      );

      if (!userDoc.exists) {
        await userRef.set({
          'fullName': fullName,
          'createdAt': FieldValue.serverTimestamp(),
        }).timeout(
          Duration(seconds: AppConfig.firestoreTimeoutSeconds),
          onTimeout: () {
            throw Exception('Firestore kayıt zaman aşımı. İnternet bağlantınızı kontrol edin.');
          },
        );
      }
    } on FirebaseException catch (e) {
      // FirebaseException'ı düzgün handle et
      AppLogger.error('Firestore FirebaseException: ${e.code} - ${e.message}', e);
      throw Exception('Firestore hatası: ${e.code} - ${e.message}');
    } catch (e) {
      // Diğer hatalar için
      AppLogger.error('Firestore genel hata', e);
      throw Exception('Firestore hatası: ${e.toString()}');
    }
  }

  /// Kullanıcı bilgilerini Firestore'dan getirir
  static Future<Map<String, dynamic>?> getUser(String userId) async {
    try {
      final userRef = _firestore.collection('users').doc(userId);
      final userDoc = await userRef.get().timeout(
        Duration(seconds: AppConfig.firestoreTimeoutSeconds),
        onTimeout: () {
          throw Exception('Firestore bağlantı zaman aşımı. İnternet bağlantınızı kontrol edin.');
        },
      );

      if (userDoc.exists) {
        return userDoc.data() as Map<String, dynamic>?;
      }
      return null;
    } on FirebaseException catch (e) {
      AppLogger.error('Firestore getUser FirebaseException: ${e.code} - ${e.message}', e);
      return null;
    } catch (e) {
      AppLogger.error('Firestore getUser genel hata', e);
      return null;
    }
  }

  /// Kullanıcının kendi kayıtlarını stream olarak döndürür
  /// Performans için optimize edilmiş: composite index gerekli (ownerId + createdAt)
  static Stream<List<ExpenseEntry>> streamMyEntries(String userId) {
    return _firestore
        .collection('entries')
        .where('ownerId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(AppConfig.streamLimit) // İlk 100 kayıt (performans için)
        .snapshots(includeMetadataChanges: false) // Sadece gerçek değişiklikler için
        .map((snapshot) {
      try {
        // Performans için daha hızlı parse
        final entries = <ExpenseEntry>[];
        for (var doc in snapshot.docs) {
          try {
            final data = doc.data() as Map<String, dynamic>;
            entries.add(ExpenseEntry.fromJson(data, doc.id));
          } catch (e) {
            AppLogger.warning('streamMyEntries parse hatası (doc ${doc.id}): $e');
            // Hatalı dokümanı atla
          }
        }
        return entries;
      } catch (e) {
        AppLogger.error('Firestore streamMyEntries parse hatası', e);
        return <ExpenseEntry>[];
      }
    });
  }

  /// Tüm kayıtları stream olarak döndürür
  static Stream<List<ExpenseEntry>> streamAllEntries() {
    return _firestore
        .collection('entries')
        .orderBy('createdAt', descending: true)
        .limit(AppConfig.streamLimit) // Performans için limit ekle
        .snapshots()
        .handleError((error) {
      // Hata durumunda boş liste döndür ve hatayı logla
        AppLogger.error('Firestore streamAllEntries hatası', error);
      return <ExpenseEntry>[];
    })
        .map((snapshot) {
      try {
        return snapshot.docs
            .map((doc) => ExpenseEntry.fromJson(doc.data() as Map<String, dynamic>, doc.id))
            .toList();
      } catch (e) {
        AppLogger.error('Firestore streamAllEntries parse hatası', e);
        return <ExpenseEntry>[];
      }
    });
  }

  /// Yeni bir harcama kaydı ekler
  static Future<void> addEntry(ExpenseEntry entry) async {
    try {
      await _firestore.collection('entries').add({
        ...entry.toJson(),
        'createdAt': FieldValue.serverTimestamp(),
        }).timeout(
          Duration(seconds: AppConfig.firestoreTimeoutSeconds),
        onTimeout: () {
          throw Exception('Firestore kayıt zaman aşımı. İnternet bağlantınızı kontrol edin.');
        },
      );
    } on FirebaseException catch (e) {
      throw Exception('Firestore hatası: ${e.code} - ${e.message}');
    } catch (e) {
      throw Exception('Firestore hatası: ${e.toString()}');
    }
  }

  /// Harcama kaydını siler (sadece sahibi silebilir)
  static Future<void> deleteEntry(String entryId, String userId) async {
    try {
      // Önce entry'yi kontrol et
      final entryRef = _firestore.collection('entries').doc(entryId);
      final entryDoc = await entryRef.get().timeout(
        Duration(seconds: AppConfig.firestoreTimeoutSeconds),
        onTimeout: () {
          throw Exception('Firestore bağlantı zaman aşımı. İnternet bağlantınızı kontrol edin.');
        },
      );

      if (!entryDoc.exists) {
        throw Exception('Kayıt bulunamadı.');
      }

      final entryData = entryDoc.data() as Map<String, dynamic>?;
      final ownerId = entryData?['ownerId'] as String?;

      // Owner kontrolü
      if (ownerId != userId) {
        throw Exception('Bu kaydı silme yetkiniz yok. Sadece kendi kayıtlarınızı silebilirsiniz.');
      }

      // Entry'yi sil
      await entryRef.delete().timeout(
        Duration(seconds: AppConfig.firestoreTimeoutSeconds),
        onTimeout: () {
          throw Exception('Firestore silme zaman aşımı. İnternet bağlantınızı kontrol edin.');
        },
      );
    } on FirebaseException catch (e) {
      throw Exception('Firestore hatası: ${e.code} - ${e.message}');
    } catch (e) {
      throw Exception('Firestore hatası: ${e.toString()}');
    }
  }

  /// Tüm farklı ownerName değerlerini getirir (filtreleme için)
  static Future<List<String>> getAllOwnerNames() async {
    try {
      final snapshot = await _firestore.collection('entries').get().timeout(
        Duration(seconds: AppConfig.firestoreTimeoutSeconds),
        onTimeout: () {
          throw Exception('Firestore sorgu zaman aşımı. İnternet bağlantınızı kontrol edin.');
        },
      );
      final ownerNames = <String>{};

      for (var doc in snapshot.docs) {
        try {
          final data = doc.data() as Map<String, dynamic>?;
          if (data != null) {
            final ownerName = data['ownerName'] as String?;
            if (ownerName != null && ownerName.isNotEmpty) {
              ownerNames.add(ownerName);
            }
          }
        } catch (e) {
          AppLogger.warning('getAllOwnerNames parse hatası (doc ${doc.id}): $e');
          // Hatalı dokümanı atla, devam et
        }
      }

      return ownerNames.toList()..sort();
    } on FirebaseException catch (e) {
      throw Exception('Firestore hatası: ${e.code} - ${e.message}');
    } catch (e) {
      throw Exception('Firestore hatası: ${e.toString()}');
    }
  }

  /// Tüm farklı ownerName değerlerini stream olarak döndürür (realtime güncelleme için)
  static Stream<List<String>> streamAllOwnerNames() {
    return _firestore
        .collection('entries')
        .snapshots()
        .handleError((error) {
      // Hata durumunda boş liste döndür ve hatayı logla
      AppLogger.error('Firestore streamAllOwnerNames hatası', error);
      return <String>[];
    })
        .map((snapshot) {
      try {
        final ownerNames = <String>{};

        for (var doc in snapshot.docs) {
          try {
            final data = doc.data() as Map<String, dynamic>?;
            if (data != null) {
              final ownerName = data['ownerName'] as String?;
              if (ownerName != null && ownerName.isNotEmpty) {
                ownerNames.add(ownerName);
              }
            }
          } catch (e) {
            AppLogger.warning('streamAllOwnerNames doc parse hatası (doc ${doc.id}): $e');
            // Hatalı dokümanı atla, devam et
          }
        }

        return ownerNames.toList()..sort();
      } catch (e) {
        AppLogger.error('Firestore streamAllOwnerNames parse hatası', e);
        return <String>[];
      }
    });
  }

  /// Belirli bir tarih aralığındaki kayıtları getirir
  static Future<List<ExpenseEntry>> getEntriesByDateRange(
    DateTime startDate,
    DateTime endDate,
    String? userId,
  ) async {
    try {
      Query query = _firestore.collection('entries');

      if (userId != null && userId.isNotEmpty) {
        query = query.where('ownerId', isEqualTo: userId);
      }

      final snapshot = await query.get().timeout(
        Duration(seconds: AppConfig.firestoreTimeoutSeconds),
        onTimeout: () {
          throw Exception('Firestore sorgu zaman aşımı. İnternet bağlantınızı kontrol edin.');
        },
      );
      
      final entries = <ExpenseEntry>[];
      for (var doc in snapshot.docs) {
        try {
          final data = doc.data() as Map<String, dynamic>?;
          if (data != null) {
            entries.add(ExpenseEntry.fromJson(data, doc.id));
          }
        } catch (e) {
          AppLogger.warning('getEntriesByDateRange parse hatası (doc ${doc.id}): $e');
          // Hatalı dokümanı atla, devam et
        }
      }

      // Tarih aralığını normalize et (sadece tarih kısmı, saat bilgisi olmadan)
      final normalizedStartDate = DateTime(startDate.year, startDate.month, startDate.day);
      final normalizedEndDate = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59, 999);

      return entries.where((entry) {
        if (entry.createdAt == null) return false;
        
        // Entry tarihini normalize et
        final entryDate = DateTime(
          entry.createdAt!.year,
          entry.createdAt!.month,
          entry.createdAt!.day,
        );
        
        // Tarih aralığında mı kontrol et (>= startDate && <= endDate)
        return entryDate.compareTo(normalizedStartDate) >= 0 &&
            entryDate.compareTo(normalizedEndDate) <= 0;
      }).toList();
    } on FirebaseException catch (e) {
      throw Exception('Firestore tarih aralığı sorgusu hatası: ${e.code} - ${e.message}');
    } catch (e) {
      throw Exception('Firestore tarih aralığı sorgusu hatası: ${e.toString()}');
    }
  }

}

