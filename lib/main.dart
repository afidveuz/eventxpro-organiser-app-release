import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'core/theme/app_theme.dart';
import 'data/adapters/simulated_hardware_adapter.dart';
import 'data/adapters/zebra_datawedge_adapter.dart';
import 'data/datasources/django_scan_api_datasource.dart';
import 'data/datasources/scanner_local_storage.dart';
import 'data/repositories/scanner_repository_impl.dart';
import 'domain/adapters/i_hardware_scanner_adapter.dart';
import 'presentation/bloc/scanner_bloc.dart';
import 'presentation/bloc/scanner_event.dart';
import 'presentation/screens/kiosk_scanner_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set immersive fullscreen on handhelds
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Initialize persistent local storage
  final localStorage = await ScannerLocalStorage.create();

  // Initialize remote Django DRF API client with timeout
  final remoteDatasource = DjangoScanApiDatasource();
  remoteDatasource.updateBaseUrl(localStorage.getServerUrl());
  remoteDatasource.testUsername = localStorage.getTestUsername();

  // Initialize repository
  final repository = ScannerRepositoryImpl(
    remoteDatasource: remoteDatasource,
    localStorage: localStorage,
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

  runApp(EventXProScannerApp(
    repository: repository,
    localStorage: localStorage,
    zebraAdapter: zebraAdapter,
    simulatorAdapter: simulatorAdapter,
    defaultAdapter: defaultAdapter,
  ));
}

class EventXProScannerApp extends StatelessWidget {
  final ScannerRepositoryImpl repository;
  final ScannerLocalStorage localStorage;
  final ZebraDataWedgeAdapter zebraAdapter;
  final SimulatedHardwareAdapter simulatorAdapter;
  final HardwareScannerAdapter defaultAdapter;

  const EventXProScannerApp({
    super.key,
    required this.repository,
    required this.localStorage,
    required this.zebraAdapter,
    required this.simulatorAdapter,
    required this.defaultAdapter,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ScannerBloc>(
      create: (context) => ScannerBloc(
        repository: repository,
        localStorage: localStorage,
        activeAdapter: defaultAdapter,
      )..add(const ScannerInitialized()),
      child: MaterialApp(
        title: 'EventXPro Hardware Scanner',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: KioskScannerScreen(
          zebraAdapter: zebraAdapter,
          simulatorAdapter: simulatorAdapter,
        ),
      ),
    );
  }
}
