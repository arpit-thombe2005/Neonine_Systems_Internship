import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import '../widgets/custom_button.dart';
import 'farmer_home_page.dart';
import 'provider_home_page.dart';

class RegistrationPage extends StatefulWidget {
  final String phoneNumber; // e.g. "+917208155789"
  final String mobile;      // e.g. "917208155789"

  const RegistrationPage({
    super.key,
    required this.phoneNumber,
    required this.mobile,
  });

  @override
  State<RegistrationPage> createState() => _RegistrationPageState();
}

class _RegistrationPageState extends State<RegistrationPage>
    with TickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();
  final LocationService _locationService = LocationService();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _villageController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _serviceNameController = TextEditingController();

  String _selectedUserType = 'farmer';
  bool _isRegistering = false;

  // Service categories checkboxes
  final Map<String, bool> _serviceCategories = {
    'Tractor': false,
    'Fertilizer': false,
    'Feed Supplier': false,
    'Machinery Rental': false,
    'Transport': false,
    'Other': false,
  };

  // Category ID mapping (matches the DB insert order)
  final Map<String, int> _categoryIdMap = {
    'Tractor': 1,
    'Fertilizer': 2,
    'Feed Supplier': 3,
    'Machinery Rental': 4,
    'Transport': 5,
    'Other': 6,
  };

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
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _nameController.dispose();
    _villageController.dispose();
    _addressController.dispose();
    _serviceNameController.dispose();
    super.dispose();
  }

  void _showSnackBar(String message, {bool isError = true}) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.inter(
            color: isError ? Colors.black : Colors.white,
            fontWeight: FontWeight.w500,
          ),
        ),
        backgroundColor: isError ? Colors.white : const Color(0xFF1E1E1E),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  List<int> get _selectedCategoryIds {
    return _serviceCategories.entries
        .where((e) => e.value)
        .map((e) => _categoryIdMap[e.key]!)
        .toList();
  }

  Future<void> _handleRegister() async {
    // Validate inputs
    if (_nameController.text.trim().isEmpty) {
      _showSnackBar('Please enter your full name.');
      return;
    }

    if (_selectedUserType == 'service_provider') {
      if (_serviceNameController.text.trim().isEmpty) {
        _showSnackBar('Please enter your service name.');
        return;
      }
      if (_selectedCategoryIds.isEmpty) {
        _showSnackBar('Please select at least one service category.');
        return;
      }
    }

    setState(() => _isRegistering = true);

    try {
      // Capture GPS location in background
      double? latitude;
      double? longitude;
      final position = await _locationService.getCurrentPosition();
      if (position != null) {
        latitude = position.latitude;
        longitude = position.longitude;
      }

      // Register user via API
      final result = await _apiService.registerUser(
        fullName: _nameController.text.trim(),
        phoneNumber: widget.mobile,
        userType: _selectedUserType == 'farmer' ? 'farmer' : 'service_provider',
        villageArea: _villageController.text.trim().isNotEmpty
            ? _villageController.text.trim()
            : null,
        address: _addressController.text.trim().isNotEmpty
            ? _addressController.text.trim()
            : null,
        latitude: latitude,
        longitude: longitude,
        serviceName: _selectedUserType == 'service_provider'
            ? _serviceNameController.text.trim()
            : null,
        categoryIds:
            _selectedUserType == 'service_provider' ? _selectedCategoryIds : null,
      );

      if (result == null) {
        throw Exception('Registration failed. Please try again.');
      }

      // Save session with user data
      await _authService.saveSession(widget.phoneNumber, userData: result);

      if (!mounted) return;

      // Navigate to role-based homepage
      Widget homePage;
      if (_selectedUserType == 'service_provider') {
        homePage = const ProviderHomePage();
      } else {
        homePage = const FarmerHomePage();
      }

      Navigator.pushAndRemoveUntil(
        context,
        PageRouteBuilder(
          pageBuilder: (_, animation, __) => homePage,
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 500),
        ),
        (route) => false,
      );
    } catch (e) {
      debugPrint('Registration error: $e');
      if (mounted) {
        setState(() => _isRegistering = false);
        _showSnackBar('Registration failed. Please try again.');
      }
    }
  }

  Widget _buildInputField({
    required String label,
    required TextEditingController controller,
    bool readOnly = false,
    String? initialValue,
    int maxLines = 1,
  }) {
    if (readOnly && initialValue != null) {
      controller.text = initialValue;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: TextSpan(
            text: label,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: Colors.white60,
              fontWeight: FontWeight.w500,
            ),
            children: const [
              TextSpan(
                text: '*',
                style: TextStyle(color: Color(0xFFFF4444)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withOpacity(0.08),
              width: 1,
            ),
          ),
          child: TextField(
            controller: controller,
            readOnly: readOnly,
            maxLines: maxLines,
            style: GoogleFonts.inter(
              color: readOnly ? Colors.white38 : Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w400,
            ),
            decoration: InputDecoration(
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              hintStyle: GoogleFonts.inter(
                color: Colors.white.withValues(alpha: 0.16),
                fontSize: 15,
              ),
            ),
            cursorColor: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildOptionalInputField({
    required String label,
    required TextEditingController controller,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 13,
            color: Colors.white60,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withOpacity(0.08),
              width: 1,
            ),
          ),
          child: TextField(
            controller: controller,
            maxLines: maxLines,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w400,
            ),
            decoration: InputDecoration(
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              hintStyle: GoogleFonts.inter(
                color: Colors.white.withValues(alpha: 0.16),
                fontSize: 15,
              ),
            ),
            cursorColor: Colors.white,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 48),

                  // Title
                  Text(
                    'REGISTER YOURSELF:',
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 1.5,
                    ),
                  ),

                  const SizedBox(height: 36),

                  // Full Name
                  _buildInputField(
                    label: 'Full Name',
                    controller: _nameController,
                  ),

                  const SizedBox(height: 20),

                  // Phone Number (read-only, pre-filled)
                  _buildInputField(
                    label: 'Phone Number',
                    controller: TextEditingController(text: widget.phoneNumber),
                    readOnly: true,
                    initialValue: widget.phoneNumber,
                  ),

                  const SizedBox(height: 20),

                  // User Type dropdown
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RichText(
                        text: TextSpan(
                          text: 'User Type',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: Colors.white60,
                            fontWeight: FontWeight.w500,
                          ),
                          children: const [
                            TextSpan(
                              text: '*',
                              style: TextStyle(color: Color(0xFFFF4444)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A1A),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.08),
                            width: 1,
                          ),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedUserType,
                            dropdownColor: const Color(0xFF1E1E1E),
                            icon: const Icon(
                              Icons.keyboard_arrow_down_rounded,
                              color: Colors.white38,
                            ),
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w400,
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'farmer',
                                child: Text('Farmer'),
                              ),
                              DropdownMenuItem(
                                value: 'service_provider',
                                child: Text('Service Provider'),
                              ),
                            ],
                            onChanged: (value) {
                              setState(() {
                                _selectedUserType = value ?? 'farmer';
                              });
                            },
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // ── Conditional fields based on user type ──

                  // Service Provider specific fields
                  if (_selectedUserType == 'service_provider') ...[
                    _buildInputField(
                      label: 'Service Name',
                      controller: _serviceNameController,
                    ),
                    const SizedBox(height: 20),

                    // Service Category checkboxes
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RichText(
                          text: TextSpan(
                            text: 'Service Category',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: Colors.white60,
                              fontWeight: FontWeight.w500,
                            ),
                            children: const [
                              TextSpan(
                                text: '*',
                                style: TextStyle(color: Color(0xFFFF4444)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1A1A),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.08),
                              width: 1,
                            ),
                          ),
                          child: Column(
                            children:
                                _serviceCategories.keys.map((category) {
                              return CheckboxListTile(
                                title: Text(
                                  category,
                                  style: GoogleFonts.inter(
                                    color: Colors.white70,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                                value: _serviceCategories[category],
                                onChanged: (bool? value) {
                                  setState(() {
                                    _serviceCategories[category] =
                                        value ?? false;
                                  });
                                },
                                activeColor: Colors.white,
                                checkColor: Colors.black,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                visualDensity: const VisualDensity(
                                    horizontal: -4, vertical: -4),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Village/Area — shown for both farmer and service provider
                  _buildOptionalInputField(
                    label: 'Village / Area',
                    controller: _villageController,
                  ),

                  const SizedBox(height: 20),

                  // Address — shown for both farmer and service provider
                  _buildOptionalInputField(
                    label: 'Address',
                    controller: _addressController,
                    maxLines: 2,
                  ),

                  const SizedBox(height: 36),

                  // Register button
                  CustomButton(
                    label: 'Register Using OTP',
                    onPressed: _isRegistering ? null : _handleRegister,
                    isLoading: _isRegistering,
                  ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
