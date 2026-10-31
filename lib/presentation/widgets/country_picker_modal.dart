import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/country_model.dart';

/// Searchable modal bottom sheet to pick a country / nationality / dial code
class CountryPickerModal extends StatefulWidget {
  final List<CountryModel> countries;
  final CountryModel? selectedCountry;
  final String title;
  final bool showDialCode;

  const CountryPickerModal({
    super.key,
    required this.countries,
    this.selectedCountry,
    this.title = 'Select Country',
    this.showDialCode = true,
  });

  static Future<CountryModel?> show(
    BuildContext context, {
    required List<CountryModel> countries,
    CountryModel? selectedCountry,
    String title = 'Select Country',
    bool showDialCode = true,
  }) {
    return showModalBottomSheet<CountryModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => CountryPickerModal(
        countries: countries,
        selectedCountry: selectedCountry,
        title: title,
        showDialCode: showDialCode,
      ),
    );
  }

  @override
  State<CountryPickerModal> createState() => _CountryPickerModalState();
}

class _CountryPickerModalState extends State<CountryPickerModal> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<CountryModel> _filtered = [];

  @override
  void initState() {
    super.initState();
    _filtered = widget.countries;
    _searchCtrl.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    final q = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      if (q.isEmpty) {
        _filtered = widget.countries;
      } else {
        _filtered = widget.countries.where((c) {
          final labelMatches = c.label.toLowerCase().contains(q);
          final codeMatches = c.code.toLowerCase().contains(q);
          final dialMatches = c.dialCode.toLowerCase().contains(q);
          return labelMatches || codeMatches || dialMatches;
        }).toList();
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final maxHeight = MediaQuery.of(context).size.height * 0.75;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      margin: EdgeInsets.only(bottom: bottomInset),
      decoration: const BoxDecoration(
        color: Color(0xFF131722),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: Color(0xFF2A3447), width: 1),
          left: BorderSide(color: Color(0xFF2A3447), width: 1),
          right: BorderSide(color: Color(0xFF2A3447), width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            const SizedBox(height: 12),
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),

            // Header title & close
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Search Box
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                ),
                child: TextField(
                  controller: _searchCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  cursorColor: AppTheme.brandGradientStart,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: Colors.white54,
                      size: 20,
                    ),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(
                              Icons.cancel_rounded,
                              color: Colors.white38,
                              size: 18,
                            ),
                            onPressed: () => _searchCtrl.clear(),
                          )
                        : null,
                    hintText: 'Search by name, code or dial code...',
                    hintStyle: const TextStyle(
                      color: Colors.white38,
                      fontSize: 13,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // List of countries
            Expanded(
              child: _filtered.isEmpty
                  ? const Center(
                      child: Text(
                        'No matching countries found',
                        style: TextStyle(color: Colors.white38, fontSize: 14),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _filtered.length,
                      physics: const BouncingScrollPhysics(),
                      itemBuilder: (context, index) {
                        final country = _filtered[index];
                        final isSelected = widget.selectedCountry?.code == country.code;

                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => Navigator.of(context).pop(country),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppTheme.brandGradientStart.withValues(alpha: 0.15)
                                    : Colors.transparent,
                                border: Border(
                                  bottom: BorderSide(
                                    color: Colors.white.withValues(alpha: 0.04),
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  // Flag emoji
                                  Text(
                                    country.flagEmoji,
                                    style: const TextStyle(fontSize: 22),
                                  ),
                                  const SizedBox(width: 14),

                                  // Country name
                                  Expanded(
                                    child: Text(
                                      country.label,
                                      style: TextStyle(
                                        color: isSelected
                                            ? Colors.white
                                            : Colors.white.withValues(alpha: 0.9),
                                        fontSize: 14,
                                        fontWeight: isSelected
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                      ),
                                    ),
                                  ),

                                  // Dial code or country code
                                  if (widget.showDialCode && country.dialCode.isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        country.dialCode,
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  const SizedBox(width: 8),

                                  if (isSelected)
                                    const Icon(
                                      Icons.check_circle_rounded,
                                      color: Color(0xFF10B981),
                                      size: 18,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
