import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../database/database_helper.dart';
import '../theme/app_theme.dart';
import '../services/auth_service.dart';
import '../services/supabase_sync_service.dart';
import '../widgets/vault_toast.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _nameController = TextEditingController(text: 'Angelica Melli');
  final _emailController = TextEditingController(text: 'sampleuser@gmail.com');

  bool _syncEnabled = true;
  String _syncStatusText = 'Synced';
  bool _isSynced = true;
  String _appSize = '1.2 GB';
  String _lastSession = 'Today, 8:43 PM';
  String _lastSyncTime = 'Never';

  String? _avatarPath;
  String? _coverPhotoPath;

  bool _isLockEnabled = false;
  bool _isBiometricsEnabled = false;
  bool _deviceHasBiometrics = false;

  bool _showSettingsPanel = false;

  late final StreamSubscription<AuthState> _authSubscription;

  @override
  void initState() {
    super.initState();
    _loadProfileData();
    _loadAppInfo();

    SupabaseSyncService.instance.syncStatusNotifier.addListener(_updateSyncStatusFromNotifier);

    _authSubscription = SupabaseSyncService.instance.client.auth.onAuthStateChange.listen((data) async {
      final AuthChangeEvent event = data.event;
      final Session? session = data.session;

      if (session != null && event == AuthChangeEvent.signedIn) {
        if (!_syncEnabled) {
          setState(() {
            _syncEnabled = true;
          });
        }
        await _handlePostLogin(session.user);
      }
    });
  }

  @override
  void dispose() {
    SupabaseSyncService.instance.syncStatusNotifier.removeListener(_updateSyncStatusFromNotifier);
    _authSubscription.cancel();
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _updateSyncStatusFromNotifier() {
    if (!mounted) return;
    final status = SupabaseSyncService.instance.syncStatusNotifier.value;
    final isLoggedIn = SupabaseSyncService.instance.isLoggedIn;

    setState(() {
      if (!isLoggedIn) {
        _isSynced = false;
        _syncStatusText = 'NOT SYNC';
      } else {
        switch (status) {
          case SyncStatus.syncing:
            _isSynced = false;
            _syncStatusText = 'Syncing...';
            break;
          case SyncStatus.synced:
          case SyncStatus.idle:
          case SyncStatus.error:
            _isSynced = true;
            _syncStatusText = 'Synced';
            break;
        }
      }
    });
  }

  // ── Load Profile Data (Dual Source: Local + Online Cloud Photos) ──
  Future<void> _loadProfileData() async {
    final settings = await SupabaseSyncService.instance.loadProfileSettings();

    String name = settings['fullName'] ?? '';
    String email = settings['email'] ?? '';
    bool sync = settings['syncEnabled'] ?? false;
    String? avatar = settings['avatarPath'];
    String? cover = settings['coverPhotoPath'];
    String lastSync = settings['lastSyncTime'] ?? 'Never';

    bool isLock = settings['isLockEnabled'] ?? false;
    bool isBio = settings['isBiometricsEnabled'] ?? false;
    bool hasBio = false;
    try {
      hasBio = await AuthService.canAuthenticate();
    } catch (_) {}

    // If logged in to Supabase, sync online metadata & restore cloud photos
    if (SupabaseSyncService.instance.isLoggedIn) {
      final user = SupabaseSyncService.instance.currentUser;
      if (user != null) {
        if (user.email != null && user.email!.isNotEmpty) {
          email = user.email!;
        }
        final metadata = user.userMetadata;
        if (metadata != null) {
          if (metadata['full_name'] != null && metadata['full_name'].toString().isNotEmpty) {
            name = metadata['full_name'];
          }
          // Restore Avatar from cloud base64 if missing locally
          if (metadata['avatar_base64'] != null && metadata['avatar_base64'].toString().isNotEmpty) {
            try {
              final docDir = await getApplicationDocumentsDirectory();
              final restoredAvatar = File('${docDir.path}/profile_avatar.jpg');
              if (!restoredAvatar.existsSync() || avatar == null || !File(avatar).existsSync()) {
                final decodedBytes = base64Decode(metadata['avatar_base64']);
                await restoredAvatar.writeAsBytes(decodedBytes);
                avatar = restoredAvatar.path;
                settings['avatarPath'] = avatar;
                await SupabaseSyncService.instance.saveProfileSettings(settings);
              }
            } catch (e) {
              debugPrint('Error restoring cloud avatar: $e');
            }
          }
          // Restore Cover Photo from cloud base64 if missing locally
          if (metadata['cover_base64'] != null && metadata['cover_base64'].toString().isNotEmpty) {
            try {
              final docDir = await getApplicationDocumentsDirectory();
              final restoredCover = File('${docDir.path}/profile_cover.jpg');
              if (!restoredCover.existsSync() || cover == null || !File(cover).existsSync()) {
                final decodedBytes = base64Decode(metadata['cover_base64']);
                await restoredCover.writeAsBytes(decodedBytes);
                cover = restoredCover.path;
                settings['coverPhotoPath'] = cover;
                await SupabaseSyncService.instance.saveProfileSettings(settings);
              }
            } catch (e) {
              debugPrint('Error restoring cloud cover: $e');
            }
          }
        }
      }
      final syncStatus = SupabaseSyncService.instance.syncStatusNotifier.value;
      if (syncStatus == SyncStatus.syncing) {
        _isSynced = false;
        _syncStatusText = 'Syncing...';
      } else {
        _isSynced = true;
        _syncStatusText = 'Synced';
      }
    } else {
      _isSynced = false;
      _syncStatusText = 'NOT SYNC';
      if (lastSync == '5 mins ago' || lastSync.isEmpty) {
        lastSync = 'Never';
      }
    }

    if (mounted) {
      setState(() {
        _nameController.text = name;
        _emailController.text = email;
        _syncEnabled = sync;
        _avatarPath = avatar;
        _coverPhotoPath = cover;
        _lastSyncTime = lastSync;
        _isLockEnabled = isLock;
        _isBiometricsEnabled = isBio;
        _deviceHasBiometrics = hasBio;
      });
    }
  }

  Future<void> _handlePostLogin(User user) async {
    final settings = await SupabaseSyncService.instance.loadProfileSettings();
    settings['syncEnabled'] = true;
    if (user.email != null && user.email!.isNotEmpty) {
      settings['email'] = user.email!;
    }
    final metadata = user.userMetadata;
    if (metadata != null && metadata['full_name'] != null && metadata['full_name'].toString().isNotEmpty) {
      settings['fullName'] = metadata['full_name'];
    }
    await SupabaseSyncService.instance.saveProfileSettings(settings);

    if (mounted) {
      setState(() {
        _syncStatusText = 'Fetching Cloud Data...';
        _isSynced = false;
      });
      VaultToast.showInfo(context, 'Syncing all records with Cloud...', title: 'Syncing');
    }

    try {
      await SupabaseSyncService.instance.syncAll(showToast: true);
    } catch (e) {
      debugPrint('Post login sync error: $e');
    }
    if (!mounted) return;
    await _loadProfileData();
  }

  Future<void> _loadAppInfo() async {
    final sizeStr = await SupabaseSyncService.instance.getAppSizeString();
    final now = DateTime.now();
    final sessionStr = 'Today, ${DateFormat('h:mm a').format(now)}';

    if (mounted) {
      setState(() {
        _appSize = sizeStr;
        _lastSession = sessionStr;
      });
    }
  }

  // ── Save Profile Changes (Dual Persistence: Local & Online) ──
  Future<void> _saveProfileChanges({String? newName, String? newEmail, String? newAvatarPath}) async {
    final nameToSave = (newName ?? _nameController.text).trim();
    final emailToSave = (newEmail ?? _emailController.text).trim();
    final avatarToSave = newAvatarPath ?? _avatarPath;

    // 1. Save Locally
    final settings = await SupabaseSyncService.instance.loadProfileSettings();
    settings['fullName'] = nameToSave;
    settings['email'] = emailToSave;
    if (avatarToSave != null) settings['avatarPath'] = avatarToSave;
    if (_coverPhotoPath != null) settings['coverPhotoPath'] = _coverPhotoPath;
    settings['syncEnabled'] = _syncEnabled;
    await SupabaseSyncService.instance.saveProfileSettings(settings);

    // 2. Save Online to Supabase (User Metadata & Profiles table)
    try {
      if (SupabaseSyncService.instance.isLoggedIn) {
        final client = SupabaseSyncService.instance.client;
        final Map<String, dynamic> updateData = {
          'full_name': nameToSave,
        };
        if (settings['avatarBase64'] != null) {
          updateData['avatar_base64'] = settings['avatarBase64'];
        }
        if (settings['coverBase64'] != null) {
          updateData['cover_base64'] = settings['coverBase64'];
        }

        await client.auth.updateUser(
          UserAttributes(
            data: updateData,
          ),
        );

        final user = client.auth.currentUser;
        if (user != null) {
          await client.from('profiles').upsert({
            'id': user.id,
            'full_name': nameToSave,
            'email': emailToSave,
            'updated_at': DateTime.now().toIso8601String(),
          }).catchError((_) {});
        }
      }
    } catch (e) {
      debugPrint('Error updating user profile online: $e');
    }

    if (mounted) {
      setState(() {
        _nameController.text = nameToSave;
        _emailController.text = emailToSave;
        _avatarPath = avatarToSave;
        _lastSyncTime = DateFormat('MMM d, yyyy • h:mm a').format(DateTime.now());
        _isSynced = true;
        _syncStatusText = 'Synced';
      });

      VaultToast.showSuccess(context, 'Profile updated & synced to Cloud!');
    }
  }

  // ── Pick Avatar Image ──
  Future<void> _pickAvatarImage() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
        maxWidth: 512,
        maxHeight: 512,
      );

      if (image != null) {
        final bytes = await File(image.path).readAsBytes();
        final docDir = await getApplicationDocumentsDirectory();
        final savedFile = File('${docDir.path}/profile_avatar.jpg');
        await savedFile.writeAsBytes(bytes);
        final base64Str = base64Encode(bytes);

        final settings = await SupabaseSyncService.instance.loadProfileSettings();
        settings['avatarPath'] = savedFile.path;
        settings['avatarBase64'] = base64Str;
        await SupabaseSyncService.instance.saveProfileSettings(settings);

        if (SupabaseSyncService.instance.isLoggedIn) {
          try {
            await SupabaseSyncService.instance.client.auth.updateUser(
              UserAttributes(
                data: {
                  'avatar_base64': base64Str,
                },
              ),
            );
          } catch (e) {
            debugPrint('Cloud avatar upload error: $e');
          }
        }

        if (mounted) {
          setState(() {
            _avatarPath = savedFile.path;
          });
          VaultToast.showSuccess(context, 'Profile photo saved & synced!');
        }
      }
    } catch (e) {
      if (mounted) {
        VaultToast.showError(context, 'Failed to update picture: $e');
      }
    }
  }

  // ── Pick Cover Photo ──
  Future<void> _pickCoverImage() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
        maxWidth: 1024,
        maxHeight: 600,
      );

      if (image != null) {
        final bytes = await File(image.path).readAsBytes();
        final docDir = await getApplicationDocumentsDirectory();
        final savedFile = File('${docDir.path}/profile_cover.jpg');
        await savedFile.writeAsBytes(bytes);
        final base64Str = base64Encode(bytes);

        final settings = await SupabaseSyncService.instance.loadProfileSettings();
        settings['coverPhotoPath'] = savedFile.path;
        settings['coverBase64'] = base64Str;
        await SupabaseSyncService.instance.saveProfileSettings(settings);

        if (SupabaseSyncService.instance.isLoggedIn) {
          try {
            await SupabaseSyncService.instance.client.auth.updateUser(
              UserAttributes(
                data: {
                  'cover_base64': base64Str,
                },
              ),
            );
          } catch (e) {
            debugPrint('Cloud cover upload error: $e');
          }
        }

        if (mounted) {
          setState(() {
            _coverPhotoPath = savedFile.path;
          });
          VaultToast.showSuccess(context, 'Cover photo saved & synced!');
        }
      }
    } catch (e) {
      if (mounted) {
        VaultToast.showError(context, 'Failed to update cover photo: $e');
      }
    }
  }

  // ── Remove Cover Photo ──
  Future<void> _removeCoverPhoto() async {
    final docDir = await getApplicationDocumentsDirectory();
    final file = File('${docDir.path}/profile_cover.jpg');
    if (file.existsSync()) {
      try {
        await file.delete();
      } catch (_) {}
    }

    final settings = await SupabaseSyncService.instance.loadProfileSettings();
    settings['coverPhotoPath'] = null;
    settings['coverBase64'] = null;
    await SupabaseSyncService.instance.saveProfileSettings(settings);

    if (SupabaseSyncService.instance.isLoggedIn) {
      try {
        await SupabaseSyncService.instance.client.auth.updateUser(
          UserAttributes(
            data: {
              'cover_base64': '',
            },
          ),
        );
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _coverPhotoPath = null;
      });
      VaultToast.showInfo(context, 'Cover photo removed.');
    }
  }

  // ── Show Cover Photo Options ──
  void _showCoverPhotoOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Cover Photo',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark,
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFC68A0E).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.photo_library_rounded, color: Color(0xFFC68A0E)),
                ),
                title: const Text('Upload Cover Photo', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Choose a picture from your gallery'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickCoverImage();
                },
              ),
              if (_coverPhotoPath != null && _coverPhotoPath!.isNotEmpty) ...[
                const Divider(),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.red.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.delete_outline_rounded, color: AppTheme.red),
                  ),
                  title: const Text('Remove Cover Photo', style: TextStyle(color: AppTheme.red, fontWeight: FontWeight.w600)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _removeCoverPhoto();
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Edit Name Dialog ──
  void _editFullName() async {
    final nameCtrl = TextEditingController(text: _nameController.text);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Edit Profile Name',
          style: TextStyle(color: AppTheme.textDark, fontWeight: FontWeight.w900, fontSize: 18),
        ),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textDark, fontSize: 16),
          decoration: InputDecoration(
            hintText: 'Enter your full name',
            filled: true,
            fillColor: const Color(0xFFF6F4EE),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, nameCtrl.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFC68A0E),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty) {
      await _saveProfileChanges(newName: newName);
    }
  }

  // ── Edit Email Dialog ──
  void _editEmail() async {
    final emailCtrl = TextEditingController(text: _emailController.text);
    final newEmail = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Edit Email Address',
          style: TextStyle(color: AppTheme.textDark, fontWeight: FontWeight.w900, fontSize: 18),
        ),
        content: TextField(
          controller: emailCtrl,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textDark, fontSize: 16),
          decoration: InputDecoration(
            hintText: 'Enter email address',
            filled: true,
            fillColor: const Color(0xFFF6F4EE),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, emailCtrl.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFC68A0E),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (newEmail != null && newEmail.isNotEmpty) {
      await _saveProfileChanges(newEmail: newEmail);
    }
  }

  // ── Change Password Dialog (For Lockscreen) ──
  // ── Change Master Password Dialog ──
  void _showChangePasswordDialog() async {
    final settings = await SupabaseSyncService.instance.loadProfileSettings();
    final currentSavedPassword = settings['lockPassword'] ?? 'julius';

    final currentPassCtrl = TextEditingController();
    final newPassCtrl = TextEditingController();
    final confirmPassCtrl = TextEditingController();

    bool obscureCurrent = true;
    bool obscureNew = true;
    bool obscureConfirm = true;

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.16),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Centered Icon Badge
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: const Color(0xFFC68A0E).withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.lock_reset_rounded, color: Color(0xFFC68A0E), size: 28),
                  ),
                  const SizedBox(height: 14),

                  const Text(
                    'Change Master Password',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.textDark,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Enter your current master password to set a new one.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B), height: 1.35),
                  ),
                  const SizedBox(height: 20),

                  // Current Password Input
                  TextField(
                    controller: currentPassCtrl,
                    obscureText: obscureCurrent,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textDark),
                    decoration: InputDecoration(
                      hintText: 'Current Password',
                      hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                      prefixIcon: const Icon(Icons.key_rounded, size: 18, color: Color(0xFFC68A0E)),
                      suffixIcon: IconButton(
                        icon: Icon(obscureCurrent ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18, color: const Color(0xFF94A3B8)),
                        onPressed: () => setModalState(() => obscureCurrent = !obscureCurrent),
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF8F7F4),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFC68A0E), width: 1.8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // New Password Input
                  TextField(
                    controller: newPassCtrl,
                    obscureText: obscureNew,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textDark),
                    decoration: InputDecoration(
                      hintText: 'New Master Password',
                      hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                      prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18, color: Color(0xFFC68A0E)),
                      suffixIcon: IconButton(
                        icon: Icon(obscureNew ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18, color: const Color(0xFF94A3B8)),
                        onPressed: () => setModalState(() => obscureNew = !obscureNew),
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF8F7F4),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFC68A0E), width: 1.8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Confirm New Password Input
                  TextField(
                    controller: confirmPassCtrl,
                    obscureText: obscureConfirm,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textDark),
                    decoration: InputDecoration(
                      hintText: 'Confirm New Password',
                      hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                      prefixIcon: const Icon(Icons.check_circle_outline_rounded, size: 18, color: Color(0xFFC68A0E)),
                      suffixIcon: IconButton(
                        icon: Icon(obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18, color: const Color(0xFF94A3B8)),
                        onPressed: () => setModalState(() => obscureConfirm = !obscureConfirm),
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF8F7F4),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFC68A0E), width: 1.8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Action Buttons
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () async {
                        if (currentPassCtrl.text != currentSavedPassword) {
                          VaultToast.showError(context, 'Incorrect current password!');
                          return;
                        }
                        if (newPassCtrl.text.trim().isEmpty) {
                          VaultToast.showError(context, 'New password cannot be empty.');
                          return;
                        }
                        if (newPassCtrl.text != confirmPassCtrl.text) {
                          VaultToast.showError(context, 'New passwords do not match.');
                          return;
                        }

                        settings['lockPassword'] = newPassCtrl.text.trim();
                        await SupabaseSyncService.instance.saveProfileSettings(settings);

                        if (ctx.mounted) {
                          Navigator.of(ctx).pop();
                        }
                        if (mounted) {
                          VaultToast.showSuccess(context, 'Master password updated successfully!');
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFC68A0E),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text(
                        'Save Password',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Change 4-Digit PIN Dialog ──
  void _showChangePinDialog() async {
    final settings = await SupabaseSyncService.instance.loadProfileSettings();
    final currentSavedPin = settings['paymentPin'] ?? '1234';

    final currentPinCtrl = TextEditingController();
    final newPinCtrl = TextEditingController();
    final confirmPinCtrl = TextEditingController();

    bool obscureCurrent = true;
    bool obscureNew = true;
    bool obscureConfirm = true;

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.16),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Centered Icon Badge
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: const Color(0xFFC68A0E).withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.pin_rounded, color: Color(0xFFC68A0E), size: 28),
                  ),
                  const SizedBox(height: 14),

                  const Text(
                    'Change 4-Digit PIN',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.textDark,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Update the 4-digit PIN used for quick unlocking and confirming borrower payments.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B), height: 1.35),
                  ),
                  const SizedBox(height: 20),

                  // Current PIN Input
                  TextField(
                    controller: currentPinCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    obscureText: obscureCurrent,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppTheme.textDark, letterSpacing: 4),
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: 'Current 4-Digit PIN',
                      hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13, letterSpacing: 0),
                      prefixIcon: const Icon(Icons.key_rounded, size: 18, color: Color(0xFFC68A0E)),
                      suffixIcon: IconButton(
                        icon: Icon(obscureCurrent ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18, color: const Color(0xFF94A3B8)),
                        onPressed: () => setModalState(() => obscureCurrent = !obscureCurrent),
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF8F7F4),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFC68A0E), width: 1.8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // New PIN Input
                  TextField(
                    controller: newPinCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    obscureText: obscureNew,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppTheme.textDark, letterSpacing: 4),
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: 'New 4-Digit PIN',
                      hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13, letterSpacing: 0),
                      prefixIcon: const Icon(Icons.pin_rounded, size: 18, color: Color(0xFFC68A0E)),
                      suffixIcon: IconButton(
                        icon: Icon(obscureNew ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18, color: const Color(0xFF94A3B8)),
                        onPressed: () => setModalState(() => obscureNew = !obscureNew),
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF8F7F4),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFC68A0E), width: 1.8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Confirm PIN Input
                  TextField(
                    controller: confirmPinCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    obscureText: obscureConfirm,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppTheme.textDark, letterSpacing: 4),
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: 'Confirm New PIN',
                      hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13, letterSpacing: 0),
                      prefixIcon: const Icon(Icons.check_circle_outline_rounded, size: 18, color: Color(0xFFC68A0E)),
                      suffixIcon: IconButton(
                        icon: Icon(obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18, color: const Color(0xFF94A3B8)),
                        onPressed: () => setModalState(() => obscureConfirm = !obscureConfirm),
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF8F7F4),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFC68A0E), width: 1.8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Action Buttons
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () async {
                        if (currentPinCtrl.text != currentSavedPin) {
                          VaultToast.showError(context, 'Incorrect current PIN!');
                          return;
                        }
                        if (newPinCtrl.text.trim().length != 4) {
                          VaultToast.showError(context, 'PIN must be exactly 4 digits.');
                          return;
                        }
                        if (newPinCtrl.text != confirmPinCtrl.text) {
                          VaultToast.showError(context, 'PINs do not match.');
                          return;
                        }

                        settings['paymentPin'] = newPinCtrl.text.trim();
                        await SupabaseSyncService.instance.saveProfileSettings(settings);

                        if (ctx.mounted) {
                          Navigator.of(ctx).pop();
                        }
                        if (mounted) {
                          VaultToast.showSuccess(context, '4-Digit PIN updated successfully!');
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFC68A0E),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text(
                        'Save PIN',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── App Lock Toggle & Setup Dialogs ──
  void _toggleAppLock(bool enable) {
    if (enable) {
      _showEnableLockDialog();
    } else {
      _showDisableLockDialog();
    }
  }

  void _showEnableLockDialog() {
    final passCtrl = TextEditingController();
    final confirmPassCtrl = TextEditingController();
    final pinCtrl = TextEditingController();
    final confirmPinCtrl = TextEditingController();

    bool obscurePass = true;
    bool obscureConfirmPass = true;
    bool obscurePin = true;
    bool obscureConfirmPin = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.16),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Centered Header Badge
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: const Color(0xFFC68A0E).withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.shield_outlined, color: Color(0xFFC68A0E), size: 28),
                  ),
                  const SizedBox(height: 14),

                  const Text(
                    'Set Password & PIN',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.textDark,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Set a Master Password and 4-Digit PIN to protect your vault. You can use either one to unlock.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B), height: 1.35),
                  ),
                  const SizedBox(height: 20),

                  // Section A: Master Password
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFAF9F6),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFEBE8E0), width: 1.0),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.password_rounded, size: 16, color: Color(0xFFC68A0E)),
                            SizedBox(width: 6),
                            Text(
                              'MASTER PASSWORD',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFF64748B), letterSpacing: 0.6),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: passCtrl,
                          obscureText: obscurePass,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textDark),
                          decoration: InputDecoration(
                            hintText: 'Enter master password',
                            hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                            prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18, color: Color(0xFFC68A0E)),
                            suffixIcon: IconButton(
                              icon: Icon(obscurePass ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18, color: const Color(0xFF94A3B8)),
                              onPressed: () => setModalState(() => obscurePass = !obscurePass),
                            ),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFC68A0E), width: 1.8)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: confirmPassCtrl,
                          obscureText: obscureConfirmPass,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textDark),
                          decoration: InputDecoration(
                            hintText: 'Confirm master password',
                            hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                            prefixIcon: const Icon(Icons.check_circle_outline_rounded, size: 18, color: Color(0xFFC68A0E)),
                            suffixIcon: IconButton(
                              icon: Icon(obscureConfirmPass ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18, color: const Color(0xFF94A3B8)),
                              onPressed: () => setModalState(() => obscureConfirmPass = !obscureConfirmPass),
                            ),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFC68A0E), width: 1.8)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Section B: 4-Digit PIN
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFAF9F6),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFEBE8E0), width: 1.0),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.pin_rounded, size: 16, color: Color(0xFFC68A0E)),
                            SizedBox(width: 6),
                            Text(
                              '4-DIGIT PIN',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFF64748B), letterSpacing: 0.6),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: pinCtrl,
                          keyboardType: TextInputType.number,
                          maxLength: 4,
                          obscureText: obscurePin,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppTheme.textDark, letterSpacing: 4),
                          decoration: InputDecoration(
                            counterText: '',
                            hintText: 'Enter 4-digit PIN',
                            hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13, letterSpacing: 0),
                            prefixIcon: const Icon(Icons.pin_rounded, size: 18, color: Color(0xFFC68A0E)),
                            suffixIcon: IconButton(
                              icon: Icon(obscurePin ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18, color: const Color(0xFF94A3B8)),
                              onPressed: () => setModalState(() => obscurePin = !obscurePin),
                            ),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFC68A0E), width: 1.8)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: confirmPinCtrl,
                          keyboardType: TextInputType.number,
                          maxLength: 4,
                          obscureText: obscureConfirmPin,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppTheme.textDark, letterSpacing: 4),
                          decoration: InputDecoration(
                            counterText: '',
                            hintText: 'Confirm 4-digit PIN',
                            hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13, letterSpacing: 0),
                            prefixIcon: const Icon(Icons.check_circle_outline_rounded, size: 18, color: Color(0xFFC68A0E)),
                            suffixIcon: IconButton(
                              icon: Icon(obscureConfirmPin ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18, color: const Color(0xFF94A3B8)),
                              onPressed: () => setModalState(() => obscureConfirmPin = !obscureConfirmPin),
                            ),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFC68A0E), width: 1.8)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Action Buttons
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () async {
                        if (passCtrl.text.trim().isEmpty) {
                          VaultToast.showError(context, 'Please enter a master password.');
                          return;
                        }
                        if (passCtrl.text != confirmPassCtrl.text) {
                          VaultToast.showError(context, 'Passwords do not match.');
                          return;
                        }
                        if (pinCtrl.text.trim().length != 4) {
                          VaultToast.showError(context, 'PIN must be exactly 4 digits.');
                          return;
                        }
                        if (pinCtrl.text != confirmPinCtrl.text) {
                          VaultToast.showError(context, 'PINs do not match.');
                          return;
                        }

                        final settings = await SupabaseSyncService.instance.loadProfileSettings();
                        settings['isLockEnabled'] = true;
                        settings['lockPassword'] = passCtrl.text.trim();
                        settings['paymentPin'] = pinCtrl.text.trim();
                        await SupabaseSyncService.instance.saveProfileSettings(settings);

                        if (mounted) {
                          setState(() {
                            _isLockEnabled = true;
                          });
                        }

                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                        }
                        if (mounted) {
                          VaultToast.showSuccess(context, 'App lock enabled with password & PIN!');
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFC68A0E),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text(
                        'Enable App Lock',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showDisableLockDialog() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.16),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Red/Amber Warning Icon Badge
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.lock_open_rounded, color: Color(0xFFEF4444), size: 28),
              ),
              const SizedBox(height: 14),

              const Text(
                'Disable App Lock?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.textDark,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'If disabled, startup login and password checks will be bypassed, opening directly into your dashboard.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Color(0xFF64748B), height: 1.35),
              ),
              const SizedBox(height: 24),

              // Turn Off Lock Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () async {
                    final settings = await SupabaseSyncService.instance.loadProfileSettings();
                    settings['isLockEnabled'] = false;
                    settings['isBiometricsEnabled'] = false;
                    await SupabaseSyncService.instance.saveProfileSettings(settings);

                    if (mounted) {
                      setState(() {
                        _isLockEnabled = false;
                        _isBiometricsEnabled = false;
                      });
                    }

                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                    }
                    if (mounted) {
                      VaultToast.showSuccess(context, 'App lock disabled. Startup login bypassed.');
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEF4444),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('Turn Off Lock', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Keep Locked', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _toggleBiometrics(bool enable) async {
    if (enable) {
      if (!_isLockEnabled) {
        VaultToast.showError(context, 'Please enable App Lock first before turning on biometrics.');
        return;
      }
      if (!_deviceHasBiometrics) {
        VaultToast.showError(context, 'No biometric hardware found or enrolled on this device.');
        return;
      }

      final authenticated = await AuthService.authenticate(reason: 'Verify biometric identity');
      if (authenticated) {
        final settings = await SupabaseSyncService.instance.loadProfileSettings();
        settings['isBiometricsEnabled'] = true;
        await SupabaseSyncService.instance.saveProfileSettings(settings);
        if (mounted) {
          setState(() {
            _isBiometricsEnabled = true;
          });
          VaultToast.showSuccess(context, 'Biometrics enabled for instant unlock!');
        }
      }
    } else {
      final settings = await SupabaseSyncService.instance.loadProfileSettings();
      settings['isBiometricsEnabled'] = false;
      await SupabaseSyncService.instance.saveProfileSettings(settings);
      if (mounted) {
        setState(() {
          _isBiometricsEnabled = false;
        });
        VaultToast.showSuccess(context, 'Biometric unlock disabled.');
      }
    }
  }

  // ── Import / Export Database Tools ──
  Future<void> _exportBackup() async {
    try {
      final dbPath = await DatabaseHelper.instance.getDatabasePath();
      final file = File(dbPath);
      if (await file.exists()) {
        await Share.shareXFiles(
          [XFile(dbPath, name: 'anda_vault_backup.db')],
          subject: 'ANDA Database Backup',
        );
      }
    } catch (e) {
      if (mounted) {
        VaultToast.showError(context, 'Failed to export backup: $e');
      }
    }
  }

  Future<void> _importBackup() async {
    try {
      final result = await FilePicker.platform.pickFiles();
      if (result != null && result.files.single.path != null) {
        final success = await DatabaseHelper.instance.importDatabase(result.files.single.path!);
        if (mounted) {
          if (success) {
            VaultToast.showSuccess(context, 'Database imported successfully!');
          } else {
            VaultToast.showError(context, 'Failed to import database file.');
          }
        }
      }
    } catch (e) {
      if (mounted) {
        VaultToast.showError(context, 'Import error: $e');
      }
    }
  }

  // ── Google Login Flow ──
  Future<void> _startGoogleLogin() async {
    setState(() {
      _syncStatusText = 'Signing in...';
    });
    try {
      final success = await SupabaseSyncService.instance.signInWithGoogle();
      if (!success && mounted) {
        setState(() {
          _syncStatusText = 'Logged Out';
        });
        VaultToast.showError(context, 'Failed to trigger Google Sign-In');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _syncStatusText = 'Logged Out';
        });
        VaultToast.showError(context, 'Google Sign-In error: $e');
      }
    }
  }

  // ── Logout ──
  Future<void> _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Logout', style: TextStyle(color: AppTheme.textDark, fontWeight: FontWeight.w900)),
        content: const Text('Are you sure you want to log out? Local data will remain saved on this device.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B)))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFC68A0E), foregroundColor: Colors.white),
            child: const Text('Logout', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await SupabaseSyncService.instance.logout();
      if (mounted) {
        setState(() {
          _syncEnabled = false;
          _isSynced = false;
          _syncStatusText = 'Logged Out';
        });
        VaultToast.showSuccess(context, 'Logged out successfully.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // ── Scrollable Profile Content ──
          SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 100),
            child: Column(
              children: [
                // ── Top Header Banner with Curved Bottom & Cover Photo ──
                Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.topCenter,
                  children: [
                    // Header Background (Custom Cover Photo OR Curved Lavender Gradient)
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(44)),
                      child: Container(
                        height: 220,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          gradient: _coverPhotoPath != null &&
                                  _coverPhotoPath!.isNotEmpty &&
                                  File(_coverPhotoPath!).existsSync()
                              ? null
                              : const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFFE8EEFF),
                                    Color(0xFFEFE8FE),
                                    Color(0xFFE6E8FF),
                                  ],
                                ),
                        ),
                        child: _coverPhotoPath != null &&
                                _coverPhotoPath!.isNotEmpty &&
                                File(_coverPhotoPath!).existsSync()
                            ? Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.file(
                                    File(_coverPhotoPath!),
                                    fit: BoxFit.cover,
                                  ),
                                  Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Colors.black.withValues(alpha: 0.45),
                                          Colors.transparent,
                                          Colors.black.withValues(alpha: 0.60),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : null,
                      ),
                    ),

                    // Top Bar with Back, Title & Settings
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            if (Navigator.canPop(context))
                              GestureDetector(
                                onTap: () => Navigator.pop(context),
                                child: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 6)],
                                  ),
                                  child: const Icon(Icons.chevron_left, color: AppTheme.textDark, size: 24),
                                ),
                              )
                            else
                              const SizedBox(width: 40),
                            Text(
                              'Profile',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: _coverPhotoPath != null &&
                                        _coverPhotoPath!.isNotEmpty &&
                                        File(_coverPhotoPath!).existsSync()
                                    ? Colors.white
                                    : AppTheme.textDark,
                                shadows: _coverPhotoPath != null &&
                                        _coverPhotoPath!.isNotEmpty &&
                                        File(_coverPhotoPath!).existsSync()
                                    ? [const BoxShadow(color: Colors.black45, blurRadius: 8)]
                                    : null,
                              ),
                            ),
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _showSettingsPanel = !_showSettingsPanel;
                                });
                              },
                              child: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: _showSettingsPanel ? const Color(0xFFC68A0E) : Colors.white,
                                  shape: BoxShape.circle,
                                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
                                ),
                                child: AnimatedRotation(
                                  turns: _showSettingsPanel ? 0.5 : 0.0,
                                  duration: const Duration(milliseconds: 350),
                                  curve: Curves.easeInOutCubic,
                                  child: Icon(
                                    Icons.settings_outlined,
                                    color: _showSettingsPanel ? Colors.white : AppTheme.textDark,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Edit / Add Cover Photo Action Button (Bottom Right of Banner)
                    Positioned(
                      right: 20,
                      bottom: 12,
                      child: GestureDetector(
                        onTap: _showCoverPhotoOptions,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.50),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.4),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 13),
                              const SizedBox(width: 4),
                              Text(
                                _coverPhotoPath != null &&
                                        _coverPhotoPath!.isNotEmpty &&
                                        File(_coverPhotoPath!).existsSync()
                                    ? 'Edit Cover'
                                    : 'Add Cover',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Center Large Circular Avatar (Overlapping)
                    Positioned(
                      bottom: -46,
                      child: GestureDetector(
                        onTap: _pickAvatarImage,
                        child: Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                            border: Border.all(color: Colors.white, width: 4),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.14),
                                blurRadius: 18,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(48),
                            child: _avatarPath != null && _avatarPath!.isNotEmpty && File(_avatarPath!).existsSync()
                                ? Image.file(File(_avatarPath!), fit: BoxFit.cover)
                                : Container(
                                    color: const Color(0xFF3B4371),
                                    child: const Icon(Icons.person, size: 54, color: Colors.white),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 56),

                // ── Name & Email (Live Tap-to-Edit & Persist) ──
                GestureDetector(
                  onTap: _editFullName,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _nameController.text.trim().isNotEmpty
                            ? _nameController.text.trim()
                            : 'Set Name',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: _nameController.text.trim().isNotEmpty
                              ? AppTheme.textDark
                              : const Color(0xFF94A3B8),
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.edit_outlined, size: 16, color: Color(0xFF64748B)),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: _editEmail,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _emailController.text.trim().isNotEmpty
                            ? _emailController.text.trim()
                            : 'Tap to add email',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: _emailController.text.trim().isNotEmpty
                              ? const Color(0xFF64748B)
                              : const Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 28),

                // ── Sections Body ──
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── 1. App Data Section ──
                      const Text(
                        'App Data',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.textDark,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildDataRow('Storage use', _appSize),
                      const SizedBox(height: 10),
                      _buildDataRow('Last session', _lastSession),
                      const SizedBox(height: 10),
                      _buildDataRow('Last sync', _lastSyncTime),
                      const SizedBox(height: 10),
                      _buildStatusRow('Status', _syncStatusText, _isSynced),

                      const SizedBox(height: 28),

                      // ── 2. Security Section ──
                      const Text(
                        'Security & Access',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.textDark,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildSwitchTile(
                        icon: Icons.lock_outline_rounded,
                        title: 'App Lock / Login Panel',
                        subtitle: _isLockEnabled
                            ? 'Protected with password & PIN'
                            : 'Disabled (Startup login bypassed)',
                        value: _isLockEnabled,
                        onChanged: _toggleAppLock,
                      ),
                      const SizedBox(height: 8),
                      _buildSwitchTile(
                        icon: Icons.fingerprint_rounded,
                        title: 'Biometric Unlock',
                        subtitle: _isLockEnabled
                            ? (_isBiometricsEnabled ? 'Active (Fingerprint / Face ID)' : 'Disabled')
                            : 'Enable App Lock first',
                        value: _isBiometricsEnabled,
                        isEnabled: _isLockEnabled,
                        onChanged: _toggleBiometrics,
                      ),
                      if (_isLockEnabled) ...[
                        const SizedBox(height: 12),
                        _buildActionTile(
                          leadingIcon: Icons.lock_reset_rounded,
                          title: 'Change Master Password',
                          onTap: _showChangePasswordDialog,
                        ),
                        const SizedBox(height: 10),
                        _buildActionTile(
                          leadingIcon: Icons.pin_rounded,
                          title: 'Change 4-Digit PIN',
                          onTap: _showChangePinDialog,
                        ),
                      ],

                      const SizedBox(height: 36),

                      // ── 4. Bottom Dynamic Action Button (Logout vs Login to Google) ──
                      Builder(
                        builder: (context) {
                          final isLoggedIn = SupabaseSyncService.instance.isLoggedIn;
                          return SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton(
                              onPressed: isLoggedIn ? _handleLogout : _startGoogleLogin,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFC68A0E),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (!isLoggedIn) ...[
                                    const Icon(Icons.login, size: 20),
                                    const SizedBox(width: 8),
                                  ],
                                  Text(
                                    isLoggedIn ? 'Logout' : 'Login to Google',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 36),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Backdrop Dismiss Area (when settings is open) ──
          if (_showSettingsPanel)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _showSettingsPanel = false),
                child: Container(
                  color: Colors.black.withValues(alpha: 0.25),
                ),
              ),
            ),

          // ── Floating Settings Dropdown Overlay on Top of the Design ──
          if (_showSettingsPanel)
            Positioned(
              top: MediaQuery.of(context).padding.top + 56,
              left: 20,
              right: 20,
              child: Material(
                elevation: 16,
                borderRadius: BorderRadius.circular(22),
                shadowColor: Colors.black.withValues(alpha: 0.25),
                color: Colors.white,
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: const Color(0xFFE2E8F0),
                      width: 1.2,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'CLOUD & SYNC',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF94A3B8),
                              letterSpacing: 0.8,
                            ),
                          ),
                          GestureDetector(
                            onTap: () => setState(() => _showSettingsPanel = false),
                            child: const Padding(
                              padding: EdgeInsets.all(2.0),
                              child: Icon(Icons.close_rounded, size: 18, color: Color(0xFF94A3B8)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.sync_rounded, size: 20, color: Color(0xFF0F172A)),
                              SizedBox(width: 8),
                              Text(
                                'Database sync',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                            ],
                          ),
                          Switch(
                            value: _syncEnabled,
                            activeTrackColor: const Color(0xFF22C55E),
                            activeThumbColor: Colors.white,
                            inactiveThumbColor: const Color(0xFF94A3B8),
                            inactiveTrackColor: const Color(0xFFE2E8F0),
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            onChanged: (val) async {
                              setState(() => _syncEnabled = val);
                              final settings = await SupabaseSyncService.instance.loadProfileSettings();
                              settings['syncEnabled'] = val;
                              await SupabaseSyncService.instance.saveProfileSettings(settings);

                              if (val) {
                                if (!SupabaseSyncService.instance.isLoggedIn) {
                                  await _startGoogleLogin();
                                } else {
                                  await SupabaseSyncService.instance.syncAll();
                                  _loadProfileData();
                                }
                              } else {
                                _loadProfileData();
                              }
                            },
                          ),
                        ],
                      ),
                      const Divider(height: 22, color: Color(0xFFF1F5F9)),
                      const Text(
                        'DATABASE TOOLS',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF94A3B8),
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildActionTile(
                        leadingIcon: Icons.upload_file_rounded,
                        title: 'Import Data',
                        onTap: () {
                          setState(() => _showSettingsPanel = false);
                          _importBackup();
                        },
                      ),
                      const SizedBox(height: 8),
                      _buildActionTile(
                        leadingIcon: Icons.file_download_rounded,
                        title: 'Export Backup',
                        onTap: () {
                          setState(() => _showSettingsPanel = false);
                          _exportBackup();
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool isEnabled = true,
  }) {
    return Opacity(
      opacity: isEnabled ? 1.0 : 0.45,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFC68A0E).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: const Color(0xFFC68A0E), size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textDark,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: value,
              activeTrackColor: const Color(0xFF22C55E),
              activeThumbColor: Colors.white,
              inactiveThumbColor: const Color(0xFF94A3B8),
              inactiveTrackColor: const Color(0xFFE2E8F0),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: isEnabled ? onChanged : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDataRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Color(0xFF64748B),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            color: AppTheme.textDark,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusRow(String label, String status, bool isSynced) {
    final bool isSyncInProgress = status.contains('Syncing') || status.contains('Fetching');
    final statusColor = isSyncInProgress
        ? const Color(0xFFC68A0E)
        : (isSynced ? const Color(0xFF22C55E) : const Color(0xFFEF4444));

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Color(0xFF64748B),
          ),
        ),
        Row(
          children: [
            if (isSyncInProgress) ...[
              const SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFC68A0E)),
              ),
              const SizedBox(width: 6),
            ] else ...[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              status,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: isSyncInProgress
                    ? const Color(0xFFC68A0E)
                    : (isSynced ? AppTheme.textDark : const Color(0xFFEF4444)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionTile({
    IconData? leadingIcon,
    required String title,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                if (leadingIcon != null) ...[
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFC68A0E).withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(leadingIcon, color: const Color(0xFFC68A0E), size: 18),
                  ),
                  const SizedBox(width: 12),
                ],
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textDark,
                  ),
                ),
              ],
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: Color(0xFF94A3B8),
            ),
          ],
        ),
      ),
    );
  }
}
