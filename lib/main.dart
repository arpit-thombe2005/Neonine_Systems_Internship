import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'services/auth_service.dart';
import 'services/api_service.dart';
import 'services/location_service.dart';
import 'services/language_manager.dart';
import 'screens/login_page.dart';
import 'screens/farmer_home_page.dart';
import 'screens/provider_home_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize language manager from saved preferences
  await LanguageManager.instance.init();

  // Lock orientation to portrait
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Check if user is signed in and determine their role
  final authService = AuthService();
  final bool isLoggedIn = await authService.isSignedIn();
  String? userType;

  if (isLoggedIn) {
    userType = await authService.getUserType();

    // Update location in background on app start
    _updateLocationOnStart(authService);
  }

  runApp(NeonineApp(isLoggedIn: isLoggedIn, userType: userType));
}

/// Update the user's location silently every time the app starts
void _updateLocationOnStart(AuthService authService) async {
  try {
    final locationService = LocationService();
    final apiService = ApiService();

    final userId = await authService.getUserId();
    if (userId == null) return;

    final position = await locationService.getCurrentPosition();
    if (position != null) {
      await apiService.updateLocation(
        userId: userId,
        latitude: position.latitude,
        longitude: position.longitude,
      );
      debugPrint('Location updated on app start.');
    }
  } catch (e) {
    debugPrint('Background location update on start failed: $e');
  }
}

class NeonineApp extends StatelessWidget {
  final bool isLoggedIn;
  final String? userType;

  const NeonineApp({super.key, required this.isLoggedIn, this.userType});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LanguageManager.instance.currentLanguage,
      builder: (context, currentLanguage, _) {
        // Determine the home screen based on login status and user type
        Widget homeScreen;
        if (!isLoggedIn) {
          homeScreen = const LoginPage();
        } else if (userType == 'service_provider') {
          homeScreen = const ProviderHomePage();
        } else {
          homeScreen = const FarmerHomePage();
        }

        return MaterialApp(
          key: ValueKey(currentLanguage), // Force reload of tree on language toggle
          title: 'Neonine',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            brightness: Brightness.dark,
            scaffoldBackgroundColor: const Color(0xFF0A0A0A),
            colorScheme: const ColorScheme.dark(
              primary: Colors.white,
              secondary: Color(0xFF1E1E1E),
              surface: Color(0xFF141414),
              onSurface: Colors.white,
            ),
            textTheme: GoogleFonts.interTextTheme(
              ThemeData.dark().textTheme,
            ).apply(
              bodyColor: Colors.white,
              displayColor: Colors.white,
            ),
            pageTransitionsTheme: const PageTransitionsTheme(
              builders: {
                TargetPlatform.android: CupertinoPageTransitionsBuilder(),
                TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
              },
            ),
          ),
          home: homeScreen,
        );
      },
    );
  }
}
