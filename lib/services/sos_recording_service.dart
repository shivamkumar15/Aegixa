import 'dart:io';

import 'package:camera/camera.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:sqflite/sqflite.dart';

class SosRecording {
  const SosRecording({
    this.id,
    required this.userId,
    required this.filePath,
    required this.startedAt,
    this.stoppedAt,
    required this.isActive,
  });

  final int? id;
  final String userId;
  final String filePath;
  final DateTime startedAt;
  final DateTime? stoppedAt;
  final bool isActive;

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'file_path': filePath,
      'started_at': startedAt.toIso8601String(),
      'stopped_at': stoppedAt?.toIso8601String(),
      'is_active': isActive ? 1 : 0,
    };
  }

  factory SosRecording.fromMap(Map<String, Object?> map) {
    return SosRecording(
      id: map['id'] as int?,
      userId: map['user_id'] as String,
      filePath: map['file_path'] as String,
      startedAt: DateTime.parse(map['started_at'] as String),
      stoppedAt: map['stopped_at'] == null
          ? null
          : DateTime.parse(map['stopped_at'] as String),
      isActive: (map['is_active'] as int? ?? 0) == 1,
    );
  }
}

class SosVideoRecording {
  const SosVideoRecording({
    this.id,
    required this.userId,
    required this.filePath,
    required this.createdAt,
  });

  final int? id;
  final String userId;
  final String filePath;
  final DateTime createdAt;

  factory SosVideoRecording.fromMap(Map<String, Object?> map) {
    return SosVideoRecording(
      id: map['id'] as int?,
      userId: map['user_id'] as String,
      filePath: map['file_path'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}

class SosRecordingService {
  SosRecordingService._();

  static final SosRecordingService _instance = SosRecordingService._();
  factory SosRecordingService() => _instance;

  static const _dbName = 'aegixa_sos.db';
  static const _table = 'sos_recordings';
  static const _videoTable = 'sos_videos';

  final AudioRecorder _recorder = AudioRecorder();
  final ImagePicker _imagePicker = ImagePicker();
  CameraController? _cameraController;
  Database? _database;
  int? _activeRecordingId;
  String? _activeRecordingPath;
  bool _videoRecordingActive = false;
  DateTime? _videoStartedAt;

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }

    final dbPath = await getDatabasesPath();
    _database = await openDatabase(
      path.join(dbPath, _dbName),
      version: 2,
      onCreate: (db, version) async {
        await _createTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS $_videoTable (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              user_id TEXT NOT NULL,
              file_path TEXT NOT NULL,
              created_at TEXT NOT NULL
            )
          ''');
        }
      },
    );

    return _database!;
  }

  Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE $_table (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id TEXT NOT NULL,
        file_path TEXT NOT NULL,
        started_at TEXT NOT NULL,
        stopped_at TEXT,
        is_active INTEGER NOT NULL DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE $_videoTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id TEXT NOT NULL,
        file_path TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
  }

  bool get isRecordingActive => _activeRecordingId != null;
  bool get isVideoRecordingActive => _videoRecordingActive;

  String get _currentUserId {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('User must be signed in to create SOS recordings.');
    }
    return user.uid;
  }

  Future<String> startRecording() async {
    if (isRecordingActive && _activeRecordingPath != null) {
      return _activeRecordingPath!;
    }

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      throw StateError('Microphone permission is required for SOS recording.');
    }

    final appDirectory = await getApplicationDocumentsDirectory();
    final recordingsDirectory = Directory(
      path.join(appDirectory.path, 'sos_recordings'),
    );
    await recordingsDirectory.create(recursive: true);

    final filePath = path.join(
      recordingsDirectory.path,
      'sos_${DateTime.now().millisecondsSinceEpoch}.m4a',
    );

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
      ),
      path: filePath,
    );

    final db = await database;
    final startedAt = DateTime.now();
    final id = await db.insert(
      _table,
      SosRecording(
        userId: _currentUserId,
        filePath: filePath,
        startedAt: startedAt,
        isActive: true,
      ).toMap()
        ..remove('id'),
    );

    _activeRecordingId = id;
    _activeRecordingPath = filePath;
    return filePath;
  }

  Future<String?> stopRecording() async {
    if (!isRecordingActive) {
      return null;
    }

    final recordedPath = await _recorder.stop();
    final finalPath = recordedPath ?? _activeRecordingPath;

    if (_activeRecordingId != null && finalPath != null) {
      final db = await database;
      await db.update(
        _table,
        {
          'file_path': finalPath,
          'stopped_at': DateTime.now().toIso8601String(),
          'is_active': 0,
        },
        where: 'id = ? AND user_id = ?',
        whereArgs: [_activeRecordingId, _currentUserId],
      );
    }

    _activeRecordingId = null;
    _activeRecordingPath = null;
    return finalPath;
  }

  Future<List<SosRecording>> getRecordings() async {
    final db = await database;
    final rows = await db.query(
      _table,
      where: 'user_id = ?',
      whereArgs: [_currentUserId],
      orderBy: 'started_at DESC',
    );
    return rows.map(SosRecording.fromMap).toList();
  }

  Future<void> deleteRecording(int id) async {
    final db = await database;
    await db.delete(
      _table,
      where: 'id = ? AND user_id = ?',
      whereArgs: [id, _currentUserId],
    );
  }

  Future<List<SosVideoRecording>> getVideoRecordings() async {
    final db = await database;
    final rows = await db.query(
      _videoTable,
      where: 'user_id = ?',
      whereArgs: [_currentUserId],
      orderBy: 'created_at DESC',
    );
    return rows.map(SosVideoRecording.fromMap).toList();
  }

  Future<void> deleteVideoRecording(int id) async {
    final db = await database;
    await db.delete(
      _videoTable,
      where: 'id = ? AND user_id = ?',
      whereArgs: [id, _currentUserId],
    );
  }

  Future<String?> captureAndSaveSosVideo() async {
    final capture = await _imagePicker.pickVideo(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.rear,
      maxDuration: const Duration(minutes: 2),
    );

    if (capture == null) {
      return null;
    }

    final db = await database;
    await db.insert(_videoTable, {
      'user_id': _currentUserId,
      'file_path': capture.path,
      'created_at': DateTime.now().toIso8601String(),
    });

    return capture.path;
  }

  Future<void> startAutoVideoRecording() async {
    if (_videoRecordingActive) {
      return;
    }

    // Set flag immediately to prevent concurrent calls from racing
    _videoRecordingActive = true;

    try {
      final cameras = await availableCameras();
      final selectedCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        selectedCamera,
        ResolutionPreset.medium,
        enableAudio: true,
      );

      await controller.initialize();
      await controller.prepareForVideoRecording();
      await controller.startVideoRecording();

      // Dispose the old controller only after the new one is fully ready
      final oldController = _cameraController;
      _cameraController = controller;
      _videoStartedAt = DateTime.now();

      // Dispose old controller after reassignment to avoid use-after-dispose
      try {
        await oldController?.dispose();
      } catch (_) {
        // Old controller may already be disposed; safe to ignore.
      }
    } catch (e) {
      _videoRecordingActive = false;
      rethrow;
    }
  }

  Future<String?> stopAutoVideoRecording() async {
    if (!_videoRecordingActive || _cameraController == null) {
      return null;
    }

    final recordedFile = await _cameraController!.stopVideoRecording();
    final pathValue = recordedFile.path;
    final db = await database;
    await db.insert(_videoTable, {
      'user_id': _currentUserId,
      'file_path': pathValue,
      'created_at': (_videoStartedAt ?? DateTime.now()).toIso8601String(),
    });

    await _cameraController!.dispose();
    _cameraController = null;
    _videoRecordingActive = false;
    _videoStartedAt = null;
    return pathValue;
  }

  /// Save an entry for a native (service-based) audio recording file.
  Future<void> saveNativeAudioEntry(String filePath) async {
    final db = await database;
    await db.insert(
      _table,
      SosRecording(
        userId: _currentUserId,
        filePath: filePath,
        startedAt: DateTime.now(),
        stoppedAt: DateTime.now(),
        isActive: false,
      ).toMap()
        ..remove('id'),
    );
  }

  /// Save an entry for a native (service-based) video recording file.
  Future<void> saveNativeVideoEntry(String filePath) async {
    final db = await database;
    await db.insert(_videoTable, {
      'user_id': _currentUserId,
      'file_path': filePath,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> disposeRecorder() async {
    await _recorder.dispose();
    await _cameraController?.dispose();
    _cameraController = null;
    _videoRecordingActive = false;
  }
}
