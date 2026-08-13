import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import '../services/supabase_sync_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();

  bool _syncEnabled = false;
  String _syncStatusText = 'Logged Out';
  bool _isSynced = false;
  String _appSize = 'Calculating...';
  String _lastLogin = 'Never';
  String _lastSyncTime = 'Never';

  int _pendingUploads = 0;
  int _pendingDownloads = 0;

  bool _loadingCounts = false;
  String? _avatarPath;

  late final StreamSubscription<AuthState> _authSubscription;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadAppInfo();
    
    // Listen to Supabase auth state changes (ignoring initialSession to prevent recurring bind prompts)
    _authSubscription = SupabaseSyncService.instance.client.auth.onAuthStateChange.listen((data) async {
      final AuthChangeEvent event = data.event;
      final Session? session = data.session;
      
      if (session != null && event == AuthChangeEvent.signedIn) {
        if (!_syncEnabled) {
          setState(() {
            _syncEnabled = true;
          });
          await _handlePostLogin(session.user);
        }
      }
    });
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  // Load profile settings from file
  Future<void> _loadSettings() async {
    final settings = await SupabaseSyncService.instance.loadProfileSettings();
    setState(() {
      _nameController.text = settings['fullName'] ?? 'John Doe';
      _emailController.text = settings['email'] ?? 'john@example.com';
      _syncEnabled = settings['syncEnabled'] ?? false;
      _lastSyncTime = settings['lastSyncTime'] ?? 'Never';
      _avatarPath = settings['avatarPath'];
      
      if (SupabaseSyncService.instance.isLoggedIn) {
        _isSynced = true;
        _syncStatusText = 'Synced';
        final user = SupabaseSyncService.instance.currentUser;
        if (user != null) {
          _emailController.text = user.email ?? '';
        }
      } else {
        _isSynced = false;
        _syncStatusText = 'Logged Out';
        _syncEnabled = false; // Sync cannot be enabled if logged out
      }
    });
    
    if (SupabaseSyncService.instance.isLoggedIn) {
      _loadPendingCounts();
    }
  }

  // Load app details
  Future<void> _loadAppInfo() async {
    final sizeStr = await SupabaseSyncService.instance.getAppSizeString();
    
    // Get last login time from settings or current formatted date
    final settings = await SupabaseSyncService.instance.loadProfileSettings();
    String lastLoginStr = settings['lastLoginTime'] ?? '';
    if (lastLoginStr.isEmpty) {
      lastLoginStr = DateFormat('MMM d, yyyy').format(DateTime.now());
    }

    if (mounted) {
      setState(() {
        _appSize = sizeStr;
        _lastLogin = lastLoginStr;
      });
    }
  }

  // Load pending sync counts
  Future<void> _loadPendingCounts() async {
    if (!SupabaseSyncService.instance.isLoggedIn) return;
    setState(() => _loadingCounts = true);
    try {
      final counts = await SupabaseSyncService.instance.getPendingCounts();
      if (mounted) {
        setState(() {
          _pendingUploads = counts['uploads'] ?? 0;
          _pendingDownloads = counts['downloads'] ?? 0;
          _loadingCounts = false;
          
          if (_pendingUploads > 0 || _pendingDownloads > 0) {
            _isSynced = false;
            _syncStatusText = 'Unsynced';
          } else {
            _isSynced = true;
            _syncStatusText = 'Synced';
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loadingCounts = false);
      }
    }
  }

  // Post Login integration (Data binding / restore)
  Future<void> _handlePostLogin(User user) async {
    if (mounted) {
      setState(() {
        _emailController.text = user.email ?? '';
        _syncStatusText = 'Syncing...';
      });
    }

    try {
      final settings = await SupabaseSyncService.instance.loadProfileSettings();
      final hasCompletedInitialBind = settings['hasCompletedInitialBind'] ?? false;

      if (hasCompletedInitialBind) {
        // Run sync automatically in the background
        await SupabaseSyncService.instance.syncAll();
      } else {
        // First-time sign-in: check if there's local data and prompt
        final hasLocal = await SupabaseSyncService.instance.hasLocalData();
        if (hasLocal) {
          if (mounted) {
            final bind = await showDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder: (context) => AlertDialog(
                backgroundColor: AppTheme.cream,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                title: const Text(
                  'Bind Local Data?',
                  style: TextStyle(color: AppTheme.navy, fontWeight: FontWeight.bold),
                ),
                content: const Text(
                  'We found existing database records on this device. Would you like to merge and bind this local data to your Google Account?\n\nSelecting "No" will overwrite local data and restore your existing online backup.',
                  style: TextStyle(color: AppTheme.textDark),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('No, Restore Backup', style: TextStyle(color: AppTheme.red, fontWeight: FontWeight.bold)),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.yellow,
                      foregroundColor: AppTheme.navy,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Yes, Bind & Merge', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            );

            if (bind == true) {
              await SupabaseSyncService.instance.syncAll();
            } else {
              await SupabaseSyncService.instance.downloadRestore();
            }
          }
        } else {
          await SupabaseSyncService.instance.downloadRestore();
        }
      }

      // Save settings with syncEnabled and hasCompletedInitialBind set to true
      final updatedSettings = await SupabaseSyncService.instance.loadProfileSettings();
      updatedSettings['syncEnabled'] = true;
      updatedSettings['hasCompletedInitialBind'] = true;
      updatedSettings['fullName'] = _nameController.text;
      updatedSettings['email'] = _emailController.text;
      updatedSettings['lastSyncTime'] = DateTime.now().toLocal().toString().substring(0, 16);
      await SupabaseSyncService.instance.saveProfileSettings(updatedSettings);

      if (mounted) {
        setState(() {
          _isSynced = true;
          _syncStatusText = 'Synced';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Supabase sync activated and data restored!'),
            backgroundColor: AppTheme.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('Post login sync error: $e');
      if (mounted) {
        setState(() {
          _syncStatusText = 'Sync Error';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync error: $e'),
            backgroundColor: AppTheme.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
    _loadPendingCounts();
  }

  // Toggle Sync Option
  void _onSyncToggled(bool value) async {
    if (value) {
      if (!SupabaseSyncService.instance.isLoggedIn) {
        // Must login first
        setState(() => _syncEnabled = false);
        _startGoogleLogin();
      } else {
        // Already logged in, just enable
        setState(() => _syncEnabled = true);
        final settings = await SupabaseSyncService.instance.loadProfileSettings();
        settings['syncEnabled'] = true;
        await SupabaseSyncService.instance.saveProfileSettings(settings);
        await SupabaseSyncService.instance.syncAll();
        _loadPendingCounts();
      }
    } else {
      // Disable Sync (Prompt for logout)
      final confirmLogout = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppTheme.cream,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Disable Sync?',
            style: TextStyle(color: AppTheme.navy, fontWeight: FontWeight.bold),
          ),
          content: const Text(
            'This will sign you out and stop online backups. Your local records will remain safe on this device.',
            style: TextStyle(color: AppTheme.textDark),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel', style: TextStyle(color: AppTheme.navy, fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.red,
                foregroundColor: AppTheme.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Sign Out & Disable', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );

      if (confirmLogout == true) {
        // Show loading
        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => const Center(
              child: Card(
                color: AppTheme.cream,
                child: Padding(
                  padding: EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: AppTheme.navy),
                      SizedBox(height: 16),
                      Text(
                        'Syncing data before logout...',
                        style: TextStyle(color: AppTheme.navy, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        try {
          await SupabaseSyncService.instance.logout();
        } catch (e) {
          debugPrint('Logout sync error: $e');
        }

        // Close loading dialog
        if (mounted) {
          Navigator.pop(context);
        }

        setState(() {
          _syncEnabled = false;
          _isSynced = false;
          _syncStatusText = 'Logged Out';
          _pendingUploads = 0;
          _pendingDownloads = 0;
          _emailController.text = 'john@example.com';
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Offline sync disabled and logged out.'),
              backgroundColor: AppTheme.navy,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        setState(() {
          _syncEnabled = true;
        });
      }
    }
  }

  // Open Edit Name Dialog
  void _editFullName() async {
    final nameCtrl = TextEditingController(text: _nameController.text);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.cream,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Edit Full Name',
          style: TextStyle(color: AppTheme.navy, fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(
            hintText: 'Enter your full name',
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.navy)),
          ),
          style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textDark),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textGrey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, nameCtrl.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.yellow,
              foregroundColor: AppTheme.navy,
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && mounted) {
      setState(() {
        _nameController.text = newName;
      });
      await _saveChanges();
    }
  }

  // Open Edit Email Dialog (only when logged out)
  void _editEmailAddress() async {
    if (SupabaseSyncService.instance.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Email address is bound to Google Account and cannot be edited.'),
          backgroundColor: AppTheme.navy,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final emailCtrl = TextEditingController(text: _emailController.text);
    final newEmail = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.cream,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Edit Email Address',
          style: TextStyle(color: AppTheme.navy, fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: emailCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            hintText: 'Enter your email address',
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.navy)),
          ),
          style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textDark),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textGrey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, emailCtrl.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.yellow,
              foregroundColor: AppTheme.navy,
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newEmail != null && newEmail.isNotEmpty && mounted) {
      setState(() {
        _emailController.text = newEmail;
      });
      await _saveChanges();
    }
  }

  // Save changes locally and to Supabase
  Future<void> _saveChanges() async {
    final settings = await SupabaseSyncService.instance.loadProfileSettings();
    settings['fullName'] = _nameController.text.trim();
    settings['email'] = _emailController.text.trim();
    settings['syncEnabled'] = _syncEnabled;
    await SupabaseSyncService.instance.saveProfileSettings(settings);

    try {
      if (SupabaseSyncService.instance.isLoggedIn) {
        // Update user metadata in Supabase
        await SupabaseSyncService.instance.client.auth.updateUser(
          UserAttributes(data: {'full_name': _nameController.text.trim()}),
        );
        // Trigger smart sync
        await SupabaseSyncService.instance.syncAll();
        
        final updatedSettings = await SupabaseSyncService.instance.loadProfileSettings();
        setState(() {
          _lastSyncTime = updatedSettings['lastSyncTime'] ?? 'Never';
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Changes saved successfully!'),
            backgroundColor: AppTheme.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving changes: $e'),
            backgroundColor: AppTheme.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }

    _loadPendingCounts();
  }

  // Pick profile image from gallery
  Future<void> _pickProfileImage() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
      
      if (image != null) {
        // Copy the image file to documents directory to persist it
        final docDir = await getApplicationDocumentsDirectory();
        final fileName = 'profile_avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final savedFile = File('${docDir.path}/$fileName');
        await File(image.path).copy(savedFile.path);

        // Delete old avatar if it exists
        if (_avatarPath != null && _avatarPath!.isNotEmpty) {
          final oldFile = File(_avatarPath!);
          if (await oldFile.exists()) {
            await oldFile.delete();
          }
        }

        setState(() {
          _avatarPath = savedFile.path;
        });

        // Save to settings
        final settings = await SupabaseSyncService.instance.loadProfileSettings();
        settings['avatarPath'] = savedFile.path;
        await SupabaseSyncService.instance.saveProfileSettings(settings);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Profile picture updated successfully!'),
              backgroundColor: AppTheme.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error picking profile image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to pick image: $e'),
            backgroundColor: AppTheme.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // Trigger Google Browser OAuth Sign-in
  void _startGoogleLogin() async {
    setState(() {
      _syncStatusText = 'Signing in...';
    });
    try {
      final success = await SupabaseSyncService.instance.signInWithGoogle();
      if (!success && mounted) {
        setState(() {
          _syncStatusText = 'Logged Out';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to trigger Google Sign-In'),
            backgroundColor: AppTheme.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _syncStatusText = 'Logged Out';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Google Sign-In error: $e'),
            backgroundColor: AppTheme.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Widget _buildInfoRow(String label, String value, {Widget? trailingWidget}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            color: AppTheme.textGrey,
            fontWeight: FontWeight.w500,
          ),
        ),
        trailingWidget ??
            Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                color: AppTheme.navy,
                fontWeight: FontWeight.bold,
              ),
            ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLoggedIn = SupabaseSyncService.instance.isLoggedIn;

    return Scaffold(
      backgroundColor: AppTheme.cream,
      appBar: AppBar(
        backgroundColor: AppTheme.cream,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.navy),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Profile',
          style: TextStyle(
            color: AppTheme.navy,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Avatar and user info subtitle
                    Center(
                      child: Column(
                        children: [
                          GestureDetector(
                            onTap: _pickProfileImage,
                            child: Stack(
                              children: [
                                Container(
                                  width: 90,
                                  height: 90,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFE2DDD5),
                                    shape: BoxShape.circle,
                                  ),
                                  child: _avatarPath != null && _avatarPath!.isNotEmpty && File(_avatarPath!).existsSync()
                                      ? ClipRRect(
                                          borderRadius: BorderRadius.circular(45),
                                          child: Image.file(
                                            File(_avatarPath!),
                                            width: 90,
                                            height: 90,
                                            fit: BoxFit.cover,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.person,
                                          size: 48,
                                          color: AppTheme.navy,
                                        ),
                                ),
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Container(
                                    width: 30,
                                    height: 30,
                                    decoration: const BoxDecoration(
                                      color: AppTheme.navy,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.edit,
                                      size: 14,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Manage your account settings and preferences',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.textGrey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),

                    // User Details grouped box
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.black12, width: 1.0),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            title: const Text(
                              'FULL NAME',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textGrey, letterSpacing: 0.5),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4.0),
                              child: Text(
                                _nameController.text,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.navy),
                              ),
                            ),
                            trailing: const Icon(Icons.chevron_right, color: Colors.black26),
                            onTap: _editFullName,
                          ),
                          const Divider(height: 1, color: Colors.black12),
                          ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            title: const Text(
                              'EMAIL ADDRESS',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textGrey, letterSpacing: 0.5),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4.0),
                              child: Text(
                                _emailController.text,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.navy),
                              ),
                            ),
                            trailing: const Icon(Icons.chevron_right, color: Colors.black26),
                            onTap: _editEmailAddress,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Database Sync Card
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.black12, width: 1.0),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE2DDD5),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.sync,
                              color: AppTheme.navy,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Database Sync',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.navy,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Automatic cloud backup',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textGrey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: _syncEnabled,
                            onChanged: _onSyncToggled,
                            activeThumbColor: AppTheme.white,
                            activeTrackColor: AppTheme.navy,
                            inactiveThumbColor: AppTheme.textGrey,
                            inactiveTrackColor: const Color(0xFFE2DDD5),
                          ),
                        ],
                      ),
                    ),
                    if (_syncEnabled && (_pendingUploads > 0 || _pendingDownloads > 0)) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0, left: 4.0),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline, size: 14, color: AppTheme.orange),
                            const SizedBox(width: 6),
                            Text(
                              'Unsynced Changes: $_pendingUploads uploads, $_pendingDownloads downloads',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.orange,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 28),

                    // APP METADATA Section
                    const Text(
                      'APP METADATA',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textGrey,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.black12, width: 1.0),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Column(
                        children: [
                          _buildInfoRow('Storage Used', _appSize),
                          const Divider(height: 24, color: Colors.black12),
                          _buildInfoRow('Last Session', _lastLogin),
                          const Divider(height: 24, color: Colors.black12),
                          _buildInfoRow('Last Sync', _lastSyncTime),
                          const Divider(height: 24, color: Colors.black12),
                          _buildInfoRow(
                            'Status',
                            _syncStatusText,
                            trailingWidget: _loadingCounts
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.navy),
                                  )
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        _isSynced ? Icons.check_circle : Icons.info_outline,
                                        color: _isSynced ? AppTheme.navy : AppTheme.orange,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        _syncStatusText,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.navy,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            // Continue with Google Button (only if not logged in)
            if (!isLoggedIn)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _startGoogleLogin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.navy,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.login, color: Colors.white, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Continue with Google',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
