// home_screen.dart (FINAL FIXED & OPTIMIZED VERSION)
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
import 'Side_Panel_Screens/AboutUsPage.dart';
import 'Side_Panel_Screens/PrivacyPolicyPage.dart';
import 'Side_Panel_Screens/TermsOfServicePage.dart';
import 'Side_Panel_Screens/ContactSupportPage.dart';

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
    _initializePages();
  }

  void _initializePages() {
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

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Rebuild pages when journey state changes
    _updateJourneyDependentPages();
  }

  void _updateJourneyDependentPages() {
    setState(() {
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
    });
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
      _index = 4; // Auto-switch to Danger Zone tab
    });
    _updateJourneyDependentPages();
  }

  void _handleEndJourney() {
    setState(() {
      _isJourneyActive = false;
      _routeStart = null;
      _routeEnd = null;
      _routePoints = null;
      _destinationName = null;
    });
    _updateJourneyDependentPages();
  }

  Future<void> _launchURL(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not launch $url')),
      );
    }
  }

  String _getTitle(int index) {
    return switch (index) {
      0 => 'Smart Helmet - Home',
      1 => 'Health Monitoring',
      2 => 'Stress Detection',
      3 => 'Post Journey',
      4 => 'Danger Zone Detection',
      _ => 'Smart Helmet',
    };
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context, listen: false);

    return Scaffold(
      appBar: AppBar(
        title: Text(_getTitle(_index)),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
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
            // Professional Drawer Header
            DrawerHeader(
              decoration: const BoxDecoration(
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
                    backgroundImage:
                        const AssetImage('assets/icons/app_icon.png'),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Smart Helmet',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text(
                    'Ride Safe, Ride Smart',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),

            // Main Navigation
            ...[0, 1, 2, 3, 4].map((i) {
              final titles = [
                'Home',
                'Health Monitoring',
                'Stress Detection',
                'Post Journey',
                'Danger Zone Detection'
              ];
              final icons = [
                Icons.home,
                Icons.favorite,
                Icons.psychology,
                Icons.history,
                Icons.warning_amber
              ];

              return ListTile(
                leading: Icon(icons[i]),
                title: Text(titles[i]),
                selected: _index == i,
                selectedTileColor: Colors.indigo.withOpacity(0.1),
                onTap: () {
                  setState(() => _index = i);
                  Navigator.pop(context);
                },
              );
            }).toList(),

            const Divider(),

            // Additional Links
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('About Us'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                    context, MaterialPageRoute(builder: (_) => AboutUsPage()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('Privacy Policy'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => PrivacyPolicyPage()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Terms of Service'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => TermsOfServicePage()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.support_agent),
              title: const Text('Contact Support'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => ContactSupportPage()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.star_rate),
              title: const Text('Rate App'),
              onTap: () {
                Navigator.pop(context);
                _launchURL(
                    'https://play.google.com/store/apps/details?id=com.yourpackage'); // Update with real ID
              },
            ),

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
      body: IndexedStack(
        index: _index,
        children: _pages,
      ), // Better than direct indexing for preserving state
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (value) => setState(() => _index = value),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.indigo,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.favorite), label: 'Health'),
          BottomNavigationBarItem(
              icon: Icon(Icons.psychology), label: 'Stress'),
          BottomNavigationBarItem(
              icon: Icon(Icons.history), label: 'Post Journey'),
          BottomNavigationBarItem(
              icon: Icon(Icons.warning), label: 'Danger Zone'),
        ],
      ),
    );
  }
}
