import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/services/audio_feedback_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/adapters/enterprise_hardware_adapter.dart';
import '../../../data/datasources/lead_remote_datasource.dart';
import '../../../data/datasources/scanner_local_storage.dart';
import '../../../data/models/lead_model.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/lead_repository.dart';
import '../../bloc/scanner_bloc.dart';
import '../../bloc/scanner_event.dart';
import 'lead_info_screen.dart';
import 'leads_list_screen.dart';
import 'widgets/lead_captured_modal_sheet.dart';

/// Flagship Lead Capture Scanner Screen for EventXPro exhibitors and organizers.
/// Adopts the authentic EventXPro check-in scanner UI design system:
/// - EventTopBar with circular white back button and centered event badge
/// - 270x270 Viewfinder with 4 signature corner brackets, sweeping laser beam, and hardware pulse artwork
/// - Dual hardware broadcast scanning (Honeywell ScanPal EDA51 & Zebra TC15/TC21) and camera scanning
/// - Authoritative Lead Decision Card with instant rating selector (Hot/Warm/Cold)
/// - Continuous scanning (Rush Mode) with top-floating notification toast
/// - Control dock with mode switcher, flashlight, camera flip, and rush mode
class LeadCaptureScreen extends StatefulWidget {
  final int? eventId;
  final String? eventName;
  final bool isRootTab;
  final bool isActive;
  final VoidCallback? onOpenLeads;

  const LeadCaptureScreen({
    super.key,
    this.eventId,
    this.eventName,
    this.isRootTab = false,
    this.isActive = true,
    this.onOpenLeads,
  });

  @override
  State<LeadCaptureScreen> createState() => _LeadCaptureScreenState();
}

class _LeadCaptureScreenState extends State<LeadCaptureScreen>
    with TickerProviderStateMixin {
  late final EnterpriseHardwareAdapter _hardwareAdapter;
  StreamSubscription<String>? _hardwareSubscription;
  MobileScannerController? _cameraController;

  late AnimationController _laserController;
  late Animation<double> _laserAnimation;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  bool _isCameraMode = false;
  bool _isTorchOn = false;
  bool _isShortToast = false;
  bool _isProcessing = false;
  bool _hasCapturedAny = false;
  bool _hasLoadedPrefs = false;
  bool _isUpdatingRating = false;

  int _capturedCount = 0;
  String? _lastScannedCode;
  DateTime? _lastScanTime;

  LeadModel? _decisionLead;
  String? _errorMessage;

  LeadModel? _toastLead;
  String? _toastError;
  Timer? _toastTimer;

  @override
  void initState() {
    super.initState();

    // Laser sweeps up and down
    _laserController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    );

    _laserAnimation = Tween<double>(begin: 0.05, end: 0.95).animate(
      CurvedAnimation(parent: _laserController, curve: Curves.easeInOut),
    );

    // Hardware Scanner radar pulse rings
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );

    _pulseAnimation = CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeOut,
    );

    // Initialize dedicated enterprise hardware adapter (Honeywell + Zebra)
    _hardwareAdapter = EnterpriseHardwareAdapter();
    _initHardwareScanner();

    if (widget.isActive) {
      _laserController.repeat(reverse: true);
      _pulseController.repeat();
      // Pause global gate check-in scanner while in lead capture mode
      try {
        context.read<ScannerBloc>().add(const ScannerScanningPaused());
      } catch (_) {}
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_hasLoadedPrefs) {
      _hasLoadedPrefs = true;
      try {
        final storage = context.read<ScannerLocalStorage>();
        _isCameraMode = storage.isCameraEnabled;
        _isShortToast = storage.isShortToastEnabled;
        if (_isCameraMode && widget.isActive) {
          _initCamera();
        }
      } catch (_) {}
    }
  }

  @override
  void didUpdateWidget(covariant LeadCaptureScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) {
      if (widget.isActive) {
        _onActivated();
      } else {
        _onDeactivated();
      }
    }
  }

  void _onActivated() {
    try {
      context.read<ScannerBloc>().add(const ScannerScanningPaused());
    } catch (_) {}

    _laserController.repeat(reverse: true);
    _pulseController.repeat();

    if (_isCameraMode) {
      if (_cameraController == null) {
        _initCamera();
      } else {
        _cameraController?.start();
      }
    }
  }

  void _onDeactivated() {
    try {
      context.read<ScannerBloc>().add(const ScannerScanningResumed());
    } catch (_) {}

    _laserController.stop();
    _pulseController.stop();

    _isTorchOn = false;
    _cameraController?.stop();
  }

  Future<void> _initHardwareScanner() async {
    await _hardwareAdapter.initialize();
    _hardwareSubscription =
        _hardwareAdapter.scanStream.listen(_onBarcodeDecoded);
  }

  void _initCamera() {
    _cameraController ??= MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
  }

  @override
  void dispose() {
    _laserController.dispose();
    _pulseController.dispose();
    _toastTimer?.cancel();
    _hardwareSubscription?.cancel();
    _hardwareAdapter.dispose();
    _cameraController?.dispose();

    // Resume global gate check-in scanner if was active
    if (widget.isActive) {
      try {
        context.read<ScannerBloc>().add(const ScannerScanningResumed());
      } catch (_) {}
    }

    super.dispose();
  }

  void _toggleScannerMode() {
    HapticFeedback.lightImpact();
    setState(() {
      _isCameraMode = !_isCameraMode;
      if (_isCameraMode) {
        _initCamera();
      } else {
        _cameraController?.dispose();
        _cameraController = null;
        _isTorchOn = false;
      }
    });
    try {
      context.read<ScannerLocalStorage>().setCameraEnabled(_isCameraMode);
    } catch (_) {}
  }

  void _toggleRushMode() {
    HapticFeedback.lightImpact();
    setState(() {
      _isShortToast = !_isShortToast;
      if (!_isShortToast) {
        _toastLead = null;
        _toastError = null;
        _toastTimer?.cancel();
      }
    });
    try {
      context.read<ScannerLocalStorage>().setShortToast(_isShortToast);
    } catch (_) {}
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isShortToast
              ? 'Rush Mode Activated: Continuous scanning with quick floating toasts'
              : 'Standard Mode: Detailed lead review cards enabled',
        ),
        backgroundColor:
            _isShortToast ? const Color(0xFFD97706) : AppTheme.eventxproAccent,
        duration: const Duration(milliseconds: 1600),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _toggleTorch() async {
    if (_cameraController == null) return;
    HapticFeedback.lightImpact();
    try {
      await _cameraController!.toggleTorch();
      setState(() {
        _isTorchOn = !_isTorchOn;
      });
    } catch (_) {}
  }

  Future<void> _switchCamera() async {
    if (_cameraController == null) return;
    HapticFeedback.lightImpact();
    try {
      await _cameraController!.switchCamera();
    } catch (_) {}
  }

  Future<void> _onBarcodeDecoded(String rawCode) async {
    final code = rawCode.trim();
    if (code.isEmpty || _isProcessing) return;

    final now = DateTime.now();
    if (_lastScannedCode == code &&
        _lastScanTime != null &&
        now.difference(_lastScanTime!).inMilliseconds < 1800) {
      return; // Ignore duplicate bounces
    }

    _lastScannedCode = code;
    _lastScanTime = now;

    HapticFeedback.lightImpact();

    setState(() {
      _isProcessing = true;
      if (!_isShortToast) {
        _decisionLead = null;
        _errorMessage = null;
      }
    });

    try {
      final repository = context.read<LeadRepository>();
      final LeadCaptureResult result = await repository.captureLead(
        uniqueId: code,
        scanType: 0,
      );

      if (!mounted) return;

      if (result.isSuccess && result.lead != null) {
        _hasCapturedAny = true;
        _capturedCount++;
        await AudioFeedbackService().playTone(AudioTone.success);

        if (_isShortToast) {
          setState(() {
            _toastLead = result.lead;
            _toastError = null;
          });
          _startToastTimer();
        } else {
          setState(() {
            _decisionLead = result.lead;
            _errorMessage = null;
          });
        }
      } else {
        await AudioFeedbackService().playTone(AudioTone.error);
        final err = result.message ?? 'Lead capture failed for token: $code';
        if (_isShortToast) {
          setState(() {
            _toastLead = null;
            _toastError = err;
          });
          _startToastTimer();
        } else {
          setState(() {
            _decisionLead = null;
            _errorMessage = err;
          });
        }
      }
    } catch (e) {
      await AudioFeedbackService().playTone(AudioTone.error);
      final err = 'Error capturing lead: $e';
      if (_isShortToast) {
        setState(() {
          _toastLead = null;
          _toastError = err;
        });
        _startToastTimer();
      } else {
        setState(() {
          _decisionLead = null;
          _errorMessage = err;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  void _startToastTimer() {
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(milliseconds: 2600), () {
      if (mounted) {
        setState(() {
          _toastLead = null;
          _toastError = null;
        });
      }
    });
  }

  void _resetToReady() {
    HapticFeedback.lightImpact();
    setState(() {
      _decisionLead = null;
      _errorMessage = null;
      _isProcessing = false;
    });
  }

  Future<void> _updateLeadRating(String type) async {
    if (_decisionLead == null ||
        _decisionLead!.leadType == type ||
        _isUpdatingRating) {
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => _isUpdatingRating = true);

    final leadRepo = context.read<LeadRepository>();
    final success = await leadRepo.updateLead(
      id: _decisionLead!.id,
      leadType: type,
      notes: _decisionLead!.notes ?? '',
    );

    if (mounted) {
      setState(() => _isUpdatingRating = false);
      if (success) {
        final updated = _decisionLead!.copyWith(leadType: type);
        setState(() {
          _decisionLead = updated;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lead marked as $type'),
            backgroundColor: AppTheme.eventxproSuccess,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 1),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update lead rating'),
            backgroundColor: AppTheme.eventxproDanger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showLeadDetailsModal(LeadModel lead) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => LeadCapturedModalSheet(
        lead: lead,
        onDismiss: () => Navigator.of(ctx).pop(),
        onLeadUpdated: (updated) {
          if (mounted) {
            setState(() {
              if (_decisionLead?.id == updated.id) {
                _decisionLead = updated;
              }
              if (_toastLead?.id == updated.id) {
                _toastLead = updated;
              }
            });
          }
        },
      ),
    );
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
    return 'EventXPro Leads';
  }

  String? _resolveAvatarUrl(String? photo) {
    if (photo == null || photo.trim().isEmpty) return null;
    final cleanPhoto = photo.trim();
    if (cleanPhoto.startsWith('http://') || cleanPhoto.startsWith('https://')) {
      return cleanPhoto;
    }
    try {
      final mediaUrl = context.read<AuthRepository>().mediaUrl;
      final cleanMedia = mediaUrl.endsWith('/')
          ? mediaUrl.substring(0, mediaUrl.length - 1)
          : mediaUrl;
      final cleanPath = cleanPhoto.startsWith('/') ? cleanPhoto : '/$cleanPhoto';
      return '$cleanMedia$cleanPath';
    } catch (_) {
      return null;
    }
  }



  @override
  Widget build(BuildContext context) {
    final topBannerOffset = MediaQuery.of(context).padding.top + 70.0;
    final hasToast =
        _isShortToast && (_toastLead != null || _toastError != null);

    return Scaffold(
      backgroundColor: AppTheme.eventxproBg,
      body: Stack(
        children: [
          // ── Main Content Layout ────────────────────────────────────
          SafeArea(
            bottom: !widget.isRootTab,
            child: Column(
              children: [
                // Top Bar (Matching React Native EventTopBar.jsx)
                _buildEventTopBar(),

                // Main Body (Viewfinder / Processing / Decision Card)
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 8),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: _buildBody(),
                      ),
                    ),
                  ),
                ),

                // Bottom Dock: Mode switch, flashlight, flip, rush mode
                _buildControlDock(),

                // Sleek Telemetry Footer
                _buildFooter(),
              ],
            ),
          ),

          // ── Short Toast Floating Notification (Rush Mode) ──────────
          if (hasToast)
            Positioned(
              top: topBannerOffset,
              left: 16,
              right: 16,
              child: _buildShortToastBanner(),
            ),
        ],
      ),
      bottomNavigationBar: widget.isRootTab ? null : _buildStandaloneBottomBar(),
    );
  }

  // ── 1. EventTopBar (Matching SimpleScannerView) ─────────────────────
  Widget _buildEventTopBar() {
    final eventName = _resolveEventName();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Circular White Back Button (hidden if root tab to maintain centered title)
          if (!widget.isRootTab)
            InkWell(
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.of(context).pop(_hasCapturedAny);
              },
              borderRadius: BorderRadius.circular(50),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 6,
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
            )
          else
            const SizedBox(width: 40, height: 40),

          const SizedBox(width: 14),

          // Centered Gate Title & Event Name
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text.rich(
                  const TextSpan(
                    style: TextStyle(
                      fontFamily: 'Segoe UI',
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                    children: [
                      TextSpan(text: 'Lead '),
                      TextSpan(
                        text: 'Capture',
                        style: TextStyle(
                          color: AppTheme.eventxproAccent,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),

                // Subtitle: Calendar icon + Event Name
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

          // Action: Leads List Shortcut
          InkWell(
            onTap: () async {
              HapticFeedback.lightImpact();
              if (widget.onOpenLeads != null) {
                widget.onOpenLeads!();
              } else {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => LeadsListScreen(
                      eventId: widget.eventId,
                      eventName: widget.eventName,
                    ),
                  ),
                );
              }
            },
            borderRadius: BorderRadius.circular(50),
            child: Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: Color(0xFF212836),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.list_alt_rounded,
                size: 18,
                color: Colors.white70,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 2. Main Body (State-driven) ─────────────────────────────────────
  Widget _buildBody() {
    if (_isProcessing && !_isShortToast) {
      return _buildProcessingCard();
    }

    if ((_decisionLead != null || _errorMessage != null) && !_isShortToast) {
      return _buildDecisionCard();
    }

    // Default: Ready Viewfinder (stays continuously active if _isShortToast is true)
    return _buildReadyViewfinder();
  }

  // ── 2A. Ready Viewfinder (Hardware vs Camera) ───────────────────────
  Widget _buildReadyViewfinder() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Headline guidance
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
            'Position your phone to make sure the attendee QR code is within the frame',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              color: Color(0xFFAFAFAF),
              height: 1.3,
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Viewfinder Frame
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
                  if (_isCameraMode && _cameraController != null)
                    MobileScanner(
                      controller: _cameraController!,
                      onDetect: (BarcodeCapture capture) {
                        if (_isProcessing) return;
                        for (final barcode in capture.barcodes) {
                          final rawVal = barcode.rawValue?.trim();
                          if (rawVal != null && rawVal.isNotEmpty) {
                            _onBarcodeDecoded(rawVal);
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

                  // 4 Signature Corner Brackets (Magenta Accent)
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

                  // Animated Sweeping Laser Beam
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
                                        color: AppTheme.eventxproAccent
                                            .withValues(alpha: 0.9),
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
                  color: _isCameraMode
                      ? AppTheme.accentCyan
                      : AppTheme.statusSuccess,
                  boxShadow: [
                    BoxShadow(
                      color: _isCameraMode
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
                _isCameraMode
                    ? 'Phone Camera Active'
                    : 'Hardware Scanner Ready',
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

  /// Artwork shown when Zebra/Honeywell OEM Hardware Scanner is active
  Widget _buildHardwareScannerArtwork() {
    return RepaintBoundary(
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Animated Pulse Rings
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

          // Subtle Watermark QR Icon in center
          Icon(
            Icons.qr_code_2_rounded,
            size: 100,
            color: Colors.white.withValues(alpha: 0.08),
          ),

          // Center Target Crosshair Graphic
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

  // ── 2B. In-Flight Processing Card ───────────────────────────────────
  Widget _buildProcessingCard() {
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
              valueColor:
                  AlwaysStoppedAnimation<Color>(AppTheme.eventxproAccent),
            ),
          ),
          const SizedBox(height: 22),
          const Text(
            'CAPTURING ATTENDEE LEAD...',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.0,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Token: ${_lastScannedCode ?? '...'}',
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

  // ── 2C. Authoritative Lead Decision Card ────────────────────────────
  Widget _buildDecisionCard() {
    final isSuccess = _decisionLead != null;
    final headerColor =
        isSuccess ? const Color(0xFF23A618) : const Color(0xFFFF4343);
    final iconData =
        isSuccess ? Icons.check_circle_rounded : Icons.error_outline_rounded;
    final lead = _decisionLead;

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
          // ── Top Header Bar (Matching AttendeeSheet.jsx) ──
          Container(
            color: headerColor,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Circular White Background ('okBg')
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
                      Text(
                        isSuccess ? 'LEAD CAPTURED' : 'CAPTURE REJECTED',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        DateFormat('dd MMM yyyy • hh:mm a')
                            .format(DateTime.now()),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),

                // Circular Close Button
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _resetToReady,
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

          // ── Card Content Body ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isSuccess && lead != null) ...[
                  // Profile Row: Avatar + Details
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildAvatar(lead),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              lead.fullName.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 16.5,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF111827),
                                letterSpacing: 0.3,
                              ),
                            ),
                            if (lead.companyName != null &&
                                lead.companyName!.trim().isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                lead.companyName!,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF4B5563),
                                ),
                              ),
                            ],
                            if (lead.designation != null &&
                                lead.designation!.trim().isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                lead.designation!,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w400,
                                  color: Color(0xFF6B7280),
                                ),
                              ),
                            ],
                            const SizedBox(height: 6),
                            _buildChipTail(lead.ticketType ?? 'Lead Attendee'),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Interactive Quick Rating Selector (Hot, Warm, Cold)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9FAFB),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.label_outline_rounded,
                                size: 14, color: Color(0xFF6B7280)),
                            SizedBox(width: 6),
                            Text(
                              'Rate this Lead',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF4B5563),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _buildRatingPill(
                                label: 'HOT',
                                icon: Icons.whatshot_rounded,
                                isSelected: lead.leadType == 'HOT',
                                activeColor: const Color(0xFFEF4444),
                                onTap: () => _updateLeadRating('HOT'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildRatingPill(
                                label: 'WARM',
                                icon: Icons.wb_sunny_rounded,
                                isSelected: lead.leadType == 'WARM',
                                activeColor: const Color(0xFFF59E0B),
                                onTap: () => _updateLeadRating('WARM'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildRatingPill(
                                label: 'COLD',
                                icon: Icons.ac_unit_rounded,
                                isSelected: lead.leadType == 'COLD',
                                activeColor: const Color(0xFF3B82F6),
                                onTap: () => _updateLeadRating('COLD'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Quick Contact Pills (if available)
                  if ((lead.mobile != null && lead.mobile!.isNotEmpty) ||
                      (lead.email != null && lead.email!.isNotEmpty)) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        if (lead.mobile != null && lead.mobile!.isNotEmpty)
                          _buildContactPill(
                            icon: Icons.phone_rounded,
                            text: lead.mobile!,
                          ),
                        if (lead.email != null && lead.email!.isNotEmpty)
                          _buildContactPill(
                            icon: Icons.mail_outline_rounded,
                            text: lead.email!,
                          ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 16),

                  // Action: View & Edit Full Lead Info Button
                  SizedBox(
                    width: double.infinity,
                    height: 42,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final updated = await Navigator.push<LeadModel>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => LeadInfoScreen(lead: lead),
                          ),
                        );
                        if (mounted && updated != null) {
                          setState(() => _decisionLead = updated);
                        }
                      },
                      icon: const Icon(Icons.edit_note_rounded,
                          size: 18, color: Color(0xFF4B5563)),
                      label: const Text(
                        'View & Edit Notes / Details',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF374151),
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFD1D5DB)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ] else ...[
                  // Error details
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: Text(
                        _errorMessage ?? 'Unable to capture attendee lead',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFDC2626),
                          height: 1.3,
                        ),
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 14),

                // Ready For Next Attendee Button
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton.icon(
                    onPressed: _resetToReady,
                    icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                    label: const Text(
                      'Ready For Next Lead',
                      style: TextStyle(
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
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 180.ms).scale(begin: const Offset(0.92, 0.92));
  }

  Widget _buildAvatar(LeadModel lead) {
    final photoUrl = _resolveAvatarUrl(lead.photo);
    if (photoUrl != null) {
      return ClipOval(
        child: Image.network(
          photoUrl,
          width: 76,
          height: 76,
          fit: BoxFit.cover,
          errorBuilder: (ctx, err, stack) =>
              _buildInitialsAvatar(lead.initials),
          loadingBuilder: (ctx, child, progress) {
            if (progress == null) return child;
            return Container(
              width: 76,
              height: 76,
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
    return _buildInitialsAvatar(lead.initials);
  }

  Widget _buildInitialsAvatar(String initials) {
    return Container(
      width: 76,
      height: 76,
      decoration: const BoxDecoration(
        color: Color(0xFF171C26),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          initials,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.0,
          ),
        ),
      ),
    );
  }

  Widget _buildChipTail(String category) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: const BoxDecoration(
        color: Color(0xFF9D4AC5),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(4),
          bottomLeft: Radius.circular(4),
          topRight: Radius.circular(12),
          bottomRight: Radius.circular(12),
        ),
      ),
      child: Text(
        category.toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildRatingPill({
    required String label,
    required IconData icon,
    required bool isSelected,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        decoration: BoxDecoration(
          color: isSelected ? activeColor : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? activeColor : const Color(0xFFD1D5DB),
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: activeColor.withValues(alpha: 0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 13,
              color: isSelected ? Colors.white : const Color(0xFF6B7280),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: isSelected ? Colors.white : const Color(0xFF374151),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactPill({required IconData icon, required String text}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: const Color(0xFF6B7280)),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF374151),
            ),
          ),
        ],
      ),
    );
  }

  // ── 3. Floating Control Dock ─────────────────────────────────────────
  Widget _buildControlDock() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Mode Switch Button (White circular if in hardware mode, Magenta if in camera mode)
          InkWell(
            onTap: _toggleScannerMode,
            borderRadius: BorderRadius.circular(50),
            child: Container(
              height: 50,
              width: 50,
              decoration: BoxDecoration(
                color: _isCameraMode
                    ? AppTheme.eventxproAccent
                    : Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: (_isCameraMode
                            ? AppTheme.eventxproAccent
                            : Colors.white)
                        .withValues(alpha: 0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(
                _isCameraMode
                    ? Icons.qr_code_scanner_rounded
                    : Icons.videocam_rounded,
                color: _isCameraMode ? Colors.white : const Color(0xFF171C26),
                size: 24,
              ),
            ),
          ),

          // Camera controls: Flashlight & Switch Camera (only when camera is active)
          if (_isCameraMode && _cameraController != null) ...[
            const SizedBox(width: 14),

            // Flashlight / Torch Toggle
            InkWell(
              onTap: _toggleTorch,
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
              onTap: _switchCamera,
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
        ],
      ),
    );
  }

  // ── 4. Telemetry Footer Bar ──────────────────────────────────────────
  Widget _buildFooter() {
    final eventName = _resolveEventName();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF141924),
      ),
      child: Row(
        children: [
          // Captured Leads Counter Pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppTheme.eventxproSuccess.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
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
                  '$_capturedCount Captured',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.eventxproSuccess,
                  ),
                ),
              ],
            ),
          ),

          const Spacer(),

          // Event Identifier Pill
          Flexible(
            child: InkWell(
              onTap: () {
                if (widget.onOpenLeads != null) {
                  widget.onOpenLeads!();
                } else {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => LeadsListScreen(
                        eventId: widget.eventId,
                        eventName: widget.eventName,
                      ),
                    ),
                  );
                }
              },
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF202636),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.people_alt_rounded,
                      size: 13,
                      color: AppTheme.accentCyan,
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        eventName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.white70,
                        ),
                      ),
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

  // ── 5. Short Toast Floating Notification (Rush Mode) ────────────────
  Widget _buildShortToastBanner() {
    final isError = _toastError != null;
    final alertColor =
        isError ? const Color(0xFFFF4343) : const Color(0xFF23A618);
    final alertIcon =
        isError ? Icons.error_outline_rounded : Icons.check_circle_rounded;
    final name = isError
        ? 'CAPTURE REJECTED'
        : (_toastLead?.fullName.toUpperCase() ?? 'LEAD CAPTURED');
    final subtitle = isError
        ? _toastError!
        : '${_toastLead?.companyName ?? 'Attendee'} • Lead Captured';

    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        onTap: () {
          if (_toastLead != null) {
            _showLeadDetailsModal(_toastLead!);
          }
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
                  margin:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Trailing Details Arrow
                if (!isError)
                  const Padding(
                    padding: EdgeInsets.only(right: 14),
                    child: Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 15,
                      color: Colors.white70,
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
        .slideY(
            begin: -0.25, end: 0, duration: 200.ms, curve: Curves.easeOutQuad);
  }

  Widget _buildStandaloneBottomBar() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF10141E).withValues(alpha: 0.98),
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 20,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStandaloneNavItem(
                icon: Icons.home_outlined,
                activeIcon: Icons.home_rounded,
                label: 'Home',
                isSelected: false,
                onTap: () {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
              ),
              _buildStandaloneNavItem(
                icon: Icons.qr_code_scanner_outlined,
                activeIcon: Icons.qr_code_scanner_rounded,
                label: 'Scan Lead',
                isSelected: true,
                onTap: () {},
              ),
              _buildStandaloneNavItem(
                icon: Icons.badge_outlined,
                activeIcon: Icons.badge_rounded,
                label: 'Leads',
                isSelected: false,
                onTap: () {
                  if (widget.onOpenLeads != null) {
                    widget.onOpenLeads!();
                  } else {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => LeadsListScreen(
                          eventId: widget.eventId,
                          eventName: widget.eventName,
                        ),
                      ),
                    );
                  }
                },
              ),
              _buildStandaloneNavItem(
                icon: Icons.settings_outlined,
                activeIcon: Icons.settings_rounded,
                label: 'Settings',
                isSelected: false,
                onTap: () {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStandaloneNavItem({
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final activeColor = AppTheme.brandGradientStart;
    final inactiveColor = Colors.white.withValues(alpha: 0.42);

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkResponse(
          onTap: onTap,
          containedInkWell: true,
          highlightShape: BoxShape.rectangle,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isSelected ? activeIcon : icon,
                  size: 22,
                  color: isSelected ? activeColor : inactiveColor,
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isSelected ? Colors.white : inactiveColor,
                    fontSize: isSelected ? 11 : 10.5,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
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
