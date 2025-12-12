/**
 * Firestore servisi
 * Firestore veritabanı işlemlerini yönetir
 */

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/expense_entry.dart';
import '../models/fixed_expense.dart';
import '../utils/app_logger.dart';
import '../config/app_config.dart';

class FirestoreService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  /// Kullanıcının authenticate olup olmadığını kontrol eder
  static bool _isUserAuthenticated() {
    final currentUser = FirebaseAuth.instance.currentUser;
    return currentUser != null;
  }
  
  /// Authentication kontrolü yapar, değilse hata fırlatır
  static void _ensureAuthenticated() {
    if (!_isUserAuthenticated()) {
      throw Exception('Kullanıcı giriş yapmamış. Lütfen tekrar giriş yapın.');
    }
  }
  
  /// Token'ı yeniler (permission hatası durumunda kullanılır)
  static Future<void> _refreshAuthToken() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        // Token'ı zorla yenile
        await currentUser.getIdToken(true);
        AppLogger.info('Auth token yenilendi');
      }
    } catch (e) {
      AppLogger.warning('Token yenileme hatası: $e');
    }
  }
  

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
        return userDoc.data();
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
    // Authentication kontrolü
    if (!_isUserAuthenticated()) {
      AppLogger.warning('streamMyEntries: Kullanıcı authenticate değil');
      return Stream.value(<ExpenseEntry>[]);
    }
    
    return _firestore
        .collection('entries')
        .where('ownerId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(AppConfig.streamLimit) // İlk 100 kayıt (performans için)
        .snapshots(includeMetadataChanges: false) // Sadece gerçek değişiklikler için
        .handleError((error) {
      final errorString = error.toString().toLowerCase();
      // Permission hatası durumunda token'ı yenilemeyi dene (async olmadan)
      if (errorString.contains('permission') || errorString.contains('permission-denied')) {
        AppLogger.warning('Firestore permission hatası - token yenileniyor...');
        _refreshAuthToken(); // Fire and forget
      }
      AppLogger.error('Firestore streamMyEntries hatası', error);
      // Tüm hataları fırlat - StreamBuilder'ın hasError ile yakalayabilmesi için
      throw error;
    })
        .map((snapshot) {
      try {
        // Performans için daha hızlı parse
        final entries = <ExpenseEntry>[];
        for (var doc in snapshot.docs) {
          try {
            final data = doc.data();
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
    // Authentication kontrolü
    if (!_isUserAuthenticated()) {
      AppLogger.warning('streamAllEntries: Kullanıcı authenticate değil');
      return Stream.value(<ExpenseEntry>[]);
    }
    
    return _firestore
        .collection('entries')
        .orderBy('createdAt', descending: true)
        .limit(AppConfig.streamLimit) // Performans için limit ekle
        .snapshots(includeMetadataChanges: false) // Sadece gerçek değişiklikler için
        .handleError((error) {
      final errorString = error.toString().toLowerCase();
      // Permission hatası durumunda token'ı yenilemeyi dene (async olmadan)
      if (errorString.contains('permission') || errorString.contains('permission-denied')) {
        AppLogger.warning('Firestore permission hatası - token yenileniyor...');
        _refreshAuthToken(); // Fire and forget
      }
      AppLogger.error('Firestore streamAllEntries hatası', error);
      // Tüm hataları fırlat - StreamBuilder'ın hasError ile yakalayabilmesi için
      throw error;
    })
        .map((snapshot) {
      try {
        return snapshot.docs
            .map((doc) => ExpenseEntry.fromJson(doc.data(), doc.id))
            .toList();
      } catch (e) {
        AppLogger.error('Firestore streamAllEntries parse hatası', e);
        return <ExpenseEntry>[];
      }
    });
  }

  /// Kullanıcının kendi kayıtlarını Future olarak döndürür
  static Future<List<ExpenseEntry>> getMyEntries(String userId) async {
    _ensureAuthenticated();
    try {
      final snapshot = await _firestore
          .collection('entries')
          .where('ownerId', isEqualTo: userId)
          .orderBy('createdAt', descending: true)
          .get()
          .timeout(
            Duration(seconds: AppConfig.firestoreTimeoutSeconds),
            onTimeout: () {
              throw Exception('Firestore sorgu zaman aşımı. İnternet bağlantınızı kontrol edin.');
            },
          );
      
      return snapshot.docs
          .map((doc) => ExpenseEntry.fromJson(doc.data(), doc.id))
          .toList();
    } on FirebaseException catch (e) {
      AppLogger.error('Firestore getMyEntries FirebaseException: ${e.code} - ${e.message}', e);
      throw Exception('Firestore hatası: ${e.code} - ${e.message}');
    } catch (e) {
      AppLogger.error('Firestore getMyEntries genel hata', e);
      throw Exception('Firestore hatası: ${e.toString()}');
    }
  }

  /// Tüm kayıtları Future olarak döndürür
  static Future<List<ExpenseEntry>> getAllEntries() async {
    _ensureAuthenticated();
    try {
      final snapshot = await _firestore
          .collection('entries')
          .orderBy('createdAt', descending: true)
          .get()
          .timeout(
            Duration(seconds: AppConfig.firestoreTimeoutSeconds),
            onTimeout: () {
              throw Exception('Firestore sorgu zaman aşımı. İnternet bağlantınızı kontrol edin.');
            },
          );
      
      return snapshot.docs
          .map((doc) => ExpenseEntry.fromJson(doc.data(), doc.id))
          .toList();
    } on FirebaseException catch (e) {
      AppLogger.error('Firestore getAllEntries FirebaseException: ${e.code} - ${e.message}', e);
      throw Exception('Firestore hatası: ${e.code} - ${e.message}');
    } catch (e) {
      AppLogger.error('Firestore getAllEntries genel hata', e);
      throw Exception('Firestore hatası: ${e.toString()}');
    }
  }

  /// Yeni bir harcama kaydı ekler
  static Future<void> addEntry(ExpenseEntry entry) async {
    _ensureAuthenticated();
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

      final entryData = entryDoc.data();
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

  // ========== SABİT GİDERLER ==========

  /// Tüm sabit giderleri stream olarak döndürür
  static Stream<List<FixedExpense>> streamAllFixedExpenses() {
    // Authentication kontrolü
    if (!_isUserAuthenticated()) {
      AppLogger.warning('streamAllFixedExpenses: Kullanıcı authenticate değil');
      return Stream.value(<FixedExpense>[]);
    }
    
    return _firestore
        .collection('fixed_expenses')
        .orderBy('createdAt', descending: true)
        .limit(AppConfig.streamLimit)
        .snapshots(includeMetadataChanges: false) // Sadece gerçek değişiklikler için
        .handleError((error) {
      final errorString = error.toString().toLowerCase();
      // Permission hatası durumunda token'ı yenilemeyi dene (async olmadan)
      if (errorString.contains('permission') || errorString.contains('permission-denied')) {
        AppLogger.warning('Firestore permission hatası - token yenileniyor...');
        _refreshAuthToken(); // Fire and forget
      }
      AppLogger.error('Firestore streamAllFixedExpenses hatası', error);
      // Tüm hataları fırlat - StreamBuilder'ın hasError ile yakalayabilmesi için
      throw error;
    })
        .map((snapshot) {
      try {
        return snapshot.docs
            .map((doc) => FixedExpense.fromJson(doc.data(), doc.id))
            .toList();
      } catch (e) {
        AppLogger.error('Firestore streamAllFixedExpenses parse hatası', e);
        return <FixedExpense>[];
      }
    });
  }

  /// Kullanıcının kendi sabit giderlerini stream olarak döndürür
  static Stream<List<FixedExpense>> streamMyFixedExpenses(String userId) {
    // Authentication kontrolü
    if (!_isUserAuthenticated()) {
      AppLogger.warning('streamMyFixedExpenses: Kullanıcı authenticate değil');
      return Stream.value(<FixedExpense>[]);
    }
    
    return _firestore
        .collection('fixed_expenses')
        .where('ownerId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(AppConfig.streamLimit)
        .snapshots(includeMetadataChanges: false) // Sadece gerçek değişiklikler için
        .handleError((error) {
      final errorString = error.toString().toLowerCase();
      // Permission hatası durumunda token'ı yenilemeyi dene (async olmadan)
      if (errorString.contains('permission') || errorString.contains('permission-denied')) {
        AppLogger.warning('Firestore permission hatası - token yenileniyor...');
        _refreshAuthToken(); // Fire and forget
      }
      AppLogger.error('Firestore streamMyFixedExpenses hatası', error);
      // Tüm hataları fırlat - StreamBuilder'ın hasError ile yakalayabilmesi için
      throw error;
    })
        .map((snapshot) {
      try {
        final expenses = <FixedExpense>[];
        for (var doc in snapshot.docs) {
          try {
            final data = doc.data();
            expenses.add(FixedExpense.fromJson(data, doc.id));
          } catch (e) {
            AppLogger.warning('streamMyFixedExpenses parse hatası (doc ${doc.id}): $e');
          }
        }
        return expenses;
      } catch (e) {
        AppLogger.error('Firestore streamMyFixedExpenses parse hatası', e);
        return <FixedExpense>[];
      }
    });
  }

  /// Yeni bir sabit gider ekler
  static Future<void> addFixedExpense(FixedExpense expense) async {
    _ensureAuthenticated();
    try {
      await _firestore.collection('fixed_expenses').add({
        ...expense.toJson(),
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

  /// Sabit gideri günceller
  static Future<void> updateFixedExpense(FixedExpense expense) async {
    try {
      if (expense.id == null) {
        throw Exception('Güncellenecek sabit gider ID\'si bulunamadı.');
      }
      await _firestore.collection('fixed_expenses').doc(expense.id).update({
        ...expense.toJson(),
      }).timeout(
        Duration(seconds: AppConfig.firestoreTimeoutSeconds),
        onTimeout: () {
          throw Exception('Firestore güncelleme zaman aşımı. İnternet bağlantınızı kontrol edin.');
        },
      );
    } on FirebaseException catch (e) {
      throw Exception('Firestore hatası: ${e.code} - ${e.message}');
    } catch (e) {
      throw Exception('Firestore hatası: ${e.toString()}');
    }
  }

  /// Sabit gideri siler (sadece sahibi silebilir)
  static Future<void> deleteFixedExpense(String expenseId, String userId) async {
    try {
      final expenseRef = _firestore.collection('fixed_expenses').doc(expenseId);
      final expenseDoc = await expenseRef.get().timeout(
        Duration(seconds: AppConfig.firestoreTimeoutSeconds),
        onTimeout: () {
          throw Exception('Firestore bağlantı zaman aşımı. İnternet bağlantınızı kontrol edin.');
        },
      );

      if (!expenseDoc.exists) {
        throw Exception('Sabit gider bulunamadı.');
      }

      final expenseData = expenseDoc.data();
      final ownerId = expenseData?['ownerId'] as String?;

      if (ownerId != userId) {
        throw Exception('Bu sabit gideri silme yetkiniz yok. Sadece kendi kayıtlarınızı silebilirsiniz.');
      }

      await expenseRef.delete().timeout(
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

  /// Tüm sabit giderleri getirir (Google Sheets için)
  static Future<List<FixedExpense>> getAllFixedExpenses() async {
    try {
      final snapshot = await _firestore.collection('fixed_expenses').get().timeout(
        Duration(seconds: AppConfig.firestoreTimeoutSeconds),
        onTimeout: () {
          throw Exception('Firestore sorgu zaman aşımı. İnternet bağlantınızı kontrol edin.');
        },
      );
      
      final expenses = <FixedExpense>[];
      for (var doc in snapshot.docs) {
        try {
          final data = doc.data();
          expenses.add(FixedExpense.fromJson(data, doc.id));
        } catch (e) {
          AppLogger.warning('getAllFixedExpenses parse hatası (doc ${doc.id}): $e');
        }
      }
      return expenses;
    } on FirebaseException catch (e) {
      throw Exception('Firestore hatası: ${e.code} - ${e.message}');
    } catch (e) {
      throw Exception('Firestore hatası: ${e.toString()}');
    }
  }

}

