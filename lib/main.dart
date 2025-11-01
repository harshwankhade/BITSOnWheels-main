import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:bitsonwheelsv1/screens/home_screen.dart';
import 'package:bitsonwheelsv1/screens/login_screen.dart';
import 'package:bitsonwheelsv1/screens/signup_screen.dart';
import 'package:bitsonwheelsv1/screens/verify_email_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'screens/add_bike_screen.dart';
import 'package:bitsonwheelsv1/screens/bike_details_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BITSOnWheels',
      theme: ThemeData(
        primarySwatch: Colors.deepOrange,
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const Root(),
        '/login': (context) => const LoginScreen(),
        '/signup': (context) => const SignupScreen(),
        '/verify': (context) => const VerifyEmailScreen(),
        '/home': (context) => const HomeScreen(),
        '/add_bike': (context) => const AddBikeScreen(),
        BookBikeScreen.routeName: (context) => const BookBikeScreen(),
      },
    );
  }
}

class Root extends StatelessWidget {
  const Root({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final user = snapshot.data;
        if (user == null) {
          return const LoginScreen();
        } else {
          if (!user.emailVerified) return const VerifyEmailScreen();
          return const HomeScreen();
        }
      },
    );
  }
}