import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';

// import the member pages
import 'members/Health_Monitoring/member1_page.dart';
import 'members/Stress_Detection/member2_page.dart';
import 'members/Post_Journey/member3_page.dart';
import 'members/Danger_Zone/member4_page.dart';
import 'home_dashboard.dart'; // The new home dashboard page with journey planning

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;
  final List<Widget> _pages = const [
    HomeDashboard(), // New home dashboard as the first page
    Member1Page(),
    Member2Page(),
    Member3Page(),
    Member4Page(),
  ];

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context, listen: false);

    String title = _index == 0 ? 'Smart Helmet - Home' : 'Smart Helmet — Team';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async => await auth.signOut(),
            tooltip: 'Sign out',
          ),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: <Widget>[
            const DrawerHeader(
              decoration: BoxDecoration(color: Colors.indigo),
              child: Text(
                'Menu',
                style: TextStyle(color: Colors.white, fontSize: 24),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.home),
              title: const Text('Home'),
              onTap: () {
                setState(() => _index = 0);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.person),
              title: const Text('Member 1'),
              onTap: () {
                setState(() => _index = 1);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.person),
              title: const Text('Member 2'),
              onTap: () {
                setState(() => _index = 2);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.person),
              title: const Text('Member 3'),
              onTap: () {
                setState(() => _index = 3);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.person),
              title: const Text('Member 4'),
              onTap: () {
                setState(() => _index = 4);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
      body: _pages[_index],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (v) => setState(() => _index = v),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Member 1'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Member 2'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Member 3'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Member 4'),
        ],
      ),
    );
  }
}
