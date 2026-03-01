import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'screens/user_map_screen.dart';
import 'dart:developer' as developer; // For better logging

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp();
    developer.log("Firebase Initialized Successfully");
  } catch (e) {
    developer.log("Firebase Initialization Error", error: e);
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MYsity Map',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true, // Fixed the parameter name here
        colorSchemeSeed: Colors.amber,
      ),
      home: const UserMapScreen(),
    );
  }
}