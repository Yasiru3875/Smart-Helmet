import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart'; // This file is generated when you connect Flutter to Firebase
import 'package:provider/provider.dart';

// Import necessary files for your application's structure
import 'services/auth_service.dart'; // Manages authentication state
import 'screens/auth/login_screen.dart'; // User login interface
import 'screens/home/home_screen.dart'; // Main application screen
import 'screens/member_one/member1_page.dart'; // Your BLE dashboard

void main() async {
  // Ensure that Flutter widgets binding is initialized before calling native code (like Firebase)
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase with your project's configuration
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Run the main application widget
  runApp(const SmartHelmetApp());
}

// --- Main Application Widget ---
class SmartHelmetApp extends StatelessWidget {
  const SmartHelmetApp({super.key});

  @override
  Widget build(BuildContext context) {
    // MultiProvider makes the AuthService available throughout the app
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        // Add other providers for state management here if needed
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Smart Helmet',
        theme: ThemeData(
          useMaterial3: true,
          primarySwatch: Colors.indigo, // Set a primary color palette
        ),
        // The EntryPoint handles the initial routing decision (Logged In vs. Logged Out)
        home: const EntryPoint(), 
        
        // Define routes for easy navigation (Optional, but good practice)
        routes: {
          '/member1': (context) => const Member1Page(),
          // Add other member screens or pages here
        },
      ),
    );
  }
}

// --- Authentication Routing Widget ---
// This widget listens to the user's authentication state in real-time.
class EntryPoint extends StatelessWidget {
  const EntryPoint({super.key});

  @override
  Widget build(BuildContext context) {
    // Access the AuthService instance
    final auth = Provider.of<AuthService>(context);
    
    // StreamBuilder listens for changes in the user's login status
    return StreamBuilder(
      stream: auth.authStateChanges,
      builder: (context, snapshot) {
        // Show loading indicator while connecting to Firebase Auth
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        
        // If snapshot has data (user is logged in)
        if (snapshot.hasData) {
          // Send the user to the main application screen
          return const HomeScreen();
        }
        
        // If no user data (user is logged out)
        return const LoginScreen();
      },
    );
  }
}