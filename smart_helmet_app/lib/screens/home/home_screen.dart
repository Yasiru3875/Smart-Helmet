// home_screen.dart (FINAL UPDATED VERSION)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/auth_service.dart';

import 'members/Health_Monitoring/member1_page.dart';
import 'members/Stress_Detection/member2_page.dart';
import 'members/Post_Journey/member3_page.dart';
import 'members/Danger_Zone/member4_page.dart';
import 'home_dashboard.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  // Journey route data
  LatLng? _routeStart;
  LatLng? _routeEnd;
  List<LatLng>? _routePoints;
  String? _destinationName;

  // Global journey active state
  bool _isJourneyActive = false;

  late List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      HomeDashboard(
        onStartJourney: _handleStartJourney,
        onEndJourney: _handleEndJourney,
        isJourneyActive: _isJourneyActive,
      ),
      const Member1Page(),
      const Member2Page(),
      const Member3Page(),
      Member4Page(
        predefinedStart: _routeStart,
        predefinedEnd: _routeEnd,
        predefinedRoute: _routePoints,
        destinationName: _destinationName,
        startJourney: _isJourneyActive,
      ),
    ];
  }

  void _handleStartJourney({
    required LatLng start,
    required LatLng end,
    required List<LatLng> route,
    required String destinationName,
  }) {
    setState(() {
      _routeStart = start;
      _routeEnd = end;
      _routePoints = route;
      _destinationName = destinationName;
      _isJourneyActive = true;
      _index = 4; // Switch to Danger Zone tab
    });
  }

  void _handleEndJourney() {
    setState(() {
      _isJourneyActive = false;
      _routeStart = null;
      _routeEnd = null;
      _routePoints = null;
      _destinationName = null;
    });
  }

  // Helper to launch external URLs
  Future<void> _launchURL(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not launch $url')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context, listen: false);

    // Always keep pages in sync with current journey state
    _pages[0] = HomeDashboard(
      onStartJourney: _handleStartJourney,
      onEndJourney: _handleEndJourney,
      isJourneyActive: _isJourneyActive,
    );

    _pages[4] = Member4Page(
      predefinedStart: _routeStart,
      predefinedEnd: _routeEnd,
      predefinedRoute: _routePoints,
      destinationName: _destinationName,
      startJourney: _isJourneyActive,
    );

    String title = switch (_index) {
      0 => 'Smart Helmet - Home',
      1 => 'Health Monitoring',
      2 => 'Stress Detection',
      3 => 'Post Journey',
      4 => 'Danger Zone Detection',
      _ => 'Smart Helmet',
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => auth.signOut(),
            tooltip: 'Sign out',
          ),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            // Professional Header
            const DrawerHeader(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.indigo, Colors.deepPurple],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.white,
                    child: Icon(Icons.security, size: 40, color: Colors.indigo),
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Smart Helmet',
                    style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Ride Safe, Ride Smart',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
            ),

            // Main Navigation Links
            ListTile(
              leading: const Icon(Icons.home),
              title: const Text('Home'),
              selected: _index == 0,
              selectedTileColor: Colors.indigo.withOpacity(0.1),
              onTap: () {
                setState(() => _index = 0);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.favorite),
              title: const Text('Health Monitoring'),
              selected: _index == 1,
              selectedTileColor: Colors.indigo.withOpacity(0.1),
              onTap: () {
                setState(() => _index = 1);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.psychology),
              title: const Text('Stress Detection'),
              selected: _index == 2,
              selectedTileColor: Colors.indigo.withOpacity(0.1),
              onTap: () {
                setState(() => _index = 2);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Post Journey'),
              selected: _index == 3,
              selectedTileColor: Colors.indigo.withOpacity(0.1),
              onTap: () {
                setState(() => _index = 3);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.warning_amber),
              title: const Text('Danger Zone Detection'),
              selected: _index == 4,
              selectedTileColor: Colors.indigo.withOpacity(0.1),
              onTap: () {
                setState(() => _index = 4);
                Navigator.pop(context);
              },
            ),

            // Separator
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Divider(thickness: 1),
            ),

            // Additional App Links
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('About Us'),
              onTap: () {
                Navigator.pop(context);
                _launchURL('https://yourwebsite.com/about');
              },
            ),
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('Privacy Policy'),
              onTap: () {
                Navigator.pop(context);
                _launchURL('https://yourwebsite.com/privacy');
              },
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Terms of Service'),
              onTap: () {
                Navigator.pop(context);
                _launchURL('https://yourwebsite.com/terms');
              },
            ),
            ListTile(
              leading: const Icon(Icons.support_agent),
              title: const Text('Contact Support'),
              onTap: () {
                Navigator.pop(context);
                _launchURL('mailto:support@smarthelmet.com');
              },
            ),
            ListTile(
              leading: const Icon(Icons.star_rate),
              title: const Text('Rate App'),
              onTap: () {
                Navigator.pop(context);
                _launchURL('https://play.google.com/store/apps/details?id=com.yourpackage');
              },
            ),

            // App Version
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: Text(
                  'Version 1.0.0',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
      body: _pages[_index],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (v) => setState(() => _index = v),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.indigo,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.favorite), label: 'Health'),
          BottomNavigationBarItem(icon: Icon(Icons.psychology), label: 'Stress'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'Post Journey'),
          BottomNavigationBarItem(icon: Icon(Icons.warning), label: 'Danger Zone'),
        ],
      ),
    );
  }
}