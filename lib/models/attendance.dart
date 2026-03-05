import 'package:flutter/material.dart';

class Attendance {
  final String studentId;
  final String studentName;
  final DateTime timestamp;
  final String sessionId;

  Attendance({
    required this.studentId,
    required this.studentName,
    required this.timestamp,
    required this.sessionId,
  });

  Map<String, dynamic> toMap() {
    return {
      'studentId': studentId,
      'studentName': studentName,
      'timestamp': timestamp.toIso8601String(),
      'sessionId': sessionId,
    };
  }

  factory Attendance.fromMap(Map<String, dynamic> map) {
    return Attendance(
      studentId: map['studentId'] ?? '',
      studentName: map['studentName'] ?? '',
      timestamp: DateTime.parse(map['timestamp']),
      sessionId: map['sessionId'] ?? '',
    );
  }
}

/// In-memory attendance log for the current session.
/// Replace [log] and [markPresent] with Firestore calls when ready.
class AttendanceService {
  static final AttendanceService _instance = AttendanceService._internal();
  factory AttendanceService() => _instance;
  AttendanceService._internal();

  final List<Attendance> _log = [];

  // Tracks who has already been marked in this session to avoid duplicates
  final Set<String> _markedStudentIds = {};

  String _currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();

  List<Attendance> get log => List.unmodifiable(_log);

  void startNewSession() {
    _currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();
    _markedStudentIds.clear();
  }

  /// Returns true if this is the first time the student is marked in the session.
  bool markPresent(String studentId, String studentName) {
    if (_markedStudentIds.contains(studentId)) return false;

    final record = Attendance(
      studentId: studentId,
      studentName: studentName,
      timestamp: DateTime.now(),
      sessionId: _currentSessionId,
    );

    _log.add(record);
    _markedStudentIds.add(studentId);

    // TODO: Persist to Firebase:
    // FirebaseFirestore.instance.collection('attendance').add(record.toMap());

    return true;
  }

  bool isPresent(String studentId) => _markedStudentIds.contains(studentId);
}

/// A simple screen that lists today's attendance log
class AttendanceLogScreen extends StatelessWidget {
  const AttendanceLogScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final service = AttendanceService();
    final records = service.log;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          "Attendance Log (${records.length})",
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              service.startNewSession();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("New session started")),
              );
            },
            icon: const Icon(Icons.refresh, color: Colors.greenAccent),
            label: const Text("New Session",
                style: TextStyle(color: Colors.greenAccent)),
          )
        ],
      ),
      body: records.isEmpty
          ? const Center(
        child: Text(
          "No attendance recorded yet.\nGo back and scan faces.",
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey, fontSize: 16),
        ),
      )
          : ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: records.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final r = records[index];
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.greenAccent, width: 1),
            ),
            child: Row(
              children: [
                const CircleAvatar(
                  backgroundColor: Colors.greenAccent,
                  child: Icon(Icons.person, color: Colors.black),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.studentName,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16)),
                      Text(
                        _formatTime(r.timestamp),
                        style: const TextStyle(
                            color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.check_circle,
                    color: Colors.greenAccent, size: 20),
              ],
            ),
          );
        },
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return "${dt.day}/${dt.month}/${dt.year} $h:$m:$s";
  }
}