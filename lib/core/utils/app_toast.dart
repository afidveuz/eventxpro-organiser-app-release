import 'package:flutter/material.dart';
import 'package:toastification/toastification.dart';
import '../../main.dart';

/// Centralized Toast Notification utility using [Toastification].
///
/// Designed to replace Flutter's default [SnackBar] throughout the application
/// with a modern, high-contrast, minimalist card design:
/// - Clean white background card with right-curved corners
/// - Colored vertical accent border on the left
/// - Circular outline type icon
/// - Crisp, readable dark typography
/// - Interactive dismiss button ('x') and swipe-to-close
///
/// **Context-Free**:
/// Because [ToastificationWrapper] is declared at the app root in `main.dart`,
/// [context] is completely optional across all methods. You can call
/// `AppToast.showSuccess(message: '...')` or shorthand `AppToast.success('...')`
/// from anywhere in the codebase without passing a [BuildContext].
class AppToast {
  AppToast._();

  /// Default animation duration for toast appearances/exits
  static const Duration defaultAnimationDuration = Duration(milliseconds: 300);

  /// Default auto-close duration for toasts
  static const Duration defaultDuration = Duration(seconds: 3);

  /// Shorthand: Displays a success toast without requiring [context].
  static ToastificationItem? success(
    String message, {
    String? title,
    BuildContext? context,
    Duration duration = defaultDuration,
    Color? primaryColor,
    Alignment alignment = Alignment.bottomCenter,
    ToastificationStyle style = ToastificationStyle.minimal,
    bool showProgressBar = false,
    bool showCloseButton = true,
    VoidCallback? onTap,
  }) =>
      showSuccess(
        message: message,
        title: title,
        context: context,
        duration: duration,
        primaryColor: primaryColor,
        alignment: alignment,
        style: style,
        showProgressBar: showProgressBar,
        showCloseButton: showCloseButton,
        onTap: onTap,
      );

  /// Shorthand: Displays an error toast without requiring [context].
  static ToastificationItem? error(
    String message, {
    String? title,
    BuildContext? context,
    Duration duration = defaultDuration,
    Color? primaryColor,
    Alignment alignment = Alignment.bottomCenter,
    ToastificationStyle style = ToastificationStyle.minimal,
    bool showProgressBar = false,
    bool showCloseButton = true,
    VoidCallback? onTap,
  }) =>
      showError(
        message: message,
        title: title,
        context: context,
        duration: duration,
        primaryColor: primaryColor,
        alignment: alignment,
        style: style,
        showProgressBar: showProgressBar,
        showCloseButton: showCloseButton,
        onTap: onTap,
      );

  /// Shorthand: Displays a warning toast without requiring [context].
  static ToastificationItem? warning(
    String message, {
    String? title,
    BuildContext? context,
    Duration duration = defaultDuration,
    Color? primaryColor,
    Alignment alignment = Alignment.bottomCenter,
    ToastificationStyle style = ToastificationStyle.minimal,
    bool showProgressBar = false,
    bool showCloseButton = true,
    VoidCallback? onTap,
  }) =>
      showWarning(
        message: message,
        title: title,
        context: context,
        duration: duration,
        primaryColor: primaryColor,
        alignment: alignment,
        style: style,
        showProgressBar: showProgressBar,
        showCloseButton: showCloseButton,
        onTap: onTap,
      );

  /// Shorthand: Displays an info toast without requiring [context].
  static ToastificationItem? info(
    String message, {
    String? title,
    BuildContext? context,
    Duration duration = defaultDuration,
    Color? primaryColor,
    Alignment alignment = Alignment.bottomCenter,
    ToastificationStyle style = ToastificationStyle.minimal,
    bool showProgressBar = false,
    bool showCloseButton = true,
    VoidCallback? onTap,
  }) =>
      showInfo(
        message: message,
        title: title,
        context: context,
        duration: duration,
        primaryColor: primaryColor,
        alignment: alignment,
        style: style,
        showProgressBar: showProgressBar,
        showCloseButton: showCloseButton,
        onTap: onTap,
      );

  /// Displays a success toast notification.
  /// [context] is optional. If omitted, [ToastificationWrapper] or [appNavigatorKey] will be used.
  static ToastificationItem? showSuccess({
    BuildContext? context,
    required String message,
    String? title,
    Duration duration = defaultDuration,
    Color? primaryColor,
    Alignment alignment = Alignment.bottomCenter,
    ToastificationStyle style = ToastificationStyle.minimal,
    bool showProgressBar = false,
    bool showCloseButton = true,
    VoidCallback? onTap,
  }) {
    return _show(
      context: context,
      type: ToastificationType.success,
      primaryColor: primaryColor,
      message: message,
      title: title,
      duration: duration,
      alignment: alignment,
      style: style,
      showProgressBar: showProgressBar,
      showCloseButton: showCloseButton,
      onTap: onTap,
    );
  }

  /// Displays an error toast notification.
  /// [context] is optional. If omitted, [ToastificationWrapper] or [appNavigatorKey] will be used.
  static ToastificationItem? showError({
    BuildContext? context,
    required String message,
    String? title,
    Duration duration = defaultDuration,
    Color? primaryColor,
    Alignment alignment = Alignment.bottomCenter,
    ToastificationStyle style = ToastificationStyle.minimal,
    bool showProgressBar = false,
    bool showCloseButton = true,
    VoidCallback? onTap,
  }) {
    return _show(
      context: context,
      type: ToastificationType.error,
      primaryColor: primaryColor,
      message: message,
      title: title,
      duration: duration,
      alignment: alignment,
      style: style,
      showProgressBar: showProgressBar,
      showCloseButton: showCloseButton,
      onTap: onTap,
    );
  }

  /// Displays a warning toast notification.
  /// [context] is optional. If omitted, [ToastificationWrapper] or [appNavigatorKey] will be used.
  static ToastificationItem? showWarning({
    BuildContext? context,
    required String message,
    String? title,
    Duration duration = defaultDuration,
    Color? primaryColor,
    Alignment alignment = Alignment.bottomCenter,
    ToastificationStyle style = ToastificationStyle.minimal,
    bool showProgressBar = false,
    bool showCloseButton = true,
    VoidCallback? onTap,
  }) {
    return _show(
      context: context,
      type: ToastificationType.warning,
      primaryColor: primaryColor,
      message: message,
      title: title,
      duration: duration,
      alignment: alignment,
      style: style,
      showProgressBar: showProgressBar,
      showCloseButton: showCloseButton,
      onTap: onTap,
    );
  }

  /// Displays an informational toast notification.
  /// [context] is optional. If omitted, [ToastificationWrapper] or [appNavigatorKey] will be used.
  static ToastificationItem? showInfo({
    BuildContext? context,
    required String message,
    String? title,
    Duration duration = defaultDuration,
    Color? primaryColor,
    Alignment alignment = Alignment.bottomCenter,
    ToastificationStyle style = ToastificationStyle.minimal,
    bool showProgressBar = false,
    bool showCloseButton = true,
    VoidCallback? onTap,
  }) {
    return _show(
      context: context,
      type: ToastificationType.info,
      primaryColor: primaryColor,
      message: message,
      title: title,
      duration: duration,
      alignment: alignment,
      style: style,
      showProgressBar: showProgressBar,
      showCloseButton: showCloseButton,
      onTap: onTap,
    );
  }

  /// Internal builder for predefined typed toasts.
  static ToastificationItem? _show({
    BuildContext? context,
    required ToastificationType type,
    Color? primaryColor,
    required String message,
    String? title,
    Duration duration = defaultDuration,
    Alignment alignment = Alignment.bottomCenter,
    ToastificationStyle style = ToastificationStyle.minimal,
    bool showProgressBar = false,
    bool showCloseButton = true,
    VoidCallback? onTap,
  }) {
    final effectiveContext = (context != null && context.mounted)
        ? context
        : (appNavigatorKey.currentContext?.mounted == true
            ? appNavigatorKey.currentContext
            : null);

    try {
      return toastification.show(
        context: effectiveContext,
        type: type,
        style: style,
        primaryColor: primaryColor,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        borderSide: const BorderSide(
          color: Color(0xFFE2E8F0),
          width: 1.0,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F000000),
            blurRadius: 16,
            spreadRadius: 0,
            offset: Offset(0, 4),
          ),
        ],
        title: title != null
            ? Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              )
            : Text(
                message,
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                  height: 1.3,
                ),
              ),
        description: title != null
            ? Text(
                message,
                style: const TextStyle(
                  color: Color(0xFF334155),
                  fontWeight: FontWeight.w400,
                  fontSize: 12,
                  height: 1.3,
                ),
              )
            : null,
        alignment: alignment,
        autoCloseDuration: duration,
        animationDuration: defaultAnimationDuration,
        borderRadius: BorderRadius.circular(12),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        showProgressBar: showProgressBar,
        dragToClose: true,
        closeOnClick: true,
        closeButton: ToastCloseButton(
          showType: showCloseButton ? CloseButtonShowType.always : CloseButtonShowType.none,
        ),
        callbacks: ToastificationCallbacks(
          onTap: onTap != null ? (_) => onTap() : null,
        ),
      );
    } catch (e) {
      debugPrint('[AppToast] Toastification display notice: $e');
      return null;
    }
  }

  /// Displays a custom toast widget.
  /// [context] is optional. If omitted, [ToastificationWrapper] or [appNavigatorKey] will be used.
  static ToastificationItem? showCustom({
    BuildContext? context,
    required Widget child,
    Duration duration = defaultDuration,
    Alignment alignment = Alignment.bottomCenter,
  }) {
    final effectiveContext = (context != null && context.mounted)
        ? context
        : (appNavigatorKey.currentContext?.mounted == true
            ? appNavigatorKey.currentContext
            : null);

    try {
      return toastification.showCustom(
        context: effectiveContext,
        alignment: alignment,
        autoCloseDuration: duration,
        animationDuration: defaultAnimationDuration,
        builder: (context, holder) {
          return Material(
            type: MaterialType.transparency,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: child,
            ),
          );
        },
      );
    } catch (e) {
      debugPrint('[AppToast] Toastification showCustom notice: $e');
      return null;
    }
  }

  /// Dismisses all visible and queued toasts.
  static void dismissAll({bool delayForAnimation = false}) {
    try {
      toastification.dismissAll(delayForAnimation: delayForAnimation);
    } catch (_) {}
  }
}
