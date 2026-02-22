/// Firebase yapılandırma dosyası
///
/// NOT: Bu dosya placeholder değerler içerir.
/// Gerçek Firebase yapılandırması için:
///
/// 1. Firebase Console'da proje oluşturun
/// 2. Flutter projesini Firebase'e bağlayın:
///    flutter pub global activate flutterfire_cli
///    flutterfire configure
///
/// Bu komut bu dosyayı otomatik olarak güncelleyecektir.
library;

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
    apiKey: 'AIzaSyDTfXnbxbQtSc83n5tXlU292VPzU0Q0Kws',
    appId: '1:7040117025:android:4621f797b9191b472ab660',
    messagingSenderId: '7040117025',
    projectId: 'manage-d9a18',
    storageBucket: 'manage-d9a18.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDTfXnbxbQtSc83n5tXlU292VPzU0Q0Kws',
    appId: '1:7040117025:ios:4621f797b9191b472ab660',
    messagingSenderId: '7040117025',
    projectId: 'manage-d9a18',
    storageBucket: 'manage-d9a18.firebasestorage.app',
    iosBundleId: 'com.revium.management',
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDTfXnbxbQtSc83n5tXlU292VPzU0Q0Kws',
    appId: '1:7040117025:web:4621f797b9191b472ab660',
    messagingSenderId: '7040117025',
    projectId: 'manage-d9a18',
    authDomain: 'manage-d9a18.firebaseapp.com',
    storageBucket: 'manage-d9a18.firebasestorage.app',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyDTfXnbxbQtSc83n5tXlU292VPzU0Q0Kws',
    appId: '1:7040117025:android:4621f797b9191b472ab660',
    messagingSenderId: '7040117025',
    projectId: 'manage-d9a18',
    storageBucket: 'manage-d9a18.firebasestorage.app',
  );
}

