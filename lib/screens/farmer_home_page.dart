import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
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
  final Set<Marker> _markers = {};
  List<Map<String, dynamic>> _nearbyProviders = [];
  List<Map<String, dynamic>> _filteredProviders = [];

  final TextEditingController _searchController = TextEditingController();
  bool _isLoadingMap = true;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
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
    _markers.clear();

    // Add farmer's own location marker
    if (_latitude != null && _longitude != null) {
      _markers.add(
        Marker(
          markerId: const MarkerId('my_location'),
          position: LatLng(_latitude!, _longitude!),
          infoWindow: const InfoWindow(title: 'You are here'),
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        ),
      );
    }

    // Add service provider markers
    for (final provider in _filteredProviders) {
      final lat = provider['latitude'] as double?;
      final lng = provider['longitude'] as double?;
      if (lat != null && lng != null) {
        final name = provider['full_name'] ?? 'Provider';
        final serviceName = provider['service_name'] ?? '';
        _markers.add(
          Marker(
            markerId: MarkerId(provider['user_id'] ?? name),
            position: LatLng(lat, lng),
            infoWindow: InfoWindow(
              title: name,
              snippet: serviceName,
            ),
            icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueGreen),
          ),
        );
      }
    }
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

                // Greeting
                Text(
                  'Hello $_userName 👋',
                  style: GoogleFonts.inter(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
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
                      hintText: 'Search Services',
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
                  'Nearby Services Map:',
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
                                    'Loading map...',
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
                                  initialCameraPosition: CameraPosition(
                                    target: LatLng(_latitude!, _longitude!),
                                    zoom: 13,
                                  ),
                                  markers: _markers,
                                  myLocationEnabled: true,
                                  myLocationButtonEnabled: false,
                                  zoomControlsEnabled: false,
                                  mapToolbarEnabled: false,
                                  onMapCreated: (controller) {
                                    _mapController = controller;
                                    // Apply dark map style
                                    controller.setMapStyle(_darkMapStyle);
                                  },
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
                                        'Enable location to view map',
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

      // Account floating button — bottom right
      floatingActionButton: FloatingActionButton(
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
    );
  }

  // Dark theme map style
  static const String _darkMapStyle = '''
[
  {"elementType": "geometry", "stylers": [{"color": "#212121"}]},
  {"elementType": "labels.icon", "stylers": [{"visibility": "off"}]},
  {"elementType": "labels.text.fill", "stylers": [{"color": "#757575"}]},
  {"elementType": "labels.text.stroke", "stylers": [{"color": "#212121"}]},
  {"featureType": "administrative", "elementType": "geometry", "stylers": [{"color": "#757575"}]},
  {"featureType": "administrative.country", "elementType": "labels.text.fill", "stylers": [{"color": "#9e9e9e"}]},
  {"featureType": "administrative.land_parcel", "stylers": [{"visibility": "off"}]},
  {"featureType": "administrative.locality", "elementType": "labels.text.fill", "stylers": [{"color": "#bdbdbd"}]},
  {"featureType": "poi", "elementType": "labels.text.fill", "stylers": [{"color": "#757575"}]},
  {"featureType": "poi.park", "elementType": "geometry", "stylers": [{"color": "#181818"}]},
  {"featureType": "poi.park", "elementType": "labels.text.fill", "stylers": [{"color": "#616161"}]},
  {"featureType": "poi.park", "elementType": "labels.text.stroke", "stylers": [{"color": "#1b1b1b"}]},
  {"featureType": "road", "elementType": "geometry.fill", "stylers": [{"color": "#2c2c2c"}]},
  {"featureType": "road", "elementType": "labels.text.fill", "stylers": [{"color": "#8a8a8a"}]},
  {"featureType": "road.arterial", "elementType": "geometry", "stylers": [{"color": "#373737"}]},
  {"featureType": "road.highway", "elementType": "geometry", "stylers": [{"color": "#3c3c3c"}]},
  {"featureType": "road.highway.controlled_access", "elementType": "geometry", "stylers": [{"color": "#4e4e4e"}]},
  {"featureType": "road.local", "elementType": "labels.text.fill", "stylers": [{"color": "#616161"}]},
  {"featureType": "transit", "elementType": "labels.text.fill", "stylers": [{"color": "#757575"}]},
  {"featureType": "water", "elementType": "geometry", "stylers": [{"color": "#000000"}]},
  {"featureType": "water", "elementType": "labels.text.fill", "stylers": [{"color": "#3d3d3d"}]}
]
''';
}
