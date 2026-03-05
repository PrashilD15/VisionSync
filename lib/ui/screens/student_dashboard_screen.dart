import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math';

class StudentDashboardScreen extends StatelessWidget {
  final String studentName;
  const StudentDashboardScreen({Key? key, required this.studentName}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050510),
      appBar: AppBar(
        title: Text("$studentName'S ANALYTICS",
            style: const TextStyle(fontSize: 14, letterSpacing: 2, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('attendance')
            .where('studentName', isEqualTo: studentName)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Color(0xFF00E676)));

          final docs = snapshot.data!.docs;
          if (docs.isEmpty) return _buildEmptyState();

          // Data Processing for Analytics
          Map<int, int> weeklyData = _processWeeklyStats(docs);
          double consistency = (docs.length / 30).clamp(0.0, 1.0) * 100; // Mock target of 30 days

          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSummaryHeader(docs.length, consistency),
                const SizedBox(height: 24),
                const Text("WEEKLY ACTIVITY PATTERN",
                    style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1.5)),
                const SizedBox(height: 16),
                _buildBarChart(weeklyData),
                const SizedBox(height: 32),
                const Text("RECENT LOGS",
                    style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1.5)),
                const SizedBox(height: 16),
                _buildLogsList(docs),
              ],
            ),
          );
        },
      ),
    );
  }

  // --- ANALYTICS LOGIC ---
  Map<int, int> _processWeeklyStats(List<QueryDocumentSnapshot> docs) {
    // Maps Weekday (1-7) to Count
    Map<int, int> stats = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0, 6: 0, 7: 0};
    for (var doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      if (data['timestamp'] != null) {
        DateTime date = (data['timestamp'] as Timestamp).toDate();
        stats[date.weekday] = (stats[date.weekday] ?? 0) + 1;
      }
    }
    return stats;
  }

  // --- UI COMPONENTS ---

  Widget _buildSummaryHeader(int total, double consistency) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF12121F),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF00E676).withOpacity(0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _statItem("TOTAL SESSIONS", total.toString(), Icons.bolt),
          const VerticalDivider(color: Colors.white10, thickness: 1),
          _statItem("CONSISTENCY", "${consistency.toStringAsFixed(0)}%", Icons.insights),
        ],
      ),
    );
  }

  Widget _statItem(String label, String val, IconData icon) {
    return Column(children: [
      Icon(icon, color: const Color(0xFF00E676), size: 18),
      const SizedBox(height: 8),
      Text(val, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white)),
      Text(label, style: const TextStyle(fontSize: 9, color: Colors.white38, letterSpacing: 1)),
    ]);
  }

  Widget _buildBarChart(Map<int, int> data) {
    return Container(
      height: 200,
      padding: const EdgeInsets.fromLTRB(10, 20, 10, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF12121F),
        borderRadius: BorderRadius.circular(24),
      ),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: (data.values.reduce(max).toDouble() + 1),
          barTouchData: BarTouchData(enabled: false),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (val, meta) {
                  const days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
                  return Text(days[val.toInt() - 1], style: const TextStyle(color: Colors.white38, fontSize: 10));
                },
              ),
            ),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barGroups: data.entries.map((e) => BarChartGroupData(
            x: e.key,
            barRods: [
              BarChartRodData(
                toY: e.value.toDouble(),
                color: const Color(0xFF00E676),
                width: 12,
                borderRadius: BorderRadius.circular(4),
                backDrawRodData: BackgroundBarChartRodData(
                  show: true,
                  toY: 10,
                  color: Colors.white.withOpacity(0.05),
                ),
              ),
            ],
          )).toList(),
        ),
      ),
    );
  }

  Widget _buildLogsList(List<QueryDocumentSnapshot> docs) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: docs.length,
      itemBuilder: (context, index) {
        final data = docs[index].data() as Map<String, dynamic>;
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              const CircleAvatar(
                backgroundColor: Color(0xFF00E676),
                radius: 4,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(data['date'] ?? 'N/A', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    Text("${data['department']} | ${data['class']}", style: const TextStyle(color: Colors.white38, fontSize: 11)),
                  ],
                ),
              ),
              const Text("VERIFIED", style: TextStyle(color: Color(0xFF00E676), fontSize: 9, fontWeight: FontWeight.bold)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.analytics_outlined, size: 64, color: Colors.white.withOpacity(0.1)),
          const SizedBox(height: 16),
          const Text("NO DATA FOUND", style: TextStyle(color: Colors.white24, letterSpacing: 2)),
        ],
      ),
    );
  }
}