import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/services/app_update_service.dart';
import '../../core/theme/app_theme.dart';

/// Legacy alias for backward compatibility with existing call sites
typedef UpdateDialog = UpdateBottomSheet;

class UpdateBottomSheet extends StatelessWidget {
  final AppUpdateInfo updateInfo;

  const UpdateBottomSheet({super.key, required this.updateInfo});

  /// Displays the update modal bottom sheet.
  /// If it is a force update, dismiss gestures and back buttons are blocked.
  static Future<bool?> show(BuildContext context, AppUpdateInfo info) {
    debugPrint(
      '[UpdateBottomSheet] 🔔 Displaying bottom sheet: isForce=${info.isForceUpdate}, '
      'target=v${info.isForceUpdate ? info.minRequiredVersion : info.latestVersion}',
    );

    final isForce = info.isForceUpdate;

    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: !isForce,
      enableDrag: !isForce,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.82),
      builder: (_) => UpdateBottomSheet(updateInfo: info),
    );
  }

  Future<void> _handleDownload(BuildContext context) async {
    final uri = Uri.tryParse(updateInfo.apkUrl);
    if (uri != null) {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open APK download link. Please verify browser is available.'),
            backgroundColor: AppTheme.statusRejected,
          ),
        );
      }
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid APK download URL in Remote Config.'),
          backgroundColor: AppTheme.statusRejected,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isForce = updateInfo.isForceUpdate;
    final targetVersion = isForce
        ? updateInfo.minRequiredVersion
        : updateInfo.latestVersion;
    final targetBuild = isForce
        ? updateInfo.minRequiredBuildNumber
        : updateInfo.latestBuildNumber;

    final primaryColor = isForce
        ? const Color(0xFFFF3B30)
        : AppTheme.eventxproAccent;
    final secondaryColor = isForce
        ? const Color(0xFFC62828)
        : const Color(0xFF6366F1);

    return PopScope(
      canPop: !isForce, // Prevents Android hardware back button & gestures on force update
      child: Container(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 12,
          bottom: MediaQuery.of(context).padding.bottom + 20,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF141923),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          border: Border.all(
            color: isForce
                ? const Color(0xFFFF3B30).withValues(alpha: 0.45)
                : AppTheme.eventxproAccent.withValues(alpha: 0.35),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: isForce
                  ? const Color(0xFFFF3B30).withValues(alpha: 0.18)
                  : Colors.black.withValues(alpha: 0.7),
              blurRadius: 36,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── 1. Top Drag Handle ──────────────────────────────────────────
              Center(
                child: Container(
                  width: 44,
                  height: 4.5,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(2.5),
                  ),
                ),
              ),

              // ── 2. Glowing Header Icon Badge ────────────────────────────────
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [primaryColor, secondaryColor],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: primaryColor.withValues(alpha: 0.4),
                        blurRadius: 20,
                        spreadRadius: 2,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Icon(
                      isForce
                          ? Icons.system_security_update_warning_rounded
                          : Icons.rocket_launch_rounded,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ── 3. Title & Tag ──────────────────────────────────────────────
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: primaryColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    isForce ? 'MANDATORY UPDATE' : 'NEW VERSION READY',
                    style: TextStyle(
                      color: primaryColor,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              Text(
                isForce ? 'Update Required to Continue' : 'EventXPro Update Available',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.2,
                ),
              ),

              const SizedBox(height: 6),

              Text(
                isForce
                    ? 'Your current app version is outdated and no longer supported. Please update now to continue scanning.'
                    : 'A new release is available with enhanced scanner performance and stability improvements.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),

              const SizedBox(height: 20),

              // ── 4. Version Comparison Cards ─────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0C1017),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Row(
                  children: [
                    // Current Version
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            'CURRENT',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.45),
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'v${updateInfo.currentVersion}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            'Build ${updateInfo.currentBuildNumber}',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.35),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Arrow Divider
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.05),
                      ),
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        color: primaryColor,
                        size: 18,
                      ),
                    ),

                    // Target Version
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            isForce ? 'REQUIRED' : 'LATEST',
                            style: TextStyle(
                              color: primaryColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'v$targetVersion',
                            style: TextStyle(
                              color: primaryColor,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Build $targetBuild',
                            style: TextStyle(
                              color: primaryColor.withValues(alpha: 0.7),
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ── 5. Release Notes Box ────────────────────────────────────────
              if (updateInfo.releaseNotes.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0C1017),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.auto_awesome_rounded,
                            color: isForce
                                ? const Color(0xFFFF9800)
                                : AppTheme.eventxproAccent,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            "What's New in This Version",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        updateInfo.releaseNotes,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: 12.5,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // ── 6. Primary Action Button ────────────────────────────────────
              SizedBox(
                height: 52,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [primaryColor, secondaryColor],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: primaryColor.withValues(alpha: 0.35),
                        blurRadius: 18,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: ElevatedButton.icon(
                    onPressed: () => _handleDownload(context),
                    icon: const Icon(Icons.download_rounded, size: 22, color: Colors.white),
                    label: Text(
                      isForce
                          ? 'Download & Update Now (v$targetVersion)'
                          : 'Update to v$targetVersion Now',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.2,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ),

              // ── 7. Optional "Later" Button for Regular Updates ──────────────
              if (!isForce) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white60,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text(
                    'Remind Me Later',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
