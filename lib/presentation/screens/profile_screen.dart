import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/config/app_constants.dart';
import '../../core/network/api_client.dart';
import '../../core/services/app_update_service.dart';
import '../../core/theme/app_theme.dart';
import '../../data/datasources/offline_database_helper.dart';
import '../../data/datasources/scanner_local_storage.dart';
import '../../data/models/user_profile_model.dart';
import '../../data/repositories/auth_repository.dart';
import '../bloc/auth/auth_bloc.dart';
import '../bloc/auth/auth_event.dart';
import '../bloc/scanner_bloc.dart';
import '../bloc/scanner_state.dart';
import '../widgets/app_background_layer.dart';
import 'auth/change_password_screen.dart';
import 'auth/login_screen.dart';
import 'offline/offline_sessions_screen.dart';
import 'qr_blacklist_screen.dart';
import 'settings_screen.dart';

/// Profile screen matching the React Native EventXPro Organiser Profile screen.
/// Includes:
/// - Organizer user profile card (photo, name, email, phone, role)
/// - Settings tile (opens dedicated SettingsScreen)
/// - QR Blacklist tile
/// - Offline Sessions tile
/// - System update check
/// - Log out action
class ProfileScreen extends StatefulWidget {
  final bool isRootTab;
  final VoidCallback? onOpenScanLead;

  const ProfileScreen({
    super.key,
    this.isRootTab = false,
    this.onOpenScanLead,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isOfflineMode = false;
  int _unsyncedCount = 0;

  UserProfileModel? _userProfile;
  bool _isLoadingProfile = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadProfile();
  }

  Future<void> _loadSettings() async {
    final storage = context.read<ScannerLocalStorage>();
    final db = context.read<OfflineDatabaseHelper>();

    final unsynced = await db.getUnsyncedCount();

    if (mounted) {
      setState(() {
        _isOfflineMode = storage.isOfflineModeEnabled;
        _unsyncedCount = unsynced;
      });
    }
  }

  /// Loads organizer user profile from 'organizer/user-profile' (matching React Native useProfile)
  Future<void> _loadProfile({bool forceRefresh = false}) async {
    final authRepo = context.read<AuthRepository>();

    // 1. Immediately display cached profile synchronously
    final cached = authRepo.cachedUserProfile;
    if (cached != null && _userProfile == null) {
      if (mounted) {
        setState(() {
          _userProfile = cached;
        });
      }
    }

    if (forceRefresh ||
        _userProfile == null ||
        _userProfile?.email.isEmpty == true) {
      if (mounted) {
        setState(() {
          _isLoadingProfile = true;
        });
      }

      try {
        final profile = await authRepo.getUserProfile(
          forceRefresh: forceRefresh,
        );
        if (mounted) {
          setState(() {
            _userProfile = profile;
            _isLoadingProfile = false;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _isLoadingProfile = false;
          });
        }
      }
    }
  }

  String? _resolveAvatarUrl(String? photo, String mediaUrl) {
    if (photo == null || photo.trim().isEmpty) return null;
    final cleanPhoto = photo.trim();
    if (cleanPhoto.startsWith('http://') || cleanPhoto.startsWith('https://')) {
      return cleanPhoto;
    }
    final cleanMedia = mediaUrl.endsWith('/')
        ? mediaUrl.substring(0, mediaUrl.length - 1)
        : mediaUrl;
    final cleanPath = cleanPhoto.startsWith('/') ? cleanPhoto : '/$cleanPhoto';
    return '$cleanMedia$cleanPath';
  }

  void _confirmLogout() {
    _showConfirmDialog(
      title: 'Log Out',
      message: 'Are you sure you want to log out of your EventXPro account?',
      isDestructive: true,
      onConfirm: () {
        context.read<AuthBloc>().add(const LogoutRequested());
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      },
    );
  }

  Future<void> _showConfirmDialog({
    required String title,
    required String message,
    required VoidCallback onConfirm,
    bool isDestructive = false,
  }) async {
    return showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppTheme.surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.surfaceBorder),
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          message,
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 14,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppTheme.textMuted),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isDestructive
                  ? const Color(0xFFFF6767)
                  : AppTheme.accentIndigo,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () {
              Navigator.of(dialogCtx).pop();
              onConfirm();
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  Future<(int, String)> _resolveCurrentEvent() async {
    final storage = context.read<ScannerLocalStorage>();
    int eventId = storage.getEventId();
    String eventName = 'Event #$eventId';
    final offlineData = storage.getOfflineData();
    if (offlineData != null && offlineData.isNotEmpty) {
      try {
        final map = jsonDecode(offlineData) as Map<String, dynamic>;
        final ev = map['event'] as Map<String, dynamic>?;
        if (ev != null) {
          eventId =
              (ev['pk'] as num?)?.toInt() ??
              (ev['id'] as num?)?.toInt() ??
              eventId;
          eventName = ev['publish_event_name']?.toString() ?? eventName;
        }
      } catch (_) {}
    }

    if (eventId == 1) {
      try {
        final apiClient = context.read<ApiClient>();
        final dashRes = await apiClient.dio.get('organizer/dashboard');
        if (dashRes.statusCode == 200 && dashRes.data != null) {
          final data = dashRes.data is Map
              ? dashRes.data as Map<String, dynamic>
              : jsonDecode(dashRes.data.toString()) as Map<String, dynamic>;
          final rawEvents = data['event_list'] as List<dynamic>? ?? [];
          if (rawEvents.isNotEmpty) {
            final firstEvt = rawEvents.first as Map<String, dynamic>;
            final pk =
                (firstEvt['pk'] as num?)?.toInt() ??
                (firstEvt['id'] as num?)?.toInt() ??
                int.tryParse(firstEvt['pk']?.toString() ?? '') ??
                int.tryParse(firstEvt['id']?.toString() ?? '');
            if (pk != null) {
              eventId = pk;
              eventName =
                  firstEvt['publish_event_name']?.toString() ?? eventName;
              await storage.setEventId(pk);
            }
          }
        }
      } catch (_) {}
    }
    return (eventId, eventName);
  }

  @override
  Widget build(BuildContext context) {
    final authRepo = context.read<AuthRepository>();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        elevation: 0,
        centerTitle: false,
        automaticallyImplyLeading: false,
        leading: widget.isRootTab
            ? null
            : IconButton(
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                onPressed: () => Navigator.of(context).pop(),
              ),
        title: const Text(
          'Profile',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.3,
          ),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(color: AppTheme.surfaceBorder, height: 1),
        ),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const AppBackgroundLayer(),
          RefreshIndicator(
            color: AppTheme.accentIndigo,
            backgroundColor: AppTheme.surfaceElevated,
            onRefresh: () async {
              await Future.wait([
                _loadSettings(),
                _loadProfile(forceRefresh: true),
              ]);
            },
            child: BlocBuilder<ScannerBloc, ScannerState>(
              builder: (context, state) {
                return ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    // ── Section 1: Organizer Profile (organizer/user-profile) ──
                    _buildProfileCard(authRepo),

                    const SizedBox(height: 14),

                    _buildSettingsTile(),

                    if (!_isOfflineMode) ...[
                      const SizedBox(height: 10),
                      _buildQrBlacklistTile(),
                    ],

                    const SizedBox(height: 10),

                    _buildOfflineSessionsTile(),

                    if (!_isOfflineMode) ...[
                      const SizedBox(height: 10),
                      _buildChangePasswordTile(),
                    ],

                    const SizedBox(height: 10),

                    _buildCheckUpdateTile(),

                    const SizedBox(height: 10),

                    _buildLogoutTile(),

                    _buildVersionFooter(),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileCard(AuthRepository authRepo) {
    final profile = _userProfile;
    final name = (profile != null && profile.name.trim().isNotEmpty)
        ? profile.name.trim()
        : 'Organizer';
    final username = (profile != null && profile.username.trim().isNotEmpty)
        ? profile.username.trim()
        : '';
    final email = profile?.email.trim() ?? '';
    final phone = profile?.phone.trim() ?? '';
    final isAdmin = profile?.isAdmin ?? false;
    final photoUrl = _resolveAvatarUrl(profile?.photo, authRepo.mediaUrl);
    final initials = profile?.initials ?? 'P';

    return _buildGlassCard(
      borderRadius: BorderRadius.circular(16),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppTheme.accentIndigo.withValues(alpha: 0.6),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.accentIndigo.withValues(alpha: 0.25),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: photoUrl != null
                      ? Image.network(
                          photoUrl,
                          fit: BoxFit.cover,
                          width: 56,
                          height: 56,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return _buildInitialsAvatar(initials);
                          },
                          errorBuilder: (context, error, stackTrace) {
                            return _buildInitialsAvatar(initials);
                          },
                        )
                      : _buildInitialsAvatar(initials),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isAdmin) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.accentIndigo.withValues(
                                alpha: 0.18,
                              ),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: AppTheme.accentIndigo.withValues(
                                  alpha: 0.6,
                                ),
                                width: 0.8,
                              ),
                            ),
                            child: const Text(
                              'ADMIN',
                              style: TextStyle(
                                color: AppTheme.accentIndigo,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (username.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        '@$username',
                        style: const TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (_isLoadingProfile)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.accentIndigo,
                  ),
                )
              else
                IconButton(
                  tooltip: 'Refresh profile',
                  icon: const Icon(
                    Icons.refresh_rounded,
                    color: AppTheme.textMuted,
                    size: 20,
                  ),
                  onPressed: () => _loadProfile(forceRefresh: true),
                ),
            ],
          ),

          if (email.isNotEmpty || phone.isNotEmpty) ...[
            const SizedBox(height: 14),
            Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
            const SizedBox(height: 12),
            if (email.isNotEmpty)
              _buildProfileDetailRow(
                icon: Icons.email_outlined,
                iconColor: AppTheme.accentCyan,
                label: 'Email',
                value: email,
              ),
            if (phone.isNotEmpty) ...[
              if (email.isNotEmpty) const SizedBox(height: 8),
              _buildProfileDetailRow(
                icon: Icons.phone_outlined,
                iconColor: AppTheme.statusSuccess,
                label: 'Phone',
                value: phone,
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildSettingsTile() {
    return _buildGlassCard(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        leading: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: AppTheme.accentIndigo.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.settings_rounded,
            color: AppTheme.accentIndigo,
            size: 22,
          ),
        ),
        title: const Text(
          'Settings',
          style: TextStyle(
            color: Colors.white,
            fontSize: 15.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
        trailing: const Icon(
          Icons.arrow_forward_ios_rounded,
          color: AppTheme.textMuted,
          size: 14,
        ),
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SettingsScreen()),
          );
          if (mounted) {
            _loadSettings();
          }
        },
      ),
    );
  }

  Widget _buildQrBlacklistTile() {
    return _buildGlassCard(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        leading: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: AppTheme.accentIndigo.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.block_rounded,
            color: AppTheme.accentIndigo,
            size: 22,
          ),
        ),
        title: const Text(
          'QR Blacklist',
          style: TextStyle(
            color: Colors.white,
            fontSize: 15.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
        trailing: const Icon(
          Icons.arrow_forward_ios_rounded,
          color: AppTheme.textMuted,
          size: 14,
        ),
        onTap: () async {
          final (eventId, eventName) = await _resolveCurrentEvent();
          if (!mounted) return;
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  QrBlacklistScreen(eventId: eventId, eventName: eventName),
            ),
          );
        },
      ),
    );
  }

  Widget _buildOfflineSessionsTile() {
    return _buildGlassCard(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        leading: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: AppTheme.accentIndigo.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.inventory_2_outlined,
            color: AppTheme.accentIndigo,
            size: 22,
          ),
        ),
        title: const Text(
          'Offline Sessions',
          style: TextStyle(
            color: Colors.white,
            fontSize: 15.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_unsyncedCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.accentOrange.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.accentOrange),
                ),
                child: Text(
                  '$_unsyncedCount pending',
                  style: const TextStyle(
                    color: AppTheme.accentOrange,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            const SizedBox(width: 8),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              color: AppTheme.textMuted,
              size: 14,
            ),
          ],
        ),
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const OfflineSessionsScreen()),
          );
          _loadSettings();
        },
      ),
    );
  }

  Widget _buildChangePasswordTile() {
    return _buildGlassCard(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        leading: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: AppTheme.accentIndigo.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.lock_outline_rounded,
            color: AppTheme.accentIndigo,
            size: 22,
          ),
        ),
        title: const Text(
          'Change Password',
          style: TextStyle(
            color: Colors.white,
            fontSize: 15.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
        trailing: const Icon(
          Icons.arrow_forward_ios_rounded,
          color: AppTheme.textMuted,
          size: 14,
        ),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ChangePasswordScreen()),
          );
        },
      ),
    );
  }

  Widget _buildCheckUpdateTile() {
    return _buildGlassCard(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        leading: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: AppTheme.accentIndigo.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.system_update_rounded,
            color: AppTheme.accentIndigo,
            size: 22,
          ),
        ),
        title: const Text(
          'Check for Updates',
          style: TextStyle(
            color: Colors.white,
            fontSize: 15.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
        trailing: const Icon(
          Icons.arrow_forward_ios_rounded,
          color: AppTheme.textMuted,
          size: 14,
        ),
        onTap: () async {
          await AppUpdateService().checkAndPromptUpdate(
            context,
            showLatestToast: true,
          );
        },
      ),
    );
  }

  Widget _buildLogoutTile() {
    return _buildGlassCard(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        leading: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: const Color(0xFFEF5350).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.logout_rounded,
            color: Color(0xFFEF5350),
            size: 22,
          ),
        ),
        title: const Text(
          'Log Out',
          style: TextStyle(
            color: Colors.white,
            fontSize: 15.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
        trailing: const Icon(
          Icons.arrow_forward_ios_rounded,
          color: AppTheme.textMuted,
          size: 14,
        ),
        onTap: _confirmLogout,
      ),
    );
  }

  Widget _buildVersionFooter() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Column(
          children: [
            Text(
              'EventXPro Organiser • ${AppConstants.appVersion}',
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Connected to EventXPro Access Control',
              style: TextStyle(color: Color(0xFF4A4B56), fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInitialsAvatar(String initials) {
    return Container(
      color: AppTheme.accentIndigo,
      child: Center(
        child: Text(
          initials,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
      ),
    );
  }

  Widget _buildProfileDetailRow({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, color: iconColor, size: 14),
        ),
        const SizedBox(width: 10),
        Text(
          '$label: ',
          style: const TextStyle(
            color: AppTheme.textMuted,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildGlassCard({
    required Widget child,
    BorderRadius? borderRadius,
    EdgeInsetsGeometry? padding,
    Border? border,
  }) {
    final radius = borderRadius ?? BorderRadius.circular(14);
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: radius,
            border:
                border ??
                Border.all(
                  color: Colors.white.withValues(alpha: 0.12),
                  width: 1,
                ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}
