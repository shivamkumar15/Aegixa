import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'battery_optimization_guide_screen.dart';
import '../services/device_settings_service.dart';

import '../ui_components.dart';

class AppPermissionsScreen extends StatefulWidget {
  const AppPermissionsScreen({super.key, required this.onCompleted});

  final VoidCallback onCompleted;

  static const permissionsPrefsKey = 'app_permissions_completed_v2';

  @override
  State<AppPermissionsScreen> createState() => _AppPermissionsScreenState();
}

class _AppPermissionsScreenState extends State<AppPermissionsScreen>
    with WidgetsBindingObserver {
  final AudioRecorder _recorder = AudioRecorder();
  bool _isChecking = true;
  bool _isSubmitting = false;
  bool _locationGranted = false;
  bool _micGranted = false;
  bool _cameraGranted = false;
  bool _notificationsGranted = false;
  bool _overlayGranted = false;
  bool _locationServiceEnabled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshPermissionState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _recorder.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshPermissionState();
    }
  }

  Future<void> _refreshPermissionState() async {
    final locationServiceEnabled = await Geolocator.isLocationServiceEnabled();
    final locationPermission = await Geolocator.checkPermission();
    final micGranted = await _safeMicPermissionCheck();
    final cameraGranted = await Permission.camera.isGranted;
    final notificationsGranted = await _isNotificationPermissionGranted();
    final overlayGranted = await _isOverlayPermissionGranted();

    if (!mounted) {
      return;
    }

    setState(() {
      _locationServiceEnabled = locationServiceEnabled;
      _locationGranted = locationPermission == LocationPermission.always ||
          locationPermission == LocationPermission.whileInUse;
      _micGranted = micGranted;
      _cameraGranted = cameraGranted;
      _notificationsGranted = notificationsGranted;
      _overlayGranted = overlayGranted;
      _isChecking = false;
    });

    if (_hasAllRequiredPermissions) {
      await _markComplete();
    }
  }

  bool get _hasAllRequiredPermissions =>
      _locationServiceEnabled &&
      _locationGranted &&
      _micGranted &&
      _cameraGranted &&
      _notificationsGranted &&
      _overlayGranted;

  Future<void> _markComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppPermissionsScreen.permissionsPrefsKey, true);
    if (mounted) {
      widget.onCompleted();
    }
  }

  Future<void> _requestAllPermissions() async {
    if (_isSubmitting) {
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      var serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        await Geolocator.openLocationSettings();
      }

      var locationPermission = await Geolocator.checkPermission();
      if (locationPermission == LocationPermission.denied) {
        locationPermission = await Geolocator.requestPermission();
      }
      if (locationPermission == LocationPermission.deniedForever) {
        await Geolocator.openAppSettings();
      }

      final micGranted = await _safeMicPermissionCheck();
      if (!micGranted) {
        await Permission.microphone.request();
      }

      final cameraStatus = await Permission.camera.request();
      if (cameraStatus.isPermanentlyDenied) {
        await openAppSettings();
      }

      final notificationStatus = await Permission.notification.request();
      if (notificationStatus.isPermanentlyDenied) {
        await openAppSettings();
      }

      if (!await _isOverlayPermissionGranted()) {
        if (Platform.isAndroid) {
          await FlutterOverlayWindow.requestPermission();
        }
      }

      await _refreshPermissionState();

      if (!mounted) {
        return;
      }

      final allGranted = _hasAllRequiredPermissions;
      if (!allGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Please allow location, microphone, camera, notifications, overlay access, and keep location services on to continue.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<bool> _safeMicPermissionCheck() async {
    try {
      return await _recorder.hasPermission();
    } catch (_) {
      return false;
    }
  }

  Future<bool> _isNotificationPermissionGranted() async {
    final status = await Permission.notification.status;
    return status.isGranted || status.isLimited || status.isProvisional;
  }

  Future<bool> _isOverlayPermissionGranted() async {
    if (!Platform.isAndroid) {
      return true;
    }
    final status = await Permission.systemAlertWindow.status;
    if (status.isGranted) {
      return true;
    }
    return FlutterOverlayWindow.isPermissionGranted();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: _isChecking
              ? const Center(
                  child: AegixaLoader(),
                )
              : ListView(
                  children: [
                    Center(
                      child: Image.asset(
                        'assets/Logo.png',
                        height: 100,
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Enable core permissions',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Aegixa needs location, microphone, camera, notification, and overlay access from the start so SOS, live tracking, emergency evidence, and panic alerts work instantly.',
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.6,
                        color: Color(0xFFA3A3A3),
                      ),
                    ),
                    if (Platform.isAndroid) ...[
                      const SizedBox(height: 18),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Battery optimization can block emergency alerts',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'On many Android phones, panic notifications can be delayed unless Aegixa is excluded from battery optimization.',
                              style: TextStyle(
                                height: 1.45,
                                color: Color(0xFFA3A3A3),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () async {
                                    await DeviceSettingsService
                                        .openBatteryOptimizationSettings();
                                  },
                                  icon: const Icon(Icons.battery_alert_outlined),
                                  label: const Text('Open battery settings'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    side: const BorderSide(color: Colors.white24),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                TextButton(
                                  onPressed: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const BatteryOptimizationGuideScreen(),
                                      ),
                                    );
                                  },
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.white70,
                                  ),
                                  child: const Text(
                                    'Guide',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 26),
                    _PermissionStatusTile(
                      icon: Icons.location_on_outlined,
                      title: 'Location access',
                      subtitle: _locationServiceEnabled
                          ? 'Required for live route and nearby police navigation.'
                          : 'Turn on device location services to continue.',
                      isGranted: _locationGranted && _locationServiceEnabled,
                    ),
                    const SizedBox(height: 12),
                    _PermissionStatusTile(
                      icon: Icons.mic_none_rounded,
                      title: 'Microphone access',
                      subtitle:
                          'Required to record audio automatically during SOS.',
                      isGranted: _micGranted,
                    ),
                    const SizedBox(height: 12),
                    _PermissionStatusTile(
                      icon: Icons.videocam_outlined,
                      title: 'Camera access',
                      subtitle:
                          'Required for SOS video capture and emergency evidence.',
                      isGranted: _cameraGranted,
                    ),
                    const SizedBox(height: 12),
                    _PermissionStatusTile(
                      icon: Icons.notifications_active_outlined,
                      title: 'Notification access',
                      subtitle:
                          'Required so incoming SOS alerts can break through immediately.',
                      isGranted: _notificationsGranted,
                    ),
                    const SizedBox(height: 12),
                    _PermissionStatusTile(
                      icon: Icons.picture_in_picture_alt_outlined,
                      title: 'Overlay access',
                      subtitle:
                          'Required on Android to show panic alerts on top of other apps.',
                      isGranted: _overlayGranted,
                    ),
                    const SizedBox(height: 20),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed:
                            _isSubmitting ? null : _requestAllPermissions,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          elevation: 0,
                        ),
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.black,
                                ),
                              )
                            : const Text(
                                'Allow Permissions',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _PermissionStatusTile extends StatelessWidget {
  const _PermissionStatusTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isGranted,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool isGranted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 60,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isGranted ? Colors.pink : Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: isGranted
                ? const Text(
                    'DONE',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  )
                : Icon(
                    icon,
                    color: Colors.white70,
                    size: 18,
                  ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFFA3A3A3),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
