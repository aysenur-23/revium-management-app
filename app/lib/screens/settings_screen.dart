/**
 * Ayarlar ekranı
 * Tema ayarları ve logout
 */

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import '../services/local_storage_service.dart';
import '../services/upload_service.dart';
import '../services/file_opener/file_open_service.dart';
import '../services/backend_test_service.dart';
import '../models/app_file_reference.dart';
import '../utils/app_logger.dart';

class SettingsScreen extends StatefulWidget {
  final Function(bool)? onThemeChanged;

  const SettingsScreen({
    super.key,
    this.onThemeChanged,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isDarkMode = false;

  @override
  void initState() {
    super.initState();
    _loadThemePreference();
  }

  Future<void> _loadThemePreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isDarkMode = prefs.getBool('dark_mode') ?? false;
    });
  }

  Future<void> _changePassword() async {
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool obscureCurrentPassword = true;
    bool obscureNewPassword = true;
    bool obscureConfirmPassword = true;
    bool isLoading = false;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Şifre Değiştir',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 20,
            ),
          ),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Mevcut Şifre
                  TextFormField(
                    controller: currentPasswordController,
                    obscureText: obscureCurrentPassword,
                    decoration: InputDecoration(
                      labelText: 'Mevcut Şifre',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscureCurrentPassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        onPressed: () {
                          setDialogState(() {
                            obscureCurrentPassword = !obscureCurrentPassword;
                          });
                        },
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      filled: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 18,
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Lütfen mevcut şifrenizi giriniz';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  // Yeni Şifre
                  TextFormField(
                    controller: newPasswordController,
                    obscureText: obscureNewPassword,
                    decoration: InputDecoration(
                      labelText: 'Yeni Şifre',
                      prefixIcon: const Icon(Icons.lock),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscureNewPassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        onPressed: () {
                          setDialogState(() {
                            obscureNewPassword = !obscureNewPassword;
                          });
                        },
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      filled: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 18,
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Lütfen yeni şifrenizi giriniz';
                      }
                      if (value.length < 6) {
                        return 'Şifre en az 6 karakter olmalıdır';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  // Yeni Şifre Tekrar
                  TextFormField(
                    controller: confirmPasswordController,
                    obscureText: obscureConfirmPassword,
                    decoration: InputDecoration(
                      labelText: 'Yeni Şifre (Tekrar)',
                      prefixIcon: const Icon(Icons.lock),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscureConfirmPassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        onPressed: () {
                          setDialogState(() {
                            obscureConfirmPassword = !obscureConfirmPassword;
                          });
                        },
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      filled: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 18,
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Lütfen yeni şifrenizi tekrar giriniz';
                      }
                      if (value != newPasswordController.text) {
                        return 'Şifreler eşleşmiyor';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isLoading
                  ? null
                  : () => Navigator.of(context).pop(),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: isLoading
                  ? null
                  : () async {
                      if (formKey.currentState!.validate()) {
                        setDialogState(() {
                          isLoading = true;
                        });

                        try {
                          final user = FirebaseAuth.instance.currentUser;
                          if (user == null) {
                            throw Exception('Kullanıcı bulunamadı');
                          }

                          // Mevcut şifreyi doğrula
                          final credential = EmailAuthProvider.credential(
                            email: user.email!,
                            password: currentPasswordController.text,
                          );
                          await user.reauthenticateWithCredential(credential);

                          // Şifreyi güncelle
                          await user.updatePassword(newPasswordController.text);

                          // Şifre değiştirme başarılı - kullanıcıyı çıkış yaptır ve giriş ekranına yönlendir
                          if (context.mounted) {
                            Navigator.of(context).pop();
                            
                            // Başarı mesajı göster
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Row(
                                  children: [
                                    const Icon(Icons.check_circle,
                                        color: Colors.white),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        'Şifreniz başarıyla değiştirildi. Güvenlik nedeniyle tekrar giriş yapmanız gerekiyor.',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ],
                                ),
                                backgroundColor: Colors.green,
                                duration: const Duration(seconds: 4),
                              ),
                            );
                            
                            // Kısa bir gecikme sonrası çıkış yap ve giriş ekranına yönlendir
                            await Future.delayed(const Duration(milliseconds: 500));
                            
                            if (context.mounted) {
                              // Firebase Auth'tan çıkış yap
                              await FirebaseAuth.instance.signOut();
                              
                              // Lokal depolamayı temizle
                              await LocalStorageService.clearUser();
                              
                              // Giriş ekranına yönlendir
                              if (context.mounted) {
                                Navigator.of(context, rootNavigator: true)
                                    .pushNamedAndRemoveUntil('/login', (route) => false);
                              }
                            }
                          }
                        } on FirebaseAuthException catch (e) {
                          String errorMessage = 'Şifre değiştirilemedi';
                          switch (e.code) {
                            case 'wrong-password':
                              errorMessage =
                                  'Mevcut şifre hatalı. Lütfen tekrar deneyin.';
                              break;
                            case 'weak-password':
                              errorMessage =
                                  'Yeni şifre çok zayıf. Lütfen daha güçlü bir şifre seçin.';
                              break;
                            case 'requires-recent-login':
                              errorMessage =
                                  'Güvenlik nedeniyle lütfen tekrar giriş yapın.';
                              break;
                            default:
                              errorMessage =
                                  'Şifre değiştirme hatası: ${e.message ?? e.code}';
                          }

                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(errorMessage),
                                backgroundColor: Colors.red,
                                duration: const Duration(seconds: 4),
                              ),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Bir hata oluştu: ${e.toString()}'),
                                backgroundColor: Colors.red,
                                duration: const Duration(seconds: 4),
                              ),
                            );
                          }
                        } finally {
                          if (context.mounted) {
                            setDialogState(() {
                              isLoading = false;
                            });
                          }
                        }
                      }
                    },
              child: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Değiştir'),
            ),
          ],
        ),
      ),
    );

    currentPasswordController.dispose();
    newPasswordController.dispose();
    confirmPasswordController.dispose();
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Çıkış Yap'),
        content: const Text('Çıkış yapmak istediğinize emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Çıkış Yap'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        // Firebase Auth'tan çıkış yap
        await FirebaseAuth.instance.signOut();
        
        // Lokal depolamayı temizle
        await LocalStorageService.clearUser();
        
        // Login ekranına yönlendir
        if (mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil(
            '/login',
            (route) => false,
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Çıkış hatası: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  /// Excel dosyasını Google Drive'dan indirip geçici olarak saklayıp açar (yeni modüler servis)
  Future<void> _openExcelFromDrive(BuildContext context, String fileId, int entryCount) async {
    try {
      AppLogger.info('📥 Excel dosyası açma işlemi başlatıldı');
      AppLogger.debug('File ID: $fileId');
      
      // Loading göster
      if (context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => Center(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    const Text('Excel yükleniyor...'),
                  ],
                ),
              ),
            ),
          ),
        );
      }

      // AppFileReference oluştur (Excel için)
      final fileRef = AppFileReference(
        id: 'excel_$fileId',
        driveFileId: fileId,
        name: 'Harcama Takibi.xlsx',
        mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        createdAt: DateTime.now(),
        uploadedByUserId: '',
      );

      // Yeni modüler servis ile aç
      await FileOpenService.openOrDownloadAndOpen(fileRef);

      // Loading'i kapat
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    } catch (e, stackTrace) {
      AppLogger.error('Excel açma hatası', e, stackTrace);
      // Loading'i kapat
      if (context.mounted) {
        Navigator.of(context).pop();
        
        // Kullanıcıya açıklayıcı hata mesajı göster
        String errorMessage = 'Excel dosyası açılamadı';
        final errorString = e.toString().toLowerCase();
        
        if (errorString.contains('timeout') || errorString.contains('zaman aşımı')) {
          errorMessage = 'Excel dosyası yüklenirken zaman aşımı oluştu. İnternet bağlantınızı kontrol edip tekrar deneyin.';
        } else if (errorString.contains('connection') || errorString.contains('bağlanılamadı')) {
          errorMessage = 'Backend sunucusuna bağlanılamıyor. İnternet bağlantınızı kontrol edin.';
        } else if (errorString.contains('404') || errorString.contains('not found')) {
          errorMessage = 'Excel dosyası bulunamadı. Dosya henüz oluşturulmamış olabilir.';
        } else if (errorString.contains('401') || errorString.contains('403') || errorString.contains('unauthorized')) {
          errorMessage = 'Yetkilendirme hatası. Lütfen tekrar giriş yapın.';
        } else {
          errorMessage = 'Excel açma hatası: ${e.toString().length > 100 ? e.toString().substring(0, 100) + "..." : e.toString()}';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 56,
        automaticallyImplyLeading: true,
        centerTitle: true,
        title: Text(
          'Ayarlar',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        elevation: 0,
        backgroundColor: theme.colorScheme.surface,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Tema Bölümü
                  Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: theme.colorScheme.outline.withValues(alpha: 0.08),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: theme.colorScheme.shadow.withValues(alpha: 0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                          spreadRadius: 0,
                        ),
                      ],
                    ),
                    child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  title: Text(
                    'Karanlık Mod',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  subtitle: Text(
                    'Uygulama temasını değiştir',
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  secondary: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _isDarkMode ? Icons.dark_mode : Icons.light_mode,
                      color: theme.colorScheme.primary,
                      size: 20,
                    ),
                  ),
                  value: _isDarkMode,
                  onChanged: (value) async {
                    setState(() {
                      _isDarkMode = value;
                    });
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('dark_mode', value);
                    widget.onThemeChanged?.call(value);
                  },
                ),
              ),
                  ),
                  const SizedBox(height: 20),
                  // Şifre Değiştir Bölümü
                  Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: theme.colorScheme.outline.withValues(alpha: 0.08),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: theme.colorScheme.shadow.withValues(alpha: 0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                          spreadRadius: 0,
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _changePassword,
                        borderRadius: BorderRadius.circular(20),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.lock_reset,
                            color: theme.colorScheme.primary,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Şifre Değiştir',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Hesap şifrenizi güncelleyin',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
                  ),
                  const SizedBox(height: 20),
                  // Google Sheets Bölümü
                  Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: theme.colorScheme.outline.withValues(alpha: 0.08),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: theme.colorScheme.shadow.withValues(alpha: 0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                          spreadRadius: 0,
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.table_chart_rounded,
                            color: Colors.green,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Excel\'i Görüntüle',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Tüm kayıtlar otomatik olarak Excel dosyasına eklenir',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
            ),
            const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                          'Her dosya yüklendiğinde kayıtlarınız "Harcama Takibi" adlı Excel dosyasına otomatik olarak eklenir. Bu dosyayı Google Drive\'ınızda bulabilirsiniz.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          if (!mounted) return;
                          
                            AppLogger.info('📊 Excel açma işlemi başlatıldı (Ayarlar - Tüm Kayıtlar)');
                          
                          // Loading göster
                          showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (context) => const Center(
                              child: CircularProgressIndicator(),
                            ),
                          );

                          try {
                            // Önce kullanıcı kontrolü
                            final currentUser = FirebaseAuth.instance.currentUser;
                            if (currentUser == null) {
                                AppLogger.warning('Kullanıcı oturumu bulunamadı');
                              Navigator.of(context).pop(); // Loading dialog'u kapat
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                    content: Text('Kullanıcı oturumu bulunamadı. Lütfen tekrar giriş yapın.'),
                                    backgroundColor: Colors.red,
                                      duration: const Duration(seconds: 4),
                                  ),
                                );
                              }
                              return;
                            }
                            
                            // TÜM entry'leri çek (herkesin)
                              AppLogger.info('Firestore\'dan tüm entry\'ler alınıyor...');
                            final entriesSnapshot = await FirebaseFirestore.instance
                                .collection('entries')
                                .orderBy('createdAt', descending: true)
                                .get();

                            if (!mounted) return;

                            final entries = entriesSnapshot.docs.map((doc) {
                              final data = doc.data();
                              return {
                                'createdAt': data['createdAt']?.toDate()?.toIso8601String() ?? DateTime.now().toIso8601String(),
                                'notes': data['notes'] ?? '',
                                'ownerName': data['ownerName'] ?? '',
                                'amount': data['amount'] ?? 0.0,
                                'description': data['description'] ?? '',
                                'fileUrl': data['fileUrl'] ?? '',
                              };
                            }).toList();
                              AppLogger.info('${entries.length} entry bulundu');

                              // TÜM sabit giderleri çek
                              AppLogger.info('Firestore\'dan tüm sabit giderler alınıyor...');
                              final fixedExpensesSnapshot = await FirebaseFirestore.instance
                                  .collection('fixed_expenses')
                                  .orderBy('createdAt', descending: true)
                                  .get();

                            if (!mounted) return;

                              final fixedExpenses = fixedExpensesSnapshot.docs.map((doc) {
                                final data = doc.data();
                                return {
                                  'createdAt': data['createdAt']?.toDate()?.toIso8601String() ?? DateTime.now().toIso8601String(),
                                  'startDate': data['startDate']?.toDate()?.toIso8601String(),
                                  'notes': data['notes'] ?? '',
                                  'ownerName': data['ownerName'] ?? '',
                                  'amount': data['amount'] ?? 0.0,
                                  'description': data['description'] ?? '',
                                  'category': data['category'] ?? '',
                                  'recurrence': data['recurrence'] ?? '',
                                  'isActive': data['isActive'] ?? true,
                                };
                              }).toList();
                              AppLogger.info('${fixedExpenses.length} sabit gider bulundu');

                              if (!mounted) return;

                              if (entries.isEmpty && fixedExpenses.isEmpty) {
                                AppLogger.warning('Entry ve sabit gider bulunamadı, işlem iptal ediliyor');
                              Navigator.of(context).pop(); // Loading dialog'u kapat
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Henüz kayıt bulunmuyor. İlk kaydı eklediğinizde Excel dosyası otomatik olarak oluşturulacak.'),
                                    backgroundColor: Colors.orange,
                                      duration: const Duration(seconds: 4),
                                  ),
                                );
                              }
                              return;
                            }

                              // Tüm entry'ler ve sabit giderlerle Excel'i oluştur/güncelle
                              AppLogger.info('Excel dosyası oluşturuluyor/güncelleniyor (${entries.length} entry, ${fixedExpenses.length} sabit gider)...');
                              final result = await UploadService.initializeGoogleSheetsWithAllData(entries, fixedExpenses);
                              AppLogger.debug('Excel oluşturma sonucu: ${result != null ? "Başarılı" : "Başarısız"}');

                            if (!mounted) return;
                            Navigator.of(context).pop(); // Loading dialog'u kapat

                            if (result != null && result['url'] != null) {
                                // Excel oluşturuldu/güncellendi, URL'i düzelt ve aç
                              final sheetsUrl = result['url'] as String;
                                AppLogger.info('Excel URL alındı: $sheetsUrl');
                                
                                // File ID'yi çıkar
                                String? fileId;
                                if (sheetsUrl.contains('drive.google.com')) {
                                  AppLogger.debug('Google Drive URL tespit edildi, File ID çıkarılıyor...');
                                  // Format 1: /file/d/FILE_ID/view veya /file/d/FILE_ID
                                  final fileIdMatch1 = RegExp(r'/file/d/([a-zA-Z0-9_-]+)').firstMatch(sheetsUrl);
                                  if (fileIdMatch1 != null) {
                                    fileId = fileIdMatch1.group(1);
                                    AppLogger.debug('File ID bulundu (format 1): $fileId');
                                  } else {
                                    // Format 2: id=FILE_ID
                                    final fileIdMatch2 = RegExp(r'[?&]id=([a-zA-Z0-9_-]+)').firstMatch(sheetsUrl);
                                    if (fileIdMatch2 != null) {
                                      fileId = fileIdMatch2.group(1);
                                      AppLogger.debug('File ID bulundu (format 2): $fileId');
                                    }
                                  }
                                }
                                
                                if (fileId != null) {
                                  // Excel dosyasını indirip lokal aç (hesap seçimi olmadan)
                                  await _openExcelFromDrive(context, fileId, entries.length);
                                } else {
                                  AppLogger.warning('File ID bulunamadı, orijinal URL kullanılıyor');
                                  // Fallback: Orijinal URL'i aç
                              final uri = Uri.parse(sheetsUrl);
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(uri, mode: LaunchMode.externalApplication);
                                  }
                                }
                              } else {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Excel dosyası oluşturulamadı. Lütfen tekrar deneyin.'),
                                      backgroundColor: Colors.red,
                                      duration: const Duration(seconds: 4),
                                  ),
                                );
                              }
                            }
                          } catch (e) {
                            if (!mounted) return;
                            Navigator.of(context).pop(); // Loading dialog'u kapat
                            
                              String errorMessage = 'Excel dosyası oluşturulurken hata oluştu';
                            final errorString = e.toString().toLowerCase();
                            
                            if (errorString.contains('permission') || errorString.contains('permission denied')) {
                              errorMessage = 'Firestore izin hatası. Lütfen Firebase Console\'da güvenlik kurallarını kontrol edin.';
                            } else if (errorString.contains('timeout') || errorString.contains('connection') || errorString.contains('network')) {
                              errorMessage = 'Bağlantı zaman aşımı. İnternet bağlantınızı kontrol edip tekrar deneyin.';
                            } else if (errorString.contains('not found') || errorString.contains('404')) {
                              errorMessage = 'Backend servisi bulunamadı. Lütfen daha sonra tekrar deneyin.';
                            } else if (errorString.contains('500') || errorString.contains('internal')) {
                              errorMessage = 'Sunucu hatası. Lütfen daha sonra tekrar deneyin.';
                            } else {
                              errorMessage = 'Hata: ${e.toString()}';
                            }
                            
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(errorMessage),
                                  backgroundColor: Colors.red,
                                  duration: const Duration(seconds: 6),
                                ),
                              );
                            }
                          }
                        },
                        icon: const Icon(Icons.table_chart_rounded, size: 18),
                        label: const Text(
                          'Excel\'i Görüntüle',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          side: BorderSide(
                            color: Colors.green.withValues(alpha: 0.5),
                            width: 1.5,
                          ),
                ),
              ),
            ),
                        ],
                      ),
                    ),
                    ),
                  const SizedBox(height: 20),
                  // Backend Test Bölümü
                  Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: theme.colorScheme.outline.withValues(alpha: 0.08),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: theme.colorScheme.shadow.withValues(alpha: 0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                          spreadRadius: 0,
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: Colors.blue.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.cloud_sync_rounded,
                                  color: Colors.blue,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Backend Test',
                                      style: theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Backend endpoint\'lerini test et',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            height: 44,
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                if (!mounted) return;
                                
                                // Loading göster
                                showDialog(
                                  context: context,
                                  barrierDismissible: false,
                                  builder: (context) => const Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                );

                                try {
                                  AppLogger.info('🔍 Backend endpoint\'leri test ediliyor...');
                                  
                                  // Health check test
                                  final healthCheck = await BackendTestService.testHealthCheck();
                                  
                                  if (!mounted) return;
                                  Navigator.of(context).pop(); // Loading dialog'u kapat
                                  
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          healthCheck 
                                            ? '✅ Backend health check başarılı!' 
                                            : '❌ Backend health check başarısız. Logları kontrol edin.',
                                        ),
                                        backgroundColor: healthCheck ? Colors.green : Colors.red,
                                        duration: const Duration(seconds: 4),
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (!mounted) return;
                                  Navigator.of(context).pop(); // Loading dialog'u kapat
                                  
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Backend test hatası: ${e.toString()}'),
                                        backgroundColor: Colors.red,
                                        duration: const Duration(seconds: 4),
                                      ),
                                    );
                                  }
                                }
                              },
                              icon: const Icon(Icons.cloud_sync_rounded, size: 18),
                              label: const Text(
                                'Health Check Test',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                side: BorderSide(
                                  color: Colors.blue.withValues(alpha: 0.5),
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Çıkış Bölümü
                  Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: theme.colorScheme.error.withValues(alpha: 0.15),
                        width: 1,
                      ),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                  onTap: _logout,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.error.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.logout_rounded,
                            color: theme.colorScheme.error,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Çıkış Yap',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                  color: theme.colorScheme.error,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Hesabınızdan çıkış yapın',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          color: theme.colorScheme.error.withValues(alpha: 0.7),
                        ),
                      ],
                    ),
                  ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}

