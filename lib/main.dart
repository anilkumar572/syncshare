import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:sharesyncapp/firebase_options.dart';
import 'package:sharesyncapp/screens/transfer_screen.dart';
import 'servises/background_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // await BackgroundHandler.initializeService();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(home: TransferScreen());
}
