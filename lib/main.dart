import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:sharesyncapp/firebase_options.dart';
import 'package:sharesyncapp/screens/transfer_screen.dart';
import 'package:sharesyncapp/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ShareSync',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: const TransferScreen(),
    );
  }
}
