import 'package:flutter/material.dart';
import 'dart:async';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../services/translation_service.dart';
import '../widgets/language_selector.dart';
import 'account_page.dart';

class FarmerHomePage extends StatefulWidget {
  const FarmerHomePage({super.key});

  @override
  State<FarmerHomePage> createState() => _FarmerHomePageState();
}

class _FarmerHomePageState extends State<FarmerHomePage>
    with TickerProviderStateMixin {
  final AuthService _authService = AuthService();
  final ApiService _apiService = ApiService();
  final LocationService _locationService = LocationService();

  String _userName = 'User';
  String _currentLocation = 'Fetching location...';
  double? _latitude;
  double? _longitude;

  GoogleMapController? _mapController;
  Set<Marker> _markers = {};
  List<Map<String, dynamic>> _nearbyProviders = [];
  List<Map<String, dynamic>> _filteredProviders = [];

  final TextEditingController _searchController = TextEditingController();
  bool _isLoadingMap = true;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  // Dark mode style for Google Maps to match the app's dark theme
  static const String _darkMapStyle = '''
[
  {"elementType":"geometry","stylers":[{"color":"#212121"}]},
  {"elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#757575"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#212121"}]},
  {"featureType":"administrative","elementType":"geometry","stylers":[{"color":"#757575"}]},
  {"featureType":"administrative.country","elementType":"labels.text.fill","stylers":[{"color":"#9e9e9e"}]},
  {"featureType":"administrative.land_parcel","stylers":[{"visibility":"off"}]},
  {"featureType":"administrative.locality","elementType":"labels.text.fill","stylers":[{"color":"#bdbdbd"}]},
  {"featureType":"poi","elementType":"labels.text.fill","stylers":[{"color":"#757575"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#181818"}]},
  {"featureType":"poi.park","elementType":"labels.text.fill","stylers":[{"color":"#616161"}]},
  {"featureType":"poi.park","elementType":"labels.text.stroke","stylers":[{"color":"#1b1b1b"}]},
  {"featureType":"road","elementType":"geometry.fill","stylers":[{"color":"#2c2c2c"}]},
  {"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#8a8a8a"}]},
  {"featureType":"road.arterial","elementType":"geometry","stylers":[{"color":"#373737"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#3c3c3c"}]},
  {"featureType":"road.highway.controlled_access","elementType":"geometry","stylers":[{"color":"#4e4e4e"}]},
  {"featureType":"road.local","elementType":"labels.text.fill","stylers":[{"color":"#616161"}]},
  {"featureType":"transit","elementType":"labels.text.fill","stylers":[{"color":"#757575"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#000000"}]},
  {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#3d3d3d"}]}
]
''';

  @override
  void initState() {
    super.initState();
    _currentLocation = tr('fetching_location');
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
    );
    _fadeController.forward();

    _loadUserData();
    _initLocation();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _searchController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    final name = await _authService.getUserName();
    if (name != null && mounted) {
      setState(() => _userName = name);
    }
  }

  Future<void> _initLocation() async {
    final position = await _locationService.getCurrentPosition();
    if (position != null) {
      _latitude = position.latitude;
      _longitude = position.longitude;

      // Get address
      final address = await _locationService.getAddressFromCoordinates(
          position.latitude, position.longitude);

      // Update location on server
      final userId = await _authService.getUserId();
      if (userId != null) {
        _apiService.updateLocation(
          userId: userId,
          latitude: position.latitude,
          longitude: position.longitude,
        );
      }

      if (mounted) {
        setState(() {
          _currentLocation = address;
          _isLoadingMap = false;
        });
      }

      // Load nearby providers
      await _loadNearbyProviders();
    } else {
      if (mounted) {
        setState(() {
          _currentLocation = 'Location unavailable';
          _isLoadingMap = false;
        });
      }
    }
  }

  Future<void> _loadNearbyProviders() async {
    if (_latitude == null || _longitude == null) return;

    try {
      final providers = await _apiService.getNearbyProviders(
        latitude: _latitude!,
        longitude: _longitude!,
        radiusKm: 25.0,
      );

      if (mounted) {
        setState(() {
          _nearbyProviders = providers;
          _filteredProviders = providers;
          _updateMarkers();
        });
      }
    } catch (e) {
      debugPrint('Error loading nearby providers: $e');
    }
  }

  void _updateMarkers() {
    final Set<Marker> newMarkers = {};

    // Add farmer's own location marker (blue)
    if (_latitude != null && _longitude != null) {
      newMarkers.add(
        Marker(
          markerId: const MarkerId('my_location'),
          position: LatLng(_latitude!, _longitude!),
          infoWindow: const InfoWindow(title: 'You are here'),
          icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueAzure),
        ),
      );
    }

    // Add service provider markers (green)
    for (int i = 0; i < _filteredProviders.length; i++) {
      final provider = _filteredProviders[i];
      final lat = provider['latitude'] as double?;
      final lng = provider['longitude'] as double?;
      if (lat != null && lng != null) {
        final name = provider['full_name'] ?? 'Provider';
        final serviceName = provider['service_name'] ?? '';
        newMarkers.add(
          Marker(
            markerId: MarkerId('provider_$i'),
            position: LatLng(lat, lng),
            infoWindow: InfoWindow(
              title: name,
              snippet: '$serviceName - Tap to request',
              onTap: () {
                _showRequestServiceDialog(provider);
              },
            ),
            onTap: () {
              _showRequestServiceDialog(provider);
            },
            icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueGreen),
          ),
        );
      }
    }

    _markers = newMarkers;
  }

  void _onSearchChanged(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredProviders = _nearbyProviders;
      } else {
        _filteredProviders = _nearbyProviders.where((p) {
          final name = (p['full_name'] ?? '').toString().toLowerCase();
          final service = (p['service_name'] ?? '').toString().toLowerCase();
          final categories =
              (p['categories'] as List?)?.join(', ').toLowerCase() ?? '';
          final q = query.toLowerCase();
          return name.contains(q) ||
              service.contains(q) ||
              categories.contains(q);
        }).toList();
      }
      _updateMarkers();
    });
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
  }

  void _showRequestServiceDialog(Map<String, dynamic> provider) async {
    final messageController = TextEditingController();
    bool isSubmitting = false;
    final selectedEquipmentNames = <String>{};

    List<Map<String, dynamic>> providerEquipment = [];
    bool isLoadingEquipment = true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> fetchProviderEquipment() async {
              try {
                final providerUserId = provider['user_id'] ?? provider['id'];
                final list = await _apiService.getEquipmentList(providerId: providerUserId);
                setModalState(() {
                  providerEquipment = list;
                  isLoadingEquipment = false;
                });
              } catch (e) {
                debugPrint('Error loading provider equipment: $e');
                setModalState(() => isLoadingEquipment = false);
              }
            }

            if (isLoadingEquipment) {
              fetchProviderEquipment();
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                decoration: const BoxDecoration(
                  color: Color(0xFF141414),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Pull indicator
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Title
                    Text(
                      provider['full_name'] ?? 'Provider',
                      style: GoogleFonts.inter(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),

                    // Service Name
                    Text(
                      provider['service_name'] ?? '',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF4AE54A),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(
                          Icons.star_rounded,
                          color: Color(0xFFFFC107),
                          size: 18,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          provider['review_count'] != null && provider['review_count'] > 0
                              ? '${(provider['avg_rating'] is num ? provider['avg_rating'] as num : double.tryParse(provider['avg_rating'].toString()) ?? 0.0).toStringAsFixed(1)} (${provider['review_count']} ${tr('reviews')})'
                              : tr('no_reviews'),
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: Colors.white70,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Categories
                    if (provider['categories'] != null) ...[
                      Text(
                        '${tr('categories')}:',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Colors.white38,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        (provider['categories'] is List)
                            ? (provider['categories'] as List).map((c) => tr(c.toString())).join(', ')
                            : tr(provider['categories'].toString()),
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: Colors.white70,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],

                    // Phone Number
                    if (provider['phone_number'] != null) ...[
                      Text(
                        '${tr('phone_number')}:',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Colors.white38,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '+${provider['phone_number']}',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: Colors.white70,
                          fontWeight: FontWeight.w400,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],

                    // Available Equipment Listing
                    Text(
                      'Available Equipment & Rates:',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.white38,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (isLoadingEquipment)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Center(
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white38)),
                          ),
                        ),
                      )
                    else if (providerEquipment.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'No equipment registered by provider yet.',
                          style: GoogleFonts.inter(fontSize: 13, color: Colors.white38, fontStyle: FontStyle.italic),
                        ),
                      )
                    else
                      Container(
                        margin: const EdgeInsets.only(bottom: 18),
                        height: 76,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          itemCount: providerEquipment.length,
                          itemBuilder: (context, index) {
                            final eq = providerEquipment[index];
                            final eqName = eq['name'] ?? '';
                            final eqPrice = eq['price_per_hour'] != null
                                ? double.tryParse(eq['price_per_hour'].toString()) ?? 0.0
                                : 0.0;
                            final catName = eq['category_name'] ?? '';
                            final isSelected = selectedEquipmentNames.contains(eqName);

                            return GestureDetector(
                              onTap: () {
                                setModalState(() {
                                  final term = trWithArgs('want_to_rent', [eqName, eqPrice.toStringAsFixed(0)]) + '\n';
                                  if (isSelected) {
                                    selectedEquipmentNames.remove(eqName);
                                    messageController.text = messageController.text.replaceAll(term, '').trim();
                                  } else {
                                    selectedEquipmentNames.add(eqName);
                                    messageController.text = (messageController.text.trim() + '\n' + term).trim();
                                  }
                                });
                              },
                              child: Container(
                                margin: const EdgeInsets.only(right: 12),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                width: 160,
                                decoration: BoxDecoration(
                                  color: isSelected ? const Color(0xFF1B3B1B) : const Color(0xFF1E1E1E),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: isSelected ? const Color(0xFF4AE54A) : Colors.white.withOpacity(0.05),
                                    width: isSelected ? 1.5 : 1.0,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      eqName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                                    ),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          catName,
                                          style: GoogleFonts.inter(fontSize: 10, color: Colors.white38),
                                        ),
                                        Text(
                                          '₹${eqPrice.toStringAsFixed(0)}/hr',
                                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF4AE54A)),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 10),

                    // Message field
                    Text(
                      '${tr('optional_message')}:',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.white38,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.08),
                          width: 1,
                        ),
                      ),
                      child: TextField(
                        controller: messageController,
                        maxLines: 3,
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          hintText: tr('message_placeholder'),
                          hintStyle: GoogleFonts.inter(
                            color: Colors.white24,
                            fontSize: 14,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.all(12),
                        ),
                        cursorColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Submit button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                        onPressed: isSubmitting
                            ? null
                            : () async {
                                setModalState(() => isSubmitting = true);
                                try {
                                  final farmerId = await _authService.getUserId();
                                  final providerUserId = provider['user_id'] ?? provider['id'];

                                  if (farmerId == null || providerUserId == null) {
                                    throw Exception('Unable to fetch user IDs.');
                                  }

                                  // Send service request
                                  final reqResult = await _apiService.createServiceRequest(
                                    farmerId: farmerId,
                                    providerId: providerUserId,
                                    message: messageController.text.trim().isNotEmpty
                                        ? messageController.text.trim()
                                        : null,
                                    farmerLatitude: _latitude,
                                    farmerLongitude: _longitude,
                                  );

                                  if (reqResult == null) {
                                    throw Exception('Failed to send request.');
                                  }

                                  if (context.mounted) {
                                    Navigator.pop(context);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          tr('request_success'),
                                          style: GoogleFonts.inter(
                                            color: Colors.black,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        backgroundColor: Colors.white,
                                        behavior: SnackBarBehavior.floating,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          '${tr('request_failed')}: ${e.toString().replaceAll('Exception:', '').trim()}',
                                          style: GoogleFonts.inter(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        backgroundColor: const Color(0xFFFF4444),
                                        behavior: SnackBarBehavior.floating,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                      ),
                                    );
                                  }
                                } finally {
                                  setModalState(() => isSubmitting = false);
                                }
                              },
                        child: isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                                ),
                              )
                            : Text(
                                tr('request_service'),
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showRatingDialog(BuildContext context, Map<String, dynamic> request, VoidCallback onSubmitted) {
    int selectedRating = 5;
    final commentController = TextEditingController();
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                decoration: const BoxDecoration(
                  color: Color(0xFF141414),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Pull indicator
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Header
                    Text(
                      tr('rate_service'),
                      style: GoogleFonts.inter(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      request['provider_name'] ?? 'Provider',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: const Color(0xFF4AE54A),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Rating selection
                    Text(
                      tr('rating_label'),
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.white38,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: List.generate(5, (index) {
                        final starValue = index + 1;
                        return GestureDetector(
                          onTap: () {
                            setModalState(() {
                              selectedRating = starValue;
                            });
                          },
                          child: Padding(
                            padding: const EdgeInsets.only(right: 12.0),
                            child: Icon(
                              Icons.star_rounded,
                              color: starValue <= selectedRating
                                  ? const Color(0xFFFFC107)
                                  : Colors.white24,
                              size: 40,
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 24),

                    // Comment field
                    Text(
                      tr('comment_label'),
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.white38,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.08),
                          width: 1,
                        ),
                      ),
                      child: TextField(
                        controller: commentController,
                        maxLines: 3,
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          hintText: 'e.g. Friendly service, very punctual!',
                          hintStyle: GoogleFonts.inter(
                            color: Colors.white24,
                            fontSize: 14,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.all(12),
                        ),
                        cursorColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Submit button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                        onPressed: isSubmitting
                            ? null
                            : () async {
                                setModalState(() => isSubmitting = true);
                                try {
                                  final farmerId = request['farmer_id'];
                                  final providerId = request['provider_id'];
                                  final requestId = request['id'];

                                  if (farmerId == null || providerId == null || requestId == null) {
                                    throw Exception('Missing details for review.');
                                  }

                                  final result = await _apiService.submitReview(
                                    requestId: requestId,
                                    farmerId: farmerId,
                                    providerId: providerId,
                                    rating: selectedRating,
                                    reviewText: commentController.text.trim().isNotEmpty
                                        ? commentController.text.trim()
                                        : null,
                                  );

                                  if (result == null) {
                                    throw Exception('Failed to submit review.');
                                  }

                                  if (context.mounted) {
                                    Navigator.pop(context); // Close bottom sheet
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          tr('review_submitted'),
                                          style: GoogleFonts.inter(
                                            color: Colors.black,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        backgroundColor: Colors.white,
                                        behavior: SnackBarBehavior.floating,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                      ),
                                    );
                                    // Refresh markers and history list
                                    onSubmitted();
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Failed: ${e.toString().replaceAll('Exception:', '').trim()}',
                                          style: GoogleFonts.inter(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        backgroundColor: const Color(0xFFFF4444),
                                        behavior: SnackBarBehavior.floating,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                      ),
                                    );
                                  }
                                } finally {
                                  setModalState(() => isSubmitting = false);
                                }
                              },
                        child: isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                                ),
                              )
                            : Text(
                                tr('submit_review'),
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showChatBottomSheet(String requestId, String recipientName, String senderId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final textController = TextEditingController();
        List<Map<String, dynamic>> messages = [];
        bool isLoadingChat = true;
        Timer? pollTimer;

        return StatefulBuilder(
          builder: (context, setChatState) {
            Future<void> fetchMessages() async {
              try {
                final list = await _apiService.getChatMessages(requestId);
                if (context.mounted) {
                  setChatState(() {
                    messages = list;
                    isLoadingChat = false;
                  });
                }
              } catch (e) {
                debugPrint('Error fetching chat messages: $e');
                if (context.mounted) {
                  setChatState(() => isLoadingChat = false);
                }
              }
            }

            // Setup polling every 3 seconds
            if (isLoadingChat) {
              fetchMessages();
              pollTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
                fetchMessages();
              });
            }

            return WillPopScope(
              onWillPop: () async {
                pollTimer?.cancel();
                return true;
              },
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                ),
                child: Container(
                  height: MediaQuery.of(context).size.height * 0.65,
                  decoration: const BoxDecoration(
                    color: Color(0xFF141414),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                    ),
                  ),
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      // Pull indicator & Header
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Chat with $recipientName',
                            style: GoogleFonts.inter(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white54),
                            onPressed: () {
                              pollTimer?.cancel();
                              Navigator.pop(context);
                            },
                          ),
                        ],
                      ),
                      const Divider(color: Colors.white10),

                      // Messages List
                      Expanded(
                        child: isLoadingChat
                            ? const Center(
                                child: CircularProgressIndicator(
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white38),
                                ),
                              )
                            : messages.isEmpty
                                ? Center(
                                    child: Text(
                                      'No messages yet. Send a message to start.',
                                      style: GoogleFonts.inter(color: Colors.white24, fontSize: 13),
                                    ),
                                  )
                                : ListView.builder(
                                    reverse: false,
                                    physics: const BouncingScrollPhysics(),
                                    itemCount: messages.length,
                                    itemBuilder: (context, index) {
                                      final msg = messages[index];
                                      final isMe = msg['sender_id'] == senderId;
                                      final text = msg['message_text'] ?? '';
                                      final senderName = msg['sender_name'] ?? '';

                                      return Align(
                                        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                                        child: Container(
                                          margin: const EdgeInsets.only(bottom: 12),
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                          decoration: BoxDecoration(
                                            color: isMe ? const Color(0xFF4AE54A).withOpacity(0.12) : const Color(0xFF1E1E1E),
                                            borderRadius: BorderRadius.circular(16).copyWith(
                                              bottomRight: isMe ? const Radius.circular(0) : const Radius.circular(16),
                                              bottomLeft: isMe ? const Radius.circular(16) : const Radius.circular(0),
                                            ),
                                            border: Border.all(
                                              color: isMe ? const Color(0xFF4AE54A).withOpacity(0.3) : Colors.white.withOpacity(0.04),
                                              width: 1,
                                            ),
                                          ),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              if (!isMe)
                                                Text(
                                                  senderName,
                                                  style: GoogleFonts.inter(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                    color: const Color(0xFF4AE54A),
                                                  ),
                                                ),
                                              const SizedBox(height: 2),
                                              Text(
                                                text,
                                                style: GoogleFonts.inter(
                                                  fontSize: 14,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                      ),

                      // Input Bar
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E1E1E),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(color: Colors.white.withOpacity(0.08)),
                              ),
                              child: TextField(
                                controller: textController,
                                style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                                decoration: const InputDecoration(
                                  hintText: 'Type a message...',
                                  hintStyle: TextStyle(color: Colors.white24),
                                  border: InputBorder.none,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () async {
                              final text = textController.text.trim();
                              if (text.isEmpty) return;
                              textController.clear();
                              try {
                                await _apiService.sendChatMessage(
                                  requestId: requestId,
                                  senderId: senderId,
                                  messageText: text,
                                );
                                fetchMessages();
                              } catch (e) {
                                debugPrint('Error sending message: $e');
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.send_rounded, color: Colors.black, size: 20),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showCallSimulationDialog(String providerName, String phoneNumber) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF141414),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Colors.white.withOpacity(0.08)),
          ),
          title: Row(
            children: [
              const Icon(Icons.call, color: Color(0xFF4AE54A)),
              const SizedBox(width: 8),
              Text(
                'IVR calling...',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: Colors.white),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person, size: 60, color: Colors.white54),
              ),
              const SizedBox(height: 16),
              Text(
                providerName,
                style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 4),
              Text(
                '+$phoneNumber',
                style: GoogleFonts.inter(fontSize: 14, color: Colors.white38),
              ),
              const SizedBox(height: 24),
              Text(
                'Connecting your call securely via agricultural voice gateway...',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 12, color: Colors.white24, fontStyle: FontStyle.italic),
              ),
            ],
          ),
          actions: [
            Center(
              child: SizedBox(
                width: 140,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF4444),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.call_end),
                      const SizedBox(width: 8),
                      Text('Hang Up', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showPaymentCheckoutDialog(Map<String, dynamic> request, double amount, VoidCallback onCompleted) {
    bool isPaying = false;
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF141414),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: Colors.white.withOpacity(0.08)),
              ),
              title: Text(
                'Transparent Payment Quote',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: Colors.white),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Service Request Summary:',
                    style: GoogleFonts.inter(fontSize: 12, color: Colors.white38, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Provider: ${request['provider_name'] ?? 'Provider'}',
                    style: GoogleFonts.inter(fontSize: 14, color: Colors.white70),
                  ),
                  Text(
                    'Service: ${request['service_name'] ?? 'Agricultural Service'}',
                    style: GoogleFonts.inter(fontSize: 14, color: Colors.white70),
                  ),
                  const SizedBox(height: 16),
                  const Divider(color: Colors.white10),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total Price Quote:',
                        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white70),
                      ),
                      Text(
                        '₹${amount.toStringAsFixed(0)}',
                        style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF4AE54A)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Calculated based on equipment hourly rates.',
                    style: GoogleFonts.inter(fontSize: 11, color: Colors.white24),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Cancel', style: GoogleFonts.inter(color: Colors.white54)),
                ),
                ElevatedButton(
                  onPressed: isPaying
                      ? null
                      : () async {
                          setDialogState(() => isPaying = true);
                          try {
                            final res = await _apiService.processPayment(
                              requestId: request['id'],
                              amount: amount,
                            );
                            if (res != null && context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Payment successful! Reference: ${res['payment']?['transaction_id'] ?? ''}',
                                    style: GoogleFonts.inter(color: Colors.black, fontWeight: FontWeight.w500),
                                  ),
                                  backgroundColor: Colors.white,
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              );
                              onCompleted();
                            }
                          } catch (e) {
                            debugPrint('Payment error: $e');
                            setDialogState(() => isPaying = false);
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4AE54A),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: isPaying
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.black)))
                      : Text('Pay Now', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showNotificationsSheet(String userId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        List<Map<String, dynamic>> notifications = [];
        bool isLoadingNotif = true;

        return StatefulBuilder(
          builder: (context, setNotifState) {
            Future<void> fetchNotifs() async {
              try {
                final list = await _apiService.getUserNotifications(userId);
                if (context.mounted) {
                  setNotifState(() {
                    notifications = list;
                    isLoadingNotif = false;
                  });
                }
              } catch (e) {
                debugPrint('Error fetching notifications: $e');
                if (context.mounted) {
                  setNotifState(() => isLoadingNotif = false);
                }
              }
            }

            if (isLoadingNotif) {
              fetchNotifs();
              _apiService.markNotificationsAsRead(userId);
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                height: MediaQuery.of(context).size.height * 0.7,
                decoration: const BoxDecoration(
                  color: Color(0xFF141414),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Notifications Center',
                      style: GoogleFonts.inter(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: isLoadingNotif
                          ? const Center(
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white38),
                              ),
                            )
                          : notifications.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.notifications_none_rounded, color: Colors.white24, size: 48),
                                      const SizedBox(height: 12),
                                      Text(
                                        'No notifications yet.',
                                        style: GoogleFonts.inter(color: Colors.white38, fontSize: 14),
                                      ),
                                    ],
                                  ),
                                )
                              : ListView.builder(
                                  physics: const BouncingScrollPhysics(),
                                  itemCount: notifications.length,
                                  itemBuilder: (context, index) {
                                    final n = notifications[index];
                                    final title = n['title'] ?? 'Notification';
                                    final msg = n['message'] ?? '';
                                    final isRead = n['is_read'] == true;

                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 12),
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF1E1E1E),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(color: Colors.white.withOpacity(0.04)),
                                      ),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            margin: const EdgeInsets.only(top: 3),
                                            width: 8,
                                            height: 8,
                                            decoration: BoxDecoration(
                                              color: isRead ? Colors.transparent : const Color(0xFF4AE54A),
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  title,
                                                  style: GoogleFonts.inter(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  msg,
                                                  style: GoogleFonts.inter(
                                                    fontSize: 13,
                                                    color: Colors.white54,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showOfflineChannelsOverlay() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF141414),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  const Icon(Icons.cell_tower_rounded, color: Color(0xFF4AE54A), size: 28),
                  const SizedBox(width: 12),
                  Text(
                    'Offline Access Channels',
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Farmers without active internet can request, check, or list agricultural services using these offline templates:',
                style: GoogleFonts.inter(fontSize: 13, color: Colors.white54, height: 1.4),
              ),
              const SizedBox(height: 20),
              
              _buildChannelGuide(
                title: 'IVR Voice Portal (Toll-Free)',
                details: 'Call 1800-3000-NEON (1800-3000-6366)\nFollow voice instructions to select equipment and book automatically in local languages.',
                icon: Icons.settings_phone_rounded,
              ),
              const SizedBox(height: 16),
              
              _buildChannelGuide(
                title: 'WhatsApp Automated Bot',
                details: 'Send "BOOK" to +91 90001 90002.\nOur automated assistant will guide you step-by-step through agricultural service booking.',
                icon: Icons.chat_rounded,
              ),
              const SizedBox(height: 16),
              
              _buildChannelGuide(
                title: 'SMS Booking Templates',
                details: 'SMS "BOOK <Category_ID> <Village_Name>" to 56767.\nExample: BOOK 1 Vasantpur\nCategory IDs: 1-Tractor, 2-Fertilizer, 4-Machinery Rental.',
                icon: Icons.sms_rounded,
              ),
              const SizedBox(height: 24),
              
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text('Close', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildChannelGuide({required String title, required String details, required IconData icon}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF4AE54A), size: 24),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  details,
                  style: GoogleFonts.inter(fontSize: 12, color: Colors.white54, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showMyRequestsBottomSheet() async {
    List<Map<String, dynamic>> requestsList = [];
    bool isLoading = true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            // Fetch requests inside the bottom sheet on load
            if (isLoading) {
              _authService.getUserId().then((userId) {
                if (userId != null) {
                  _apiService.getFarmerRequests(userId).then((requests) {
                    if (context.mounted) {
                      setModalState(() {
                        requestsList = requests;
                        isLoading = false;
                      });
                    }
                  }).catchError((_) {
                    if (context.mounted) {
                      setModalState(() => isLoading = false);
                    }
                  });
                } else {
                  if (context.mounted) {
                    setModalState(() => isLoading = false);
                  }
                }
              });
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.75,
                ),
                decoration: const BoxDecoration(
                  color: Color(0xFF141414),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Pull indicator
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          tr('my_requests'),
                          style: GoogleFonts.inter(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        if (!isLoading && requestsList.isNotEmpty)
                          Text(
                            '${requestsList.length} items',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: Colors.white38,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // List
                    Flexible(
                      child: isLoading
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.symmetric(vertical: 40),
                                child: SizedBox(
                                  width: 28,
                                  height: 28,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white38),
                                  ),
                                ),
                              ),
                            )
                          : requestsList.isEmpty
                              ? Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 40),
                                  child: Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Icon(
                                          Icons.inbox_outlined,
                                          color: Colors.white24,
                                          size: 40,
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          tr('no_requests'),
                                          style: GoogleFonts.inter(
                                            color: Colors.white30,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  shrinkWrap: true,
                                  physics: const BouncingScrollPhysics(),
                                  itemCount: requestsList.length,
                                  itemBuilder: (context, index) {
                                    final request = requestsList[index];
                                    final providerName = request['provider_name'] ?? 'Provider';
                                    final serviceName = request['service_name'] ?? '';
                                    final status = request['status'] ?? 'pending';
                                    final message = request['message'] ?? '';
                                    final reviewRating = request['review_rating'];
                                    final reviewText = request['review_text'] ?? '';

                                    // Status color mapping
                                    Color statusColor;
                                    Color statusBg;
                                    switch (status.toLowerCase()) {
                                      case 'pending':
                                        statusColor = const Color(0xFFFF9800);
                                        statusBg = const Color(0xFFFF9800).withOpacity(0.12);
                                        break;
                                      case 'accepted':
                                        statusColor = const Color(0xFF4AE54A);
                                        statusBg = const Color(0xFF4AE54A).withOpacity(0.12);
                                        break;
                                      case 'rejected':
                                        statusColor = const Color(0xFFFF4444);
                                        statusBg = const Color(0xFFFF4444).withOpacity(0.12);
                                        break;
                                      case 'completed':
                                        statusColor = const Color(0xFF2196F3);
                                        statusBg = const Color(0xFF2196F3).withOpacity(0.12);
                                        break;
                                      default:
                                        statusColor = Colors.white54;
                                        statusBg = Colors.white10;
                                    }

                                    String statusLabel;
                                    switch (status.toLowerCase()) {
                                      case 'pending':
                                        statusLabel = tr('status_pending');
                                        break;
                                      case 'accepted':
                                        statusLabel = tr('status_accepted');
                                        break;
                                      case 'rejected':
                                        statusLabel = tr('status_rejected');
                                        break;
                                      case 'completed':
                                        statusLabel = tr('status_completed');
                                        break;
                                      default:
                                        statusLabel = status.toUpperCase();
                                    }

                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 16),
                                      padding: const EdgeInsets.all(18),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF1E1E1E),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: Colors.white.withOpacity(0.06),
                                          width: 1,
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  providerName,
                                                  style: GoogleFonts.inter(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.white,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: statusBg,
                                                  borderRadius: BorderRadius.circular(20),
                                                  border: Border.all(color: statusColor.withOpacity(0.3), width: 1),
                                                ),
                                                child: Text(
                                                  statusLabel,
                                                  style: GoogleFonts.inter(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w600,
                                                    color: statusColor,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          if (serviceName.isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              serviceName,
                                              style: GoogleFonts.inter(
                                                fontSize: 13,
                                                color: const Color(0xFF4AE54A),
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                          if (message.isNotEmpty) ...[
                                            const SizedBox(height: 12),
                                            Text(
                                              message,
                                              style: GoogleFonts.inter(
                                                fontSize: 13,
                                                color: Colors.white54,
                                                fontStyle: FontStyle.italic,
                                              ),
                                            ),
                                          ],
                                          // Chat, Call & Payments for Accepted/Completed Requests
                                          if (status.toLowerCase() == 'accepted' || status.toLowerCase() == 'completed') ...[
                                            const SizedBox(height: 14),
                                            const Divider(color: Colors.white10),
                                            const SizedBox(height: 8),
                                            
                                            // Communication Buttons
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: OutlinedButton.icon(
                                                    onPressed: () => _showCallSimulationDialog(
                                                      providerName,
                                                      request['provider_phone'] ?? '919000000000',
                                                    ),
                                                    icon: const Icon(Icons.phone_rounded, size: 16),
                                                    label: Text(
                                                      'Call Provider',
                                                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
                                                    ),
                                                    style: OutlinedButton.styleFrom(
                                                      foregroundColor: Colors.white,
                                                      side: BorderSide(color: Colors.white.withOpacity(0.12)),
                                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: OutlinedButton.icon(
                                                    onPressed: () async {
                                                      final myId = await _authService.getUserId();
                                                      if (myId != null) {
                                                        _showChatBottomSheet(
                                                          request['id'],
                                                          providerName,
                                                          myId,
                                                        );
                                                      }
                                                    },
                                                    icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16),
                                                    label: Text(
                                                      'Chat',
                                                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
                                                    ),
                                                    style: OutlinedButton.styleFrom(
                                                      foregroundColor: Colors.white,
                                                      side: BorderSide(color: Colors.white.withOpacity(0.12)),
                                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 12),

                                            // Pricing Quote & Payment Details
                                            Container(
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                color: Colors.white.withOpacity(0.02),
                                                borderRadius: BorderRadius.circular(12),
                                                border: Border.all(color: Colors.white.withOpacity(0.04)),
                                              ),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                    children: [
                                                      Text(
                                                        'Transparent Pricing Quote',
                                                        style: GoogleFonts.inter(fontSize: 11, color: Colors.white38, fontWeight: FontWeight.w600),
                                                      ),
                                                      Text(
                                                        '₹370/hr x 4 hrs',
                                                        style: GoogleFonts.inter(fontSize: 11, color: Colors.white38),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 8),
                                                  Row(
                                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                    children: [
                                                      Text(
                                                        'Amount due:',
                                                        style: GoogleFonts.inter(fontSize: 13, color: Colors.white70),
                                                      ),
                                                      Text(
                                                        '₹${(request['payment_amount'] != null ? double.tryParse(request['payment_amount'].toString()) ?? 1480.0 : 1480.0).toStringAsFixed(0)}',
                                                        style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF4AE54A)),
                                                      ),
                                                    ],
                                                  ),
                                                  if (request['payment_status'] == 'paid') ...[
                                                    const SizedBox(height: 10),
                                                    Row(
                                                      children: [
                                                        const Icon(Icons.check_circle_rounded, color: Color(0xFF4AE54A), size: 16),
                                                        const SizedBox(width: 6),
                                                        Text(
                                                          'PAID (Txn: ${request['transaction_id'] ?? ''})',
                                                          style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF4AE54A), fontWeight: FontWeight.w700),
                                                        ),
                                                      ],
                                                    ),
                                                  ] else ...[
                                                    const SizedBox(height: 10),
                                                    SizedBox(
                                                      width: double.infinity,
                                                      child: ElevatedButton(
                                                        onPressed: () {
                                                          _showPaymentCheckoutDialog(
                                                            request,
                                                            request['payment_amount'] != null ? double.tryParse(request['payment_amount'].toString()) ?? 1480.0 : 1480.0,
                                                            () {
                                                              setModalState(() {
                                                                isLoading = true;
                                                              });
                                                            },
                                                          );
                                                        },
                                                        style: ElevatedButton.styleFrom(
                                                          backgroundColor: const Color(0xFF4AE54A),
                                                          foregroundColor: Colors.black,
                                                          elevation: 0,
                                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                                          padding: const EdgeInsets.symmetric(vertical: 10),
                                                        ),
                                                        child: Text(
                                                          'Proceed to Payment Checkout',
                                                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                          ],
                                          if (status.toLowerCase() == 'completed' && reviewRating == null) ...[
                                            const SizedBox(height: 12),
                                            SizedBox(
                                              width: double.infinity,
                                              child: ElevatedButton(
                                                onPressed: () {
                                                  _showRatingDialog(context, request, () {
                                                    setModalState(() {
                                                      isLoading = true;
                                                    });
                                                  });
                                                },
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: Colors.white,
                                                  foregroundColor: Colors.black,
                                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                                  elevation: 0,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius: BorderRadius.circular(10),
                                                  ),
                                                ),
                                                child: Text(
                                                  tr('rate_service'),
                                                  style: GoogleFonts.inter(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                          if (reviewRating != null) ...[
                                            const SizedBox(height: 12),
                                            Container(
                                              width: double.infinity,
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF141414),
                                                borderRadius: BorderRadius.circular(10),
                                                border: Border.all(
                                                  color: Colors.white.withOpacity(0.04),
                                                  width: 1,
                                                ),
                                              ),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: List.generate(5, (index) {
                                                      return Icon(
                                                        Icons.star_rounded,
                                                        color: index < (reviewRating as num).toInt()
                                                            ? const Color(0xFFFFC107)
                                                            : Colors.white12,
                                                        size: 16,
                                                      );
                                                    }),
                                                  ),
                                                  if (reviewText.toString().isNotEmpty) ...[
                                                    const SizedBox(height: 6),
                                                    Text(
                                                      reviewText.toString(),
                                                      style: GoogleFonts.inter(
                                                        fontSize: 12,
                                                        color: Colors.white70,
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    );
                                  },
                                ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 28),

                // Greeting Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        '${tr('hello')} $_userName 👋',
                        style: GoogleFonts.inter(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.cell_tower_rounded, color: Colors.white70),
                      onPressed: _showOfflineChannelsOverlay,
                      tooltip: 'Offline channels info',
                      constraints: const BoxConstraints(),
                      padding: EdgeInsets.zero,
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      icon: const Icon(Icons.notifications_none_rounded, color: Colors.white70),
                      onPressed: () async {
                        final userId = await _authService.getUserId();
                        if (userId != null) {
                          _showNotificationsSheet(userId);
                        }
                      },
                      constraints: const BoxConstraints(),
                      padding: EdgeInsets.zero,
                    ),
                    const SizedBox(width: 12),
                    const LanguageSelector(),
                  ],
                ),

                const SizedBox(height: 6),

                // Current location
                Row(
                  children: [
                    const Icon(
                      Icons.location_on,
                      color: Color(0xFF4AE54A),
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        _currentLocation,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: Colors.white38,
                          fontWeight: FontWeight.w400,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Search box
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.08),
                      width: 1,
                    ),
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                    ),
                    decoration: InputDecoration(
                      hintText: tr('search_services'),
                      hintStyle: GoogleFonts.inter(
                        color: Colors.white24,
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                      ),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: Colors.white30,
                        size: 20,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                    cursorColor: Colors.white,
                  ),
                ),

                const SizedBox(height: 24),

                // Map label
                Text(
                  tr('nearby_map'),
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white70,
                  ),
                ),

                const SizedBox(height: 12),

                // Google Map
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A1A),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.08),
                          width: 1,
                        ),
                      ),
                      child: _isLoadingMap
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const SizedBox(
                                    width: 28,
                                    height: 28,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor:
                                          AlwaysStoppedAnimation<Color>(
                                              Colors.white38),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Text(
                                    tr('loading_map'),
                                    style: GoogleFonts.inter(
                                      color: Colors.white30,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : (_latitude != null && _longitude != null)
                              ? GoogleMap(
                                  onMapCreated: _onMapCreated,
                                  initialCameraPosition: CameraPosition(
                                    target: LatLng(_latitude!, _longitude!),
                                    zoom: 13,
                                  ),
                                  markers: _markers,
                                  style: _darkMapStyle,
                                  myLocationEnabled: false,
                                  myLocationButtonEnabled: false,
                                  zoomControlsEnabled: false,
                                  mapToolbarEnabled: false,
                                  compassEnabled: false,
                                )
                              : Center(
                                  child: Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      const Icon(
                                        Icons.location_off_rounded,
                                        color: Colors.white24,
                                        size: 40,
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        tr('enable_location_map'),
                                        style: GoogleFonts.inter(
                                          color: Colors.white30,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                    ),
                  ),
                ),

                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),

      // Dual floating buttons at bottom
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(left: 32.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // My Requests history button — bottom left
            FloatingActionButton(
              heroTag: 'my_requests_btn',
              onPressed: () {
                _showMyRequestsBottomSheet();
              },
              backgroundColor: const Color(0xFF1A1A1A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: Colors.white.withOpacity(0.1),
                  width: 1,
                ),
              ),
              child: const Icon(
                Icons.history_rounded,
                color: Colors.white70,
                size: 28,
              ),
            ),

            // Account floating button — bottom right
            FloatingActionButton(
              heroTag: 'account_profile_btn',
              onPressed: () {
                Navigator.push(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (_, animation, __) => const AccountPage(),
                    transitionsBuilder: (_, animation, __, child) {
                      return SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 1),
                          end: Offset.zero,
                        ).animate(CurvedAnimation(
                            parent: animation, curve: Curves.easeOutCubic)),
                        child: child,
                      );
                    },
                    transitionDuration: const Duration(milliseconds: 400),
                  ),
                );
              },
              backgroundColor: const Color(0xFF1A1A1A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: Colors.white.withOpacity(0.1),
                  width: 1,
                ),
              ),
              child: const Icon(
                Icons.account_circle_outlined,
                color: Colors.white70,
                size: 28,
              ),
            ),
          ],
        ),
      ),
    );
  }

}
