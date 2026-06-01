import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/otp_service.dart';
import '../widgets/custom_button.dart';
import 'otp_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with TickerProviderStateMixin {
  final OtpService _otpService = OtpService();
  final TextEditingController _phoneController = TextEditingController();

  bool _isLoading = false;

  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
    );
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
    );

    _fadeController.forward();
    _slideController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  String get _completePhoneNumber {
    final digits = _phoneController.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 10) {
      return '+91$digits';
    }
    return '';
  }

  String get _mobileFormatted {
    final digits = _phoneController.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 10) {
      return '91$digits';
    }
    return '';
  }

  bool get _isPhoneValid {
    final digits = _phoneController.text.replaceAll(RegExp(r'\D'), '');
    return digits.length == 10;
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

  Future<void> _handleSendOtp() async {
    if (!_isPhoneValid) {
      _showSnackBar('Please enter a valid 10-digit phone number.');
      return;
    }

    setState(() => _isLoading = true);

    final mobile = _mobileFormatted;
    final completePhone = _completePhoneNumber;

    await _otpService.sendOtp(
      mobile: mobile,
      onSuccess: () {
        setState(() => _isLoading = false);
        if (mounted) {
          Navigator.push(
            context,
            PageRouteBuilder(
              pageBuilder: (_, animation, __) => OtpPage(
                phoneNumber: completePhone,
                mobile: mobile,
              ),
              transitionsBuilder: (_, animation, __, child) {
                return SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(1, 0),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                        parent: animation, curve: Curves.easeOutCubic),
                  ),
                  child: child,
                );
              },
              transitionDuration: const Duration(milliseconds: 400),
            ),
          );
        }
      },
      onError: (String errorMessage) {
        setState(() => _isLoading = false);
        if (mounted) _showSnackBar(errorMessage);
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
          child: SlideTransition(
            position: _slideAnimation,
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(height: MediaQuery.of(context).size.height * 0.18),

                    // Welcome heading — centered, uppercase, matching Figma
                    Text(
                      'WELCOME BACK',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 3,
                        height: 1.2,
                      ),
                    ),

                    const SizedBox(height: 14),

                    Text(
                      'SIGN IN WITH YOUR\nREGISTERED PHONE NUMBER',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: Colors.white38,
                        height: 1.6,
                        letterSpacing: 1.5,
                      ),
                    ),

                    SizedBox(height: MediaQuery.of(context).size.height * 0.08),

                    // Phone number input — simple dark box matching Figma
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A1A),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.08),
                          width: 1,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        child: TextField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          maxLength: 10,
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 2.5,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: InputDecoration(
                            hintText: 'XXXXX XXXXX',
                            hintStyle: GoogleFonts.inter(
                              color: Colors.white.withValues(alpha: 0.16),
                              fontSize: 17,
                              fontWeight: FontWeight.w400,
                              letterSpacing: 2.5,
                            ),
                            border: InputBorder.none,
                            counterText: '',
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 16,
                            ),
                          ),
                          cursorColor: Colors.white,
                          onChanged: (_) => setState(() {}),
                        ),
                      ),

                    ),

                    const SizedBox(height: 32),

                    // Send OTP button
                    CustomButton(
                      label: 'Send OTP',
                      onPressed: _isLoading ? null : _handleSendOtp,
                      isLoading: _isLoading,
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
