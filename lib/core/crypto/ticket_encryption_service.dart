import 'dart:convert';
import 'package:dart_des/dart_des.dart';
import 'package:flutter/foundation.dart';
import '../config/app_constants.dart';

/// Offline ticket validation result
class TicketValidationResult {
  final bool isValid;
  final String decryptedPayload;
  final String normalizedCode;
  final String? errorMessage;

  const TicketValidationResult({
    required this.isValid,
    required this.decryptedPayload,
    required this.normalizedCode,
    this.errorMessage,
  });

  factory TicketValidationResult.valid({
    required String decryptedPayload,
    required String normalizedCode,
  }) {
    return TicketValidationResult(
      isValid: true,
      decryptedPayload: decryptedPayload,
      normalizedCode: normalizedCode,
    );
  }

  factory TicketValidationResult.invalid({
    required String normalizedCode,
    String message = 'Invalid QR Code',
  }) {
    return TicketValidationResult(
      isValid: false,
      decryptedPayload: '',
      normalizedCode: normalizedCode,
      errorMessage: message,
    );
  }
}

/// DES ECB Encryption & Decryption service matching React Native EventXPro Organiser
/// (OfflineScanner.jsx -> DESEncryption).
class TicketEncryptionService {
  final String defaultKey;

  TicketEncryptionService({
    this.defaultKey = AppConstants.defaultTicketEncryptionKey,
  });

  /// Parse encryption key from Base64, Python bytes string (`b"\x89..."`), or UTF-8.
  List<int> parseKey(String key) {
    try {
      final trimmed = key.trim();

      // Case 2: Key looks like Python bytes (starts with b" and contains \x..)
      if (trimmed.startsWith('b"') || trimmed.startsWith("b'")) {
        final raw = trimmed.substring(2, trimmed.length - 1);
        final regex = RegExp(r'\\x([0-9A-Fa-f]{2})');
        final matches = regex.allMatches(raw);
        if (matches.isNotEmpty) {
          final List<int> bytes = [];
          for (final m in matches) {
            bytes.add(int.parse(m.group(1)!, radix: 16));
          }
          if (bytes.length >= 8) {
            return bytes.sublist(0, 8);
          }
        }
      }

      // Case 1: Key looks like base64
      final base64Regex = RegExp(r'^[A-Za-z0-9+/=]+$');
      if (base64Regex.hasMatch(trimmed) && trimmed.length % 4 == 0) {
        try {
          final decoded = base64.decode(trimmed);
          if (decoded.length >= 8) {
            return decoded.sublist(0, 8);
          }
        } catch (_) {}
      }

      // Fallback: UTF-8 string padded or truncated to 8 bytes for DES
      final utf8Bytes = utf8.encode(trimmed);
      if (utf8Bytes.length >= 8) {
        return utf8Bytes.sublist(0, 8);
      } else {
        final padded = List<int>.filled(8, 0);
        for (int i = 0; i < utf8Bytes.length; i++) {
          padded[i] = utf8Bytes[i];
        }
        return padded;
      }
    } catch (e) {
      debugPrint('[TicketEncryptionService] ❌ parseKey error: $e');
      return base64.decode(AppConstants.defaultTicketEncryptionKey);
    }
  }

  /// Convert base32 string to binary bytes (for compatibility with Python's base32)
  List<int> base32ToBytes(String base32String) {
    const base32Chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    String bits = '';

    for (int i = 0; i < base32String.toUpperCase().length; i++) {
      final char = base32String[i];
      if (char == '=') break;
      final val = base32Chars.indexOf(char);
      if (val == -1) continue;
      bits += val.toRadixString(2).padLeft(5, '0');
    }

    final List<int> bytes = [];
    for (int i = 0; i < bits.length; i += 8) {
      if (i + 8 <= bits.length) {
        bytes.add(int.parse(bits.substring(i, i + 8), radix: 2));
      }
    }
    return bytes;
  }

  /// Convert binary bytes to base32 string (matching React Native base64ToBase32)
  String bytesToBase32(List<int> bytes) {
    const base32Chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    String bits = '';

    for (final b in bytes) {
      bits += b.toRadixString(2).padLeft(8, '0');
    }

    String base32 = '';
    for (int i = 0; i < bits.length; i += 5) {
      if (i + 5 <= bits.length) {
        final chunk = bits.substring(i, i + 5);
        base32 += base32Chars[int.parse(chunk, radix: 2)];
      } else {
        final chunk = bits.substring(i).padRight(5, '0');
        base32 += base32Chars[int.parse(chunk, radix: 2)];
      }
    }

    while (base32.length % 8 != 0) {
      base32 += '=';
    }

    return base32;
  }

  /// Decrypt base32-encoded DES ECB ticket
  String decryptTicket(String ticketId, {String? keyString}) {
    try {
      final keyBytes = parseKey(keyString ?? defaultKey);
      final cipherBytes = base32ToBytes(ticketId.trim());

      if (cipherBytes.isEmpty || cipherBytes.length % 8 != 0) {
        return '';
      }

      final des = DES(
        key: keyBytes,
        mode: DESMode.ECB,
        paddingType: DESPaddingType.PKCS7,
      );

      final decryptedBytes = des.decrypt(cipherBytes);
      final decrypted = utf8.decode(decryptedBytes, allowMalformed: false);
      return decrypted;
    } catch (_) {
      // If decryption fails or bytes are not valid UTF-8, return empty string
      return '';
    }
  }

  /// Encrypt plain text ticket into base32-encoded DES ECB string
  String encryptTicket(String message, {String? keyString}) {
    try {
      final keyBytes = parseKey(keyString ?? defaultKey);
      final messageBytes = utf8.encode(message);

      final des = DES(
        key: keyBytes,
        mode: DESMode.ECB,
        paddingType: DESPaddingType.PKCS7,
      );

      final encryptedBytes = des.encrypt(messageBytes);
      return bytesToBase32(encryptedBytes);
    } catch (e) {
      debugPrint('[TicketEncryptionService] ❌ encryptTicket error: $e');
      return '';
    }
  }

  /// Primary validation function matching React Native `OfflineScanner.jsx`:
  /// - Tries decryptTicket
  /// - Strips ASCII \u0002 padding
  /// - Checks if trimmed decrypted payload is non-empty
  TicketValidationResult validateTicket({
    required String rawQrToken,
    String? keyString,
    bool allowTestPrefixes = true,
  }) {
    final token = rawQrToken.trim();
    if (token.isEmpty) {
      return TicketValidationResult.invalid(
        normalizedCode: token,
        message: 'Empty QR code',
      );
    }

    // 1. Attempt standard EventXPro DES decryption
    final decrypted = decryptTicket(token, keyString: keyString);
    final trimmedDecrypted = decrypted.replaceAll('\u0002', '').trim();

    if (trimmedDecrypted.isNotEmpty) {
      final reEncrypted = encryptTicket(trimmedDecrypted, keyString: keyString);
      return TicketValidationResult.valid(
        decryptedPayload: trimmedDecrypted,
        normalizedCode: reEncrypted.isNotEmpty ? reEncrypted : token,
      );
    }

    // 2. Fallback for test/demo tokens (VIP-, EXH-, TEST-, DEMO-)
    if (allowTestPrefixes) {
      final upper = token.toUpperCase();
      if (upper.startsWith('VIP') ||
          upper.startsWith('EXH') ||
          upper.startsWith('TEST') ||
          upper.startsWith('DEMO')) {
        return TicketValidationResult.valid(
          decryptedPayload: token,
          normalizedCode: token,
        );
      }
    }

    return TicketValidationResult.invalid(
      normalizedCode: token,
      message: 'Invalid QR Code',
    );
  }
}
