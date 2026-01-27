import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'firebase_options.dart';
import 'repositories/auth_repository.dart';
import 'screens/dashboard_screen.dart';
import 'screens/login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  if (kIsWeb) {
    await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
  }
  runApp(const VacacionesApp());
}

class VacacionesApp extends StatelessWidget {
  const VacacionesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'APP Vacaciones',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.teal,
        scaffoldBackgroundColor: const Color(0xFFF5F5F5),
      ),
      locale: const Locale('es', 'ES'),
      supportedLocales: const [
        Locale('es', 'ES'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _AuthLoading();
        }

        final user = snapshot.data;
        if (user == null) {
          return const LoginScreen();
        }

        return FutureBuilder(
          future: AuthRepository.fetchProfile(user),
          builder: (context, profileSnapshot) {
            if (profileSnapshot.connectionState == ConnectionState.waiting) {
              return const _AuthLoading();
            }

            if (profileSnapshot.hasError) {
              return _AuthError(message: profileSnapshot.error.toString());
            }

            final profile = profileSnapshot.data;
            if (profile == null) {
              return const _AuthError(message: 'Perfil no disponible');
            }

            return DashboardScreen(profile: profile);
          },
        );
      },
    );
  }
}

class _AuthLoading extends StatelessWidget {
  const _AuthLoading();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}

class _AuthError extends StatelessWidget {
  final String message;

  const _AuthError({required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              const Text(
                'No se pudo validar el acceso.',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () async {
                  await FirebaseAuth.instance.signOut();
                },
                child: const Text('Volver a iniciar sesion'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
