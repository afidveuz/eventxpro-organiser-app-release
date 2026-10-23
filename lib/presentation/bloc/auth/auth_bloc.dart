import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/auth_repository.dart';
import 'auth_event.dart';
import 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthRepository _authRepository;

  AuthBloc({required AuthRepository authRepository})
      : _authRepository = authRepository,
        super(const AuthInitial()) {
    on<CheckAuthStatus>(_onCheckAuthStatus);
    on<LoginSubmitted>(_onLoginSubmitted);
    on<LogoutRequested>(_onLogoutRequested);
    on<UpdateBaseUrlRequested>(_onUpdateBaseUrlRequested);
    on<ClearBaseUrlRequested>(_onClearBaseUrlRequested);
    on<ClearAuthError>(_onClearAuthError);
  }

  Future<void> _onCheckAuthStatus(
    CheckAuthStatus event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoading());
    // Small delay to let splash animation look smooth
    await Future.delayed(const Duration(milliseconds: 1200));

    if (_authRepository.isLoggedIn) {
      final user = _authRepository.currentUser;
      if (user != null) {
        emit(AuthAuthenticated(user));
        return;
      }
    }
    emit(const AuthUnauthenticated());
  }

  Future<void> _onLoginSubmitted(
    LoginSubmitted event,
    Emitter<AuthState> emit,
  ) async {
    final user = event.username.trim();
    final pass = event.password;

    if (user.isEmpty && pass.isEmpty) {
      emit(const AuthUnauthenticated(errorMessage: 'Please enter username and password'));
      return;
    }
    if (user.isEmpty) {
      emit(const AuthUnauthenticated(errorMessage: 'Please enter username'));
      return;
    }
    if (pass.isEmpty) {
      emit(const AuthUnauthenticated(errorMessage: 'Please enter password'));
      return;
    }

    emit(const AuthLoading(message: 'Logging in...'));

    final result = await _authRepository.login(
      username: user,
      password: pass,
    );

    if (result.isSuccess && result.user != null) {
      emit(AuthAuthenticated(result.user!));
    } else {
      emit(AuthUnauthenticated(errorMessage: result.errorMessage ?? 'Login failed'));
    }
  }

  Future<void> _onLogoutRequested(
    LogoutRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoading(message: 'Logging out...'));
    await _authRepository.logout();
    emit(AuthUnauthenticated(errorMessage: event.reason));
  }

  Future<void> _onUpdateBaseUrlRequested(
    UpdateBaseUrlRequested event,
    Emitter<AuthState> emit,
  ) async {
    await _authRepository.updateBaseUrl(event.newUrl);
  }

  Future<void> _onClearBaseUrlRequested(
    ClearBaseUrlRequested event,
    Emitter<AuthState> emit,
  ) async {
    await _authRepository.clearBaseUrl();
  }

  void _onClearAuthError(
    ClearAuthError event,
    Emitter<AuthState> emit,
  ) {
    if (state is AuthUnauthenticated) {
      emit(const AuthUnauthenticated(errorMessage: null));
    }
  }
}
