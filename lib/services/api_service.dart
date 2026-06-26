import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

/// Central API service for communicating with the Neon backend.
/// Replace [_baseUrl] with your actual backend server URL.
class ApiService {
  // ─── Backend URL ──────────────────────────────────────────────────────────
  // For physical Android devices connected via USB, we set up ADB port forwarding: adb reverse tcp:3000 tcp:3000
  // Local development URL pointing to your local MS SQL backend
  static const String _baseUrl = 'http://localhost:3000/api';
  // Production URL:
  // static const String _baseUrl = 'https://neonine-systems-internship-backend.onrender.com/api';

  // Timeout duration for API calls
  static const Duration _timeout = Duration(seconds: 10);

  ApiService();

  // ─── Helper: Make HTTP requests ───────────────────────────────────────────

  Future<Map<String, dynamic>?> _get(String endpoint, {Map<String, String>? queryParams}) async {
    try {
      final uri = Uri.parse('$_baseUrl$endpoint').replace(queryParameters: queryParams);
      debugPrint('API GET: $uri');

      final response = await http.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      ).timeout(_timeout);

      debugPrint('API response (${response.statusCode}): ${response.body}');

      if (response.statusCode == 200) {
        if (response.body.isEmpty) return {};
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else if (response.statusCode == 404) {
        return null;
      } else {
        throw Exception('API error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('API GET error: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> _post(String endpoint, Map<String, dynamic> body) async {
    try {
      final uri = Uri.parse('$_baseUrl$endpoint');
      debugPrint('API POST: $uri');

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(_timeout);

      debugPrint('API response (${response.statusCode}): ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (response.body.isEmpty) return {};
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception('API error: ${response.statusCode} — ${response.body}');
      }
    } catch (e) {
      debugPrint('API POST error: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> _put(String endpoint, Map<String, dynamic> body) async {
    try {
      final uri = Uri.parse('$_baseUrl$endpoint');
      debugPrint('API PUT: $uri');

      final response = await http.put(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(_timeout);

      debugPrint('API response (${response.statusCode}): ${response.body}');

      if (response.statusCode == 200) {
        if (response.body.isEmpty) return {};
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception('API error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('API PUT error: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> _delete(String endpoint) async {
    try {
      final uri = Uri.parse('$_baseUrl$endpoint');
      debugPrint('API DELETE: $uri');

      final response = await http.delete(
        uri,
        headers: {'Content-Type': 'application/json'},
      ).timeout(_timeout);

      debugPrint('API response (${response.statusCode}): ${response.body}');

      if (response.statusCode == 200) {
        if (response.body.isEmpty) return {};
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception('API error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('API DELETE error: $e');
      rethrow;
    }
  }

  // ─── User endpoints ──────────────────────────────────────────────────────

  /// Check if a user exists by phone number.
  /// Returns user data if found, null if not registered.
  Future<Map<String, dynamic>?> getUserByPhone(String phone) async {
    return await _get('/users/phone/$phone');
  }

  /// Register a new user.
  /// Returns the created user data.
  Future<Map<String, dynamic>?> registerUser({
    required String fullName,
    required String phoneNumber,
    required String userType,
    required String aadhaarNumber,
    String? villageArea,
    String? address,
    double? latitude,
    double? longitude,
    // Service provider specific fields
    String? serviceName,
    List<int>? categoryIds,
  }) async {
    final body = <String, dynamic>{
      'full_name': fullName,
      'phone_number': phoneNumber,
      'user_type': userType,
      'aadhaar_number': aadhaarNumber,
      'village_area': villageArea,
      'address': address,
      'latitude': latitude,
      'longitude': longitude,
    };

    if (userType == 'service_provider') {
      body['service_name'] = serviceName;
      body['category_ids'] = categoryIds;
    }

    return await _post('/users/register', body);
  }

  // ─── Location endpoints ──────────────────────────────────────────────────

  /// Update user's GPS location.
  Future<Map<String, dynamic>?> updateLocation({
    required String userId,
    required double latitude,
    required double longitude,
  }) async {
    return await _put('/users/$userId/location', {
      'latitude': latitude,
      'longitude': longitude,
    });
  }

  // ─── Provider endpoints ──────────────────────────────────────────────────

  /// Get nearby online service providers within a radius (in km).
  Future<List<Map<String, dynamic>>> getNearbyProviders({
    required double latitude,
    required double longitude,
    double radiusKm = 25.0,
    String? categoryFilter,
  }) async {
    final params = <String, String>{
      'lat': latitude.toString(),
      'lng': longitude.toString(),
      'radius': radiusKm.toString(),
    };
    if (categoryFilter != null) {
      params['category'] = categoryFilter;
    }

    final response = await _get('/providers/nearby', queryParams: params);
    if (response != null && response['providers'] != null) {
      return List<Map<String, dynamic>>.from(response['providers']);
    }
    return [];
  }

  /// Toggle online/offline status for a service provider.
  Future<Map<String, dynamic>?> toggleOnlineStatus({
    required String userId,
    required bool isOnline,
  }) async {
    return await _put('/providers/$userId/status', {
      'is_online': isOnline,
    });
  }

  // ─── Service request endpoints ────────────────────────────────────────────

  /// Get today's request count for a service provider.
  Future<int> getTodayRequestCount(String providerId) async {
    final response = await _get('/providers/$providerId/requests/today');
    if (response != null && response['count'] != null) {
      return response['count'] as int;
    }
    return 0;
  }

  /// Get today's requests list for a service provider.
  Future<List<Map<String, dynamic>>> getTodayRequests(String providerId) async {
    final response = await _get('/providers/$providerId/requests/today/list');
    if (response != null && response['requests'] != null) {
      return List<Map<String, dynamic>>.from(response['requests']);
    }
    return [];
  }

  /// Create a new service request from a farmer to a provider.
  Future<Map<String, dynamic>?> createServiceRequest({
    required String farmerId,
    required String providerId,
    int? categoryId,
    String? message,
    double? farmerLatitude,
    double? farmerLongitude,
  }) async {
    return await _post('/requests', {
      'farmer_id': farmerId,
      'provider_id': providerId,
      'category_id': categoryId,
      'message': message,
      'farmer_latitude': farmerLatitude,
      'farmer_longitude': farmerLongitude,
    });
  }

  /// Update the status of a service request.
  Future<Map<String, dynamic>?> updateServiceRequestStatus({
    required String requestId,
    required String status,
  }) async {
    return await _put('/requests/$requestId/status', {
      'status': status,
    });
  }

  /// Get all requests sent by a farmer.
  Future<List<Map<String, dynamic>>> getFarmerRequests(String farmerId) async {
    final response = await _get('/farmers/$farmerId/requests');
    if (response != null && response['requests'] != null) {
      return List<Map<String, dynamic>>.from(response['requests']);
    }
    return [];
  }

  /// Submit a rating and review for a completed service request.
  Future<Map<String, dynamic>?> submitReview({
    required String requestId,
    required String farmerId,
    required String providerId,
    required int rating,
    String? reviewText,
  }) async {
    return await _post('/reviews', {
      'request_id': requestId,
      'farmer_id': farmerId,
      'provider_id': providerId,
      'rating': rating,
      'review_text': reviewText,
    });
  }

  /// Get all service categories.
  Future<List<Map<String, dynamic>>> getServiceCategories() async {
    final response = await _get('/categories');
    if (response != null && response['categories'] != null) {
      return List<Map<String, dynamic>>.from(response['categories']);
    }
    return [];
  }

  // ─── Chat Message endpoints ────────────────────────────────────────────────

  /// Get chat messages for a specific service request.
  Future<List<Map<String, dynamic>>> getChatMessages(String requestId) async {
    final response = await _get('/requests/$requestId/messages');
    if (response != null && response['messages'] != null) {
      return List<Map<String, dynamic>>.from(response['messages']);
    }
    return [];
  }

  /// Send a chat message for a service request.
  Future<Map<String, dynamic>?> sendChatMessage({
    required String requestId,
    required String senderId,
    required String messageText,
  }) async {
    return await _post('/requests/$requestId/messages', {
      'sender_id': senderId,
      'message_text': messageText,
    });
  }

  // ─── Payment endpoints ──────────────────────────────────────────────────────

  /// Process simulated payment checkout for a service request.
  Future<Map<String, dynamic>?> processPayment({
    required String requestId,
    required double amount,
  }) async {
    return await _post('/requests/$requestId/pay', {
      'amount': amount,
    });
  }

  // ─── Notifications endpoints ────────────────────────────────────────────────

  /// Get notifications feed for a user.
  Future<List<Map<String, dynamic>>> getUserNotifications(String userId) async {
    final response = await _get('/notifications/$userId');
    if (response != null && response['notifications'] != null) {
      return List<Map<String, dynamic>>.from(response['notifications']);
    }
    return [];
  }

  /// Mark all user notifications as read.
  Future<Map<String, dynamic>?> markNotificationsAsRead(String userId) async {
    return await _put('/notifications/$userId/read', {});
  }

  // ─── Equipment endpoints ────────────────────────────────────────────────────

  /// Get equipment list (optionally filtered by provider).
  Future<List<Map<String, dynamic>>> getEquipmentList({String? providerId}) async {
    final params = <String, String>{};
    if (providerId != null) {
      params['provider_id'] = providerId;
    }
    final response = await _get('/equipment', queryParams: params.isEmpty ? null : params);
    if (response != null && response['equipment'] != null) {
      return List<Map<String, dynamic>>.from(response['equipment']);
    }
    return [];
  }

  /// Add a new equipment listing.
  Future<Map<String, dynamic>?> addEquipment({
    required String providerId,
    required String name,
    required int categoryId,
    required double pricePerHour,
  }) async {
    return await _post('/equipment', {
      'provider_id': providerId,
      'name': name,
      'category_id': categoryId,
      'price_per_hour': pricePerHour,
    });
  }

  /// Delete an equipment listing.
  Future<Map<String, dynamic>?> deleteEquipment(String id) async {
    return await _delete('/equipment/$id');
  }
}
