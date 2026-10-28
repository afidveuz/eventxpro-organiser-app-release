import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../core/config/app_constants.dart';
import '../../core/services/gate_count_service.dart';
import '../../core/services/remote_config_service.dart';
import '../../core/theme/app_theme.dart';
import '../../data/datasources/auth_local_storage.dart';
import '../../data/datasources/scanner_local_storage.dart';
import '../../domain/entities/attendee.dart';
import '../../domain/entities/scan_decision_code.dart';
import '../bloc/scanner_bloc.dart';
import '../bloc/scanner_event.dart';
import '../bloc/scanner_state.dart';
import '../screens/settings_screen.dart';

/// Clean, high-performance scanning UI for EventXPro gate staff.
/// Implements the authentic EventXPro branding, EventTopBar, viewfinder with glowing corner
/// brackets & sweeping laser, dual hardware/camera mode switcher, and high-visibility decision cards.
class SimpleScannerView extends StatefulWidget {
  final ScannerState state;
  final String? gateName;
  final String? eventName;
  final String? section;
  final String? sectionLocation;
  final VoidCallback onLogout;
  final VoidCallback onResetToReady;

  const SimpleScannerView({
    super.key,
    required this.state,
    this.gateName,
    this.eventName,
    this.section,
    this.sectionLocation,
    required this.onLogout,
    required this.onResetToReady,
  });

  @override
  State<SimpleScannerView> createState() => _SimpleScannerViewState();
}

class _SimpleScannerViewState extends State<SimpleScannerView>
    with TickerProviderStateMixin {
  late AnimationController _laserController;
  late Animation<double> _laserAnimation;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  late AnimationController _blinkController;
  late Animation<double> _blinkAnimation;

  MobileScannerController? _cameraController;
  bool _isCameraActive = false;
  bool _isTorchOn = false;
  bool _hasLoadedCameraPref = false;

  bool _isShortToast = false;
  ScannerDecisionState? _currentToastDecision;
  Timer? _toastDismissTimer;
  String? _lastCameraScannedToken;
  DateTime? _lastCameraScanTime;

  GateCheckInOutCount _gateCount = const GateCheckInOutCount();
  bool _hasLoadedGateCount = false;

  @override
  void initState() {
    super.initState();

    // Laser sweeps up and down
    _laserController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    )..repeat(reverse: true);

    _laserAnimation = Tween<double>(begin: 0.05, end: 0.95).animate(
      CurvedAnimation(parent: _laserController, curve: Curves.easeInOut),
    );

    // Hardware Scanner radar pulse rings
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();

    _pulseAnimation = CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeOut,
    );

    // Offline beacon blinking
    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    _blinkAnimation = Tween<double>(begin: 0.35, end: 1.0).animate(
      CurvedAnimation(parent: _blinkController, curve: Curves.easeInOut),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_hasLoadedCameraPref) {
      _hasLoadedCameraPref = true;
      try {
        final storage = context.read<ScannerLocalStorage>();
        final enabled = storage.isCameraEnabled;
        if (enabled) {
          _initCamera();
        }
        _isShortToast = storage.isShortToastEnabled;
        if (_isShortToast && widget.state is ScannerDecisionState) {
          _currentToastDecision = widget.state as ScannerDecisionState;
        }
      } catch (_) {}
    }

    if (!_hasLoadedGateCount) {
      _hasLoadedGateCount = true;
      _loadGateCounts();
    }
  }

  Future<void> _loadGateCounts() async {
    try {
      final service = context.read<GateCountService>();
      final section = widget.section ?? 'entrances';
      final actionId = widget.state.gateId;
      final eventId = widget.state.eventId;
      final location = widget.sectionLocation;

      final count = await service.getCounts(
        eventId: eventId,
        section: section,
        actionId: actionId,
        location: location,
      );

      if (mounted) {
        setState(() {
          _gateCount = count;
        });
      }
    } catch (_) {}
  }

  @override
  void didUpdateWidget(covariant SimpleScannerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state is ScannerDecisionState && widget.state != oldWidget.state) {
      final decisionState = widget.state as ScannerDecisionState;
      if (decisionState.isSuccess || decisionState.response.status == 'ACCEPTED') {
        final isCheckIn = widget.state.scanType.toLowerCase().contains('in') ||
            widget.state.scanType.toLowerCase().contains('entry');
        setState(() {
          _gateCount = _gateCount.copyWith(
            checkIn: isCheckIn ? _gateCount.checkIn + 1 : _gateCount.checkIn,
            checkOut: !isCheckIn ? _gateCount.checkOut + 1 : _gateCount.checkOut,
          );
        });
        try {
          context.read<GateCountService>().incrementCount(
                eventId: widget.state.eventId,
                section: widget.section ?? decisionState.request.section,
                actionId: widget.state.gateId,
                punchType: widget.state.scanType,
                location: widget.sectionLocation ?? decisionState.request.sectionLocation,
              );
        } catch (_) {}
      }

      if (_isShortToast) {
        _currentToastDecision = widget.state as ScannerDecisionState;
        _toastDismissTimer?.cancel();
        _toastDismissTimer = Timer(const Duration(milliseconds: 3500), () {
          if (mounted) {
            setState(() {
              _currentToastDecision = null;
            });
          }
        });
      }
    } else if (widget.state is ScannerReadyState && oldWidget.state is ScannerDecisionState) {
      if (!_isShortToast) {
        _currentToastDecision = null;
      }
    }
  }

  void _initCamera() {
    _cameraController ??= MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
    setState(() {
      _isCameraActive = true;
    });
  }

  void _toggleCamera() {
    HapticFeedback.lightImpact();
    if (_isCameraActive) {
      _cameraController?.dispose();
      _cameraController = null;
      setState(() {
        _isCameraActive = false;
        _isTorchOn = false;
      });
    } else {
      _initCamera();
    }

    try {
      context.read<ScannerLocalStorage>().setCameraEnabled(_isCameraActive);
    } catch (_) {}
  }

  String _resolveGateName() {
    if (widget.gateName != null && widget.gateName!.trim().isNotEmpty) {
      return widget.gateName!.trim();
    }
    try {
      final storage = context.read<ScannerLocalStorage>();
      final offlineRaw = storage.getOfflineData();
      if (offlineRaw != null && offlineRaw.isNotEmpty) {
        final data = jsonDecode(offlineRaw) as Map<String, dynamic>;
        final entrances = data['entrance'] as List<dynamic>?;
        if (entrances != null) {
          for (final ent in entrances) {
            if ((ent['entrance_id'] as num?)?.toInt() == widget.state.gateId) {
              final name = ent['entrance_name']?.toString();
              if (name != null && name.isNotEmpty) return name;
            }
          }
        }
      }
    } catch (_) {}
    return 'Entrance #${widget.state.gateId}';
  }

  String _resolveEventName() {
    if (widget.eventName != null && widget.eventName!.trim().isNotEmpty) {
      return widget.eventName!.trim();
    }
    try {
      final storage = context.read<ScannerLocalStorage>();
      final offlineRaw = storage.getOfflineData();
      if (offlineRaw != null && offlineRaw.isNotEmpty) {
        final data = jsonDecode(offlineRaw) as Map<String, dynamic>;
        final event = data['event'] as Map<String, dynamic>?;
        final name = event?['name']?.toString() ?? event?['title']?.toString();
        if (name != null && name.isNotEmpty) return name;
      }
    } catch (_) {}
    return 'EventXPro Organiser';
  }

  String? _resolvePhotoUrl(String? photoUrl) {
    if (photoUrl == null || photoUrl.trim().isEmpty) return null;
    final trimmed = photoUrl.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    try {
      final authStorage = context.read<AuthLocalStorage?>();
      final baseUrl = authStorage?.getBaseUrl() ?? AppConstants.defaultBaseUrl;
      final cleanBase = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
      final cleanPath = trimmed.startsWith('/') ? trimmed : '/$trimmed';
      return '$cleanBase$cleanPath';
    } catch (_) {
      final defaultBase = RemoteConfigService().getDefaultBaseUrl();
      final cleanBase = defaultBase.endsWith('/')
          ? defaultBase.substring(0, defaultBase.length - 1)
          : defaultBase;
      final cleanPath = trimmed.startsWith('/') ? trimmed : '/$trimmed';
      return '$cleanBase$cleanPath';
    }
  }

  String _formatPunchTime(String? punchTime) {
    if (punchTime == null || punchTime.trim().isEmpty) return '';
    try {
      final parts = punchTime.trim().split(':');
      if (parts.length >= 2) {
        final hour = int.parse(parts[0]);
        final minute = int.parse(parts[1]);
        final now = DateTime.now();
        final dt = DateTime(now.year, now.month, now.day, hour, minute);
        return DateFormat('hh:mm a').format(dt);
      }
    } catch (_) {}
    return punchTime.trim();
  }

  void _showManualEntrySheet() {
    HapticFeedback.selectionClick();
    final textController = TextEditingController();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return Container(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 24,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF1B2130),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(
              color: AppTheme.eventxproAccent.withValues(alpha: 0.4),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.6),
                blurRadius: 32,
                offset: const Offset(0, -6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Sheet Handle
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // Title
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.eventxproAccent.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.keyboard_outlined,
                      color: AppTheme.eventxproAccent,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Manual Ticket Entry',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Enter or paste the ticket QR token code to manually validate admission.',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 20),

              // Input TextField
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF131722),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppTheme.eventxproAccent.withValues(alpha: 0.5),
                    width: 1.2,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: textController,
                        autofocus: true,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.6,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'e.g. TICKET-98234-A7',
                          hintStyle: TextStyle(
                            color: Colors.white38,
                            fontSize: 14,
                          ),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          border: InputBorder.none,
                        ),
                        onSubmitted: (val) {
                          if (val.trim().isNotEmpty) {
                            Navigator.of(sheetCtx).pop();
                            context
                                .read<ScannerBloc>()
                                .add(ScannerRawBarcodeReceived(val.trim()));
                          }
                        },
                      ),
                    ),
                    IconButton(
                      tooltip: 'Paste from clipboard',
                      icon: const Icon(Icons.paste_rounded, color: Colors.white70),
                      onPressed: () async {
                        final data = await Clipboard.getData('text/plain');
                        if (data?.text != null) {
                          textController.text = data!.text!.trim();
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Submit Button
              ElevatedButton(
                onPressed: () {
                  final code = textController.text.trim();
                  if (code.isNotEmpty) {
                    Navigator.of(sheetCtx).pop();
                    context
                        .read<ScannerBloc>()
                        .add(ScannerRawBarcodeReceived(code));
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.eventxproAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'Verify Ticket',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _toastDismissTimer?.cancel();
    _cameraController?.dispose();
    _laserController.dispose();
    _pulseController.dispose();
    _blinkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isCheckOut = widget.state.scanType == 'check_out';
    final topBannerOffset = MediaQuery.of(context).padding.top +
        (widget.state.isOfflineMode ? 96.0 : 70.0);

    return Stack(
      children: [
        // ── 1. Top Radial Brand Aura ──────────────────────────────
        Positioned(
          top: -80,
          left: 0,
          right: 0,
          height: 380,
          child: const RepaintBoundary(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -0.65),
                  radius: 1.15,
                  colors: [
                    Color(0x35C10067),
                    Color(0x10C10067),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),

        // ── 2. Main Content Layout ────────────────────────────────
        SafeArea(
          child: Column(
            children: [
              // Top Bar (Matching React Native EventTopBar.jsx)
              _buildEventTopBar(isCheckOut),

              // Offline Indicator Badge if offline mode is active
              if (widget.state.isOfflineMode) _buildOfflineBadge(),

              // Main Body (Viewfinder / Processing / Decision Card)
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: _buildBody(isCheckOut),
                    ),
                  ),
                ),
              ),

              // Bottom Dock: Mode switch, flashlight, flip, manual entry
              _buildControlDock(),

              // Sleek Telemetry Footer
              _buildFooter(),
            ],
          ),
        ),

        // ── 3. Short Toast Floating Notification (Rush Mode) ──────
        if (_isShortToast && _currentToastDecision != null)
          Positioned(
            top: topBannerOffset,
            left: 16,
            right: 16,
            child: _buildShortToastBanner(_currentToastDecision!),
          ),
      ],
    );
  }

  // ── 1. EventTopBar (Matching React Native EventTopBar.jsx) ─────────
  Widget _buildEventTopBar(bool isCheckOut) {
    final gateName = _resolveGateName();
    final eventName = _resolveEventName();
    final typeColor =
        isCheckOut ? AppTheme.eventxproDanger : AppTheme.eventxproSuccess;
    final typeText = isCheckOut ? 'Check-out' : 'Check-in';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Circular White Back Button with Accent Border (EventTopBar.jsx)
          InkWell(
            onTap: () {
              HapticFeedback.lightImpact();
              Navigator.of(context).pop();
            },
            borderRadius: BorderRadius.circular(50),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppTheme.eventxproAccent,
                  width: 2.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.eventxproAccent.withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Center(
                child: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 16,
                  color: Color(0xFF171C26),
                ),
              ),
            ),
          ),

          const SizedBox(width: 14),

          // Centered Gate Title & Event Name
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Title Section: Entrance Name + Status Text
                RichText(
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  text: TextSpan(
                    style: const TextStyle(
                      fontFamily: 'Segoe UI',
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                    children: [
                      TextSpan(text: '$gateName '),
                      TextSpan(
                        text: typeText,
                        style: TextStyle(
                          color: typeColor,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 3),

                // Subtitle Section: Calendar icon + Event Name
                Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.calendar_today_rounded,
                      size: 11,
                      color: Colors.white70,
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        eventName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(width: 10),

          // Action: Settings Button
          InkWell(
            onTap: () async {
              HapticFeedback.lightImpact();
              context.read<ScannerBloc>().add(const ScannerScanningPaused());
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
              if (mounted) {
                context.read<ScannerBloc>().add(const ScannerScanningResumed());
                final storage = context.read<ScannerLocalStorage>();
                setState(() {
                  _isShortToast = storage.isShortToastEnabled;
                  if (!_isShortToast) {
                    _currentToastDecision = null;
                    _toastDismissTimer?.cancel();
                  }
                });
              }
            },
            borderRadius: BorderRadius.circular(50),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF212836),
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppTheme.eventxproBorder,
                  width: 1.2,
                ),
              ),
              child: const Icon(
                Icons.settings_outlined,
                size: 18,
                color: Colors.white70,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Offline Beacon Badge ───────────────────────────────────────────
  Widget _buildOfflineBadge() {
    return RepaintBoundary(
      child: FadeTransition(
        opacity: _blinkAnimation,
        child: Container(
          margin: const EdgeInsets.only(top: 2, bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFFF3B30),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF3B30).withValues(alpha: 0.45),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off_rounded, size: 12, color: Colors.white),
              SizedBox(width: 6),
              Text(
                'OFFLINE MODE ACTIVE',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 2. Main Body (State-driven) ───────────────────────────────────
  Widget _buildBody(bool isCheckOut) {
    if (widget.state is ScannerProcessingState && !_isShortToast) {
      return _buildProcessingCard(widget.state as ScannerProcessingState);
    }

    if (widget.state is ScannerDecisionState && !_isShortToast) {
      return _buildDecisionCard(widget.state as ScannerDecisionState);
    }

    // Default: Ready Viewfinder (stays continuously active if _isShortToast is true)
    return _buildReadyViewfinder(isCheckOut);
  }

  // ── 2A. Ready Viewfinder (Hardware vs Camera) ───────────────────────
  Widget _buildReadyViewfinder(bool isCheckOut) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Headline guidance (Matching OfflineScanner.jsx)
        const Text(
          'Scan any QR',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 6),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'Position your phone to make sure the QR code is within the frame',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              color: Color(0xFFAFAFAF),
              height: 1.3,
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Viewfinder Frame (Isolated RepaintBoundary to prevent repaint cascade)
        RepaintBoundary(
          child: Container(
              width: 270,
              height: 270,
              decoration: BoxDecoration(
                color: const Color(0xFF0F141E),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.12),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.eventxproAccent.withValues(alpha: 0.2),
                    blurRadius: 28,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Mode A: Live Smartphone Camera Feed
                    if (_isCameraActive && _cameraController != null)
                      MobileScanner(
                        controller: _cameraController!,
                        onDetect: (BarcodeCapture capture) {
                          if (widget.state is ScannerProcessingState) return;
                          if (!_isShortToast && widget.state is! ScannerReadyState) return;

                          for (final barcode in capture.barcodes) {
                            final rawVal = barcode.rawValue?.trim();
                            if (rawVal != null && rawVal.isNotEmpty) {
                              final now = DateTime.now();
                              if (_lastCameraScannedToken == rawVal && _lastCameraScanTime != null) {
                                final elapsed = now.difference(_lastCameraScanTime!).inMilliseconds;
                                if (elapsed < 1500) {
                                  return; // suppress rapid duplicate frame of identical token
                                }
                              }
                              _lastCameraScannedToken = rawVal;
                              _lastCameraScanTime = now;
                              debugPrint('[CAMERA SCAN DETECTED] 📷 Scanned barcode: "$rawVal"');
                              HapticFeedback.lightImpact();
                              context
                                  .read<ScannerBloc>()
                                  .add(ScannerRawBarcodeReceived(rawVal));
                              break;
                            }
                          }
                        },
                        errorBuilder: (context, error) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.videocam_off_rounded,
                                    size: 38,
                                    color: AppTheme.eventxproDanger,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Camera Access: ${error.errorCode.name}',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.white70,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      )
                    else
                      // Mode B: Hardware Scanner Listening Illustration
                      _buildHardwareScannerArtwork(),

                    // 4 Signature Corner Brackets (Magenta Accent) - Static paint layer
                    const Positioned.fill(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: _CornerBracketPainter(
                            color: AppTheme.eventxproAccent,
                            bracketLength: 32,
                            strokeWidth: 3.5,
                          ),
                        ),
                      ),
                    ),

                    // Animated Sweeping Laser Beam (Isolated animation & repaint layer)
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: AnimatedBuilder(
                          animation: _laserAnimation,
                          builder: (context, _) {
                            return Stack(
                              children: [
                                Positioned(
                                  top: 270 * _laserAnimation.value,
                                  left: 14,
                                  right: 14,
                                  child: Container(
                                    height: 2.8,
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [
                                          Colors.transparent,
                                          AppTheme.eventxproAccent,
                                          Color(0xFFFF3E96),
                                          Colors.white,
                                          Color(0xFFFF3E96),
                                          AppTheme.eventxproAccent,
                                          Colors.transparent,
                                        ],
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppTheme.eventxproAccent.withValues(alpha: 0.9),
                                          blurRadius: 12,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        const SizedBox(height: 20),

        // Active Listening Indicator Pill
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF1B2232),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.15),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isCameraActive
                      ? AppTheme.accentCyan
                      : AppTheme.statusSuccess,
                  boxShadow: [
                    BoxShadow(
                      color: _isCameraActive
                          ? AppTheme.accentCyan
                          : AppTheme.statusSuccess,
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _isCameraActive
                    ? 'Phone Camera Active'
                    : 'Zebra Hardware Scanner Ready',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ],
    ).animate().fadeIn(duration: 200.ms);
  }

  /// High-tech Artwork shown when Zebra/Honeywell Hardware Scanner is active
  Widget _buildHardwareScannerArtwork() {
    return RepaintBoundary(
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Animated Pulse Rings (Isolated)
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, _) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 80 + (90 * _pulseAnimation.value),
                    height: 80 + (90 * _pulseAnimation.value),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppTheme.eventxproAccent.withValues(
                          alpha: (1.0 - _pulseAnimation.value) * 0.45,
                        ),
                        width: 1.5,
                      ),
                    ),
                  ),
                  Container(
                    width: 50 + (130 * _pulseAnimation.value),
                    height: 50 + (130 * _pulseAnimation.value),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppTheme.eventxproAccent.withValues(
                          alpha: (1.0 - _pulseAnimation.value) * 0.25,
                        ),
                        width: 1.0,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),

          // Subtle Watermark QR Icon in center (Static layer)
          Icon(
            Icons.qr_code_2_rounded,
            size: 100,
            color: Colors.white.withValues(alpha: 0.08),
          ),

          // Center Target Crosshair Graphic (Static layer)
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.eventxproAccent.withValues(alpha: 0.12),
              border: Border.all(
                color: AppTheme.eventxproAccent.withValues(alpha: 0.6),
                width: 1.5,
              ),
            ),
            child: const Icon(
              Icons.center_focus_strong_rounded,
              size: 28,
              color: AppTheme.eventxproAccent,
            ),
          ),
        ],
      ),
    );
  }

  // ── 2B. In-Flight Processing Card ─────────────────────────────────
  Widget _buildProcessingCard(ScannerProcessingState procState) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2536),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: AppTheme.eventxproAccent.withValues(alpha: 0.6),
          width: 1.8,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.eventxproAccent.withValues(alpha: 0.2),
            blurRadius: 24,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 52,
            height: 52,
            child: CircularProgressIndicator(
              strokeWidth: 3.8,
              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.eventxproAccent),
            ),
          ),
          const SizedBox(height: 22),
          const Text(
            'VERIFYING ADMISSION...',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.0,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Token: ${procState.tokenSnippet}',
            style: const TextStyle(
              fontSize: 13,
              fontFamily: 'monospace',
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 150.ms).scale(begin: const Offset(0.95, 0.95));
  }

  // ── 2C. Authoritative Decision Card (Success / Warning / Rejected) ─
  // ── 2C. Authoritative Decision Card (Matching React Native AttendeeSheet.jsx) ─
  Widget _buildDecisionCard(ScannerDecisionState decState, {bool isModal = false}) {
    Color headerColor;
    IconData iconData;
    final alertType = decState.response.alertType;
    final msg = decState.response.message;
    final isSuccess = decState.response.isAlertSuccess;
    final isWarning = decState.response.isAlertWarning;

    final isNetworkErr = decState.isNetworkError ||
        decState.response.code == ScanDecisionCode.networkError ||
        alertType == 'network_error' ||
        msg.toLowerCase().contains('no internet') ||
        msg.toLowerCase().contains('saved offline') ||
        msg.toLowerCase().contains('network unreachable') ||
        msg.toLowerCase().contains('unable to reach server');

    if (isNetworkErr) {
      headerColor = const Color(0xFFFF8450); // Warning Amber
      iconData = Icons.wifi_off_rounded;
    } else if (alertType == 'success' || (alertType == null && isSuccess)) {
      headerColor = const Color(0xFF23A618); // #23A618 Vibrant Green from AttendeeSheet.jsx
      iconData = decState.request.scanType.toLowerCase() == 'check_out'
          ? Icons.logout_rounded
          : Icons.check_circle_rounded;
    } else if (alertType == 'warning' || (alertType == null && isWarning)) {
      headerColor = const Color(0xFFFF8450); // #FF8450 Warning Fill
      iconData = Icons.warning_amber_rounded;
    } else if (alertType == 'info' || decState.response.isAlertInfo) {
      headerColor = const Color(0xFF00A0D2); // #00A0D2 Info Sky Blue
      iconData = Icons.info_outline_rounded;
    } else {
      headerColor = const Color(0xFFFF4343); // #FF4343 Error Red
      iconData = Icons.error_outline_rounded;
    }

    final attendee = decState.response.attendee;
    final punchTime = decState.response.punchTime ?? attendee?.punchTime;
    final formattedPunchTime = _formatPunchTime(punchTime);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: headerColor.withValues(alpha: 0.35),
            blurRadius: 28,
            spreadRadius: 2,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 1. Top Header Bar (Matching AttendeeSheet.jsx) ──
          Container(
            color: headerColor,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Circular White Background ('okBg') with Icon in Header Color
                Container(
                  width: 38,
                  height: 38,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(iconData, size: 22, color: headerColor),
                ),
                const SizedBox(width: 12),

                // Title & Subtitle / Timestamp
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildHeaderTitle(msg, isNetworkErr: isNetworkErr),
                      const SizedBox(height: 2),
                      _buildHeaderSubtitle(msg, formattedPunchTime, isNetworkErr: isNetworkErr),
                    ],
                  ),
                ),

                // Circular Close Button (styles.closeBtn)
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      if (isModal) {
                        Navigator.of(context).pop();
                      } else {
                        widget.onResetToReady();
                      }
                    },
                    borderRadius: BorderRadius.circular(50),
                    child: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.33),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                        size: 19,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── 2. Card Content Body (Matching styles.profileWrapper) ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isNetworkErr) ...[
                  _buildNetworkOfflineBody(decState, isModal: isModal),
                ] else if (attendee != null) ...[
                  // Profile Row: Avatar + Details
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Avatar: Photo or Initials Monogram (styles.imgTxt)
                      _buildAvatar(attendee),
                      const SizedBox(width: 14),

                      // User Detail Wrapper (styles.userDetailWrapper)
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Full Name (styles.name)
                            Text(
                              attendee.fullName.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 16.5,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF111827),
                                letterSpacing: 0.3,
                              ),
                            ),

                            // Company Name (styles.nameSub)
                            if (attendee.company != null &&
                                attendee.company!.trim().isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                attendee.company!,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF4B5563),
                                ),
                              ),
                            ],

                            // Ticket ID (styles.nameSub)
                            if (attendee.ticketId != null &&
                                attendee.ticketId!.trim().isNotEmpty &&
                                attendee.ticketId != decState.request.qrToken) ...[
                              const SizedBox(height: 2),
                              Text(
                                'Ticket ID: ${attendee.ticketId}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF4B5563),
                                ),
                              ),
                            ],

                            // Category Badge (ChipTail.jsx: #9D4AC5 purple)
                            const SizedBox(height: 6),
                            _buildChipTail(attendee),
                          ],
                        ),
                      ),
                    ],
                  ),

                  // Last Checkin Session (if available in AttendeeSheet.jsx)
                  if (attendee.lastCheckinSession != null &&
                      attendee.lastCheckinSession!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.history_rounded, size: 14, color: Color(0xFF6B7280)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Last Checkin: ${attendee.lastCheckinSession} at ${_formatPunchTime(attendee.lastCheckinTime)}',
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: Color(0xFF374151),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Session Access tags (styles.accessWrapper & AgendaTag.jsx)
                  if (attendee.sessionAccess != null &&
                      attendee.sessionAccess!.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    const Text(
                      'Access',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: attendee.sessionAccess!.map((itm) {
                        final timeStr = itm.startTm != null ? _formatPunchTime(itm.startTm) : '';
                        final hallStr = itm.hallName != null && itm.hallName!.isNotEmpty ? '- ${itm.hallName}' : '';
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3E8FF),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFD8B4FE)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '$timeStr $hallStr'.trim(),
                                style: const TextStyle(
                                  fontSize: 9.5,
                                  color: Color(0xFF7E22CE),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                itm.title,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF3B0764),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ] else ...[
                  // If attendee is null (Access Denied / Unassigned / Invalid Badge)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Center(
                      child: Text(
                        msg,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFDC2626),
                        ),
                      ),
                    ),
                  ),
                ],

                if (!isNetworkErr) ...[
                  const SizedBox(height: 16),

                  // Ready For Next Attendee Button
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        if (isModal) {
                          Navigator.of(context).pop();
                        } else {
                          widget.onResetToReady();
                        }
                      },
                      icon: Icon(
                        isModal ? Icons.check_rounded : Icons.arrow_forward_rounded,
                        size: 18,
                      ),
                      label: Text(
                        isModal ? 'Done & Return To Scanner' : 'Ready For Next Attendee',
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.3,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: headerColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 180.ms).scale(begin: const Offset(0.92, 0.92));
  }

  Widget _buildNetworkOfflineBody(ScannerDecisionState decState, {bool isModal = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 6),
        // Visual offline aura badge
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: const Color(0xFFFFF7ED),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFFFEDD5), width: 2),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFEA580C).withValues(alpha: 0.12),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Center(
            child: Icon(
              Icons.wifi_off_rounded,
              size: 32,
              color: Color(0xFFEA580C),
            ),
          ),
        ),

        const SizedBox(height: 14),

        // Headline
        const Text(
          'Scan Recorded Offline',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 17.5,
            fontWeight: FontWeight.w800,
            color: Color(0xFF111827),
            letterSpacing: 0.2,
          ),
        ),

        const SizedBox(height: 6),

        // User-friendly descriptive explanation
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            'Unable to reach EventXPro server. This scan has been safely recorded to your local offline queue and will automatically sync once internet connection is restored.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF6B7280),
              height: 1.35,
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Scanned ticket / token chip
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF9FAFB),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Row(
            children: [
              const Icon(Icons.qr_code_2_rounded, size: 20, color: Color(0xFF4B5563)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  decState.request.qrToken,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1F2937),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'QUEUED',
                  style: TextStyle(
                    color: Color(0xFFB45309),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 18),

        // Ready for Next Attendee Button (Primary)
        SizedBox(
          width: double.infinity,
          height: 46,
          child: ElevatedButton.icon(
            onPressed: () {
              HapticFeedback.lightImpact();
              if (isModal) {
                Navigator.of(context).pop();
              } else {
                widget.onResetToReady();
              }
            },
            icon: Icon(
              isModal ? Icons.check_rounded : Icons.arrow_forward_rounded,
              size: 18,
            ),
            label: Text(
              isModal ? 'Done & Return To Scanner' : 'Ready For Next Attendee',
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.3,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF8450),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
          ),
        ),

        const SizedBox(height: 10),

        // Switch to Offline Mode Button (Secondary outline)
        SizedBox(
          width: double.infinity,
          height: 42,
          child: OutlinedButton.icon(
            onPressed: () async {
              HapticFeedback.mediumImpact();
              await _enableOfflineMode();
              if (!mounted) return;
              if (isModal) {
                Navigator.of(context).pop();
              } else {
                widget.onResetToReady();
              }
            },
            icon: const Icon(Icons.offline_bolt_rounded, size: 18, color: Color(0xFFEA580C)),
            label: const Text(
              'Switch to Offline Mode',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFFEA580C),
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFFFED7AA), width: 1.2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderTitle(String msg, {bool isNetworkErr = false}) {
    if (isNetworkErr ||
        msg.toLowerCase().contains('no internet') ||
        msg.toLowerCase().contains('saved offline') ||
        msg.toLowerCase().contains('network unreachable')) {
      return const Text(
        'No Internet Connection',
        style: TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      );
    }
    if (msg.contains('Checked Out Successfully!')) {
      return const Text.rich(
        TextSpan(
          children: [
            TextSpan(text: 'Checked Out ', style: TextStyle(fontWeight: FontWeight.w900)),
            TextSpan(text: 'Successfully!'),
          ],
        ),
        style: TextStyle(color: Colors.white, fontSize: 16),
      );
    }
    if (msg.contains('Checked In Successfully!')) {
      return const Text.rich(
        TextSpan(
          children: [
            TextSpan(text: 'Checked In ', style: TextStyle(fontWeight: FontWeight.w900)),
            TextSpan(text: 'Successfully!'),
          ],
        ),
        style: TextStyle(color: Colors.white, fontSize: 16),
      );
    }
    if (msg.contains('Already Checked In')) {
      return const Text.rich(
        TextSpan(
          children: [
            TextSpan(text: 'Already '),
            TextSpan(text: 'Checked In', style: TextStyle(fontWeight: FontWeight.w900)),
          ],
        ),
        style: TextStyle(color: Colors.white, fontSize: 16),
      );
    }
    if (msg.contains('Already Checked Out')) {
      return const Text.rich(
        TextSpan(
          children: [
            TextSpan(text: 'Already '),
            TextSpan(text: 'Checked Out', style: TextStyle(fontWeight: FontWeight.w900)),
          ],
        ),
        style: TextStyle(color: Colors.white, fontSize: 16),
      );
    }
    if (msg.toLowerCase().contains('invalid') || msg.toLowerCase().contains('unreadable')) {
      return const Text(
        'Invalid Badge',
        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
      );
    }
    if (msg.toLowerCase().contains('revoked') ||
        msg.toLowerCase().contains('denied') ||
        msg.toLowerCase().contains('blocked')) {
      return const Text(
        'Access Denied',
        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
      );
    }
    if (msg.toLowerCase().contains('expired')) {
      return const Text(
        'Badge Expired',
        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
      );
    }
    if (msg.toLowerCase().contains('wrong')) {
      return const Text(
        'Wrong Event',
        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
      );
    }
    return Text(
      msg.length > 30 ? '${msg.substring(0, 30)}...' : msg,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 16,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  Widget _buildHeaderSubtitle(String msg, String punchTime, {bool isNetworkErr = false}) {
    if (isNetworkErr || msg.toLowerCase().contains('saved offline')) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_done_outlined, size: 13, color: Colors.white),
          SizedBox(width: 4),
          Flexible(
            child: Text(
              'Saved to Offline Queue',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      );
    }
    if (punchTime.isNotEmpty &&
        (msg.contains('Already') ||
            msg.contains('Checked Out') ||
            msg.contains('Checked In') ||
            msg.contains('Limited'))) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.access_time_rounded, size: 13, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            punchTime,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }
    return Text(
      DateFormat('dd MMM yyyy hh:mm a').format(DateTime.now()),
      style: const TextStyle(
        color: Colors.white,
        fontSize: 12.5,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _buildAvatar(Attendee attendee) {
    final photoUrl = _resolvePhotoUrl(attendee.photoUrl);
    if (photoUrl != null) {
      return ClipOval(
        child: Image.network(
          photoUrl,
          width: 80,
          height: 80,
          fit: BoxFit.cover,
          errorBuilder: (ctx, err, stack) => _buildInitialsAvatar(attendee.initials),
          loadingBuilder: (ctx, child, progress) {
            if (progress == null) return child;
            return Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF171C26),
              ),
              child: const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white54,
                  ),
                ),
              ),
            );
          },
        ),
      );
    }
    return _buildInitialsAvatar(attendee.initials);
  }

  Widget _buildInitialsAvatar(String initials) {
    return Container(
      width: 80,
      height: 80,
      decoration: const BoxDecoration(
        color: Color(0xFF171C26), // colors.bg from AttendeeSheet.jsx
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          initials,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.0,
          ),
        ),
      ),
    );
  }

  Widget _buildChipTail(Attendee attendee) {
    final title = (attendee.category != null && attendee.category!.isNotEmpty)
        ? attendee.category!
        : attendee.badgeType;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: const BoxDecoration(
        color: Color(0xFF9D4AC5), // ChipTail.jsx #9D4AC5
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(4),
          bottomLeft: Radius.circular(4),
          topRight: Radius.circular(12),
          bottomRight: Radius.circular(12),
        ),
      ),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10.5,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }



  void _showAttendeeDetailsSheet(ScannerDecisionState decState) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetCtx).size.height * 0.85,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Sheet handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 6),
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  child: _buildDecisionCard(decState, isModal: true),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _toggleRushMode() async {
    HapticFeedback.mediumImpact();
    final nextState = !_isShortToast;
    try {
      await context.read<ScannerLocalStorage>().setShortToast(nextState);
    } catch (_) {}
    setState(() {
      _isShortToast = nextState;
      if (!nextState) {
        _currentToastDecision = null;
        _toastDismissTimer?.cancel();
      }
    });

    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                nextState ? Icons.bolt_rounded : Icons.pause_circle_outline_rounded,
                color: nextState ? Colors.amberAccent : Colors.white70,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  nextState
                      ? 'Rush Mode Enabled: Continuous fast scanning with brief notifications'
                      : 'Rush Mode Disabled: Full attendee card modal on each scan',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF1E2638),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 2000),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  Future<void> _enableOfflineMode() async {
    try {
      final storage = context.read<ScannerLocalStorage>();
      await storage.setOfflineMode(true);
      if (mounted) {
        context.read<ScannerBloc>().add(
              const ScannerConfigChanged(
                offlineModeEnabled: true,
              ),
            );
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.wifi_off_rounded, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Switched to Offline Mode. High-speed local validation active.',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFFE65100),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(milliseconds: 2500),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (_) {}
  }

  Widget _buildShortToastBanner(ScannerDecisionState decState) {
    Color alertColor;
    IconData alertIcon;
    final alertType = decState.response.alertType;
    final isSuccess = decState.response.isAlertSuccess;
    final isWarning = decState.response.isAlertWarning;

    final isNetworkErr = decState.isNetworkError ||
        decState.response.code == ScanDecisionCode.networkError ||
        alertType == 'network_error' ||
        decState.response.message.toLowerCase().contains('no internet') ||
        decState.response.message.toLowerCase().contains('saved offline') ||
        decState.response.message.toLowerCase().contains('network unreachable') ||
        decState.response.message.toLowerCase().contains('unable to reach server');

    if (isNetworkErr) {
      alertColor = const Color(0xFFFF8450); // Warning Orange
      alertIcon = Icons.wifi_off_rounded;
    } else if (alertType == 'success' || (alertType == null && isSuccess)) {
      alertColor = const Color(0xFF23A618); // #23A618 Vibrant Green
      alertIcon = decState.request.scanType.toLowerCase() == 'check_out'
          ? Icons.logout_rounded
          : Icons.check_circle_rounded;
    } else if (alertType == 'warning' || (alertType == null && isWarning)) {
      alertColor = const Color(0xFFFF8450); // Warning Orange
      alertIcon = Icons.warning_amber_rounded;
    } else if (alertType == 'info' || decState.response.isAlertInfo) {
      alertColor = const Color(0xFF00A0D2); // Info Sky Blue
      alertIcon = Icons.info_outline_rounded;
    } else {
      alertColor = const Color(0xFFFF4343); // Error Red
      alertIcon = Icons.error_outline_rounded;
    }

    final attendee = decState.response.attendee;
    final String name;
    final String subtitle;
    if (isNetworkErr) {
      name = 'SCAN SAVED OFFLINE';
      subtitle = 'No internet • Saved to queue for auto-sync';
    } else {
      name = attendee != null && attendee.fullName.trim().isNotEmpty
          ? attendee.fullName.toUpperCase()
          : (isSuccess ? 'ADMISSION GRANTED' : 'SCAN NOTIFICATION');
      final msg = decState.response.message;
      final punchTime = decState.response.punchTime ?? attendee?.punchTime;
      final formattedTime = _formatPunchTime(punchTime);
      subtitle = formattedTime.isNotEmpty ? '$msg • $formattedTime' : msg;
    }

    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          _showAttendeeDetailsSheet(decState);
        },
        child: Container(
          decoration: BoxDecoration(
            color: alertColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: alertColor.withValues(alpha: 0.45),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.28),
              width: 1.2,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Circular White Icon
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  width: 38,
                  height: 38,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Icon(alertIcon, size: 22, color: alertColor),
                  ),
                ),

                // Name & Status Subtitle
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.95),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (attendee?.category != null && attendee!.category!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.22),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              attendee.category!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                // Details Button
                Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Details',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, color: Colors.white, size: 16),
                    ],
                  ),
                ),

                // Close Button
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      setState(() {
                        _currentToastDecision = null;
                      });
                    },
                    borderRadius: BorderRadius.circular(50),
                    child: Container(
                      margin: const EdgeInsets.only(right: 10),
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 180.ms)
        .slideY(begin: -0.25, end: 0, duration: 200.ms, curve: Curves.easeOutQuad);
  }

  // ── 3. Floating Control Dock (SwitchBtn.jsx & InfraredBtn.jsx style) ─
  Widget _buildControlDock() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Mode Switch Button (White circular if in hardware mode, Magenta if in camera mode)
          InkWell(
            onTap: _toggleCamera,
            borderRadius: BorderRadius.circular(50),
            child: Container(
              height: 50,
              width: 50,
              decoration: BoxDecoration(
                color: _isCameraActive
                    ? AppTheme.eventxproAccent
                    : Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: (_isCameraActive
                            ? AppTheme.eventxproAccent
                            : Colors.white)
                        .withValues(alpha: 0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(
                _isCameraActive
                    ? Icons.qr_code_scanner_rounded
                    : Icons.videocam_rounded,
                color: _isCameraActive ? Colors.white : const Color(0xFF171C26),
                size: 24,
              ),
            ),
          ),

          // Camera controls: Flashlight & Switch Camera (only when camera is active)
          if (_isCameraActive && _cameraController != null) ...[
            const SizedBox(width: 14),

            // Flashlight / Torch Toggle
            InkWell(
              onTap: () {
                HapticFeedback.lightImpact();
                _cameraController?.toggleTorch();
                setState(() {
                  _isTorchOn = !_isTorchOn;
                });
              },
              borderRadius: BorderRadius.circular(50),
              child: Container(
                height: 50,
                width: 50,
                decoration: BoxDecoration(
                  color: _isTorchOn
                      ? Colors.amber.withValues(alpha: 0.25)
                      : const Color(0xFF222838),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _isTorchOn
                        ? Colors.amber
                        : Colors.white.withValues(alpha: 0.2),
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  _isTorchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                  size: 22,
                  color: _isTorchOn ? Colors.amberAccent : Colors.white70,
                ),
              ),
            ),

            const SizedBox(width: 14),

            // Flip Front/Back Camera
            InkWell(
              onTap: () {
                HapticFeedback.lightImpact();
                _cameraController?.switchCamera();
              },
              borderRadius: BorderRadius.circular(50),
              child: Container(
                height: 50,
                width: 50,
                decoration: BoxDecoration(
                  color: const Color(0xFF222838),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.2),
                    width: 1.5,
                  ),
                ),
                child: const Icon(
                  Icons.cameraswitch_rounded,
                  size: 22,
                  color: Colors.white70,
                ),
              ),
            ),
          ],

          const SizedBox(width: 14),

          // Rush Mode (Continuous Scanning) Fast Toggle Button
          Tooltip(
            message: _isShortToast
                ? 'Rush Mode (Continuous Scanning): ON'
                : 'Rush Mode: OFF (Tap to enable continuous scan)',
            child: InkWell(
              onTap: _toggleRushMode,
              borderRadius: BorderRadius.circular(50),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                height: 50,
                width: 50,
                decoration: BoxDecoration(
                  color: _isShortToast
                      ? Colors.amber.withValues(alpha: 0.22)
                      : const Color(0xFF222838),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _isShortToast
                        ? Colors.amberAccent
                        : Colors.white.withValues(alpha: 0.2),
                    width: 1.5,
                  ),
                  boxShadow: _isShortToast
                      ? [
                          BoxShadow(
                            color: Colors.amberAccent.withValues(alpha: 0.35),
                            blurRadius: 10,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
                child: Icon(
                  Icons.bolt_rounded,
                  size: 24,
                  color: _isShortToast ? Colors.amberAccent : Colors.white70,
                ),
              ),
            ),
          ),

          const SizedBox(width: 14),

          // Manual Ticket Code Input Button
          InkWell(
            onTap: _showManualEntrySheet,
            borderRadius: BorderRadius.circular(50),
            child: Container(
              height: 50,
              width: 50,
              decoration: BoxDecoration(
                color: const Color(0xFF222838),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.25),
                  width: 1.5,
                ),
              ),
              child: const Icon(
                Icons.keyboard_alt_outlined,
                size: 22,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 4. Telemetry Footer Bar ────────────────────────────────────────
  Widget _buildFooter() {
    final telemetry = widget.state.telemetry;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF141924),
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Accepted Scans Counter Pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppTheme.eventxproSuccess.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppTheme.eventxproSuccess.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.how_to_reg_rounded,
                  size: 14,
                  color: AppTheme.eventxproSuccess,
                ),
                const SizedBox(width: 5),
                Text(
                  '${telemetry.acceptedCount} Scanned',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.eventxproSuccess,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          // Gate Live Check-In & Check-Out Pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF202636),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'IN: ',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.eventxproSuccess,
                  ),
                ),
                Text(
                  '${_gateCount.checkIn}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'OUT: ',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.eventxproDanger,
                  ),
                ),
                Text(
                  '${_gateCount.checkOut}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),

          const Spacer(),

          // Gate Identifier Pill
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFF202636),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.12),
                ),
              ),
              child: Text(
                _resolveGateName(),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom painter for the 4 signature corner brackets on the scanner viewfinder.
class _CornerBracketPainter extends CustomPainter {
  final Color color;
  final double bracketLength;
  final double strokeWidth;

  const _CornerBracketPainter({
    required this.color,
    required this.bracketLength,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final w = size.width;
    final h = size.height;
    final l = bracketLength;

    // Top-Left
    canvas.drawLine(Offset(0, l), const Offset(0, 0), paint);
    canvas.drawLine(const Offset(0, 0), Offset(l, 0), paint);

    // Top-Right
    canvas.drawLine(Offset(w - l, 0), Offset(w, 0), paint);
    canvas.drawLine(Offset(w, 0), Offset(w, l), paint);

    // Bottom-Left
    canvas.drawLine(Offset(0, h - l), Offset(0, h), paint);
    canvas.drawLine(Offset(0, h), Offset(l, h), paint);

    // Bottom-Right
    canvas.drawLine(Offset(w - l, h), Offset(w, h), paint);
    canvas.drawLine(Offset(w, h), Offset(w, h - l), paint);
  }

  @override
  bool shouldRepaint(covariant _CornerBracketPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.bracketLength != bracketLength ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
