import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;

/// Service for handling GPS location permissions, fetching coordinates,
/// and reverse geocoding.
class LocationService {
  LocationService();

  /// Check and request location permissions.
  /// Returns true if permissions are granted.
  Future<bool> checkAndRequestPermission() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Check if location services are enabled
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('Location services are disabled.');
      return false;
    }

    // Check permission status
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        debugPrint('Location permissions are denied.');
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      debugPrint('Location permissions are permanently denied.');
      return false;
    }

    return true;
  }

  /// Get the current GPS position.
  /// Returns null if permissions are not granted.
  Future<Position?> getCurrentPosition() async {
    final hasPermission = await checkAndRequestPermission();
    if (!hasPermission) return null;

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      );
      debugPrint('Current position: ${position.latitude}, ${position.longitude}');
      return position;
    } catch (e) {
      debugPrint('Error getting location: $e');
      return null;
    }
  }

  /// Reverse geocode coordinates to a human-readable address.
  /// Returns a formatted string like "Village Name, District".
  Future<String> getAddressFromCoordinates(double latitude, double longitude) async {
    if (kIsWeb) {
      try {
        final url = Uri.parse(
            'https://api.bigdatacloud.net/data/reverse-geocode-client?latitude=$latitude&longitude=$longitude&localityLanguage=en');
        final response = await http.get(url);
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final city = data['city'] as String?;
          final locality = data['locality'] as String?;
          final principalSubdivision = data['principalSubdivision'] as String?;

          final parts = <String>[
            if (locality != null && locality.isNotEmpty) locality,
            if (city != null && city.isNotEmpty) city,
            if (principalSubdivision != null && principalSubdivision.isNotEmpty) principalSubdivision,
          ];

          if (parts.isNotEmpty) {
            return parts.join(', ');
          }
        }
      } catch (e) {
        debugPrint('Web geocoding error: $e');
      }
      return 'Unknown Location';
    }

    try {
      final placemarks = await placemarkFromCoordinates(latitude, longitude);
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        // Build a meaningful location string
        final parts = <String>[
          if (place.subLocality != null && place.subLocality!.isNotEmpty)
            place.subLocality!,
          if (place.locality != null && place.locality!.isNotEmpty)
            place.locality!,
          if (place.administrativeArea != null && place.administrativeArea!.isNotEmpty)
            place.administrativeArea!,
        ];
        final address = parts.isNotEmpty ? parts.join(', ') : 'Unknown Location';
        debugPrint('Reverse geocoded address: $address');
        return address;
      }
    } catch (e) {
      debugPrint('Reverse geocoding error: $e');
    }
    return 'Unknown Location';
  }

  /// Convenience method: get current location as a formatted address string.
  Future<String> getCurrentLocationAddress() async {
    final position = await getCurrentPosition();
    if (position == null) return 'Location unavailable';
    return getAddressFromCoordinates(position.latitude, position.longitude);
  }
}
