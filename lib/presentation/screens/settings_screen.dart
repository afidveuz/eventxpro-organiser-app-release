import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/config/app_constants.dart';
import '../../core/network/api_client.dart';
import '../../core/services/app_update_service.dart';
import '../../core/services/audio_feedback_service.dart';
import '../../core/services/device_detection_service.dart';
import '../../core/theme/app_theme.dart';
import '../../data/datasources/offline_database_helper.dart';
import '../../data/datasources/scanner_local_storage.dart';
import '../../data/models/user_profile_model.dart';
import '../../data/repositories/auth_repository.dart';
import '../bloc/auth/auth_bloc.dart';
import '../bloc/auth/auth_event.dart';
import '../bloc/scanner_bloc.dart';
import '../bloc/scanner_event.dart';
import '../bloc/scanner_state.dart';
import 'auth/login_screen.dart';
import 'offline/offline_sessions_screen.dart';

/// Settings screen matching the React Native EventXPro Organiser Settings screen.
/// Includes:
/// - Top-level tickets toggle with confirmation
/// - Short toast toggle with confirmation
/// - Offline mode toggle with confirmation & online permission sync
/// - Offline Sessions navigation entry
/// - Gate and device hardware settings
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isTopLevelTickets = false;
  bool _isShortToast = false;
  bool _isOfflineMode = false;
  bool _isSyncingData = false;
  int _unsyncedCount = 0;
  DeviceInfoResult? _deviceInfo;

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
    final info = await DeviceDetectionService().detectDevice(storage: storage);

    if (mounted) {
      setState(() {
        _isTopLevelTickets = storage.isTopLevelTicketsEnabled;
        _isShortToast = storage.isShortToastEnabled;
        _isOfflineMode = storage.isOfflineModeEnabled;
        _unsyncedCount = unsynced;
        _deviceInfo = info;
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

    if (forceRefresh || _userProfile == null || _userProfile?.email.isEmpty == true) {
      if (mounted) {
        setState(() {
          _isLoadingProfile = true;
        });
      }

      try {
        final profile = await authRepo.getUserProfile(forceRefresh: forceRefresh);
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
              backgroundColor: isDestructive ? const Color(0xFFFF6767) : AppTheme.accentIndigo,
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

  Future<void> _toggleTopLevelTickets() async {
    final nextState = !_isTopLevelTickets;
    _showConfirmDialog(
      title: nextState ? 'Enable Top-Level Tickets' : 'Disable Top-Level Tickets',
      message: nextState
          ? 'Are you sure you want to enable top-level tickets for scanner admittance?'
          : 'Are you sure you want to disable top-level tickets?',
      onConfirm: () async {
        final storage = context.read<ScannerLocalStorage>();
        await storage.setTopLevelTickets(nextState);
        setState(() {
          _isTopLevelTickets = nextState;
        });
      },
    );
  }

  Future<void> _toggleShortToast() async {
    final nextState = !_isShortToast;
    _showConfirmDialog(
      title: nextState ? 'Enable Short Toast' : 'Disable Short Toast',
      message: nextState
          ? 'Enable short toast for rush periods? This keeps the scanner live for continuous rapid scanning and shows brief top notifications.'
          : 'Disable short toast? This will display the full attendee profile card after every scan.',
      onConfirm: () async {
        final storage = context.read<ScannerLocalStorage>();
        await storage.setShortToast(nextState);
        setState(() {
          _isShortToast = nextState;
        });
      },
    );
  }

  Future<void> _toggleOfflineMode() async {
    final nextState = !_isOfflineMode;
    _showConfirmDialog(
      title: nextState ? 'Enable Offline Mode' : 'Disable Offline Mode',
      message: nextState
          ? 'Are you sure you want to enable offline mode? All scans will be written to local SQLite and queued for batch sync.'
          : 'Are you sure you want to disable offline mode and return to online authoritative validation?',
      onConfirm: () async {
        final storage = context.read<ScannerLocalStorage>();
        await storage.setOfflineMode(nextState);
        if (mounted) {
          context.read<ScannerBloc>().add(
                ScannerConfigChanged(offlineModeEnabled: nextState),
              );
          setState(() {
            _isOfflineMode = nextState;
          });
        }
      },
    );
  }

  /// Downloads event and permission data for offline validation (matching React Native Settings syncData)
  Future<void> _syncOfflinePermissions() async {
    setState(() {
      _isSyncingData = true;
    });

    try {
      final apiClient = context.read<ApiClient>();
      final storage = context.read<ScannerLocalStorage>();

      final dashboardResp = await apiClient.dio.get('organizer/dashboard');
      if (dashboardResp.statusCode == 200 && dashboardResp.data is Map) {
        final data = dashboardResp.data as Map<String, dynamic>;
        final eventList = data['event_list'] as List<dynamic>? ?? [];

        if (eventList.isNotEmpty) {
          final event = eventList.first as Map<String, dynamic>;
          final eventPk = event['pk'] ?? event['id'] ?? storage.getEventId();

          final permResp = await apiClient.dio.get('organizer/event-permission/$eventPk');
          if (permResp.statusCode == 200 && permResp.data != null) {
            final cachePayload = {
              'event': event,
              'permission': permResp.data,
              'cached_at': DateTime.now().toIso8601String(),
            };
            await storage.setOfflineData(jsonEncode(cachePayload));

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Offline event data synced successfully.'),
                  backgroundColor: AppTheme.statusSuccess,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          } else {
            throw Exception('Failed to load event permissions');
          }
        } else {
          throw Exception('No active events found on server');
        }
      } else {
        throw Exception('Server unreachable or invalid response');
      }
    } on DioException catch (dioErr) {
      if (dioErr.response?.statusCode == 401) {
        String msg = 'You have been logged out (another login detected)';
        if (dioErr.response?.data is Map) {
          final rawMsg = dioErr.response?.data['message'] ?? dioErr.response?.data['detail'];
          if (rawMsg != null) msg = rawMsg.toString();
        }
        if (mounted) {
          context.read<AuthBloc>().add(LogoutRequested(reason: msg));
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
            (route) => false,
          );
        }
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync failed: ${ApiClient.formatDioError(dioErr)}'),
            backgroundColor: AppTheme.statusRejected,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync failed: ${e.toString().replaceAll('Exception:', '').trim()}'),
            backgroundColor: AppTheme.statusRejected,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSyncingData = false;
        });
      }
    }
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Settings',
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
      body: RefreshIndicator(
        color: AppTheme.eventxproAccent,
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
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                // ── Section 1: Organizer Profile (organizer/user-profile) ──
                _buildProfileCard(authRepo),

                const SizedBox(height: 12),

                // ── Section 2: Scanner & Attendance Preferences ─────────────
                _buildSectionHeader('SCANNER & ATTENDANCE'),

                _buildSettingRow(
                  title: _isTopLevelTickets ? 'Disable top-level tickets' : 'Enable top-level tickets',
                  subtitle: 'Allow priority tier access across gates',
                  value: _isTopLevelTickets,
                  onTap: _toggleTopLevelTickets,
                ),

                const Divider(color: AppTheme.surfaceBorder, height: 1),

                _buildSettingRow(
                  title: _isShortToast ? 'Disable short toast' : 'Enable short toast',
                  subtitle: _isShortToast
                      ? 'Continuous rush scanning active: brief top notifications'
                      : 'Full attendee details card modal shown after each scan',
                  value: _isShortToast,
                  onTap: _toggleShortToast,
                ),

                const Divider(color: AppTheme.surfaceBorder, height: 1),

                _buildOfflineModeRow(),

                const SizedBox(height: 12),

                // ── Section 3: Offline Sessions Navigation ──────────────────
                _buildSectionHeader('OFFLINE STORAGE & SYNC'),

                _buildOfflineSessionsTile(),

                const SizedBox(height: 12),

                // ── Section 4: App Update Check ────────────────────────────
                _buildSectionHeader('SYSTEM & UPDATES'),

                _buildCheckUpdateTile(),

                const SizedBox(height: 12),

                // ── Section 5: Account Actions ─────────────────────────────
                _buildSectionHeader('ACCOUNT'),

                _buildLogoutTile(),

                // ── Section 6: App Version & Footer ────────────────────────
                _buildVersionFooter(),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 8, left: 4),
      child: Text(
        title,
        style: const TextStyle(
          color: AppTheme.textMuted,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
        ),
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

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.surfaceBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header: Avatar, Name, Username, Role, Refresh ────
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Avatar with Signature EventXPro Accent Ring
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppTheme.eventxproAccent,
                    width: 2.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.eventxproAccent.withValues(alpha: 0.3),
                      blurRadius: 6,
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

              const SizedBox(width: 12),

              // Name, Username & Role Pill
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
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
                    if (username.isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text(
                        '@$username',
                        style: const TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        // Role Pill
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: isAdmin
                                ? AppTheme.eventxproAccent.withValues(alpha: 0.15)
                                : AppTheme.accentIndigo.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isAdmin
                                  ? AppTheme.eventxproAccent
                                  : AppTheme.accentIndigo,
                              width: 1,
                            ),
                          ),
                          child: Text(
                            isAdmin ? 'ADMIN' : 'ORGANIZER',
                            style: TextStyle(
                              color: isAdmin
                                  ? AppTheme.eventxproAccent
                                  : const Color(0xFF818CF8),
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                        // Online / Offline Status Dot
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: _isOfflineMode
                                ? AppTheme.accentOrange.withValues(alpha: 0.15)
                                : AppTheme.statusSuccess.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: _isOfflineMode
                                  ? AppTheme.accentOrange
                                  : AppTheme.statusSuccess,
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 5.5,
                                height: 5.5,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _isOfflineMode
                                      ? AppTheme.accentOrange
                                      : AppTheme.statusSuccess,
                                ),
                              ),
                              const SizedBox(width: 4.5),
                              Text(
                                _isOfflineMode ? 'OFFLINE' : 'ONLINE',
                                style: TextStyle(
                                  color: _isOfflineMode
                                      ? AppTheme.accentOrange
                                      : AppTheme.statusSuccess,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 4),

              // Refresh Profile Button (compact)
              IconButton(
                tooltip: 'Refresh Profile',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: _isLoadingProfile
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.accentIndigo,
                        ),
                      )
                    : const Icon(
                        Icons.refresh_rounded,
                        color: AppTheme.textSecondary,
                        size: 20,
                      ),
                onPressed: _isLoadingProfile
                    ? null
                    : () => _loadProfile(forceRefresh: true),
              ),
            ],
          ),

          // ── Details: Email & Phone ────
          if (email.isNotEmpty || phone.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(color: AppTheme.surfaceBorder, height: 1),
            const SizedBox(height: 14),

            if (email.isNotEmpty)
              _buildProfileDetailRow(
                icon: Icons.email_outlined,
                iconColor: AppTheme.accentCyan,
                label: 'Email',
                value: email,
              ),

            if (email.isNotEmpty && phone.isNotEmpty)
              const SizedBox(height: 10),

            if (phone.isNotEmpty)
              _buildProfileDetailRow(
                icon: Icons.phone_outlined,
                iconColor: AppTheme.accentIndigo,
                label: 'Phone',
                value: phone,
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildInitialsAvatar(String initials) {
    return Container(
      color: AppTheme.eventxproAccent,
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

  Widget _buildLogoutTile() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.eventxproDanger.withValues(alpha: 0.3)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.eventxproDanger.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.logout_rounded,
            color: AppTheme.eventxproDanger,
            size: 22,
          ),
        ),
        title: const Text(
          'Log Out',
          style: TextStyle(
            color: AppTheme.eventxproDanger,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: const Text(
          'Sign out of your account on this device',
          style: TextStyle(
            color: AppTheme.textMuted,
            fontSize: 12,
          ),
        ),
        trailing: const Icon(
          Icons.arrow_forward_ios_rounded,
          color: AppTheme.textMuted,
          size: 16,
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
              style: TextStyle(
                color: Color(0xFF4A4B56),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingRow({
    required String title,
    String? subtitle,
    required bool value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 4),
        child: Row(
          children: [
            _buildCustomSwitch(value: value, onChanged: (_) => onTap()),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOfflineModeRow() {
    return InkWell(
      onTap: _toggleOfflineMode,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 4),
        child: Row(
          children: [
            _buildCustomSwitch(
              value: _isOfflineMode,
              onChanged: (_) => _toggleOfflineMode(),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isOfflineMode ? 'Disable offline mode' : 'Enable offline mode',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _isOfflineMode
                        ? 'Active • All scans queued locally in SQLite'
                        : 'Scans validated via remote Django backend',
                    style: TextStyle(
                      color: _isOfflineMode ? AppTheme.accentCyan : AppTheme.textMuted,
                      fontSize: 12,
                      fontWeight: _isOfflineMode ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),

            // Sync Data icon button matching React Native syncWrapper
            if (_isOfflineMode) ...[
              const SizedBox(width: 8),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: _isSyncingData ? null : _syncOfflinePermissions,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.accentIndigo.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.accentIndigo.withValues(alpha: 0.5)),
                    ),
                    child: _isSyncingData
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(
                            Icons.sync_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Custom switch matching the React Native SettingSwitch aesthetic
  Widget _buildCustomSwitch({
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 44,
        height: 26,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: value ? AppTheme.accentIndigo : const Color(0xFF4A4B56),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 20,
            height: 20,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOfflineSessionsTile() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.surfaceBorder),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.accentIndigo.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.inventory_2_outlined,
            color: AppTheme.accentIndigo,
            size: 24,
          ),
        ),
        title: const Text(
          'Offline Sessions',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: const Text(
          'View Entrances, Halls, Agendas & sync offline check-ins',
          style: TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 12,
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
              size: 16,
            ),
          ],
        ),
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const OfflineSessionsScreen(),
            ),
          );
          _loadSettings();
        },
      ),
    );
  }

  Widget _buildCheckUpdateTile() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.surfaceBorder),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.eventxproAccent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.system_update_rounded,
            color: AppTheme.eventxproAccent,
            size: 24,
          ),
        ),
        title: const Text(
          'Check for Updates',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: const Text(
          'Verify latest version on Firebase',
          style: TextStyle(
            color: AppTheme.textMuted,
            fontSize: 12,
          ),
        ),
        trailing: const Icon(
          Icons.arrow_forward_ios_rounded,
          color: AppTheme.textMuted,
          size: 16,
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

  // ignore: unused_element
  Widget _buildSystemInfoCard(ScannerState state) {
    final dev = _deviceInfo;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.qr_code_scanner_rounded, color: AppTheme.accentIndigo, size: 18),
              const SizedBox(width: 8),
              const Text(
                'Hardware & Scanner Diagnostics',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              if (dev != null && dev.isHardwareScannerCapable)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: dev.isHoneywell
                        ? const Color(0xFFEF5350).withValues(alpha: 0.2)
                        : const Color(0xFF0288D1).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: dev.isHoneywell ? const Color(0xFFEF5350) : const Color(0xFF0288D1),
                    ),
                  ),
                  child: Text(
                    dev.isHoneywell ? 'HONEYWELL' : 'ZEBRA',
                    style: TextStyle(
                      color: dev.isHoneywell ? const Color(0xFFFF8A80) : const Color(0xFF81D4FA),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _buildInfoRow('Device Model', dev?.displayName ?? 'Android Device'),
          _buildInfoRow('Scanner Engine', dev?.scannerEngine ?? state.adapterName),
          if (dev != null && dev.osRelease.isNotEmpty)
            _buildInfoRow('Operating System', 'Android ${dev.osRelease} (API ${dev.sdkInt})'),
          _buildInfoRow('Event ID', 'Event #${state.eventId}'),
          _buildInfoRow('Gate / Scan Type', 'Gate #${state.gateId} (${state.scanType})'),
          _buildInfoRow('Device UUID', state.deviceId),
          const SizedBox(height: 14),

          // Diagnostic Action Buttons
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              // Re-provision Scanner Button
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: AppTheme.surfaceBorder),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
                icon: const Icon(Icons.sync_rounded, size: 15, color: AppTheme.accentIndigo),
                label: const Text('Re-provision', style: TextStyle(fontSize: 12)),
                onPressed: _reprovisionScanner,
              ),

              // Test Scanner Beam Button
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: AppTheme.surfaceBorder),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
                icon: const Icon(Icons.play_circle_outline_rounded, size: 15, color: AppTheme.statusSuccess),
                label: const Text('Test Beam', style: TextStyle(fontSize: 12)),
                onPressed: _showScannerTestDialog,
              ),

              // Honeywell Setup Guide (if Honeywell device or requested)
              if (dev == null || dev.isHoneywell)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFF8A80),
                    side: const BorderSide(color: Color(0xFFEF5350)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                  icon: const Icon(Icons.help_outline_rounded, size: 15, color: Color(0xFFFF8A80)),
                  label: const Text('EDA51 Setup Guide', style: TextStyle(fontSize: 12)),
                  onPressed: _showHoneywellGuideDialog,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _reprovisionScanner() async {
    final success = await DeviceDetectionService().reprovisionScanner();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success
              ? 'Scanner Profile Re-provisioned successfully'
              : 'Re-provision command sent to hardware engine'),
          backgroundColor: AppTheme.accentIndigo,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _showScannerTestDialog() {
    final scannerBloc = context.read<ScannerBloc>();
    final scanStream = scannerBloc.activeAdapter.scanStream;
    StreamSubscription<String>? sub;

    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        String testScannedCode = 'Ready! Pull hardware trigger button or scan a QR code...';
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            sub ??= scanStream.listen((barcode) {
              scannerBloc.audioService.playTone(AudioTone.scanBeep);
              setDialogState(() {
                testScannedCode = 'Decoded Barcode:\n$barcode\n\n✅ Hardware Scanner Pipeline OK\n(Diagnostic Only • No Check-In Fired)';
              });
            });

            return AlertDialog(
              backgroundColor: AppTheme.surfaceElevated,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: AppTheme.surfaceBorder),
              ),
              title: const Row(
                children: [
                  Icon(Icons.qr_code_scanner_rounded, color: AppTheme.accentIndigo, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Scanner Beam Test',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.surfaceBorder),
                    ),
                    child: Text(
                      testScannedCode,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Scans are decoded in real-time through the native hardware intent pipeline without triggering backend check-ins.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    sub?.cancel();
                    Navigator.of(dialogCtx).pop();
                  },
                  child: const Text('Done', style: TextStyle(color: Colors.white70)),
                ),
              ],
            );
          },
        );
      },
    ).then((_) {
      sub?.cancel();
    });
  }

  void _showHoneywellGuideDialog() {
    showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppTheme.surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.surfaceBorder),
        ),
        title: const Row(
          children: [
            Icon(Icons.tune_rounded, color: Color(0xFFEF5350), size: 20),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Honeywell EDA51 Settings',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'EventXPro automatically claims the Honeywell scanner engine. If your device MDM requires manual confirmation, verify these settings:',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.4),
              ),
              SizedBox(height: 12),
              _StepRow(step: '1', text: 'Open Android Settings on device'),
              _StepRow(step: '2', text: 'Select "Honeywell Settings" > "Scanning"'),
              _StepRow(step: '3', text: 'Tap "Internal Scanner" > "Default Profile"'),
              _StepRow(step: '4', text: 'Open "Data Processing Settings"'),
              _StepRow(step: '5', text: 'Enable "Data Intent"'),
              _StepRow(step: '6', text: 'Set Action to: com.eventxpro.SCAN'),
              _StepRow(step: '7', text: 'Disable "Wedge" (prevents typing delay)'),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF5350),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Understood', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.textMuted,
              fontSize: 12,
            ),
          ),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final String step;
  final String text;

  const _StepRow({required this.step, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: const Color(0xFFEF5350).withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                step,
                style: const TextStyle(
                  color: Color(0xFFFF8A80),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white70, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}
