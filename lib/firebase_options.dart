import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

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
        return macos;
      case TargetPlatform.windows:
        throw UnsupportedError('No Firebase options for Windows.');
      case TargetPlatform.linux:
        throw UnsupportedError('No Firebase options for Linux.');
      case TargetPlatform.fuchsia:
        throw UnsupportedError('No Firebase options for Fuchsia.');
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDsRytIRtopo2SB7JO2KprlaBOpi-8q068',
    appId: '1:804749289846:web:8b50a5761469483b923257',
    messagingSenderId: '804749289846',
    projectId: 'marcopesca-vacaciones-2026',
    authDomain: 'marcopesca-vacaciones-2026.firebaseapp.com',
    storageBucket: 'marcopesca-vacaciones-2026.firebasestorage.app',
    measurementId: 'G-5N5ZYP1846',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBjnIwZAx7ya72UnkPVkRgJiIL_BFIi200',
    appId: '1:804749289846:android:b4d8fb00a348ad75923257',
    messagingSenderId: '804749289846',
    projectId: 'marcopesca-vacaciones-2026',
    storageBucket: 'marcopesca-vacaciones-2026.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'TODO',
    appId: 'TODO',
    messagingSenderId: '804749289846',
    projectId: 'marcopesca-vacaciones-2026',
    storageBucket: 'marcopesca-vacaciones-2026.firebasestorage.app',
    iosBundleId: 'com.marcopesca.vacaciones',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'TODO',
    appId: 'TODO',
    messagingSenderId: '804749289846',
    projectId: 'marcopesca-vacaciones-2026',
    storageBucket: 'marcopesca-vacaciones-2026.firebasestorage.app',
    iosBundleId: 'com.marcopesca.vacaciones',
  );
}
