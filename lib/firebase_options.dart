import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions are not configured for web.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not configured for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyD9buK2I-YLswMSMgx1p1R0qzc7m2C8FFM',
    appId: '1:445431980577:android:4b0c787af73eabc3c3f960',
    messagingSenderId: '445431980577',
    projectId: 'okeyix-cf7b4',
    storageBucket: 'okeyix-cf7b4.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAgA2kisRwrmwFIKMY1LJr7Sa1a3hW-P9o',
    appId: '1:445431980577:ios:488f00b9d026798bc3f960',
    messagingSenderId: '445431980577',
    projectId: 'okeyix-cf7b4',
    storageBucket: 'okeyix-cf7b4.firebasestorage.app',
    iosBundleId: 'com.okeyix.game',
  );
}

