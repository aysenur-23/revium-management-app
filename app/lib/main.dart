/**
 * Ana uygulama dosyası
 * Firebase başlatma ve routing yönetimi
 */

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'firebase_options.dart';
import 'services/local_storage_service.dart';
import 'screens/splash_login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/statistics_screen.dart';
import 'models/user_profile.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase'i başlat
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('✅ Firebase başarıyla başlatıldı');
  } on FirebaseException catch (e) {
    debugPrint('❌ Firebase başlatma hatası (FirebaseException): ${e.code} - ${e.message}');
  } catch (e) {
    debugPrint('❌ Firebase başlatma hatası: $e');
    // Firebase başlatılamazsa da uygulama çalışmaya devam eder
    // Ancak Firestore işlemleri başarısız olacaktır
  }

  // intl paketini Türkçe locale için başlat (web'de farklı şekilde)
  if (!kIsWeb) {
    // Mobil platformlarda locale data'yı yükle
    try {
      await initializeDateFormatting('tr_TR', null);
      debugPrint('✅ intl locale başarıyla başlatıldı');
    } catch (e) {
      debugPrint('⚠️ intl locale başlatma hatası: $e');
    }
  } else {
    // Web'de locale data otomatik yüklenir, manuel yükleme gerekmez
    debugPrint('✅ Web platformu - locale data otomatik yüklenecek');
  }

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
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
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          filled: true,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          filled: true,
        ),
      ),
      themeMode: _isDarkMode ? ThemeMode.dark : ThemeMode.light,
          initialRoute: '/',
          routes: {
            '/': (context) => const InitialRoute(),
            '/login': (context) => const SplashLoginScreen(),
            '/home': (context) => const HomeScreen(),
            '/settings': (context) => SettingsScreen(
                  onThemeChanged: (isDark) {
                    (context.findAncestorStateOfType<_MyAppState>())
                        ?.toggleTheme(isDark);
                  },
                ),
            '/statistics': (context) {
              final args = ModalRoute.of(context)!.settings.arguments as UserProfile?;
              if (args == null) {
                return const Scaffold(
                  body: Center(child: Text('Kullanıcı bilgisi bulunamadı')),
                );
              }
              return StatisticsScreen(currentUser: args);
            },
          },
    );
  }
}

/// İlk açılışta kullanıcı kontrolü yapan widget
class InitialRoute extends StatefulWidget {
  const InitialRoute({super.key});

  @override
  State<InitialRoute> createState() => _InitialRouteState();
}

class _InitialRouteState extends State<InitialRoute> {
  bool _isChecking = true;

  @override
  void initState() {
    super.initState();
    _checkUser();
  }

  Future<void> _checkUser() async {
    try {
      final user = await LocalStorageService.getSavedUser();
      if (mounted) {
        if (user != null) {
          Navigator.of(context).pushReplacementNamed('/home');
        } else {
          Navigator.of(context).pushReplacementNamed('/login');
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/login');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isChecking = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: CircularProgressIndicator(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

