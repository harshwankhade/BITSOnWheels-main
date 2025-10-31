import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:bitsonwheelsv1/services/auth_service.dart';
import 'package:bitsonwheelsv1/screens/add_bike_screen.dart'; // import Add Bike screen

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('BITSOnWheels'),
        actions: [
          // Add Bike icon on AppBar
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
            Text(
              'Welcome, ${user?.email ?? 'User'}',
              style: const TextStyle(fontSize: 18),
            ),

            // ✅ Two Buttons Side by Side
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Add Bicycle Button
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pushNamed(context, AddBikeScreen.routeName);
                      },
                      icon: const Icon(Icons.add_circle_outline),
                      label: const Text('Add Bicycle'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        textStyle: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                ),

                // Book Bicycle Button (placeholder for now)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: ElevatedButton.icon(
                      onPressed: () {
                        // TODO: Replace '/book_bike' with actual route once you create booking screen
                        Navigator.pushNamed(context, '/book_bike');
                      },
                      icon: const Icon(Icons.directions_bike_outlined),
                      label: const Text('Book Bicycle'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        textStyle: const TextStyle(fontSize: 16),
                        backgroundColor: Colors.green,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
