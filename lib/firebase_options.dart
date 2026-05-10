// Auto-generated Firebase options from google-services.json
// Project: protego-51833

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions have not been configured for web - '
        'you can reconfigure this by running the FlutterFire CLI again.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for macOS - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for Windows - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for Linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDrIrPX0-FjRO_kdYPffUA3wxLVlgsW9C8',
    appId: '1:820900289964:android:ed76023b42f80eec406e09',
    messagingSenderId: '820900289964',
    projectId: 'protego-51833',
    storageBucket: 'protego-51833.firebasestorage.app',
  );

  // iOS: Add your iOS app to Firebase Console and fill these in,
  // or run `flutterfire configure` to auto-generate.
  // TODO: Replace with actual iOS appId from Firebase Console.
  // The current value is the Android appId (copy-paste bug).
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDrIrPX0-FjRO_kdYPffUA3wxLVlgsW9C8',
    appId: '1:820900289964:ios:REPLACE_WITH_IOS_APP_ID',
    messagingSenderId: '820900289964',
    projectId: 'protego-51833',
    storageBucket: 'protego-51833.firebasestorage.app',
    iosBundleId: 'com.example.aegixa',
  );
}
