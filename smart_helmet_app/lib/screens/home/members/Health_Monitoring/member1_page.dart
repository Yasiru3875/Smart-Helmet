import 'package:flutter/material.dart';

class Member1Page extends StatelessWidget {
  const Member1Page({super.key});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Text('Member 1', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text('Place UI for Member 1 here. Live data panels, graphs, controls etc.'),
          ],
        ),
      ),
    );
  }
}
