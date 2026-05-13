import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart' as latlng;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/auth_service.dart';
import '../services/device_settings_service.dart';
import '../services/emergency_contacts_service.dart';
import '../services/sos_alert_service.dart';
import '../services/sos_recording_service.dart';
import '../services/username_service.dart';
import '../services/revenuecat_service.dart';
import '../theme_mode_scope.dart';
import '../auth_gate.dart';
import 'emergency_contact_editor_sheet.dart';
import 'battery_optimization_guide_screen.dart';
import 'sos_alerts_screen.dart';
import 'sos_recordings_screen.dart';

import '../ui_components.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.initialIndex = 0,
    this.showOfflineBanner = false,
  });

  final int initialIndex;
  final bool showOfflineBanner;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const _autoVideoRecordKey = 'sos_auto_video_record';
  static const _autoVoiceRecordKey = 'sos_auto_voice_record';
  static const _sosHoldDurationKey = 'sos_hold_duration';
  static const _vibrationOnSosKey = 'sos_vibration_on_trigger';
  static const _hardwareSosShortcutKey = 'hardware_sos_shortcut_enabled';
  static const _activeSosSessionKey = 'active_sos_session_id';
  static const MethodChannel _hardwareSosChannel =
      MethodChannel('aegixa/hardware_sos');

  late int _currentIndex;
  final SosRecordingService _sosRecordingService = SosRecordingService();
  final SosAlertService _sosAlertService = SosAlertService();
  bool _isSosActive = false;
  String? _activeSosRecordingPath;
  String? _activeSosVideoPath;
  String? _activeSosSessionId;
  bool _autoVideoRecord = false;
  bool _autoVoiceRecord = true;
  bool _vibrationOnSos = true;
  bool _hardwareSosShortcutEnabled = true;
  bool _isHardwareSosPermissionEnabled = false;
  bool _isStoppingSos = false;
  int _sosHoldDuration = 2;
  String? _navProfilePhotoPath;
  DateTime? _lastBackPressedAt;
  StreamSubscription<Position>? _sosLocationSubscription;
  Position? _lastSharedSosPosition;
  DateTime? _lastSharedSosAt;
  Timer? _offlineBannerProbeTimer;
  bool _showOfflineBanner = false;

  static const _titles = <String>[
    'Home',
    'Live Map',
    'Profile',
    'Settings',
  ];

  static const _navItems = <_BottomNavItem>[
    _BottomNavItem(
      icon: Icons.house_outlined,
      activeIcon: Icons.house_rounded,
      label: 'Home',
    ),
    _BottomNavItem(
      icon: Icons.explore_outlined,
      activeIcon: Icons.explore_rounded,
      label: 'Live Map',
    ),
    _BottomNavItem(
      icon: Icons.account_circle_outlined,
      activeIcon: Icons.account_circle,
      label: 'Profile',
    ),
    _BottomNavItem(
      icon: Icons.tune_outlined,
      activeIcon: Icons.tune_rounded,
      label: 'Settings',
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentIndex = widget.initialIndex;
    _showOfflineBanner = widget.showOfflineBanner;
    _initializeHardwareSosShortcut();
    _loadSosPreferences();
    _loadNavProfilePhoto();
    _restoreSosStateIfNeeded();
    if (_showOfflineBanner) {
      _startOfflineBannerProbe();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hardwareSosChannel.setMethodCallHandler(null);
    _offlineBannerProbeTimer?.cancel();
    _sosLocationSubscription?.cancel();
    _sosRecordingService.disposeRecorder();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Reserved for future lifecycle handling
  }

  void _startOfflineBannerProbe() {
    _offlineBannerProbeTimer?.cancel();
    _offlineBannerProbeTimer = Timer.periodic(
      const Duration(seconds: 6),
      (_) async {
        if (!mounted || !_showOfflineBanner) {
          return;
        }
        final isOnline = await _hasInternetConnection();
        if (!mounted || !isOnline) {
          return;
        }
        setState(() {
          _showOfflineBanner = false;
        });
        _offlineBannerProbeTimer?.cancel();
        _offlineBannerProbeTimer = null;
      },
    );
  }

  Future<bool> _hasInternetConnection() async {
    try {
      final result = await InternetAddress.lookup('example.com');
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> _loadNavProfilePhoto() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();

    // Show cached photo immediately while we fetch the remote one.
    final cachedPath = (prefs.getString('profile_photo_$uid') ?? '').trim();
    if (cachedPath.isNotEmpty && mounted) {
      setState(() {
        _navProfilePhotoPath = cachedPath;
      });
    }

    // Then try to fetch the remote profile photo in background.
    try {
      final remoteProfile =
          await UsernameService().getPublicProfileForUserId(uid);
      final remotePath = (remoteProfile?.profilePhotoPath ?? '').trim();

      // Use remote path if available, otherwise keep the cached local path.
      final resolvedPath = remotePath.isNotEmpty ? remotePath : cachedPath;

      if (resolvedPath.isNotEmpty) {
        await prefs.setString('profile_photo_$uid', resolvedPath);
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _navProfilePhotoPath = resolvedPath.isEmpty ? null : resolvedPath;
      });
    } catch (_) {
      // Network error — keep using the cached photo (already set above).
    }
  }

  Future<void> _loadSosPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _autoVideoRecord = prefs.getBool(_autoVideoRecordKey) ?? false;
      _autoVoiceRecord = prefs.getBool(_autoVoiceRecordKey) ?? true;
      _vibrationOnSos = prefs.getBool(_vibrationOnSosKey) ?? true;
      _hardwareSosShortcutEnabled =
          prefs.getBool(_hardwareSosShortcutKey) ?? true;
      final hold = prefs.getInt(_sosHoldDurationKey) ?? 2;
      _sosHoldDuration = <int>{2, 5, 7}.contains(hold) ? hold : 2;
    });
    await _setHardwareSosShortcutEnabled(_hardwareSosShortcutEnabled);
    await _refreshHardwareSosPermissionStatus();
  }

  Future<void> _saveBoolPreference(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> _saveIntPreference(String key, int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key, value);
  }

  Future<void> _initializeHardwareSosShortcut() async {
    try {
      _hardwareSosChannel.setMethodCallHandler((call) async {
        if (call.method != 'onShortcutTriggered') {
          return;
        }
        if (!mounted || _isSosActive) {
          return;
        }
        await _handleSosActivated();
      });
    } catch (_) {}
  }

  Future<void> _setHardwareSosShortcutEnabled(bool enabled) async {
    try {
      await _hardwareSosChannel.invokeMethod('setEnabled', {
        'enabled': enabled,
      });
    } catch (_) {}
  }

  Future<void> _refreshHardwareSosPermissionStatus() async {
    try {
      final enabled = await _hardwareSosChannel.invokeMethod<bool>(
        'isAccessibilityEnabled',
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _isHardwareSosPermissionEnabled = enabled ?? false;
      });
    } catch (_) {}
  }

  Future<void> _startSosForegroundService() async {
    try {
      await _hardwareSosChannel.invokeMethod('startSosForegroundService');
    } catch (_) {}
  }

  Future<void> _persistActiveSosSession(String? sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    if ((sessionId ?? '').trim().isEmpty) {
      await prefs.remove(_activeSosSessionKey);
      return;
    }
    await prefs.setString(_activeSosSessionKey, sessionId!.trim());
  }

  Future<void> _restoreSosStateIfNeeded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedSessionId =
          (prefs.getString(_activeSosSessionKey) ?? '').trim();
      if (savedSessionId.isEmpty || !mounted) {
        return;
      }

      final serviceRunning = await _hardwareSosChannel
              .invokeMethod<bool>('isSosForegroundServiceRunning') ??
          false;

      if (!serviceRunning) {
        await prefs.remove(_activeSosSessionKey);
        return;
      }

      // Check if native recordings are still active from before app restart
      String? restoredAudioPath;
      String? restoredVideoPath;
      try {
        final status = await _hardwareSosChannel
            .invokeMapMethod<String, dynamic>('getNativeRecordingPaths');
        if (status != null) {
          if (status['audioActive'] == true) {
            restoredAudioPath = 'native_audio_active';
          }
          if (status['videoActive'] == true) {
            restoredVideoPath = 'native_video_active';
          }
        }
      } catch (_) {}

      setState(() {
        _isSosActive = true;
        _activeSosSessionId = savedSessionId;
        _activeSosRecordingPath = restoredAudioPath;
        _activeSosVideoPath = restoredVideoPath;
      });

      Position? initialPosition;
      try {
        initialPosition = await Geolocator.getLastKnownPosition();
      } catch (_) {
        initialPosition = null;
      }

      if (initialPosition == null) {
        try {
          initialPosition = await _getCurrentPositionWithOfflineFallback();
        } catch (_) {
          initialPosition = null;
        }
      }

      if (initialPosition != null) {
        await _startSosLocationSharing(savedSessionId, initialPosition);
      }
    } catch (_) {
      return;
    }
  }

  Future<void> _stopSosForegroundService() async {
    try {
      await _hardwareSosChannel.invokeMethod('stopSosForegroundService');
    } catch (_) {}
  }

  Future<void> _handleSosActivated() async {
    try {
      final contacts = await EmergencyContactsService().getContacts();
      if (contacts.isEmpty) {
        throw StateError(
            'Add at least one emergency contact before using SOS.');
      }

      final initialPosition = await _getSosPosition();
      final dispatch = await _sosAlertService.triggerAlerts(
        contacts: contacts,
        position: initialPosition,
        alertMessage: _buildSosAlertMessage(),
      );

      final shouldRecordVoice = _autoVoiceRecord || dispatch.deliveredCount > 0;
      final shouldRecordVideo = _autoVideoRecord || dispatch.deliveredCount > 0;
      bool audioStarted = false;
      bool videoStarted = false;
      if (_vibrationOnSos) {
        HapticFeedback.heavyImpact();
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _isSosActive = true;
        _activeSosRecordingPath =
            shouldRecordVoice ? 'native_audio_pending' : null;
        _activeSosVideoPath = shouldRecordVideo ? 'native_video_pending' : null;
        _activeSosSessionId = dispatch.sessionId;
      });
      await _persistActiveSosSession(dispatch.sessionId);
      await _startSosForegroundService();

      // Start native recordings via foreground service (survives app kill)
      if (shouldRecordVoice) {
        try {
          await _hardwareSosChannel.invokeMethod('startNativeAudioRecording');
          audioStarted = true;
        } catch (_) {
          audioStarted = false;
        }
      }

      if (shouldRecordVideo) {
        try {
          await _hardwareSosChannel.invokeMethod('startNativeVideoRecording');
          videoStarted = true;
        } catch (_) {
          videoStarted = false;
        }
      }

      if (mounted) {
        setState(() {
          _activeSosRecordingPath = audioStarted ? 'native_audio_active' : null;
          _activeSosVideoPath = videoStarted ? 'native_video_active' : null;
        });
      }

      await _startSosLocationSharing(dispatch.sessionId, initialPosition);
      if (!mounted) {
        return;
      }
      final activationDetails = _buildSosActivatedMessage(
        deliveredCount: dispatch.deliveredCount,
        skippedCount: dispatch.skippedCount,
        recordingStarted: audioStarted || videoStarted,
        pushDeliveredCount: dispatch.pushDeliveredCount,
        pushSkippedCount: dispatch.pushSkippedCount,
        pushErrorMessage: dispatch.pushErrorMessage,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Help is on the way. Stay calm and move to safety. $activationDetails',
          ),
          backgroundColor: Colors.red,
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Bad state: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _stopSos() async {
    if (_isStoppingSos || !_isSosActive) {
      return;
    }

    _isStoppingSos = true;
    final activeSessionId = _activeSosSessionId;
    final previousRecordingPath = _activeSosRecordingPath;
    final previousVideoPath = _activeSosVideoPath;

    if (mounted) {
      setState(() {
        _isSosActive = false;
        _activeSosSessionId = null;
      });
      unawaited(_persistActiveSosSession(null));
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Stopping SOS... finalizing safety logs.'),
          duration: Duration(seconds: 2),
        ),
      );
    }

    String? savedPath = previousRecordingPath;
    String? savedVideo = previousVideoPath;
    try {
      await _sosLocationSubscription?.cancel();
      _sosLocationSubscription = null;

      // Stop native audio recording via foreground service
      String? recordingPath;
      try {
        final isAudioActive = await _hardwareSosChannel
                .invokeMethod<bool>('isNativeAudioRecording') ??
            false;
        if (isAudioActive) {
          recordingPath = await _hardwareSosChannel
              .invokeMethod<String>('stopNativeAudioRecording');
        }
      } catch (_) {
        recordingPath = null;
      }

      // Stop native video recording via foreground service
      String? videoPath;
      try {
        final isVideoActive = await _hardwareSosChannel
                .invokeMethod<bool>('isNativeVideoRecording') ??
            false;
        if (isVideoActive) {
          videoPath = await _hardwareSosChannel
              .invokeMethod<String>('stopNativeVideoRecording');
        }
      } catch (_) {
        videoPath = null;
      }

      savedPath = recordingPath ?? previousRecordingPath;
      savedVideo = videoPath ?? previousVideoPath;

      // Save native recording entries to local database
      if (recordingPath != null) {
        try {
          await _sosRecordingService.saveNativeAudioEntry(recordingPath);
        } catch (_) {}
      }
      if (videoPath != null) {
        try {
          await _sosRecordingService.saveNativeVideoEntry(videoPath);
        } catch (_) {}
      }

      if (activeSessionId != null) {
        await _sosAlertService.resolveAlertSession(
          sessionId: activeSessionId,
          voiceRecordingPath: savedPath,
          videoRecordingPath: savedVideo,
        );
      }
    } finally {
      await _stopSosForegroundService();
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        setState(() {
          _activeSosRecordingPath = savedPath;
          _activeSosVideoPath = savedVideo;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _buildStopSosMessage(savedPath, savedVideo),
            ),
          ),
        );
      }
      _isStoppingSos = false;
    }
  }

  String _buildSosAlertMessage() {
    final user = FirebaseAuth.instance.currentUser;
    final name = (user?.displayName ?? '').trim();
    final email = (user?.email ?? '').trim();
    final label = name.isNotEmpty
        ? name
        : (email.isNotEmpty ? email.split('@').first : 'Aegixa user');
    return 'PANIC ALERT: $label may be in immediate danger. Emergency SOS has been triggered and live location sharing is active. Respond now.';
  }

  String _buildSosActivatedMessage({
    required int deliveredCount,
    required int skippedCount,
    required bool recordingStarted,
    required int pushDeliveredCount,
    required int pushSkippedCount,
    String? pushErrorMessage,
  }) {
    final recordingMessage = recordingStarted
        ? ' Emergency voice and video capture started for your contacts.'
        : '';
    final pushMessage = (pushErrorMessage ?? '').trim().isNotEmpty
        ? ' ${pushErrorMessage!.trim()}'
        : pushDeliveredCount > 0
            ? ' Panic notifications reached $pushDeliveredCount device${pushDeliveredCount == 1 ? '' : 's'}.'
            : pushSkippedCount > 0
                ? ' Some contacts have not opened Aegixa with notifications enabled yet, so panic push could not reach $pushSkippedCount device${pushSkippedCount == 1 ? '' : 's'}.'
                : '';
    if (skippedCount > 0) {
      return 'SOS sent to $deliveredCount contact${deliveredCount == 1 ? '' : 's'} in-app. $skippedCount contact${skippedCount == 1 ? ' is' : 's are'} not linked to Aegixa yet.$recordingMessage$pushMessage';
    }
    return 'SOS sent to $deliveredCount contact${deliveredCount == 1 ? '' : 's'} in-app.$recordingMessage$pushMessage';
  }

  Future<Position> _getSosPosition() async {
    final cached = await Geolocator.getLastKnownPosition();
    try {
      return await _getCurrentPositionWithOfflineFallback();
    } catch (_) {
      if (cached != null) {
        return cached;
      }
      rethrow;
    }
  }

  Future<Position> _getCurrentPositionWithOfflineFallback() async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          timeLimit: Duration(seconds: 8),
        ),
      );
    } catch (_) {
      return Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
        ),
      );
    }
  }

  Future<void> _startSosLocationSharing(
    String sessionId,
    Position initialPosition,
  ) async {
    _lastSharedSosPosition = initialPosition;
    _lastSharedSosAt = DateTime.now();
    await _sosLocationSubscription?.cancel();
    _sosLocationSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 3,
      ),
    ).listen((position) async {
      if (!position.latitude.isFinite || !position.longitude.isFinite) {
        return;
      }
      if (!_shouldPushSosLocation(position)) {
        return;
      }

      try {
        await _sosAlertService.updateLiveLocation(
          sessionId: sessionId,
          position: position,
        );
        _lastSharedSosPosition = position;
        _lastSharedSosAt = DateTime.now();
      } catch (_) {
        // Keep SOS locally active even if a background sync fails.
      }
    });
  }

  bool _shouldPushSosLocation(Position nextPosition) {
    final lastPosition = _lastSharedSosPosition;
    final lastSharedAt = _lastSharedSosAt;
    if (lastPosition == null || lastSharedAt == null) {
      return true;
    }

    final movedDistance = Geolocator.distanceBetween(
      lastPosition.latitude,
      lastPosition.longitude,
      nextPosition.latitude,
      nextPosition.longitude,
    );
    final elapsed = DateTime.now().difference(lastSharedAt);
    return movedDistance >= 15 || elapsed >= const Duration(seconds: 15);
  }

  String _buildStopSosMessage(String? audioPath, String? videoPath) {
    if (audioPath == null && videoPath == null) {
      return 'SOS stopped. Recording ended.';
    }
    if (audioPath != null && videoPath != null) {
      return 'SOS stopped. Audio and video recordings saved.';
    }
    if (audioPath != null) {
      return 'SOS stopped. Audio recording saved.';
    }
    return 'SOS stopped. Video recording saved.';
  }

  void _handleBackNavigation() {
    if (_currentIndex != 0) {
      setState(() {
        _currentIndex = 0;
      });
      return;
    }

    final now = DateTime.now();
    final lastPressed = _lastBackPressedAt;
    if (lastPressed == null ||
        now.difference(lastPressed) > const Duration(seconds: 2)) {
      _lastBackPressedAt = now;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Press back again to exit'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final user = FirebaseAuth.instance.currentUser;
    final authService = AuthService();
    final themeModeController = ThemeModeScope.of(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          return;
        }
        _handleBackNavigation();
      },
      child: Scaffold(
        backgroundColor: isDark ? Colors.black : const Color(0xFFF8FAFC),
        appBar: AppBar(
          backgroundColor: theme.colorScheme.surface,
          elevation: 0,
          title: Text(
            _titles[_currentIndex],
            style: TextStyle(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.bold,
            ),
          ),
          actions: [
            IconButton(
              tooltip: 'SOS inbox',
              icon: Icon(
                Icons.notification_important_outlined,
                color: theme.colorScheme.onSurface,
              ),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SosAlertsScreen()),
                );
              },
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(
              color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE5E7EB),
              height: 1,
            ),
          ),
        ),
        body: Column(
          children: [
            if (_showOfflineBanner)
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                color: const Color(0xFFB45309),
                child: const Text(
                  'Offline mode: some live features are temporarily unavailable.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            Expanded(
              child: IndexedStack(
                index: _currentIndex,
                children: [
                  _HomeTab(
                    user: user,
                    isSosActive: _isSosActive,
                    onSosActivated: _handleSosActivated,
                    onStopSos: _stopSos,
                    holdDuration: _sosHoldDuration,
                  ),
                  _LiveMapTab(
                    isSosActive: _isSosActive,
                    onStopSos: _stopSos,
                  ),
                  _ProfileTab(
                    user: user,
                    onProfilePhotoChanged: (path) {
                      setState(() {
                        _navProfilePhotoPath = path;
                      });
                    },
                  ),
                  _SettingsTab(
                    user: user,
                    themeModeController: themeModeController,
                    onOpenEmergencyContacts: () {
                      setState(() => _currentIndex = 2);
                    },
                    onOpenSosInbox: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const SosAlertsScreen()),
                      );
                    },
                    onLogout: authService.signOut,
                    autoVideoRecord: _autoVideoRecord,
                    autoVoiceRecord: _autoVoiceRecord,
                    vibrationOnSos: _vibrationOnSos,
                    hardwareSosShortcutEnabled: _hardwareSosShortcutEnabled,
                    hardwareSosPermissionEnabled:
                        _isHardwareSosPermissionEnabled,
                    holdDuration: _sosHoldDuration,
                    onOpenBatteryOptimizationSettings: () {
                      return DeviceSettingsService
                          .openBatteryOptimizationSettings();
                    },
                    onManageSubscription: () async {
                      try {
                        final result = await RevenueCatService.presentPaywall();
                        if (!context.mounted) {
                          return;
                        }
                        final message = switch (result) {
                          PaywallResult.purchased =>
                            'Purchase complete. Your subscription is now active.',
                          PaywallResult.restored =>
                            'Purchases restored for this account.',
                          PaywallResult.cancelled =>
                            'Checkout closed. No changes were made.',
                          PaywallResult.notPresented =>
                            'No active paywall was found in RevenueCat.',
                          PaywallResult.error =>
                            'Unable to open checkout right now. Please try again.',
                        };
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(message)),
                        );
                      } catch (_) {
                        if (!context.mounted) {
                          return;
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Unable to open checkout right now. Please try again.',
                            ),
                          ),
                        );
                      }
                    },
                    onAutoVideoRecordChanged: (value) {
                      setState(() => _autoVideoRecord = value);
                      _saveBoolPreference(_autoVideoRecordKey, value);
                    },
                    onAutoVoiceRecordChanged: (value) {
                      setState(() => _autoVoiceRecord = value);
                      _saveBoolPreference(_autoVoiceRecordKey, value);
                    },
                    onVibrationOnSosChanged: (value) {
                      setState(() => _vibrationOnSos = value);
                      _saveBoolPreference(_vibrationOnSosKey, value);
                    },
                    onOpenHardwareShortcutSettings: () async {
                      try {
                        await _hardwareSosChannel
                            .invokeMethod('openAccessibilitySettings');
                        await Future<void>.delayed(
                          const Duration(milliseconds: 800),
                        );
                        await _refreshHardwareSosPermissionStatus();
                      } catch (_) {
                        if (!context.mounted) {
                          return;
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Could not open accessibility settings.',
                            ),
                          ),
                        );
                      }
                    },
                    onHardwareSosShortcutChanged: (value) async {
                      setState(() => _hardwareSosShortcutEnabled = value);
                      await _saveBoolPreference(_hardwareSosShortcutKey, value);
                      await _setHardwareSosShortcutEnabled(value);
                      await _refreshHardwareSosPermissionStatus();
                    },
                    onHoldDurationChanged: (value) {
                      setState(() => _sosHoldDuration = value);
                      _saveIntPreference(_sosHoldDurationKey, value);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: _AnimatedBottomNavBar(
            items: _navItems,
            currentIndex: _currentIndex,
            profileImagePath: _navProfilePhotoPath,
            onTap: (index) {
              if (_currentIndex == index) return;
              setState(() => _currentIndex = index);
              if (index == 3) {
                _refreshHardwareSosPermissionStatus();
              }
            },
          ),
        ),
      ),
    );
  }
}

class _BottomNavItem {
  const _BottomNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
}

class _AnimatedBottomNavBar extends StatefulWidget {
  const _AnimatedBottomNavBar({
    required this.items,
    required this.currentIndex,
    required this.profileImagePath,
    required this.onTap,
  });

  final List<_BottomNavItem> items;
  final int currentIndex;
  final String? profileImagePath;
  final ValueChanged<int> onTap;

  @override
  State<_AnimatedBottomNavBar> createState() => _AnimatedBottomNavBarState();
}

class _AnimatedBottomNavBarState extends State<_AnimatedBottomNavBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _animation = Tween<double>(
      begin: widget.currentIndex.toDouble(),
      end: widget.currentIndex.toDouble(),
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.elasticOut));
  }

  @override
  void didUpdateWidget(covariant _AnimatedBottomNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex) {
      _animation = Tween<double>(
        begin: _animation.value, // Start from current animated position
        end: widget.currentIndex.toDouble(),
      ).animate(
        CurvedAnimation(
          parent: _controller,
          // Elastic curve creates the "forth and back" sloshing water effect
          curve: Curves.elasticOut,
        ),
      );
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final navBackground = isDark ? const Color(0xFF0E0E0E) : Colors.white;
    final borderColor =
        isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE5E7EB);
    final iconColor =
        isDark ? const Color(0xFFB8B8B8) : const Color(0xFF111827);

    return LayoutBuilder(
      builder: (context, constraints) {
        final itemCount = widget.items.length;
        final slotWidth = constraints.maxWidth / itemCount;

        return SizedBox(
          height: 84,
          child: AnimatedBuilder(
            animation: _animation,
            builder: (context, _) {
              final currentIndexFloat = _animation.value;

              // Allow raw center to overshoot so the elastic wobble
              // is fully visible at the edges (the "forth and back" water effect).
              final notchCenterX =
                  (slotWidth * currentIndexFloat) + (slotWidth / 2);

              // The ball stays a perfect circle and smoothly glides with the notch
              const ballSize = 16.0;
              const ballTop = -2.0; // Floats slightly up
              const notchDepth = 18.0;

              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    top: 14,
                    child: CustomPaint(
                      painter: _LiquidNavBarPainter(
                        backgroundColor: navBackground,
                        borderColor: borderColor,
                        notchCenterX: notchCenterX,
                        notchDepth: notchDepth,
                        showShadow: true,
                      ),
                      child: Row(
                        children: List.generate(itemCount, (index) {
                          final item = widget.items[index];
                          final selected = index == widget.currentIndex;
                          return Expanded(
                            child: Semantics(
                              button: true,
                              label: item.label,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: () => widget.onTap(index),
                                child: SizedBox(
                                  height: 72,
                                  child: Center(
                                    child: AnimatedScale(
                                      duration:
                                          const Duration(milliseconds: 400),
                                      curve: Curves.easeOutBack,
                                      scale: selected ? 1.15 : 1,
                                      child: _buildNavIcon(
                                        index: index,
                                        item: item,
                                        selected: selected,
                                        theme: theme,
                                        iconColor: iconColor,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                  ),
                  Positioned(
                    left: notchCenterX - (ballSize / 2),
                    top: ballTop,
                    child: IgnorePointer(
                      child: Container(
                        width: ballSize,
                        height: ballSize,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: [
                            BoxShadow(
                              color: theme.colorScheme.primary
                                  .withValues(alpha: 0.45),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildNavIcon({
    required int index,
    required _BottomNavItem item,
    required bool selected,
    required ThemeData theme,
    required Color iconColor,
  }) {
    if (index != 2) {
      return Icon(
        selected ? item.activeIcon : item.icon,
        color: selected ? theme.colorScheme.primary : iconColor,
        size: selected ? 28 : 26,
      );
    }

    final provider = _profileImageProvider(widget.profileImagePath);
    if (provider == null) {
      return Icon(
        selected ? item.activeIcon : item.icon,
        color: selected ? theme.colorScheme.primary : iconColor,
        size: selected ? 28 : 26,
      );
    }

    return Container(
      width: selected ? 30 : 27,
      height: selected ? 30 : 27,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? theme.colorScheme.primary : iconColor,
          width: selected ? 2 : 1.5,
        ),
        image: DecorationImage(image: provider, fit: BoxFit.cover),
      ),
    );
  }

  ImageProvider<Object>? _profileImageProvider(String? value) {
    final path = (value ?? '').trim();
    if (path.isEmpty) {
      return null;
    }
    final normalized = path.toLowerCase();
    if (normalized.startsWith('http://') || normalized.startsWith('https://')) {
      return NetworkImage(path);
    }
    final file = File(path);
    if (file.existsSync()) {
      return FileImage(file);
    }
    return null;
  }
}

class _LiquidNavBarPainter extends CustomPainter {
  _LiquidNavBarPainter({
    required this.backgroundColor,
    required this.borderColor,
    required this.notchCenterX,
    required this.notchDepth,
    required this.showShadow,
  });

  final Color backgroundColor;
  final Color borderColor;
  final double notchCenterX;
  final double notchDepth;
  final bool showShadow;

  @override
  void paint(Canvas canvas, Size size) {
    const radius = 24.0;
    const notchWidth = 84.0;

    // The raw center of the notch, which can freely bounce past the edges
    final notchStart = notchCenterX - (notchWidth / 2);
    final notchEnd = notchCenterX + (notchWidth / 2);

    // 1. Create the base rounded rectangle
    final baseRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      const Radius.circular(radius),
    );
    final basePath = Path()..addRRect(baseRect);

    // 2. Create the cutout shape for the liquid notch
    final cutoutPath = Path()
      ..moveTo(notchStart, -50) // Start high above the bar
      ..lineTo(notchStart, 0)
      // First half of the liquid notch
      ..cubicTo(
        notchStart + (notchWidth * 0.35),
        0,
        notchCenterX - (notchWidth * 0.25),
        notchDepth,
        notchCenterX,
        notchDepth,
      )
      // Second half of the liquid notch
      ..cubicTo(
        notchCenterX + (notchWidth * 0.25),
        notchDepth,
        notchEnd - (notchWidth * 0.35),
        0,
        notchEnd,
        0,
      )
      ..lineTo(notchEnd, -50) // Go back up
      ..close();

    // 3. Subtract the cutout from the base shape.
    // This perfectly handles the notch overlapping the corner radius (no bulges!)
    final finalPath = Path.combine(
      PathOperation.difference,
      basePath,
      cutoutPath,
    );

    if (showShadow) {
      canvas.drawShadow(finalPath, Colors.black, 16, true);
    }

    final fillPaint = Paint()..color = backgroundColor;
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    canvas.drawPath(finalPath, fillPaint);
    canvas.drawPath(finalPath, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _LiquidNavBarPainter oldDelegate) {
    return oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.borderColor != borderColor ||
        oldDelegate.notchCenterX != notchCenterX ||
        oldDelegate.notchDepth != notchDepth ||
        oldDelegate.showShadow != showShadow;
  }
}

class _HomeTab extends StatelessWidget {
  const _HomeTab({
    required this.user,
    required this.isSosActive,
    required this.onSosActivated,
    required this.onStopSos,
    required this.holdDuration,
  });

  final User? user;
  final bool isSosActive;
  final Future<void> Function() onSosActivated;
  final Future<void> Function() onStopSos;
  final int holdDuration;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      children: [
        _SosHoldButton(
          isSosActive: isSosActive,
          onActivated: onSosActivated,
          onStop: onStopSos,
          holdDuration: holdDuration,
        ),
      ],
    );
  }
}

class _SosHoldButton extends StatefulWidget {
  const _SosHoldButton({
    required this.isSosActive,
    required this.onActivated,
    required this.onStop,
    required this.holdDuration,
  });

  final bool isSosActive;
  final Future<void> Function() onActivated;
  final Future<void> Function() onStop;
  final int holdDuration;

  @override
  State<_SosHoldButton> createState() => _SosHoldButtonState();
}

class _SosHoldButtonState extends State<_SosHoldButton>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _holdController;
  Timer? _activeCountdownTimer;
  bool _isHolding = false;
  bool _activated = false;
  bool _isProcessing = false;
  int _activeCountdown = 2;

  @override
  void initState() {
    super.initState();
    _activeCountdown = widget.holdDuration;
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat(reverse: true);

    _holdController = AnimationController(
      vsync: this,
      duration: Duration(seconds: widget.holdDuration),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed && !_activated) {
          _activated = true;
          _activateSos();
        }
      });
  }

  @override
  void didUpdateWidget(covariant _SosHoldButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isSosActive && widget.isSosActive) {
      _startActiveCountdown();
    } else if (oldWidget.isSosActive && !widget.isSosActive) {
      _activeCountdownTimer?.cancel();
      _activeCountdown = widget.holdDuration;
    }

    if (oldWidget.holdDuration != widget.holdDuration) {
      _holdController.duration = Duration(seconds: widget.holdDuration);
      if (!widget.isSosActive) {
        _activeCountdown = widget.holdDuration;
      }
    }
  }

  @override
  void dispose() {
    _activeCountdownTimer?.cancel();
    _pulseController.dispose();
    _holdController.dispose();
    super.dispose();
  }

  void _startActiveCountdown() {
    _activeCountdownTimer?.cancel();
    setState(() {
      _activeCountdown = widget.holdDuration;
    });
    _activeCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || !widget.isSosActive) {
        timer.cancel();
        return;
      }
      if (_activeCountdown <= 1) {
        timer.cancel();
        setState(() {
          _activeCountdown = 0;
        });
        return;
      }
      setState(() {
        _activeCountdown -= 1;
      });
    });
  }

  void _startHold() {
    if (_isHolding || widget.isSosActive || _isProcessing) return;
    setState(() {
      _isHolding = true;
      _activated = false;
    });
    _holdController.forward(from: 0);
  }

  void _endHold() {
    if (!_isHolding) return;
    setState(() {
      _isHolding = false;
    });
    if (_holdController.isCompleted) {
      _holdController.value = 0;
      return;
    }
    _holdController.animateBack(0,
        duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
  }

  Future<void> _activateSos() async {
    if (_isProcessing) {
      return;
    }
    setState(() {
      _isProcessing = true;
      _isHolding = false;
    });
    try {
      await widget.onActivated();
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _holdController.value = 0;
        });
      }
    }
  }

  Future<void> _stopSos() async {
    if (_isProcessing) {
      return;
    }
    setState(() {
      _isProcessing = true;
    });
    try {
      await widget.onStop();
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const accentColor = Color(0xFFFF4D6D);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final panelColor = isDark ? const Color(0xFF121212) : Colors.white;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: widget.isSosActive ? const Color(0xFFFF4D6D) : panelColor,
        borderRadius: BorderRadius.circular(34),
        border: Border.all(
          color: widget.isSosActive
              ? Colors.white.withValues(alpha: 0.32)
              : (isDark ? const Color(0xFF232323) : const Color(0xFFF2D5DC)),
        ),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(
              alpha: widget.isSosActive ? 0.26 : (isDark ? 0.14 : 0.10),
            ),
            blurRadius: widget.isSosActive ? 26 : 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: widget.isSosActive
          ? Column(
              children: [
                Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.44),
                    ),
                  ),
                  child: const Icon(
                    Icons.shield_rounded,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Emergency alert sent',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Stay calm. Emergency mode is active and your SOS flow is running.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 22),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Column(
                    children: [
                      Text(
                        _activeCountdown > 0
                            ? 'You can still cancel before the alert fully locks in.'
                            : 'Emergency mode is fully active now.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF6B7280),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        _activeCountdown > 0 ? '$_activeCountdown' : 'LIVE',
                        style: TextStyle(
                          fontSize: _activeCountdown > 0 ? 58 : 32,
                          fontWeight: FontWeight.w900,
                          color: accentColor,
                          letterSpacing: _activeCountdown > 0 ? 1 : 2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _activeCountdown > 0
                            ? 'seconds remaining'
                            : 'help mode in progress',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF6B7280),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: _isProcessing ? null : _stopSos,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: accentColor,
                            side: BorderSide(
                              color: accentColor.withValues(alpha: 0.28),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          child: _isProcessing
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFFFF4D6D),
                                  ),
                                )
                              : const Text(
                                  'Cancel Alert',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            )
          : Column(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.shield_outlined,
                    color: accentColor,
                    size: 26,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Emergency Alert',
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Press and hold to trigger an emergency alert instantly.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFFA3A3A3),
                    fontSize: 15,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 30),
                GestureDetector(
                  onTapDown: (_) => _startHold(),
                  onTapUp: (_) => _endHold(),
                  onTapCancel: _endHold,
                  child: AnimatedBuilder(
                    animation:
                        Listenable.merge([_pulseController, _holdController]),
                    builder: (context, _) {
                      final pulse = 1 + (_pulseController.value * 0.045);
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          Transform.scale(
                            scale: pulse,
                            child: Container(
                              width: 208,
                              height: 208,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: accentColor.withValues(alpha: 0.06),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 180,
                            height: 180,
                            child: CircularProgressIndicator(
                              value: _holdController.value,
                              strokeWidth: 5,
                              backgroundColor:
                                  accentColor.withValues(alpha: 0.10),
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                accentColor,
                              ),
                            ),
                          ),
                          Container(
                            width: 148,
                            height: 148,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color(0xFFFF4D6D),
                                  Color(0xFFC9184A),
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: accentColor.withValues(alpha: 0.35),
                                  blurRadius: 24,
                                  offset: const Offset(0, 12),
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _isProcessing
                                      ? Icons.sync_rounded
                                      : Icons.notifications_active_rounded,
                                  color: Colors.white,
                                  size: 48,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  _isProcessing ? 'WAIT' : 'ALERT',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  _isHolding
                      ? 'Hold... ${(_holdController.value * widget.holdDuration).clamp(0, widget.holdDuration).toStringAsFixed(1)}s / ${widget.holdDuration}.0s'
                      : (_isProcessing
                          ? 'Preparing Alert...'
                          : 'Release before ${widget.holdDuration} seconds to cancel'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _isHolding ? accentColor : const Color(0xFFA3A3A3),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
    );
  }
}

class _LiveMapTab extends StatefulWidget {
  const _LiveMapTab({required this.isSosActive, required this.onStopSos});

  final bool isSosActive;
  final Future<void> Function() onStopSos;

  @override
  State<_LiveMapTab> createState() => _LiveMapTabState();
}

class _LiveMapTabState extends State<_LiveMapTab> with WidgetsBindingObserver {
  final MapController _mapController = MapController();
  static const _walkingSpeedMetersPerSecond = 1.4;
  static const _offlineRouteCacheKey = 'live_map_offline_route_cache_v1';
  static const _stationsCacheKey = 'live_map_police_stations_cache_v1';
  static const _stationsCacheTtl = Duration(minutes: 10);
  static const _stationsCacheMaxDistanceMeters = 3000.0;
  static const _stationsFetchTimeout = Duration(seconds: 6);
  static const _graphBuildTimeout = Duration(seconds: 7);
  StreamSubscription<Position>? _positionSubscription;
  Position? _position;
  latlng.LatLng? _nearestPoliceStation;
  latlng.LatLng? _lastRouteFetchOrigin;
  List<latlng.LatLng> _routePoints = const [];
  double? _routeDistanceKm;
  double? _routeEtaMinutes;
  bool _isLoading = true;
  bool _isRequestingPermission = false;
  bool _isFetchingPoliceRoute = false;
  bool _isUsingCachedStations = false;
  String? _errorMessage;
  int _activePointers = 0;
  Position? _pendingPosition;
  bool _hasAutoOpenedNavigationForActiveSos = false;

  bool get _userIsInteracting => _activePointers > 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initLocationTracking();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _initLocationTracking();
    }
  }

  @override
  void didUpdateWidget(covariant _LiveMapTab oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!oldWidget.isSosActive && widget.isSosActive) {
      _hasAutoOpenedNavigationForActiveSos = false;
      _maybeAutoOpenSosNavigation();
    }

    if (oldWidget.isSosActive && !widget.isSosActive) {
      _hasAutoOpenedNavigationForActiveSos = false;
    }
  }

  void _moveCameraTo(latlng.LatLng target, {double? zoom}) {
    if (_userIsInteracting) return;
    if (!target.latitude.isFinite || !target.longitude.isFinite) {
      return;
    }
    try {
      final currentZoom = _mapController.camera.zoom;
      final effectiveZoom = zoom ?? currentZoom;
      if (!effectiveZoom.isFinite) return;
      _mapController.move(target, effectiveZoom);
    } catch (_) {
      // Map may not be attached yet.
    }
  }

  void _flushPendingPosition() {
    final pending = _pendingPosition;
    if (pending == null || !mounted) return;
    _pendingPosition = null;
    _position = pending;
    setState(() {});
    _moveCameraTo(latlng.LatLng(pending.latitude, pending.longitude));
    _fetchNearestPoliceRoute(pending);
  }

  Future<void> _applyCachedOfflineRoute(Position position) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_offlineRouteCacheKey);
    if (raw == null || raw.trim().isEmpty || !mounted) {
      return;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return;
      }
      final originLat = (decoded['origin_lat'] as num?)?.toDouble();
      final originLon = (decoded['origin_lon'] as num?)?.toDouble();
      final stationLat = (decoded['station_lat'] as num?)?.toDouble();
      final stationLon = (decoded['station_lon'] as num?)?.toDouble();
      final pointsRaw = decoded['route_points'];
      if (originLat == null ||
          originLon == null ||
          stationLat == null ||
          stationLon == null ||
          pointsRaw is! List) {
        return;
      }

      final distanceFromCacheOrigin = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        originLat,
        originLon,
      );
      if (distanceFromCacheOrigin > 4000) {
        return;
      }

      final points = <latlng.LatLng>[];
      for (final item in pointsRaw) {
        if (item is! List || item.length != 2) continue;
        final lat = (item[0] as num?)?.toDouble();
        final lon = (item[1] as num?)?.toDouble();
        if (lat == null || lon == null || !lat.isFinite || !lon.isFinite) {
          continue;
        }
        points.add(latlng.LatLng(lat, lon));
      }
      if (points.length < 2) {
        return;
      }

      setState(() {
        _nearestPoliceStation = latlng.LatLng(stationLat, stationLon);
        _routePoints = points;
        _routeDistanceKm = (decoded['route_distance_km'] as num?)?.toDouble();
        _routeEtaMinutes = (decoded['route_eta_minutes'] as num?)?.toDouble();
      });
    } catch (_) {
      return;
    }
  }

  Future<void> _cacheOfflineRoute({
    required Position origin,
    required latlng.LatLng station,
    required List<latlng.LatLng> routePoints,
    required double? routeDistanceKm,
    required double? routeEtaMinutes,
  }) async {
    if (routePoints.length < 2) {
      return;
    }
    final payload = {
      'origin_lat': origin.latitude,
      'origin_lon': origin.longitude,
      'station_lat': station.latitude,
      'station_lon': station.longitude,
      'route_distance_km': routeDistanceKm,
      'route_eta_minutes': routeEtaMinutes,
      'route_points': routePoints
          .map((point) => [point.latitude, point.longitude])
          .toList(),
    };
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_offlineRouteCacheKey, jsonEncode(payload));
  }

  Future<void> _initLocationTracking() async {
    if (_isRequestingPermission) return;
    _isRequestingPermission = true;

    setState(() {
      _isLoading = _position == null;
      _errorMessage = null;
    });

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await Geolocator.openLocationSettings();
      setState(() {
        _isLoading = false;
        _errorMessage =
            'Location is off. Please turn on phone location and return to the app.';
      });
      _isRequestingPermission = false;
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      setState(() {
        _isLoading = false;
        _errorMessage =
            'Location permission is required to show your live location.';
      });
      _isRequestingPermission = false;
      return;
    }

    if (permission == LocationPermission.deniedForever) {
      await Geolocator.openAppSettings();
      setState(() {
        _isLoading = false;
        _errorMessage =
            'Location permission is permanently denied. Enable it from app settings.';
      });
      _isRequestingPermission = false;
      return;
    }

    try {
      final cached = await Geolocator.getLastKnownPosition();
      if (cached != null &&
          mounted &&
          cached.latitude.isFinite &&
          cached.longitude.isFinite) {
        setState(() {
          _position = cached;
          _isLoading = false;
        });
        _moveCameraTo(
          latlng.LatLng(cached.latitude, cached.longitude),
          zoom: 15.5,
        );
        await _fetchNearestPoliceRoute(cached, forceRefresh: true);
      }

      final current = await _getCurrentPositionWithOfflineFallback();

      if (!mounted) return;
      if (current.latitude.isFinite && current.longitude.isFinite) {
        setState(() {
          _position = current;
          _isLoading = false;
        });
        _moveCameraTo(
          latlng.LatLng(current.latitude, current.longitude),
          zoom: 16,
        );
        await _fetchNearestPoliceRoute(current, forceRefresh: true);
      }

      await _positionSubscription?.cancel();
      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 3,
        ),
      ).listen((position) {
        if (!mounted) return;
        if (!position.latitude.isFinite || !position.longitude.isFinite) return;

        if (_userIsInteracting) {
          // Defer update until user lifts all fingers
          _pendingPosition = position;
          return;
        }
        _position = position;
        setState(() {});
        _moveCameraTo(latlng.LatLng(position.latitude, position.longitude));
        _fetchNearestPoliceRoute(position);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = _position == null
            ? 'Unable to fetch location right now. Please try again.'
            : null;
      });
      if (_position != null) {
        await _applyCachedOfflineRoute(_position!);
      }
    } finally {
      _isRequestingPermission = false;
    }
  }

  Future<Position> _getCurrentPositionWithOfflineFallback() async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          timeLimit: Duration(seconds: 8),
        ),
      );
    } catch (_) {
      return Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
        ),
      );
    }
  }

  Future<void> _fetchNearestPoliceRoute(
    Position position, {
    bool forceRefresh = false,
  }) async {
    if (_isFetchingPoliceRoute) {
      return;
    }

    if (!forceRefresh && _lastRouteFetchOrigin != null) {
      final movedDistance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        _lastRouteFetchOrigin!.latitude,
        _lastRouteFetchOrigin!.longitude,
      );
      if (movedDistance < 150) {
        return;
      }
    }

    _isFetchingPoliceRoute = true;
    if (!position.latitude.isFinite || !position.longitude.isFinite) {
      _isFetchingPoliceRoute = false;
      return;
    }
    _lastRouteFetchOrigin =
        latlng.LatLng(position.latitude, position.longitude);
    try {
      final stations = await _findNearestPoliceStations(
        latitude: position.latitude,
        longitude: position.longitude,
      );
      if (stations.isEmpty) return;

      final origin = latlng.LatLng(position.latitude, position.longitude);
      _PoliceStation? selectedStation;
      _RouteInfo? selectedRoute;
      final candidateStations = stations.take(4).toList();

      final quickStation = candidateStations.first;
      final quickRoute =
          _buildDirectRoute(from: origin, to: quickStation.position);
      if (mounted) {
        setState(() {
          _nearestPoliceStation = quickStation.position;
          _routePoints = quickRoute.points;
          _routeDistanceKm = quickRoute.distanceMeters != null
              ? quickRoute.distanceMeters! / 1000
              : null;
          _routeEtaMinutes = quickRoute.durationSeconds != null
              ? quickRoute.durationSeconds! / 60
              : null;
        });
      }

      Future<void> chooseBestRoute() async {
        final graph = await _buildWalkingGraph(
          origin: origin,
          destinations: candidateStations.map((s) => s.position).toList(),
        ).timeout(_graphBuildTimeout);

        for (final station in candidateStations) {
          final route = await _buildRouteToPoliceStation(
            from: origin,
            to: station.position,
            graph: graph,
          );

          if (route == null && selectedStation == null) {
            selectedStation = station;
            continue;
          }
          if (route == null) {
            continue;
          }
          final selectedRouteDuration =
              selectedRoute?.durationSeconds ?? double.infinity;
          if (selectedRoute == null ||
              (route.durationSeconds ?? double.infinity) <
                  selectedRouteDuration) {
            selectedStation = station;
            selectedRoute = route;
          }
        }
      }

      try {
        await chooseBestRoute();
      } on TimeoutException {
        selectedStation = quickStation;
        selectedRoute = quickRoute;
      }

      final station = selectedStation ?? quickStation;
      final route = selectedRoute ?? quickRoute;

      if (!mounted) return;
      final distanceMeters = route.distanceMeters;
      final durationSeconds = route.durationSeconds;
      setState(() {
        _nearestPoliceStation = station.position;
        _routePoints = route.points;
        _routeDistanceKm =
            distanceMeters != null ? distanceMeters / 1000 : null;
        _routeEtaMinutes =
            durationSeconds != null ? durationSeconds / 60 : null;
      });
      _maybeAutoOpenSosNavigation();
      await _cacheOfflineRoute(
        origin: position,
        station: station.position,
        routePoints: _routePoints,
        routeDistanceKm: _routeDistanceKm,
        routeEtaMinutes: _routeEtaMinutes,
      );
    } catch (_) {
      if (!mounted) return;
      await _applyCachedOfflineRoute(position);
      _maybeAutoOpenSosNavigation();
    } finally {
      _isFetchingPoliceRoute = false;
    }
  }

  void _maybeAutoOpenSosNavigation() {
    if (!widget.isSosActive || _hasAutoOpenedNavigationForActiveSos) {
      return;
    }
    if (_position == null || _nearestPoliceStation == null) {
      return;
    }
    _hasAutoOpenedNavigationForActiveSos = true;
  }

  Future<List<_PoliceStation>> _findNearestPoliceStations({
    required double latitude,
    required double longitude,
  }) async {
    final cachedStations = await _getCachedPoliceStations(
      latitude: latitude,
      longitude: longitude,
    );
    if (cachedStations != null && cachedStations.isNotEmpty) {
      if (mounted && !_isUsingCachedStations) {
        setState(() {
          _isUsingCachedStations = true;
        });
      }
      return cachedStations;
    }

    if (mounted && _isUsingCachedStations) {
      setState(() {
        _isUsingCachedStations = false;
      });
    }

    final query =
        '[out:json][timeout:20];(node["amenity"="police"](around:7000,$latitude,$longitude);way["amenity"="police"](around:7000,$latitude,$longitude););out center 1;';
    final uri =
        Uri.https('overpass-api.de', '/api/interpreter', {'data': query});
    final response = await http.get(uri, headers: {
      'User-Agent': 'Aegixa/1.0 (safety app)',
      'Accept': 'application/json',
    }).timeout(_stationsFetchTimeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      return const [];
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      return const [];
    }

    final elements = decoded['elements'];
    if (elements is! List || elements.isEmpty) {
      return const [];
    }

    final stations = <_PoliceStationDistance>[];
    for (final item in elements) {
      if (item is! Map<String, dynamic>) continue;

      final lat = (item['lat'] as num?)?.toDouble() ??
          (item['center'] is Map<String, dynamic>
              ? ((item['center']['lat'] as num?)?.toDouble())
              : null);
      final lon = (item['lon'] as num?)?.toDouble() ??
          (item['center'] is Map<String, dynamic>
              ? ((item['center']['lon'] as num?)?.toDouble())
              : null);
      if (lat == null || lon == null || !lat.isFinite || !lon.isFinite) {
        continue;
      }

      final tags = item['tags'];
      final name = tags is Map<String, dynamic>
          ? (tags['name'] as String?) ?? 'Nearby police station'
          : 'Nearby police station';
      stations.add(
        _PoliceStationDistance(
          station: _PoliceStation(
            name: name,
            position: latlng.LatLng(lat, lon),
          ),
          straightLineDistance: Geolocator.distanceBetween(
            latitude,
            longitude,
            lat,
            lon,
          ),
        ),
      );
    }

    stations.sort(
      (a, b) => a.straightLineDistance.compareTo(b.straightLineDistance),
    );
    final result = stations.map((entry) => entry.station).take(6).toList();
    if (result.isNotEmpty) {
      await _cachePoliceStations(
        originLatitude: latitude,
        originLongitude: longitude,
        stations: result,
      );
    }
    return result;
  }

  Future<List<_PoliceStation>?> _getCachedPoliceStations({
    required double latitude,
    required double longitude,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_stationsCacheKey);
      if (raw == null || raw.isEmpty) return null;

      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;

      final cachedAtMs = (decoded['cached_at_ms'] as num?)?.toInt();
      final originLat = (decoded['origin_lat'] as num?)?.toDouble();
      final originLon = (decoded['origin_lon'] as num?)?.toDouble();
      final stationsRaw = decoded['stations'];

      if (cachedAtMs == null ||
          originLat == null ||
          originLon == null ||
          stationsRaw is! List) {
        return null;
      }

      final cacheAge = DateTime.now().millisecondsSinceEpoch - cachedAtMs;
      if (cacheAge > _stationsCacheTtl.inMilliseconds) {
        return null;
      }

      final distanceFromCacheOrigin = Geolocator.distanceBetween(
        latitude,
        longitude,
        originLat,
        originLon,
      );
      if (distanceFromCacheOrigin > _stationsCacheMaxDistanceMeters) {
        return null;
      }

      final stations = <_PoliceStation>[];
      for (final item in stationsRaw) {
        if (item is! Map<String, dynamic>) continue;
        final name = item['name'] as String?;
        final lat = (item['lat'] as num?)?.toDouble();
        final lon = (item['lon'] as num?)?.toDouble();
        if (name == null || lat == null || lon == null) continue;
        if (!lat.isFinite || !lon.isFinite) continue;
        stations.add(
          _PoliceStation(name: name, position: latlng.LatLng(lat, lon)),
        );
      }

      if (stations.isEmpty) return null;

      stations.sort((a, b) {
        final aDistance = Geolocator.distanceBetween(
          latitude,
          longitude,
          a.position.latitude,
          a.position.longitude,
        );
        final bDistance = Geolocator.distanceBetween(
          latitude,
          longitude,
          b.position.latitude,
          b.position.longitude,
        );
        return aDistance.compareTo(bDistance);
      });
      return stations.take(6).toList();
    } catch (_) {
      return null;
    }
  }

  Future<void> _cachePoliceStations({
    required double originLatitude,
    required double originLongitude,
    required List<_PoliceStation> stations,
  }) async {
    try {
      final payload = {
        'cached_at_ms': DateTime.now().millisecondsSinceEpoch,
        'origin_lat': originLatitude,
        'origin_lon': originLongitude,
        'stations': stations
            .map((station) => {
                  'name': station.name,
                  'lat': station.position.latitude,
                  'lon': station.position.longitude,
                })
            .toList(),
      };
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_stationsCacheKey, jsonEncode(payload));
    } catch (_) {
      return;
    }
  }

  _RouteInfo _buildDirectRoute({
    required latlng.LatLng from,
    required latlng.LatLng to,
  }) {
    final distanceMeters = Geolocator.distanceBetween(
      from.latitude,
      from.longitude,
      to.latitude,
      to.longitude,
    );
    final durationSeconds = distanceMeters / _walkingSpeedMetersPerSecond;
    return _RouteInfo(
      points: [from, to],
      distanceMeters: distanceMeters,
      durationSeconds: durationSeconds,
    );
  }

  Future<_RouteInfo?> _buildRouteToPoliceStation({
    required latlng.LatLng from,
    required latlng.LatLng to,
    required _WalkingGraph graph,
  }) async {
    if (graph.nodes.length < 2) {
      return null;
    }

    final startCandidates = _findNearestGraphNodeCandidates(graph, from);
    final endCandidates = _findNearestGraphNodeCandidates(graph, to);
    if (startCandidates.isEmpty || endCandidates.isEmpty) {
      return null;
    }

    _ShortestPathResult? bestPath;
    _GraphNodeDistance? bestStart;
    _GraphNodeDistance? bestEnd;
    double? bestTotalDistance;

    for (final start in startCandidates.take(5)) {
      for (final end in endCandidates.take(5)) {
        final aStarPath = _runAStar(graph, start.nodeId, end.nodeId);
        final dijkstraPath = _runDijkstra(graph, start.nodeId, end.nodeId);
        final chosenPath = _chooseBestPath(aStarPath, dijkstraPath);
        if (chosenPath == null || chosenPath.nodeIds.isEmpty) {
          continue;
        }

        final totalDistance = chosenPath.distanceMeters +
            start.distanceMeters +
            end.distanceMeters;
        if (bestTotalDistance == null || totalDistance < bestTotalDistance) {
          bestTotalDistance = totalDistance;
          bestPath = chosenPath;
          bestStart = start;
          bestEnd = end;
        }
      }
    }

    if (bestPath == null || bestStart == null || bestEnd == null) {
      return null;
    }

    final points = <latlng.LatLng>[from];
    for (final nodeId in bestPath.nodeIds) {
      final point = graph.nodes[nodeId];
      if (point != null) {
        points.add(point);
      }
    }
    if (points.last.latitude != to.latitude ||
        points.last.longitude != to.longitude) {
      points.add(to);
    }

    final distanceMeters = bestPath.distanceMeters +
        bestStart.distanceMeters +
        bestEnd.distanceMeters;
    final durationSeconds = distanceMeters / _walkingSpeedMetersPerSecond;

    return _RouteInfo(
      points: points,
      distanceMeters: distanceMeters,
      durationSeconds: durationSeconds,
    );
  }

  Future<_WalkingGraph> _buildWalkingGraph({
    required latlng.LatLng origin,
    required List<latlng.LatLng> destinations,
    double paddingDegrees = 0.01,
  }) async {
    final points = [origin, ...destinations];
    final latitudes = points.map((point) => point.latitude);
    final longitudes = points.map((point) => point.longitude);
    final centerLatitude =
        points.map((point) => point.latitude).reduce((a, b) => a + b) /
            points.length;
    final latitudePadding = paddingDegrees;
    final longitudePadding = paddingDegrees /
        (math.cos(centerLatitude * math.pi / 180).abs().clamp(0.3, 1.0));

    final south = latitudes.reduce((a, b) => a < b ? a : b) - latitudePadding;
    final north = latitudes.reduce((a, b) => a > b ? a : b) + latitudePadding;
    final west = longitudes.reduce((a, b) => a < b ? a : b) - longitudePadding;
    final east = longitudes.reduce((a, b) => a > b ? a : b) + longitudePadding;

    final query = '''
[out:json][timeout:25];
(
  way["highway"]($south,$west,$north,$east);
);
(._;>;);
out body;
''';
    final uri =
        Uri.https('overpass-api.de', '/api/interpreter', {'data': query});
    final response = await http.get(uri, headers: {
      'User-Agent': 'Aegixa/1.0 (safety app)',
      'Accept': 'application/json',
    });

    if (response.statusCode < 200 || response.statusCode >= 300) {
      return const _WalkingGraph(nodes: {}, adjacency: {});
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      return const _WalkingGraph(nodes: {}, adjacency: {});
    }

    final elements = decoded['elements'];
    if (elements is! List) {
      return const _WalkingGraph(nodes: {}, adjacency: {});
    }

    final nodes = <int, latlng.LatLng>{};
    final ways = <Map<String, dynamic>>[];
    for (final element in elements) {
      if (element is! Map<String, dynamic>) continue;
      if (element['type'] == 'node') {
        final id = element['id'] as num?;
        final lat = element['lat'] as num?;
        final lon = element['lon'] as num?;
        if (id == null ||
            lat == null ||
            lon == null ||
            !lat.toDouble().isFinite ||
            !lon.toDouble().isFinite) {
          continue;
        }
        nodes[id.toInt()] = latlng.LatLng(lat.toDouble(), lon.toDouble());
      } else if (element['type'] == 'way') {
        ways.add(element);
      }
    }

    final adjacency = <int, List<_GraphEdge>>{};
    for (final way in ways) {
      final tags = way['tags'];
      if (!_isWalkableWay(tags is Map<String, dynamic> ? tags : const {})) {
        continue;
      }
      final nodeRefs = way['nodes'];
      if (nodeRefs is! List || nodeRefs.length < 2) continue;

      final walkForward =
          !_isOneWayFootBlocked(tags is Map<String, dynamic> ? tags : const {});
      for (var i = 0; i < nodeRefs.length - 1; i++) {
        final fromId = (nodeRefs[i] as num?)?.toInt();
        final toId = (nodeRefs[i + 1] as num?)?.toInt();
        if (fromId == null || toId == null) continue;
        final fromPoint = nodes[fromId];
        final toPoint = nodes[toId];
        if (fromPoint == null || toPoint == null) continue;

        final distance = Geolocator.distanceBetween(
          fromPoint.latitude,
          fromPoint.longitude,
          toPoint.latitude,
          toPoint.longitude,
        );
        adjacency.putIfAbsent(fromId, () => []).add(
              _GraphEdge(toNodeId: toId, distanceMeters: distance),
            );
        if (walkForward) {
          adjacency.putIfAbsent(toId, () => []).add(
                _GraphEdge(toNodeId: fromId, distanceMeters: distance),
              );
        }
      }
    }

    return _WalkingGraph(nodes: nodes, adjacency: adjacency);
  }

  bool _isWalkableWay(Map<String, dynamic> tags) {
    const blockedHighways = {
      'motorway',
      'motorway_link',
      'trunk',
      'trunk_link',
      'construction',
      'raceway',
    };
    final highway = tags['highway'] as String?;
    if (highway == null || blockedHighways.contains(highway)) {
      return false;
    }

    final access = tags['access'] as String?;
    final foot = tags['foot'] as String?;
    if (access == 'private' || access == 'no' || foot == 'no') {
      return false;
    }

    return true;
  }

  bool _isOneWayFootBlocked(Map<String, dynamic> tags) {
    final oneWayFoot = tags['oneway:foot'] as String?;
    if (oneWayFoot == 'yes') {
      return false;
    }
    return (tags['oneway'] as String?) != 'yes';
  }

  List<_GraphNodeDistance> _findNearestGraphNodeCandidates(
    _WalkingGraph graph,
    latlng.LatLng point,
  ) {
    final candidates = <_GraphNodeDistance>[];

    graph.nodes.forEach((nodeId, nodePoint) {
      if (!(graph.adjacency[nodeId]?.isNotEmpty ?? false)) {
        return;
      }
      final distance = Geolocator.distanceBetween(
        point.latitude,
        point.longitude,
        nodePoint.latitude,
        nodePoint.longitude,
      );
      candidates.add(
        _GraphNodeDistance(nodeId: nodeId, distanceMeters: distance),
      );
    });

    candidates.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    return candidates.take(12).toList();
  }

  _ShortestPathResult? _chooseBestPath(
    _ShortestPathResult? aStarPath,
    _ShortestPathResult? dijkstraPath,
  ) {
    if (aStarPath == null) return dijkstraPath;
    if (dijkstraPath == null) return aStarPath;
    return aStarPath.distanceMeters <= dijkstraPath.distanceMeters
        ? aStarPath
        : dijkstraPath;
  }

  _ShortestPathResult? _runAStar(
    _WalkingGraph graph,
    int startNodeId,
    int endNodeId,
  ) {
    final openSet =
        _MinHeap<_FrontierNode>((a, b) => a.priority.compareTo(b.priority))
          ..add(_FrontierNode(nodeId: startNodeId, priority: 0));
    final cameFrom = <int, int>{};
    final gScore = <int, double>{startNodeId: 0};
    final fScore = <int, double>{
      startNodeId: _heuristicDistance(graph, startNodeId, endNodeId),
    };
    final closedSet = <int>{};

    while (openSet.isNotEmpty) {
      final current = openSet.removeFirst().nodeId;
      if (!closedSet.add(current)) {
        continue;
      }
      if (current == endNodeId) {
        return _reconstructPath(cameFrom, current, gScore[current] ?? 0);
      }

      for (final edge in graph.adjacency[current] ?? const <_GraphEdge>[]) {
        final tentative =
            (gScore[current] ?? double.infinity) + edge.distanceMeters;
        if (tentative >= (gScore[edge.toNodeId] ?? double.infinity)) {
          continue;
        }
        cameFrom[edge.toNodeId] = current;
        gScore[edge.toNodeId] = tentative;
        final estimatedTotal =
            tentative + _heuristicDistance(graph, edge.toNodeId, endNodeId);
        fScore[edge.toNodeId] = estimatedTotal;
        if (!closedSet.contains(edge.toNodeId)) {
          openSet.add(
            _FrontierNode(nodeId: edge.toNodeId, priority: estimatedTotal),
          );
        }
      }
    }

    return null;
  }

  _ShortestPathResult? _runDijkstra(
    _WalkingGraph graph,
    int startNodeId,
    int endNodeId,
  ) {
    final queue =
        _MinHeap<_FrontierNode>((a, b) => a.priority.compareTo(b.priority))
          ..add(_FrontierNode(nodeId: startNodeId, priority: 0));
    final distances = <int, double>{startNodeId: 0};
    final cameFrom = <int, int>{};
    final visited = <int>{};

    while (queue.isNotEmpty) {
      final current = queue.removeFirst().nodeId;
      if (!visited.add(current)) {
        continue;
      }
      if (current == endNodeId) {
        return _reconstructPath(cameFrom, current, distances[current] ?? 0);
      }

      for (final edge in graph.adjacency[current] ?? const <_GraphEdge>[]) {
        final tentative =
            (distances[current] ?? double.infinity) + edge.distanceMeters;
        if (tentative >= (distances[edge.toNodeId] ?? double.infinity)) {
          continue;
        }
        distances[edge.toNodeId] = tentative;
        cameFrom[edge.toNodeId] = current;
        queue.add(_FrontierNode(nodeId: edge.toNodeId, priority: tentative));
      }
    }

    return null;
  }

  double _heuristicDistance(_WalkingGraph graph, int fromNodeId, int toNodeId) {
    final from = graph.nodes[fromNodeId];
    final to = graph.nodes[toNodeId];
    if (from == null || to == null) {
      return 0;
    }
    return Geolocator.distanceBetween(
      from.latitude,
      from.longitude,
      to.latitude,
      to.longitude,
    );
  }

  _ShortestPathResult _reconstructPath(
    Map<int, int> cameFrom,
    int current,
    double distanceMeters,
  ) {
    final path = <int>[current];
    while (cameFrom.containsKey(current)) {
      current = cameFrom[current]!;
      path.add(current);
    }
    return _ShortestPathResult(
      nodeIds: path.reversed.toList(),
      distanceMeters: distanceMeters,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.place_outlined, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Live map tracking',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (widget.isSosActive) ...[
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF3A0B15), Color(0xFF16070A)],
                    ),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: const Color(0xFFFF4D6D).withValues(alpha: 0.30),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFFFF4D6D).withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.graphic_eq_rounded,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'SOS emergency mode is active',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Voice recording is running, and the live route stays focused on nearby police support.',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.78),
                                height: 1.35,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton(
                        onPressed: widget.onStopSos,
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF9F1239),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'Stop',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (_errorMessage != null) ...[
                Text(
                  _errorMessage!,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  height: 520,
                  child: Stack(
                    children: [
                      Positioned.fill(child: _buildMapContent(theme, isDark)),
                      if (!_isLoading && _position != null)
                        Positioned.fill(child: _buildMapOverlay(theme, isDark)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  onPressed: _startWalkingNavigation,
                  icon: const Icon(Icons.directions_walk_rounded),
                  label: const Text(
                    'Show Route in Google Maps',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _initLocationTracking,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Retry Location Access',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMapContent(ThemeData theme, bool isDark) {
    if (_isLoading) {
      return ColoredBox(
        color: isDark ? const Color(0xFF101010) : const Color(0xFFF8FAFC),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: theme.colorScheme.primary),
              const SizedBox(height: 14),
              Text(
                'Acquiring GPS signal...',
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.82),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'This may take longer when offline.',
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.66),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_position == null ||
        !_position!.latitude.isFinite ||
        !_position!.longitude.isFinite) {
      return ColoredBox(
        color: isDark ? const Color(0xFF101010) : const Color(0xFFF8FAFC),
        child: Center(
          child: Text(
            'Location unavailable',
            style: TextStyle(color: theme.colorScheme.onSurface),
          ),
        ),
      );
    }

    final current = latlng.LatLng(_position!.latitude, _position!.longitude);
    final destination = _nearestPoliceStation != null &&
            _nearestPoliceStation!.latitude.isFinite &&
            _nearestPoliceStation!.longitude.isFinite
        ? _nearestPoliceStation
        : null;
    final routePoints = _routePoints.length >= 2
        ? _routePoints
        : (destination != null
            ? [current, destination]
            : const <latlng.LatLng>[]);

    return Listener(
      onPointerDown: (_) => _activePointers++,
      onPointerUp: (_) {
        _activePointers = (_activePointers - 1).clamp(0, 99);
        if (_activePointers == 0) _flushPendingPosition();
      },
      onPointerCancel: (_) {
        _activePointers = (_activePointers - 1).clamp(0, 99);
        if (_activePointers == 0) _flushPendingPosition();
      },
      child: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: current,
          initialZoom: 16,
          maxZoom: 22,
          minZoom: 3,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.aegixa',
            retinaMode: RetinaMode.isHighDensity(context),
            maxNativeZoom: 19,
            keepBuffer: 8,
            panBuffer: 4,
          ),
          if (routePoints.length >= 2 &&
              routePoints
                  .every((p) => p.latitude.isFinite && p.longitude.isFinite))
            PolylineLayer(
              polylines: [
                Polyline(
                  points: routePoints,
                  color: theme.colorScheme.primary.withValues(alpha: 0.9),
                  strokeWidth: 6,
                ),
              ],
            ),
          CircleLayer(
            circles: [
              CircleMarker(
                point: current,
                radius:
                    (_position!.accuracy.isFinite ? _position!.accuracy : 20.0)
                            .clamp(20, 120)
                            .toDouble() /
                        2,
                color: theme.colorScheme.primary.withValues(alpha: 0.16),
                borderColor: theme.colorScheme.primary.withValues(alpha: 0.55),
                borderStrokeWidth: 1,
              ),
            ],
          ),
          MarkerLayer(
            markers: [
              Marker(
                point: current,
                width: 32,
                height: 32,
                child: _position!.heading >= 0 && _position!.speed > 0.5
                    ? Transform.rotate(
                        angle: _position!.heading * (3.141592653589793 / 180),
                        child: Icon(
                          Icons.navigation,
                          color: theme.colorScheme.primary,
                          size: 28,
                        ),
                      )
                    : Icon(
                        Icons.my_location,
                        color: theme.colorScheme.primary,
                        size: 24,
                      ),
              ),
              if (destination != null)
                Marker(
                  point: destination,
                  width: 36,
                  height: 36,
                  child: const Icon(
                    Icons.local_police,
                    color: Color(0xFFFF4D4F),
                    size: 30,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMapOverlay(ThemeData theme, bool isDark) {
    final distanceText = _routeDistanceKm == null
        ? '--'
        : '${_routeDistanceKm!.toStringAsFixed(_routeDistanceKm! < 10 ? 1 : 0)} km';
    final etaText =
        _routeEtaMinutes == null ? '--' : '${_routeEtaMinutes!.round()} min';

    return IgnorePointer(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Spacer(),
            Align(
              alignment: Alignment.bottomRight,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: isDark ? 0.68 : 0.78),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.14)),
                ),
                child: Text(
                  'Walk: $distanceText   ETA: $etaText',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startWalkingNavigation({bool silent = false}) async {
    final destination = _nearestPoliceStation;
    final current = _position;
    if (destination == null || current == null) {
      if (!mounted || silent) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Waiting for route. Please try again in a moment.'),
        ),
      );
      return;
    }

    final destinationParam = '${destination.latitude},${destination.longitude}';
    final originParam = '${current.latitude},${current.longitude}';
    final googleMapsUri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&origin=$originParam&destination=$destinationParam&travelmode=walking',
    );

    final openedGoogleMaps = await launchUrl(
      googleMapsUri,
      mode: LaunchMode.externalApplication,
    );
    if (openedGoogleMaps || !mounted) {
      return;
    }

    final geoUri = Uri.parse('geo:0,0?q=$destinationParam');
    final openedGeo = await launchUrl(
      geoUri,
      mode: LaunchMode.externalApplication,
    );
    if (openedGeo || !mounted || silent) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open maps app.')),
    );
  }
}

class _PoliceStation {
  const _PoliceStation({required this.name, required this.position});

  final String name;
  final latlng.LatLng position;
}

class _PoliceStationDistance {
  const _PoliceStationDistance({
    required this.station,
    required this.straightLineDistance,
  });

  final _PoliceStation station;
  final double straightLineDistance;
}

class _GraphNodeDistance {
  const _GraphNodeDistance({
    required this.nodeId,
    required this.distanceMeters,
  });

  final int nodeId;
  final double distanceMeters;
}

class _RouteInfo {
  const _RouteInfo({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
  });

  final List<latlng.LatLng> points;
  final double? distanceMeters;
  final double? durationSeconds;
}

class _WalkingGraph {
  const _WalkingGraph({required this.nodes, required this.adjacency});

  final Map<int, latlng.LatLng> nodes;
  final Map<int, List<_GraphEdge>> adjacency;
}

class _FrontierNode {
  const _FrontierNode({required this.nodeId, required this.priority});

  final int nodeId;
  final double priority;
}

class _MinHeap<T> {
  _MinHeap(this._compare);

  final int Function(T a, T b) _compare;
  final List<T> _items = <T>[];

  bool get isNotEmpty => _items.isNotEmpty;

  void add(T value) {
    _items.add(value);
    _siftUp(_items.length - 1);
  }

  T removeFirst() {
    final first = _items.first;
    final last = _items.removeLast();
    if (_items.isNotEmpty) {
      _items[0] = last;
      _siftDown(0);
    }
    return first;
  }

  void _siftUp(int index) {
    var child = index;
    while (child > 0) {
      final parent = (child - 1) ~/ 2;
      if (_compare(_items[child], _items[parent]) >= 0) {
        break;
      }
      _swap(child, parent);
      child = parent;
    }
  }

  void _siftDown(int index) {
    var parent = index;
    while (true) {
      final left = (parent * 2) + 1;
      final right = left + 1;
      var candidate = parent;

      if (left < _items.length &&
          _compare(_items[left], _items[candidate]) < 0) {
        candidate = left;
      }
      if (right < _items.length &&
          _compare(_items[right], _items[candidate]) < 0) {
        candidate = right;
      }
      if (candidate == parent) {
        break;
      }

      _swap(parent, candidate);
      parent = candidate;
    }
  }

  void _swap(int left, int right) {
    final temp = _items[left];
    _items[left] = _items[right];
    _items[right] = temp;
  }
}

class _GraphEdge {
  const _GraphEdge({required this.toNodeId, required this.distanceMeters});

  final int toNodeId;
  final double distanceMeters;
}

class _ShortestPathResult {
  const _ShortestPathResult({
    required this.nodeIds,
    required this.distanceMeters,
  });

  final List<int> nodeIds;
  final double distanceMeters;
}

class _EmergencyContactsTab extends StatefulWidget {
  const _EmergencyContactsTab();

  @override
  State<_EmergencyContactsTab> createState() => _EmergencyContactsTabState();
}

class _EmergencyContactsTabState extends State<_EmergencyContactsTab> {
  final _service = EmergencyContactsService();
  bool _isLoading = true;
  List<EmergencyContact> _contacts = const [];

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    try {
      final contacts = await _service.getContacts();
      if (!mounted) {
        return;
      }
      setState(() {
        _contacts = contacts;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
      });
      final message = e.toString().replaceFirst('Bad state: ', '').trim();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            message.isEmpty ? 'Could not load emergency contacts.' : message,
          ),
        ),
      );
    }
  }

  Future<void> _openContactSheet({EmergencyContact? contact}) async {
    final didSave = await showEmergencyContactEditorSheet(
      context,
      contact: contact,
      suggestPrimary: _contacts.isEmpty,
      onSave: _service.saveContact,
    );
    if (!mounted || !didSave) return;
    await _loadContacts();
  }

  Future<void> _callContact(String phoneNumber) async {
    final uri = Uri(scheme: 'tel', path: phoneNumber);
    if (!await launchUrl(uri)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not place the call.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (_isLoading) {
      return const Center(
        child: AegixaLoader(),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Text(
              'Emergency Contacts',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: () => _openContactSheet(),
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_contacts.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 36),
              child: Text(
                'No contacts saved yet',
                style: TextStyle(
                  color: isDark
                      ? const Color(0xFFA3A3A3)
                      : const Color(0xFF6B7280),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          )
        else
          ..._contacts.map(
            (contact) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _StoredEmergencyContactTile(
                contact: contact,
                onCall: () => _callContact(contact.phoneNumber),
                onEdit: () => _openContactSheet(contact: contact),
                onDelete: () async {
                  await _service.deleteContact(contact.id!);
                  await _loadContacts();
                },
              ),
            ),
          ),
      ],
    );
  }
}

class _StoredEmergencyContactTile extends StatelessWidget {
  const _StoredEmergencyContactTile({
    required this.contact,
    required this.onCall,
    required this.onEdit,
    required this.onDelete,
  });

  final EmergencyContact contact;
  final VoidCallback onCall;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  bool _isRemotePath(String? value) {
    final path = (value ?? '').trim().toLowerCase();
    return path.startsWith('http://') || path.startsWith('https://');
  }

  ImageProvider<Object>? _contactImageProvider() {
    final path = (contact.profilePhotoPath ?? '').trim();
    if (path.isEmpty) {
      return null;
    }
    if (_isRemotePath(path)) {
      return NetworkImage(path);
    }
    final file = File(path);
    if (file.existsSync()) {
      return FileImage(file);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final imageProvider = _contactImageProvider();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0D0D0D) : const Color(0xFFFBFBFD),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE5E7EB),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor:
                    theme.colorScheme.primary.withValues(alpha: 0.12),
                foregroundColor: theme.colorScheme.primary,
                backgroundImage: imageProvider,
                child: imageProvider == null
                    ? const Icon(Icons.person_outline)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      contact.name,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      contact.phoneNumber,
                      style: TextStyle(
                        color: isDark
                            ? const Color(0xFFA3A3A3)
                            : const Color(0xFF6B7280),
                      ),
                    ),
                    if ((contact.username ?? '').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          '@${contact.username}',
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (contact.isPrimary)
                Container(
                  margin: const EdgeInsets.only(right: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Primary',
                    style: TextStyle(
                      color: isDark ? Colors.black : Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') {
                    onEdit();
                  } else if (value == 'delete') {
                    onDelete();
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem<String>(value: 'edit', child: Text('Edit')),
                  PopupMenuItem<String>(value: 'delete', child: Text('Delete')),
                ],
                icon: Icon(Icons.more_vert, color: theme.colorScheme.onSurface),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onCall,
                  icon: const Icon(Icons.call_outlined, size: 18),
                  label: const Text('Call'),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Edit'),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProfileMetaChip extends StatelessWidget {
  const _ProfileMetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF151515) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isDark ? const Color(0xFF272727) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: isDark ? const Color(0xFFA3A3A3) : const Color(0xFF64748B),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? const Color(0xFFD4D4D4) : const Color(0xFF334155),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileTab extends StatefulWidget {
  const _ProfileTab({
    required this.user,
    required this.onProfilePhotoChanged,
  });

  final User? user;
  final ValueChanged<String?> onProfilePhotoChanged;

  @override
  State<_ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<_ProfileTab> {
  final _service = EmergencyContactsService();
  final _usernameService = UsernameService();
  final _imagePicker = ImagePicker();
  bool _isLoadingContacts = true;
  List<EmergencyContact> _contacts = const [];
  String? _username;
  String? _profilePhotoPath;

  bool _isRemotePhoto(String? value) {
    final path = (value ?? '').trim().toLowerCase();
    return path.startsWith('http://') || path.startsWith('https://');
  }

  ImageProvider<Object>? _profileImageProvider() {
    final pathValue = (_profilePhotoPath ?? '').trim();
    if (pathValue.isEmpty) {
      return null;
    }
    if (_isRemotePhoto(pathValue)) {
      return NetworkImage(pathValue);
    }
    final file = File(pathValue);
    if (file.existsSync()) {
      return FileImage(file);
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _loadContacts();
    _loadUsername();
    _loadProfilePhoto();
  }

  Future<void> _loadProfilePhoto() async {
    final userId = widget.user?.uid;
    if (userId == null) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();

    // Show cached photo immediately while we fetch the remote one.
    final cachedPath = (prefs.getString('profile_photo_$userId') ?? '').trim();
    if (cachedPath.isNotEmpty && mounted) {
      setState(() {
        _profilePhotoPath = cachedPath;
      });
      widget.onProfilePhotoChanged(cachedPath);
    }

    // Then try remote.
    try {
      final remoteProfile =
          await _usernameService.getPublicProfileForUserId(userId);
      final remotePath = (remoteProfile?.profilePhotoPath ?? '').trim();

      // Prefer remote URL; fall back to cached local path.
      final resolvedPath = remotePath.isNotEmpty ? remotePath : cachedPath;

      if (resolvedPath.isNotEmpty) {
        await prefs.setString('profile_photo_$userId', resolvedPath);
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _profilePhotoPath = resolvedPath.isEmpty ? null : resolvedPath;
      });
      widget.onProfilePhotoChanged(resolvedPath.isEmpty ? null : resolvedPath);
    } catch (_) {
      // Network error — keep using the cached photo (already set above).
    }
  }

  Future<void> _pickProfilePhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose from gallery'),
                onTap: () =>
                    Navigator.of(sheetContext).pop(ImageSource.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Take a photo'),
                onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
              ),
            ],
          ),
        );
      },
    );

    if (source == null || widget.user == null) {
      return;
    }

    final picked = await _imagePicker.pickImage(
      source: source,
      maxWidth: 1200,
      imageQuality: 85,
    );
    if (picked == null) {
      return;
    }

    final appDirectory = await getApplicationDocumentsDirectory();
    final profileDirectory =
        Directory(path.join(appDirectory.path, 'profile_photos'));
    await profileDirectory.create(recursive: true);

    final extension = path.extension(picked.path).toLowerCase();
    final safeExtension = extension.isEmpty
        ? '.jpg'
        : (extension.length > 5 ? '.jpg' : extension);
    final targetPath = path.join(
      profileDirectory.path,
      'profile_${widget.user!.uid}$safeExtension',
    );
    final savedFile = await File(picked.path).copy(targetPath);

    var finalPath = savedFile.path;
    String? uploadError;
    try {
      final uploadedUrl = await _usernameService.uploadProfilePhoto(
        user: widget.user!,
        localFilePath: savedFile.path,
      );
      if ((uploadedUrl ?? '').trim().isNotEmpty) {
        finalPath = uploadedUrl!.trim();
      }
    } catch (e) {
      uploadError = e.toString();
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('profile_photo_${widget.user!.uid}', finalPath);

    // If _username hasn't loaded yet (race condition), fetch it now so we
    // don't silently skip saving the photo URL to Supabase.
    var username = (_username ?? '').trim();
    if (username.isEmpty) {
      try {
        username =
            (await _usernameService.getUsernameForUserId(widget.user!.uid) ??
                    '')
                .trim();
        if (username.isNotEmpty) {
          setState(() {
            _username = username;
          });
        }
      } catch (_) {}
    }

    // Only write photo_path to Supabase when we have a remote URL.
    // Never overwrite an existing remote URL with an empty string on
    // upload failure.
    if (username.isNotEmpty && _isRemotePhoto(finalPath)) {
      await _usernameService.upsertPublicProfile(
        user: widget.user!,
        username: username,
        displayName: widget.user!.displayName,
        photoPath: finalPath,
      );
    }

    if (!mounted) {
      return;
    }
    if (!_isRemotePhoto(finalPath)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            uploadError != null
                ? 'Photo upload failed: $uploadError'
                : 'Photo saved on this device only. Check internet and try again to sync it.',
          ),
        ),
      );
    }

    setState(() {
      _profilePhotoPath = finalPath;
    });
    widget.onProfilePhotoChanged(finalPath);
  }

  Future<void> _loadUsername() async {
    final userId = widget.user?.uid;
    if (userId == null) {
      return;
    }
    String? username;
    try {
      username = await _usernameService.getUsernameForUserId(userId);
    } catch (_) {
      username = null;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _username = username;
    });
  }

  Future<void> _loadContacts() async {
    try {
      final contacts = await _service.getContacts();
      if (!mounted) {
        return;
      }
      setState(() {
        _contacts = contacts;
        _isLoadingContacts = false;
      });

      final mergedContacts = await _syncContactProfilePhotos(contacts);
      if (!mounted) {
        return;
      }
      setState(() {
        _contacts = mergedContacts;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoadingContacts = false;
      });
      final message = e.toString().replaceFirst('Bad state: ', '').trim();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            message.isEmpty ? 'Could not load emergency contacts.' : message,
          ),
        ),
      );
    }
  }

  Future<List<EmergencyContact>> _syncContactProfilePhotos(
    List<EmergencyContact> contacts,
  ) async {
    final updated = <EmergencyContact>[];
    for (final contact in contacts) {
      final username = (contact.username ?? '').trim();
      if (username.isEmpty) {
        updated.add(contact);
        continue;
      }

      try {
        // Use direct profile lookup instead of searchUsers, which can
        // silently fail to enrich the photo_path field.
        final profile = await _usernameService
            .getPublicProfileForUsername(username)
            .timeout(const Duration(seconds: 2), onTimeout: () => null);
        final remotePhoto = (profile?.profilePhotoPath ?? '').trim();
        final currentPhoto = (contact.profilePhotoPath ?? '').trim();

        // Only update if remote has a real photo; never overwrite a valid
        // photo with an empty string (e.g. when the lookup returns no match).
        if (remotePhoto.isNotEmpty && remotePhoto != currentPhoto) {
          final merged = contact.copyWith(profilePhotoPath: remotePhoto);
          await _service.saveContact(merged);
          updated.add(merged);
        } else {
          updated.add(contact);
        }
      } catch (_) {
        updated.add(contact);
      }
    }
    return updated;
  }

  Future<void> _openContactSheet({EmergencyContact? contact}) async {
    final didSave = await showEmergencyContactEditorSheet(
      context,
      contact: contact,
      suggestPrimary: _contacts.isEmpty,
      currentUserUid: widget.user?.uid,
      existingContacts: _contacts,
      onSave: _service.saveContact,
    );
    if (!mounted || !didSave) {
      return;
    }
    await _loadContacts();
  }

  Future<void> _callContact(String phoneNumber) async {
    final uri = Uri(scheme: 'tel', path: phoneNumber);
    if (!await launchUrl(uri)) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not place the call.')),
      );
    }
  }

  String _profileName() {
    final user = widget.user;
    if ((user?.displayName ?? '').trim().isNotEmpty) {
      return user!.displayName!.trim();
    }
    if ((user?.email ?? '').trim().isNotEmpty) {
      return user!.email!.split('@').first;
    }
    return 'Aegixa User';
  }

  String _profileInitials() {
    final parts = _profileName()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      return 'P';
    }
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final contactCount = _contacts.length;
    final user = widget.user;
    final hasUsername = (_username ?? '').isNotEmpty;
    final hasPhone = (user?.phoneNumber ?? '').isNotEmpty;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? const [Color(0xFF191919), Color(0xFF0E0E0E)]
                  : const [Color(0xFFFFFBFD), Color(0xFFF5F7FF)],
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE8EAF2),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.06),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  CircleAvatar(
                    radius: 34,
                    backgroundColor:
                        theme.colorScheme.primary.withValues(alpha: 0.18),
                    backgroundImage: _profileImageProvider(),
                    child: _profileImageProvider() == null
                        ? Text(
                            _profileInitials(),
                            style: TextStyle(
                              color: theme.colorScheme.primary,
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                            ),
                          )
                        : null,
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: InkWell(
                      onTap: _pickProfilePhoto,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isDark ? Colors.black : Colors.white,
                            width: 2,
                          ),
                        ),
                        child: const Icon(
                          Icons.photo_camera_outlined,
                          size: 12,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _profileName(),
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (hasUsername)
                      Text(
                        '@${_username!}',
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    if (hasUsername) const SizedBox(height: 4),
                    if ((user?.email ?? '').isNotEmpty)
                      Text(
                        user!.email!,
                        style: TextStyle(
                          color: isDark
                              ? const Color(0xFFA3A3A3)
                              : const Color(0xFF6B7280),
                        ),
                      ),
                    if ((user?.phoneNumber ?? '').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          user!.phoneNumber!,
                          style: TextStyle(
                            color: isDark
                                ? const Color(0xFFA3A3A3)
                                : const Color(0xFF6B7280),
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _ProfileMetaChip(
                          icon: Icons.groups_2_outlined,
                          label: '$contactCount contacts',
                        ),
                        if (hasPhone)
                          const _ProfileMetaChip(
                            icon: Icons.phone_outlined,
                            label: 'Phone linked',
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your Contacts',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _openContactSheet(),
                  icon: const Icon(Icons.add),
                  label: const Text('Add contact'),
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: isDark ? Colors.black : Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              if (_isLoadingContacts)
                const Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: AegixaLoader(),
                  ),
                )
              else if (_contacts.isEmpty)
                Text(
                  'No primary contacts saved yet.',
                  style: TextStyle(
                    color: isDark
                        ? const Color(0xFFA3A3A3)
                        : const Color(0xFF6B7280),
                    fontWeight: FontWeight.w500,
                  ),
                )
              else
                ..._contacts.map(
                  (contact) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _StoredEmergencyContactTile(
                      contact: contact,
                      onCall: () => _callContact(contact.phoneNumber),
                      onEdit: () => _openContactSheet(contact: contact),
                      onDelete: () async {
                        await _service.deleteContact(contact.id!);
                        await _loadContacts();
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingsTab extends StatelessWidget {
  const _SettingsTab({
    required this.user,
    required this.themeModeController,
    required this.onOpenEmergencyContacts,
    required this.onOpenSosInbox,
    required this.onLogout,
    required this.autoVideoRecord,
    required this.autoVoiceRecord,
    required this.vibrationOnSos,
    required this.hardwareSosShortcutEnabled,
    required this.hardwareSosPermissionEnabled,
    required this.holdDuration,
    required this.onOpenBatteryOptimizationSettings,
    required this.onManageSubscription,
    required this.onAutoVideoRecordChanged,
    required this.onAutoVoiceRecordChanged,
    required this.onVibrationOnSosChanged,
    required this.onOpenHardwareShortcutSettings,
    required this.onHardwareSosShortcutChanged,
    required this.onHoldDurationChanged,
  });

  final User? user;
  final ValueNotifier<ThemeMode> themeModeController;
  final VoidCallback onOpenEmergencyContacts;
  final VoidCallback onOpenSosInbox;
  final Future<void> Function() onLogout;
  final bool autoVideoRecord;
  final bool autoVoiceRecord;
  final bool vibrationOnSos;
  final bool hardwareSosShortcutEnabled;
  final bool hardwareSosPermissionEnabled;
  final int holdDuration;
  final Future<void> Function() onOpenBatteryOptimizationSettings;
  final Future<void> Function() onManageSubscription;
  final ValueChanged<bool> onAutoVideoRecordChanged;
  final ValueChanged<bool> onAutoVoiceRecordChanged;
  final ValueChanged<bool> onVibrationOnSosChanged;
  final Future<void> Function() onOpenHardwareShortcutSettings;
  final ValueChanged<bool> onHardwareSosShortcutChanged;
  final ValueChanged<int> onHoldDurationChanged;

  static final Uri _termsUri = Uri.parse(
    'https://protego-51833.web.app/terms',
  );
  static final Uri _privacyUri = Uri.parse(
    'https://protego-51833.web.app/privacy',
  );

  Future<void> _openLegalPage(BuildContext context, Uri uri) async {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (opened || !context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open link right now.')),
    );
  }

  Future<void> _showAccountDetailsSheet(BuildContext context) async {
    final currentUser = user;
    if (currentUser == null) {
      return;
    }
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return FutureBuilder<String?>(
          future: UsernameService().getUsernameForUserId(currentUser.uid),
          builder: (context, snapshot) {
            final username = snapshot.data;
            return SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(24)),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF2A2A2A)
                        : const Color(0xFFE5E7EB),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF3A3A3A)
                              : const Color(0xFFD1D5DB),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Account details',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _buildAccountRow(
                        context,
                        'Username',
                        (username?.isNotEmpty ?? false)
                            ? '@$username'
                            : 'Not set'),
                    _buildAccountRow(
                        context, 'Name', currentUser.displayName ?? 'Not set'),
                    _buildAccountRow(
                        context, 'Email', currentUser.email ?? 'Not linked'),
                    _buildAccountRow(context, 'Phone',
                        currentUser.phoneNumber ?? 'Not linked'),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Done'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildAccountRow(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 86,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color:
                    isDark ? const Color(0xFFA3A3A3) : const Color(0xFF6B7280),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Log out?'),
          content: const Text('You will need to sign in again to continue.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              style: TextButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE11D48),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Log out'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await onLogout();
      if (!context.mounted) {
        return;
      }

      if (FirebaseAuth.instance.currentUser != null) {
        await FirebaseAuth.instance.signOut();
      }

      if (!context.mounted) {
        return;
      }

      if (FirebaseAuth.instance.currentUser != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Could not complete logout. Please try again.')),
        );
        return;
      }

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthGate()),
        (route) => false,
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not log out. Please try again.')),
      );
    }
  }

  Future<void> _showThemeModeSheet(BuildContext context) async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return ValueListenableBuilder<ThemeMode>(
          valueListenable: themeModeController,
          builder: (context, selectedMode, _) {
            return SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(24)),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF2A2A2A)
                        : const Color(0xFFE5E7EB),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF3A3A3A)
                            : const Color(0xFFD1D5DB),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(height: 14),
                    SegmentedButton<ThemeMode>(
                      style: SegmentedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      segments: const [
                        ButtonSegment<ThemeMode>(
                          value: ThemeMode.system,
                          label: Text('System'),
                          icon: Icon(Icons.settings_suggest_outlined),
                        ),
                        ButtonSegment<ThemeMode>(
                          value: ThemeMode.light,
                          label: Text('Light'),
                          icon: Icon(Icons.light_mode_outlined),
                        ),
                        ButtonSegment<ThemeMode>(
                          value: ThemeMode.dark,
                          label: Text('Dark'),
                          icon: Icon(Icons.dark_mode_outlined),
                        ),
                      ],
                      selected: <ThemeMode>{selectedMode},
                      onSelectionChanged: (selection) {
                        themeModeController.value = selection.first;
                      },
                    ),
                    const SizedBox(height: 14),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const _SettingsSectionHeader(title: 'Account'),
        _SurfaceCard(
          child: Column(
            children: [
              _SettingsTile(
                assetIconPath: 'assets/add-contact.png',
                title: 'Profile & contacts',
                subtitle: '',
                onTap: onOpenEmergencyContacts,
              ),
              const SizedBox(height: 10),
              _SettingsTile(
                assetIconPath: 'assets/profile.png',
                title: 'Account details',
                subtitle: '',
                onTap: () => _showAccountDetailsSheet(context),
              ),
              const SizedBox(height: 10),
              _SettingsTile(
                assetIconPath: 'assets/folder.png',
                title: 'SOS recordings',
                subtitle: '',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const SosRecordingsScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
              _SettingsTile(
                assetIconPath: 'assets/profile.png',
                title: 'Manage subscription',
                subtitle: '',
                onTap: () async {
                  await onManageSubscription();
                },
              ),
              const SizedBox(height: 10),
              _SettingsTile(
                title: 'SOS inbox',
                subtitle: '',
                onTap: onOpenSosInbox,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const _SettingsSectionHeader(title: 'Preferences'),
        _SurfaceCard(
          child: Column(
            children: [
              ValueListenableBuilder<ThemeMode>(
                valueListenable: themeModeController,
                builder: (context, mode, _) {
                  final subtitle = switch (mode) {
                    ThemeMode.system => 'System',
                    ThemeMode.light => 'Light',
                    ThemeMode.dark => 'Dark',
                  };

                  return _SettingsTile(
                    assetIconPath: 'assets/night-mode.png',
                    title: 'Theme mode',
                    subtitle: subtitle,
                    onTap: () => _showThemeModeSheet(context),
                  );
                },
              ),
              const SizedBox(height: 10),
              _SettingsTile(
                iconData: Icons.battery_saver_outlined,
                title: 'Battery optimization',
                subtitle: 'Disable it on Android for faster panic alerts.',
                onTap: () async {
                  await onOpenBatteryOptimizationSettings();
                },
              ),
              const SizedBox(height: 10),
              _SettingsTile(
                iconData: Icons.phonelink_setup_outlined,
                title: 'OEM background guide',
                subtitle: 'Brand-specific autostart and battery steps.',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const BatteryOptimizationGuideScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const _SettingsSectionHeader(title: 'SOS Automation'),
        _SurfaceCard(
          child: Column(
            children: [
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: autoVideoRecord,
                onChanged: onAutoVideoRecordChanged,
                title: const Text(
                  'Auto video record',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const Divider(height: 1),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: autoVoiceRecord,
                onChanged: onAutoVoiceRecordChanged,
                title: const Text(
                  'Auto voice record',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const Divider(height: 1),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: vibrationOnSos,
                onChanged: onVibrationOnSosChanged,
                title: const Text(
                  'Vibration on SOS',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const Divider(height: 1),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: hardwareSosShortcutEnabled,
                onChanged: onHardwareSosShortcutChanged,
                title: const Text(
                  'Volume down x3 shortcut',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const Text(
                  'Press volume down 3 times quickly to trigger SOS.',
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 2),
                  child: Text(
                    hardwareSosPermissionEnabled
                        ? 'Accessibility permission: Enabled'
                        : 'Accessibility permission: Not enabled',
                    style: TextStyle(
                      color: hardwareSosPermissionEnabled
                          ? const Color(0xFF16A34A)
                          : Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.72),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onOpenHardwareShortcutSettings,
                  icon: const Icon(Icons.settings_accessibility_outlined),
                  label: const Text('Enable in Android Accessibility settings'),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Hold Duration to Trigger SOS',
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SegmentedButton<int>(
                style: SegmentedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                segments: const [
                  ButtonSegment<int>(value: 2, label: Text('2s')),
                  ButtonSegment<int>(value: 5, label: Text('5s')),
                  ButtonSegment<int>(value: 7, label: Text('7s')),
                ],
                selected: <int>{holdDuration},
                onSelectionChanged: (selection) {
                  onHoldDurationChanged(selection.first);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const _SettingsSectionHeader(title: 'Legal'),
        _SurfaceCard(
          child: Column(
            children: [
              _SettingsTile(
                assetIconPath: 'assets/folder.png',
                title: 'Terms of Service',
                subtitle: '',
                onTap: () => _openLegalPage(context, _termsUri),
              ),
              const SizedBox(height: 10),
              _SettingsTile(
                assetIconPath: 'assets/folder.png',
                title: 'Privacy Policy',
                subtitle: '',
                onTap: () => _openLegalPage(context, _privacyUri),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const _SettingsSectionHeader(title: 'Security'),
        _SurfaceCard(
          child: _SettingsTile(
            assetIconPath: 'assets/logout.png',
            title: 'Logout',
            subtitle: '',
            onTap: () => _handleLogout(context),
            isDestructive: true,
          ),
        ),
      ],
    );
  }
}

class _SettingsSectionHeader extends StatelessWidget {
  const _SettingsSectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: isDark ? const Color(0xFFA3A3A3) : const Color(0xFF6B7280),
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.title,
    required this.subtitle,
    this.assetIconPath,
    this.iconData,
    this.onTap,
    this.isDestructive = false,
  });

  final String? assetIconPath;
  final IconData? iconData;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF171717)
                      : const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: iconData != null
                      ? Icon(
                          iconData,
                          color: isDark
                              ? Colors.white
                              : theme.colorScheme.onSurface
                                  .withValues(alpha: 0.85),
                          size: 21,
                        )
                      : assetIconPath != null
                          ? Image.asset(
                              assetIconPath!,
                              width: 21,
                              height: 21,
                              color: isDark ? Colors.white : null,
                            )
                          : Icon(
                              Icons.circle,
                              color: isDestructive
                                  ? const Color(0xFFE11D48)
                                  : theme.colorScheme.onSurface,
                              size: 21,
                            ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: isDestructive
                            ? const Color(0xFFE11D48)
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.62),
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SurfaceCard extends StatelessWidget {
  const _SurfaceCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE5E7EB),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}
