import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

class AegixaUserSuggestion {
  const AegixaUserSuggestion({
    required this.uid,
    required this.username,
    this.displayName,
    this.phoneNumber,
    this.profilePhotoPath,
  });

  final String uid;
  final String username;
  final String? displayName;
  final String? phoneNumber;
  final String? profilePhotoPath;
}

class AegixaPublicProfile {
  const AegixaPublicProfile({
    required this.uid,
    this.username,
    this.displayName,
    this.phoneNumber,
    this.profilePhotoPath,
    this.dateOfBirth,
  });

  final String uid;
  final String? username;
  final String? displayName;
  final String? phoneNumber;
  final String? profilePhotoPath;
  final String? dateOfBirth;
}

class UsernameService {
  UsernameService._();
  static final UsernameService _instance = UsernameService._();
  factory UsernameService() => _instance;

  final SupabaseClient _supabase = Supabase.instance.client;
  static const _table = 'usernames';

  String normalizeForInput(String value) {
    final lowered = value.toLowerCase().trim();
    final cleaned = lowered.replaceAll(RegExp(r'[^a-z0-9._]'), '');
    final singleDots = cleaned.replaceAll(RegExp(r'\.{2,}'), '.');
    final singleUnderscore = singleDots.replaceAll(RegExp(r'_{2,}'), '_');
    final trimmed = singleUnderscore.replaceAll(RegExp(r'^[._]+|[._]+$'), '');
    return trimmed.length > 24 ? trimmed.substring(0, 24) : trimmed;
  }

  Future<String?> getUsernameForUserId(String userId) async {
    final data = await _supabase
        .from(_table)
        .select('username')
        .eq('uid', userId)
        .maybeSingle();
    if (data == null) {
      return null;
    }
    final username = data['username'];
    if (username is String && username.trim().isNotEmpty) {
      return username.trim();
    }
    return null;
  }

  Stream<String?> usernameStreamForUserId(String userId) {
    return _supabase
        .from(_table)
        .stream(primaryKey: ['uid'])
        .eq('uid', userId)
        .map((rows) {
          final data = rows.isEmpty ? null : rows.first;
          final username = data?['username'];
          if (username is String && username.trim().isNotEmpty) {
            return username.trim();
          }
          return null;
        });
  }

  bool isValidUsernameFormat(String username) {
    return RegExp(r'^[a-z0-9._]{3,24}$').hasMatch(username);
  }

  Future<bool> isUsernameAvailable(
    String rawUsername, {
    String? currentUserId,
  }) async {
    final username = normalizeForInput(rawUsername);
    if (!isValidUsernameFormat(username)) {
      return false;
    }

    final usernameRow = await _supabase
        .from(_table)
        .select('uid')
        .eq('username', username)
        .maybeSingle();
    if (usernameRow == null) {
      return true;
    }

    final ownerId = usernameRow['uid'];
    return ownerId == currentUserId;
  }

  Future<String> claimUsername({
    required User user,
    required String rawUsername,
  }) async {
    final username = normalizeForInput(rawUsername);
    if (!isValidUsernameFormat(username)) {
      throw FirebaseAuthException(
        code: 'invalid-username',
        message:
            'Use 3-24 chars with lowercase letters, numbers, dot or underscore.',
      );
    }

    final existingForUser = await _supabase
        .from(_table)
        .select('username')
        .eq('uid', user.uid)
        .maybeSingle();
    final existingUsername = existingForUser?['username'];
    if (existingUsername is String && existingUsername.trim().isNotEmpty) {
      if (existingUsername == username) {
        return username;
      }
      throw FirebaseAuthException(
        code: 'username-already-set',
        message: 'Username is already set for this account.',
      );
    }

    try {
      await _supabase.from(_table).insert({
        'uid': user.uid,
        'username': username,
      });
    } on PostgrestException catch (e) {
      if (_isUniqueViolation(e)) {
        throw FirebaseAuthException(
          code: 'username-taken',
          message: 'That username is not available.',
        );
      }
      throw FirebaseAuthException(
        code: 'username-service-unavailable',
        message:
            'Could not save username right now. Check Supabase table/policies.',
      );
    }

    return username;
  }

  Future<List<String>> generateSuggestions(
    String preferredName, {
    required String currentUserId,
    int max = 5,
  }) async {
    final base = _normalizeBase(preferredName);
    final suggestions = <String>[];
    final seen = <String>{};

    for (var attempt = 0; suggestions.length < max && attempt < 80; attempt++) {
      final candidate = attempt == 0 ? base : '$base${attempt + 1}';
      if (!seen.add(candidate)) {
        continue;
      }
      if (!isValidUsernameFormat(candidate)) {
        continue;
      }
      final available = await isUsernameAvailable(
        candidate,
        currentUserId: currentUserId,
      );
      if (available) {
        suggestions.add(candidate);
      }
    }

    return suggestions;
  }

  Future<String> ensureUniqueUsername({
    required User user,
    required String preferredName,
  }) async {
    final existing = await getUsernameForUserId(user.uid);
    if (existing != null) {
      return existing;
    }

    final base = _normalizeBase(preferredName);
    for (var attempt = 0; attempt < 2000; attempt++) {
      final candidate = attempt == 0 ? base : '$base$attempt';
      final reserved =
          await _tryReserveUsername(user: user, username: candidate);
      if (reserved) {
        return candidate;
      }
    }

    throw FirebaseAuthException(
      code: 'username-unavailable',
      message: 'Could not generate a unique username right now.',
    );
  }

  Future<List<AegixaUserSuggestion>> searchUsers(
    String rawQuery, {
    int limit = 8,
  }) async {
    final query = normalizeForInput(rawQuery);
    if (query.length < 2) {
      return const <AegixaUserSuggestion>[];
    }

    // Escape ILIKE wildcards so user input cannot widen the search pattern.
    final safeQuery = query
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');

    final rows = await _supabase
        .from(_table)
        .select('uid,username')
        .ilike('username', '$safeQuery%')
        .limit(limit);

    final suggestions = rows
        .whereType<Map<String, dynamic>>()
        .map(
          (row) => AegixaUserSuggestion(
            uid: (row['uid'] ?? '').toString(),
            username: (row['username'] ?? '').toString(),
          ),
        )
        .where((item) => item.uid.isNotEmpty && item.username.isNotEmpty)
        .toList();

    if (suggestions.isEmpty) {
      return suggestions;
    }

    try {
      final profileRows = await _supabase
          .from('public_profiles')
          .select('uid,display_name,phone_number,photo_path')
          .inFilter('uid', suggestions.map((item) => item.uid).toList());

      final profileMap = <String, Map<String, dynamic>>{};
      for (final row in profileRows) {
        final uid = (row['uid'] ?? '').toString();
        if (uid.isNotEmpty) {
          profileMap[uid] = row;
        }
      }

      return suggestions.map((item) {
        final profile = profileMap[item.uid];
        return AegixaUserSuggestion(
          uid: item.uid,
          username: item.username,
          displayName:
              profile == null ? null : profile['display_name'] as String?,
          phoneNumber:
              profile == null ? null : profile['phone_number'] as String?,
          profilePhotoPath:
              profile == null ? null : profile['photo_path'] as String?,
        );
      }).toList();
    } catch (_) {
      return suggestions;
    }
  }

  Future<void> upsertPublicProfile({
    required User user,
    required String username,
    String? displayName,
    String? phoneNumber,
    String? photoPath,
    String? dateOfBirth,
  }) async {
    // When the caller passes empty values for photo, phone, or DOB, preserve
    // whatever is already stored in Supabase so partial updates (e.g. only
    // changing the photo) don't accidentally wipe unrelated fields.
    var effectivePhotoPath = (photoPath ?? '').trim();
    var effectivePhone = (phoneNumber ?? '').trim();
    var effectiveDob = (dateOfBirth ?? '').trim();

    if (effectivePhotoPath.isEmpty ||
        effectivePhone.isEmpty ||
        effectiveDob.isEmpty) {
      try {
        final existing = await getPublicProfileForUserId(user.uid);
        if (existing != null) {
          if (effectivePhotoPath.isEmpty) {
            effectivePhotoPath =
                (existing.profilePhotoPath ?? '').trim();
          }
          if (effectivePhone.isEmpty) {
            effectivePhone = (existing.phoneNumber ?? '').trim();
          }
          if (effectiveDob.isEmpty) {
            effectiveDob = (existing.dateOfBirth ?? '').trim();
          }
        }
      } catch (_) {
        // Best-effort; proceed with whatever values we have.
      }
    }

    try {
      await _supabase.from('public_profiles').upsert({
        'uid': user.uid,
        'username': username,
        'display_name': (displayName ?? '').trim(),
        'phone_number': effectivePhone,
        'photo_path': effectivePhotoPath,
        'date_of_birth': effectiveDob,
      });
    } on PostgrestException catch (error) {
      // Only drop date_of_birth when the error is specifically about that
      // column (e.g. column does not exist). Otherwise rethrow immediately.
      final msg = error.message.toLowerCase();
      if (!msg.contains('date_of_birth') && !msg.contains('column')) {
        throw StateError(_publicProfileWriteErrorMessage(error));
      }
      try {
        await _supabase.from('public_profiles').upsert({
          'uid': user.uid,
          'username': username,
          'display_name': (displayName ?? '').trim(),
          'phone_number': effectivePhone,
          'photo_path': effectivePhotoPath,
        });
      } on PostgrestException catch (fallbackError) {
        throw StateError(_publicProfileWriteErrorMessage(fallbackError));
      } catch (_) {
        throw StateError(_publicProfileWriteErrorMessage(error));
      }
    } catch (_) {
      throw StateError(
        'Could not save profile details. Check Supabase public_profiles setup.',
      );
    }
  }

  Future<AegixaPublicProfile?> getPublicProfileForUserId(String uid) async {
    try {
      final row = await _supabase
          .from('public_profiles')
          .select(
              'uid,username,display_name,phone_number,photo_path,date_of_birth')
          .eq('uid', uid)
          .maybeSingle();
      if (row == null) {
        return null;
      }
      return AegixaPublicProfile(
        uid: (row['uid'] ?? '').toString(),
        username: row['username'] as String?,
        displayName: row['display_name'] as String?,
        phoneNumber: row['phone_number'] as String?,
        profilePhotoPath: row['photo_path'] as String?,
        dateOfBirth: row['date_of_birth'] as String?,
      );
    } catch (_) {
      try {
        final row = await _supabase
            .from('public_profiles')
            .select('uid,username,display_name,phone_number,photo_path')
            .eq('uid', uid)
            .maybeSingle();
        if (row == null) {
          return null;
        }
        return AegixaPublicProfile(
          uid: (row['uid'] ?? '').toString(),
          username: row['username'] as String?,
          displayName: row['display_name'] as String?,
          phoneNumber: row['phone_number'] as String?,
          profilePhotoPath: row['photo_path'] as String?,
        );
      } catch (_) {
        return null;
      }
    }
  }

  /// Look up a public profile by username (not uid).
  /// Returns the full profile including photo_path.
  Future<AegixaPublicProfile?> getPublicProfileForUsername(
      String username) async {
    try {
      final row = await _supabase
          .from('public_profiles')
          .select(
              'uid,username,display_name,phone_number,photo_path,date_of_birth')
          .eq('username', username)
          .maybeSingle();
      if (row == null) {
        return null;
      }
      return AegixaPublicProfile(
        uid: (row['uid'] ?? '').toString(),
        username: row['username'] as String?,
        displayName: row['display_name'] as String?,
        phoneNumber: row['phone_number'] as String?,
        profilePhotoPath: row['photo_path'] as String?,
        dateOfBirth: row['date_of_birth'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  /// Uploads a profile photo to Supabase Storage and returns the public URL.
  ///
  /// Returns `null` only when the local file does not exist.
  /// Throws on any storage/network error so callers can decide how to handle
  /// the failure instead of silently losing the photo URL.
  Future<String?> uploadProfilePhoto({
    required User user,
    required String localFilePath,
  }) async {
    final file = File(localFilePath);
    if (!file.existsSync()) {
      debugPrint('[uploadProfilePhoto] File does not exist: $localFilePath');
      return null;
    }

    final bytes = await file.readAsBytes();
    final extension = _safeImageExtension(localFilePath);
    final objectPath = '${user.uid}/profile.$extension';

    debugPrint('[uploadProfilePhoto] Uploading ${bytes.length} bytes '
        'to bucket "profile-photos", path "$objectPath"');

    try {
      await _supabase.storage.from('profile-photos').uploadBinary(
            objectPath,
            bytes,
            fileOptions: const FileOptions(upsert: true),
          );
    } catch (e) {
      debugPrint('[uploadProfilePhoto] Storage upload FAILED: $e');
      rethrow;
    }

    final url =
        _supabase.storage.from('profile-photos').getPublicUrl(objectPath);
    debugPrint('[uploadProfilePhoto] Success! Public URL: $url');
    return url;
  }

  Future<bool> _tryReserveUsername({
    required User user,
    required String username,
  }) async {
    try {
      await claimUsername(user: user, rawUsername: username);
      return true;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'username-already-set' || e.code == 'invalid-username') {
        rethrow;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  bool _isUniqueViolation(PostgrestException error) {
    return error.code == '23505' ||
        error.message.toLowerCase().contains('duplicate key') ||
        error.message.toLowerCase().contains('unique');
  }

  String _normalizeBase(String preferredName) {
    final lowered = preferredName.toLowerCase().trim().replaceAll(' ', '_');
    final cleaned = normalizeForInput(lowered);
    if (cleaned.isEmpty) {
      return 'aegixa_user';
    }
    return cleaned.length > 24 ? cleaned.substring(0, 24) : cleaned;
  }

  String _safeImageExtension(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'png';
    if (lower.endsWith('.webp')) return 'webp';
    return 'jpg';
  }

  String _publicProfileWriteErrorMessage(PostgrestException error) {
    final raw = error.message.trim();
    final lower = raw.toLowerCase();
    if (lower.contains('row-level security') ||
        lower.contains('permission denied') ||
        lower.contains('violates row-level security')) {
      return 'Supabase public_profiles policies are blocking save. Re-run supabase_public_profiles_schema.sql.';
    }
    if (lower.contains('date_of_birth') && lower.contains('column')) {
      return 'Supabase public_profiles is missing the date_of_birth column. Re-run supabase_public_profiles_schema.sql.';
    }
    if (raw.isNotEmpty) {
      return raw;
    }
    return 'Could not save profile details to Supabase.';
  }
}
