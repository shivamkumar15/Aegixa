import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

class SailorUserSuggestion {
  const SailorUserSuggestion({
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

class SailorPublicProfile {
  const SailorPublicProfile({
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

  Map<String, Object?> toMap() {
    return {
      'uid': uid,
      'username': username,
      'display_name': displayName,
      'phone_number': phoneNumber,
      'photo_path': profilePhotoPath,
      'date_of_birth': dateOfBirth,
    };
  }

  factory SailorPublicProfile.fromMap(Map<String, dynamic> map) {
    return SailorPublicProfile(
      uid: (map['uid'] ?? '').toString(),
      username: map['username'] as String?,
      displayName: map['display_name'] as String?,
      phoneNumber: map['phone_number'] as String?,
      profilePhotoPath: map['photo_path'] as String?,
      dateOfBirth: map['date_of_birth'] as String?,
    );
  }
}

class _MemoryCacheEntry<T> {
  const _MemoryCacheEntry(this.value, this.expiresAt);

  final T value;
  final DateTime expiresAt;

  bool get isFresh => DateTime.now().isBefore(expiresAt);
}

class UsernameService {
  UsernameService._();
  static final UsernameService _instance = UsernameService._();
  factory UsernameService() => _instance;

  final SupabaseClient _supabase = Supabase.instance.client;
  static const _table = 'usernames';
  static const Duration _usernameCacheTtl = Duration(minutes: 10);
  static const Duration _profileCacheTtl = Duration(minutes: 10);
  static const Duration _searchCacheTtl = Duration(seconds: 30);
  static const Duration _availabilityCacheTtl = Duration(seconds: 10);
  static const _usernameCacheKeyPrefix = 'username_cache_v1_';
  static const _profileUidCacheKeyPrefix = 'public_profile_uid_cache_v1_';
  static const _profileUsernameCacheKeyPrefix =
      'public_profile_username_cache_v1_';

  final Map<String, _MemoryCacheEntry<String?>> _usernameCache = {};
  final Map<String, _MemoryCacheEntry<SailorPublicProfile?>> _profileUidCache =
      {};
  final Map<String, _MemoryCacheEntry<SailorPublicProfile?>>
      _profileUsernameCache = {};
  final Map<String, _MemoryCacheEntry<List<SailorUserSuggestion>>>
      _searchCache = {};
  final Map<String, _MemoryCacheEntry<String?>> _availabilityCache = {};

  String normalizeForInput(String value) {
    final lowered = value.toLowerCase().trim();
    final cleaned = lowered.replaceAll(RegExp(r'[^a-z0-9._]'), '');
    final singleDots = cleaned.replaceAll(RegExp(r'\.{2,}'), '.');
    final singleUnderscore = singleDots.replaceAll(RegExp(r'_{2,}'), '_');
    final trimmed = singleUnderscore.replaceAll(RegExp(r'^[._]+|[._]+$'), '');
    return trimmed.length > 24 ? trimmed.substring(0, 24) : trimmed;
  }

  Future<String?> getUsernameForUserId(String userId) async {
    final cached = _usernameCache[userId];
    if (cached != null && cached.isFresh) {
      return cached.value;
    }

    final persisted = await _loadPersistedValue<String?>(
      '$_usernameCacheKeyPrefix$userId',
      (map) {
        final username = map['username'];
        if (username is String && username.trim().isNotEmpty) {
          return username.trim();
        }
        return null;
      },
    );
    if (persisted.hit) {
      _usernameCache[userId] = _MemoryCacheEntry(
        persisted.value,
        persisted.expiresAt!,
      );
      return persisted.value;
    }

    try {
      final data = await _supabase
          .from(_table)
          .select('username')
          .eq('uid', userId)
          .maybeSingle();
      final username = _extractUsername(data);
      await _cacheUsername(userId, username);
      return username;
    } catch (_) {
      if (cached != null) {
        return cached.value;
      }
      return persisted.value;
    }
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

    // Check short-lived availability cache first.
    final cached = _availabilityCache[username];
    if (cached != null && cached.isFresh) {
      final cachedOwnerId = cached.value;
      if (cachedOwnerId == null) {
        return true; // No owner — available.
      }
      return cachedOwnerId == currentUserId;
    }

    final usernameRow = await _supabase
        .from(_table)
        .select('uid')
        .eq('username', username)
        .maybeSingle();

    final ownerId =
        usernameRow == null ? null : (usernameRow['uid'] ?? '').toString();
    _availabilityCache[username] = _MemoryCacheEntry(
      ownerId,
      DateTime.now().add(_availabilityCacheTtl),
    );

    if (usernameRow == null) {
      return true;
    }
    return ownerId == currentUserId;
  }

  /// Batch-check availability for multiple usernames in a single query.
  Future<Map<String, String?>> _batchCheckAvailability(
    List<String> usernames,
  ) async {
    if (usernames.isEmpty) {
      return const <String, String?>{};
    }

    final result = <String, String?>{};
    final toFetch = <String>[];

    for (final username in usernames) {
      final cached = _availabilityCache[username];
      if (cached != null && cached.isFresh) {
        result[username] = cached.value;
      } else {
        toFetch.add(username);
      }
    }

    if (toFetch.isNotEmpty) {
      final rows = await _supabase
          .from(_table)
          .select('uid,username')
          .inFilter('username', toFetch);

      final fetched = <String, String>{};
      for (final row in rows) {
        final u = (row['username'] ?? '').toString().trim();
        final uid = (row['uid'] ?? '').toString().trim();
        if (u.isNotEmpty && uid.isNotEmpty) {
          fetched[u] = uid;
        }
      }

      final expiry = DateTime.now().add(_availabilityCacheTtl);
      for (final username in toFetch) {
        final ownerId = fetched[username];
        result[username] = ownerId;
        _availabilityCache[username] = _MemoryCacheEntry(ownerId, expiry);
      }
    }

    return result;
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

    // Try the in-memory username cache first before hitting DB.
    final cachedUsername = _usernameCache[user.uid];
    String? existingUsername;
    if (cachedUsername != null && cachedUsername.isFresh) {
      existingUsername = cachedUsername.value;
    } else {
      final existingForUser = await _supabase
          .from(_table)
          .select('username')
          .eq('uid', user.uid)
          .maybeSingle();
      existingUsername = _extractUsername(existingForUser);
      await _cacheUsername(user.uid, existingUsername);
    }

    if (existingUsername != null && existingUsername.trim().isNotEmpty) {
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
      await _cacheUsername(user.uid, username);
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

    // Build all valid candidates up front.
    final candidates = <String>[];
    final seen = <String>{};
    for (var attempt = 0; candidates.length < 80 && attempt < 80; attempt++) {
      final candidate = attempt == 0 ? base : '$base${attempt + 1}';
      if (!seen.add(candidate)) {
        continue;
      }
      if (!isValidUsernameFormat(candidate)) {
        continue;
      }
      candidates.add(candidate);
    }

    if (candidates.isEmpty) {
      return const <String>[];
    }

    // Single batch query instead of up to 80 serial DB calls.
    final ownersByUsername = await _batchCheckAvailability(candidates);

    final suggestions = <String>[];
    for (final candidate in candidates) {
      if (suggestions.length >= max) {
        break;
      }
      final ownerId = ownersByUsername[candidate];
      if (ownerId == null || ownerId == currentUserId) {
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

  Future<List<SailorUserSuggestion>> searchUsers(
    String rawQuery, {
    int limit = 8,
  }) async {
    final query = normalizeForInput(rawQuery);
    if (query.length < 2) {
      return const <SailorUserSuggestion>[];
    }

    final cacheKey = '$query:$limit';
    final cached = _searchCache[cacheKey];
    if (cached != null && cached.isFresh) {
      return cached.value;
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
          (row) => SailorUserSuggestion(
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

      final hydrated = suggestions.map((item) {
        final profile = profileMap[item.uid];
        return SailorUserSuggestion(
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
      _searchCache[cacheKey] = _MemoryCacheEntry(
        hydrated,
        DateTime.now().add(_searchCacheTtl),
      );
      return hydrated;
    } catch (_) {
      _searchCache[cacheKey] = _MemoryCacheEntry(
        suggestions,
        DateTime.now().add(_searchCacheTtl),
      );
      return suggestions;
    }
  }

  Future<Map<String, SailorPublicProfile>> getPublicProfilesForUsernames(
    Iterable<String> usernames,
  ) async {
    final normalizedUsernames = usernames
        .map((username) => username.trim())
        .where((username) => username.isNotEmpty)
        .toSet()
        .toList();
    if (normalizedUsernames.isEmpty) {
      return const <String, SailorPublicProfile>{};
    }

    final profilesByUsername = <String, SailorPublicProfile>{};
    final missingUsernames = <String>[];

    for (final username in normalizedUsernames) {
      final cached = _profileUsernameCache[username];
      if (cached != null && cached.isFresh && cached.value != null) {
        profilesByUsername[username] = cached.value!;
        continue;
      }

      final persisted = await _loadPersistedValue<SailorPublicProfile?>(
        '$_profileUsernameCacheKeyPrefix$username',
        (map) => SailorPublicProfile.fromMap(map),
      );
      if (persisted.hit && persisted.value != null) {
        final profile = persisted.value!;
        _profileUsernameCache[username] = _MemoryCacheEntry(
          profile,
          persisted.expiresAt!,
        );
        if (profile.uid.isNotEmpty) {
          _profileUidCache[profile.uid] = _MemoryCacheEntry(
            profile,
            persisted.expiresAt!,
          );
        }
        profilesByUsername[username] = profile;
        continue;
      }

      missingUsernames.add(username);
    }

    if (missingUsernames.isEmpty) {
      return profilesByUsername;
    }

    try {
      final rows = await _supabase
          .from('public_profiles')
          .select(
              'uid,username,display_name,phone_number,photo_path,date_of_birth')
          .inFilter('username', missingUsernames);

      final fetchedUsernames = <String>{};
      for (final row in rows.whereType<Map<String, dynamic>>()) {
        final profile = SailorPublicProfile.fromMap(row);
        final username = (profile.username ?? '').trim();
        if (username.isEmpty) {
          continue;
        }
        fetchedUsernames.add(username);
        profilesByUsername[username] = profile;
        await _cachePublicProfile(profile);
      }

      for (final username in missingUsernames) {
        if (!fetchedUsernames.contains(username)) {
          await _cachePublicProfile(null, username: username);
        }
      }
    } catch (_) {
      for (final username in missingUsernames) {
        final fallback = _profileUsernameCache[username];
        if (fallback?.value != null) {
          profilesByUsername[username] = fallback!.value!;
        }
      }
    }

    return profilesByUsername;
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

    await _cachePublicProfile(
      SailorPublicProfile(
        uid: user.uid,
        username: username,
        displayName: (displayName ?? '').trim(),
        phoneNumber: effectivePhone,
        profilePhotoPath: effectivePhotoPath,
        dateOfBirth: effectiveDob.isEmpty ? null : effectiveDob,
      ),
    );
  }

  Future<SailorPublicProfile?> getPublicProfileForUserId(String uid) async {
    final cached = _profileUidCache[uid];
    if (cached != null && cached.isFresh) {
      return cached.value;
    }

    final persisted = await _loadPersistedValue<SailorPublicProfile?>(
      '$_profileUidCacheKeyPrefix$uid',
      (map) => SailorPublicProfile.fromMap(map),
    );
    if (persisted.hit) {
      _profileUidCache[uid] = _MemoryCacheEntry(
        persisted.value,
        persisted.expiresAt!,
      );
      final profile = persisted.value;
      if (profile != null && (profile.username ?? '').trim().isNotEmpty) {
        _profileUsernameCache[profile.username!.trim()] = _MemoryCacheEntry(
          profile,
          persisted.expiresAt!,
        );
      }
      return profile;
    }

    try {
      final row = await _supabase
          .from('public_profiles')
          .select(
              'uid,username,display_name,phone_number,photo_path,date_of_birth')
          .eq('uid', uid)
          .maybeSingle();
      if (row == null) {
        await _cachePublicProfile(null, uid: uid);
        return null;
      }
      final profile = SailorPublicProfile.fromMap(row);
      await _cachePublicProfile(profile);
      return profile;
    } catch (_) {
      try {
        final row = await _supabase
            .from('public_profiles')
            .select('uid,username,display_name,phone_number,photo_path')
            .eq('uid', uid)
            .maybeSingle();
        if (row == null) {
          await _cachePublicProfile(null, uid: uid);
          return null;
        }
        final profile = SailorPublicProfile.fromMap(row);
        await _cachePublicProfile(profile);
        return profile;
      } catch (_) {
        if (cached != null) {
          return cached.value;
        }
        return persisted.value;
      }
    }
  }

  /// Look up a public profile by username (not uid).
  /// Returns the full profile including photo_path.
  Future<SailorPublicProfile?> getPublicProfileForUsername(
      String username) async {
    final normalizedUsername = username.trim();
    if (normalizedUsername.isEmpty) {
      return null;
    }

    final cached = _profileUsernameCache[normalizedUsername];
    if (cached != null && cached.isFresh) {
      return cached.value;
    }

    final persisted = await _loadPersistedValue<SailorPublicProfile?>(
      '$_profileUsernameCacheKeyPrefix$normalizedUsername',
      (map) => SailorPublicProfile.fromMap(map),
    );
    if (persisted.hit) {
      _profileUsernameCache[normalizedUsername] = _MemoryCacheEntry(
        persisted.value,
        persisted.expiresAt!,
      );
      final profile = persisted.value;
      if (profile != null && profile.uid.isNotEmpty) {
        _profileUidCache[profile.uid] = _MemoryCacheEntry(
          profile,
          persisted.expiresAt!,
        );
      }
      return profile;
    }

    try {
      final row = await _supabase
          .from('public_profiles')
          .select(
              'uid,username,display_name,phone_number,photo_path,date_of_birth')
          .eq('username', normalizedUsername)
          .maybeSingle();
      if (row == null) {
        await _cachePublicProfile(null, username: normalizedUsername);
        return null;
      }
      final profile = SailorPublicProfile.fromMap(row);
      await _cachePublicProfile(profile);
      return profile;
    } catch (_) {
      if (cached != null) {
        return cached.value;
      }
      return persisted.value;
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
      return 'sailor_user';
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

  String? _extractUsername(Map<String, dynamic>? data) {
    final username = data?['username'];
    if (username is String && username.trim().isNotEmpty) {
      return username.trim();
    }
    return null;
  }

  Future<void> _cacheUsername(String userId, String? username) async {
    final expiresAt = DateTime.now().add(_usernameCacheTtl);
    _usernameCache[userId] = _MemoryCacheEntry(username, expiresAt);
    await _savePersistedValue(
      '$_usernameCacheKeyPrefix$userId',
      expiresAt,
      {'username': username},
    );
  }

  Future<void> _cachePublicProfile(
    SailorPublicProfile? profile, {
    String? uid,
    String? username,
  }) async {
    final resolvedUid = profile?.uid ?? uid;
    final resolvedUsername = (profile?.username ?? username ?? '').trim();
    final expiresAt = DateTime.now().add(_profileCacheTtl);

    if (resolvedUid != null && resolvedUid.isNotEmpty) {
      _profileUidCache[resolvedUid] = _MemoryCacheEntry(profile, expiresAt);
      await _savePersistedValue(
        '$_profileUidCacheKeyPrefix$resolvedUid',
        expiresAt,
        profile?.toMap(),
      );
    }

    if (resolvedUsername.isNotEmpty) {
      _profileUsernameCache[resolvedUsername] = _MemoryCacheEntry(
        profile,
        expiresAt,
      );
      await _savePersistedValue(
        '$_profileUsernameCacheKeyPrefix$resolvedUsername',
        expiresAt,
        profile?.toMap(),
      );
    }
  }

  Future<void> _savePersistedValue(
    String key,
    DateTime expiresAt,
    Map<String, Object?>? data,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      key,
      jsonEncode({
        'expires_at': expiresAt.toIso8601String(),
        'data': data,
      }),
    );
  }

  Future<_PersistedCacheResult<T>> _loadPersistedValue<T>(
    String key,
    T Function(Map<String, dynamic> map) parser,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.trim().isEmpty) {
      return const _PersistedCacheResult.miss();
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return const _PersistedCacheResult.miss();
      }
      final expiresRaw = decoded['expires_at'];
      final expiresAt = expiresRaw is String
          ? DateTime.tryParse(expiresRaw)
          : null;
      final data = decoded['data'];
      if (expiresAt == null) {
        return const _PersistedCacheResult.miss();
      }
      if (data == null) {
        return _PersistedCacheResult.hit(null, expiresAt);
      }
      if (data is! Map<String, dynamic>) {
        return const _PersistedCacheResult.miss();
      }
      if (DateTime.now().isAfter(expiresAt)) {
        return _PersistedCacheResult.stale(parser(data));
      }
      return _PersistedCacheResult.hit(parser(data), expiresAt);
    } catch (_) {
      return const _PersistedCacheResult.miss();
    }
  }
}

class _PersistedCacheResult<T> {
  const _PersistedCacheResult.hit(this.value, this.expiresAt)
      : hit = true;

  const _PersistedCacheResult.stale(this.value)
      : hit = false,
        expiresAt = null;

  const _PersistedCacheResult.miss()
      : hit = false,
        value = null,
        expiresAt = null;

  final bool hit;
  final T? value;
  final DateTime? expiresAt;
}
