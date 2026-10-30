import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme/app_theme.dart';
import '../../data/adapters/simulated_hardware_adapter.dart';
import '../../data/adapters/zebra_datawedge_adapter.dart';
import '../../data/datasources/scanner_local_storage.dart';
import 'home/home_screen.dart';
import 'lead/lead_capture_screen.dart';
import 'lead/leads_list_screen.dart';
import 'settings_screen.dart';

enum NavigationTab {
  home,
  leads,
  settings,
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
      setState(() {
        _currentTab = tab;
      });
    }
  }

  void _openLeadScanner() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const LeadCaptureScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<ScannerLocalStorage>();

    return ValueListenableBuilder<bool>(
      valueListenable: storage.leadCapturePermissionNotifier,
      builder: (context, hasLeadPermission, _) {
        // Fallback: If user was on leads tab but permission was revoked, switch to home
        if (!hasLeadPermission && _currentTab == NavigationTab.leads) {
          _currentTab = NavigationTab.home;
        }

        // Ordered active screens according to current permission set
        final List<Widget> stackChildren = [
          HomeScreen(
            zebraAdapter: widget.zebraAdapter,
            simulatorAdapter: widget.simulatorAdapter,
            onOpenSettings: () => _selectTab(NavigationTab.settings),
            onOpenLeads: hasLeadPermission ? () => _selectTab(NavigationTab.leads) : null,
          ),
          if (hasLeadPermission)
            LeadsListScreen(isRootTab: true),
          SettingsScreen(isRootTab: true),
        ];

        // Resolve integer index inside the IndexedStack
        int activeStackIndex;
        if (hasLeadPermission) {
          switch (_currentTab) {
            case NavigationTab.home:
              activeStackIndex = 0;
              break;
            case NavigationTab.leads:
              activeStackIndex = 1;
              break;
            case NavigationTab.settings:
              activeStackIndex = 2;
              break;
          }
        } else {
          switch (_currentTab) {
            case NavigationTab.home:
              activeStackIndex = 0;
              break;
            case NavigationTab.settings:
              activeStackIndex = 1;
              break;
            case NavigationTab.leads:
              activeStackIndex = 0;
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
        color: const Color(0xFF131722).withValues(alpha: 0.98),
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: hasLeadPermission
              ? _buildLeadEnabledBar()
              : _buildTwoItemBar(),
        ),
      ),
    );
  }

  /// 4-item bar when Lead Capture is enabled (Home, Scan Lead, Leads, Settings)
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
        _buildActionScanButton(),
        _buildNavItem(
          icon: Icons.badge_outlined,
          activeIcon: Icons.badge_rounded,
          label: 'Leads',
          isSelected: _currentTab == NavigationTab.leads,
          onTap: () => _selectTab(NavigationTab.leads),
        ),
        _buildNavItem(
          icon: Icons.settings_outlined,
          activeIcon: Icons.settings_rounded,
          label: 'Settings',
          isSelected: _currentTab == NavigationTab.settings,
          onTap: () => _selectTab(NavigationTab.settings),
        ),
      ],
    );
  }

  /// 2-item clean bar when Lead Capture is disabled (Home & Settings)
  Widget _buildTwoItemBar() {
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
          icon: Icons.settings_outlined,
          activeIcon: Icons.settings_rounded,
          label: 'Settings',
          isSelected: _currentTab == NavigationTab.settings,
          onTap: () => _selectTab(NavigationTab.settings),
        ),
      ],
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final activeColor = AppTheme.brandGradientStart; // #C10067
    final inactiveColor = Colors.white.withValues(alpha: 0.45);

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? activeColor.withValues(alpha: 0.16)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    isSelected ? activeIcon : icon,
                    size: 21,
                    color: isSelected ? activeColor : inactiveColor,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isSelected ? Colors.white : inactiveColor,
                    fontSize: 10.5,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Distinct center quick-action scan button (matching React Native center QR button)
  Widget _buildActionScanButton() {
    return Expanded(
      child: GestureDetector(
        onTap: _openLeadScanner,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: AppTheme.brandGradient,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.25),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.brandGradientStart.withValues(alpha: 0.45),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Icon(
                Icons.qr_code_scanner_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(height: 3),
            const Text(
              'Scan Lead',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
