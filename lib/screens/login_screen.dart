import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  String? _errorText;
  bool _loading = false;

  Future<void> _login() async {
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _errorText = 'Introduce email y contrasena');
      return;
    }

    setState(() {
      _errorText = null;
      _loading = true;
    });

    try {
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (credential.user == null) {
        throw Exception('No se pudo iniciar sesion');
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        _errorText = e.message ?? 'Error de autenticacion';
      });
    } catch (e) {
      setState(() {
        _errorText = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Acceso')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'APP Vacaciones',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _emailController,
              decoration: InputDecoration(
                labelText: 'Email',
                errorText: _errorText,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.email),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(
                labelText: 'Contrasena',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock),
              ),
              obscureText: true,
              onSubmitted: (_) => _login(),
            ),
            const SizedBox(height: 25),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _loading ? null : _login,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12.0),
                  child: Text('Entrar'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
