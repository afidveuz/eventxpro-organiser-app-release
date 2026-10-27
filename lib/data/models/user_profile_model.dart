import 'package:equatable/equatable.dart';

/// User profile model representing the organizer's profile from 'organizer/user-profile'.
class UserProfileModel extends Equatable {
  final String name;
  final String username;
  final String email;
  final String phone;
  final String? photo;
  final bool isAdmin;

  const UserProfileModel({
    required this.name,
    required this.username,
    required this.email,
    required this.phone,
    this.photo,
    this.isAdmin = false,
  });

  factory UserProfileModel.fromJson(Map<String, dynamic> json) {
    // Gracefully handle if the API response is wrapped in { "data": { ... } }
    final map = (json['data'] is Map<String, dynamic>)
        ? json['data'] as Map<String, dynamic>
        : json;

    return UserProfileModel(
      name: (map['name'] as String?)?.trim() ?? '',
      username: (map['username'] as String?)?.trim() ?? '',
      email: (map['email'] as String?)?.trim() ?? '',
      phone: (map['phone'] as String?)?.trim() ?? '',
      photo: map['photo'] as String?,
      isAdmin: (map['is_admin'] as bool?) ??
          (map['is_company_admin'] as bool?) ??
          (map['isAdmin'] as bool?) ??
          false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'username': username,
      'email': email,
      'phone': phone,
      'photo': photo,
      'isAdmin': isAdmin,
    };
  }

  /// Calculates initials matching the React Native 'nameShoter' logic:
  /// Splits by spaces: if multiple words, takes first letters of first two words.
  /// If single word, takes first letter. Fallback to 'P'.
  String get initials {
    if (name.trim().isEmpty) {
      if (username.trim().isNotEmpty) {
        return username.trim()[0].toUpperCase();
      }
      return 'P';
    }
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length > 1 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    } else if (parts.isNotEmpty && parts[0].isNotEmpty) {
      return parts[0][0].toUpperCase();
    }
    return 'P';
  }

  UserProfileModel copyWith({
    String? name,
    String? username,
    String? email,
    String? phone,
    String? photo,
    bool? isAdmin,
  }) {
    return UserProfileModel(
      name: name ?? this.name,
      username: username ?? this.username,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      photo: photo ?? this.photo,
      isAdmin: isAdmin ?? this.isAdmin,
    );
  }

  @override
  List<Object?> get props => [name, username, email, phone, photo, isAdmin];
}
