/**
 * Ana uygulama dosyası
 * Firebase başlatma ve routing yönetimi
 */

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'firebase_options.dart';
import 'services/local_storage_service.dart';
import 'services/firestore_service.dart';
import 'screens/splash_login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/statistics_screen.dart';
import 'screens/password_reset_screen.dart';
import 'models/user_profile.dart';
import 'utils/app_logger.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase'i başlat
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    AppLogger.success('Firebase başarıyla başlatıldı');
  } on FirebaseException catch (e) {
    AppLogger.error('Firebase başlatma hatası (FirebaseException): ${e.code} - ${e.message}', e);
  } catch (e) {
    AppLogger.error('Firebase başlatma hatası', e);
    // Firebase başlatılamazsa da uygulama çalışmaya devam eder
    // Ancak Firestore işlemleri başarısız olacaktır
  }

  // Uygulamayı hemen başlat (locale yüklemesi arka planda yapılacak)
  runApp(const MyApp());
  
  // Locale yüklemesini arka planda yap (non-blocking - performans için)
  if (!kIsWeb) {
    // Mobil platformlarda locale data'yı arka planda yükle
    initializeDateFormatting('tr_TR', null).then((_) {
      AppLogger.success('intl locale başarıyla başlatıldı');
    }).catchError((e) {
      AppLogger.warning('intl locale başlatma hatası: $e');
    });
  } else {
    // Web'de locale data otomatik yüklenir, manuel yükleme gerekmez
    AppLogger.info('Web platformu - locale data otomatik yüklenecek');
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  bool _isDarkMode = false;

  @override
  void initState() {
    super.initState();
    _loadThemePreference();
    WidgetsBinding.instance.addObserver(this);
    // Deep link kontrolü
    _checkInitialLink();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  static const MethodChannel _channel = MethodChannel('com.revium.management/deep_link');
  String? _pendingActionCode;

  // Deep link kontrolü - uygulama açıldığında
  Future<void> _checkInitialLink() async {
    if (kIsWeb) {
      // Web'de getRedirectResult kullan
      final auth = FirebaseAuth.instance;
      final link = await auth.getRedirectResult();
      
      if (link.user != null && link.additionalUserInfo != null) {
        final actionCode = link.additionalUserInfo!.profile?['actionCode'] as String?;
        if (actionCode != null) {
          AppLogger.info('Password reset deep link detected (web): $actionCode');
          _navigateToPasswordReset(actionCode);
        }
      }
    } else {
      // Android'de MethodChannel kullan
      try {
        final initialLink = await _channel.invokeMethod<String>('getInitialLink');
        if (initialLink != null) {
          AppLogger.info('Deep link detected: $initialLink');
          _parseDeepLink(initialLink);
        }
        
        // Deep link listener - uygulama açıkken gelen linkler için
        _channel.setMethodCallHandler((call) async {
          if (call.method == 'onLink') {
            final link = call.arguments as String?;
            if (link != null) {
              AppLogger.info('Deep link received: $link');
              _parseDeepLink(link);
            }
          }
        });
      } catch (e) {
        AppLogger.warning('Deep link kontrolü hatası: $e');
      }
    }
  }

  void _parseDeepLink(String url) {
    AppLogger.info('Parsing deep link: $url');
    try {
      final uri = Uri.parse(url);
      final oobCode = uri.queryParameters['oobCode'];
      final mode = uri.queryParameters['mode'];
      
      if (mode == 'resetPassword' && oobCode != null) {
        AppLogger.info('Password reset deep link detected, oobCode: $oobCode');
        _pendingActionCode = oobCode;
        _navigateToPasswordReset(oobCode);
      }
    } catch (e) {
      AppLogger.error('Deep link parse hatası', e);
    }
  }

  void _navigateToPasswordReset(String actionCode) {
    // Şifre sıfırlama ekranına yönlendir
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pushNamed(
          '/passwordReset',
          arguments: actionCode,
        );
      }
    });
  }

  Future<void> _loadThemePreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isDarkMode = prefs.getBool('dark_mode') ?? false;
    });
  }

  void toggleTheme(bool isDark) {
    setState(() {
      _isDarkMode = isDark;
    });
    SharedPreferences.getInstance().then((prefs) {
      prefs.setBool('dark_mode', isDark);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Harcama Takibi',
      debugShowCheckedModeBanner: false,
      locale: const Locale('tr', 'TR'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('tr', 'TR'),
        Locale('en', 'US'),
      ],
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB), // Modern blue
          brightness: Brightness.light,
        ).copyWith(
          primary: const Color(0xFF2563EB),
          secondary: const Color(0xFF3B82F6),
          surface: Colors.white,
          surfaceContainerHighest: const Color(0xFFF8FAFC),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(
              color: Colors.grey.shade200,
              width: 1,
            ),
          ),
          shadowColor: Colors.black.withValues(alpha: 0.08),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFF2563EB), width: 2),
          ),
          filled: true,
          fillColor: Colors.grey.shade50,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            backgroundColor: const Color(0xFF2563EB),
            foregroundColor: Colors.white,
          ),
        ),
        appBarTheme: AppBarTheme(
          elevation: 0,
          centerTitle: false,
          scrolledUnderElevation: 0,
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF1E293B),
          surfaceTintColor: Colors.transparent,
          titleTextStyle: const TextStyle(
            color: Color(0xFF1E293B),
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        tabBarTheme: TabBarThemeData(
          labelColor: const Color(0xFF2563EB),
          unselectedLabelColor: Colors.grey.shade600,
          indicatorSize: TabBarIndicatorSize.tab,
          indicator: UnderlineTabIndicator(
            borderSide: const BorderSide(
              width: 3,
              color: Color(0xFF2563EB),
            ),
            insets: const EdgeInsets.symmetric(horizontal: 16),
          ),
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
          unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 14,
          ),
        ),
        textTheme: const TextTheme(
          headlineLarge: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            letterSpacing: -1,
            color: Color(0xFF1E293B),
          ),
          titleLarge: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            color: Color(0xFF1E293B),
          ),
          bodyLarge: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w400,
            color: Color(0xFF475569),
          ),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3B82F6), // Lighter blue for dark mode
          brightness: Brightness.dark,
        ).copyWith(
          primary: const Color(0xFF3B82F6),
          secondary: const Color(0xFF60A5FA),
          surface: const Color(0xFF1E293B),
          surfaceContainerHighest: const Color(0xFF334155),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(
              color: Colors.grey.shade800,
              width: 1,
            ),
          ),
          shadowColor: Colors.black.withValues(alpha: 0.5),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.grey.shade700),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.grey.shade700),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 2),
          ),
          filled: true,
          fillColor: const Color(0xFF334155),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            backgroundColor: const Color(0xFF3B82F6),
            foregroundColor: Colors.white,
          ),
        ),
        appBarTheme: AppBarTheme(
          elevation: 0,
          centerTitle: false,
          scrolledUnderElevation: 0,
          backgroundColor: const Color(0xFF1E293B),
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        tabBarTheme: TabBarThemeData(
          labelColor: const Color(0xFF3B82F6),
          unselectedLabelColor: Colors.grey.shade400,
          indicatorSize: TabBarIndicatorSize.tab,
          indicator: UnderlineTabIndicator(
            borderSide: const BorderSide(
              width: 3,
              color: Color(0xFF3B82F6),
            ),
            insets: const EdgeInsets.symmetric(horizontal: 16),
          ),
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
          unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 14,
          ),
        ),
        textTheme: const TextTheme(
          headlineLarge: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            letterSpacing: -1,
            color: Colors.white,
          ),
          titleLarge: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            color: Colors.white,
          ),
          bodyLarge: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w400,
            color: Color(0xFFCBD5E1),
          ),
        ),
      ),
      themeMode: _isDarkMode ? ThemeMode.dark : ThemeMode.light,
          initialRoute: '/login',
          routes: {
            '/login': (context) => const SplashLoginScreen(),
            '/home': (context) => const HomeScreen(),
            '/settings': (context) => SettingsScreen(
                  onThemeChanged: (isDark) {
                    (context.findAncestorStateOfType<_MyAppState>())
                        ?.toggleTheme(isDark);
                  },
                ),
            '/statistics': (context) {
              final route = ModalRoute.of(context);
              final args = route?.settings.arguments;
              
              // Eğer arguments UserProfile değilse veya null ise
              if (args == null || args is! UserProfile) {
                // Home screen'e geri dön
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  Navigator.of(context).pop();
                });
                return const Scaffold(
                  body: Center(
                    child: CircularProgressIndicator(),
                  ),
                );
              }
              
              return StatisticsScreen(currentUser: args);
            },
            '/passwordReset': (context) {
              final route = ModalRoute.of(context);
              final actionCode = route?.settings.arguments as String?;
              if (actionCode == null) {
                return const Scaffold(
                  body: Center(
                    child: Text('Geçersiz şifre sıfırlama linki'),
                  ),
                );
              }
              return PasswordResetScreen(actionCode: actionCode);
            },
          },
    );
  }
}


