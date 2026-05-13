import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/sos_alert_service.dart';

import '../ui_components.dart';

class SosAlertsScreen extends StatelessWidget {
  const SosAlertsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final service = SosAlertService();

    return Scaffold(
      appBar: AppBar(title: const Text('SOS inbox')),
      body: StreamBuilder<List<SosAlert>>(
        stream: service.watchReceivedAlerts(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not load SOS alerts right now.',
                  style: TextStyle(color: theme.colorScheme.onSurface),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          if (!snapshot.hasData) {
            return const Center(
              child: AegixaLoader(),
            );
          }

          final alerts = snapshot.data!;
          if (alerts.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No incoming SOS alerts yet.',
                  style: TextStyle(color: theme.colorScheme.onSurface),
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: alerts.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) => _AlertCard(alert: alerts[index]),
          );
        },
      ),
    );
  }
}

class _AlertCard extends StatefulWidget {
  const _AlertCard({required this.alert});

  final SosAlert alert;

  @override
  State<_AlertCard> createState() => _AlertCardState();
}

class _AlertCardState extends State<_AlertCard> {
  final SosAlertService _service = SosAlertService();
  bool _isSavingRecording = false;
  bool _isSavingVideo = false;
  bool _hasLocalVoiceRecording = false;
  bool _hasLocalVideoRecording = false;

  SosAlert get alert => widget.alert;

  @override
  void initState() {
    super.initState();
    _loadLocalMediaState();
  }

  @override
  void didUpdateWidget(covariant _AlertCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.alert.id != widget.alert.id ||
        oldWidget.alert.voiceRecordingUrl != widget.alert.voiceRecordingUrl ||
        oldWidget.alert.videoRecordingUrl != widget.alert.videoRecordingUrl) {
      _loadLocalMediaState();
    }
  }

  Future<void> _loadLocalMediaState() async {
    final voicePath = await _service.getDownloadedVoiceRecordingPath(alert.id);
    final videoPath = await _service.getDownloadedVideoRecordingPath(alert.id);
    if (!mounted) {
      return;
    }
    setState(() {
      _hasLocalVoiceRecording = (voicePath ?? '').trim().isNotEmpty;
      _hasLocalVideoRecording = (videoPath ?? '').trim().isNotEmpty;
    });
  }

  Future<void> _openLocation(BuildContext context) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${alert.latitude},${alert.longitude}',
    );
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the live location.')),
      );
    }
  }

  Future<void> _openRecording(BuildContext context) async {
    if (_isSavingRecording) {
      return;
    }

    setState(() {
      _isSavingRecording = true;
    });

    try {
      final filePath = await _service.saveVoiceRecordingToDevice(alert);
      final file = File(filePath);
      if (!await file.exists()) {
        throw StateError('The saved voice recording could not be found.');
      }

      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Voice recording saved to this phone. The online copy was removed to save storage.',
          ),
        ),
      );

      final result = await OpenFilex.open(filePath);
      if (result.type != ResultType.done && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.message.trim().isNotEmpty
                  ? 'Saved the recording, but could not open it: ${result.message}'
                  : 'Saved the recording, but could not open it.',
            ),
          ),
        );
      }
      if (mounted) {
        setState(() {
          _hasLocalVoiceRecording = true;
        });
      }
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(error.toString().replaceFirst('Bad state: ', ''))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSavingRecording = false;
        });
      }
    }
  }

  Future<void> _openVideo(BuildContext context) async {
    if (_isSavingVideo) {
      return;
    }

    setState(() {
      _isSavingVideo = true;
    });

    try {
      final filePath = await _service.saveVideoRecordingToDevice(alert);
      final file = File(filePath);
      if (!await file.exists()) {
        throw StateError('The saved video recording could not be found.');
      }

      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Video recording saved to this phone. The online copy was removed to save storage.',
          ),
        ),
      );

      final result = await OpenFilex.open(filePath);
      if (result.type != ResultType.done && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.message.trim().isNotEmpty
                  ? 'Saved the video, but could not open it: ${result.message}'
                  : 'Saved the video, but could not open it.',
            ),
          ),
        );
      }
      if (mounted) {
        setState(() {
          _hasLocalVideoRecording = true;
        });
      }
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Bad state: ', '')),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSavingVideo = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isActive = alert.status == 'active';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFE11D48).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'PANIC ALERT',
                  style: TextStyle(
                    color: Color(0xFFE11D48),
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  alert.senderName,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isActive
                      ? const Color(0xFFE11D48).withValues(alpha: 0.12)
                      : const Color(0xFF10B981).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  isActive ? 'LIVE' : 'Resolved',
                  style: TextStyle(
                    color: isActive
                        ? const Color(0xFFE11D48)
                        : const Color(0xFF047857),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            alert.alertMessage,
            style: TextStyle(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.78),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Updated ${_formatTimestamp(alert.updatedAt)}',
            style: TextStyle(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.58),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: () => _openLocation(context),
                icon: const Icon(Icons.location_on_outlined),
                label: const Text('Live location'),
              ),
              if (_hasLocalVoiceRecording ||
                  (alert.voiceRecordingUrl ?? '').trim().isNotEmpty)
                OutlinedButton.icon(
                  onPressed:
                      _isSavingRecording ? null : () => _openRecording(context),
                  icon: _isSavingRecording
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download_for_offline_outlined),
                  label: Text(
                    _isSavingRecording ? 'Saving...' : 'Save voice recording',
                  ),
                ),
              if (_hasLocalVideoRecording ||
                  (alert.videoRecordingUrl ?? '').trim().isNotEmpty)
                OutlinedButton.icon(
                  onPressed: _isSavingVideo ? null : () => _openVideo(context),
                  icon: _isSavingVideo
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.videocam_outlined),
                  label: Text(_isSavingVideo ? 'Saving...' : 'Save video'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _formatTimestamp(DateTime value) {
    final local = value.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour >= 12 ? 'PM' : 'AM';
    return '${local.day}/${local.month}/${local.year} $hour:$minute $period';
  }
}
