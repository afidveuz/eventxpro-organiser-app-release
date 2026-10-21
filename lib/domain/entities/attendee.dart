import 'package:equatable/equatable.dart';

/// Least-privilege attendee information returned only after authorized admission.
class Attendee extends Equatable {
  final String name;
  final String badgeType;
  final String? company;
  final String? category;

  const Attendee({
    required this.name,
    required this.badgeType,
    this.company,
    this.category,
  });

  String get fullName => name;

  factory Attendee.fromJson(Map<String, dynamic> json) {
    return Attendee(
      name: json['name'] as String? ?? 'Authorized Attendee',
      badgeType: json['badge_type'] as String? ?? 'General Admission',
      company: json['company'] as String?,
      category: json['category'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'badge_type': badgeType,
      if (company != null) 'company': company,
      if (category != null) 'category': category,
    };
  }

  @override
  List<Object?> get props => [name, badgeType, company, category];
}
