import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';

import 'emergency_contacts_service.dart';
import 'username_service.dart';

class SosTriggerCacheService {
  SosTriggerCacheService._();

  static final SosTriggerCacheService _instance = SosTriggerCacheService._();

  factory SosTriggerCacheService() => _instance;

  final EmergencyContactsService _emergencyContactsService =
      EmergencyContactsService();
  final UsernameService _usernameService = UsernameService();

  Position? _cachedPosition;

  Position? get cachedPosition => _cachedPosition;

  /// Pre-warms contacts, position, sender profile, and recipient profiles
  /// so that the SOS trigger path hits only in-memory caches.
  Future<void> warmup({bool refreshPrecisePosition = false}) async {
    List<EmergencyContact> contacts = const [];
    try {
      contacts = await _emergencyContactsService.getContacts();
    } catch (_) {
      // Keep using any existing contact cache when the network is unavailable.
    }

    await _cacheLastKnownPosition();

    if (refreshPrecisePosition) {
      unawaited(refreshPrecisePositionCache());
    }

    // Pre-warm sender profile and recipient profiles in background so
    // triggerAlerts() hits cache instead of making network calls.
    unawaited(_prewarmProfiles(contacts));
  }

  Future<void> _prewarmProfiles(List<EmergencyContact> contacts) async {
    // Sender profile
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await _usernameService.getPublicProfileForUserId(uid);
      }
    } catch (_) {}

    // Recipient profiles (batch)
    try {
      final usernames = contacts
          .map((c) => (c.username ?? '').trim())
          .where((u) => u.isNotEmpty)
          .toSet();
      if (usernames.isNotEmpty) {
        await _usernameService.getPublicProfilesForUsernames(usernames);
      }
    } catch (_) {}
  }

  Future<List<EmergencyContact>> getContacts() {
    return _emergencyContactsService.getContacts();
  }

  Future<Position> getBestAvailablePosition() async {
    final cached = _cachedPosition;
    if (cached != null) {
      return cached;
    }

    final lastKnown = await _cacheLastKnownPosition();
    if (lastKnown != null) {
      return lastKnown;
    }

    return refreshPrecisePositionCache();
  }

  Future<Position> refreshPrecisePositionCache() async {
    final position = await _getCurrentPositionWithOfflineFallback();
    _cachedPosition = position;
    return position;
  }

  void storePosition(Position position) {
    _cachedPosition = position;
  }

  Future<Position?> _cacheLastKnownPosition() async {
    try {
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        _cachedPosition = lastKnown;
      }
      return lastKnown;
    } catch (_) {
      return _cachedPosition;
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
}
