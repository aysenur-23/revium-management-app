/// Ayarlar ekranı
/// Şifre değiştirme ve logout
library;

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../services/local_storage_service.dart';
import '../services/drive_token_service.dart';
import '../services/upload_service.dart' show getBackendBaseUrl;

/// Şifre değiştirme dialog'u - ayrı widget olarak context sorunlarını önler
class _ChangePasswordDialog extends StatefulWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController currentPasswordController;
  final TextEditingController newPasswordController;
  final TextEditingController confirmPasswordController;

  const _ChangePasswordDialog({
    required this.formKey,
    required this.currentPasswordController,
    required this.newPasswordController,
    required this.confirmPasswordController,
  });

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  bool _obscureCurrentPassword = true;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;

  Future<void> _submit() async {
    if (!widget.formKey.currentState!.validate()) return;
    
    setState(() => _isLoading = true);
    
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('Kullanıcı bulunamadı');
      }

      // Mevcut şifreyi doğrula
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: widget.currentPasswordController.text,
      );
      await user.reauthenticateWithCredential(credential);

      // Şifreyi güncelle
      await user.updatePassword(widget.newPasswordController.text);

      // Başarılı - dialog'u kapat ve true döndür
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on FirebaseAuthException catch (e) {
      String errorMessage = 'Şifre değiştirilemedi';
      switch (e.code) {
        case 'wrong-password':
          errorMessage = 'Mevcut şifre hatalı. Lütfen tekrar deneyin.';
          break;
        case 'weak-password':
          errorMessage = 'Yeni şifre çok zayıf. Lütfen daha güçlü bir şifre seçin.';
          break;
        case 'requires-recent-login':
          errorMessage = 'Güvenlik nedeniyle lütfen tekrar giriş yapın.';
          break;
        default:
          errorMessage = 'Şifre değiştirme hatası: ${e.message ?? e.code}';
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hata: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      title: const Text(
        'Şifre Değiştir',
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
      ),
      content: SingleChildScrollView(
        child: Form(
          key: widget.formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: widget.currentPasswordController,
                obscureText: _obscureCurrentPassword,
                decoration: InputDecoration(
                  labelText: 'Mevcut Şifre',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureCurrentPassword ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _obscureCurrentPassword = !_obscureCurrentPassword),
                  ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                  filled: true,
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Lütfen mevcut şifrenizi giriniz';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: widget.newPasswordController,
                obscureText: _obscureNewPassword,
                decoration: InputDecoration(
                  labelText: 'Yeni Şifre',
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureNewPassword ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _obscureNewPassword = !_obscureNewPassword),
                  ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                  filled: true,
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Lütfen yeni şifrenizi giriniz';
                  if (value.length < 6) return 'Şifre en az 6 karakter olmalıdır';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: widget.confirmPasswordController,
                obscureText: _obscureConfirmPassword,
                decoration: InputDecoration(
                  labelText: 'Yeni Şifre (Tekrar)',
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureConfirmPassword ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                  ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                  filled: true,
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Lütfen yeni şifrenizi tekrar giriniz';
                  if (value != widget.newPasswordController.text) return 'Şifreler eşleşmiyor';
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(false),
          child: const Text('İptal'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _submit,
          child: _isLoading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Değiştir'),
        ),
      ],
    );
  }
}

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
  bool _backendChecking = false;

  @override
  void initState() {
    super.initState();
  }


  Future<void> _checkBackendExcelStatus() async {
    if (_backendChecking || !mounted) return;
    setState(() => _backendChecking = true);
    try {
      final baseUrl = await getBackendBaseUrl();
      final uri = Uri.parse(baseUrl.endsWith('/') ? '${baseUrl}health' : '$baseUrl/health');
      final response = await http.get(uri).timeout(const Duration(seconds: 12));
      final json = response.statusCode == 200 ? jsonDecode(response.body) as Map<String, dynamic> : null;
      final excelReady = json?['excelReady'] as bool? ?? false;
      final serviceAccountEmail = json?['serviceAccountEmail'] as String? ?? '';
      final driveAuthType = json?['driveAuthType'] as String? ?? '';
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              Icon(excelReady ? Icons.check_circle : Icons.warning_amber_rounded,
                  color: excelReady ? Colors.green : Colors.orange, size: 28),
              const SizedBox(width: 12),
              const Text('Backend / Excel durumu'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(excelReady
                    ? 'Backend Excel yazımına hazır.'
                    : 'Backend Excel yazımına hazır değil (Drive/Sheets kimliği eksik).'),
                if (serviceAccountEmail.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('Hesap: $serviceAccountEmail', style: const TextStyle(fontSize: 12)),
                ],
                if (driveAuthType.isNotEmpty)
                  Text('Tür: $driveAuthType', style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tamam')),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Backend kontrolü başarısız: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _backendChecking = false);
    }
  }

  Future<void> _changePassword() async {
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final scaffoldContext = context; // Ana widget context'ini sakla
    
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _ChangePasswordDialog(
        formKey: formKey,
        currentPasswordController: currentPasswordController,
        newPasswordController: newPasswordController,
        confirmPasswordController: confirmPasswordController,
      ),
    );
    
    // Dialog sonucu: true = başarılı, false/null = iptal veya hata
    if (result == true && mounted) {
      // Başarı mesajı göster
      ScaffoldMessenger.of(scaffoldContext).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Şifreniz başarıyla değiştirildi. Tekrar giriş yapmanız gerekiyor.',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
      
      // Çıkış yap ve giriş ekranına yönlendir
      await FirebaseAuth.instance.signOut();
      await LocalStorageService.clearUser();
      
      if (mounted) {
        Navigator.of(scaffoldContext, rootNavigator: true)
            .pushNamedAndRemoveUntil('/login', (route) => false);
      }
    }
    
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
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                  const SizedBox(height: 12),
                  // Backend / Excel durumu
                  ListTile(
                    leading: Icon(Icons.settings_ethernet_rounded, color: theme.colorScheme.primary),
                    title: const Text('Backend (Excel) durumunu kontrol et'),
                    subtitle: Text(
                      _backendChecking ? 'Kontrol ediliyor...' : 'Sunucunun Excel yazımına hazır olup olmadığını görün',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                    ),
                    trailing: _backendChecking ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.chevron_right),
                    onTap: _backendChecking ? null : _checkBackendExcelStatus,
                  ),
                  const SizedBox(height: 20),
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
    );
  }
}
