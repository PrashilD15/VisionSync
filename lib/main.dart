import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/register_screen.dart';
import 'ui/screens/recognition_screen.dart';
import 'ui/screens/student_login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const VisionSyncApp());
}

class VisionSyncApp extends StatelessWidget {
  const VisionSyncApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VisionSync',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF050510),
        primaryColor: const Color(0xFF00E676),
        fontFamily: 'monospace', // Tech/Biometric aesthetic
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const HomeScreen(),
        '/register': (context) => const RegisterScreen(),
        '/recognize': (context) => const RecognitionScreen(),
        '/analytics': (context) => const StudentLoginScreen(),
      },
    );
  }
}