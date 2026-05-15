import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import 'panic_alert_service.dart';

class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService _instance = PushNotificationService._();
  factory PushNotificationService() => _instance;

  static const _table = 'push_notification_tokens';

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final SupabaseClient _supabase = Supabase.instance.client;

  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<String>? _tokenRefreshSubscription;
  bool _initialized = false;

  static Future<void> handleBackgroundMessage(RemoteMessage message) async {
    final payload = _payloadFromMessage(message);
    if (payload == null) {
      return;
    }

    await PanicAlertService().initialize();
    await PanicAlertService().triggerIncomingAlert(
      payload,
      showLocalNotification: false,
    );
  }

  Future<void> initialize(GlobalKey<NavigatorState> navigatorKey) async {
    if (_initialized) {
      return;
    }

    await _authSubscription?.cancel();
    await _tokenRefreshSubscription?.cancel();
    try {
      await _messaging.setAutoInitEnabled(true);
      await _messaging.requestPermission(
          alert: true, badge: true, sound: true);
    } catch (e) {
      debugPrint('Firebase Messaging setup failed: $e');
    }
    await PanicAlertService().initialize(navigatorKey);

    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleOpenedMessage);

    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleOpenedMessage(initialMessage);
    }

    if (FirebaseAuth.instance.currentUser != null) {
      await _syncCurrentToken();
    }

    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        _syncCurrentToken();
      }
    });

    _tokenRefreshSubscription = _messaging.onTokenRefresh.listen((token) {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if ((userId ?? '').isEmpty) {
        return;
      }
      _upsertToken(userId!, token);
    });

    _initialized = true;
  }

  Future<void> _syncCurrentToken() async {
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if ((userId ?? '').isEmpty) {
        return;
      }

      final token = await _messaging.getToken();
      if ((token ?? '').isEmpty) {
        return;
      }

      await _upsertToken(userId!, token!);
    } catch (e) {
      debugPrint('FCM token sync failed: $e');
    }
  }

  Future<void> _upsertToken(String userId, String token) async {
    try {
      await _supabase.from(_table).upsert({
        'user_id': userId,
        'fcm_token': token,
        'platform': defaultTargetPlatform.name,
        'updated_at': DateTime.now().toIso8601String(),
        'last_seen_at': DateTime.now().toIso8601String(),
      }, onConflict: 'fcm_token');
    } catch (error) {
      // Log only a generic message to avoid leaking sensitive error details
      debugPrint('FCM token sync failed');
    }
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final payload = _payloadFromMessage(message);
    if (payload == null) {
      return;
    }
    await PanicAlertService().triggerIncomingAlert(payload);
  }

  void _handleOpenedMessage(RemoteMessage message) {
    final payload = _payloadFromMessage(message);
    if (payload == null) {
      return;
    }
    PanicAlertService().openSosInbox();
  }

  static PanicAlertPayload? _payloadFromMessage(RemoteMessage message) {
    final data = message.data;
    final type = (data['type'] ?? '').toString();
    if (type != 'sos_alert') {
      return null;
    }
    return PanicAlertPayload.fromMap(data);
  }
}
