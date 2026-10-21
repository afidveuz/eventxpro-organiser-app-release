# EventXPro Direct Hardware QR Scanner (Flutter + Native Android + Django DRF)

Production-grade Flutter application implementing direct hardware QR scanner event delivery for enterprise event entrance gates and kiosks, completely eliminating focus-dependent hidden TextFields and simulated keystrokes.

---

## 1. Architectural Highlights

- **Native Hardware Bridge**:
  - Zebra TC15 / TC21 / TC26 / TC52 / TC57 DataWedge Intent Output.
  - Kotlin `BroadcastReceiver` registered with `ContextCompat.RECEIVER_EXPORTED` (Android 13+ / API 33 compatible).
  - Flutter `EventChannel('eventxpro/scanner')` streaming decoded events directly into the controller.
- **Enterprise State Management (BLoC + Concurrency)**:
  - **Single Consumer Pipeline**: All physical scans flow through a single unified event controller.
  - **Configurable 300ms Deduplication**: Suppresses repeated hardware callbacks on the same device without delaying rapid consecutive attendee scans.
  - **Bounded FIFO Queue**: Safe 50-item buffer with safe overflow drop logging to prevent memory bloat or race conditions.
  - **RFC4122 v4 UUID Idempotency**: Each physical scan attempt generates a unique `scan_request_id`. Idempotent retries reuse the exact same UUID.
  - **Strict PII Protection**: Attendee details are **only** decoded and displayed for authorized admissions (`ENTRY_ALLOWED`). Invalid, expired, and wrong-event scans reveal zero personal data.
  - **Continuous Hands-Free Scanning**: Displays feedback for 1800ms before auto-resetting to `READY TO SCAN`. Any new hardware scan immediately interrupts feedback and processes the new code.
- **Service-Level Telemetry & Measurements (Section 11)**:
  - Real-time **p50, p95, p99** and average end-to-end latency percentiles.
  - Accuracy & integrity counters: total scans, admitted, rejected, warnings, duplicates suppressed (300ms), queue drops.
  - Device health indicators: battery, network state, adapter name, registered device UUID.
- **Testing & Multi-Platform Support**:
  - `ZebraDataWedgeAdapter`: Native Android EventChannel for physical Zebra handhelds.
  - `SimulatedHardwareAdapter`: Virtual barcode engine for development on Windows, Web, macOS, and Android Emulators.
  - Built-in interactive stress test laboratory (duplicate suppression burst, FIFO queue overflow, edge case badges).

---

## 2. Zebra DataWedge Profile Provisioning (Section 4)

Configure on Zebra TC15 / TC2x / TC5x handhelds via the **DataWedge** app:

| Setting | Configuration Rule |
| :--- | :--- |
| **Profile Name** | `EventXPro_Scanner` |
| **Associated Apps** | `com.eventxpro.qr_scanner` (`*` for all activities) |
| **Barcode Input** | **Enabled** (Symbologies: QR Code enabled) |
| **Keystroke Output** | **DISABLED** (Prevents simulated typing & focus bugs) |
| **Intent Output** | **ENABLED** |
| **Intent Action** | `com.eventxpro.SCAN` |
| **Intent Delivery** | **Broadcast Intent** |
| **Intent Category** | Default (leave empty) |
| **Payload Key** | `com.symbol.datawedge.data_string` |

---

## 3. Django DRF API Contract (Section 8)

### Endpoint
`POST /api/v1/access-control/scans/validate/`

### Request Payload
```json
{
  "qr_token": "VIP-2026-VICTORIA-STERLING",
  "event_id": 1024,
  "gate_id": 12,
  "scan_type": "ENTRY",
  "device_id": "8f31b268-07e1-4c7b-a2c6-ef48e24fa901",
  "scan_request_id": "c71a3d92-28e4-4638-b7eb-81c81ef407ab",
  "scanned_at": "2026-10-19T11:15:00.000Z"
}
```

### Response Codes
- `ENTRY_ALLOWED` (Status: ACCEPTED -> Large Green banner, Attendee name, badge category, check-in ID)
- `ALREADY_CHECKED_IN` (Status: WARNING -> Amber banner, previous check-in timestamp and gate)
- `WRONG_EVENT` (Status: REJECTED -> Red banner, zero personal data)
- `ACCESS_DENIED` (Status: REJECTED -> Red banner, security revoked status)
- `EXPIRED` (Status: REJECTED -> Red banner, badge expired notice)
- `INVALID_BADGE` (Status: REJECTED -> Red banner, unreadable/malformed)
- `NOT_AUTHORIZED` (Status: REJECTED -> Red banner, gate direction mismatch)
- `NETWORK_ERROR` (Status: PENDING -> Blue banner, idempotent retry action)

---

## 4. Project Structure (Clean Architecture)

```
lib/
├── core/
│   ├── config/app_constants.dart           # Timing benchmarks, endpoints, channel names
│   ├── services/
│   │   ├── audio_feedback_service.dart     # Distinct beeps & chimes for results
│   │   └── haptic_feedback_service.dart    # Android vibration patterns
│   └── theme/app_theme.dart               # High-contrast Kiosk dark palette
├── domain/
│   ├── entities/
│   │   ├── attendee.dart                  # Least-privilege attendee domain model
│   │   ├── scan_decision_code.dart        # Machine-readable admission codes
│   │   ├── scan_request.dart              # Scan request payload & metadata
│   │   ├── scan_response.dart             # Authoritative admission result
│   │   └── telemetry_data.dart            # p50, p95, p99 latency & integrity metrics
│   ├── adapters/
│   │   └── i_hardware_scanner_adapter.dart # Abstract OEM scanner interface
│   └── repositories/
│       └── i_scanner_repository.dart       # Contract for scan validation & queueing
├── data/
│   ├── adapters/
│   │   ├── zebra_datawedge_adapter.dart   # Native Kotlin EventChannel bridge
│   │   └── simulated_hardware_adapter.dart # Virtual engine for desktop/testing
│   ├── datasources/
│   │   ├── django_scan_api_datasource.dart # Dio client with 3s timeout & mock engine
│   │   └── scanner_local_storage.dart     # Local offline FIFO queue & settings
│   └── repositories/
│       └── scanner_repository_impl.dart   # Coordinates API, local cache, telemetry
└── presentation/
    ├── bloc/
    │   ├── scanner_bloc.dart              # Central Scan Controller (300ms dedupe, FIFO queue)
    │   ├── scanner_event.dart             # Ingestion & operational events
    │   └── scanner_state.dart             # Ready, Processing, Decision states
    ├── screens/
    │   ├── kiosk_scanner_screen.dart      # Main entrance-gate kiosk view
    │   ├── diagnostics_screen.dart        # Real-time p50/p95/p99 telemetry dashboard
    │   ├── simulator_screen.dart          # Test bench with presets & stress bursts
    │   └── provisioning_screen.dart       # DataWedge setup guide & gate configuration
    └── widgets/
        ├── kiosk_header_hud.dart          # Gate/Event/Adapter/Queue status bar
        ├── ready_scanner_target.dart      # Pulsing radar target (no-focus indicator)
        └── scan_feedback_banner.dart      # Large Green/Amber/Red/Blue result banner
```

---

## 5. Running the Application

### On Connected Zebra Handheld (e.g. TC15 / TC21):
```bash
flutter run -d 24152524702288
```

### On Windows Desktop:
```bash
flutter run -d windows
```

### Run Unit & Acceptance Tests:
```bash
flutter test
```
