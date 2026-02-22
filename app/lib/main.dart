/// Ana uygulama dosyası
/// Firebase başlatma ve routing yönetimi
library;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'firebase_options.dart';
import 'screens/splash_login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/password_reset_screen.dart';
import 'screens/calculations_screen.dart';
import 'screens/fuarlar_screen.dart';
import 'utils/app_logger.dart';
import 'models/user_profile.dart'; // UserProfile modeli eklendi

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Uygulama kapalıyken veya arka plandayken gelen mesajlar burada yakalanır.
  // Bu fonksiyonun EN ÜSTTE (library level) olması zorunludur.
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Arka plan logu çok belirgin olsun
  print('=========================================');
  print('[FCM_RECEIVE_BG] Arka plan mesajı: ${message.messageId}');
  print('=========================================');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase'i başlat
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    
    // Background message handler kaydı
    if (!kIsWeb) {
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
      AppLogger.success('FCM Background Handler kaydedildi');
    }
    
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

  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  static final GlobalKey<ScaffoldMessengerState> messengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  bool _isDarkMode = false;
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  static const AndroidNotificationDetails _androidNotificationDetails =
      AndroidNotificationDetails(
    'high_importance_channel_v3',
    'Fuar Hatırlatmaları (Yüksek)',
    channelDescription: 'Fuar ve önemli hatırlatmalar için bildirim kanalı',
    importance: Importance.max,
    priority: Priority.max,
    ticker: 'Fuar Hatırlatması',
    showWhen: true,
    category: AndroidNotificationCategory.message,
    icon: 'ic_notification', // launcher_icon yerine ic_notification
  );

  @override
  void initState() {
    super.initState();
    _loadThemePreference();
    WidgetsBinding.instance.addObserver(this);
    _checkInitialLink();
    _initLocalNotificationsAndForegroundListener();
  }

  /// Yerel bildirimleri başlatır; ön planda gelen FCM'i sistem bildirimi olarak gösterir. Hata olursa uygulama kapanmasın.
  Future<void> _initLocalNotificationsAndForegroundListener() async {
    if (kIsWeb) return;
    try {
      const android = AndroidInitializationSettings('ic_notification'); // launcher_icon yerine ic_notification
      const initSettings = InitializationSettings(android: android);
      
      // Android 8.0+ için bildirim kanalını açıkça oluştur
      final androidPlatform = _localNotifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlatform != null) {
        await androidPlatform.createNotificationChannel(
          const AndroidNotificationChannel(
            'high_importance_channel_v3',
            'Fuar Hatırlatmaları (Yüksek)',
            description: 'Fuar ve önemli hatırlatmalar için bildirim kanalı',
            importance: Importance.max, // Kanal bazında da MAX
            playSound: true,
            enableVibration: true,
          ),
        );
      }

      final initResult = await _localNotifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (_) {
          // Bildirime tıklanınca sadece uygulamayı öne getir; ek işlem yapma (crash önleme)
        },
      );
      print('[FCM_INIT] Yerel bildirimler başlatıldı: $initResult');
      
      // Ön planda bildirim ayarlarını zorla
      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        print('=========================================');
        print('[FCM_RECEIVE_FG] Ön plan mesajı alındı: ${message.messageId}');
        print('[FCM_DATA] Veri: ${message.data}');
        print('[FCM_NOTIF] Başlık: ${message.notification?.title}, Gövde: ${message.notification?.body}');
        print('=========================================');
        try {
          // Hem notification hem de data alanlarını kontrol et
          final title = message.notification?.title ?? message.data['title'] ?? 'Fuar Bildirimi';
          final body = message.notification?.body ?? message.data['body'] ?? 'Yeni bir güncelleme var.';
          
          final id = (message.hashCode & 0x7FFFFFFF).clamp(1, 2147483647);
          _localNotifications.show(
            id,
            title,
            body,
            const NotificationDetails(android: _androidNotificationDetails),
          );
          AppLogger.success('Yerel bildirim gösterildi: $title');
        } catch (e) {
          AppLogger.error('Bildirim gösterilemedi: $e');
        }
      });
    } catch (e) {
      debugPrint('Yerel bildirimler başlatılamadı: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  static const MethodChannel _channel = MethodChannel('com.revium.management/deep_link');

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
      navigatorKey: MyApp.navigatorKey,
      scaffoldMessengerKey: MyApp.messengerKey,
      title: 'Revium Gider',
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
        appBarTheme: const AppBarTheme(
          elevation: 0,
          centerTitle: false,
          scrolledUnderElevation: 0,
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF1E293B),
          surfaceTintColor: Colors.transparent,
          titleTextStyle: TextStyle(
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
          indicator: const UnderlineTabIndicator(
            borderSide: BorderSide(
              width: 3,
              color: Color(0xFF2563EB),
            ),
            insets: EdgeInsets.symmetric(horizontal: 16),
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
        appBarTheme: const AppBarTheme(
          elevation: 0,
          centerTitle: false,
          scrolledUnderElevation: 0,
          backgroundColor: Color(0xFF1E293B),
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: TextStyle(
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
          indicator: const UnderlineTabIndicator(
            borderSide: BorderSide(
              width: 3,
              color: Color(0xFF3B82F6),
            ),
            insets: EdgeInsets.symmetric(horizontal: 16),
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
            '/fuarlar': (context) => const FuarlarScreen(),
            '/calculations': (context) {
              final route = ModalRoute.of(context);
              final args = route?.settings.arguments;
              
              // Eğer arguments UserProfile değilse veya null ise
              if (args == null || args is! UserProfile) {
                // Home screen'e geri dön (güvenli şekilde)
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (context.mounted && Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  }
                });
                return const Scaffold(
                  body: Center(
                    child: CircularProgressIndicator(),
                  ),
                );
              }
              
              return CalculationsScreen(currentUser: args);
            },
          },
    );
  }
}


