import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    as notifications;
import 'package:flutter_overlay_window/flutter_overlay_window.dart' as overlay;
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/sos_alerts_screen.dart';

class PanicAlertPayload {
  const PanicAlertPayload({
    required this.alertId,
    required this.sessionId,
    required this.senderName,
    required this.alertMessage,
  });

  final int alertId;
  final String sessionId;
  final String senderName;
  final String alertMessage;

  factory PanicAlertPayload.fromMap(Map<String, dynamic> map) {
    return PanicAlertPayload(
      alertId:
          int.tryParse((map['alertId'] ?? map['alert_id'] ?? '').toString()) ??
              0,
      sessionId: (map['sessionId'] ?? map['session_id'] ?? '').toString(),
      senderName:
          (map['senderName'] ?? map['sender_name'] ?? 'Emergency contact')
              .toString(),
      alertMessage: (map['alertMessage'] ??
              map['alert_message'] ??
              'PANIC ALERT received. Open Sailor immediately.')
          .toString(),
    );
  }
}

class PanicAlertService {
  PanicAlertService._();

  static final PanicAlertService _instance = PanicAlertService._();
  factory PanicAlertService() => _instance;

  static const _handledAlertIdsKey = 'panic_alert_handled_ids_v1';
  static const notificationChannelId = 'panic_sos_alerts';
  static const _notificationChannelName = 'Panic SOS Alerts';

  final notifications.FlutterLocalNotificationsPlugin _notifications =
      notifications.FlutterLocalNotificationsPlugin();
  final Set<int> _handledAlertIds = <int>{};

  GlobalKey<NavigatorState>? _navigatorKey;
  Timer? _alarmAutoStopTimer;
  bool _initialized = false;
  bool _dialogVisible = false;

  Future<void> initialize([GlobalKey<NavigatorState>? navigatorKey]) async {
    _navigatorKey = navigatorKey ?? _navigatorKey;
    if (_initialized) {
      return;
    }

    await _loadHandledAlertIds();
    await _initializeNotifications();
    _initialized = true;
  }

  Future<void> _initializeNotifications() async {
    const settings = notifications.InitializationSettings(
      android: notifications.AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      ),
    );

    await _notifications.initialize(
      settings,
      onDidReceiveNotificationResponse: (_) => openSosInbox(),
    );

    final androidImplementation =
        _notifications.resolvePlatformSpecificImplementation<
            notifications.AndroidFlutterLocalNotificationsPlugin>();
    await androidImplementation?.createNotificationChannel(
      const notifications.AndroidNotificationChannel(
        notificationChannelId,
        _notificationChannelName,
        description:
            'Emergency panic alerts for incoming SOS messages and live location updates.',
        importance: notifications.Importance.max,
        playSound: true,
        enableVibration: true,
      ),
    );
    await androidImplementation?.requestNotificationsPermission();
    await androidImplementation?.requestFullScreenIntentPermission();
  }

  Future<void> triggerIncomingAlert(
    PanicAlertPayload payload, {
    bool showLocalNotification = true,
  }) async {
    if (payload.alertId > 0 && _handledAlertIds.contains(payload.alertId)) {
      return;
    }
    if (payload.alertId > 0) {
      _handledAlertIds.add(payload.alertId);
      await _persistHandledAlertIds();
    }

    if (showLocalNotification) {
      await _showNotification(payload);
    }
    _startAlarmSound();
    await _showOverlay(payload);
    await _showForegroundDialog(payload);
  }

  Future<void> _showNotification(PanicAlertPayload payload) async {
    const details = notifications.NotificationDetails(
      android: notifications.AndroidNotificationDetails(
        notificationChannelId,
        _notificationChannelName,
        channelDescription:
            'Emergency panic alerts for incoming SOS messages and live location updates.',
        importance: notifications.Importance.max,
        priority: notifications.Priority.max,
        category: notifications.AndroidNotificationCategory.alarm,
        visibility: notifications.NotificationVisibility.public,
        fullScreenIntent: true,
        playSound: true,
        enableVibration: true,
        ticker: 'PANIC ALERT',
      ),
    );

    await _notifications.show(
      payload.alertId == 0
          ? DateTime.now().millisecondsSinceEpoch
          : payload.alertId,
      'PANIC ALERT',
      '${payload.senderName} sent an emergency SOS. Open Sailor now.',
      details,
      payload: 'sos_inbox',
    );
  }

  void _startAlarmSound() {
    FlutterRingtonePlayer().stop();
    FlutterRingtonePlayer().play(
      android: AndroidSounds.alarm,
      ios: IosSounds.alarm,
      looping: true,
      volume: 1,
      asAlarm: true,
    );
    _alarmAutoStopTimer?.cancel();
    _alarmAutoStopTimer = Timer(
      const Duration(seconds: 30),
      FlutterRingtonePlayer().stop,
    );
  }

  Future<void> _showOverlay(PanicAlertPayload payload) async {
    if (!Platform.isAndroid) {
      return;
    }

    final hasPermission =
        await overlay.FlutterOverlayWindow.isPermissionGranted() ||
            await Permission.systemAlertWindow.isGranted;
    if (!hasPermission) {
      return;
    }

    try {
      await overlay.FlutterOverlayWindow.closeOverlay();
    } catch (_) {
      // Ignore when there is no active overlay.
    }

    await overlay.FlutterOverlayWindow.showOverlay(
      enableDrag: false,
      alignment: overlay.OverlayAlignment.center,
      height: 420,
      width: overlay.WindowSize.matchParent,
      visibility: overlay.NotificationVisibility.visibilityPublic,
      flag: overlay.OverlayFlag.focusPointer,
      overlayTitle: 'PANIC ALERT',
      overlayContent: 'Sailor emergency SOS alert',
    );

    await overlay.FlutterOverlayWindow.shareData(
      jsonEncode({
        'senderName': payload.senderName,
        'alertMessage': payload.alertMessage,
      }),
    );
  }

  Future<void> _showForegroundDialog(PanicAlertPayload payload) async {
    final navigator = _navigatorKey?.currentState;
    final context = navigator?.overlay?.context;
    if (context == null || _dialogVisible) {
      return;
    }

    _dialogVisible = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('PANIC ALERT'),
          content: Text(
            '${payload.senderName} sent an emergency SOS. Open the SOS inbox now to view live location and emergency details.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                stopActiveAlarm();
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Dismiss'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                openSosInbox();
              },
              child: const Text('Open Inbox'),
            ),
          ],
        );
      },
    );
    _dialogVisible = false;
  }

  void openSosInbox() {
    stopActiveAlarm();
    final navigator = _navigatorKey?.currentState;
    if (navigator == null) {
      return;
    }

    navigator.push(
      MaterialPageRoute(builder: (_) => const SosAlertsScreen()),
    );
  }

  void stopActiveAlarm() {
    _alarmAutoStopTimer?.cancel();
    FlutterRingtonePlayer().stop();
    if (Platform.isAndroid) {
      overlay.FlutterOverlayWindow.closeOverlay();
    }
  }

  Future<void> _loadHandledAlertIds() async {
    final prefs = await SharedPreferences.getInstance();
    final values = prefs.getStringList(_handledAlertIdsKey) ?? const [];
    _handledAlertIds
      ..clear()
      ..addAll(values.map(int.tryParse).whereType<int>());
  }

  Future<void> _persistHandledAlertIds() async {
    final prefs = await SharedPreferences.getInstance();
    final entries = _handledAlertIds.toList()..sort();
    final trimmed =
        entries.length <= 200 ? entries : entries.sublist(entries.length - 200);
    await prefs.setStringList(
      _handledAlertIdsKey,
      trimmed.map((value) => value.toString()).toList(),
    );
  }
}
