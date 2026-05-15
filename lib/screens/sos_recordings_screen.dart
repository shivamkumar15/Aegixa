import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';

import '../services/sos_recording_service.dart';

import '../ui_components.dart';

class SosRecordingsScreen extends StatefulWidget {
  const SosRecordingsScreen({super.key});

  @override
  State<SosRecordingsScreen> createState() => _SosRecordingsScreenState();
}

class _SosRecordingsScreenState extends State<SosRecordingsScreen> {
  final _service = SosRecordingService();
  bool _isLoading = true;
  List<SosRecording> _recordings = const [];
  List<SosVideoRecording> _videos = const [];

  @override
  void initState() {
    super.initState();
    _loadRecordings();
  }

  Future<void> _loadRecordings() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final recordings = await _service.getRecordings();
      final videos = await _service.getVideoRecordings();
      if (!mounted) {
        return;
      }
      setState(() {
        _recordings = recordings;
        _videos = videos;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load recordings: $e')),
      );
    }
  }

  Future<void> _openRecording(SosRecording recording) async {
    final file = File(recording.filePath);
    if (!await file.exists()) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Recording file was not found on this device.')),
      );
      return;
    }

    final result = await OpenFilex.open(recording.filePath);
    if (result.type != ResultType.done) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.message.trim().isNotEmpty
                ? 'Could not open this recording: ${result.message}'
                : 'Could not open this recording.',
          ),
        ),
      );
    }
  }

  Future<void> _copyPath(String path) async {
    await Clipboard.setData(ClipboardData(text: path));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Recording path copied.')),
    );
  }

  Future<void> _deleteRecording(SosRecording recording) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete recording?'),
            content: const Text(
              'This removes the saved database entry. The audio file will also be deleted if it still exists.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) {
      return;
    }

    final file = File(recording.filePath);
    if (await file.exists()) {
      await file.delete();
    }
    await _service.deleteRecording(recording.id!);
    await _loadRecordings();
  }

  Future<void> _openVideo(SosVideoRecording recording) async {
    final file = File(recording.filePath);
    if (!await file.exists()) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Video file was not found on this device.')),
      );
      return;
    }

    final result = await OpenFilex.open(recording.filePath);
    if (result.type != ResultType.done) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.message.trim().isNotEmpty
                ? 'Could not open this video: ${result.message}'
                : 'Could not open this video.',
          ),
        ),
      );
    }
  }

  Future<void> _deleteVideo(SosVideoRecording recording) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete video?'),
            content: const Text(
              'This removes the saved database entry. The video file will also be deleted if it still exists.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) {
      return;
    }

    final file = File(recording.filePath);
    if (await file.exists()) {
      await file.delete();
    }
    await _service.deleteVideoRecording(recording.id!);
    await _loadRecordings();
  }

  String _formatDateTime(DateTime value) {
    final month = _monthName(value.month);
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    final suffix = value.hour >= 12 ? 'PM' : 'AM';
    return '${value.day} $month ${value.year}, $hour:$minute $suffix';
  }

  String _monthName(int month) {
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[month - 1];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('SOS Recordings'),
      ),
      body: RefreshIndicator(
        onRefresh: _loadRecordings,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (_isLoading)
              const Padding(
                padding: const EdgeInsets.only(top: 80),
                child: Center(
                  child: SailorLoader(),
                ),
              )
            else if (_recordings.isEmpty && _videos.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF2A2A2A)
                        : const Color(0xFFE5E7EB),
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.radio_button_checked_outlined,
                      size: 42,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No SOS media yet',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'When SOS is triggered, voice and video recordings will be saved here automatically.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isDark
                            ? const Color(0xFFA3A3A3)
                            : const Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              if (_videos.isNotEmpty) ...[
                Text(
                  'Video recordings',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 10),
                ..._videos.map(
                  (video) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _SosVideoCard(
                      recording: video,
                      formattedCreated: _formatDateTime(video.createdAt),
                      onOpen: () => _openVideo(video),
                      onCopyPath: () => _copyPath(video.filePath),
                      onDelete: () => _deleteVideo(video),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
              ],
              if (_recordings.isNotEmpty) ...[
                Text(
                  'Audio recordings',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 10),
                ..._recordings.map(
                  (recording) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _SosRecordingCard(
                      recording: recording,
                      formattedStart: _formatDateTime(recording.startedAt),
                      formattedStop: recording.stoppedAt == null
                          ? 'Recording in progress'
                          : _formatDateTime(recording.stoppedAt!),
                      onOpen: () => _openRecording(recording),
                      onCopyPath: () => _copyPath(recording.filePath),
                      onDelete: () => _deleteRecording(recording),
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _SosVideoCard extends StatelessWidget {
  const _SosVideoCard({
    required this.recording,
    required this.formattedCreated,
    required this.onOpen,
    required this.onCopyPath,
    required this.onDelete,
  });

  final SosVideoRecording recording;
  final String formattedCreated;
  final VoidCallback onOpen;
  final VoidCallback onCopyPath;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE5E7EB),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.videocam_outlined,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'SOS video recording',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _RecordingInfoRow(label: 'Created', value: formattedCreated),
          _RecordingInfoRow(label: 'Path', value: recording.filePath),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: onOpen,
                icon: const Icon(Icons.play_arrow_outlined),
                label: const Text('Open'),
              ),
              OutlinedButton.icon(
                onPressed: onCopyPath,
                icon: const Icon(Icons.copy_all_outlined),
                label: const Text('Copy Path'),
              ),
              OutlinedButton.icon(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SosRecordingCard extends StatelessWidget {
  const _SosRecordingCard({
    required this.recording,
    required this.formattedStart,
    required this.formattedStop,
    required this.onOpen,
    required this.onCopyPath,
    required this.onDelete,
  });

  final SosRecording recording;
  final String formattedStart;
  final String formattedStop;
  final VoidCallback onOpen;
  final VoidCallback onCopyPath;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE5E7EB),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  recording.isActive ? Icons.mic : Icons.audio_file_outlined,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      recording.isActive
                          ? 'Active SOS recording'
                          : 'SOS recording',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formattedStart,
                      style: TextStyle(
                        color: isDark
                            ? const Color(0xFFA3A3A3)
                            : const Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: recording.isActive
                      ? const Color(0xFFDC2626).withValues(alpha: 0.14)
                      : theme.colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  recording.isActive ? 'Recording' : 'Saved',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: recording.isActive
                        ? const Color(0xFFDC2626)
                        : theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _RecordingInfoRow(label: 'Started', value: formattedStart),
          _RecordingInfoRow(label: 'Stopped', value: formattedStop),
          _RecordingInfoRow(label: 'Path', value: recording.filePath),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: onOpen,
                icon: const Icon(Icons.play_arrow_outlined),
                label: const Text('Open'),
              ),
              OutlinedButton.icon(
                onPressed: onCopyPath,
                icon: const Icon(Icons.copy_all_outlined),
                label: const Text('Copy Path'),
              ),
              OutlinedButton.icon(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecordingInfoRow extends StatelessWidget {
  const _RecordingInfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 58,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color:
                    isDark ? const Color(0xFFA3A3A3) : const Color(0xFF6B7280),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: theme.colorScheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}
