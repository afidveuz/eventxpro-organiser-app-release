/// Machine-readable decision codes matching EventXPro Django API contracts.
enum ScanDecisionCode {
  entryAllowed('ENTRY_ALLOWED', 'ACCEPTED', isSuccess: true),
  alreadyCheckedIn('ALREADY_CHECKED_IN', 'WARNING', isWarning: true),
  wrongEvent('WRONG_EVENT', 'REJECTED', isRejected: true),
  accessDenied('ACCESS_DENIED', 'REJECTED', isRejected: true),
  expired('EXPIRED', 'REJECTED', isRejected: true),
  invalidBadge('INVALID_BADGE', 'REJECTED', isRejected: true),
  notAuthorized('NOT_AUTHORIZED', 'REJECTED', isRejected: true),
  networkError('NETWORK_ERROR', 'PENDING', isNetworkError: true);

  final String code;
  final String status;
  final bool isSuccess;
  final bool isWarning;
  final bool isRejected;
  final bool isNetworkError;

  const ScanDecisionCode(
    this.code,
    this.status, {
    this.isSuccess = false,
    this.isWarning = false,
    this.isRejected = false,
    this.isNetworkError = false,
  });

  static ScanDecisionCode fromCode(String? code) {
    if (code == null) return ScanDecisionCode.invalidBadge;
    return ScanDecisionCode.values.firstWhere(
      (e) => e.code.toUpperCase() == code.toUpperCase(),
      orElse: () => ScanDecisionCode.accessDenied,
    );
  }
}
