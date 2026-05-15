import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EmergencyContact {
  const EmergencyContact({
    this.id,
    required this.userId,
    required this.name,
    required this.phoneNumber,
    this.username,
    this.profilePhotoPath,
    required this.isPrimary,
  });

  final int? id;
  final String userId;
  final String name;
  final String phoneNumber;
  final String? username;
  final String? profilePhotoPath;
  final bool isPrimary;

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'name': name,
      'phone_number': phoneNumber,
      'username': username,
      'profile_photo_path': profilePhotoPath,
      'is_primary': isPrimary,
    };
  }

  EmergencyContact copyWith({
    int? id,
    String? userId,
    String? name,
    String? phoneNumber,
    String? username,
    String? profilePhotoPath,
    bool? isPrimary,
  }) {
    return EmergencyContact(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      username: username ?? this.username,
      profilePhotoPath: profilePhotoPath ?? this.profilePhotoPath,
      isPrimary: isPrimary ?? this.isPrimary,
    );
  }

  factory EmergencyContact.fromMap(Map<String, dynamic> map) {
    final rawId = map['id'];
    return EmergencyContact(
      id: rawId is int ? rawId : int.tryParse((rawId ?? '').toString()),
      userId: (map['user_id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      phoneNumber: (map['phone_number'] ?? '').toString(),
      username: map['username'] as String?,
      profilePhotoPath: map['profile_photo_path'] as String?,
      isPrimary: map['is_primary'] == true || map['is_primary'] == 1,
    );
  }
}

class EmergencyContactsService {
  EmergencyContactsService._();
  static final EmergencyContactsService _instance =
      EmergencyContactsService._();
  factory EmergencyContactsService() => _instance;

  static const _table = 'emergency_contacts';
  static const _skipKeyPrefix = 'emergency_contacts_setup_skipped_';
  static const _cacheKeyPrefix = 'emergency_contacts_cache_';
  static const Duration _cacheTtl = Duration(minutes: 10);
  final SupabaseClient _supabase = Supabase.instance.client;
  final Map<String, List<EmergencyContact>> _memoryCache = {};
  final Map<String, DateTime> _memoryCacheExpiresAt = {};

  String get _currentUserId {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('User must be signed in to manage emergency contacts.');
    }
    return user.uid;
  }

  Future<List<EmergencyContact>> getContacts() async {
    final userId = _currentUserId;
    final freshMemoryCache = _getFreshMemoryCache(userId);
    if (freshMemoryCache != null) {
      return freshMemoryCache;
    }

    final persistedCache = await _loadContactsCache(userId, requireFresh: true);
    if (persistedCache != null) {
      _setMemoryCache(userId, persistedCache);
      return persistedCache;
    }

    try {
      final rows = await _supabase
          .from(_table)
          .select()
          .eq('user_id', userId)
          .order('is_primary', ascending: false)
          .order('id', ascending: true);

      final contacts = rows
          .whereType<Map<String, dynamic>>()
          .map(EmergencyContact.fromMap)
          .toList();
      await _saveContactsCache(userId, contacts);
      return contacts;
    } catch (_) {
      try {
        final rows = await _supabase
            .from(_table)
            .select()
            .eq('user_id', userId)
            .order('is_primary', ascending: false)
            .order('name', ascending: true);

        final contacts = rows
            .whereType<Map<String, dynamic>>()
            .map(EmergencyContact.fromMap)
            .toList();
        await _saveContactsCache(userId, contacts);
        return contacts;
      } catch (_) {
        return (await _loadContactsCache(userId)) ?? const [];
      }
    }
  }

  Future<bool> hasContacts() async {
    final contacts = await getContacts();
    return contacts.isNotEmpty;
  }

  /// Maximum length for contact name to prevent abuse / storage issues.
  static const _maxNameLength = 100;

  /// Maximum length for phone number string.
  static const _maxPhoneLength = 20;

  /// Validates and sanitizes a contact before saving.
  EmergencyContact _sanitizeContact(EmergencyContact contact) {
    final name = contact.name.trim();
    if (name.isEmpty) {
      throw ArgumentError('Contact name must not be empty.');
    }
    if (name.length > _maxNameLength) {
      throw ArgumentError(
        'Contact name exceeds $_maxNameLength characters.',
      );
    }

    final phone = contact.phoneNumber.replaceAll(RegExp(r'[^\d+\-() ]'), '');
    if (phone.isEmpty) {
      throw ArgumentError('Contact phone number must not be empty.');
    }
    if (phone.length > _maxPhoneLength) {
      throw ArgumentError(
        'Phone number exceeds $_maxPhoneLength characters.',
      );
    }

    return contact.copyWith(name: name, phoneNumber: phone);
  }

  Future<void> saveContact(EmergencyContact contact) async {
    final sanitized = _sanitizeContact(contact);
    final userId = _currentUserId;
    final data = sanitized.copyWith(userId: userId).toMap()..remove('id');

    try {
      if (sanitized.id == null) {
        await _supabase.from(_table).insert(data);
      } else {
        await _supabase
            .from(_table)
            .update(data)
            .eq('id', sanitized.id as Object)
            .eq('user_id', userId);
      }
    } on PostgrestException catch (e) {
      final message = (e.message).toLowerCase();
      final isPermissionIssue =
          e.code == '42501' || message.contains('permission');
      if (isPermissionIssue) {
        throw StateError(
          'Emergency contacts save failed: Supabase RLS policy blocked write. '
          'Apply the latest `supabase_emergency_contacts_schema.sql` policies.',
        );
      }
      throw StateError('Emergency contacts save failed: ${e.message}');
    }

    await _refreshContactsCache(userId);
    await markOnboardingSkipped(false);
  }

  Future<void> deleteContact(int id) async {
    final userId = _currentUserId;
    await _supabase
        .from(_table)
        .delete()
        .eq('id', id)
        .eq('user_id', userId);
    await _refreshContactsCache(userId);
  }

  Future<bool> shouldShowOnboarding() async {
    if (await hasContacts()) {
      return false;
    }
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool('$_skipKeyPrefix$_currentUserId') ?? false);
  }

  Future<void> markOnboardingSkipped(bool skipped) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_skipKeyPrefix$_currentUserId', skipped);
  }

  Future<void> _refreshContactsCache(String userId) async {
    try {
      final rows = await _supabase
          .from(_table)
          .select()
          .eq('user_id', userId)
          .order('is_primary', ascending: false)
          .order('id', ascending: true);
      final contacts = rows
          .whereType<Map<String, dynamic>>()
          .map(EmergencyContact.fromMap)
          .toList();
      await _saveContactsCache(userId, contacts);
    } catch (_) {
      // Ignore cache refresh failures when network is unavailable.
    }
  }

  Future<void> _saveContactsCache(
    String userId,
    List<EmergencyContact> contacts,
  ) async {
    _setMemoryCache(userId, contacts);
    final prefs = await SharedPreferences.getInstance();
    final payload = contacts.map((contact) => contact.toMap()).toList();
    await prefs.setString(
      '$_cacheKeyPrefix$userId',
      jsonEncode({
        'expires_at': DateTime.now().add(_cacheTtl).toIso8601String(),
        'contacts': payload,
      }),
    );
  }

  Future<List<EmergencyContact>?> _loadContactsCache(
    String userId, {
    bool requireFresh = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_cacheKeyPrefix$userId');
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        final legacyContacts = decoded
            .whereType<Map<String, dynamic>>()
            .map(EmergencyContact.fromMap)
            .toList();
        if (legacyContacts.isEmpty) {
          return null;
        }
        return legacyContacts;
      }
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      final expiresRaw = decoded['expires_at'];
      final contactsRaw = decoded['contacts'];
      if (contactsRaw is! List) {
        return null;
      }
      final contacts = contactsRaw
          .whereType<Map<String, dynamic>>()
          .map(EmergencyContact.fromMap)
          .toList();
      final expiresAt = expiresRaw is String ? DateTime.tryParse(expiresRaw) : null;
      if (requireFresh && expiresAt != null && DateTime.now().isAfter(expiresAt)) {
        return null;
      }
      return contacts;
    } catch (_) {
      return null;
    }
  }

  List<EmergencyContact>? _getFreshMemoryCache(String userId) {
    final expiresAt = _memoryCacheExpiresAt[userId];
    final contacts = _memoryCache[userId];
    if (expiresAt == null || contacts == null) {
      return null;
    }
    if (DateTime.now().isAfter(expiresAt)) {
      return null;
    }
    return contacts;
  }

  void _setMemoryCache(String userId, List<EmergencyContact> contacts) {
    _memoryCache[userId] = List<EmergencyContact>.unmodifiable(contacts);
    _memoryCacheExpiresAt[userId] = DateTime.now().add(_cacheTtl);
  }
}
