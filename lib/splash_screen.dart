import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
// 1. Import your actual map screen file here
import 'screens/user_map_screen.dart'; 

class MySitySplashScreen extends StatefulWidget {
  const MySitySplashScreen({super.key});

  @override
  State<MySitySplashScreen> createState() => _MySitySplashScreenState();
}

class _MySitySplashScreenState extends State<MySitySplashScreen> {
  
  @override
  void initState() {
    super.initState();
    _navigateToHome();
  }

  // 2. Added type annotation 'Future<void>' to fix "Missing type annotation"
  Future<void> _navigateToHome() async {
    // Wait for 3 seconds for the animation to play
    await Future.delayed(const Duration(milliseconds: 3000)); 
    
    if (mounted) {
      // 3. Changed 'MapHomePage' to 'UserMapScreen' (or whatever your class name is)
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const UserMapScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Lottie.asset(
          'assets/animations/map_pulse.json', 
          width: 250,
          repeat: true,
          // 4. Handle error if file is missing to avoid a crash
          errorBuilder: (context, error, stackTrace) {
            return const Icon(Icons.map, size: 100, color: Colors.green);
          },
        ),
      ),
    );
  }
}