/**
 * Şifre Sıfırlama Ekranı
 * Deep link'ten gelen action code ile şifre sıfırlama
 */

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/local_storage_service.dart';
import '../services/firestore_service.dart';
import '../utils/app_logger.dart';

class PasswordResetScreen extends StatefulWidget {
  final String actionCode;

  const PasswordResetScreen({
    super.key,
    required this.actionCode,
  });

  @override
  State<PasswordResetScreen> createState() => _PasswordResetScreenState();
}

class _PasswordResetScreenState extends State<PasswordResetScreen> {
  final _formKey = GlobalKey<FormState>();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;
  String? _email;

  @override
  void initState() {
    super.initState();
    _verifyActionCode();
  }

  @override
  void dispose() {
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _verifyActionCode() async {
    try {
      setState(() {
        _isLoading = true;
      });

      AppLogger.info('Action code doğrulanıyor: ${widget.actionCode}');

      // Action code'u doğrula - bu email'i döndürür
      final email = await FirebaseAuth.instance.verifyPasswordResetCode(widget.actionCode);
      
      AppLogger.info('Action code doğrulandı, email: $email');
      
      setState(() {
        _email = email;
        _isLoading = false;
      });
    } catch (e) {
      AppLogger.error('Action code doğrulama hatası', e);
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Şifre sıfırlama linki geçersiz veya süresi dolmuş.'),
            backgroundColor: Colors.red,
          ),
        );
        // Login ekranına geri dön
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            Navigator.of(context, rootNavigator: true)
                .pushNamedAndRemoveUntil('/login', (route) => false);
          }
        });
      }
    }
  }

  Future<void> _handlePasswordReset() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    try {
      setState(() {
        _isLoading = true;
      });

      AppLogger.info('Şifre sıfırlama başlatılıyor (actionCode: ${widget.actionCode})');

      // Action code ile şifreyi değiştir
      await FirebaseAuth.instance.confirmPasswordReset(
        code: widget.actionCode,
        newPassword: _newPasswordController.text,
      );

      AppLogger.success('Şifre başarıyla sıfırlandı');

      // Şifre sıfırlama flag'ini temizle
      await LocalStorageService.setPasswordResetPending(false);

      // Email'i action code'dan çıkar (verifyPasswordResetCode'dan sonra)
      // Firebase Auth'un currentUser'ı null olacak, email'i başka yoldan almalıyız
      // Şifre sıfırlandı, şimdi yeni şifreyle giriş yap
      // Email'i verifyPasswordResetCode'dan aldık
      if (_email != null && mounted) {
        await _loginWithNewPassword(_email!);
      } else {
        // Email yoksa kullanıcıdan iste
        if (mounted) {
          _showEmailInputDialog();
        }
      }
    } catch (e) {
      AppLogger.error('Şifre sıfırlama hatası', e);
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        String errorMessage = 'Şifre sıfırlanamadı';
        if (e is FirebaseAuthException) {
          switch (e.code) {
            case 'expired-action-code':
              errorMessage = 'Şifre sıfırlama linki süresi dolmuş. Lütfen yeni bir link isteyin.';
              break;
            case 'invalid-action-code':
              errorMessage = 'Şifre sıfırlama linki geçersiz. Lütfen yeni bir link isteyin.';
              break;
            case 'weak-password':
              errorMessage = 'Şifre çok zayıf. Lütfen daha güçlü bir şifre seçin.';
              break;
            default:
              errorMessage = 'Şifre sıfırlama hatası: ${e.message ?? e.code}';
          }
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showEmailInputDialog() {
    final emailController = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('E-posta Adresi'),
        content: TextField(
          controller: emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'E-posta',
            hintText: 'ornek@reviumtech.com',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context, rootNavigator: true)
                  .pushNamedAndRemoveUntil('/login', (route) => false);
            },
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () {
              final email = emailController.text.trim();
              if (email.isNotEmpty) {
                Navigator.of(context).pop();
                _loginWithNewPassword(email);
              }
            },
            child: const Text('Giriş Yap'),
          ),
        ],
      ),
    );
  }

  Future<void> _loginWithNewPassword(String email) async {
    try {
      setState(() {
        _isLoading = true;
      });

      AppLogger.info('Yeni şifreyle giriş yapılıyor (email: $email)');

      // Yeni şifreyle giriş yap
      final userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: _newPasswordController.text,
      );

      final user = userCredential.user;
      if (user != null) {
        // Firestore'dan kullanıcı bilgilerini al
        final userDoc = await FirestoreService.getUser(user.uid);
        final fullName = userDoc?['fullName'] as String? ?? user.displayName ?? 'Kullanıcı';
        
        // Lokal olarak kaydet
        await LocalStorageService.saveUser(user.uid, fullName);
        
        // Şifre sıfırlama flag'ini temizle
        await LocalStorageService.setPasswordResetPending(false);
        
        AppLogger.success('Başarılı giriş - şifre sıfırlama tamamlandı');

        if (mounted) {
          // Home ekranına yönlendir
          Navigator.of(context, rootNavigator: true)
              .pushNamedAndRemoveUntil('/home', (route) => false);
        }
      }
    } catch (e) {
      AppLogger.error('Yeni şifreyle giriş hatası', e);
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Giriş hatası: ${e.toString()}'),
            backgroundColor: Colors.red,
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
        title: const Text('Şifre Sıfırlama'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 32),
                    Icon(
                      Icons.lock_reset,
                      size: 64,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Yeni Şifre Belirleyin',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Yeni şifrenizi girin. En az 6 karakter olmalıdır.',
                      style: theme.textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    // Yeni Şifre
                    TextFormField(
                      controller: _newPasswordController,
                      obscureText: _obscureNewPassword,
                      decoration: InputDecoration(
                        labelText: 'Yeni Şifre',
                        prefixIcon: const Icon(Icons.lock),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureNewPassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscureNewPassword = !_obscureNewPassword;
                            });
                          },
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
                    // Şifre Tekrar
                    TextFormField(
                      controller: _confirmPasswordController,
                      obscureText: _obscureConfirmPassword,
                      decoration: InputDecoration(
                        labelText: 'Yeni Şifre (Tekrar)',
                        prefixIcon: const Icon(Icons.lock),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureConfirmPassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscureConfirmPassword = !_obscureConfirmPassword;
                            });
                          },
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Lütfen şifrenizi tekrar giriniz';
                        }
                        if (value != _newPasswordController.text) {
                          return 'Şifreler eşleşmiyor';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _handlePasswordReset,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('Şifreyi Değiştir'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

