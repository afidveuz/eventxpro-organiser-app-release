import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/country_model.dart';
import '../../../data/models/spot_registration_model.dart';
import '../../../data/models/ticket_type_model.dart';
import '../../../data/repositories/attendee_repository.dart';
import '../../widgets/country_picker_modal.dart';
import '../../widgets/fade_in_background_image.dart';
import '../../widgets/spot_registration_success_sheet.dart';

/// Screen for registering walk-in attendees on-site at the event venue.
/// Mirrors `AttendeesCreation.jsx` from React Native with modern Flutter UI.
class SpotRegistrationScreen extends StatefulWidget {
  final int eventId;
  final String eventName;

  const SpotRegistrationScreen({
    super.key,
    required this.eventId,
    required this.eventName,
  });

  @override
  State<SpotRegistrationScreen> createState() => _SpotRegistrationScreenState();
}

class _SpotRegistrationScreenState extends State<SpotRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();

  // Text Controllers
  final TextEditingController _firstNameCtrl = TextEditingController();
  final TextEditingController _lastNameCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _confirmEmailCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _companyCtrl = TextEditingController();
  final TextEditingController _jobTitleCtrl = TextEditingController();

  // Focus nodes
  final FocusNode _firstNameFocus = FocusNode();
  final FocusNode _lastNameFocus = FocusNode();
  final FocusNode _emailFocus = FocusNode();
  final FocusNode _confirmEmailFocus = FocusNode();
  final FocusNode _phoneFocus = FocusNode();
  final FocusNode _companyFocus = FocusNode();
  final FocusNode _jobTitleFocus = FocusNode();

  // Data State
  bool _isLoadingData = true;
  bool _isSubmitting = false;
  String? _dataLoadError;

  List<TicketTypeModel> _ticketTypes = [];
  TicketTypeModel? _selectedTicket;

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
    _loadInitialData();
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    _confirmEmailCtrl.dispose();
    _phoneCtrl.dispose();
    _companyCtrl.dispose();
    _jobTitleCtrl.dispose();

    _firstNameFocus.dispose();
    _lastNameFocus.dispose();
    _emailFocus.dispose();
    _confirmEmailFocus.dispose();
    _phoneFocus.dispose();
    _companyFocus.dispose();
    _jobTitleFocus.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _isLoadingData = true;
      _dataLoadError = null;
    });

    final repo = context.read<AttendeeRepository>();

    try {
      final results = await Future.wait([
        repo.getTicketList(widget.eventId),
        repo.getCountries(),
      ]);

      final tickets = results[0] as List<TicketTypeModel>;
      final countries = results[1] as List<CountryModel>;

      if (mounted) {
        setState(() {
          _ticketTypes = tickets;
          if (_ticketTypes.isNotEmpty) {
            _selectedTicket = _ticketTypes.first;
          }

          _countries = countries.isNotEmpty
              ? countries
              : CountryModel.defaultCountries;

          // Default Country code to UAE or first match
          final defaultCode = _countries.firstWhere(
            (c) => c.code == 'AE',
            orElse: () => _countries.first,
          );
          _selectedCountryCode = defaultCode;
          _selectedCountry = defaultCode;
          _selectedNationality = defaultCode;

          _isLoadingData = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingData = false;
          _dataLoadError = 'Failed to load tickets: $e';
          _countries = CountryModel.defaultCountries;
        });
      }
    }
  }

  void _resetForm() {
    _formKey.currentState?.reset();
    _firstNameCtrl.clear();
    _lastNameCtrl.clear();
    _emailCtrl.clear();
    _confirmEmailCtrl.clear();
    _phoneCtrl.clear();
    _companyCtrl.clear();
    _jobTitleCtrl.clear();

    setState(() {
      if (_ticketTypes.isNotEmpty) {
        _selectedTicket = _ticketTypes.first;
      }
    });

    _firstNameFocus.requestFocus();
  }

  /// Normalize Gmail email aliases (strip +tag)
  String _normalizeEmail(String email) {
    final clean = email.trim().toLowerCase();
    final parts = clean.split('@');
    if (parts.length == 2 &&
        (parts[1] == 'gmail.com' || parts[1] == 'googlemail.com')) {
      final base = parts[0].split('+')[0];
      return '$base@gmail.com';
    }
    return clean;
  }

  Future<void> _submitRegistration() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      HapticFeedback.vibrate();
      return;
    }

    if (_selectedTicket == null) {
      _showWarning('Please select a ticket tier');
      return;
    }

    if (_selectedCountry == null) {
      _showWarning('Please select Country of Residence');
      return;
    }

    if (_selectedNationality == null) {
      _showWarning('Please select Nationality');
      return;
    }

    setState(() => _isSubmitting = true);
    HapticFeedback.mediumImpact();

    final repo = context.read<AttendeeRepository>();
    final cleanEmail = _normalizeEmail(_emailCtrl.text);
    final ticketPrice = (_selectedTicket?.price != null)
        ? _selectedTicket!.price!.toDouble()
        : 0.0;

    final request = SpotRegistrationRequest(
      eventId: widget.eventId,
      ticketId: _selectedTicket!.pk,
      firstName: _firstNameCtrl.text.trim(),
      lastName: _lastNameCtrl.text.trim(),
      email: cleanEmail,
      countryCode: _selectedCountryCode.dialCode,
      mobile: _phoneCtrl.text.trim(),
      companyName: _companyCtrl.text.trim(),
      jobTitle: _jobTitleCtrl.text.trim(),
      country: _selectedCountry!.label,
      nationality: _selectedNationality!.label,
      countryInitial: _selectedCountry?.code,
      receivedAmount: ticketPrice,
      currency: _selectedTicket?.currency,
      paymentMode: 'onsite_qr',
      collectedBy: 'Spot Registration',
    );

    final result = await repo.createSpotAttendee(request);

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (result.isSuccess) {
      HapticFeedback.heavyImpact();
      SpotRegistrationSuccessSheet.show(
        context,
        eventId: widget.eventId,
        eventName: widget.eventName,
        result: result,
        onRegisterAnother: _resetForm,
      );
    } else {
      HapticFeedback.vibrate();
      _showError(result.message ?? 'Registration failed. Please check your inputs and try again.');
    }
  }

  void _showWarning(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(msg)),
          ],
        ),
        backgroundColor: const Color(0xFFF59E0B),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showError(String msg) {
    // For multiline or detailed field validation errors (kiosk_v2 style), show dialog
    if (msg.contains('\n') || msg.length > 70) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1E2538),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
          ),
          title: const Row(
            children: [
              Icon(Icons.error_outline_rounded, color: AppTheme.eventxproDanger, size: 24),
              SizedBox(width: 10),
              Text(
                'Registration Failed',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Text(
            msg,
            style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK', style: TextStyle(color: AppTheme.brandGradientStart)),
            ),
          ],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(msg)),
            ],
          ),
          backgroundColor: AppTheme.eventxproDanger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // Pick Dial Code
  Future<void> _pickDialCode() async {
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

  // Pick Country of Residence
  Future<void> _pickCountry() async {
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

  // Pick Nationality
  Future<void> _pickNationality() async {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.eventxproNavy,
      body: Stack(
        children: [
          // Background ambient graphic
          Positioned.fill(
            child: const FadeInBackgroundImage(
              imagePath: 'assets/images/bg.png',
              duration: Duration(milliseconds: 800),
              curve: Curves.easeOutCubic,
            ),
          ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF131722).withValues(alpha: 0.35),
                    AppTheme.eventxproBg.withValues(alpha: 0.15),
                    const Color(0xFF0D111A).withValues(alpha: 0.65),
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                _buildAppBar(),
                Expanded(
                  child: _isLoadingData
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: AppTheme.brandGradientStart,
                          ),
                        )
                      : _dataLoadError != null
                          ? _buildErrorView()
                          : _buildFormView(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.eventxproNavy.withValues(alpha: 0.9),
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Spot Registration',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  widget.eventName,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Reset Form',
            onPressed: _resetForm,
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: AppTheme.eventxproDanger, size: 48),
            const SizedBox(height: 14),
            Text(
              _dataLoadError ?? 'Failed to load tickets',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: _loadInitialData,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.brandGradientStart,
              ),
              child: const Text('Try Again', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormView() {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              physics: const BouncingScrollPhysics(),
              children: [
                // 1. Ticket Tier Section
                _buildSectionCard(
                  title: 'TICKET CATEGORY',
                  icon: Icons.confirmation_number_rounded,
                  iconColor: AppTheme.brandGradientStart,
                  child: _buildTicketSelector(),
                ),
                const SizedBox(height: 16),

                // 2. Personal Information Section
                _buildSectionCard(
                  title: 'PERSONAL DETAILS',
                  icon: Icons.person_rounded,
                  iconColor: AppTheme.accentCyan,
                  child: Column(
                    children: [
                      // First Name
                      _buildTextField(
                        controller: _firstNameCtrl,
                        focusNode: _firstNameFocus,
                        nextFocus: _lastNameFocus,
                        label: 'First Name',
                        hint: 'e.g. John',
                        icon: Icons.badge_outlined,
                        capitalization: TextCapitalization.words,
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'First Name is required';
                          }
                          if (!RegExp(r'^[A-Za-z\s]+$').hasMatch(val.trim())) {
                            return 'Only letters are allowed';
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
                          if (val == null || val.trim().isEmpty) {
                            return 'Last Name is required';
                          }
                          if (!RegExp(r'^[A-Za-z\s]+$').hasMatch(val.trim())) {
                            return 'Only letters are allowed';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),

                      // Email
                      _buildTextField(
                        controller: _emailCtrl,
                        focusNode: _emailFocus,
                        nextFocus: _confirmEmailFocus,
                        label: 'Email Address',
                        hint: 'e.g. john.doe@company.com',
                        icon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Email is required';
                          }
                          final emailRegExp = RegExp(
                            r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
                          );
                          if (!emailRegExp.hasMatch(val.trim())) {
                            return 'Invalid email format';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),

                      // Confirm Email
                      _buildTextField(
                        controller: _confirmEmailCtrl,
                        focusNode: _confirmEmailFocus,
                        nextFocus: _phoneFocus,
                        label: 'Confirm Email',
                        hint: 'Re-enter email address',
                        icon: Icons.mark_email_read_outlined,
                        keyboardType: TextInputType.emailAddress,
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Please confirm email';
                          }
                          if (val.trim().toLowerCase() !=
                              _emailCtrl.text.trim().toLowerCase()) {
                            return 'Emails do not match';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),

                      // Phone with Dial Code Picker
                      _buildPhoneInput(),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 3. Professional Details Section
                _buildSectionCard(
                  title: 'ORGANIZATION & ROLE',
                  icon: Icons.business_center_rounded,
                  iconColor: const Color(0xFF10B981),
                  child: Column(
                    children: [
                      _buildTextField(
                        controller: _companyCtrl,
                        focusNode: _companyFocus,
                        nextFocus: _jobTitleFocus,
                        label: 'Company / Organization',
                        hint: 'e.g. Acme Corporation',
                        icon: Icons.business_outlined,
                        capitalization: TextCapitalization.words,
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Company Name is required';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(
                        controller: _jobTitleCtrl,
                        focusNode: _jobTitleFocus,
                        label: 'Job Title / Designation',
                        hint: 'e.g. Marketing Manager',
                        icon: Icons.work_outline_rounded,
                        capitalization: TextCapitalization.words,
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Job Title is required';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 4. Location & Nationality Section
                _buildSectionCard(
                  title: 'COUNTRY & NATIONALITY',
                  icon: Icons.public_rounded,
                  iconColor: const Color(0xFFA855F7),
                  child: Column(
                    children: [
                      _buildSelectorTile(
                        label: 'Country of Residence',
                        country: _selectedCountry,
                        onTap: _pickCountry,
                      ),
                      const SizedBox(height: 12),
                      _buildSelectorTile(
                        label: 'Nationality',
                        country: _selectedNationality,
                        onTap: _pickNationality,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Bottom Submit Action
          _buildBottomSubmitBar(),
        ],
      ),
    );
  }

  // Ticket Selector Chips
  Widget _buildTicketSelector() {
    if (_ticketTypes.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Text(
          'No tickets configured for this event.',
          style: TextStyle(color: Colors.white54, fontSize: 13),
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _ticketTypes.map((ticket) {
        final isSelected = _selectedTicket?.pk == ticket.pk;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _selectedTicket = ticket);
            },
            borderRadius: BorderRadius.circular(10),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppTheme.brandGradientStart.withValues(alpha: 0.22)
                    : Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected
                      ? AppTheme.brandGradientStart
                      : Colors.white.withValues(alpha: 0.12),
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isSelected
                        ? Icons.check_circle_rounded
                        : Icons.confirmation_number_outlined,
                    size: 16,
                    color: isSelected
                        ? AppTheme.brandGradientStart
                        : Colors.white54,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    ticket.label,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white70,
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  if (ticket.price != null && ticket.price! > 0) ...[
                    const SizedBox(width: 6),
                    Text(
                      '(${ticket.currency ?? ''} ${ticket.price})',
                      style: const TextStyle(
                        color: Color(0xFF10B981),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // Section Card Container
  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2538).withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
        ),
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
                  color: iconColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: iconColor),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
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

  // Generic Styled Text Field
  Widget _buildTextField({
    required TextEditingController controller,
    required FocusNode focusNode,
    FocusNode? nextFocus,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    TextCapitalization capitalization = TextCapitalization.none,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      textCapitalization: capitalization,
      keyboardType: keyboardType,
      textInputAction: nextFocus != null ? TextInputAction.next : TextInputAction.done,
      onFieldSubmitted: (_) => nextFocus?.requestFocus(),
      style: const TextStyle(color: Colors.white, fontSize: 14),
      cursorColor: AppTheme.brandGradientStart,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white60, fontSize: 13),
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
        prefixIcon: Icon(icon, color: Colors.white54, size: 20),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.brandGradientStart, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.eventxproDanger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.eventxproDanger, width: 1.5),
        ),
      ),
    );
  }

  // Phone Input with Dial Code Selector
  Widget _buildPhoneInput() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Dial Code Selector Pill
        InkWell(
          onTap: _pickDialCode,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _selectedCountryCode.flagEmoji,
                  style: const TextStyle(fontSize: 18),
                ),
                const SizedBox(width: 6),
                Text(
                  _selectedCountryCode.dialCode,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Icon(
                  Icons.arrow_drop_down_rounded,
                  color: Colors.white54,
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
            onFieldSubmitted: (_) => _companyFocus.requestFocus(),
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(color: Colors.white, fontSize: 14),
            cursorColor: AppTheme.brandGradientStart,
            validator: (val) {
              if (val == null || val.trim().isEmpty) {
                return 'Mobile number is required';
              }
              if (val.trim().length < 6) {
                return 'Enter valid phone number';
              }
              return null;
            },
            decoration: InputDecoration(
              labelText: 'Mobile Number',
              labelStyle: const TextStyle(color: Colors.white60, fontSize: 13),
              hintText: 'e.g. 501234567',
              hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
              prefixIcon: const Icon(Icons.phone_outlined,
                  color: Colors.white54, size: 20),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    BorderSide(color: Colors.white.withValues(alpha: 0.1)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    BorderSide(color: Colors.white.withValues(alpha: 0.1)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                    color: AppTheme.brandGradientStart, width: 1.5),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.eventxproDanger),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // Country / Nationality Selector Tile
  Widget _buildSelectorTile({
    required String label,
    required CountryModel? country,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: Row(
          children: [
            if (country != null) ...[
              Text(country.flagEmoji, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 10),
            ] else ...[
              const Icon(Icons.public_rounded, color: Colors.white54, size: 20),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    country?.label ?? 'Select $label',
                    style: TextStyle(
                      color: country != null ? Colors.white : Colors.white38,
                      fontSize: 13,
                      fontWeight:
                          country != null ? FontWeight.w600 : FontWeight.w400,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Colors.white54,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  // Sticky Bottom Submit Bar
  Widget _buildBottomSubmitBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF131722),
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          height: 50,
          child: Container(
            decoration: BoxDecoration(
              gradient: AppTheme.brandGradient,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.brandGradientStart.withValues(alpha: 0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _isSubmitting ? null : _submitRegistration,
                borderRadius: BorderRadius.circular(14),
                child: Center(
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.how_to_reg_rounded,
                                color: Colors.white, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'REGISTER ATTENDEE',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
}
