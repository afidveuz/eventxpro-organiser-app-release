import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/services/audio_feedback_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/app_toast.dart';
import '../../../data/models/attendee_details_model.dart';
import '../../../data/models/country_model.dart';
import '../../../data/models/update_attendee_model.dart';
import '../../../data/repositories/attendee_repository.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../widgets/app_background_layer.dart';
import '../../widgets/country_picker_modal.dart';

/// Screen for editing an attendee's profile information matching `EditAttendeesDetails.jsx`.
/// Allows event organizers to update First Name, Last Name, Email, Phone, Country,
/// Organization, Job Title, and Notes.
class EditAttendeeDetailsScreen extends StatefulWidget {
  final AttendeeDetailsModel attendee;
  final int? eventId;
  final String? eventName;
  final bool isReadOnly;

  const EditAttendeeDetailsScreen({
    super.key,
    required this.attendee,
    this.eventId,
    this.eventName,
    this.isReadOnly = false,
  });

  @override
  State<EditAttendeeDetailsScreen> createState() =>
      _EditAttendeeDetailsScreenState();
}

class _EditAttendeeDetailsScreenState extends State<EditAttendeeDetailsScreen> {
  final _formKey = GlobalKey<FormState>();

  // Text Controllers
  late final TextEditingController _firstNameCtrl;
  late final TextEditingController _lastNameCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _companyCtrl;
  late final TextEditingController _jobTitleCtrl;
  late final TextEditingController _notesCtrl;

  // Focus Nodes
  final FocusNode _firstNameFocus = FocusNode();
  final FocusNode _lastNameFocus = FocusNode();
  final FocusNode _emailFocus = FocusNode();
  final FocusNode _phoneFocus = FocusNode();
  final FocusNode _companyFocus = FocusNode();
  final FocusNode _jobTitleFocus = FocusNode();
  final FocusNode _notesFocus = FocusNode();

  // State
  bool _isLoadingCountries = true;
  bool _isSaving = false;
  String? _errorField;
  String? _fieldErrorMessage;

  List<CountryModel> _countries = [];
  CountryModel _selectedCountryCode = const CountryModel(
    label: 'United Arab Emirates',
    code: 'AE',
    dialCode: '+971',
  );
  CountryModel? _selectedCountry;
  CountryModel? _selectedNationality;

  @override
  void initState() {
    super.initState();
    _initControllers();
    _loadCountries();
  }

  void _initControllers() {
    final att = widget.attendee;
    _firstNameCtrl = TextEditingController(text: att.firstname);
    _lastNameCtrl = TextEditingController(text: att.lastname ?? '');
    _emailCtrl = TextEditingController(text: att.email ?? '');
    _companyCtrl = TextEditingController(text: att.companyName ?? '');
    _jobTitleCtrl = TextEditingController(text: att.designation ?? '');
    _notesCtrl = TextEditingController();

    // Parse existing mobile & dial code
    String rawPhone = (att.mobile ?? '').trim();
    if (rawPhone.startsWith('+')) {
      // Find matching dial code from default countries first
      for (final c in CountryModel.defaultCountries) {
        if (rawPhone.startsWith(c.dialCode)) {
          _selectedCountryCode = c;
          rawPhone = rawPhone.substring(c.dialCode.length).trim();
          break;
        }
      }
    }
    _phoneCtrl = TextEditingController(text: rawPhone);

    _phoneCtrl.addListener(() {
      if (_errorField == 'mobile' || _errorField == 'phone') {
        setState(() {
          _errorField = null;
          _fieldErrorMessage = null;
        });
      }
    });

    _emailCtrl.addListener(() {
      if (_errorField == 'email') {
        setState(() {
          _errorField = null;
          _fieldErrorMessage = null;
        });
      }
    });
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _companyCtrl.dispose();
    _jobTitleCtrl.dispose();
    _notesCtrl.dispose();

    _firstNameFocus.dispose();
    _lastNameFocus.dispose();
    _emailFocus.dispose();
    _phoneFocus.dispose();
    _companyFocus.dispose();
    _jobTitleFocus.dispose();
    _notesFocus.dispose();
    super.dispose();
  }

  Future<void> _loadCountries() async {
    try {
      final repo = context.read<AttendeeRepository>();
      final list = await repo.getCountries();
      if (mounted) {
        setState(() {
          _countries = list.isNotEmpty ? list : CountryModel.defaultCountries;
          _isLoadingCountries = false;

          // Attempt to match attendee country
          final targetCountry = widget.attendee.country?.trim().toLowerCase();
          if (targetCountry != null && targetCountry.isNotEmpty) {
            _selectedCountry = _countries.firstWhere(
              (c) =>
                  c.label.toLowerCase() == targetCountry ||
                  c.code.toLowerCase() == targetCountry,
              orElse: () => _countries.firstWhere(
                (c) => c.label.toLowerCase().contains(targetCountry),
                orElse: () => CountryModel(
                  label: widget.attendee.country!,
                  code: '',
                  dialCode: '',
                ),
              ),
            );
          }

          // Refine phone dial code match with full country catalog
          final rawMobile = (widget.attendee.mobile ?? '').trim();
          if (rawMobile.startsWith('+')) {
            for (final c in _countries) {
              if (rawMobile.startsWith(c.dialCode)) {
                _selectedCountryCode = c;
                final clean = rawMobile.substring(c.dialCode.length).trim();
                if (_phoneCtrl.text != clean) {
                  _phoneCtrl.text = clean;
                }
                break;
              }
            }
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _countries = CountryModel.defaultCountries;
          _isLoadingCountries = false;
        });
      }
    }
  }

  /// Open Country / Dial code picker bottom sheet
  Future<void> _pickCountryCode() async {
    HapticFeedback.lightImpact();
    final picked = await CountryPickerModal.show(
      context,
      countries: _countries,
      selectedCountry: _selectedCountryCode,
      title: 'Select Country Dial Code',
      showDialCode: true,
    );
    if (picked != null && mounted) {
      setState(() => _selectedCountryCode = picked);
    }
  }

  /// Open Country picker bottom sheet
  Future<void> _pickCountry() async {
    HapticFeedback.lightImpact();
    final picked = await CountryPickerModal.show(
      context,
      countries: _countries,
      selectedCountry: _selectedCountry,
      title: 'Select Country of Residence',
      showDialCode: false,
    );
    if (picked != null && mounted) {
      setState(() => _selectedCountry = picked);
    }
  }

  /// Open Nationality picker bottom sheet
  Future<void> _pickNationality() async {
    HapticFeedback.lightImpact();
    final picked = await CountryPickerModal.show(
      context,
      countries: _countries,
      selectedCountry: _selectedNationality,
      title: 'Select Nationality',
      showDialCode: false,
    );
    if (picked != null && mounted) {
      setState(() => _selectedNationality = picked);
    }
  }

  Future<void> _submitUpdate() async {
    // Unfocus all keyboards
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      HapticFeedback.mediumImpact();
      AppToast.warning(
        'Please verify and correct the form fields.',
        title: 'Validation Error',
      );
      return;
    }

    if (_selectedCountry == null || _selectedCountry!.label.isEmpty) {
      HapticFeedback.mediumImpact();
      AppToast.warning(
        'Please select a country of residence.',
        title: 'Country Required',
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final repo = context.read<AttendeeRepository>();
      final request = UpdateAttendeeRequest(
        attendeeId: widget.attendee.id,
        eventId: widget.eventId ?? widget.attendee.eventId,
        ticketId: widget.attendee.ticketId,
        firstName: _firstNameCtrl.text.trim(),
        lastName: _lastNameCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        countryCode: _selectedCountryCode.dialCode,
        countryInitial: _selectedCountryCode.code,
        mobile: _phoneCtrl.text.trim(),
        companyName: _companyCtrl.text.trim(),
        jobTitle: _jobTitleCtrl.text.trim(),
        country: _selectedCountry!.label.trim(),
        nationality: _selectedNationality?.label.trim(),
        notes: _notesCtrl.text.trim().isNotEmpty
            ? _notesCtrl.text.trim()
            : null,
      );

      final result = await repo.updateAttendee(request);

      if (!mounted) return;

      setState(() => _isSaving = false);

      if (result.isSuccess) {
        AudioFeedbackService().playTone(AudioTone.success);
        HapticFeedback.heavyImpact();
        AppToast.success(
          result.message.isNotEmpty
              ? result.message
              : 'Attendee information updated successfully.',
          title: 'Update Successful',
        );
        Navigator.of(context).pop(true);
      } else {
        AudioFeedbackService().playTone(AudioTone.error);
        HapticFeedback.heavyImpact();

        final errField = result.field?.toLowerCase().trim();
        setState(() {
          _errorField = errField;
          _fieldErrorMessage = result.message;
        });

        // Warning toast matching React Native's Toast.show({ type: 'warning', props: { title: res.data.message } })
        AppToast.warning(
          result.message.isNotEmpty
              ? result.message
              : 'Unable to update attendee. Please check inputs and try again.',
          title: 'Validation Warning',
        );

        // Auto-focus the offending field if returned
        if (errField != null) {
          if (errField.contains('mobile') || errField.contains('phone')) {
            _phoneFocus.requestFocus();
          } else if (errField.contains('email')) {
            _emailFocus.requestFocus();
          } else if (errField.contains('first') || errField.contains('name')) {
            _firstNameFocus.requestFocus();
          } else if (errField.contains('company')) {
            _companyFocus.requestFocus();
          } else if (errField.contains('title') ||
              errField.contains('designation') ||
              errField.contains('job')) {
            _jobTitleFocus.requestFocus();
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        AudioFeedbackService().playTone(AudioTone.error);
        HapticFeedback.heavyImpact();
        AppToast.error(
          'An unexpected error occurred: ${e.toString()}',
          title: 'Update Error',
        );
      }
    }
  }

  String? _resolveImageUrl(String? path) {
    if (path == null || path.trim().isEmpty) return null;
    final clean = path.trim();
    if (clean.startsWith('http://') || clean.startsWith('https://'))
      return clean;

    try {
      final authRepo = context.read<AuthRepository>();
      final baseUrl = authRepo.mediaUrl;
      final cleanBase = baseUrl.endsWith('/')
          ? baseUrl.substring(0, baseUrl.length - 1)
          : baseUrl;
      final cleanPath = clean.startsWith('/') ? clean : '/$clean';
      return '$cleanBase$cleanPath';
    } catch (_) {
      return clean;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.eventxproBg,
      body: Stack(
        children: [
          const AppBackgroundLayer(),
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (widget.isReadOnly) ...[
                            Container(
                              margin: const EdgeInsets.only(bottom: 14),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFFF59E0B,
                                ).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: const Color(
                                    0xFFF59E0B,
                                  ).withValues(alpha: 0.3),
                                ),
                              ),
                              child: const Row(
                                children: [
                                  Icon(
                                    Icons.lock_outline_rounded,
                                    color: Color(0xFFF59E0B),
                                    size: 16,
                                  ),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'View-Only: You do not have permission to edit registrations for this event.',
                                      style: TextStyle(
                                        color: Color(0xFFFBBF24),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          _buildHeaderCard(),
                          const SizedBox(height: 16),
                          _buildPersonalInfoSection(),
                          const SizedBox(height: 16),
                          _buildProfessionalSection(),
                          const SizedBox(height: 16),
                          _buildLocationSection(),
                          const SizedBox(height: 24),
                          _buildSubmitButton(),
                          const SizedBox(height: 40),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Top Bar ──────────────────────────────────────────────────────────
  Widget _buildTopBar() {
    final title = 'Edit Attendee';
    final subtitle =
        widget.eventName ?? widget.attendee.eventName ?? 'Attendee Profile';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF10141E).withValues(alpha: 0.95),
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.of(context).pop();
              },
              borderRadius: BorderRadius.circular(20),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(
                    Icons.arrow_back_ios_new_rounded,
                    size: 14,
                    color: Color(0xFF131722),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.65),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Header Card ──────────────────────────────────────────────────────
  Widget _buildHeaderCard() {
    final att = widget.attendee;
    final photoUrl = _resolveImageUrl(att.photoUrl);
    final initials = att.initials;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161B26).withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: AppTheme.brandGradientStart.withValues(alpha: 0.6),
                width: 2,
              ),
            ),
            child: ClipOval(
              child: photoUrl != null && photoUrl.isNotEmpty
                  ? Image.network(
                      photoUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          _buildAvatarInitials(initials),
                    )
                  : _buildAvatarInitials(initials),
            ),
          ),
          const SizedBox(width: 14),

          // Metadata
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  att.fullName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                if (att.uniqueId != null && att.uniqueId!.isNotEmpty) ...[
                  Row(
                    children: [
                      Icon(
                        Icons.confirmation_number_outlined,
                        size: 13,
                        color: AppTheme.accentCyan.withValues(alpha: 0.8),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'URN: ${att.uniqueId}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                ],
                if (att.ticketName != null && att.ticketName!.isNotEmpty) ...[
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2.5,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.brandGradientStart.withValues(
                        alpha: 0.15,
                      ),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: AppTheme.brandGradientStart.withValues(
                          alpha: 0.4,
                        ),
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      att.ticketName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFF472B6),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarInitials(String initials) {
    return Container(
      color: const Color(0xFFC10067),
      child: Center(
        child: Text(
          initials,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  // ── Personal Info Section ────────────────────────────────────────────
  Widget _buildPersonalInfoSection() {
    return _buildSectionCard(
      title: 'PERSONAL INFORMATION',
      icon: Icons.person_rounded,
      iconColor: AppTheme.accentCyan,
      child: Column(
        children: [
          // First Name
          _buildTextField(
            controller: _firstNameCtrl,
            focusNode: _firstNameFocus,
            nextFocus: _lastNameFocus,
            label: 'First Name *',
            hint: 'e.g. John',
            icon: Icons.badge_outlined,
            capitalization: TextCapitalization.words,
            validator: (val) {
              if (val == null || val.trim().isEmpty) {
                return 'First Name is required';
              }
              if (!RegExp(r'^[A-Za-z\s]+$').hasMatch(val.trim())) {
                return 'First name must contain only letters';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),

          // Last Name
          _buildTextField(
            controller: _lastNameCtrl,
            focusNode: _lastNameFocus,
            nextFocus: _emailFocus,
            label: 'Last Name',
            hint: 'e.g. Doe',
            icon: Icons.badge_outlined,
            capitalization: TextCapitalization.words,
            validator: (val) {
              if (val != null &&
                  val.trim().isNotEmpty &&
                  !RegExp(r'^[A-Za-z\s]+$').hasMatch(val.trim())) {
                return 'Last name must contain only letters';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),

          // Email Address
          _buildTextField(
            controller: _emailCtrl,
            focusNode: _emailFocus,
            nextFocus: _phoneFocus,
            label: 'Email Address *',
            hint: 'e.g. attendee@company.com',
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            errorText: _errorField == 'email' ? _fieldErrorMessage : null,
            validator: (val) {
              if (val == null || val.trim().isEmpty) {
                return 'Email is required';
              }
              final emailRegExp = RegExp(
                r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
              );
              if (!emailRegExp.hasMatch(val.trim())) {
                return 'Please enter a valid email address';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),

          // Mobile Number with Dial Code
          _buildPhoneInput(),
        ],
      ),
    );
  }

  // ── Phone Input with Country Dial Code ───────────────────────────────
  Widget _buildPhoneInput() {
    final hasPhoneError = _errorField == 'mobile' || _errorField == 'phone';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Mobile Number *',
          style: TextStyle(
            color: Colors.white,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Country Dial Code Selector
            InkWell(
              onTap: widget.isReadOnly ? null : _pickCountryCode,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: hasPhoneError
                        ? const Color(0xFFEF4444)
                        : Colors.white.withValues(alpha: 0.14),
                    width: hasPhoneError ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _selectedCountryCode.flagEmoji,
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _selectedCountryCode.dialCode,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.arrow_drop_down_rounded,
                      color: Colors.white.withValues(alpha: 0.6),
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Phone Number Input
            Expanded(
              child: TextFormField(
                controller: _phoneCtrl,
                focusNode: _phoneFocus,
                readOnly: widget.isReadOnly,
                keyboardType: TextInputType.phone,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  hintText: 'e.g. 50 123 4567',
                  hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.3),
                    fontSize: 13.5,
                  ),
                  filled: true,
                  fillColor: Colors.black.withValues(alpha: 0.35),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: hasPhoneError
                          ? const Color(0xFFEF4444)
                          : Colors.white.withValues(alpha: 0.14),
                      width: hasPhoneError ? 1.5 : 1,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: hasPhoneError
                          ? const Color(0xFFEF4444)
                          : Colors.white.withValues(alpha: 0.14),
                      width: hasPhoneError ? 1.5 : 1,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: hasPhoneError
                          ? const Color(0xFFEF4444)
                          : AppTheme.brandGradientStart,
                      width: 1.5,
                    ),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFEF4444)),
                  ),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Mobile number is required';
                  }
                  if (val.trim().length < 5) {
                    return 'Enter a valid mobile number';
                  }
                  return null;
                },
              ),
            ),
          ],
        ),
        if (hasPhoneError && _fieldErrorMessage != null) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 14,
                color: Color(0xFFEF4444),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  _fieldErrorMessage!,
                  style: const TextStyle(
                    color: Color(0xFFEF4444),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  // ── Professional Section ─────────────────────────────────────────────
  Widget _buildProfessionalSection() {
    return _buildSectionCard(
      title: 'ORGANIZATION & ROLE',
      icon: Icons.business_center_rounded,
      iconColor: const Color(0xFF10B981),
      child: Column(
        children: [
          // Company Name
          _buildTextField(
            controller: _companyCtrl,
            focusNode: _companyFocus,
            nextFocus: _jobTitleFocus,
            label: 'Company / Organization *',
            hint: 'e.g. Global Tech Enterprises',
            icon: Icons.business_outlined,
            capitalization: TextCapitalization.words,
            validator: (val) {
              if (val == null || val.trim().isEmpty) {
                return 'Company name is required';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),

          // Job Title / Designation
          _buildTextField(
            controller: _jobTitleCtrl,
            focusNode: _jobTitleFocus,
            nextFocus: _notesFocus,
            label: 'Job Title / Designation *',
            hint: 'e.g. Operations Director',
            icon: Icons.work_outline_rounded,
            capitalization: TextCapitalization.words,
            validator: (val) {
              if (val == null || val.trim().isEmpty) {
                return 'Job title is required';
              }
              return null;
            },
          ),
        ],
      ),
    );
  }

  // ── Location & Demographics Section ──────────────────────────────────
  Widget _buildLocationSection() {
    return _buildSectionCard(
      title: 'LOCATION & NATIONALITY',
      icon: Icons.public_rounded,
      iconColor: const Color(0xFFF59E0B),
      child: Column(
        children: [
          // Country of Residence Picker
          _buildSelectorTile(
            label: 'Country of Residence *',
            value: _selectedCountry?.label,
            flag: _selectedCountry?.flagEmoji,
            placeholder: 'Select Country of Residence',
            icon: Icons.location_on_outlined,
            isLoading: _isLoadingCountries,
            onTap: _pickCountry,
          ),
          const SizedBox(height: 12),

          // Nationality Picker
          _buildSelectorTile(
            label: 'Nationality (Optional)',
            value: _selectedNationality?.label,
            flag: _selectedNationality?.flagEmoji,
            placeholder: 'Select Nationality',
            icon: Icons.flag_outlined,
            isLoading: _isLoadingCountries,
            onTap: _pickNationality,
          ),
          const SizedBox(height: 12),

          // Notes
          _buildTextField(
            controller: _notesCtrl,
            focusNode: _notesFocus,
            label: 'Internal Notes (Optional)',
            hint: 'Add any notes or badge printing instructions...',
            icon: Icons.notes_rounded,
            maxLines: 2,
            textInputAction: TextInputAction.done,
          ),
        ],
      ),
    );
  }

  // ── Selector Tile for Countries ──────────────────────────────────────
  Widget _buildSelectorTile({
    required String label,
    required String? value,
    required String? flag,
    required String placeholder,
    required IconData icon,
    required bool isLoading,
    required VoidCallback onTap,
  }) {
    final hasValue = value != null && value.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        InkWell(
          onTap: (isLoading || widget.isReadOnly) ? null : onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.14),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                if (flag != null && flag.isNotEmpty) ...[
                  Text(flag, style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 8),
                ] else ...[
                  Icon(
                    icon,
                    size: 18,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    hasValue ? value! : placeholder,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: hasValue
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.3),
                      fontSize: 13.5,
                      fontWeight: hasValue ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
                if (isLoading)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                    ),
                  )
                else
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: Colors.white.withValues(alpha: 0.6),
                    size: 22,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Generic Section Card ─────────────────────────────────────────────
  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161B26).withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(child: Icon(icon, color: iconColor, size: 16)),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  // ── Generic Reusable Text Field ──────────────────────────────────────
  Widget _buildTextField({
    required TextEditingController controller,
    required FocusNode focusNode,
    FocusNode? nextFocus,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    TextCapitalization capitalization = TextCapitalization.none,
    int maxLines = 1,
    TextInputAction textInputAction = TextInputAction.next,
    String? Function(String?)? validator,
    String? errorText,
  }) {
    final hasError = errorText != null && errorText.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          focusNode: focusNode,
          readOnly: widget.isReadOnly,
          keyboardType: keyboardType,
          textCapitalization: capitalization,
          maxLines: maxLines,
          textInputAction: textInputAction,
          onFieldSubmitted: (_) {
            if (nextFocus != null) {
              FocusScope.of(context).requestFocus(nextFocus);
            }
          },
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: Colors.white.withValues(alpha: 0.3),
              fontSize: 13.5,
            ),
            prefixIcon: Icon(
              icon,
              size: 18,
              color: Colors.white.withValues(alpha: 0.5),
            ),
            filled: true,
            fillColor: Colors.black.withValues(alpha: 0.35),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: hasError
                    ? const Color(0xFFEF4444)
                    : Colors.white.withValues(alpha: 0.14),
                width: hasError ? 1.5 : 1,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: hasError
                    ? const Color(0xFFEF4444)
                    : Colors.white.withValues(alpha: 0.14),
                width: hasError ? 1.5 : 1,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: hasError
                    ? const Color(0xFFEF4444)
                    : AppTheme.brandGradientStart,
                width: 1.5,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFEF4444)),
            ),
          ),
          validator: validator,
        ),
        if (hasError) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 14,
                color: Color(0xFFEF4444),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  errorText,
                  style: const TextStyle(
                    color: Color(0xFFEF4444),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  // ── Submit Button ────────────────────────────────────────────────────
  Widget _buildSubmitButton() {
    if (widget.isReadOnly) {
      return const SizedBox.shrink();
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _isSaving ? null : _submitUpdate,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            gradient: _isSaving ? null : AppTheme.brandGradient,
            color: _isSaving ? const Color(0xFF334155) : null,
            borderRadius: BorderRadius.circular(14),
            boxShadow: _isSaving
                ? null
                : [
                    BoxShadow(
                      color: AppTheme.brandGradientStart.withValues(alpha: 0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: Center(
            child: _isSaving
                ? const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      ),
                      SizedBox(width: 12),
                      Text(
                        'SAVING CHANGES...',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  )
                : const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_circle_outline_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'UPDATE ATTENDEE',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
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
