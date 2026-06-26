import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../services/translation_service.dart';
import '../widgets/language_selector.dart';
import 'account_page.dart';

class ProviderHomePage extends StatefulWidget {
  const ProviderHomePage({super.key});

  @override
  State<ProviderHomePage> createState() => _ProviderHomePageState();
}

class _ProviderHomePageState extends State<ProviderHomePage>
    with TickerProviderStateMixin {
  final AuthService _authService = AuthService();
  final ApiService _apiService = ApiService();
  final LocationService _locationService = LocationService();

  String _userName = 'User';
  String _currentLocation = 'Fetching location...';
  bool _isOnline = false;
  bool _isTogglingStatus = false;
  int _todayRequestCount = 0;
  bool _isLoadingRequests = false;
  List<Map<String, dynamic>> _requestsList = [];

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  Widget _buildStatusBadge(String status) {
    Color color;
    Color bgColor;

    switch (status.toLowerCase()) {
      case 'pending':
        color = const Color(0xFFFF9800);
        bgColor = const Color(0xFFFF9800).withOpacity(0.12);
        break;
      case 'accepted':
        color = const Color(0xFF4AE54A);
        bgColor = const Color(0xFF4AE54A).withOpacity(0.12);
        break;
      case 'rejected':
        color = const Color(0xFFFF4444);
        bgColor = const Color(0xFFFF4444).withOpacity(0.12);
        break;
      case 'completed':
        color = const Color(0xFF2196F3);
        bgColor = const Color(0xFF2196F3).withOpacity(0.12);
        break;
      default:
        color = Colors.white54;
        bgColor = Colors.white10;
    }

    String label;
    switch (status.toLowerCase()) {
      case 'pending':
        label = tr('status_pending');
        break;
      case 'accepted':
        label = tr('status_accepted');
        break;
      case 'rejected':
        label = tr('status_rejected');
        break;
      case 'completed':
        label = tr('status_completed');
        break;
      default:
        label = status.toUpperCase();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Future<void> _updateRequestStatus(String requestId, String status) async {
    try {
      final result = await _apiService.updateServiceRequestStatus(
        requestId: requestId,
        status: status,
      );
      if (result != null) {
        await _loadTodayRequests();
      }
    } catch (e) {
      debugPrint('Error updating request status: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to update request: ${e.toString().replaceAll('Exception:', '').trim()}',
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
    }
  }

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
    _loadTodayRequests();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    final name = await _authService.getUserName();
    final data = await _authService.getUserData();

    if (mounted) {
      setState(() {
        if (name != null) _userName = name;
        // Try to get online status from cached data
        if (data != null && data['is_online'] != null) {
          _isOnline = data['is_online'] == true;
        }
      });
    }
  }

  Future<void> _initLocation() async {
    final position = await _locationService.getCurrentPosition();
    if (position != null) {
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
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _currentLocation = 'Location unavailable';
        });
      }
    }
  }

  Future<void> _loadTodayRequests() async {
    setState(() => _isLoadingRequests = true);
    try {
      final userId = await _authService.getUserId();
      if (userId != null) {
        final count = await _apiService.getTodayRequestCount(userId);
        final requests = await _apiService.getTodayRequests(userId);
        if (mounted) {
          setState(() {
            _todayRequestCount = count;
            _requestsList = requests;
            _isLoadingRequests = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoadingRequests = false);
      }
    } catch (e) {
      debugPrint('Error loading requests: $e');
      if (mounted) setState(() => _isLoadingRequests = false);
    }
  }

  Future<void> _toggleOnlineStatus() async {
    if (_isTogglingStatus) return;

    setState(() => _isTogglingStatus = true);

    try {
      final userId = await _authService.getUserId();
      if (userId != null) {
        final newStatus = !_isOnline;
        await _apiService.toggleOnlineStatus(
          userId: userId,
          isOnline: newStatus,
        );

        // Update cached data
        await _authService.updateCachedUserData({'is_online': newStatus});

        if (mounted) {
          setState(() {
            _isOnline = newStatus;
            _isTogglingStatus = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Error toggling status: $e');
      if (mounted) {
        setState(() => _isTogglingStatus = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to update status. Please try again.',
              style: GoogleFonts.inter(fontWeight: FontWeight.w500),
            ),
            backgroundColor: Colors.white,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
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
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.topRight,
                  child: const LanguageSelector(),
                ),
                const SizedBox(height: 16),

                // Top bar with online/offline toggle
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Greeting
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${tr('hello')} $_userName',
                            style: GoogleFonts.inter(
                              fontSize: 26,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 6),
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
                        ],
                      ),
                    ),

                    const SizedBox(width: 12),

                    // Online/Offline toggle
                    GestureDetector(
                      onTap: _toggleOnlineStatus,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: _isOnline
                              ? const Color(0xFF4AE54A).withOpacity(0.12)
                              : const Color(0xFFFF4444).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(
                            color: _isOnline
                                ? const Color(0xFF4AE54A).withOpacity(0.3)
                                : const Color(0xFFFF4444).withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Status dot
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: _isOnline
                                    ? const Color(0xFF4AE54A)
                                    : const Color(0xFFFF4444),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: (_isOnline
                                            ? const Color(0xFF4AE54A)
                                            : const Color(0xFFFF4444))
                                        .withOpacity(0.4),
                                    blurRadius: 8,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _isOnline ? 'Online' : 'Offline',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _isOnline
                                    ? const Color(0xFF4AE54A)
                                    : const Color(0xFFFF4444),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                SizedBox(height: MediaQuery.of(context).size.height * 0.06),

                // Status card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111111),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.07),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.4),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Icon(
                        _isOnline
                            ? Icons.wifi_rounded
                            : Icons.wifi_off_rounded,
                        color: _isOnline
                            ? const Color(0xFF4AE54A)
                            : Colors.white24,
                        size: 40,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _isOnline
                            ? 'Your services are visible to farmers'
                            : 'You are offline. Toggle to go online.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: Colors.white38,
                          fontWeight: FontWeight.w400,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Today's Requests button
                GestureDetector(
                  onTap: _loadTodayRequests,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF111111),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.07),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tr('todays_requests'),
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Tap to refresh',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: Colors.white24,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: _isLoadingRequests
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor:
                                        AlwaysStoppedAnimation<Color>(
                                            Colors.white54),
                                  ),
                                )
                              : Text(
                                  '$_todayRequestCount',
                                  style: GoogleFonts.inter(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Requests Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${tr('todays_requests')}:',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white70,
                      ),
                    ),
                    if (_requestsList.isNotEmpty)
                      Text(
                        '${_requestsList.length} items',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Colors.white38,
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 12),

                // Requests List
                Expanded(
                  child: _isLoadingRequests
                      ? const Center(
                          child: SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white38),
                            ),
                          ),
                        )
                      : _requestsList.isEmpty
                          ? Center(
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
                            )
                          : ListView.builder(
                              physics: const BouncingScrollPhysics(),
                              itemCount: _requestsList.length,
                              itemBuilder: (context, index) {
                                final request = _requestsList[index];
                                final farmerName = request['farmer_name'] ?? 'Farmer';
                                final farmerPhone = request['farmer_phone'] ?? '';
                                final message = request['message'] ?? '';
                                final status = request['status'] ?? 'pending';
                                final requestId = request['id'];

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 16),
                                  padding: const EdgeInsets.all(18),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF111111),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.06),
                                      width: 1,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Top row: Farmer name & status badge
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              farmerName,
                                              style: GoogleFonts.inter(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.white,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          _buildStatusBadge(status),
                                        ],
                                      ),

                                      // Phone number
                                      if (farmerPhone.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          '+$farmerPhone',
                                          style: GoogleFonts.inter(
                                            fontSize: 13,
                                            color: const Color(0xFF4AE54A),
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],

                                      // Message
                                      if (message.isNotEmpty) ...[
                                        const SizedBox(height: 12),
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF1A1A1A),
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(
                                              color: Colors.white.withOpacity(0.04),
                                              width: 1,
                                            ),
                                          ),
                                          child: Text(
                                            message,
                                            style: GoogleFonts.inter(
                                              fontSize: 13,
                                              color: Colors.white70,
                                              fontStyle: FontStyle.italic,
                                            ),
                                          ),
                                        ),
                                      ],

                                      // Actions
                                      if (status.toLowerCase() == 'pending') ...[
                                        const SizedBox(height: 16),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: OutlinedButton(
                                                onPressed: () => _updateRequestStatus(requestId, 'rejected'),
                                                style: OutlinedButton.styleFrom(
                                                  foregroundColor: const Color(0xFFFF4444),
                                                  side: BorderSide(
                                                    color: const Color(0xFFFF4444).withOpacity(0.4),
                                                  ),
                                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius: BorderRadius.circular(10),
                                                  ),
                                                ),
                                                child: Text(
                                                  tr('reject'),
                                                  style: GoogleFonts.inter(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: ElevatedButton(
                                                onPressed: () => _updateRequestStatus(requestId, 'accepted'),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: const Color(0xFF4AE54A),
                                                  foregroundColor: Colors.black,
                                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                                  elevation: 0,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius: BorderRadius.circular(10),
                                                  ),
                                                ),
                                                child: Text(
                                                  tr('approve'),
                                                  style: GoogleFonts.inter(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ] else if (status.toLowerCase() == 'accepted') ...[
                                        const SizedBox(height: 16),
                                        SizedBox(
                                          width: double.infinity,
                                          child: ElevatedButton(
                                            onPressed: () => _updateRequestStatus(requestId, 'completed'),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.white,
                                              foregroundColor: Colors.black,
                                              padding: const EdgeInsets.symmetric(vertical: 12),
                                              elevation: 0,
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                            ),
                                            child: Text(
                                              tr('complete'),
                                              style: GoogleFonts.inter(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
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
}
