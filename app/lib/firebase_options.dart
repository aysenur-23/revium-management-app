/**
 * Firebase yapılandırma dosyası
 * 
 * NOT: Bu dosya placeholder değerler içerir.
 * Gerçek Firebase yapılandırması için:
 * 
 * 1. Firebase Console'da proje oluşturun
 * 2. Flutter projesini Firebase'e bağlayın:
 *    flutter pub global activate flutterfire_cli
 *    flutterfire configure
 * 
 * Bu komut bu dosyayı otomatik olarak güncelleyecektir.
 */

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
///
/// Example:
/// ```dart
/// import 'firebase_options.dart';
/// // ...
/// await Firebase.initializeApp(
///   options: DefaultFirebaseOptions.currentPlatform,
/// );
/// ```
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for macos - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.windows:
        // Windows için placeholder - gerçek değerler flutterfire configure ile eklenecek
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBkI-dyxhrWAKS5LwFkD7Tj1y5ki5iftGw',
    appId: '1:261430698056:android:bc90a596f65b2095e2f87d',
    messagingSenderId: '261430698056',
    projectId: 'management-app0',
    storageBucket: 'management-app0.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAQ5VSriUfXn7rhHP8x_HkjM4qE5i5QIHo',
    appId: '1:261430698056:ios:37f189dcaec72112e2f87d',
    messagingSenderId: '261430698056',
    projectId: 'management-app0',
    storageBucket: 'management-app0.firebasestorage.app',
    iosBundleId: 'com.revium.management',
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBkI-dyxhrWAKS5LwFkD7Tj1y5ki5iftGw',
    appId: '1:261430698056:web:bc90a596f65b2095e2f87d',
    messagingSenderId: '261430698056',
    projectId: 'management-app0',
    authDomain: 'management-app0.firebaseapp.com',
    storageBucket: 'management-app0.firebasestorage.app',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyBkI-dyxhrWAKS5LwFkD7Tj1y5ki5iftGw',
    appId: '1:261430698056:android:bc90a596f65b2095e2f87d',
    messagingSenderId: '261430698056',
    projectId: 'management-app0',
    storageBucket: 'management-app0.firebasestorage.app',
  );
}

