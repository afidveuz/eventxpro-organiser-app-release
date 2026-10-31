import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../core/config/app_constants.dart';
import '../../core/network/api_client.dart';
import '../../core/services/device_detection_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/app_toast.dart';
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
import '../widgets/app_background.dart';
import '../widgets/onsite_qr_info_bottom_sheet.dart';

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
    with SingleTickerProviderStateMixin {
  late final OnsiteVerificationBloc _bloc;
  MobileScannerController? _cameraController;
  StreamSubscription<String>? _hardwareScanSub;

  late final AnimationController _laserController;
  late final Animation<double> _laserAnimation;

  bool _isCameraActive = true;
  String? _lastScannedCode;
  bool _isSheetOpen = false;
  OnsiteCouponModel? _currentCouponDetails;
  StateSetter? _sheetSetState;

  @override
  void initState() {
    super.initState();

    _laserController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _laserAnimation = Tween<double>(begin: 0.05, end: 0.95).animate(
      CurvedAnimation(parent: _laserController, curve: Curves.easeInOut),
    );

    IQrVerificationRepository repository;
    if (widget.repository != null) {
      repository = widget.repository!;
    } else {
      final apiClient = context.read<ApiClient>();
      final remoteDatasource = QrVerificationRemoteDatasource(apiClient: apiClient);
      repository = QrVerificationRepositoryImpl(remoteDatasource: remoteDatasource);
    }

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
      HardwareScannerAdapter? adapter;
      try {
        adapter = context.read<HardwareScannerAdapter>();
      } catch (_) {}

      if (adapter != null) {
        adapter.initialize();
        _hardwareScanSub = adapter.scanStream.listen(_onScanned);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _laserController.dispose();
    _hardwareScanSub?.cancel();
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

    setState(() {
      _isCameraActive = !wasActive;
      if (!wasActive && !Platform.environment.containsKey('FLUTTER_TEST')) {
        _initCamera();
      }
    });

    if (wasActive) {
      final old = _cameraController;
      _cameraController = null;
      old?.dispose();
    }

    _bloc.add(const ToggleOnsiteCameraMode());

    try {
      context.read<ScannerLocalStorage>().setCameraEnabled(_isCameraActive);
    } catch (_) {}
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

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final isLandscape = mediaQuery.orientation == Orientation.landscape;

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
          child: AppBackground(
            child: SafeArea(
              child: Stack(
                children: [
                  Column(
                    children: [
                      // Top Bar
                      _buildTopBar(),

                      // Viewfinder
                      Expanded(
                        child: isLandscape
                            ? _buildLandscapeLayout()
                            : _buildPortraitLayout(),
                      ),
                    ],
                  ),

                  // Loading Overlay
                  BlocBuilder<OnsiteVerificationBloc, OnsiteVerificationState>(
                    builder: (context, state) {
                      if (state is OnsiteVerificationLoading) {
                        return Container(
                          color: Colors.black.withValues(alpha: 0.55),
                          child: const Center(
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(
                                AppTheme.eventxproAccent,
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
        ),
      );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'On-Site QR Verification',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
                Text(
                  widget.eventName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: _isCameraActive ? 'Turn off camera' : 'Turn on camera',
            icon: Icon(
              _isCameraActive ? Icons.videocam_rounded : Icons.videocam_off_rounded,
              color: _isCameraActive ? Colors.white : AppTheme.brandGradientStart,
            ),
            onPressed: _toggleCamera,
          ),
        ],
      ),
    );
  }

  Widget _buildPortraitLayout() {
    final size = MediaQuery.of(context).size;
    final boxSize = size.width * 0.72;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          'Scan Voucher / Coupon QR',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 6),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            'Position coupon QR within the frame to verify redemption status and attendee details',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white70,
              fontSize: 13,
              height: 1.3,
            ),
          ),
        ),
        const SizedBox(height: 28),

        _buildViewfinder(boxSize, boxSize),

        const SizedBox(height: 32),

        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white.withValues(alpha: 0.08),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
            ),
          ),
          onPressed: _toggleCamera,
          icon: Icon(
            _isCameraActive ? Icons.camera_alt_outlined : Icons.sensors_rounded,
            size: 18,
            color: _isCameraActive ? Colors.white : AppTheme.brandGradientStart,
          ),
          label: Text(
            _isCameraActive ? 'Switch to Laser Only' : 'Switch to Camera',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _buildLandscapeLayout() {
    final size = MediaQuery.of(context).size;
    final boxSize = size.height * 0.58;

    return Row(
      children: [
        Expanded(
          flex: 1,
          child: Center(
            child: _buildViewfinder(boxSize, boxSize),
          ),
        ),
        Expanded(
          flex: 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Scan Voucher / Coupon QR',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Position coupon code within the frame to inspect redeemed attendees',
                  style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.3),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                    ),
                  ),
                  onPressed: _toggleCamera,
                  icon: Icon(
                    _isCameraActive ? Icons.camera_alt_outlined : Icons.sensors_rounded,
                    size: 18,
                  ),
                  label: Text(_isCameraActive ? 'Laser Scanner Only' : 'Use Camera'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildViewfinder(double width, double height) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF23A618).withValues(alpha: 0.7),
          width: 1.5,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: Stack(
          children: [
            if (_isCameraActive && _cameraController != null)
              MobileScanner(
                controller: _cameraController!,
                fit: BoxFit.cover,
                errorBuilder: (context, error) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.videocam_off_rounded, color: AppTheme.eventxproDanger, size: 36),
                          const SizedBox(height: 8),
                          Text(
                            'Camera Error: ${error.errorCode.name}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  );
                },
                onDetect: (capture) {
                  for (final barcode in capture.barcodes) {
                    final rawVal = barcode.rawValue?.trim();
                    if (rawVal != null && rawVal.isNotEmpty) {
                      _onScanned(rawVal);
                      break;
                    }
                  }
                },
              )
            else
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.qr_code_scanner_rounded,
                      size: 54,
                      color: Colors.white.withValues(alpha: 0.35),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Hardware Laser Mode',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Aim scanner gun at coupon QR',
                      style: TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),

            if (_isCameraActive)
              AnimatedBuilder(
                animation: _laserAnimation,
                builder: (context, _) {
                  return Positioned(
                    top: height * _laserAnimation.value,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 2.5,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFF23A618).withValues(alpha: 0.0),
                            const Color(0xFF23A618),
                            const Color(0xFF23A618).withValues(alpha: 0.0),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF23A618).withValues(alpha: 0.8),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),

            Positioned(
              top: 10,
              left: 10,
              child: _buildCorner(isTop: true, isLeft: true),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: _buildCorner(isTop: true, isLeft: false),
            ),
            Positioned(
              bottom: 10,
              left: 10,
              child: _buildCorner(isTop: false, isLeft: true),
            ),
            Positioned(
              bottom: 10,
              right: 10,
              child: _buildCorner(isTop: false, isLeft: false),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCorner({required bool isTop, required bool isLeft}) {
    const size = 18.0;
    const thickness = 3.0;
    const color = Colors.white;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          Positioned(
            top: isTop ? 0 : null,
            bottom: isTop ? null : 0,
            left: 0,
            right: 0,
            child: Container(height: thickness, color: color),
          ),
          Positioned(
            left: isLeft ? 0 : null,
            right: isLeft ? null : 0,
            top: 0,
            bottom: 0,
            child: Container(width: thickness, color: color),
          ),
        ],
      ),
    );
  }
}
