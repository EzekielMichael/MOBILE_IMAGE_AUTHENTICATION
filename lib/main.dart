import 'package:flutter/material.dart';
import 'api_service.dart';
import 'login_page.dart';
import 'welcome_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Load saved server URL BEFORE the app starts
  await ApiService.loadBaseUrl();
  runApp(const ForensixApp());
}

class ForensixApp extends StatelessWidget {
  const ForensixApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Forensix',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A1428),
        primaryColor: const Color(0xFF00E5CC),
      ),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkLogin();
  }

  Future<void> _checkLogin() async {
    final token = await ApiService.getAccessToken();

    if (token != null) {
      final data = await ApiService.me();
      if (data['success'] == true) {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const WelcomePage()),
        );
        return;
      }
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF0A1428),
      body: Center(
        child: CircularProgressIndicator(color: Color(0xFF00E5CC)),
      ),
    );
  }
}
