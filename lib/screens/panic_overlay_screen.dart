import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

class PanicOverlayApp extends StatelessWidget {
  const PanicOverlayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: PanicOverlayScreen(),
    );
  }
}

class PanicOverlayScreen extends StatefulWidget {
  const PanicOverlayScreen({super.key});

  @override
  State<PanicOverlayScreen> createState() => _PanicOverlayScreenState();
}

class _PanicOverlayScreenState extends State<PanicOverlayScreen> {
  String _senderName = 'Emergency contact';
  String _alertMessage = 'PANIC ALERT received. Open Sailor immediately.';

  @override
  void initState() {
    super.initState();
    FlutterOverlayWindow.overlayListener.listen((payload) {
      if (payload == null) {
        return;
      }
      try {
        final data = jsonDecode(payload.toString()) as Map<String, dynamic>;
        if (!mounted) {
          return;
        }
        setState(() {
          _senderName = (data['senderName'] ?? _senderName).toString();
          _alertMessage = (data['alertMessage'] ?? _alertMessage).toString();
        });
      } catch (_) {
        // Keep the default panic message if the overlay payload cannot be parsed.
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: SafeArea(
        child: Center(
          child: Container(
            margin: const EdgeInsets.all(20),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF111827),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: const Color(0xFFE11D48), width: 2),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x80111827),
                  blurRadius: 24,
                  offset: Offset(0, 16),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE11D48).withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'PANIC ALERT',
                    style: TextStyle(
                      color: Color(0xFFFDA4AF),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  _senderName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _alertMessage,
                  style: const TextStyle(
                    color: Color(0xFFE5E7EB),
                    fontSize: 16,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Open Sailor now and check the SOS inbox for live location details.',
                  style: TextStyle(
                    color: Color(0xFFFCA5A5),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: FlutterOverlayWindow.closeOverlay,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFE11D48),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text(
                      'Dismiss Overlay',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
