import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';

// import the member pages
import 'members/Health_Monitoring/member1_page.dart';
import 'members/Stress_Detection/member2_page.dart';
import 'members/Post_Journey/member3_page.dart';
import 'members/Danger_Zone/member4_page.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;
  final List<Widget> _pages = const [
    Member1Page(),
    Member2Page(),
    Member3Page(),
    Member4Page(),
  ];

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context, listen: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Helmet — Team'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async => await auth.signOut(),
            tooltip: 'Sign out',
          )
        ],
      ),
      body: _pages[_index],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (v) => setState(() => _index = v),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Member 1'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Member 2'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Member 3'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Member 4'),
        ],
      ),
    );
  }
}
