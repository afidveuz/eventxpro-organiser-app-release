import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme/app_theme.dart';
import '../../data/adapters/simulated_hardware_adapter.dart';
import '../../data/adapters/zebra_datawedge_adapter.dart';
import '../../data/datasources/scanner_local_storage.dart';
import 'home/home_screen.dart';
import 'lead/lead_capture_screen.dart';
import 'lead/leads_list_screen.dart';
import 'profile_screen.dart';

enum NavigationTab {
  home,
  scanLead,
  leads,
  profile;

  /// Backwards compatibility alias for settings
  static const NavigationTab settings = profile;
}

/// Main root screen hosting the persistent Bottom Navigation Bar.
/// Dynamically updates its tabs based on whether the organizer has lead capture permission enabled.
class MainNavigationScreen extends StatefulWidget {
  final ZebraDataWedgeAdapter? zebraAdapter;
  final SimulatedHardwareAdapter? simulatorAdapter;
  final NavigationTab initialTab;

  const MainNavigationScreen({
    super.key,
    this.zebraAdapter,
    this.simulatorAdapter,
    this.initialTab = NavigationTab.home,
  });

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  late NavigationTab _currentTab;

  @override
  void initState() {
    super.initState();
    _currentTab = widget.initialTab;
  }

  void _selectTab(NavigationTab tab) {
    if (_currentTab != tab) {
      HapticFeedback.lightImpact();
      setState(() {
        _currentTab = tab;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<ScannerLocalStorage>();

    return ValueListenableBuilder<bool>(
      valueListenable: storage.leadCapturePermissionNotifier,
      builder: (context, hasLeadPermission, _) {
        // Fallback: If user was on leads/scanLead tab but permission was revoked, switch to home
        if (!hasLeadPermission &&
            (_currentTab == NavigationTab.leads ||
                _currentTab == NavigationTab.scanLead)) {
          _currentTab = NavigationTab.home;
        }

        // Ordered active screens according to current permission set
        final List<Widget> stackChildren = [
          HomeScreen(
            zebraAdapter: widget.zebraAdapter,
            simulatorAdapter: widget.simulatorAdapter,
            onOpenProfile: () => _selectTab(NavigationTab.profile),
            onOpenSettings: () => _selectTab(NavigationTab.profile),
            onOpenLeads: hasLeadPermission
                ? () => _selectTab(NavigationTab.leads)
                : null,
          ),
          if (hasLeadPermission) ...[
            LeadCaptureScreen(
              isRootTab: true,
              isActive: _currentTab == NavigationTab.scanLead,
              onOpenLeads: () => _selectTab(NavigationTab.leads),
            ),
            LeadsListScreen(
              isRootTab: true,
              onOpenScanLead: () => _selectTab(NavigationTab.scanLead),
            ),
          ],
          ProfileScreen(
            isRootTab: true,
            onOpenScanLead: hasLeadPermission
                ? () => _selectTab(NavigationTab.scanLead)
                : null,
          ),
        ];

        // Resolve integer index inside the IndexedStack
        int activeStackIndex;
        if (hasLeadPermission) {
          switch (_currentTab) {
            case NavigationTab.home:
              activeStackIndex = 0;
              break;
            case NavigationTab.scanLead:
              activeStackIndex = 1;
              break;
            case NavigationTab.leads:
              activeStackIndex = 2;
              break;
            case NavigationTab.profile:
              activeStackIndex = 3;
              break;
          }
        } else {
          switch (_currentTab) {
            case NavigationTab.home:
            case NavigationTab.scanLead:
            case NavigationTab.leads:
              activeStackIndex = 0;
              break;
            case NavigationTab.profile:
              activeStackIndex = 1;
              break;
          }
        }

        return PopScope(
          canPop: _currentTab == NavigationTab.home,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            if (_currentTab != NavigationTab.home) {
              setState(() => _currentTab = NavigationTab.home);
            }
          },
          child: Scaffold(
            backgroundColor: AppTheme.eventxproBg,
            body: IndexedStack(
              index: activeStackIndex,
              children: stackChildren,
            ),
            bottomNavigationBar: _buildBottomBar(hasLeadPermission),
          ),
        );
      },
    );
  }

  Widget _buildBottomBar(bool hasLeadPermission) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF181C2E).withValues(alpha: 0.98), // Indigo-slate top edge
            const Color(0xFF101320).withValues(alpha: 0.99), // Deep midnight body
            const Color(0xFF090B12),                         // Grounded obsidian base
          ],
          stops: const [0.0, 0.45, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.50),
            blurRadius: 20,
            offset: const Offset(0, -6),
          ),
          BoxShadow(
            color: AppTheme.accentIndigo.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Ambient Indigo Top Luminous Hairline
          Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white.withValues(alpha: 0.04),
                  AppTheme.accentIndigo.withValues(alpha: 0.35),
                  const Color(0xFF818CF8).withValues(alpha: 0.60),
                  AppTheme.accentIndigo.withValues(alpha: 0.35),
                  Colors.white.withValues(alpha: 0.04),
                ],
                stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: hasLeadPermission
                  ? _buildLeadEnabledBar()
                  : _buildTwoItemBar(),
            ),
          ),
        ],
      ),
    );
  }

  /// 4-item bar when Lead Capture is enabled (Home, Scan Lead, Leads, Profile)
  Widget _buildLeadEnabledBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _buildNavItem(
          icon: Icons.home_outlined,
          activeIcon: Icons.home_rounded,
          label: 'Home',
          isSelected: _currentTab == NavigationTab.home,
          onTap: () => _selectTab(NavigationTab.home),
        ),
        _buildNavItem(
          icon: Icons.qr_code_scanner_outlined,
          activeIcon: Icons.qr_code_scanner_rounded,
          label: 'Scan Lead',
          isSelected: _currentTab == NavigationTab.scanLead,
          onTap: () => _selectTab(NavigationTab.scanLead),
        ),
        _buildNavItem(
          icon: Icons.badge_outlined,
          activeIcon: Icons.badge_rounded,
          label: 'Leads',
          isSelected: _currentTab == NavigationTab.leads,
          onTap: () => _selectTab(NavigationTab.leads),
        ),
        _buildNavItem(
          icon: Icons.person_outline_rounded,
          activeIcon: Icons.person_rounded,
          label: 'Profile',
          isSelected: _currentTab == NavigationTab.profile,
          onTap: () => _selectTab(NavigationTab.profile),
        ),
      ],
    );
  }

  /// 2-item clean bar when Lead Capture is disabled (Home & Profile)
  /// Full-width layout with generous, symmetrically spaced touch areas
  Widget _buildTwoItemBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildNavItem(
            icon: Icons.home_outlined,
            activeIcon: Icons.home_rounded,
            label: 'Home',
            isSelected: _currentTab == NavigationTab.home,
            onTap: () => _selectTab(NavigationTab.home),
          ),
          _buildNavItem(
            icon: Icons.person_outline_rounded,
            activeIcon: Icons.person_rounded,
            label: 'Profile',
            isSelected: _currentTab == NavigationTab.profile,
            onTap: () => _selectTab(NavigationTab.profile),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final activeColor = AppTheme.accentIndigo;
    final inactiveColor = Colors.white.withValues(alpha: 0.45);

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkResponse(
          onTap: onTap,
          containedInkWell: true,
          highlightShape: BoxShape.rectangle,
          borderRadius: BorderRadius.circular(16),
          splashColor: activeColor.withValues(alpha: 0.12),
          highlightColor: Colors.white.withValues(alpha: 0.04),
          child: Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Active indicator line with indigo gradient & glow
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: isSelected ? 22 : 0,
                  height: 2.5,
                  margin: const EdgeInsets.only(bottom: 5),
                  decoration: BoxDecoration(
                    gradient: isSelected
                        ? const LinearGradient(
                            colors: [
                              AppTheme.accentIndigo,
                              Color(0xFF818CF8),
                            ],
                          )
                        : null,
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: AppTheme.accentIndigo.withValues(alpha: 0.55),
                              blurRadius: 6,
                              offset: const Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                ),
                // Micro-scale icon transition
                AnimatedScale(
                  scale: isSelected ? 1.10 : 1.0,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutBack,
                  child: Icon(
                    isSelected ? activeIcon : icon,
                    size: 22,
                    color: isSelected ? Colors.white : inactiveColor,
                  ),
                ),
                const SizedBox(height: 4),
                // Smooth typography transition
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  style: TextStyle(
                    color: isSelected ? Colors.white : inactiveColor,
                    fontSize: isSelected ? 11 : 10.5,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    letterSpacing: 0.2,
                  ),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
