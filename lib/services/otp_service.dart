import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

/// MSG91 OTP Service using direct HTTP requests mapped exactly to the official SDK's endpoints.
class OtpService {
  // ─── MSG91 credentials ───────────────────────────────────────────────────
  static const String _widgetId = '3665416a5a62383637323534';
  static const String _widgetToken = '520388TzMUqRNl3Nw6a16d252P1'; // Widget-specific App Token
  // Stores the unique request ID from the sendOtp response (used for verification)
  static String? _currentReqId;

  OtpService();

  /// Helper to send requests and handle redirects.
  /// Follows MSG91's official SDK redirect logic: initial POST requests are redirected 
  /// by the gateway into GET requests (which contain all query parameters already mapped).
  Future<http.Response> _sendRequest(Uri url, Map<String, dynamic> body, {bool isPost = true, int redirectCount = 0}) async {
    if (redirectCount > 5) {
      throw Exception('Too many redirects');
    }

    http.Response response;
    if (isPost) {
      response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json; charset=UTF-8',
        },
        body: jsonEncode(body),
      );
    } else {
      response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json; charset=UTF-8',
        },
      );
    }

    // If redirected, follow it as a GET request as required by MSG91's endpoints
    if (response.statusCode >= 300 && response.statusCode < 400) {
      final redirectUrl = response.headers['location'];
      if (redirectUrl != null) {
        debugPrint('MSG91: Redirected (${response.statusCode}) to $redirectUrl. Following via GET...');
        return _sendRequest(Uri.parse(redirectUrl), body, isPost: false, redirectCount: redirectCount + 1);
      }
    }

    return response;
  }

  /// Sends OTP to the given mobile number.
  /// [mobile] must be country code + number without '+', e.g. "917208155789"
  Future<bool> sendOtp({
    required String mobile,
    required Function() onSuccess,
    required Function(String error) onError,
  }) async {
    try {
      final url = Uri.parse('https://api.msg91.com/api/v5/widget/sendOtpMobile');
      debugPrint('MSG91: Sending OTP request to $url with mobile: $mobile');

      final response = await _sendRequest(
        url,
        {
          'widgetId': _widgetId,
          'tokenAuth': _widgetToken,
          'identifier': mobile,
        },
        isPost: true,
      );

      debugPrint('MSG91 sendOTP response status: ${response.statusCode}');
      debugPrint('MSG91 sendOTP response body: ${response.body}');

      if (response.body.isEmpty) {
        onError('Server returned an empty response. Please try again.');
        return false;
      }

      final data = jsonDecode(response.body);

      if (data != null && data['type'] == 'success') {
        _currentReqId = data['reqId']?.toString() ?? data['message']?.toString();
        debugPrint('MSG91 sendOTP successful. Request ID: $_currentReqId');
        onSuccess();
        return true;
      } else {
        final errMsg = data?['message']?.toString() ?? 'Failed to send OTP.';
        onError('$errMsg (Code: ${data?['code'] ?? response.statusCode})');
        return false;
      }
    } catch (e) {
      debugPrint('MSG91 sendOTP exception: $e');
      onError('Failed to connect to OTP service. Check your internet connection.');
      return false;
    }
  }

  /// Verifies the OTP entered by the user.
  Future<bool> verifyOtp({
    required String mobile,
    required String otp,
    required Function() onSuccess,
    required Function(String error) onError,
  }) async {
    try {
      final url = Uri.parse('https://api.msg91.com/api/v5/widget/verifyOtp');
      debugPrint('MSG91: Verifying OTP via widget API for mobile: $mobile');

      final response = await _sendRequest(
        url,
        {
          'widgetId': _widgetId,
          'tokenAuth': _widgetToken,
          'identifier': mobile,
          'reqId': _currentReqId,
          'otp': otp,
        },
        isPost: true,
      );

      debugPrint('MSG91 verifyOTP response status: ${response.statusCode}');
      debugPrint('MSG91 verifyOTP response body: ${response.body}');

      if (response.body.isEmpty) {
        onError('Server returned an empty response. Please try again.');
        return false;
      }

      final data = jsonDecode(response.body);
      if (data != null && data['type'] == 'success') {
        onSuccess();
        return true;
      } else {
        final errMsg = data?['message']?.toString() ?? 'Invalid OTP. Please try again.';
        onError(errMsg);
        return false;
      }
    } catch (e) {
      debugPrint('MSG91 verifyOTP exception: $e');
      onError('Verification failed. Please check your connection.');
      return false;
    }
  }

  /// Resends OTP using MSG91 retry endpoint or falls back to sending again.
  Future<bool> resendOtp({
    required String mobile,
    required Function() onSuccess,
    required Function(String error) onError,
  }) async {
    try {
      final url = Uri.parse('https://api.msg91.com/api/v5/widget/retryOtp');
      debugPrint('MSG91: Retrying OTP for mobile: $mobile');

      final response = await _sendRequest(
        url,
        {
          'widgetId': _widgetId,
          'tokenAuth': _widgetToken,
          'identifier': mobile,
          'reqId': _currentReqId,
          'retryChannel': 'sms',
        },
        isPost: true,
      );

      debugPrint('MSG91 retryOTP response status: ${response.statusCode}');
      debugPrint('MSG91 retryOTP response body: ${response.body}');

      if (response.body.isEmpty) {
        return sendOtp(mobile: mobile, onSuccess: onSuccess, onError: onError);
      }

      final data = jsonDecode(response.body);
      if (data != null && data['type'] == 'success') {
        onSuccess();
        return true;
      } else {
        debugPrint('MSG91: Retry endpoint failed. Falling back to fresh sendOtp.');
        return sendOtp(mobile: mobile, onSuccess: onSuccess, onError: onError);
      }
    } catch (e) {
      debugPrint('MSG91 retryOTP exception: $e');
      return sendOtp(mobile: mobile, onSuccess: onSuccess, onError: onError);
    }
  }

  /// Converts a full phone number like "+917208155789" to MSG91 format "917208155789"
  static String formatMobile(String phoneNumber) {
    return phoneNumber.replaceAll(RegExp(r'[\s\-\+]'), '');
  }
}
