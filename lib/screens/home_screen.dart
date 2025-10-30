import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:bitsonwheelsv1/services/auth_service.dart';
import 'package:bitsonwheelsv1/screens/add_bike_screen.dart'; //  import Add Bike screen

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('BITSOnWheels'),
        actions: [
          // ✅ Add bike action in AppBar
          IconButton(
            onPressed: () {
              Navigator.pushNamed(context, AddBikeScreen.routeName);
            },
            icon: const Icon(Icons.pedal_bike_outlined),
            tooltip: 'Add Bike',
          ),
          // Logout button
          IconButton(
            onPressed: () async {
              await AuthService().signOut();
              Navigator.pushReplacementNamed(context, '/login');
            },
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Welcome, ${user?.email ?? 'User'}'),
            const SizedBox(height: 12),
            const Text('Phase 1 complete — Autdddhentication working!'),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pushNamed(context, AddBikeScreen.routeName);
              },
              icon: const Icon(Icons.add),
              label: const Text('Add Bike'),
            ),
          ],
        ),
      ),
      // ✅ Floating Action Button to Add Bike
      floatingActionButton: FloatingActionButton.extended(
          backgroundColor: Colors.blueAccent,
          foregroundColor: Colors.white,
        onPressed: () {
          Navigator.pushNamed(context, AddBikeScreen.routeName);
        },
        label: const Text('Add Bike'),
        icon: const Icon(Icons.add),
      ),
    );
  }
}
