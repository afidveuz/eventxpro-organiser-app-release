import 'package:flutter/material.dart';

/// Global RouteObserver for screen lifecycle tracking (e.g. pausing/resuming scanner beam).
final RouteObserver<ModalRoute<void>> appRouteObserver = RouteObserver<ModalRoute<void>>();
