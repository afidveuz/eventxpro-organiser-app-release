import 'package:equatable/equatable.dart';

abstract class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object?> get props => [];
}

class CheckAuthStatus extends AuthEvent {
  const CheckAuthStatus();
}

class LoginSubmitted extends AuthEvent {
  final String username;
  final String password;

  const LoginSubmitted({required this.username, required this.password});

  @override
  List<Object?> get props => [username, password];
}

class LogoutRequested extends AuthEvent {
  final String? reason;

  const LogoutRequested({this.reason});

  @override
  List<Object?> get props => [reason];
}

class UpdateBaseUrlRequested extends AuthEvent {
  final String newUrl;

  const UpdateBaseUrlRequested(this.newUrl);

  @override
  List<Object?> get props => [newUrl];
}

class ClearBaseUrlRequested extends AuthEvent {
  const ClearBaseUrlRequested();
}

class ClearAuthError extends AuthEvent {
  const ClearAuthError();
}
