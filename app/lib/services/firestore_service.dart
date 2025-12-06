/**
 * Firestore servisi
 * Firestore veritabanı işlemlerini yönetir
 */

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import '../models/user_profile.dart';
import '../models/expense_entry.dart';

class FirestoreService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Kullanıcıyı Firestore'a kaydeder (varsa güncellemez, sadece oluşturur)
  static Future<void> createUserIfNotExists(
      String userId, String fullName) async {
    try {
      final userRef = _firestore.collection('users').doc(userId);
      
      // Timeout ile get işlemi
      final userDoc = await userRef.get().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Firestore bağlantı zaman aşımı. İnternet bağlantınızı kontrol edin.');
        },
      );

      if (!userDoc.exists) {
        await userRef.set({
          'fullName': fullName,
          'createdAt': FieldValue.serverTimestamp(),
        }).timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            throw Exception('Firestore kayıt zaman aşımı. İnternet bağlantınızı kontrol edin.');
          },
        );
      }
    } on FirebaseException catch (e) {
      // FirebaseException'ı düzgün handle et
      debugPrint('Firestore FirebaseException: ${e.code} - ${e.message}');
      throw Exception('Firestore hatası: ${e.code} - ${e.message}');
    } catch (e) {
      // Diğer hatalar için
      debugPrint('Firestore genel hata: $e');
      throw Exception('Firestore hatası: ${e.toString()}');
    }
  }

  /// Kullanıcının kendi kayıtlarını stream olarak döndürür
  static Stream<List<ExpenseEntry>> streamMyEntries(String userId) {
    return _firestore
        .collection('entries')
        .where('ownerId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .handleError((error) {
      // Hata durumunda boş liste döndür ve hatayı logla
      debugPrint('Firestore streamMyEntries hatası: $error');
      return <ExpenseEntry>[];
    })
        .map((snapshot) {
      try {
        return snapshot.docs
            .map((doc) => ExpenseEntry.fromJson(doc.data() as Map<String, dynamic>, doc.id))
            .toList();
      } catch (e) {
        debugPrint('Firestore streamMyEntries parse hatası: $e');
        return <ExpenseEntry>[];
      }
    });
  }

  /// Tüm kayıtları stream olarak döndürür
  static Stream<List<ExpenseEntry>> streamAllEntries() {
    return _firestore
        .collection('entries')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .handleError((error) {
      // Hata durumunda boş liste döndür ve hatayı logla
      debugPrint('Firestore streamAllEntries hatası: $error');
      return <ExpenseEntry>[];
    })
        .map((snapshot) {
      try {
        return snapshot.docs
            .map((doc) => ExpenseEntry.fromJson(doc.data() as Map<String, dynamic>, doc.id))
            .toList();
      } catch (e) {
        debugPrint('Firestore streamAllEntries parse hatası: $e');
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
      });
    } on FirebaseException catch (e) {
      throw Exception('Firestore hatası: ${e.code} - ${e.message}');
    } catch (e) {
      throw Exception('Firestore hatası: ${e.toString()}');
    }
  }

  /// Tüm farklı ownerName değerlerini getirir (filtreleme için)
  static Future<List<String>> getAllOwnerNames() async {
    final snapshot = await _firestore.collection('entries').get();
    final ownerNames = <String>{};

    for (var doc in snapshot.docs) {
      final data = doc.data();
      final ownerName = data['ownerName'] as String?;
      if (ownerName != null && ownerName.isNotEmpty) {
        ownerNames.add(ownerName);
      }
    }

    return ownerNames.toList()..sort();
  }

  /// Tüm farklı ownerName değerlerini stream olarak döndürür (realtime güncelleme için)
  static Stream<List<String>> streamAllOwnerNames() {
    return _firestore
        .collection('entries')
        .snapshots()
        .handleError((error) {
      // Hata durumunda boş liste döndür ve hatayı logla
      debugPrint('Firestore streamAllOwnerNames hatası: $error');
      return <String>[];
    })
        .map((snapshot) {
      try {
        final ownerNames = <String>{};

        for (var doc in snapshot.docs) {
          final data = doc.data();
          final ownerName = data['ownerName'] as String?;
          if (ownerName != null && ownerName.isNotEmpty) {
            ownerNames.add(ownerName);
          }
        }

        return ownerNames.toList()..sort();
      } catch (e) {
        debugPrint('Firestore streamAllOwnerNames parse hatası: $e');
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

      if (userId != null) {
        query = query.where('ownerId', isEqualTo: userId);
      }

      final snapshot = await query.get();
      final entries = snapshot.docs
          .map((doc) => ExpenseEntry.fromJson(doc.data() as Map<String, dynamic>, doc.id))
          .toList();

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

