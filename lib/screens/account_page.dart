import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/auth_service.dart';
import '../services/translation_service.dart';
import '../widgets/custom_button.dart';
import '../widgets/language_selector.dart';
import 'login_page.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage>
    with SingleTickerProviderStateMixin {
  final AuthService _authService = AuthService();

  Map<String, dynamic>? _userData;
  bool _isLoading = true;
  bool _isLoggingOut = false;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
    );
    _fadeController.forward();
    _loadUserData();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    final data = await _authService.getUserData();
    if (mounted) {
      setState(() {
        _userData = data;
        _isLoading = false;
      });
    }
  }

  Future<void> _handleLogout() async {
    setState(() => _isLoggingOut = true);
    await _authService.signOut();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        PageRouteBuilder(
          pageBuilder: (_, animation, __) => const LoginPage(),
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 500),
        ),
        (route) => false,
      );
    }
  }

  Widget _buildDetailRow(String label, String? value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withOpacity(0.05),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: Colors.white38, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: Colors.white24,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value ?? '—',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    color: value != null ? Colors.white : Colors.white24,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userType = _userData?['user_type'] as String?;
    final isProvider = userType == 'service_provider';

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            margin: const EdgeInsets.only(left: 16, top: 8, bottom: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF141414),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withOpacity(0.07),
                width: 1,
              ),
            ),
            child: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Colors.white70,
              size: 18,
            ),
          ),
        ),
        title: Text(
          tr('account_profile'),
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: LanguageSelector(),
          ),
        ],
      ),
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(
                    valueColor:
                        AlwaysStoppedAnimation<Color>(Colors.white38),
                  ),
                )
              : SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        const SizedBox(height: 20),

                        // Profile avatar
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1A1A),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.1),
                              width: 1.5,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              (_userData?['full_name'] as String? ?? 'U')
                                  .substring(0, 1)
                                  .toUpperCase(),
                              style: GoogleFonts.inter(
                                fontSize: 32,
                                fontWeight: FontWeight.w700,
                                color: Colors.white60,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // User name
                        Text(
                          _userData?['full_name'] ?? 'User',
                          style: GoogleFonts.inter(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),

                        const SizedBox(height: 4),

                        // User type & KYC badges
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 5),
                              decoration: BoxDecoration(
                                color: isProvider
                                    ? const Color(0xFF4AE54A).withOpacity(0.1)
                                    : Colors.white.withOpacity(0.06),
                                borderRadius: BorderRadius.circular(100),
                              ),
                              child: Text(
                                userType == 'service_provider'
                                    ? tr('service_provider')
                                    : tr('farmer'),
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: isProvider
                                      ? const Color(0xFF4AE54A)
                                      : Colors.white54,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (_userData?['aadhaar_hash'] != null && (_userData?['aadhaar_hash'] as String).isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF4AE54A).withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(100),
                                  border: Border.all(
                                    color: const Color(0xFF4AE54A).withOpacity(0.4),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.verified_user_rounded,
                                      color: Color(0xFF4AE54A),
                                      size: 14,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'KYC VERIFIED',
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        color: const Color(0xFF4AE54A),
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),

                        const SizedBox(height: 32),

                        // Details card
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: const Color(0xFF111111),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.07),
                              width: 1,
                            ),
                          ),
                          child: Column(
                            children: [
                              _buildDetailRow(
                                tr('full_name').toUpperCase(),
                                _userData?['full_name'],
                                Icons.person_outline_rounded,
                              ),
                              _buildDetailRow(
                                tr('phone_number').toUpperCase(),
                                _userData?['phone_number'],
                                Icons.phone_outlined,
                              ),
                              _buildDetailRow(
                                tr('user_type').toUpperCase(),
                                userType == 'service_provider'
                                    ? tr('service_provider')
                                    : tr('farmer'),
                                Icons.badge_outlined,
                              ),
                              _buildDetailRow(
                                tr('village_area').toUpperCase(),
                                _userData?['village_area'],
                                Icons.location_city_outlined,
                              ),
                              _buildDetailRow(
                                tr('address').toUpperCase(),
                                _userData?['address'],
                                Icons.home_outlined,
                              ),

                              // Provider-specific fields
                              if (isProvider) ...[
                                _buildDetailRow(
                                  tr('service_name').toUpperCase(),
                                  _userData?['service_name'],
                                  Icons.build_outlined,
                                ),
                                _buildDetailRow(
                                  tr('service_category').toUpperCase() + 'S',
                                  (_userData?['categories'] as List?)
                                      ?.join(', '),
                                  Icons.category_outlined,
                                ),
                                _buildDetailRow(
                                  'STATUS',
                                  _userData?['is_online'] == true
                                      ? 'Online'
                                      : 'Offline',
                                  Icons.circle,
                                ),
                              ],
                            ],
                          ),
                        ),

                        const SizedBox(height: 40),

                        // Logout button
                        CustomButton(
                          label: tr('logout'),
                          onPressed:
                              _isLoggingOut ? null : _handleLogout,
                          isLoading: _isLoggingOut,
                          isOutlined: true,
                        ),

                        const SizedBox(height: 16),

                        Center(
                          child: Text(
                            'Your data is securely stored.',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: Colors.white12,
                              letterSpacing: 0.2,
                            ),
                          ),
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
