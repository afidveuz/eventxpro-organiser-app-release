import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:firebase_core/firebase_core.dart';
import 'core/cache/scan_memory_cache.dart';
import 'core/network/api_client.dart';
import 'core/services/crashlytics_service.dart';
import 'core/services/device_detection_service.dart';
import 'core/services/gate_count_service.dart';
import 'core/services/remote_config_service.dart';
import 'core/theme/app_theme.dart';
import 'data/adapters/simulated_hardware_adapter.dart';
import 'data/adapters/zebra_datawedge_adapter.dart';
import 'data/datasources/auth_local_storage.dart';
import 'data/datasources/auth_remote_datasource.dart';
import 'data/datasources/django_scan_api_datasource.dart';
import 'data/datasources/offline_database_helper.dart';
import 'data/datasources/scanner_local_storage.dart';
import 'data/repositories/auth_repository.dart';
import 'data/repositories/scanner_repository_impl.dart';
import 'domain/adapters/i_hardware_scanner_adapter.dart';
import 'presentation/bloc/auth/auth_bloc.dart';
import 'presentation/bloc/scanner_bloc.dart';
import 'presentation/bloc/scanner_event.dart';
import 'presentation/screens/auth/login_screen.dart';
import 'presentation/screens/auth/splash_screen.dart';
import 'core/navigation/app_route_observer.dart';
import 'presentation/screens/home/home_screen.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase Core, Crashlytics & Remote Config Services
  try {
    await Firebase.initializeApp();
    await CrashlyticsService().initialize();
    await RemoteConfigService().initialize();
  } catch (e) {
    debugPrint('[EventXPro] Firebase initialization error: $e');
  }

  // Set immersive fullscreen on handhelds
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Initialize persistent local storages
  final scannerLocalStorage = await ScannerLocalStorage.create();
  final authLocalStorage = await AuthLocalStorage.create();

  // Set Crashlytics context with device & organizer state
  await CrashlyticsService().setDeviceContext(
    deviceId: scannerLocalStorage.getDeviceId(),
    eventId: scannerLocalStorage.getEventId(),
    gateId: scannerLocalStorage.getGateId(),
    username: authLocalStorage.getUser()?.username,
    baseUrl: authLocalStorage.getBaseUrl(),
  );

  // Detect OEM device (Honeywell vs Zebra) on launch
  await DeviceDetectionService().detectDevice(storage: scannerLocalStorage);

  // Initialize API Network Client & Auth Stack
  final apiClient = ApiClient(localStorage: authLocalStorage);
  apiClient.onUnauthorized = (reason) {
    debugPrint('[EventXPro] 🚨 Global onUnauthorized: $reason');
    authLocalStorage.clearSession();
    appNavigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  };
  final authRemoteDatasource = AuthRemoteDatasource(apiClient: apiClient);
  final authRepository = AuthRepository(
    remoteDatasource: authRemoteDatasource,
    localStorage: authLocalStorage,
  );

  // Initialize remote Django DRF API client with timeout
  final remoteDatasource = DjangoScanApiDatasource(
    authLocalStorage: authLocalStorage,
  );
  remoteDatasource.updateBaseUrl(authLocalStorage.getBaseUrl());

  // Initialize high-performance offline database & in-memory cache
  final offlineDbHelper = OfflineDatabaseHelper();
  final scanMemoryCache = ScanMemoryCache();

  // Initialize GateCountService for check-in & check-out counts per gate
  final gateCountService = GateCountService(
    apiClient: apiClient,
    dbHelper: offlineDbHelper,
    localStorage: scannerLocalStorage,
  );

  // Initialize pre-warmed scanner repository (pre-loads SQLite codes to RAM)
  final scannerRepository = await ScannerRepositoryImpl.create(
    remoteDatasource: remoteDatasource,
    localStorage: scannerLocalStorage,
    dbHelper: offlineDbHelper,
    memoryCache: scanMemoryCache,
  );

  // Initialize hardware adapters
  final zebraAdapter = ZebraDataWedgeAdapter();
  final simulatorAdapter = SimulatedHardwareAdapter();

  // Default to Zebra Native adapter on Android, otherwise Simulated on Desktop/Web
  HardwareScannerAdapter defaultAdapter;
  if (!kIsWeb && Platform.isAndroid) {
    defaultAdapter = zebraAdapter;
  } else {
    defaultAdapter = simulatorAdapter;
  }

  runApp(EventXProApp(
    scannerRepository: scannerRepository,
    scannerLocalStorage: scannerLocalStorage,
    authRepository: authRepository,
    offlineDbHelper: offlineDbHelper,
    apiClient: apiClient,
    gateCountService: gateCountService,
    zebraAdapter: zebraAdapter,
    simulatorAdapter: simulatorAdapter,
    defaultAdapter: defaultAdapter,
  ));
}

class EventXProApp extends StatelessWidget {
  final ScannerRepositoryImpl scannerRepository;
  final ScannerLocalStorage scannerLocalStorage;
  final AuthRepository authRepository;
  final OfflineDatabaseHelper offlineDbHelper;
  final ApiClient apiClient;
  final GateCountService gateCountService;
  final ZebraDataWedgeAdapter zebraAdapter;
  final SimulatedHardwareAdapter simulatorAdapter;
  final HardwareScannerAdapter defaultAdapter;

  const EventXProApp({
    super.key,
    required this.scannerRepository,
    required this.scannerLocalStorage,
    required this.authRepository,
    required this.offlineDbHelper,
    required this.apiClient,
    required this.gateCountService,
    required this.zebraAdapter,
    required this.simulatorAdapter,
    required this.defaultAdapter,
  });

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<AuthRepository>.value(value: authRepository),
        RepositoryProvider<ScannerLocalStorage>.value(value: scannerLocalStorage),
        RepositoryProvider<OfflineDatabaseHelper>.value(value: offlineDbHelper),
        RepositoryProvider<ApiClient>.value(value: apiClient),
        RepositoryProvider<GateCountService>.value(value: gateCountService),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<AuthBloc>(
            create: (context) => AuthBloc(
              authRepository: authRepository,
            ),
          ),
          BlocProvider<ScannerBloc>(
            create: (context) => ScannerBloc(
              repository: scannerRepository,
              localStorage: scannerLocalStorage,
              activeAdapter: defaultAdapter,
              isScanningActive: false, // Inactive on startup until user opens KioskScannerScreen
            )..add(const ScannerInitialized()),
          ),
        ],
        child: MaterialApp(
          navigatorKey: appNavigatorKey,
          navigatorObservers: [appRouteObserver],
          title: 'EventXPro Organiser',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.darkTheme,
          home: SplashScreen(
            authenticatedHome: HomeScreen(
              zebraAdapter: zebraAdapter,
              simulatorAdapter: simulatorAdapter,
            ),
          ),
        ),
      ),
    );
  }
}
