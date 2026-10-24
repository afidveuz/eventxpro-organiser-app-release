import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../data/datasources/offline_database_helper.dart';
import '../../data/datasources/scanner_local_storage.dart';
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

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final storage = context.read<ScannerLocalStorage>();
    final db = context.read<OfflineDatabaseHelper>();

    final unsynced = await db.getUnsyncedCount();

    if (mounted) {
      setState(() {
        _isTopLevelTickets = storage.isTopLevelTicketsEnabled;
        _isShortToast = storage.isShortToastEnabled;
        _isOfflineMode = storage.isOfflineModeEnabled;
        _unsyncedCount = unsynced;
      });
    }
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
            content: Text('Sync failed: ${dioErr.message}'),
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
      body: BlocBuilder<ScannerBloc, ScannerState>(
        builder: (context, state) {
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            children: [
              // ── Section 1: Core Toggles (Matching React Native Settings) ────
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

              const SizedBox(height: 24),

              // ── Section 2: Offline Sessions Navigation ────────────────────
              _buildOfflineSessionsTile(),

              const SizedBox(height: 24),

              // ── Section 3: Gate & Device System Information ───────────────
              _buildSystemInfoCard(state),
            ],
          );
        },
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

  Widget _buildSystemInfoCard(ScannerState state) {
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
          const Row(
            children: [
              Icon(Icons.info_outline_rounded, color: AppTheme.textMuted, size: 18),
              SizedBox(width: 8),
              Text(
                'Hardware & Gate Diagnostics',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildInfoRow('Event ID', 'Event #${state.eventId}'),
          _buildInfoRow('Gate / Scan Type', 'Gate #${state.gateId} (${state.scanType})'),
          _buildInfoRow('Active Scanner', state.adapterName),
          _buildInfoRow('Device UUID', state.deviceId),
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
