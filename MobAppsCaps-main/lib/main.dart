import 'package:flutter/material.dart';
import 'package:my_app/pages/HomePage.dart';
import 'package:my_app/pages/SplashScreen.dart';
import 'package:my_app/pages/login_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final hasStoredToken =
      (prefs.getString('authToken')?.trim().isNotEmpty ?? false) ||
      (prefs.getString('accessToken')?.trim().isNotEmpty ?? false);
  final bool isLoggedIn = prefs.getBool('isLoggedIn') ?? hasStoredToken;

  runApp(MyApp(isLoggedIn: isLoggedIn));
}

class MyApp extends StatelessWidget {
  final bool isLoggedIn;

  const MyApp({super.key, required this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Login UI',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: SplashScreen(
        isLoggedIn: isLoggedIn,
        loggedInDestination: const HomePage(),
        loggedOutDestination: const LoginPage(),
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}
