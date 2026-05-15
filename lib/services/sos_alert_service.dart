import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'emergency_contacts_service.dart';
import 'username_service.dart';

class SosAlert {
  const SosAlert({
    required this.id,
    required this.sessionId,
    required this.senderUserId,
    required this.senderName,
    this.senderUsername,
    this.senderPhoneNumber,
    this.senderPhotoPath,
    required this.recipientUserId,
    this.recipientUsername,
    required this.contactName,
    required this.contactPhoneNumber,
    required this.isPrimary,
    required this.alertMessage,
    required this.latitude,
    required this.longitude,
    this.locationAccuracyMeters,
    required this.status,
    this.voiceRecordingUrl,
    this.videoRecordingUrl,
    required this.triggeredAt,
    required this.updatedAt,
    this.resolvedAt,
  });

  final int id;
  final String sessionId;
  final String senderUserId;
  final String senderName;
  final String? senderUsername;
  final String? senderPhoneNumber;
  final String? senderPhotoPath;
  final String recipientUserId;
  final String? recipientUsername;
  final String contactName;
  final String contactPhoneNumber;
  final bool isPrimary;
  final String alertMessage;
  final double latitude;
  final double longitude;
  final double? locationAccuracyMeters;
  final String status;
  final String? voiceRecordingUrl;
  final String? videoRecordingUrl;
  final DateTime triggeredAt;
  final DateTime updatedAt;
  final DateTime? resolvedAt;

  factory SosAlert.fromMap(Map<String, dynamic> map) {
    double? parseDouble(Object? value) {
      if (value is num) return value.toDouble();
      return double.tryParse((value ?? '').toString());
    }

    return SosAlert(
      id: (map['id'] as num).toInt(),
      sessionId: (map['session_id'] ?? '').toString(),
      senderUserId: (map['sender_user_id'] ?? '').toString(),
      senderName: (map['sender_name'] ?? '').toString(),
      senderUsername: map['sender_username'] as String?,
      senderPhoneNumber: map['sender_phone_number'] as String?,
      senderPhotoPath: map['sender_photo_path'] as String?,
      recipientUserId: (map['recipient_user_id'] ?? '').toString(),
      recipientUsername: map['recipient_username'] as String?,
      contactName: (map['contact_name'] ?? '').toString(),
      contactPhoneNumber: (map['contact_phone_number'] ?? '').toString(),
      isPrimary: map['is_primary'] == true,
      alertMessage: (map['alert_message'] ?? '').toString(),
      latitude: parseDouble(map['latitude']) ?? 0,
      longitude: parseDouble(map['longitude']) ?? 0,
      locationAccuracyMeters: parseDouble(map['location_accuracy_meters']),
      status: (map['status'] ?? 'active').toString(),
      voiceRecordingUrl: map['voice_recording_url'] as String?,
      videoRecordingUrl: map['video_recording_url'] as String?,
      triggeredAt: DateTime.parse((map['triggered_at'] ?? '').toString()),
      updatedAt: DateTime.parse((map['updated_at'] ?? '').toString()),
      resolvedAt: map['resolved_at'] == null
          ? null
          : DateTime.parse(map['resolved_at'].toString()),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'session_id': sessionId,
      'sender_user_id': senderUserId,
      'sender_name': senderName,
      'sender_username': senderUsername,
      'sender_phone_number': senderPhoneNumber,
      'sender_photo_path': senderPhotoPath,
      'recipient_user_id': recipientUserId,
      'recipient_username': recipientUsername,
      'contact_name': contactName,
      'contact_phone_number': contactPhoneNumber,
      'is_primary': isPrimary,
      'alert_message': alertMessage,
      'latitude': latitude,
      'longitude': longitude,
      'location_accuracy_meters': locationAccuracyMeters,
      'status': status,
      'voice_recording_url': voiceRecordingUrl,
      'video_recording_url': videoRecordingUrl,
      'triggered_at': triggeredAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'resolved_at': resolvedAt?.toIso8601String(),
    };
  }
}

class SosAlertDispatchSummary {
  const SosAlertDispatchSummary({
    required this.sessionId,
    required this.deliveredCount,
    required this.skippedCount,
    required this.hasPrimaryRecipient,
    required this.pushDeliveredCount,
    required this.pushSkippedCount,
    this.pushErrorMessage,
    this.offlineQueued = false,
  });

  final String sessionId;
  final int deliveredCount;
  final int skippedCount;
  final bool hasPrimaryRecipient;
  final int pushDeliveredCount;
  final int pushSkippedCount;
  final String? pushErrorMessage;
  final bool offlineQueued;
}

class _PushDispatchSummary {
  const _PushDispatchSummary({
    required this.deliveredCount,
    required this.skippedCount,
    this.errorMessage,
  });

  final int deliveredCount;
  final int skippedCount;
  final String? errorMessage;
}

class SosAlertService {
  SosAlertService._();

  static final SosAlertService _instance = SosAlertService._();
  factory SosAlertService() => _instance;

  static const _table = 'sos_alerts';
  static const _recordingsBucket = 'sos-alert-recordings';
  static const _downloadedVoiceRecordingsKey =
      'downloaded_sos_voice_recordings_v1';
  static const _downloadedVideoRecordingsKey =
      'downloaded_sos_video_recordings_v1';
  static const _receivedAlertsCacheKeyPrefix = 'received_sos_alerts_cache_v1_';
  static const Duration _receivedAlertsCacheTtl = Duration(minutes: 5);

  // Offline operation queue keys
  static const _offlineTriggerQueueKey = 'offline_sos_trigger_queue_v1';
  static const _offlineResolveQueueKey = 'offline_sos_resolve_queue_v1';

  final SupabaseClient _supabase = Supabase.instance.client;
  final UsernameService _usernameService = UsernameService();

  /// SOS rate limiting: minimum cooldown between alert sessions.
  static const Duration _sosCooldown = Duration(seconds: 30);
  DateTime? _lastSosTriggeredAt;

  /// Maximum length for user-controlled text fields to prevent abuse.
  static const int _maxAlertMessageLength = 500;
  static const int _maxNameLength = 100;

  /// Generate a cryptographically random session ID to prevent guessing.
  String _generateSessionId(String userId) {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${userId}_$hex';
  }

  /// Sanitize user-controlled text: trim, truncate, remove control characters.
  String _sanitizeText(String input, int maxLength) {
    // Remove control characters (except newline/tab for messages)
    final cleaned = input
        .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '')
        .trim();
    if (cleaned.length > maxLength) {
      return cleaned.substring(0, maxLength);
    }
    return cleaned;
  }

  String get _currentUserId {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('User must be signed in to send SOS alerts.');
    }
    return user.uid;
  }

  Future<SosAlertDispatchSummary> triggerAlerts({
    required List<EmergencyContact> contacts,
    required Position position,
    required String alertMessage,
  }) async {
    // Rate limiting: prevent SOS flooding
    final now = DateTime.now();
    if (_lastSosTriggeredAt != null &&
        now.difference(_lastSosTriggeredAt!) < _sosCooldown) {
      final remaining =
          _sosCooldown.inSeconds - now.difference(_lastSosTriggeredAt!).inSeconds;
      throw StateError(
        'Please wait $remaining seconds before sending another SOS alert.',
      );
    }

    final currentUserId = _currentUserId;
    final senderProfile =
        await _usernameService.getPublicProfileForUserId(currentUserId);
    final senderName = _sanitizeText(
      _resolveSenderName(senderProfile),
      _maxNameLength,
    );
    // Use cryptographically random session ID instead of predictable timestamp
    final sessionId = _generateSessionId(currentUserId);

    // Sanitize alert message
    final sanitizedMessage = _sanitizeText(alertMessage, _maxAlertMessageLength);

    final usernames = contacts
        .map((contact) => (contact.username ?? '').trim())
        .where((username) => username.isNotEmpty)
        .toSet()
        .toList();

    if (usernames.isEmpty) {
      throw StateError(
        'No emergency contacts are linked to Sailor accounts yet. Add contacts with usernames to use in-app SOS alerts.',
      );
    }

    // getPublicProfilesForUsernames uses cache, works offline if warmed.
    final profileByUsername =
        await _usernameService.getPublicProfilesForUsernames(usernames);

    final rows = <Map<String, Object?>>[];
    var deliveredCount = 0;
    var skippedCount = 0;
    var hasPrimaryRecipient = false;

    for (final contact in contacts) {
      final username = (contact.username ?? '').trim();
      final profile = profileByUsername[username];
      final recipientUserId = profile?.uid.trim() ?? '';
      if (username.isEmpty ||
          recipientUserId.isEmpty ||
          recipientUserId == currentUserId) {
        skippedCount++;
        continue;
      }

      rows.add({
        'session_id': sessionId,
        'sender_user_id': currentUserId,
        'sender_name': senderName,
        'sender_username': senderProfile?.username,
        'sender_phone_number': senderProfile?.phoneNumber,
        'sender_photo_path': senderProfile?.profilePhotoPath,
        'recipient_user_id': recipientUserId,
        'recipient_username': username,
        'contact_name': _sanitizeText(contact.name, _maxNameLength),
        'contact_phone_number': _sanitizeText(contact.phoneNumber, 20),
        'is_primary': contact.isPrimary,
        'alert_message': sanitizedMessage,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'location_accuracy_meters': position.accuracy,
      });
      deliveredCount++;
      if (contact.isPrimary) {
        hasPrimaryRecipient = true;
      }
    }

    if (rows.isEmpty) {
      throw StateError(
        'None of your saved emergency contacts can receive in-app SOS alerts yet. Ask them to join Sailor and save their username in your contact list.',
      );
    }

    // Try to deliver to Supabase.  If the network is unavailable, queue the
    // rows locally so the SOS session still starts (recordings, location, UI)
    // and rows get delivered once connectivity returns.
    try {
      final insertedRows = await _supabase
          .from(_table)
          .insert(rows)
          .select('id,session_id,recipient_user_id,sender_name,alert_message');

      final pushSummary = await _dispatchPushAlerts(insertedRows);

      // Mark rate limit timestamp only after successful dispatch
      _lastSosTriggeredAt = DateTime.now();

      return SosAlertDispatchSummary(
        sessionId: sessionId,
        deliveredCount: deliveredCount,
        skippedCount: skippedCount,
        hasPrimaryRecipient: hasPrimaryRecipient,
        pushDeliveredCount: pushSummary.deliveredCount,
        pushSkippedCount: pushSummary.skippedCount,
        pushErrorMessage: pushSummary.errorMessage,
      );
    } on PostgrestException catch (error) {
      // Table/permission errors are real failures — don't queue.
      throw StateError(_friendlySupabaseError(error));
    } catch (networkError) {
      // Network failure — queue rows locally for later delivery.
      debugPrint(
        'SOS trigger offline — queuing ${rows.length} alert rows for retry: $networkError',
      );
      await _enqueueOfflineTrigger(sessionId, rows);
      _lastSosTriggeredAt = DateTime.now();

      return SosAlertDispatchSummary(
        sessionId: sessionId,
        deliveredCount: deliveredCount,
        skippedCount: skippedCount,
        hasPrimaryRecipient: hasPrimaryRecipient,
        pushDeliveredCount: 0,
        pushSkippedCount: deliveredCount,
        pushErrorMessage: 'Alerts queued offline — will deliver when internet returns.',
        offlineQueued: true,
      );
    }
  }

  Future<void> updateLiveLocation({
    required String sessionId,
    required Position position,
  }) async {
    try {
      await _supabase
          .from(_table)
          .update({
            'latitude': position.latitude,
            'longitude': position.longitude,
            'location_accuracy_meters': position.accuracy,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('session_id', sessionId)
          .eq('sender_user_id', _currentUserId)
          .eq('status', 'active');
    } on PostgrestException catch (error) {
      throw StateError(_friendlySupabaseError(error));
    } catch (_) {
      // Network unavailable — silently skip this location update.
      // The next update cycle will retry with a fresher position.
      debugPrint('SOS live location update skipped (offline)');
    }
  }

  Future<void> resolveAlertSession({
    required String sessionId,
    String? voiceRecordingPath,
    String? videoRecordingPath,
  }) async {
    try {
      String? uploadedVoiceUrl;
      String? uploadedVideoUrl;
      if ((voiceRecordingPath ?? '').trim().isNotEmpty) {
        uploadedVoiceUrl = await _uploadMediaRecording(
          sessionId: sessionId,
          localFilePath: voiceRecordingPath!.trim(),
          fileStem: 'voice_recording',
        );
      }
      if ((videoRecordingPath ?? '').trim().isNotEmpty) {
        uploadedVideoUrl = await _uploadMediaRecording(
          sessionId: sessionId,
          localFilePath: videoRecordingPath!.trim(),
          fileStem: 'video_recording',
        );
      }

      if (uploadedVoiceUrl != null || uploadedVideoUrl != null) {
        await _supabase
            .from(_table)
            .update({
              if (uploadedVoiceUrl != null)
                'voice_recording_url': uploadedVoiceUrl,
              if (uploadedVideoUrl != null)
                'video_recording_url': uploadedVideoUrl,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('session_id', sessionId)
            .eq('sender_user_id', _currentUserId);
      }

      await _supabase
          .from(_table)
          .update({
            'status': 'resolved',
            'resolved_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('session_id', sessionId)
          .eq('sender_user_id', _currentUserId);
    } on PostgrestException catch (error) {
      throw StateError(_friendlySupabaseError(error));
    } on StorageException catch (error) {
      // Storage upload failed (possibly offline) — queue resolve for retry.
      debugPrint('SOS resolve storage upload failed (offline): $error');
      await _enqueueOfflineResolve(
        sessionId: sessionId,
        voiceRecordingPath: voiceRecordingPath,
        videoRecordingPath: videoRecordingPath,
      );
    } catch (networkError) {
      // Network unavailable — queue resolve for retry when online.
      debugPrint('SOS resolve offline — queued for retry: $networkError');
      await _enqueueOfflineResolve(
        sessionId: sessionId,
        voiceRecordingPath: voiceRecordingPath,
        videoRecordingPath: videoRecordingPath,
      );
    }
  }

  Stream<List<SosAlert>> watchReceivedAlerts() async* {
    final userId = _currentUserId;
    final cachedAlerts = await _loadReceivedAlertsCache(userId);
    if (cachedAlerts.isNotEmpty) {
      yield cachedAlerts;
    }

    try {
      yield* _supabase
          .from(_table)
          .stream(primaryKey: ['id'])
          .eq('recipient_user_id', userId)
          .map(
            (rows) => rows
                .whereType<Map<String, dynamic>>()
                .map(SosAlert.fromMap)
                .toList()
              ..sort((a, b) => b.triggeredAt.compareTo(a.triggeredAt)),
          )
          .asyncMap((alerts) async {
            await _saveReceivedAlertsCache(userId, alerts);
            return alerts;
          });
    } catch (e) {
      // Offline or stream connection failed — the cached snapshot was already
      // yielded above, so the UI still shows the last known data.
      debugPrint('SOS inbox stream failed (offline): $e');
    }
  }

  Future<String?> getDownloadedVoiceRecordingPath(int alertId) async {
    final savedPaths = await _loadDownloadedMediaPaths(
      _downloadedVoiceRecordingsKey,
    );
    final filePath = savedPaths['$alertId'];
    if ((filePath ?? '').trim().isEmpty) {
      return null;
    }

    final file = File(filePath!.trim());
    if (await file.exists()) {
      return file.path;
    }

    savedPaths.remove('$alertId');
    await _saveDownloadedMediaPaths(_downloadedVoiceRecordingsKey, savedPaths);
    return null;
  }

  Future<String?> getDownloadedVideoRecordingPath(int alertId) async {
    final savedPaths = await _loadDownloadedMediaPaths(
      _downloadedVideoRecordingsKey,
    );
    final filePath = savedPaths['$alertId'];
    if ((filePath ?? '').trim().isEmpty) {
      return null;
    }

    final file = File(filePath!.trim());
    if (await file.exists()) {
      return file.path;
    }

    savedPaths.remove('$alertId');
    await _saveDownloadedMediaPaths(_downloadedVideoRecordingsKey, savedPaths);
    return null;
  }

  Future<String> saveVoiceRecordingToDevice(SosAlert alert) async {
    return _saveMediaToDevice(
      alert: alert,
      remoteUrl: alert.voiceRecordingUrl,
      prefsKey: _downloadedVoiceRecordingsKey,
      folderName: 'received_sos_recordings',
      filePrefix: 'panic_voice',
      fileMissingMessage:
          'Voice recording is no longer available online and has not been saved on this device yet.',
      downloadFailureMessage:
          'Could not download the voice recording right now.',
      getExistingPath: getDownloadedVoiceRecordingPath,
      remoteColumn: 'voice_recording_url',
    );
  }

  Future<String> saveVideoRecordingToDevice(SosAlert alert) async {
    return _saveMediaToDevice(
      alert: alert,
      remoteUrl: alert.videoRecordingUrl,
      prefsKey: _downloadedVideoRecordingsKey,
      folderName: 'received_sos_videos',
      filePrefix: 'panic_video',
      fileMissingMessage:
          'Video recording is no longer available online and has not been saved on this device yet.',
      downloadFailureMessage:
          'Could not download the video recording right now.',
      getExistingPath: getDownloadedVideoRecordingPath,
      remoteColumn: 'video_recording_url',
    );
  }

  Future<_PushDispatchSummary> _dispatchPushAlerts(dynamic insertedRows) async {
    final alerts = (insertedRows as List)
        .whereType<Map<String, dynamic>>()
        .map(
          (row) => {
            'alertId': row['id'],
            'sessionId': row['session_id'],
            'recipientUserId': row['recipient_user_id'],
          },
        )
        .toList();
    if (alerts.isEmpty) {
      return const _PushDispatchSummary(deliveredCount: 0, skippedCount: 0);
    }

    try {
      final response = await _supabase.functions.invoke(
        'send-sos-push',
        body: {'alerts': alerts},
      );
      final data = response.data;
      if (data is Map<String, dynamic>) {
        final errorMessage = (data['error'] ?? '').toString().trim();
        return _PushDispatchSummary(
          deliveredCount:
              int.tryParse((data['sentCount'] ?? '0').toString()) ?? 0,
          skippedCount:
              int.tryParse((data['skippedCount'] ?? '0').toString()) ?? 0,
          errorMessage: errorMessage.isEmpty ? null : errorMessage,
        );
      }
      return const _PushDispatchSummary(deliveredCount: 0, skippedCount: 0);
    } catch (error) {
      debugPrint('SOS push dispatch failed: $error');
      return _PushDispatchSummary(
        deliveredCount: 0,
        skippedCount: alerts.length,
        errorMessage:
            'Push notifications are not configured yet. Deploy the send-sos-push function and set the Firebase service account secret in Supabase.',
      );
    }
  }

  String _resolveSenderName(SailorPublicProfile? profile) {
    final user = FirebaseAuth.instance.currentUser;
    final profileName = (profile?.displayName ?? '').trim();
    if (profileName.isNotEmpty) {
      return profileName;
    }
    final displayName = (user?.displayName ?? '').trim();
    if (displayName.isNotEmpty) {
      return displayName;
    }
    final email = (user?.email ?? '').trim();
    if (email.isNotEmpty) {
      return email.split('@').first;
    }
    return 'Sailor User';
  }

  Future<String?> _uploadMediaRecording({
    required String sessionId,
    required String localFilePath,
    required String fileStem,
  }) async {
    final file = File(localFilePath);
    if (!file.existsSync()) {
      return null;
    }

    final extension = path.extension(localFilePath).replaceFirst('.', '');
    final objectPath = extension.isEmpty
        ? '$_currentUserId/$sessionId/$fileStem'
        : '$_currentUserId/$sessionId/$fileStem.$extension';

    await _supabase.storage.from(_recordingsBucket).uploadBinary(
          objectPath,
          await file.readAsBytes(),
          fileOptions: const FileOptions(upsert: true),
        );

    return objectPath;
  }

  Future<String> _saveMediaToDevice({
    required SosAlert alert,
    required String? remoteUrl,
    required String prefsKey,
    required String folderName,
    required String filePrefix,
    required String fileMissingMessage,
    required String downloadFailureMessage,
    required Future<String?> Function(int alertId) getExistingPath,
    required String remoteColumn,
  }) async {
    final existingPath = await getExistingPath(alert.id);
    if (existingPath != null) {
      return existingPath;
    }

    final remoteReference = (remoteUrl ?? '').trim();
    if (remoteReference.isEmpty) {
      throw StateError(fileMissingMessage);
    }

    final objectPath = _trustedStorageObjectPath(alert, remoteReference);
    if (objectPath == null) {
      throw StateError('Invalid or untrusted media reference');
    }

    late final List<int> mediaBytes;
    try {
      mediaBytes = await _supabase.storage
          .from(_recordingsBucket)
          .download(objectPath);
    } catch (_) {
      throw StateError(downloadFailureMessage);
    }

    final mediaDirectory = Directory(
      path.join((await getApplicationDocumentsDirectory()).path, folderName),
    );
    await mediaDirectory.create(recursive: true);

    final extension = _resolveDownloadedRecordingExtension(objectPath);
    final filePath = path.join(
      mediaDirectory.path,
      '${filePrefix}_${alert.sessionId}_${alert.id}$extension',
    );
    final file = File(filePath);
    await file.writeAsBytes(mediaBytes, flush: true);

    final savedPaths = await _loadDownloadedMediaPaths(prefsKey);
    savedPaths['${alert.id}'] = file.path;
    await _saveDownloadedMediaPaths(prefsKey, savedPaths);
    await _cleanupRemoteMedia(alert, remoteReference, remoteColumn);
    return file.path;
  }

  Future<void> _cleanupRemoteMedia(
    SosAlert alert,
    String remoteUrl,
    String remoteColumn,
  ) async {
    final objectPath = _extractStorageObjectPath(remoteUrl);

    try {
      await _supabase
          .from(_table)
          .update({
            remoteColumn: null,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', alert.id)
          .eq('recipient_user_id', _currentUserId);
    } catch (error) {
      debugPrint('Could not clear SOS media URL after download: $error');
      return;
    }

    if ((objectPath ?? '').isEmpty) {
      return;
    }

    try {
      final remainingRows = await _supabase
          .from(_table)
          .select('id')
          .eq(remoteColumn, remoteUrl)
          .limit(1);
      if (remainingRows.isNotEmpty) {
        return;
      }

      await _supabase.storage.from(_recordingsBucket).remove([objectPath!]);
    } catch (error) {
      debugPrint('Could not delete remote SOS media: $error');
    }
  }

  String _resolveDownloadedRecordingExtension(String remoteUrl) {
    final uri = Uri.tryParse(remoteUrl);
    final extension = path.extension(uri?.path ?? '').trim();
    if (extension.isNotEmpty && extension.length <= 8) {
      return extension;
    }
    return '.m4a';
  }

  String? _trustedStorageObjectPath(SosAlert alert, String remoteReference) {
    final objectPath = _extractStorageObjectPath(remoteReference);
    if ((objectPath ?? '').isEmpty) {
      return null;
    }

    final expectedPrefix = '${alert.senderUserId}/${alert.sessionId}/';
    if (!objectPath!.startsWith(expectedPrefix)) {
      return null;
    }

    final segments = objectPath.split('/');
    if (segments.any((segment) => segment.isEmpty || segment == '..')) {
      return null;
    }

    return objectPath;
  }

  String? _extractStorageObjectPath(String remoteReference) {
    if (remoteReference.isEmpty) {
      return null;
    }

    final uri = Uri.tryParse(remoteReference);
    if (uri == null) {
      return null;
    }

    if (!uri.hasScheme) {
      final normalized = path.posix.normalize(remoteReference);
      if (normalized.startsWith('../') || normalized.startsWith('/')) {
        return null;
      }
      return normalized;
    }

    if (uri.scheme != 'https' || !uri.host.endsWith('.supabase.co')) {
      return null;
    }

    final segments = uri.pathSegments;
    final bucketIndex = segments.indexOf(_recordingsBucket);
    if (bucketIndex == -1 || bucketIndex + 1 >= segments.length) {
      return null;
    }
    return segments.sublist(bucketIndex + 1).join('/');
  }

  Future<Map<String, String>> _loadDownloadedMediaPaths(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if ((raw ?? '').trim().isEmpty) {
      return <String, String>{};
    }

    try {
      final decoded = jsonDecode(raw!) as Map<String, dynamic>;
      return decoded.map(
        (key, value) => MapEntry(key, (value ?? '').toString()),
      );
    } catch (_) {
      return <String, String>{};
    }
  }

  Future<void> _saveDownloadedMediaPaths(
    String key,
    Map<String, String> paths,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(paths));
  }

  Future<List<SosAlert>> _loadReceivedAlertsCache(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_receivedAlertsCacheKeyPrefix$userId');
    if ((raw ?? '').trim().isEmpty) {
      return const <SosAlert>[];
    }

    try {
      final decoded = jsonDecode(raw!) as Map<String, dynamic>;
      final expiresAt = DateTime.tryParse(
        (decoded['expires_at'] ?? '').toString(),
      );
      if (expiresAt == null || DateTime.now().isAfter(expiresAt)) {
        return const <SosAlert>[];
      }
      final items = decoded['alerts'];
      if (items is! List) {
        return const <SosAlert>[];
      }
      return items
          .whereType<Map<String, dynamic>>()
          .map(SosAlert.fromMap)
          .toList()
        ..sort((a, b) => b.triggeredAt.compareTo(a.triggeredAt));
    } catch (_) {
      return const <SosAlert>[];
    }
  }

  Future<void> _saveReceivedAlertsCache(
    String userId,
    List<SosAlert> alerts,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_receivedAlertsCacheKeyPrefix$userId',
      jsonEncode({
        'expires_at': DateTime.now()
            .add(_receivedAlertsCacheTtl)
            .toIso8601String(),
        'alerts': alerts.map((alert) => alert.toMap()).toList(),
      }),
    );
  }

  String _friendlySupabaseError(PostgrestException error) {
    // Log the raw error for debugging but never expose it to the user.
    debugPrint('Supabase SOS error: ${error.code}');
    final lower = error.message.trim().toLowerCase();
    if (lower.contains('could not find the table') &&
        lower.contains('sos_alerts')) {
      return 'SOS service is not configured. Please contact support.';
    }
    if (lower.contains('video_recording_url') ||
        lower.contains('voice_recording_url')) {
      return 'SOS media storage is not configured. Please contact support.';
    }
    if (lower.contains('row-level security') ||
        lower.contains('permission denied') ||
        lower.contains('violates row-level security')) {
      return 'You do not have permission to perform this action.';
    }
    // Never forward raw database error messages to the user —
    // they may leak table names, column names, or query internals.
    return 'SOS request failed. Please try again.';
  }

  // ---------------------------------------------------------------------------
  // Offline queue: trigger
  // ---------------------------------------------------------------------------

  Future<void> _enqueueOfflineTrigger(
    String sessionId,
    List<Map<String, Object?>> rows,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_offlineTriggerQueueKey);
    final List<dynamic> queue =
        (raw != null ? jsonDecode(raw) as List<dynamic> : <dynamic>[]);
    queue.add({
      'session_id': sessionId,
      'rows': rows,
      'queued_at': DateTime.now().toIso8601String(),
    });
    await prefs.setString(_offlineTriggerQueueKey, jsonEncode(queue));
  }

  // ---------------------------------------------------------------------------
  // Offline queue: resolve
  // ---------------------------------------------------------------------------

  Future<void> _enqueueOfflineResolve({
    required String sessionId,
    String? voiceRecordingPath,
    String? videoRecordingPath,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_offlineResolveQueueKey);
    final List<dynamic> queue =
        (raw != null ? jsonDecode(raw) as List<dynamic> : <dynamic>[]);
    queue.add({
      'session_id': sessionId,
      'voice_recording_path': voiceRecordingPath,
      'video_recording_path': videoRecordingPath,
      'queued_at': DateTime.now().toIso8601String(),
    });
    await prefs.setString(_offlineResolveQueueKey, jsonEncode(queue));
  }

  // ---------------------------------------------------------------------------
  // Public offline retry API
  // ---------------------------------------------------------------------------

  /// Returns `true` if there are queued trigger or resolve operations waiting
  /// for connectivity.
  Future<bool> hasOfflineOperations() async {
    final prefs = await SharedPreferences.getInstance();
    final triggerRaw = prefs.getString(_offlineTriggerQueueKey);
    final resolveRaw = prefs.getString(_offlineResolveQueueKey);
    final hasTriggers = triggerRaw != null &&
        triggerRaw.isNotEmpty &&
        (jsonDecode(triggerRaw) as List).isNotEmpty;
    final hasResolves = resolveRaw != null &&
        resolveRaw.isNotEmpty &&
        (jsonDecode(resolveRaw) as List).isNotEmpty;
    return hasTriggers || hasResolves;
  }

  /// Attempts to deliver all queued offline trigger and resolve operations.
  /// Silently removes successfully delivered items.  Items that still fail
  /// (e.g. still offline) remain in the queue for the next retry cycle.
  Future<void> retryOfflineOperations() async {
    await _retryOfflineTriggers();
    await _retryOfflineResolves();
  }

  Future<void> _retryOfflineTriggers() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_offlineTriggerQueueKey);
    if (raw == null || raw.isEmpty) return;

    final List<dynamic> queue;
    try {
      queue = jsonDecode(raw) as List<dynamic>;
    } catch (_) {
      await prefs.remove(_offlineTriggerQueueKey);
      return;
    }
    if (queue.isEmpty) return;

    final remaining = <dynamic>[];
    for (final entry in queue) {
      if (entry is! Map<String, dynamic>) continue;
      final rows = entry['rows'];
      if (rows is! List || rows.isEmpty) continue;

      try {
        final typedRows = rows
            .whereType<Map<String, dynamic>>()
            .map((r) => Map<String, Object?>.from(r))
            .toList();
        final insertedRows = await _supabase
            .from(_table)
            .insert(typedRows)
            .select('id,session_id,recipient_user_id,sender_name,alert_message');
        // Best-effort push after delayed insert
        await _dispatchPushAlerts(insertedRows);
        debugPrint(
          'Offline SOS trigger delivered: session ${entry['session_id']}',
        );
      } on PostgrestException catch (e) {
        // Real DB error (table missing, RLS) — drop this entry to avoid
        // infinite retries of a permanently failing operation.
        debugPrint('Offline SOS trigger permanently failed: ${e.message}');
      } catch (_) {
        // Still offline — keep for next retry
        remaining.add(entry);
      }
    }

    if (remaining.isEmpty) {
      await prefs.remove(_offlineTriggerQueueKey);
    } else {
      await prefs.setString(_offlineTriggerQueueKey, jsonEncode(remaining));
    }
  }

  Future<void> _retryOfflineResolves() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_offlineResolveQueueKey);
    if (raw == null || raw.isEmpty) return;

    final List<dynamic> queue;
    try {
      queue = jsonDecode(raw) as List<dynamic>;
    } catch (_) {
      await prefs.remove(_offlineResolveQueueKey);
      return;
    }
    if (queue.isEmpty) return;

    final remaining = <dynamic>[];
    for (final entry in queue) {
      if (entry is! Map<String, dynamic>) continue;
      final sessionId = (entry['session_id'] ?? '').toString();
      if (sessionId.isEmpty) continue;

      final voicePath = entry['voice_recording_path'] as String?;
      final videoPath = entry['video_recording_path'] as String?;

      try {
        String? uploadedVoiceUrl;
        String? uploadedVideoUrl;
        if ((voicePath ?? '').trim().isNotEmpty) {
          uploadedVoiceUrl = await _uploadMediaRecording(
            sessionId: sessionId,
            localFilePath: voicePath!.trim(),
            fileStem: 'voice_recording',
          );
        }
        if ((videoPath ?? '').trim().isNotEmpty) {
          uploadedVideoUrl = await _uploadMediaRecording(
            sessionId: sessionId,
            localFilePath: videoPath!.trim(),
            fileStem: 'video_recording',
          );
        }

        if (uploadedVoiceUrl != null || uploadedVideoUrl != null) {
          await _supabase
              .from(_table)
              .update({
                if (uploadedVoiceUrl != null)
                  'voice_recording_url': uploadedVoiceUrl,
                if (uploadedVideoUrl != null)
                  'video_recording_url': uploadedVideoUrl,
                'updated_at': DateTime.now().toIso8601String(),
              })
              .eq('session_id', sessionId)
              .eq('sender_user_id', _currentUserId);
        }

        await _supabase
            .from(_table)
            .update({
              'status': 'resolved',
              'resolved_at': DateTime.now().toIso8601String(),
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('session_id', sessionId)
            .eq('sender_user_id', _currentUserId);

        debugPrint('Offline SOS resolve delivered: session $sessionId');
      } on PostgrestException catch (e) {
        debugPrint('Offline SOS resolve permanently failed: ${e.message}');
      } catch (_) {
        // Still offline — keep for next retry
        remaining.add(entry);
      }
    }

    if (remaining.isEmpty) {
      await prefs.remove(_offlineResolveQueueKey);
    } else {
      await prefs.setString(_offlineResolveQueueKey, jsonEncode(remaining));
    }
  }
}
