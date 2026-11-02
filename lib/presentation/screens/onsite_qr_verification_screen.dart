import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../core/config/app_constants.dart';
import '../../core/network/api_client.dart';
import '../../core/services/device_detection_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/app_toast.dart';
import '../../data/adapters/enterprise_hardware_adapter.dart';
import '../../data/datasources/auth_local_storage.dart';
import '../../data/datasources/qr_verification_remote_datasource.dart';
import '../../data/datasources/scanner_local_storage.dart';
import '../../data/models/onsite_coupon_details_model.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/qr_verification_repository_impl.dart';
import '../../domain/adapters/i_hardware_scanner_adapter.dart';
import '../../domain/repositories/i_qr_verification_repository.dart';
import '../bloc/onsite_verification/onsite_verification_bloc.dart';
import '../bloc/onsite_verification/onsite_verification_event.dart';
import '../bloc/onsite_verification/onsite_verification_state.dart';
import '../bloc/scanner_bloc.dart';
import '../bloc/scanner_event.dart';
import '../widgets/app_background_layer.dart';
import '../widgets/onsite_qr_info_bottom_sheet.dart';

/// Screen for on-site voucher / coupon QR verification adopting EventXPro's
/// signature check-in scanner UI design language:
/// - EventTopBar with circular white back button and centered event badge
/// - 270x270 Viewfinder with 4 signature corner brackets, sweeping laser beam, and hardware pulse artwork
/// - Dual enterprise hardware barcode listening and MobileScanner
/// - Floating control dock with camera/hardware switcher, torch toggle, camera flip, and manual entry
/// - On-site coupon redemption modal sheet (`OnsiteQrInfoBottomSheet`)
class OnsiteQrVerificationScreen extends StatefulWidget {
  final int eventId;
  final String eventName;
  final IQrVerificationRepository? repository;
  final OnsiteVerificationBloc? bloc;

  const OnsiteQrVerificationScreen({
    super.key,
    required this.eventId,
    required this.eventName,
    this.repository,
    this.bloc,
  });

  @override
  State<OnsiteQrVerificationScreen> createState() =>
      _OnsiteQrVerificationScreenState();
}

class _OnsiteQrVerificationScreenState extends State<OnsiteQrVerificationScreen>
    with TickerProviderStateMixin {
  late final OnsiteVerificationBloc _bloc;
  MobileScannerController? _cameraController;
  HardwareScannerAdapter? _hardwareAdapter;
  StreamSubscription<String>? _hardwareScanSub;
  bool _isInternalAdapter = false;

  late final AnimationController _laserController;
  late final Animation<double> _laserAnimation;

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  bool _isCameraActive = true;
  bool _isTorchOn = false;
  String? _lastScannedCode;
  bool _isSheetOpen = false;
  OnsiteCouponModel? _currentCouponDetails;
  StateSetter? _sheetSetState;

  @override
  void initState() {
    super.initState();

    // 1. Sweeping Laser Beam Animation
    _laserController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    )..repeat(reverse: true);

    _laserAnimation = Tween<double>(begin: 0.05, end: 0.95).animate(
      CurvedAnimation(parent: _laserController, curve: Curves.easeInOut),
    );

    // 2. Hardware Scanner Radar Pulse Rings
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();

    _pulseAnimation = CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeOut,
    );

    // 3. Resolve Repository
    IQrVerificationRepository repository;
    if (widget.repository != null) {
      repository = widget.repository!;
    } else {
      final apiClient = context.read<ApiClient>();
      final remoteDatasource =
          QrVerificationRemoteDatasource(apiClient: apiClient);
      repository =
          QrVerificationRepositoryImpl(remoteDatasource: remoteDatasource);
    }

    // 4. Resolve Initial Camera Preference
    try {
      final storage = context.read<ScannerLocalStorage>();
      final info = DeviceDetectionService().cachedInfo;
      if (info != null && info.isHardwareScannerCapable) {
        _isCameraActive = storage.isCameraEnabled;
      } else {
        _isCameraActive = true;
      }
    } catch (_) {
      _isCameraActive = true;
    }

    _bloc = widget.bloc ??
        OnsiteVerificationBloc(
          repository: repository,
          initialCameraActive: _isCameraActive,
        );

    final isTest = Platform.environment.containsKey('FLUTTER_TEST');
    if (_isCameraActive && !isTest) {
      _initCamera();
    }

    // 5. Pause global gate check-in scanner while in on-site verification screen
    try {
      context.read<ScannerBloc>().add(const ScannerScanningPaused());
    } catch (_) {}

    // 6. Initialize Hardware Scanner
    _initHardwareScanner();
  }

  void _initCamera() {
    _cameraController ??= MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
  }

  void _initHardwareScanner() {
    try {
      try {
        _hardwareAdapter = context.read<HardwareScannerAdapter>();
        _isInternalAdapter = false;
      } catch (_) {
        _hardwareAdapter = EnterpriseHardwareAdapter();
        _isInternalAdapter = true;
      }

      if (_hardwareAdapter != null) {
        _hardwareAdapter!.initialize();
        _hardwareScanSub = _hardwareAdapter!.scanStream.listen(_onScanned);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    // Resume global gate scanner if active
    try {
      context.read<ScannerBloc>().add(const ScannerScanningResumed());
    } catch (_) {}

    _laserController.dispose();
    _pulseController.dispose();
    _hardwareScanSub?.cancel();
    if (_isInternalAdapter) {
      _hardwareAdapter?.dispose();
    }
    _cameraController?.dispose();
    if (widget.bloc == null) {
      _bloc.close();
    }
    super.dispose();
  }

  void _toggleCamera() {
    HapticFeedback.lightImpact();
    AppToast.dismissAll();
    final wasActive = _isCameraActive;
    final next = !wasActive;

    setState(() {
      _isCameraActive = next;
      _isTorchOn = false;
      if (next && !Platform.environment.containsKey('FLUTTER_TEST')) {
        _initCamera();
      } else {
        _cameraController?.dispose();
        _cameraController = null;
      }
    });

    _bloc.add(const ToggleOnsiteCameraMode());

    try {
      context.read<ScannerLocalStorage>().setCameraEnabled(next);
    } catch (_) {}
  }

  void _toggleTorch() {
    HapticFeedback.lightImpact();
    _cameraController?.toggleTorch();
    setState(() {
      _isTorchOn = !_isTorchOn;
    });
  }

  void _switchCamera() {
    HapticFeedback.lightImpact();
    _cameraController?.switchCamera();
  }

  void _onScanned(String rawCode) {
    final code = rawCode.trim();
    if (code.isEmpty) return;

    if (_bloc.state is OnsiteVerificationLoading) {
      return;
    }

    // Suppress repetitive scanning of same coupon: only scan once until another code is scanned
    if (_lastScannedCode == code) {
      return;
    }

    _lastScannedCode = code;

    AppToast.dismissAll();
    _bloc.add(ScanCouponQr(code));
  }

  void _showCouponSheet(OnsiteCouponModel couponDetails) {
    _currentCouponDetails = couponDetails;

    // Continuous scanning: if sheet is already open, live-update its content
    if (_isSheetOpen) {
      _sheetSetState?.call(() {});
      return;
    }

    String mediaUrl = AppConstants.defaultBaseUrl;
    try {
      mediaUrl = context.read<AuthRepository>().baseUrl;
    } catch (_) {
      try {
        mediaUrl = context.read<AuthLocalStorage>().getBaseUrl();
      } catch (_) {}
    }

    _isSheetOpen = true;

    try {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        enableDrag: true,
        builder: (sheetCtx) {
          return StatefulBuilder(
            builder: (ctx, setSheetState) {
              _sheetSetState = setSheetState;
              final activeDetails = _currentCouponDetails ?? couponDetails;
              return OnsiteQrInfoBottomSheet(
                data: activeDetails,
                mediaBaseUrl: mediaUrl,
                onClose: () {
                  Navigator.of(sheetCtx).pop();
                },
              );
            },
          );
        },
      ).whenComplete(() {
        _isSheetOpen = false;
        _sheetSetState = null;
        _currentCouponDetails = null;
        _bloc.add(const ResetOnsiteScanner());
      });
    } catch (e) {
      _isSheetOpen = false;
      _sheetSetState = null;
      _currentCouponDetails = null;
      _bloc.add(const ResetOnsiteScanner());
    }
  }

  void _showManualEntryDialog() {
    HapticFeedback.lightImpact();
    final textController = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2536),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.15),
            width: 1.2,
          ),
        ),
        title: const Row(
          children: [
            Icon(
              Icons.keyboard_alt_outlined,
              color: AppTheme.eventxproAccent,
              size: 22,
            ),
            SizedBox(width: 10),
            Text(
              'Enter Coupon Code',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Type or paste the attendee coupon / voucher code to verify redemption details:',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: textController,
              autofocus: true,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
              decoration: InputDecoration(
                hintText: 'e.g. COUPON-108 or Voucher Code',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF0F141E),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: AppTheme.eventxproAccent,
                    width: 1.5,
                  ),
                ),
              ),
              onSubmitted: (val) {
                if (val.trim().isNotEmpty) {
                  Navigator.of(dialogCtx).pop();
                  _onScanned(val.trim());
                }
              },
            ),
          ],
        ),
        actionsPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.eventxproAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () {
              final val = textController.text.trim();
              if (val.isNotEmpty) {
                Navigator.of(dialogCtx).pop();
                _onScanned(val);
              }
            },
            child: const Text(
              'Verify Coupon',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<OnsiteVerificationBloc>.value(
      value: _bloc,
      child: BlocListener<OnsiteVerificationBloc, OnsiteVerificationState>(
        listenWhen: (previous, current) {
          // Never re-trigger side effects (sheet, toast) when simply toggling camera mode
          if (previous.isCameraActive != current.isCameraActive &&
              previous.runtimeType == current.runtimeType) {
            return false;
          }
          return true;
        },
        listener: (context, state) {
          if (state is OnsiteVerificationLoaded) {
            _showCouponSheet(state.couponDetails);
          } else if (state is OnsiteVerificationError) {
            AppToast.error(state.message);
            _lastScannedCode = null;
            _bloc.add(const ResetOnsiteScanner());
          }
        },
        child: Scaffold(
          backgroundColor: AppTheme.eventxproBg,
          body: Stack(
            fit: StackFit.expand,
            children: [
              const AppBackgroundLayer(),

              SafeArea(
                child: Column(
                  children: [
                    // 1. Top Bar matching EventTopBar.jsx
                    _buildTopBar(),

                    // 2. Main Viewfinder Body
                    Expanded(
                      child: Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 8,
                          ),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 480),
                            child: _buildBody(),
                          ),
                        ),
                      ),
                    ),

                    // 3. Floating Control Dock (Mode Switch, Torch, Flip, Manual Entry)
                    _buildControlDock(),

                    const SizedBox(height: 12),
                  ],
                ),
              ),

              // In-Flight Processing Modal Overlay
              BlocBuilder<OnsiteVerificationBloc, OnsiteVerificationState>(
                builder: (context, state) {
                  if (state is OnsiteVerificationLoading) {
                    return Positioned.fill(
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.45),
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 28,
                              vertical: 24,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E2536),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: AppTheme.eventxproAccent
                                    .withValues(alpha: 0.6),
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.eventxproAccent
                                      .withValues(alpha: 0.25),
                                  blurRadius: 24,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(
                                  width: 44,
                                  height: 44,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 3.5,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      AppTheme.eventxproAccent,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 18),
                                const Text(
                                  'VERIFYING VOUCHER...',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.8,
                                    color: Colors.white,
                                  ),
                                ),
                                if (_lastScannedCode != null) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    _lastScannedCode!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontFamily: 'monospace',
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ).animate().fadeIn(duration: 150.ms).scale(
                                begin: const Offset(0.95, 0.95),
                              ),
                        ),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 1. Top Bar (Matching React Native EventTopBar.jsx) ─────────
  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Circular White Back Button
          InkWell(
            onTap: () {
              HapticFeedback.lightImpact();
              Navigator.of(context).pop();
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
                  Icons.arrow_back_ios_rounded,
                  size: 16,
                  color: Color(0xFF171C26),
                ),
              ),
            ),
          ),

          const SizedBox(width: 14),

          // Centered Title & Event Subtitle
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text(
                  'On-Site QR Verification',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.event_note_rounded,
                      size: 11,
                      color: Colors.white70,
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        widget.eventName,
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

          const SizedBox(width: 14),

          // Manual Entry Shortcut Button
          InkWell(
            onTap: _showManualEntryDialog,
            borderRadius: BorderRadius.circular(50),
            child: Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: Color(0xFF212836),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.keyboard_alt_outlined,
                size: 18,
                color: Colors.white70,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 2. Main Viewfinder Body ────────────────────────────────────
  Widget _buildBody() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Headline guidance
        const Text(
          'Scan Voucher / Coupon QR',
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
            'Position coupon QR within the frame to verify redemption status and attendee details',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              color: Color(0xFFAFAFAF),
              height: 1.3,
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Viewfinder Frame (270x270 Container)
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
                        if (_bloc.state is OnsiteVerificationLoading) return;
                        for (final barcode in capture.barcodes) {
                          final rawVal = barcode.rawValue?.trim();
                          if (rawVal != null && rawVal.isNotEmpty) {
                            _onScanned(rawVal);
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
                    ? 'Camera Active'
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

  /// High-tech Artwork shown when Zebra/Honeywell OEM Hardware Scanner is active
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

          // Center Graphic & Text
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
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
                  size: 26,
                  color: AppTheme.eventxproAccent,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Hardware Laser Mode',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 3),
              const Text(
                'Aim scanner gun at coupon QR',
                style: TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── 3. Floating Control Dock ──────────────────────────────────
  Widget _buildControlDock() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Mode Switch Button (White circular if in hardware mode, Magenta if in camera mode)
          Tooltip(
            message:
                _isCameraActive ? 'Switch to Laser Only' : 'Switch to Camera',
            child: InkWell(
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
                  color:
                      _isCameraActive ? Colors.white : const Color(0xFF171C26),
                  size: 24,
                ),
              ),
            ),
          ),

          // Camera controls: Flashlight & Switch Camera (only when camera is active)
          if (_isCameraActive && _cameraController != null) ...[
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

          // Manual Entry Keyboard Button
          Tooltip(
            message: 'Manual Coupon Entry',
            child: InkWell(
              onTap: _showManualEntryDialog,
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
                  Icons.keyboard_alt_outlined,
                  size: 22,
                  color: Colors.white70,
                ),
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
