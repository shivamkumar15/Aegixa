import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'auth_gate.dart';
import 'firebase_options.dart';
import 'screens/panic_overlay_screen.dart';
import 'theme_mode_scope.dart';
import 'screens/app_permissions_screen.dart';
import 'services/push_notification_service.dart';
import 'services/revenuecat_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://ilwxanuvttrhxkgmaphq.supabase.co',
    anonKey: 'sb_publishable_NL5o0d8iVuxi3yUXcZJ6rQ_mOvr9JqQ',
  );
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await RevenueCatService.initialize();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  runApp(const AegixaApp());
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
  await PushNotificationService.handleBackgroundMessage(message);
}

@pragma('vm:entry-point')
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PanicOverlayApp());
}

class AegixaApp extends StatefulWidget {
  const AegixaApp({super.key});

  @override
  State<AegixaApp> createState() => _AegixaAppState();
}

class _AegixaAppState extends State<AegixaApp> {
  static const _themeModePrefsKey = 'theme_mode';
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  bool _permissionsReady = false;
  final ValueNotifier<ThemeMode> _themeMode =
      ValueNotifier<ThemeMode>(ThemeMode.system);

  @override
  void initState() {
    super.initState();
    _loadStartupState();
    _themeMode.addListener(_persistThemeMode);
    if (Firebase.apps.isNotEmpty) {
      PushNotificationService().initialize(_navigatorKey);
    }
  }

  Future<void> _loadStartupState() async {
    final prefs = await SharedPreferences.getInstance();
    final savedValue = prefs.getString(_themeModePrefsKey);
    final permissionsReady =
        prefs.getBool(AppPermissionsScreen.permissionsPrefsKey) ?? false;
    final savedMode =
        savedValue == null ? null : _themeModeFromString(savedValue);

    if (!mounted) {
      return;
    }

    if (savedMode != null) {
      _themeMode.value = savedMode;
    }
    setState(() {
      _permissionsReady = permissionsReady;
    });
  }

  @override
  void dispose() {
    _themeMode.removeListener(_persistThemeMode);
    _themeMode.dispose();
    super.dispose();
  }

  Future<void> _persistThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModePrefsKey, _themeMode.value.name);
  }

  ThemeMode? _themeModeFromString(String value) {
    switch (value) {
      case 'system':
        return ThemeMode.system;
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return null;
    }
  }

  ThemeData _buildLightTheme() {
    const primary = Color(0xFFF71180);
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: const Color(0xFFF8FAFC),
      colorScheme: const ColorScheme.light(
        primary: primary,
        secondary: primary,
        surface: Colors.white,
        onSurface: Color(0xFF0F172A),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primary, width: 1.4),
        ),
      ),
      fontFamily: 'Poppins',
    );
  }

  ThemeData _buildDarkTheme() {
    const primary = Color(0xFFF71180);
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: Colors.black,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: primary,
        surface: Color(0xFF0A0A0A),
        onSurface: Color(0xFFF5F5F5),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF101010),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF2A2A2A)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF2A2A2A)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primary, width: 1.4),
        ),
      ),
      fontFamily: 'Poppins',
    );
  }

  @override
  Widget build(BuildContext context) {
    return ThemeModeScope(
      notifier: _themeMode,
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: _themeMode,
        builder: (context, mode, _) {
          return MaterialApp(
            title: 'Aegixa',
            debugShowCheckedModeBanner: false,
            navigatorKey: _navigatorKey,
            themeMode: mode,
            theme: _buildLightTheme(),
            darkTheme: _buildDarkTheme(),
            home: _permissionsReady
                ? const AuthGate()
                : AppPermissionsScreen(
                    onCompleted: () {
                      if (!mounted) {
                        return;
                      }
                      setState(() {
                        _permissionsReady = true;
                      });
                    },
                  ),
          );
        },
      ),
    );
  }
}
