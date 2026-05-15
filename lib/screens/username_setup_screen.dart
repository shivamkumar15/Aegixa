import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/username_service.dart';
import '../ui_components.dart';
import 'emergency_contacts_setup_screen.dart';

class UsernameSetupScreen extends StatefulWidget {
  const UsernameSetupScreen({
    super.key,
    required this.user,
    this.prefilledUsername,
  });

  final User user;
  final String? prefilledUsername;

  @override
  State<UsernameSetupScreen> createState() => _UsernameSetupScreenState();
}

class _UsernameSetupScreenState extends State<UsernameSetupScreen> {
  final _service = UsernameService();
  final _imagePicker = ImagePicker();
  final _usernameController = TextEditingController();
  final _dobController = TextEditingController();
  final _phoneController = TextEditingController();

  Timer? _debounce;
  bool _checkingAvailability = false;
  bool _isAvailable = false;
  bool _saving = false;
  bool _usernameLocked = false;
  String? _availabilityMessage;
  String? _errorMessage;
  String _normalizedPreview = '';
  List<String> _suggestions = const <String>[];
  DateTime? _selectedDob;
  String? _profilePhotoPath;

  bool _isRemotePhoto(String? path) {
    final value = (path ?? '').trim().toLowerCase();
    return value.startsWith('http://') || value.startsWith('https://');
  }

  ImageProvider<Object>? _profileImageProvider() {
    final pathValue = (_profilePhotoPath ?? '').trim();
    if (pathValue.isEmpty) {
      return null;
    }
    if (_isRemotePhoto(pathValue)) {
      return NetworkImage(pathValue);
    }
    final file = File(pathValue);
    if (file.existsSync()) {
      return FileImage(file);
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _prepareUsername();
    _usernameController.addListener(_onUsernameChanged);
    _loadSavedProfileDetails();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _usernameController.removeListener(_onUsernameChanged);
    _usernameController.dispose();
    _dobController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _prepareUsername() {
    final preset = (widget.prefilledUsername ?? '').trim();
    if (preset.isNotEmpty) {
      final normalized = _service.normalizeForInput(preset);
      _usernameController.text = normalized;
      _normalizedPreview = normalized;
      _usernameLocked = true;
      _isAvailable = true;
      _availabilityMessage = '@$normalized is linked to this account.';
      return;
    }

    final base = _defaultBaseUsername();
    _usernameController.text = base;
    _normalizedPreview = base;
    _checkAvailability();
  }

  Future<void> _loadSavedProfileDetails() async {
    SailorPublicProfile? remoteProfile;
    try {
      remoteProfile =
          await _service.getPublicProfileForUserId(widget.user.uid);
    } catch (_) {
      // Offline or network error — fall through to SharedPreferences fallback.
    }
    final prefs = await SharedPreferences.getInstance();
    final savedDob = (remoteProfile?.dateOfBirth ??
            prefs.getString('profile_dob_${widget.user.uid}') ??
            '')
        .trim();
    final savedPhone = (remoteProfile?.phoneNumber ??
            prefs.getString('profile_phone_${widget.user.uid}') ??
            '')
        .trim();
    final savedPhoto = (remoteProfile?.profilePhotoPath ??
            prefs.getString('profile_photo_${widget.user.uid}') ??
            '')
        .trim();

    if (!mounted) {
      return;
    }

    if (savedPhone.isNotEmpty) {
      _phoneController.text = savedPhone;
    }

    if (savedDob.isNotEmpty) {
      final parsed = DateTime.tryParse(savedDob);
      if (parsed != null) {
        _selectedDob = parsed;
        _dobController.text =
            '${parsed.day.toString().padLeft(2, '0')}/${parsed.month.toString().padLeft(2, '0')}/${parsed.year}';
      }
    }

    if (savedPhoto.isNotEmpty) {
      _profilePhotoPath = savedPhoto;
    }

    if (mounted) {
      setState(() {});
    }
  }

  String _defaultBaseUsername() {
    final displayName = (widget.user.displayName ?? '').trim();
    final email = (widget.user.email ?? '').trim();
    final base = displayName.isNotEmpty
        ? displayName
        : (email.isNotEmpty ? email.split('@').first : 'sailor_user');
    return _service.normalizeForInput(base);
  }

  void _onUsernameChanged() {
    if (_usernameLocked) {
      return;
    }

    final normalized = _service.normalizeForInput(_usernameController.text);
    if (normalized != _usernameController.text) {
      final oldSelection = _usernameController.selection;
      _usernameController.value = TextEditingValue(
        text: normalized,
        selection: TextSelection.collapsed(
          offset: oldSelection.baseOffset.clamp(0, normalized.length),
        ),
      );
      return;
    }

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _checkAvailability);

    if (mounted) {
      setState(() {
        _normalizedPreview = normalized;
      });
    }
  }

  Future<void> _checkAvailability() async {
    if (_usernameLocked) {
      return;
    }

    final username = _usernameController.text.trim();
    if (!_service.isValidUsernameFormat(username)) {
      if (!mounted) {
        return;
      }
      setState(() {
        _checkingAvailability = false;
        _isAvailable = false;
        _availabilityMessage =
            'Use 3-24 chars: lowercase letters, numbers, dot or underscore.';
        _suggestions = const <String>[];
      });
      return;
    }

    setState(() {
      _checkingAvailability = true;
      _availabilityMessage = null;
      _suggestions = const <String>[];
    });

    try {
      final available = await _service.isUsernameAvailable(
        username,
        currentUserId: widget.user.uid,
      );
      final suggestions = await _service.generateSuggestions(
        username,
        currentUserId: widget.user.uid,
        max: 5,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _checkingAvailability = false;
        _isAvailable = available;
        _availabilityMessage = available
            ? '@$username is available.'
            : '@$username is already used.';
        _suggestions =
            suggestions.where((item) => item != username).take(4).toList();
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _checkingAvailability = false;
        _isAvailable = false;
        _availabilityMessage =
            'Could not check availability. Check internet and Supabase setup.';
        _suggestions = const <String>[];
      });
    }
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDob ?? DateTime(now.year - 18, now.month, now.day),
      firstDate: DateTime(1940),
      lastDate: DateTime(now.year - 10, now.month, now.day),
    );
    if (picked == null) {
      return;
    }

    setState(() {
      _selectedDob = picked;
      _dobController.text =
          '${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}';
    });
  }

  Future<void> _saveProfile() async {
    if (_saving) {
      return;
    }

    final username = _service.normalizeForInput(_usernameController.text);
    final phone = _phoneController.text.trim();

    if (!_service.isValidUsernameFormat(username)) {
      setState(() {
        _errorMessage =
            'Use 3-24 chars: lowercase letters, numbers, dot or underscore.';
      });
      return;
    }

    if (!_usernameLocked && !_isAvailable) {
      setState(() {
        _errorMessage = 'Choose an available username to continue.';
      });
      return;
    }

    if (_selectedDob == null) {
      setState(() {
        _errorMessage = 'Please select your date of birth.';
      });
      return;
    }

    if (!RegExp(r'^[0-9]{8,15}$').hasMatch(phone)) {
      setState(() {
        _errorMessage = 'Enter a valid phone number.';
      });
      return;
    }

    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    try {
      if (!_usernameLocked) {
        await _service.claimUsername(user: widget.user, rawUsername: username);
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'profile_dob_${widget.user.uid}',
        _selectedDob!.toIso8601String(),
      );
      await prefs.setString('profile_phone_${widget.user.uid}', phone);
      if ((_profilePhotoPath ?? '').trim().isNotEmpty) {
        await prefs.setString(
          'profile_photo_${widget.user.uid}',
          _profilePhotoPath!.trim(),
        );
      }

      // If the profile photo is still a local path (upload failed earlier),
      // retry the upload before saving the profile.
      var photoToSave = _profilePhotoPath?.trim() ?? '';
      if (photoToSave.isNotEmpty && !_isRemotePhoto(photoToSave)) {
        try {
          final retryUrl = await _service.uploadProfilePhoto(
            user: widget.user,
            localFilePath: photoToSave,
          );
          if ((retryUrl ?? '').trim().isNotEmpty) {
            photoToSave = retryUrl!.trim();
            if (mounted) {
              setState(() {
                _profilePhotoPath = photoToSave;
              });
            }
          }
        } catch (_) {
          // Upload failed – keep local path, don't block profile save.
        }
      }

      // Only write photo_path to Supabase when we have a remote URL.
      // Pass null when upload failed so upsertPublicProfile preserves any
      // existing remote URL instead of overwriting it with an empty string.
      await _service.upsertPublicProfile(
        user: widget.user,
        username: username,
        displayName: widget.user.displayName ?? username,
        phoneNumber: phone,
        photoPath: _isRemotePhoto(photoToSave) ? photoToSave : null,
        dateOfBirth: _selectedDob!.toIso8601String(),
      );

      if (!mounted) {
        return;
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => const EmergencyContactsSetupScreen(),
        ),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage =
            e.message ?? 'Could not save profile details right now.';
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      final message = e.toString().replaceFirst('Bad state: ', '').trim();
      setState(() {
        _errorMessage = message.isEmpty
            ? 'Could not save profile details. Please try again in a moment.'
            : message;
      });
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _pickProfilePhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose from gallery'),
                onTap: () =>
                    Navigator.of(sheetContext).pop(ImageSource.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Take a photo'),
                onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
              ),
            ],
          ),
        );
      },
    );

    if (source == null) {
      return;
    }

    final picked = await _imagePicker.pickImage(
      source: source,
      maxWidth: 1200,
      imageQuality: 85,
    );
    if (picked == null || !mounted) {
      return;
    }

    final appDirectory = await getApplicationDocumentsDirectory();
    final profileDirectory = Directory(
      path.join(appDirectory.path, 'profile_photos'),
    );
    await profileDirectory.create(recursive: true);
    final extension = path.extension(picked.path).toLowerCase();
    final safeExtension = extension.isEmpty
        ? '.jpg'
        : (extension.length > 5 ? '.jpg' : extension);
    final targetPath = path.join(
      profileDirectory.path,
      'profile_${widget.user.uid}$safeExtension',
    );
    final savedFile = await File(picked.path).copy(targetPath);

    var finalPath = savedFile.path;
    try {
      final uploadedUrl = await _service.uploadProfilePhoto(
        user: widget.user,
        localFilePath: savedFile.path,
      );
      if ((uploadedUrl ?? '').trim().isNotEmpty) {
        finalPath = uploadedUrl!.trim();
      }
    } catch (_) {
      // Upload failed – keep local path for now; will retry on save.
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _profilePhotoPath = finalPath;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          children: [
            const SizedBox(height: 10),
            Text(
              'Complete your profile',
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Set your username, date of birth, and phone number.',
              style: TextStyle(
                fontSize: 15,
                color:
                    isDark ? const Color(0xFFA3A3A3) : const Color(0xFF6B7280),
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 44,
                    backgroundColor: theme.colorScheme.primary
                        .withValues(alpha: isDark ? 0.2 : 0.12),
                    backgroundImage: _profileImageProvider(),
                    child: _profileImageProvider() == null
                        ? Icon(
                            Icons.person_outline,
                            color: theme.colorScheme.primary,
                            size: 34,
                          )
                        : null,
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: InkWell(
                      onTap: _pickProfilePhoto,
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isDark ? Colors.black : Colors.white,
                            width: 2,
                          ),
                        ),
                        child: const Icon(
                          Icons.camera_alt_outlined,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: TextButton(
                onPressed: _pickProfilePhoto,
                child: const Text('Add profile photo'),
              ),
            ),
            const SizedBox(height: 10),
            buildTextField(
              context: context,
              label: 'Username',
              hint: 'your_name',
              controller: _usernameController,
              readOnly: _usernameLocked,
              keyboardType: TextInputType.text,
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 14, right: 8),
                child: Center(
                  widthFactor: 1,
                  child: Text(
                    '@',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ),
              validator: (_) => null,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                if (_checkingAvailability)
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.colorScheme.primary,
                    ),
                  )
                else
                  Icon(
                    _isAvailable ? Icons.check_circle : Icons.info_outline,
                    size: 16,
                    color: _isAvailable
                        ? const Color(0xFF22C55E)
                        : (isDark
                            ? const Color(0xFFA3A3A3)
                            : const Color(0xFF6B7280)),
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _availabilityMessage ??
                        (_normalizedPreview.isEmpty
                            ? 'Type a username to check availability.'
                            : 'Checking @$_normalizedPreview...'),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _isAvailable
                          ? const Color(0xFF22C55E)
                          : (isDark
                              ? const Color(0xFFA3A3A3)
                              : const Color(0xFF6B7280)),
                    ),
                  ),
                ),
              ],
            ),
            if (_suggestions.isNotEmpty && !_usernameLocked) ...[
              const SizedBox(height: 14),
              Text(
                'Suggestions',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: isDark
                      ? const Color(0xFFA3A3A3)
                      : const Color(0xFF6B7280),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _suggestions
                    .map(
                      (username) => ActionChip(
                        label: Text('@$username'),
                        onPressed: () {
                          _usernameController.text = username;
                          _usernameController.selection =
                              TextSelection.collapsed(offset: username.length);
                        },
                      ),
                    )
                    .toList(),
              ),
            ],
            const SizedBox(height: 20),
            GestureDetector(
              onTap: _pickDob,
              child: AbsorbPointer(
                child: buildTextField(
                  context: context,
                  label: 'Date of birth',
                  hint: 'DD/MM/YYYY',
                  controller: _dobController,
                  keyboardType: TextInputType.datetime,
                  suffixIcon: Icon(Icons.calendar_today,
                      color: theme.colorScheme.onSurface),
                  validator: (_) => null,
                ),
              ),
            ),
            const SizedBox(height: 16),
            buildTextField(
              context: context,
              label: 'Phone number',
              hint: '9876543210',
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              validator: (_) => null,
            ),
            if ((_errorMessage ?? '').isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: const TextStyle(
                  color: Color(0xFFEF4444),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 24),
            buildButton(
              context: context,
              label: 'Continue',
              isLoading: _saving,
              onPressed: _saving || _checkingAvailability ? null : _saveProfile,
            ),
          ],
        ),
      ),
    );
  }
}
