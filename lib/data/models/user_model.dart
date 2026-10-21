import 'package:equatable/equatable.dart';

class UserModel extends Equatable {
  final String username;
  final String name;
  final bool isAdmin;
  final String? token;
  final String? refreshToken;

  const UserModel({
    required this.username,
    required this.name,
    this.isAdmin = false,
    this.token,
    this.refreshToken,
  });

  factory UserModel.fromJson(Map<String, dynamic> json, {String? token, String? refreshToken}) {
    return UserModel(
      username: json['username'] as String? ?? '',
      name: json['name'] as String? ?? '',
      isAdmin: (json['is_admin'] as bool?) ??
          (json['is_company_admin'] as bool?) ??
          (json['isAdmin'] as bool?) ??
          false,
      token: token ?? json['token'] as String?,
      refreshToken: refreshToken ?? json['refresh_token'] as String? ?? json['refreshToken'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'username': username,
      'name': name,
      'isAdmin': isAdmin,
      if (token != null) 'token': token,
      if (refreshToken != null) 'refreshToken': refreshToken,
    };
  }

  UserModel copyWith({
    String? username,
    String? name,
    bool? isAdmin,
    String? token,
    String? refreshToken,
  }) {
    return UserModel(
      username: username ?? this.username,
      name: name ?? this.name,
      isAdmin: isAdmin ?? this.isAdmin,
      token: token ?? this.token,
      refreshToken: refreshToken ?? this.refreshToken,
    );
  }

  @override
  List<Object?> get props => [username, name, isAdmin, token, refreshToken];
}
