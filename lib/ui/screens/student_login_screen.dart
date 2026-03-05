import 'package:flutter/material.dart';
import 'student_dashboard_screen.dart';

class StudentLoginScreen extends StatefulWidget {
  const StudentLoginScreen({Key? key}) : super(key: key);
  @override
  State<StudentLoginScreen> createState() => _StudentLoginScreenState();
}

class _StudentLoginScreenState extends State<StudentLoginScreen> {
  final _nameController = TextEditingController();

  void _search() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => StudentDashboardScreen(studentName: name)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("ACCESS TERMINAL"), elevation: 0),
      body: Padding(
        padding: const EdgeInsets.all(30.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.analytics_outlined, size: 100, color: Color(0xFF00E676)),
            const SizedBox(height: 30),
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                hintText: "Enter Registered Name",
                prefixIcon: const Icon(Icons.person, color: Color(0xFF00E676)),
                filled: true,
                fillColor: Colors.white10,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: _search,
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E676)),
                child: const Text("VIEW ANALYTICS", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}