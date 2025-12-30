/**
 * Splash / Login ekranı
 * Kullanıcıdan mail ve şifre alır ve Firebase Auth ile giriş yapar
 */

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/local_storage_service.dart';
import '../services/firestore_service.dart';
import '../utils/app_logger.dart';

class SplashLoginScreen extends StatefulWidget {
  const SplashLoginScreen({super.key});

  @override
  State<SplashLoginScreen> createState() => _SplashLoginScreenState();
}

class _SplashLoginScreenState extends State<SplashLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController(); // Kayıt için ad soyad
  bool _isLoading = false;
  bool _isSignUp = false; // Giriş mi kayıt mı
  bool _isNavigating = false; // Navigasyon işlemi devam ediyor mu
  bool _obscurePassword = true; // Şifre görünürlüğü
  bool _hasCheckedUser = false; // Kullanıcı kontrolü yapıldı mı
  final FirebaseAuth _auth = FirebaseAuth.instance;

  @override
  void initState() {
    super.initState();
    // Kullanıcı kontrolü - sadece bir kez yap
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_hasCheckedUser) {
        _checkExistingUser();
      }
    });
  }

  Future<void> _checkExistingUser() async {
    if (_hasCheckedUser) return; // Zaten kontrol edildi
    _hasCheckedUser = true;
    
    try {
      // Firebase'de mevcut kullanıcı var mı kontrol et
      final currentUser = _auth.currentUser;
      
      // Eğer kullanıcı giriş yapmışsa, doğrudan home'a yönlendir
      // Şifre sıfırlama flag'i sadece yeni giriş yapılırken kontrol edilir
      if (currentUser != null && mounted && !_isNavigating) {
        AppLogger.info('Mevcut oturum bulundu - otomatik giriş yapılıyor (email: ${currentUser.email})');
        
        // Şifre sıfırlama flag'ini temizle (kullanıcı zaten giriş yapmış)
        await LocalStorageService.clearPasswordResetPending();
        
        _isNavigating = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            try {
              final navigator = Navigator.of(context, rootNavigator: true);
              if (navigator.canPop() || ModalRoute.of(context)?.settings.name != '/home') {
                navigator.pushNamedAndRemoveUntil('/home', (route) => false);
              }
            } catch (e) {
              AppLogger.error('SplashLoginScreen kullanıcı kontrolü navigasyon hatası', e);
              _isNavigating = false;
              _hasCheckedUser = false;
            }
          }
        });
      } else {
        AppLogger.info('Oturum bulunamadı - giriş ekranı gösteriliyor');
      }
    } catch (e) {
      AppLogger.error('SplashLoginScreen kullanıcı kontrolü hatası', e);
      _hasCheckedUser = false;
    }
  }

  Future<void> _handleForgotPassword() async {
    final email = _emailController.text.trim();
    
    if (email.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Lütfen e-posta adresinizi giriniz'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    // E-posta formatı kontrolü
    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Lütfen geçerli bir e-posta adresi giriniz'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    try {
      setState(() {
        _isLoading = true;
      });

      // E-posta gönder - Firebase standart şifre sıfırlama akışı
      // Kullanıcı e-postadaki linke tıklayıp web'de şifresini değiştirecek
      await _auth.sendPasswordResetEmail(email: email);
      AppLogger.info('Şifre sıfırlama e-postası gönderildi (email: $email)');
      
      // Şifre sıfırlama flag'ini ayarla (otomatik girişi engellemek için) - ÖNCE flag'i ayarla
      await LocalStorageService.setPasswordResetPending(true);
      AppLogger.info('Şifre sıfırlama flag\'i ayarlandı - otomatik giriş engellendi');
      
      // Şifre sıfırlama sonrası TÜM oturumları kapat (güvenlik için)
      // Kullanıcı yeni şifreyle giriş yapmalı
      try {
        // Mevcut oturumu kapat
        final currentUser = _auth.currentUser;
        if (currentUser != null) {
          await _auth.signOut();
          // Firebase Auth'un oturumunu tamamen temizlemesi için bekleme
          await Future.delayed(const Duration(milliseconds: 500));
          AppLogger.info('Şifre sıfırlama sonrası oturum kapatıldı');
        }
        
        // Lokal depodan da kullanıcı bilgilerini temizle
        try {
          await LocalStorageService.clearUser();
          AppLogger.info('Lokal kullanıcı bilgileri temizlendi');
        } catch (e) {
          AppLogger.warning('Lokal temizleme hatası (önemli değil): $e');
        }
      } catch (e) {
        AppLogger.warning('Şifre sıfırlama sonrası oturum kapatma hatası (önemli değil): $e');
      }

      if (mounted) {
        // Başarı mesajı göster
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Şifre sıfırlama e-postası gönderildi. Lütfen e-posta kutunuzu kontrol edin.',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Tamam',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
        
        // Modern ve şık başarı dialog'u
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Theme.of(context).colorScheme.surface,
                    Theme.of(context).colorScheme.surfaceContainerHighest,
                  ],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Başarı ikonu
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          Colors.green[400]!,
                          Colors.green[600]!,
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.green.withValues(alpha: 0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.check_circle_rounded,
                      color: Colors.white,
                      size: 48,
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Başlık
                  Text(
                    'E-posta Gönderildi!',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 22,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  // Açıklama
                  Text(
                    'Şifre sıfırlama bağlantısı e-posta adresinize gönderildi.\n\nLütfen e-postanızdaki linke tıklayarak şifrenizi değiştirin, ardından uygulamaya yeni şifrenizle giriş yapın.',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  // E-posta adresi
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.email_rounded,
                          color: Theme.of(context).colorScheme.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            email,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.primary,
                              fontSize: 14,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Bilgi kutusu
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue[50]?.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.blue[200]!.withValues(alpha: 0.5),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          color: Colors.blue[700],
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'E-postayı bulamazsanız spam klasörünü kontrol edin. E-posta gelmezse birkaç dakika bekleyip tekrar deneyin.\n\n⚠️ ÖNEMLİ: Şifre sıfırlama linkine tıklayıp yeni şifrenizi oluşturduktan sonra, lütfen yeni oluşturduğunuz şifreyi kullanarak giriş yapın. Eski şifreniz artık geçersizdir.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.blue[900],
                              height: 1.4,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Tamam butonu
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Theme.of(context).colorScheme.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 2,
                      ),
                      child: const Text(
                        'Tamam',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      String errorMessage = 'Şifre sıfırlama e-postası gönderilemedi';
      
      switch (e.code) {
        case 'user-not-found':
          errorMessage = 'Bu e-posta adresi ile kayıtlı kullanıcı bulunamadı. Lütfen e-posta adresinizi kontrol edin.';
          break;
        case 'invalid-email':
          errorMessage = 'Geçersiz e-posta adresi. Lütfen geçerli bir e-posta adresi giriniz.';
          break;
        case 'too-many-requests':
          errorMessage = 'Çok fazla istek yapıldı. Lütfen birkaç dakika bekleyip tekrar deneyin.';
          break;
        case 'network-request-failed':
          errorMessage = 'İnternet bağlantısı yok. Lütfen internet bağlantınızı kontrol edin.';
          break;
        default:
          errorMessage = 'Şifre sıfırlama hatası: ${e.message ?? e.code}';
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Bir hata oluştu: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text.trim();

      UserCredential userCredential;
      
      if (_isSignUp) {
        // Kayıt işlemi
        final fullName = _nameController.text.trim();
        if (fullName.isEmpty || fullName.length < 3) {
          throw Exception('Ad soyad en az 3 karakter olmalıdır');
        }

        // Şifre güç kontrolü
        if (password.length < 6) {
          throw Exception('Şifre en az 6 karakter olmalıdır');
        }

        // Firebase Auth ile kullanıcı oluştur
        userCredential = await _auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );

        // Kullanıcı objesini kontrol et
        final user = userCredential.user;
        if (user == null) {
          throw Exception('Kullanıcı oluşturulamadı. Lütfen tekrar deneyin.');
        }

        // Kullanıcı profilini güncelle (display name) - hata olursa devam et
        try {
          await user.updateDisplayName(fullName);
          await user.reload();
        } catch (e) {
          // Display name güncellemesi başarısız olsa bile devam et
          AppLogger.error('Display name güncellenemedi', e);
        }

        // Firestore'da kullanıcıyı oluştur - retry mekanizması ile
        bool firestoreSuccess = false;
        for (int i = 0; i < 3; i++) {
          try {
            await FirestoreService.createUserIfNotExists(
              user.uid,
              fullName,
            );
            firestoreSuccess = true;
            break;
          } catch (e) {
            AppLogger.error('Firestore kullanıcı oluşturma hatası (deneme ${i + 1}/3)', e);
            if (i < 2) {
              await Future.delayed(Duration(milliseconds: 500 * (i + 1)));
            }
          }
        }

        if (!firestoreSuccess) {
          AppLogger.warning('Firestore kullanıcı oluşturulamadı, ancak lokal kayıt yapılıyor');
        }

        // Lokal olarak kaydet
        try {
          await LocalStorageService.saveUser(user.uid, fullName);
          // Şifre sıfırlama flag'ini temizle (yeni kayıt için gerekli değil ama güvenlik için)
          await LocalStorageService.setPasswordResetPending(false);
        } catch (e) {
          AppLogger.error('Lokal kayıt hatası', e);
          throw Exception('Kullanıcı bilgileri kaydedilemedi. Lütfen tekrar deneyin.');
        }

        // Başarı mesajı göster
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Kayıt başarılı! Hoş geldiniz, $fullName',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } else {
        // Giriş işlemi - EN RADİKAL ÇÖZÜM: Şifre sıfırlama beklemede ise HER ZAMAN oturumu kapat
        final passwordResetPending = await LocalStorageService.isPasswordResetPending();
        AppLogger.info('Giriş denemesi - passwordResetPending: $passwordResetPending, email: $email');
        
        // ÖNEMLİ: Şifre sıfırlama beklemede ise, email kontrolü yapmadan HER ZAMAN oturumu kapat
        // Ayrıca, aynı e-posta ile aktif oturum varsa da kapat (güvenlik için)
        try {
          final currentUser = _auth.currentUser;
          AppLogger.info('Mevcut oturum durumu: ${currentUser != null ? "Açık (${currentUser.email})" : "Kapalı"}');
          
          // Şifre sıfırlama beklemede ise HER ZAMAN oturumu kapat (email kontrolü yapmadan)
          // VEYA aynı e-posta ile aktif oturum varsa kapat
          final shouldSignOut = passwordResetPending || (currentUser != null && currentUser.email?.toLowerCase() == email.toLowerCase());
          
          // EN RADİKAL: passwordResetPending true ise, HER ZAMAN oturumu kapat, email kontrolü yapmadan
          if (passwordResetPending || shouldSignOut) {
            if (currentUser != null) {
              AppLogger.info('Şifre sıfırlama sonrası giriş - mevcut oturum kapatılıyor (email: ${currentUser.email}, flag: $passwordResetPending)');
              
              // Oturumu kapat - çok agresif yaklaşım
              await _auth.signOut();
              AppLogger.info('İlk signOut çağrıldı');
              
              // Firebase Auth'un oturumunu tamamen temizlemesi için bekleme
              await Future.delayed(const Duration(milliseconds: 2000));
              
              // Tekrar kontrol et ve gerekirse tekrar kapat (10 kez deneme - daha agresif)
              var retryCount = 0;
              while (retryCount < 10) {
                final stillLoggedIn = _auth.currentUser;
                if (stillLoggedIn == null) {
                  AppLogger.info('Oturum başarıyla kapatıldı (deneme ${retryCount + 1})');
                  break; // Oturum kapandı
                }
                AppLogger.warning('Oturum hala açık (deneme ${retryCount + 1}/10), tekrar kapatılıyor (email: ${stillLoggedIn.email})');
                await _auth.signOut();
                await Future.delayed(const Duration(milliseconds: 1000));
                retryCount++;
              }
              
              // Lokal depolamayı temizle
              await LocalStorageService.clearUser();
              AppLogger.info('Şifre sıfırlama sonrası - mevcut oturum kapatıldı ve temizlendi');
              
              // Son bir kontrol - eğer hala oturum açıksa, bir kez daha dene
              await Future.delayed(const Duration(milliseconds: 1000));
              final finalCheck = _auth.currentUser;
              if (finalCheck != null) {
                AppLogger.error('Oturum hala açık! Son deneme yapılıyor... (email: ${finalCheck.email})');
                await _auth.signOut();
                await Future.delayed(const Duration(milliseconds: 1500));
                
                // Son kontrol
                final lastCheck = _auth.currentUser;
                if (lastCheck != null) {
                  AppLogger.error('KRİTİK: Oturum kapatılamıyor! Firebase Auth sorunu olabilir. (email: ${lastCheck.email})');
                } else {
                  AppLogger.info('Son denemede oturum kapatıldı');
                }
              } else {
                AppLogger.info('Oturum başarıyla kapatıldı - final check geçti');
              }
            } else if (passwordResetPending) {
              // Oturum yok ama flag var - sadece lokal temizle
              await LocalStorageService.clearUser();
              AppLogger.info('Şifre sıfırlama beklemede - lokal temizlendi (oturum yok)');
            }
          } else {
            AppLogger.info('Oturum kapatma gerekmiyor (flag: $passwordResetPending, currentUser: ${currentUser?.email})');
          }
        } catch (e) {
          AppLogger.warning('Oturum kapatma hatası (önemli değil): $e');
          // Hata olsa bile devam et - giriş yapmayı dene
        }
        
        // Yeni şifreyle giriş yap - oturum kesinlikle kapalı olmalı
        // EN RADİKAL: passwordResetPending true ise, HER ZAMAN son kontrol yap ve oturumu kapat
        if (passwordResetPending) {
          AppLogger.info('passwordResetPending true - giriş öncesi son kontrol yapılıyor...');
          var finalRetryCount = 0;
          while (finalRetryCount < 5) {
            final preLoginCheck = _auth.currentUser;
            if (preLoginCheck == null) {
              AppLogger.info('Giriş öncesi kontrol: Oturum kapalı - giriş yapılabilir (deneme ${finalRetryCount + 1})');
              break;
            }
            AppLogger.error('Giriş öncesi kontrol: Oturum hala açık! Zorla kapatılıyor... (email: ${preLoginCheck.email}, deneme ${finalRetryCount + 1}/5)');
            await _auth.signOut();
            await Future.delayed(const Duration(milliseconds: 2000));
            finalRetryCount++;
          }
        } else {
          final preLoginCheck = _auth.currentUser;
          if (preLoginCheck != null) {
            AppLogger.warning('Giriş öncesi kontrol: Oturum açık ama flag false (email: ${preLoginCheck.email})');
          } else {
            AppLogger.info('Giriş öncesi kontrol: Oturum kapalı - giriş yapılabilir');
          }
        }
        
        // Son bir kez daha kontrol et
        final absoluteFinalCheck = _auth.currentUser;
        if (absoluteFinalCheck != null && passwordResetPending) {
          AppLogger.error('MUTLAK SON KONTROL: Oturum hala açık! Son deneme yapılıyor... (email: ${absoluteFinalCheck.email})');
          await _auth.signOut();
          await Future.delayed(const Duration(milliseconds: 3000));
        }
        
        AppLogger.info('Yeni şifreyle giriş yapılıyor (email: $email, flag: $passwordResetPending)');
        try {
          // Şifre sıfırlama sonrası giriş - Firebase Auth'un token'ını yenile
          if (passwordResetPending) {
            // Önce mevcut oturumu tamamen temizle
            await _auth.signOut();
            await Future.delayed(const Duration(milliseconds: 1000));
            AppLogger.info('Şifre sıfırlama sonrası - oturum temizlendi, yeni giriş yapılıyor');
          }
          
          userCredential = await _auth.signInWithEmailAndPassword(
            email: email,
            password: password,
          );
          AppLogger.success('Giriş başarılı - userCredential alındı');
        } catch (loginError) {
          AppLogger.error('signInWithEmailAndPassword hatası', loginError);
          
          // PigeonUserDetails type cast hatası - giriş aslında başarılı olabilir
          // FirebaseAuth currentUser'ı kontrol et
          final errorString = loginError.toString().toLowerCase();
          if (errorString.contains('pigeonuserdetails') || 
              errorString.contains('type cast') ||
              errorString.contains('list<object') ||
              errorString.contains('not a subtype')) {
            AppLogger.warning('Type cast hatası tespit edildi - currentUser kontrol ediliyor...');
            AppLogger.warning('PigeonUserDetails type cast hatası - currentUser kontrol ediliyor...');
            await Future.delayed(const Duration(milliseconds: 500));
            final currentUser = _auth.currentUser;
            if (currentUser != null && currentUser.email == email) {
              AppLogger.success('Giriş başarılı (currentUser kontrolü ile) - type cast hatası yok sayıldı');
              // currentUser'ı direkt kullan (userCredential yerine)
              // userCredential.user yerine currentUser kullanacağız
              final user = currentUser;
              
              // Firestore'dan kullanıcı bilgilerini al
              AppLogger.info('Kullanıcı bilgileri alınıyor (uid: ${user.uid})');
              try {
                final userDoc = await FirestoreService.getUser(user.uid);
                final fullName = userDoc?['fullName'] as String? ?? user.displayName ?? 'Kullanıcı';
                
                AppLogger.info('Kullanıcı bilgileri alındı (fullName: $fullName)');
                
                // Lokal olarak kaydet
                await LocalStorageService.saveUser(user.uid, fullName);
                AppLogger.success('Kullanıcı bilgileri lokal olarak kaydedildi');
                
                // Şifre sıfırlama flag'ini temizle
                await LocalStorageService.setPasswordResetPending(false);
                AppLogger.success('Başarılı giriş - şifre sıfırlama flag\'i temizlendi');
                
                // Home ekranına yönlendir
                if (mounted && !_isNavigating) {
                  _isNavigating = true;
                  await Future.delayed(const Duration(milliseconds: 500));
                  if (!mounted) return;
                  
                  final navigator = Navigator.of(context, rootNavigator: true);
                  if (!navigator.mounted) return;
                  
                  AppLogger.info('Navigator hazır - home ekranına yönlendiriliyor');
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted || !_isNavigating) return;
                    try {
                      final nav = Navigator.of(context, rootNavigator: true);
                      if (nav.mounted) {
                        AppLogger.success('Home ekranına yönlendiriliyor');
                        nav.pushNamedAndRemoveUntil('/home', (route) => false);
                      }
                    } catch (e) {
                      AppLogger.error('Navigator hatası', e);
                      _isNavigating = false;
                    }
                  });
                }
                return; // Başarılı, devam etme
              } catch (firestoreError) {
                AppLogger.error('Firestore kullanıcı bilgisi alma hatası', firestoreError);
                // Firestore hatası olsa bile giriş yapılmış sayılır
                await LocalStorageService.saveUser(user.uid, user.displayName ?? 'Kullanıcı');
                await LocalStorageService.setPasswordResetPending(false);
                
                // Home ekranına yönlendir
                if (mounted && !_isNavigating) {
                  _isNavigating = true;
                  await Future.delayed(const Duration(milliseconds: 500));
                  if (!mounted) return;
                  
                  final navigator = Navigator.of(context, rootNavigator: true);
                  if (!navigator.mounted) return;
                  
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted || !_isNavigating) return;
                    try {
                      final nav = Navigator.of(context, rootNavigator: true);
                      if (nav.mounted) {
                        nav.pushNamedAndRemoveUntil('/home', (route) => false);
                      }
                    } catch (e) {
                      AppLogger.error('Navigator hatası', e);
                      _isNavigating = false;
                    }
                  });
                }
                return; // Başarılı, devam etme
              }
            } else {
              AppLogger.error('currentUser null veya email eşleşmiyor - gerçek hata');
              rethrow;
            }
          } else {
            rethrow; // Diğer hatalar için yukarıya fırlat
          }
        }

        final user = userCredential.user;
        if (user != null) {
          AppLogger.info('Kullanıcı bilgileri alınıyor (uid: ${user.uid})');
          // Firestore'dan kullanıcı bilgilerini al
          try {
            final userDoc = await FirestoreService.getUser(user.uid);
            final fullName = userDoc?['fullName'] as String? ?? user.displayName ?? 'Kullanıcı';
            
            AppLogger.info('Kullanıcı bilgileri alındı (fullName: $fullName)');
            
            // Lokal olarak kaydet
            await LocalStorageService.saveUser(user.uid, fullName);
            AppLogger.success('Kullanıcı bilgileri lokal olarak kaydedildi');
            
            // Şifre sıfırlama flag'ini kesinlikle temizle (başarılı giriş sonrası)
            await LocalStorageService.setPasswordResetPending(false);
            AppLogger.success('Başarılı giriş - şifre sıfırlama flag\'i temizlendi');
          } catch (firestoreError) {
            AppLogger.error('Firestore kullanıcı bilgisi alma hatası', firestoreError);
            // Firestore hatası olsa bile giriş yapılmış sayılır
            await LocalStorageService.saveUser(user.uid, user.displayName ?? 'Kullanıcı');
            await LocalStorageService.setPasswordResetPending(false);
          }
        } else {
          AppLogger.error('userCredential.user null!');
        }
      }

      // Home ekranına yönlendir - güvenli navigasyon
      AppLogger.info('Home ekranına yönlendiriliyor...');
      if (mounted && !_isNavigating) {
        _isNavigating = true;
        // Navigator'ın hazır olmasını bekle
        await Future.delayed(const Duration(milliseconds: 500));
        if (!mounted) {
          AppLogger.warning('Widget unmounted - navigasyon iptal edildi');
          return;
        }
        
        // Navigator'ın durumunu kontrol et
        final navigator = Navigator.of(context, rootNavigator: true);
        if (!navigator.mounted) {
          AppLogger.warning('Navigator unmounted - navigasyon iptal edildi');
          return;
        }
        
        AppLogger.info('Navigator hazır - home ekranına yönlendiriliyor');
        
        // Post-frame callback ile güvenli navigasyon
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_isNavigating) {
            AppLogger.warning('Post-frame callback: Widget unmounted veya navigasyon iptal edildi');
            return;
          }
          try {
            final nav = Navigator.of(context, rootNavigator: true);
            if (nav.mounted) {
              AppLogger.success('Home ekranına yönlendiriliyor');
              nav.pushNamedAndRemoveUntil('/home', (route) => false);
            } else {
              AppLogger.error('Navigator mounted değil - navigasyon yapılamadı');
            }
          } catch (e) {
            AppLogger.error('Navigator hatası', e);
            _isNavigating = false;
          }
        });
      } else {
        AppLogger.warning('Navigasyon yapılamadı: mounted=${mounted}, _isNavigating=$_isNavigating');
      }
    } on FirebaseAuthException catch (e) {
      AppLogger.error('FirebaseAuthException: ${e.code} - ${e.message}', e);
      String errorMessage = 'Giriş hatası oluştu';
      
      // PigeonUserDetails hatası için özel kontrol
      final errorString = e.toString().toLowerCase();
      final errorCode = e.code.toLowerCase();
      
      AppLogger.info('Giriş hatası kodu: $errorCode');
      
      // Şifre hataları için özel mesajlar
      if (errorCode == 'wrong-password' || errorCode == 'invalid-credential') {
        // Şifre sıfırlama beklemede mi kontrol et
        final passwordResetPending = await LocalStorageService.isPasswordResetPending();
        
        if (passwordResetPending) {
          // Şifre sıfırlama sonrası giriş denemesi - kısa mesaj
          errorMessage = 'Şifre hatalı. Şifrenizi sıfırladıysanız, e-postanızdaki linke tıklayıp yeni şifrenizi oluşturduktan sonra burada yeni şifrenizi girin. Eski şifre artık geçersizdir.';
        } else {
          errorMessage = 'E-posta veya şifre hatalı. Lütfen bilgilerinizi kontrol edin.';
        }
      } else if (errorCode == 'user-not-found' || errorCode == 'user-disabled') {
        errorMessage = 'Bu e-posta adresi ile kayıtlı kullanıcı bulunamadı veya hesap devre dışı bırakılmış.';
      } else if (errorCode == 'invalid-email') {
        errorMessage = 'Geçersiz e-posta adresi. Lütfen e-posta adresinizi kontrol edin.';
      } else if (errorCode == 'too-many-requests') {
        errorMessage = 'Çok fazla başarısız giriş denemesi. Lütfen birkaç dakika bekleyip tekrar deneyin.';
      } else if (errorCode == 'network-request-failed') {
        errorMessage = 'İnternet bağlantısı yok. Lütfen internet bağlantınızı kontrol edin.';
      } else if (errorString.contains('pigeonuserdetails') || 
          errorString.contains('user details') ||
          errorCode == 'internal-error' ||
          errorCode.contains('internal')) {
        // Kullanıcı oluşturuldu ama detaylar alınamadı - genellikle başarılı sayılabilir
        if (_isSignUp) {
          // Kullanıcı oluşturuldu, devam et
          try {
            // Biraz bekle ki kullanıcı tam oluşsun
            await Future.delayed(const Duration(milliseconds: 500));
            
            final currentUser = _auth.currentUser;
            if (currentUser != null) {
              final fullName = _nameController.text.trim();
              // Firestore'a kaydet - retry ile
              for (int i = 0; i < 3; i++) {
                try {
                  await FirestoreService.createUserIfNotExists(
                    currentUser.uid,
                    fullName,
                  );
                  break;
                } catch (e) {
                  AppLogger.error('Firestore kullanıcı oluşturma hatası (deneme ${i + 1}/3)', e);
                  if (i < 2) {
                    await Future.delayed(Duration(milliseconds: 500 * (i + 1)));
                  }
                }
              }
              
              // Lokal kaydet
              try {
                await LocalStorageService.saveUser(currentUser.uid, fullName);
              } catch (e) {
                AppLogger.error('Lokal kayıt hatası', e);
              }
              
              // Başarı mesajı
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.white),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Kayıt başarılı! Hoş geldiniz, $fullName',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    backgroundColor: Colors.green,
                    duration: const Duration(seconds: 3),
                  ),
                );
              }
              
              // Home ekranına yönlendir - güvenli navigasyon
              if (mounted && !_isNavigating) {
                _isNavigating = true;
                await Future.delayed(const Duration(milliseconds: 500));
                if (!mounted) return;
                
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted || !_isNavigating) return;
                  try {
                    final nav = Navigator.of(context, rootNavigator: true);
                    if (nav.mounted) {
                      nav.pushNamedAndRemoveUntil('/home', (route) => false);
                    }
                  } catch (e) {
                    AppLogger.error('Navigator hatası', e);
                    _isNavigating = false;
                  }
                });
              }
              return;
            } else {
              errorMessage = 'Kayıt başarılı ancak oturum açılamadı. Lütfen giriş yapın.';
            }
          } catch (e) {
            AppLogger.error('Kullanıcı detayları alınamadı', e);
            errorMessage = 'Kayıt başarılı ancak bazı bilgiler yüklenemedi. Lütfen tekrar giriş yapın.';
          }
        } else {
          errorMessage = 'Giriş hatası. Lütfen tekrar deneyin.';
        }
      } else {
        switch (e.code) {
          case 'weak-password':
            errorMessage = 'Şifre çok zayıf. Lütfen daha güçlü bir şifre seçin (en az 6 karakter).';
            break;
          case 'email-already-in-use':
            errorMessage = 'Bu e-posta adresi zaten kullanılıyor. Giriş yapmayı deneyin veya farklı bir e-posta kullanın.';
            break;
          case 'user-not-found':
            errorMessage = 'Bu e-posta adresi ile kayıtlı kullanıcı bulunamadı. Lütfen e-posta adresinizi kontrol edin veya kayıt olun.';
            break;
          case 'wrong-password':
            errorMessage = 'Şifre hatalı. Şifrenizi yeni sıfırladıysanız, lütfen yeni oluşturduğunuz şifreyi kullanın. Eski şifre artık geçersizdir.';
            // Şifre yanlış olduğunda mevcut oturumu kapat (güvenlik için)
            try {
              await _auth.signOut();
              AppLogger.info('Şifre yanlış - oturum kapatıldı');
            } catch (e) {
              AppLogger.warning('Oturum kapatma hatası (önemli değil): $e');
            }
            break;
          case 'invalid-email':
            errorMessage = 'Geçersiz e-posta adresi. Lütfen geçerli bir e-posta adresi girin (örn: ornek@email.com).';
            break;
          case 'user-disabled':
            errorMessage = 'Bu kullanıcı hesabı devre dışı bırakılmış. Lütfen destek ekibi ile iletişime geçin.';
            break;
          case 'too-many-requests':
            errorMessage = 'Çok fazla başarısız deneme yapıldı. Lütfen birkaç dakika bekleyip tekrar deneyin.';
            break;
          case 'network-request-failed':
            errorMessage = 'İnternet bağlantısı yok. Lütfen internet bağlantınızı kontrol edin ve tekrar deneyin.';
            break;
          case 'invalid-credential':
            errorMessage = 'E-posta veya şifre hatalı. Şifrenizi yeni sıfırladıysanız, lütfen yeni oluşturduğunuz şifreyi kullanın.';
            // Geçersiz kimlik bilgileri olduğunda mevcut oturumu kapat (güvenlik için)
            try {
              await _auth.signOut();
              AppLogger.info('Geçersiz kimlik bilgileri - oturum kapatıldı');
            } catch (e) {
              AppLogger.warning('Oturum kapatma hatası (önemli değil): $e');
            }
            break;
          default:
            errorMessage = 'Giriş hatası: ${e.message ?? e.code}. Lütfen bilgilerinizi kontrol edip tekrar deneyin.';
        }
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e, stackTrace) {
      AppLogger.error('Giriş hatası', e, stackTrace);
      if (mounted) {
        String errorMessage = 'Giriş hatası oluştu';
        final errorString = e.toString().toLowerCase();
        
        // PigeonUserDetails hatası kontrolü
        if (errorString.contains('pigeonuserdetails') || 
            errorString.contains('user details')) {
          if (_isSignUp) {
            // Kullanıcı oluşturuldu ama detaylar alınamadı
            try {
              await Future.delayed(const Duration(milliseconds: 500));
              final currentUser = _auth.currentUser;
              if (currentUser != null) {
                final fullName = _nameController.text.trim();
                // Firestore'a kaydet - retry ile
                for (int i = 0; i < 3; i++) {
                  try {
                    await FirestoreService.createUserIfNotExists(
                      currentUser.uid,
                      fullName,
                    );
                    break;
                  } catch (e) {
                    AppLogger.error('Firestore kullanıcı oluşturma hatası (deneme ${i + 1}/3)', e);
                    if (i < 2) {
                      await Future.delayed(Duration(milliseconds: 500 * (i + 1)));
                    }
                  }
                }
                
                // Lokal kaydet
                try {
                  await LocalStorageService.saveUser(currentUser.uid, fullName);
                } catch (e) {
                  AppLogger.error('Lokal kayıt hatası', e);
                }
                
                // Başarı mesajı
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.white),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Kayıt başarılı! Hoş geldiniz, $fullName',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                      backgroundColor: Colors.green,
                      duration: const Duration(seconds: 3),
                    ),
                  );
                }
                
                if (mounted && !_isNavigating) {
                  _isNavigating = true;
                  await Future.delayed(const Duration(milliseconds: 500));
                  if (!mounted) return;
                  
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted || !_isNavigating) return;
                    try {
                      final nav = Navigator.of(context, rootNavigator: true);
                      if (nav.mounted) {
                        nav.pushNamedAndRemoveUntil('/home', (route) => false);
                      }
                    } catch (e) {
                      AppLogger.error('Navigator hatası', e);
                      _isNavigating = false;
                    }
                  });
                }
                return;
              }
            } catch (e) {
              AppLogger.error('Kullanıcı detayları alınamadı', e);
            }
            errorMessage = 'Kayıt başarılı ancak bazı bilgiler yüklenemedi. Lütfen tekrar giriş yapın.';
          } else {
            errorMessage = 'Giriş yapılamadı. Lütfen e-posta ve şifrenizi kontrol edip tekrar deneyin.';
          }
        } else if (errorString.contains('firestore') || errorString.contains('firebase')) {
          if (errorString.contains('unavailable') || errorString.contains('unable to resolve') || errorString.contains('no address')) {
            errorMessage = 'İnternet bağlantısı yok. Lütfen internet bağlantınızı kontrol edin.';
          } else if (errorString.contains('permission-denied') || errorString.contains('permission')) {
            errorMessage = 'Firestore izin hatası. Lütfen Firebase Console\'da güvenlik kurallarını kontrol edin.';
          } else if (errorString.contains('timeout') || errorString.contains('connection')) {
            errorMessage = 'Bağlantı zaman aşımı. Lütfen tekrar deneyin.';
          } else {
            errorMessage = 'Firestore bağlantı hatası. Lütfen internet bağlantınızı kontrol edin.';
          }
        } else {
          errorMessage = 'Hata: ${e.toString()}';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 360;
    final padding = isSmallScreen ? 24.0 : 32.0;
    final logoSize = isSmallScreen ? 100.0 : 120.0;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [
                    const Color(0xFF1A1F3A),
                    const Color(0xFF0F1419),
                    const Color(0xFF1A1F3A),
                  ]
                : [
                    Colors.white,
                    const Color(0xFFF5F7FA),
                    const Color(0xFFE8F0FE),
                  ],
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(padding),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 420,
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Logo ve Marka - Şık birleşik tasarım
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.0, end: 1.0),
                        duration: const Duration(milliseconds: 1000),
                        curve: Curves.easeOutCubic,
                        builder: (context, value, child) {
                          return Opacity(
                            opacity: value,
                            child: Transform.scale(
                              scale: 0.85 + (value * 0.15),
                              child: Transform.translate(
                                offset: Offset(0, 30 * (1 - value)),
                                child: child,
                              ),
                            ),
                          );
                        },
                        child: Column(
                          children: [
                            // Logo - küçültülmüş
                            Image.asset(
                              'assets/rev-favicon.png',
                              height: logoSize * 0.8,
                              width: logoSize * 0.8,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) {
                                return Icon(
                                  Icons.receipt_long_rounded,
                                  size: logoSize * 0.8,
                                  color: theme.colorScheme.primary,
                                );
                              },
                            ),
                            const SizedBox(height: 40),
                            // REVIUM - büyük harflerle
                            Text(
                              'REVIUM',
                              style: theme.textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: isDark ? Colors.white : const Color(0xFF1A1F3A),
                                letterSpacing: 1.5,
                                height: 1.3,
                                fontSize: 32,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 48),
                      // Ad Soyad TextField (sadece kayıt modunda)
                      AnimatedSize(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        child: _isSignUp
                            ? TweenAnimationBuilder<double>(
                                tween: Tween(begin: 0.0, end: 1.0),
                                duration: const Duration(milliseconds: 500),
                                curve: Curves.easeOut,
                                builder: (context, value, child) {
                                  return Opacity(
                                    opacity: value,
                                    child: Transform.translate(
                                      offset: Offset(0, 15 * (1 - value)),
                                      child: child,
                                    ),
                                  );
                                },
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 20),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: [
                                      BoxShadow(
                                        color: theme.colorScheme.primary.withValues(alpha: 0.08),
                                        blurRadius: 15,
                                        offset: const Offset(0, 4),
                                        spreadRadius: 0,
                                      ),
                                    ],
                                  ),
                                  child: TextFormField(
                                    controller: _nameController,
                                    decoration: InputDecoration(
                                      labelText: 'Ad Soyad',
                                      hintText: 'Adınızı ve soyadınızı girin',
                                      prefixIcon: Container(
                                        margin: const EdgeInsets.all(12),
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              theme.colorScheme.primaryContainer,
                                              theme.colorScheme.primaryContainer.withValues(alpha: 0.7),
                                            ],
                                          ),
                                          borderRadius: BorderRadius.circular(14),
                                        ),
                                        child: Icon(
                                          Icons.person_outline_rounded,
                                          color: theme.colorScheme.primary,
                                          size: 22,
                                        ),
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(20),
                                        borderSide: BorderSide(
                                          color: theme.colorScheme.outline.withValues(alpha: 0.15),
                                          width: 1.5,
                                        ),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(20),
                                        borderSide: BorderSide(
                                          color: theme.colorScheme.outline.withValues(alpha: 0.15),
                                          width: 1.5,
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(20),
                                        borderSide: BorderSide(
                                          color: theme.colorScheme.primary,
                                          width: 2.5,
                                        ),
                                      ),
                                      errorBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(20),
                                        borderSide: BorderSide(
                                          color: theme.colorScheme.error,
                                          width: 1.5,
                                        ),
                                      ),
                                      focusedErrorBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(20),
                                        borderSide: BorderSide(
                                          color: theme.colorScheme.error,
                                          width: 2.5,
                                        ),
                                      ),
                                      filled: true,
                                      fillColor: theme.colorScheme.surface,
                                      contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 24,
                                        vertical: 22,
                                      ),
                                      labelStyle: TextStyle(
                                        color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15,
                                      ),
                                      hintStyle: TextStyle(
                                        color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                                        fontSize: 15,
                                      ),
                                    ),
                                    textCapitalization: TextCapitalization.words,
                                    validator: (value) {
                                      if (_isSignUp) {
                                        if (value == null || value.trim().isEmpty) {
                                          return 'Lütfen ad soyad giriniz';
                                        }
                                        if (value.trim().length < 3) {
                                          return 'Ad soyad en az 3 karakter olmalıdır';
                                        }
                                      }
                                      return null;
                                    },
                                    enabled: !_isLoading,
                                    textInputAction: TextInputAction.next,
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                      // E-posta TextField
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.0, end: 1.0),
                        duration: const Duration(milliseconds: 600),
                        curve: Curves.easeOut,
                        builder: (context, value, child) {
                          return Opacity(
                            opacity: value,
                            child: Transform.translate(
                              offset: Offset(0, 15 * (1 - value)),
                              child: child,
                            ),
                          );
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 20),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: theme.colorScheme.primary.withValues(alpha: 0.08),
                                blurRadius: 15,
                                offset: const Offset(0, 4),
                                spreadRadius: 0,
                              ),
                            ],
                          ),
                          child: TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            decoration: InputDecoration(
                              labelText: 'E-posta',
                              hintText: 'ornek@reviumtech.com',
                              prefixIcon: Container(
                                margin: const EdgeInsets.all(12),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      theme.colorScheme.primaryContainer,
                                      theme.colorScheme.primaryContainer.withValues(alpha: 0.7),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(
                                  Icons.email_outlined,
                                  color: theme.colorScheme.primary,
                                  size: 22,
                                ),
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(20),
                                borderSide: BorderSide(
                                  color: theme.colorScheme.outline.withValues(alpha: 0.15),
                                  width: 1.5,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(20),
                                borderSide: BorderSide(
                                  color: theme.colorScheme.outline.withValues(alpha: 0.15),
                                  width: 1.5,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(20),
                                borderSide: BorderSide(
                                  color: theme.colorScheme.primary,
                                  width: 2.5,
                                ),
                              ),
                              errorBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(20),
                                borderSide: BorderSide(
                                  color: theme.colorScheme.error,
                                  width: 1.5,
                                ),
                              ),
                              focusedErrorBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(20),
                                borderSide: BorderSide(
                                  color: theme.colorScheme.error,
                                  width: 2.5,
                                ),
                              ),
                              filled: true,
                              fillColor: theme.colorScheme.surface,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 22,
                              ),
                              labelStyle: TextStyle(
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                              hintStyle: TextStyle(
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                                fontSize: 15,
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Lütfen e-posta adresinizi giriniz';
                              }
                              if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value.trim())) {
                                return 'Geçerli bir e-posta adresi giriniz';
                              }
                              return null;
                            },
                            enabled: !_isLoading,
                            textInputAction: TextInputAction.next,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                      // Şifre TextField
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.0, end: 1.0),
                        duration: const Duration(milliseconds: 600),
                        curve: Curves.easeOut,
                        builder: (context, value, child) {
                          return Opacity(
                            opacity: value,
                            child: Transform.translate(
                              offset: Offset(0, 15 * (1 - value)),
                              child: child,
                            ),
                          );
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: theme.colorScheme.primary.withValues(alpha: 0.08),
                                blurRadius: 15,
                                offset: const Offset(0, 4),
                                spreadRadius: 0,
                              ),
                            ],
                          ),
                          child: TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            decoration: InputDecoration(
                              labelText: 'Şifre',
                              hintText: _isSignUp ? 'En az 6 karakter' : 'Şifrenizi giriniz',
                              prefixIcon: Container(
                                margin: const EdgeInsets.all(12),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      theme.colorScheme.primaryContainer,
                                      theme.colorScheme.primaryContainer.withValues(alpha: 0.7),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(
                                  Icons.lock_outline_rounded,
                                  color: theme.colorScheme.primary,
                                  size: 22,
                                ),
                              ),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                                tooltip: _obscurePassword ? 'Şifreyi göster' : 'Şifreyi gizle',
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(20),
                                borderSide: BorderSide(
                                  color: theme.colorScheme.outline.withValues(alpha: 0.15),
                                  width: 1.5,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(20),
                                borderSide: BorderSide(
                                  color: theme.colorScheme.outline.withValues(alpha: 0.15),
                                  width: 1.5,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(20),
                                borderSide: BorderSide(
                                  color: theme.colorScheme.primary,
                                  width: 2.5,
                                ),
                              ),
                              errorBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(20),
                                borderSide: BorderSide(
                                  color: theme.colorScheme.error,
                                  width: 1.5,
                                ),
                              ),
                              focusedErrorBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(20),
                                borderSide: BorderSide(
                                  color: theme.colorScheme.error,
                                  width: 2.5,
                                ),
                              ),
                              filled: true,
                              fillColor: theme.colorScheme.surface,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 22,
                              ),
                              labelStyle: TextStyle(
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                              hintStyle: TextStyle(
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                                fontSize: 15,
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Lütfen şifrenizi giriniz';
                              }
                              if (_isSignUp && value.length < 6) {
                                return 'Şifre en az 6 karakter olmalıdır';
                              }
                              return null;
                            },
                            enabled: !_isLoading,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _handleLogin(),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                      // Şifremi Unuttum butonu (sadece giriş modunda) - şifre alanına yakın
                      if (!_isSignUp) ...[
                        Align(
                          alignment: Alignment.centerRight,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 4, bottom: 20),
                            child: TextButton(
                              onPressed: _isLoading ? null : _handleForgotPassword,
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text(
                                'Şifremi Unuttum',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                      // Giriş butonu - Professional design
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.0, end: 1.0),
                        duration: const Duration(milliseconds: 800),
                        curve: Curves.easeOut,
                        builder: (context, value, child) {
                          return Opacity(
                            opacity: value,
                            child: Transform.translate(
                              offset: Offset(0, 15 * (1 - value)),
                              child: child,
                            ),
                          );
                        },
                        child: Container(
                          width: double.infinity,
                          height: 58,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            gradient: LinearGradient(
                              colors: [
                                theme.colorScheme.primary,
                                theme.colorScheme.primary.withValues(alpha: 0.85),
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: theme.colorScheme.primary.withValues(alpha: 0.4),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                                spreadRadius: 0,
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _handleLogin,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              foregroundColor: Colors.white,
                              shadowColor: Colors.transparent,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    height: 26,
                                    width: 26,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 3,
                                      valueColor:
                                          AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        _isSignUp ? Icons.person_add_rounded : Icons.login_rounded,
                                        size: 22,
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        _isSignUp ? 'Kayıt Ol' : 'Giriş Yap',
                                        style: theme.textTheme.titleLarge?.copyWith(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.8,
                                          fontSize: 18,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      // Giriş/Kayıt geçiş butonu
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: TextButton(
                          key: ValueKey(_isSignUp),
                          onPressed: _isLoading
                              ? null
                              : () {
                                  setState(() {
                                    _isSignUp = !_isSignUp;
                                    _formKey.currentState?.reset();
                                    _nameController.clear();
                                    _emailController.clear();
                                    _passwordController.clear();
                                  });
                                },
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _isSignUp
                                    ? 'Zaten hesabınız var mı? '
                                    : 'Hesabınız yok mu? ',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.7)
                                      : const Color(0xFF64748B),
                                  fontWeight: FontWeight.w500,
                                  fontSize: 14,
                                ),
                              ),
                              Text(
                                _isSignUp ? 'Giriş yapın' : 'Kayıt olun',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}



