import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';

import '../services/device_settings_service.dart';

class BatteryOptimizationGuideScreen extends StatefulWidget {
  const BatteryOptimizationGuideScreen({super.key});

  @override
  State<BatteryOptimizationGuideScreen> createState() =>
      _BatteryOptimizationGuideScreenState();
}

class _BatteryOptimizationGuideScreenState
    extends State<BatteryOptimizationGuideScreen> {
  static const _guides = <_OemGuideSection>[
    _OemGuideSection(
      brand: 'Samsung',
      matchers: ['samsung'],
      icon: Icons.phone_android_outlined,
      steps: [
        'Open Settings > Battery > Background usage limits.',
        'Remove Sailor from Sleeping apps and Deep sleeping apps.',
        'Open Settings > Apps > Sailor > Battery.',
        'Set battery usage to Unrestricted.',
      ],
    ),
    _OemGuideSection(
      brand: 'Xiaomi / Redmi / Poco',
      matchers: ['xiaomi', 'redmi', 'poco', 'miui'],
      icon: Icons.bolt_outlined,
      steps: [
        'Open Settings > Apps > Manage apps > Sailor.',
        'Open Autostart and allow it.',
        'Open Battery saver and choose No restrictions.',
        'In Recent apps, lock Sailor so MIUI does not clear it.',
      ],
    ),
    _OemGuideSection(
      brand: 'OnePlus / Oppo / Realme',
      matchers: ['oneplus', 'oppo', 'realme', 'coloros'],
      icon: Icons.notifications_active_outlined,
      steps: [
        'Open Settings > Apps > App management > Sailor.',
        'Open Battery usage or Battery.',
        'Allow background activity and set optimization to Don\'t optimize.',
        'If available, enable Auto-launch or Auto start.',
      ],
    ),
    _OemGuideSection(
      brand: 'Vivo / iQOO',
      matchers: ['vivo', 'iqoo'],
      icon: Icons.flash_on_outlined,
      steps: [
        'Open i Manager or Settings > Apps > Sailor.',
        'Enable Autostart for Sailor.',
        'Open Battery > High background power consumption.',
        'Allow Sailor to run in the background without restrictions.',
      ],
    ),
    _OemGuideSection(
      brand: 'Huawei / Honor',
      matchers: ['huawei', 'honor'],
      icon: Icons.security_outlined,
      steps: [
        'Open Settings > Apps > Launch > Sailor.',
        'Disable Manage automatically.',
        'Enable Auto-launch, Secondary launch, and Run in background.',
        'Open Battery > App launch and confirm Sailor stays allowed.',
      ],
    ),
    _OemGuideSection(
      brand: 'Pixel / Motorola / Nokia',
      matchers: ['google', 'pixel', 'motorola', 'moto', 'nokia'],
      icon: Icons.settings_cell_outlined,
      steps: [
        'Open Settings > Apps > Sailor > App battery usage.',
        'Set battery mode to Unrestricted.',
        'Open Notifications and make sure panic alerts are enabled.',
        'If alerts still delay, also allow Sailor in system battery optimization settings.',
      ],
    ),
  ];

  String? _detectedLabel;
  String? _detectedMatcher;

  @override
  void initState() {
    super.initState();
    _loadDeviceBrand();
  }

  Future<void> _loadDeviceBrand() async {
    if (!Platform.isAndroid) {
      return;
    }

    try {
      final info = await DeviceInfoPlugin().androidInfo;
      final manufacturer = info.manufacturer.trim();
      final brand = info.brand.trim();
      final model = info.model.trim();
      final lookup = '$manufacturer $brand $model'.toLowerCase();
      String? matched;
      for (final guide in _guides) {
        final hasMatch = guide.matchers.any(lookup.contains);
        if (hasMatch) {
          matched = guide.brand;
          break;
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _detectedMatcher = matched;
        _detectedLabel = [manufacturer, model]
            .where((part) => part.isNotEmpty)
            .join(' ')
            .trim();
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _detectedLabel = null;
        _detectedMatcher = null;
      });
    }
  }

  List<_OemGuideSection> get _orderedGuides {
    final guides = List<_OemGuideSection>.from(_guides);
    final detected = _detectedMatcher;
    if (detected == null) {
      return guides;
    }
    guides.sort((a, b) {
      final aScore = a.brand == detected ? 0 : 1;
      final bScore = b.brand == detected ? 0 : 1;
      return aScore.compareTo(bScore);
    });
    return guides;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final detected = _detectedMatcher;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Battery & autostart guide'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: const Color(0xFF333333),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Why this matters',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  detected == null
                      ? 'Many Android brands delay emergency notifications unless the app is allowed to auto start and run without battery restrictions. Use the steps below for your phone brand.'
                      : 'Sailor detected ${_detectedLabel ?? 'your Android device'} and moved the most relevant guide to the top. Review that section first, then use the battery settings shortcut below.',
                  style: const TextStyle(
                    height: 1.45,
                    color: Color(0xFFA3A3A3),
                  ),
                ),
                if (Platform.isAndroid) ...[
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () async {
                          await DeviceSettingsService
                              .openBatteryOptimizationSettings();
                        },
                        icon: const Icon(Icons.battery_alert_outlined),
                        label: const Text('Battery settings'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          elevation: 0,
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await DeviceSettingsService.openSystemAppSettings();
                        },
                        icon: const Icon(Icons.settings_outlined),
                        label: const Text('App settings'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white24),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
          for (final guide in _orderedGuides) ...[
            _GuideCard(
              section: guide,
              isRecommended: detected != null && guide.brand == detected,
              detectedLabel: _detectedLabel,
            ),
            const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }
}

class _GuideCard extends StatelessWidget {
  const _GuideCard({
    required this.section,
    required this.isRecommended,
    required this.detectedLabel,
  });

  final _OemGuideSection section;
  final bool isRecommended;
  final String? detectedLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isRecommended
              ? const Color(0xFF4ADE80).withValues(alpha: 0.5)
              : const Color(0xFF222222),
          width: isRecommended ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(section.icon, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isRecommended)
                      Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF14532D).withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          detectedLabel == null
                              ? 'Recommended for this device'
                              : 'Recommended for $detectedLabel',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF4ADE80),
                          ),
                        ),
                      ),
                    Text(
                      section.brand,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < section.steps.length; i++) ...[
            _GuideStep(index: i + 1, text: section.steps[i]),
            if (i != section.steps.length - 1) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _GuideStep extends StatelessWidget {
  const _GuideStep({required this.index, required this.text});

  final int index;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '$index',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              height: 1.45,
              color: Color(0xFFE5E7EB),
            ),
          ),
        ),
      ],
    );
  }
}

class _OemGuideSection {
  const _OemGuideSection({
    required this.brand,
    required this.matchers,
    required this.icon,
    required this.steps,
  });

  final String brand;
  final List<String> matchers;
  final IconData icon;
  final List<String> steps;
}
