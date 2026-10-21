import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/config/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../data/adapters/simulated_hardware_adapter.dart';
import '../../data/adapters/zebra_datawedge_adapter.dart';
import '../bloc/scanner_bloc.dart';
import '../bloc/scanner_event.dart';
import '../bloc/scanner_state.dart';

class ProvisioningScreen extends StatefulWidget {
  final ZebraDataWedgeAdapter zebraAdapter;
  final SimulatedHardwareAdapter simulatorAdapter;

  const ProvisioningScreen({
    super.key,
    required this.zebraAdapter,
    required this.simulatorAdapter,
  });

  @override
  State<ProvisioningScreen> createState() => _ProvisioningScreenState();
}

class _ProvisioningScreenState extends State<ProvisioningScreen> {
  late TextEditingController _eventIdController;
  late TextEditingController _gateIdController;
  String _selectedScanType = 'ENTRY';
  double _suppressionMs = 300;
  bool _offlineMode = false;

  @override
  void initState() {
    super.initState();
    final currentState = context.read<ScannerBloc>().state;
    _eventIdController =
        TextEditingController(text: currentState.eventId.toString());
    _gateIdController =
        TextEditingController(text: currentState.gateId.toString());
    _selectedScanType = currentState.scanType;
    _offlineMode = currentState.isOfflineMode;
  }

  @override
  void dispose() {
    _eventIdController.dispose();
    _gateIdController.dispose();
    super.dispose();
  }

  void _saveConfiguration() {
    final eventId = int.tryParse(_eventIdController.text.trim()) ??
        AppConstants.defaultEventId;
    final gateId = int.tryParse(_gateIdController.text.trim()) ??
        AppConstants.defaultGateId;

    context.read<ScannerBloc>().add(
          ScannerConfigChanged(
            eventId: eventId,
            gateId: gateId,
            scanType: _selectedScanType,
            suppressionMs: _suppressionMs.round(),
            offlineModeEnabled: _offlineMode,
          ),
        );

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Gate configuration saved successfully'),
        backgroundColor: AppTheme.statusSuccess,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Provisioning & Gate Settings'),
      ),
      body: BlocBuilder<ScannerBloc, ScannerState>(
        builder: (context, state) {
          final isNativeZebra = state.adapterName.contains('Native');

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Scanner Adapter Selection
              const Text(
                'ACTIVE SCANNER ADAPTER',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 8),

              Row(
                children: [
                  Expanded(
                    child: _buildAdapterChoiceCard(
                      title: 'Zebra DataWedge',
                      subtitle: 'Native Broadcast Intent',
                      isSelected: isNativeZebra,
                      icon: Icons.bolt,
                      onTap: () {
                        context
                            .read<ScannerBloc>()
                            .add(ScannerAdapterSwitched(widget.zebraAdapter));
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildAdapterChoiceCard(
                      title: 'Hardware Simulator',
                      subtitle: 'Testing & Emulators',
                      isSelected: !isNativeZebra,
                      icon: Icons.developer_mode,
                      onTap: () {
                        context
                            .read<ScannerBloc>()
                            .add(ScannerAdapterSwitched(widget.simulatorAdapter));
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Section 4: Zebra Profile Specification Guide
              const Text(
                'ZEBRA DATAWEDGE PROFILE SPECIFICATION (SECTION 4)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 10),

              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _buildSpecRow('Profile Name', AppConstants.dataWedgeProfileName),
                      const Divider(color: AppTheme.surfaceBorder),
                      _buildSpecRow('Barcode Input', 'Enabled (QR Decoder)'),
                      const Divider(color: AppTheme.surfaceBorder),
                      _buildSpecRow('Keystroke Output', 'DISABLED (No simulated typing)'),
                      const Divider(color: AppTheme.surfaceBorder),
                      _buildSpecRow('Intent Output', 'ENABLED (Broadcast Intent)'),
                      const Divider(color: AppTheme.surfaceBorder),
                      _buildSpecRow('Intent Action', AppConstants.dataWedgeIntentAction),
                      const Divider(color: AppTheme.surfaceBorder),
                      _buildSpecRow('Payload Key', AppConstants.dataWedgePayloadExtra),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Gate & Event Config
              const Text(
                'EVENT & ACCESS-CONTROL PARAMETERS',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 10),

              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _eventIdController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Event ID',
                                prefixIcon: Icon(Icons.event, size: 20),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: TextField(
                              controller: _gateIdController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Gate ID',
                                prefixIcon: Icon(Icons.door_front_door_outlined, size: 20),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedScanType,
                        decoration: const InputDecoration(
                          labelText: 'Scan Workflow / Rule Direction',
                          prefixIcon: Icon(Icons.directions_walk, size: 20),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'ENTRY', child: Text('ENTRY - Entrance Gate Admission')),
                          DropdownMenuItem(value: 'EXIT', child: Text('EXIT - Egress / Re-entry Checkpoint')),
                          DropdownMenuItem(value: 'SESSION', child: Text('SESSION - Track / Workshop Access')),
                          DropdownMenuItem(value: 'LEAD', child: Text('LEAD - Exhibitor Lead Retrieval')),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedScanType = val);
                        },
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Deduplication Benchmark
              Text(
                'HARDWARE DUPLICATE SUPPRESSION: ${_suppressionMs.round()} MS',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 8),

              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Slider(
                        value: _suppressionMs,
                        min: 100,
                        max: 1000,
                        divisions: 18,
                        label: '${_suppressionMs.round()} ms',
                        onChanged: (val) {
                          setState(() => _suppressionMs = val);
                        },
                      ),
                      const Text(
                        'Benchmark: 300 ms suppresses repeated hardware callbacks on the same device without delaying rapid consecutive attendee scans.',
                        style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Section 10: Offline Admission Mode
              const Text(
                'OFFLINE ADMISSION & QUEUE POLICY (SECTION 10)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 8),

              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Enable Offline Admission Queue',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: const Text(
                          'Store scans locally in FIFO queue when disconnected. Sync when network returns.',
                          style: TextStyle(fontSize: 12),
                        ),
                        value: _offlineMode,
                        onChanged: (val) {
                          setState(() => _offlineMode = val);
                        },
                      ),
                      if (_offlineMode) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade900.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.amber.shade700),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.warning_amber, color: Colors.amber, size: 20),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Security note: Offline admission cannot guarantee cross-gate duplicate prevention without live backend coordination.',
                                  style: TextStyle(fontSize: 11, color: Colors.amber),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Save button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _saveConfiguration,
                  icon: const Icon(Icons.check),
                  label: const Text('SAVE GATE PROVISIONING'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentIndigo,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAdapterChoiceCard({
    required String title,
    required String subtitle,
    required bool isSelected,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.accentIndigo.withValues(alpha: 0.15)
              : AppTheme.surfaceElevated,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppTheme.accentIndigo : AppTheme.surfaceBorder,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              color: isSelected ? AppTheme.accentIndigo : AppTheme.textSecondary,
              size: 24,
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isSelected ? Colors.white : AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 10,
                color: AppTheme.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpecRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
