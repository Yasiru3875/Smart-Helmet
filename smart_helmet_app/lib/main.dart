import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart'; // Generated Firebase config file
import 'package:provider/provider.dart';

// ────────────────────────────────────────────────
// Services & Providers
// ────────────────────────────────────────────────
import 'services/auth_service.dart';
import 'services/bluetooth_manager.dart';
import 'providers/journey_provider.dart';
import 'providers/sensor_data_provider.dart'; // ← NEW: Live sensor values
import 'providers/ride_session_provider.dart';
import 'providers/emotion_provider.dart';
import 'providers/sos_controller.dart';

// ────────────────────────────────────────────────
// Screens
// ────────────────────────────────────────────────
import 'screens/auth/login_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/home/members/Health_Monitoring/member1_page.dart';
import 'screens/home/emergency_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const SmartHelmetApp());
}

class SmartHelmetApp extends StatelessWidget {
  const SmartHelmetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Authentication state
        ChangeNotifierProvider(create: (_) => AuthService()),

        // Bluetooth connection manager
        ChangeNotifierProvider(create: (_) => BluetoothManager()),

        // Journey/route state (start/end journey, route points, etc.)
        ChangeNotifierProvider(create: (_) => JourneyProvider()),

        // NEW: Shared live sensor data (heart rate, temp, stress, alerts)
        ChangeNotifierProvider(create: (_) => SensorDataProvider()),

        ChangeNotifierProvider(create: (_) => RideSessionProvider()),

        ChangeNotifierProvider(create: (_) => EmotionProvider()),

        // SOS Emergency System
        ChangeNotifierProvider(create: (_) => SOSController()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Smart Helmet',
        theme: ThemeData(
          useMaterial3: true,
          primarySwatch: Colors.indigo,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
          scaffoldBackgroundColor: Colors.grey[50],
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.indigo,
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
          cardTheme: CardThemeData(
            elevation: 4,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
        home: const EntryPoint(),

        // Named routes (optional but recommended)
        routes: {
          '/member1': (context) => const Member1Page(),
          '/emergency': (context) => const EmergencyScreen(),
          // Add more routes here when needed (member2, member3, etc.)
        },
      ),
    );
  }
}

// ────────────────────────────────────────────────
// Entry point that decides Login vs Home based on auth state
// ────────────────────────────────────────────────
class EntryPoint extends StatelessWidget {
  const EntryPoint({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context);

    return StreamBuilder(
      stream: auth.authStateChanges,
      builder: (context, snapshot) {
        // Still connecting to Firebase Auth → show loader
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // User is logged in → go to main app
        if (snapshot.hasData) {
          return const HomeScreen();
        }

        // No user → show login screen
        return const LoginScreen();
      },
    );
  }
}
