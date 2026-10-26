import 'enterprise_hardware_adapter.dart';

/// Legacy alias for [EnterpriseHardwareAdapter] to maintain complete backward
/// compatibility with existing screen constructors and DI registrations.
///
/// Seamlessly supports both Honeywell ScanPal EDA51/CT40/CT60 and Zebra TC15/TC21/TC26 devices.
class ZebraDataWedgeAdapter extends EnterpriseHardwareAdapter {
  ZebraDataWedgeAdapter();
}
