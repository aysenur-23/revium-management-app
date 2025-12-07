/**
 * Ayarlar ekranı
 * Tema ayarları ve logout
 */

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/local_storage_service.dart';
import '../services/upload_service.dart';

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ayarlar'),
        elevation: 1,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Tema Bölümü
            Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: theme.colorScheme.outline.withValues(alpha: 0.1),
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
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  title: Text(
                    'Karanlık Mod',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  subtitle: Text(
                    'Uygulama temasını değiştir',
                    style: TextStyle(
                      fontSize: 14,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  secondary: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _isDarkMode ? Icons.dark_mode : Icons.light_mode,
                      color: theme.colorScheme.primary,
                      size: 24,
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
                  color: theme.colorScheme.outline.withValues(alpha: 0.1),
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
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer
                              .withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          Icons.lock_reset,
                          color: theme.colorScheme.primary,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Şifre Değiştir',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                fontSize: 17,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Hesap şifrenizi güncelleyin',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.6),
                                fontSize: 14,
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
                  color: theme.colorScheme.outline.withValues(alpha: 0.1),
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
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(
                            Icons.table_chart,
                            color: Colors.green,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Google Sheets',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 17,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Tüm kayıtlar otomatik olarak Google Sheets\'e eklenir',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.6),
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Her dosya yüklendiğinde kayıtlarınız "Harcama Takibi" adlı Google Sheets dosyasına otomatik olarak eklenir. Bu dosyayı Google Drive\'ınızda bulabilirsiniz.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
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
                            // Google Sheets linkini al
                            final sheetsUrl = await UploadService.getGoogleSheetsUrl();
                            
                            if (!mounted) return;
                            Navigator.of(context).pop(); // Loading dialog'u kapat

                            if (sheetsUrl != null) {
                              // Google Sheets'i aç
                              final uri = Uri.parse(sheetsUrl);
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(uri, mode: LaunchMode.externalApplication);
                              } else {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Google Sheets açılamadı'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              }
                            } else {
                              // Sheets dosyası henüz oluşturulmamış, mevcut tüm entry'lerle direkt oluştur
                              // Loading dialog zaten açık, devam et
                              try {
                                // Firestore'dan kullanıcının entry'lerini çek
                                if (!mounted) return;
                                
                                final currentUser = FirebaseAuth.instance.currentUser;
                                if (currentUser == null) {
                                  Navigator.of(context).pop(); // Loading dialog'u kapat
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Kullanıcı oturumu bulunamadı. Lütfen tekrar giriş yapın.'),
                                        backgroundColor: Colors.red,
                                        duration: Duration(seconds: 4),
                                      ),
                                    );
                                  }
                                  return;
                                }
                                
                                final entriesSnapshot = await FirebaseFirestore.instance
                                    .collection('entries')
                                    .where('ownerId', isEqualTo: currentUser.uid)
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

                                if (!mounted) return;

                                if (entries.isEmpty) {
                                  Navigator.of(context).pop(); // Loading dialog'u kapat
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Henüz kayıt bulunmuyor. İlk kaydı eklediğinizde Google Sheets otomatik olarak oluşturulacak.'),
                                        backgroundColor: Colors.orange,
                                        duration: Duration(seconds: 4),
                                      ),
                                    );
                                  }
                                  return;
                                }

                                // Google Sheets'i oluştur
                                final result = await UploadService.initializeGoogleSheetsWithEntries(entries);

                                if (!mounted) return;
                                Navigator.of(context).pop(); // Loading dialog'u kapat

                                if (result != null && result['url'] != null) {
                                  // Google Sheets'i direkt aç
                                  final uri = Uri.parse(result['url'] as String);
                                  if (await canLaunchUrl(uri)) {
                                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                                  } else {
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Google Sheets açılamadı'),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                    }
                                  }
                                } else {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Google Sheets oluşturulamadı. Lütfen tekrar deneyin.'),
                                        backgroundColor: Colors.red,
                                        duration: Duration(seconds: 4),
                                      ),
                                    );
                                  }
                                }
                              } catch (e) {
                                if (!mounted) return;
                                Navigator.of(context).pop(); // Loading dialog'u kapat
                                
                                String errorMessage = 'Google Sheets oluşturulurken hata oluştu';
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
                                      action: SnackBarAction(
                                        label: 'Tekrar Dene',
                                        textColor: Colors.white,
                                        onPressed: () {
                                          // Butona tıklandığında tekrar deneme işlemi yapılabilir
                                        },
                                      ),
                                    ),
                                  );
                                }
                              }
                            }
                          } catch (e) {
                            if (!mounted) return;
                            Navigator.of(context).pop(); // Loading dialog'u kapat
                            
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Hata: ${e.toString()}'),
                                  backgroundColor: Colors.red,
                                  duration: const Duration(seconds: 4),
                                ),
                              );
                            }
                          }
                        },
                        icon: const Icon(Icons.table_chart, size: 20),
                        label: const Text(
                          'Google Sheets\'i Aç',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
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
            // Çıkış Bölümü
            Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: theme.colorScheme.error.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _logout,
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.error.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            Icons.logout,
                            color: theme.colorScheme.error,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Çıkış Yap',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 17,
                                  color: theme.colorScheme.error,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Hesabınızdan çıkış yapın',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.6),
                                  fontSize: 14,
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
    );
  }
}

