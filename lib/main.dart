import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'core/network/api_client.dart';
import 'core/theme/app_theme.dart';
import 'data/adapters/simulated_hardware_adapter.dart';
import 'data/adapters/zebra_datawedge_adapter.dart';
import 'data/datasources/auth_local_storage.dart';
import 'data/datasources/auth_remote_datasource.dart';
import 'data/datasources/django_scan_api_datasource.dart';
import 'data/datasources/scanner_local_storage.dart';
import 'data/repositories/auth_repository.dart';
import 'data/repositories/scanner_repository_impl.dart';
import 'domain/adapters/i_hardware_scanner_adapter.dart';
import 'presentation/bloc/auth/auth_bloc.dart';
import 'presentation/bloc/auth/auth_event.dart';
import 'presentation/bloc/scanner_bloc.dart';
import 'presentation/bloc/scanner_event.dart';
import 'presentation/screens/auth/splash_screen.dart';
import 'presentation/screens/kiosk_scanner_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set immersive fullscreen on handhelds
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Initialize persistent local storages
  final scannerLocalStorage = await ScannerLocalStorage.create();
  final authLocalStorage = await AuthLocalStorage.create();

  // Initialize API Network Client & Auth Stack
  final apiClient = ApiClient(localStorage: authLocalStorage);
  final authRemoteDatasource = AuthRemoteDatasource(apiClient: apiClient);
  final authRepository = AuthRepository(
    remoteDatasource: authRemoteDatasource,
    localStorage: authLocalStorage,
  );

  // Initialize remote Django DRF API client with timeout
  final remoteDatasource = DjangoScanApiDatasource();
  remoteDatasource.updateBaseUrl(scannerLocalStorage.getServerUrl());
  remoteDatasource.testUsername = scannerLocalStorage.getTestUsername();

  // Initialize scanner repository
  final scannerRepository = ScannerRepositoryImpl(
    remoteDatasource: remoteDatasource,
    localStorage: scannerLocalStorage,
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
    zebraAdapter: zebraAdapter,
    simulatorAdapter: simulatorAdapter,
    defaultAdapter: defaultAdapter,
  ));
}

class EventXProApp extends StatelessWidget {
  final ScannerRepositoryImpl scannerRepository;
  final ScannerLocalStorage scannerLocalStorage;
  final AuthRepository authRepository;
  final ZebraDataWedgeAdapter zebraAdapter;
  final SimulatedHardwareAdapter simulatorAdapter;
  final HardwareScannerAdapter defaultAdapter;

  const EventXProApp({
    super.key,
    required this.scannerRepository,
    required this.scannerLocalStorage,
    required this.authRepository,
    required this.zebraAdapter,
    required this.simulatorAdapter,
    required this.defaultAdapter,
  });

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<AuthRepository>.value(value: authRepository),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<AuthBloc>(
            create: (context) => AuthBloc(
              authRepository: authRepository,
            )..add(const CheckAuthStatus()),
          ),
          BlocProvider<ScannerBloc>(
            create: (context) => ScannerBloc(
              repository: scannerRepository,
              localStorage: scannerLocalStorage,
              activeAdapter: defaultAdapter,
            )..add(const ScannerInitialized()),
          ),
        ],
        child: MaterialApp(
          title: 'EventXPro Organiser',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.darkTheme,
          home: SplashScreen(
            authenticatedHome: KioskScannerScreen(
              zebraAdapter: zebraAdapter,
              simulatorAdapter: simulatorAdapter,
            ),
          ),
        ),
      ),
    );
  }
}
