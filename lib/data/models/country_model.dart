class CountryModel {
  final String label;
  final String code; // 2-letter ISO (e.g. "AE", "IN", "US")
  final String dialCode; // e.g. "+971", "+91"

  const CountryModel({
    required this.label,
    required this.code,
    required this.dialCode,
  });

  /// Convert 2-letter ISO country code (e.g. "AE") into Unicode Flag emoji (🇦🇪)
  String get flagEmoji {
    if (code.length != 2) return '🌐';
    final upper = code.toUpperCase();
    final first = upper.codeUnitAt(0) - 0x41 + 0x1F1E6;
    final second = upper.codeUnitAt(1) - 0x41 + 0x1F1E6;
    if (first < 0x1F1E6 || first > 0x1F1FF || second < 0x1F1E6 || second > 0x1F1FF) {
      return '🌐';
    }
    return String.fromCharCode(first) + String.fromCharCode(second);
  }

  factory CountryModel.fromJson(Map<String, dynamic> json) {
    String dial = (json['dial_code'] ?? json['dialCode'] ?? json['phone_code'] ?? '').toString().trim();
    if (dial.isNotEmpty && !dial.startsWith('+')) {
      dial = '+$dial';
    }

    return CountryModel(
      label: (json['label'] ?? json['country_name'] ?? json['name'] ?? '').toString().trim(),
      code: (json['code'] ?? json['country_code'] ?? json['iso2'] ?? '').toString().toUpperCase().trim(),
      dialCode: dial,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'label': label,
      'code': code,
      'dial_code': dialCode,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CountryModel &&
          runtimeType == other.runtimeType &&
          code == other.code;

  @override
  int get hashCode => code.hashCode;

  /// Default fallback list of popular & global countries
  static const List<CountryModel> defaultCountries = [
    CountryModel(label: 'United Arab Emirates', code: 'AE', dialCode: '+971'),
    CountryModel(label: 'India', code: 'IN', dialCode: '+91'),
    CountryModel(label: 'Saudi Arabia', code: 'SA', dialCode: '+966'),
    CountryModel(label: 'United Kingdom', code: 'GB', dialCode: '+44'),
    CountryModel(label: 'United States', code: 'US', dialCode: '+1'),
    CountryModel(label: 'Qatar', code: 'QA', dialCode: '+974'),
    CountryModel(label: 'Oman', code: 'OM', dialCode: '+968'),
    CountryModel(label: 'Kuwait', code: 'KW', dialCode: '+965'),
    CountryModel(label: 'Bahrain', code: 'BH', dialCode: '+973'),
    CountryModel(label: 'Nigeria', code: 'NG', dialCode: '+234'),
    CountryModel(label: 'Singapore', code: 'SG', dialCode: '+65'),
    CountryModel(label: 'Canada', code: 'CA', dialCode: '+1'),
    CountryModel(label: 'Australia', code: 'AU', dialCode: '+61'),
    CountryModel(label: 'Germany', code: 'DE', dialCode: '+49'),
    CountryModel(label: 'France', code: 'FR', dialCode: '+33'),
    CountryModel(label: 'South Africa', code: 'ZA', dialCode: '+27'),
    CountryModel(label: 'Egypt', code: 'EG', dialCode: '+20'),
    CountryModel(label: 'Kenya', code: 'KE', dialCode: '+254'),
    CountryModel(label: 'Pakistan', code: 'PK', dialCode: '+92'),
    CountryModel(label: 'Bangladesh', code: 'BD', dialCode: '+880'),
    CountryModel(label: 'Philippines', code: 'PH', dialCode: '+63'),
    CountryModel(label: 'Malaysia', code: 'MY', dialCode: '+60'),
    CountryModel(label: 'Indonesia', code: 'ID', dialCode: '+62'),
    CountryModel(label: 'Turkey', code: 'TR', dialCode: '+90'),
    CountryModel(label: 'Italy', code: 'IT', dialCode: '+39'),
    CountryModel(label: 'Spain', code: 'ES', dialCode: '+34'),
    CountryModel(label: 'China', code: 'CN', dialCode: '+86'),
    CountryModel(label: 'Japan', code: 'JP', dialCode: '+81'),
    CountryModel(label: 'Brazil', code: 'BR', dialCode: '+55'),
    CountryModel(label: 'Switzerland', code: 'CH', dialCode: '+41'),
    CountryModel(label: 'Netherlands', code: 'NL', dialCode: '+31'),
    CountryModel(label: 'Sweden', code: 'SE', dialCode: '+46'),
    CountryModel(label: 'Norway', code: 'NO', dialCode: '+47'),
    CountryModel(label: 'Denmark', code: 'DK', dialCode: '+45'),
    CountryModel(label: 'Russia', code: 'RU', dialCode: '+7'),
    CountryModel(label: 'Sri Lanka', code: 'LK', dialCode: '+94'),
    CountryModel(label: 'Nepal', code: 'NP', dialCode: '+977'),
    CountryModel(label: 'New Zealand', code: 'NZ', dialCode: '+64'),
    CountryModel(label: 'Ireland', code: 'IE', dialCode: '+353'),
    CountryModel(label: 'Jordan', code: 'JO', dialCode: '+962'),
    CountryModel(label: 'Lebanon', code: 'LB', dialCode: '+961'),
  ];
}
