import 'package:flutter/material.dart';
import 'package:bitsonwheelsv1/services/auth_service.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  final _authService = AuthService();

  /*bool _isBitsEmail(String email) {
    return email.toLowerCase().endsWith('@pilani.bits-pilani.ac.in');
  }*/

  Future<void> _signup() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (name.isEmpty || email.isEmpty || password.length < 6) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter valid details (password >= 6 chars)')),
        );
      }
      return;
    }
    /*if (!_isBitsEmail(email)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please use your BITS Pilani email')),
        );
      }
      return;
    }*/

    setState(() => _loading = true);
    try {
      await _authService.signUpWithEmail(name: name, email: email, password: password);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Signup successful — verification email sent')),
        );
      }
      Navigator.pushReplacementNamed(context, '/verify');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Signup error: $e')),
        );
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign up')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'Full name')),
            const SizedBox(height: 8),
            TextField(controller: _emailController, decoration: const InputDecoration(labelText: 'BITS Email')),
            const SizedBox(height: 8),
            TextField(controller: _passwordController, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loading ? null : _signup, child: _loading ? const CircularProgressIndicator() : const Text('Sign up')),
            const SizedBox(height: 8),
            TextButton(onPressed: () => Navigator.pushNamed(context, '/login'), child: const Text('Already have an account? Login')),
          ],
        ),
      ),
    );
  }
}