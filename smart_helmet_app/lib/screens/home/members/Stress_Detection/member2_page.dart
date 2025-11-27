import 'package:flutter/material.dart';

class Member2Page extends StatelessWidget {
  const Member2Page({super.key});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Text('Member 2', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text('Place UI for Member 2 here. Live data panels, graphs, controls etc.'),
          ],
        ),
      ),
    );
  }
}
