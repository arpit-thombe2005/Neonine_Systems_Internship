import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pinput/pinput.dart';
import '../services/otp_service.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../services/translation_service.dart';
import '../widgets/custom_button.dart';
import '../widgets/language_selector.dart';
import 'registration_page.dart';
import 'farmer_home_page.dart';
import 'provider_home_page.dart';

class OtpPage extends StatefulWidget {
  final String phoneNumber; // display format e.g. "+917208155789"
  final String mobile;      // MSG91 format e.g. "917208155789"

  const OtpPage({
    super.key,
    required this.phoneNumber,
    required this.mobile,
  });

  @override
  State<OtpPage> createState() => _OtpPageState();
}

class _OtpPageState extends State<OtpPage> with TickerProviderStateMixin {
  final OtpService _otpService = OtpService();
  final AuthService _authService = AuthService();
  final ApiService _apiService = ApiService();
  final LocationService _locationService = LocationService();
  final TextEditingController _pinController = TextEditingController();
  final FocusNode _pinFocusNode = FocusNode();

  bool _isVerifying = false;
  bool _isResending = false;
  int _secondsRemaining = 60;
  Timer? _countdownTimer;

  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _startCountdown();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
    );
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
    );

    _fadeController.forward();
    _slideController.forward();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _pinController.dispose();
    _pinFocusNode.dispose();
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    setState(() => _secondsRemaining = 60);

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining == 0) {
        timer.cancel();
      } else {
        setState(() => _secondsRemaining--);
      }
    });
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

  Future<void> _verifyOtp() async {
    final String otp = _pinController.text.trim();

    if (otp.length < 6) {
      _showSnackBar('Please enter the complete 6-digit OTP.');
      return;
    }

    setState(() => _isVerifying = true);

    await _otpService.verifyOtp(
      mobile: widget.mobile,
      otp: otp,
      onSuccess: () async {
        debugPrint('OTP verified successfully! Checking registration...');

        try {
          // Check if user is registered in Neon DB
          final userData = await _authService.checkUserExists(widget.mobile);

          if (!mounted) return;

          if (userData == null) {
            // User not registered — navigate to registration page
            debugPrint('User not registered. Navigating to registration...');
            setState(() => _isVerifying = false);

            Navigator.pushReplacement(
              context,
              PageRouteBuilder(
                pageBuilder: (_, animation, __) => RegistrationPage(
                  phoneNumber: widget.phoneNumber,
                  mobile: widget.mobile,
                ),
                transitionsBuilder: (_, animation, __, child) {
                  return SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(1, 0),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(
                        parent: animation, curve: Curves.easeOutCubic)),
                    child: child,
                  );
                },
                transitionDuration: const Duration(milliseconds: 400),
              ),
            );
            return;
          }

          // User exists — save session and update location
          debugPrint('User found: ${userData['full_name']}');
          await _authService.saveSession(widget.phoneNumber, userData: userData);

          // Update location in background
          _updateLocationInBackground(userData['id']);

          if (!mounted) return;

          // Navigate to role-based homepage
          final userType = userData['user_type'] as String;
          Widget homePage;
          if (userType == 'service_provider') {
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
          debugPrint('Registration check error: $e');
          if (!mounted) return;
          setState(() => _isVerifying = false);
          _showSnackBar(
              'Connection error. Please check your network and try again.');
        }
      },
      onError: (String errorMessage) {
        setState(() => _isVerifying = false);
        if (mounted) {
          _showSnackBar(errorMessage);
          _pinController.clear();
        }
      },
    );
  }

  /// Update user's location in the background after login
  void _updateLocationInBackground(String userId) async {
    try {
      final position = await _locationService.getCurrentPosition();
      if (position != null) {
        await _apiService.updateLocation(
          userId: userId,
          latitude: position.latitude,
          longitude: position.longitude,
        );
        debugPrint('Location updated after login.');
      }
    } catch (e) {
      debugPrint('Background location update failed: $e');
    }
  }

  Future<void> _resendOtp() async {
    if (_secondsRemaining > 0) return;
    setState(() => _isResending = true);

    await _otpService.resendOtp(
      mobile: widget.mobile,
      onSuccess: () {
        setState(() => _isResending = false);
        _startCountdown();
        _pinController.clear();
        if (mounted) _showSnackBar('OTP resent successfully.', isError: false);
      },
      onError: (String errorMessage) {
        setState(() => _isResending = false);
        if (mounted) _showSnackBar(errorMessage);
      },
    );
  }

  String get _displayPhone {
    return widget.phoneNumber;
  }

  @override
  Widget build(BuildContext context) {
    final PinTheme defaultPinTheme = PinTheme(
      width: 48,
      height: 56,
      textStyle: GoogleFonts.inter(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: Colors.white,
        letterSpacing: 1,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withOpacity(0.08),
          width: 1.5,
        ),
      ),
    );

    final PinTheme focusedPinTheme = defaultPinTheme.copyWith(
      decoration: defaultPinTheme.decoration!.copyWith(
        border: Border.all(color: Colors.white54, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.white.withOpacity(0.06),
            blurRadius: 12,
            spreadRadius: 0,
          ),
        ],
      ),
    );

    final PinTheme filledPinTheme = defaultPinTheme.copyWith(
      decoration: defaultPinTheme.decoration!.copyWith(
        color: const Color(0xFF222222),
        border: Border.all(color: Colors.white24, width: 1.5),
      ),
    );

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.topRight,
                      child: const LanguageSelector(),
                    ),
                    SizedBox(height: MediaQuery.of(context).size.height * 0.08),

                    // Title — centered, matching Figma
                    Text(
                      tr('check_sms'),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: -0.5,
                        height: 1.2,
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Subtitle with phone number
                    RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: Colors.white38,
                          height: 1.5,
                        ),
                        children: [
                          TextSpan(text: tr('sms_sent_to')),
                          TextSpan(
                            text: _displayPhone,
                            style: const TextStyle(
                              color: Colors.white60,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 48),

                    // OTP input — 6 dark boxes matching Figma
                    Center(
                      child: Pinput(
                        controller: _pinController,
                        focusNode: _pinFocusNode,
                        length: 6,
                        defaultPinTheme: defaultPinTheme,
                        focusedPinTheme: focusedPinTheme,
                        submittedPinTheme: filledPinTheme,
                        showCursor: true,
                        cursor: Container(
                          width: 2,
                          height: 22,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                        hapticFeedbackType: HapticFeedbackType.lightImpact,
                        onCompleted: (_) => _verifyOtp(),
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Resend OTP
                     Center(
                      child: _secondsRemaining > 0
                          ? Text(
                              trWithArgs('resend_in', [_secondsRemaining.toString()]),
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: Colors.white24,
                                fontWeight: FontWeight.w400,
                              ),
                            )
                          : GestureDetector(
                              onTap: _isResending ? null : _resendOtp,
                              child: AnimatedOpacity(
                                opacity: _isResending ? 0.4 : 1.0,
                                duration: const Duration(milliseconds: 200),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1A1A1A),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.1),
                                      width: 1,
                                    ),
                                  ),
                                  child: Text(
                                    _isResending ? 'Sending...' : tr('resend_otp'),
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      color: Colors.white54,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                    ),

                    const SizedBox(height: 40),

                    // Verify OTP button
                    CustomButton(
                      label: tr('verify_otp'),
                      onPressed: _isVerifying ? null : _verifyOtp,
                      isLoading: _isVerifying,
                    ),

                    const SizedBox(height: 28),

                    // Use a different number
                    Center(
                      child: GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Text(
                          'Use a different Number?',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: Colors.white24,
                            decoration: TextDecoration.underline,
                            decorationColor: Colors.white24,
                          ),
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
      ),
    );
  }
}
