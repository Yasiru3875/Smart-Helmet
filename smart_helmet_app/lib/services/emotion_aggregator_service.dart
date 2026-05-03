// lib/services/emotion_aggregator_service.dart
// Aggregates daily stress/mood readings from Firestore into
// emotion_daily_summary documents for the 7-day trend chart.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

class EmotionAggregatorService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Aggregates the last [daysBack] days of stress_mood_readings for [userId]
  /// into the emotion_daily_summary collection.
  ///
  /// Safe to call on every app open — uses merge to avoid overwriting today's
  /// partial data unnecessarily.
  Future<void> aggregateWeek({
    required String userId,
    int daysBack = 7,
  }) async {
    debugPrint('📊 EmotionAggregator: building $daysBack-day summaries...');

    final now = DateTime.now();
    final fmt = DateFormat('yyyy-MM-dd');

    for (int i = 0; i < daysBack; i++) {
      final day = now.subtract(Duration(days: i));
      final dateStr = fmt.format(day);
      final startOfDay = DateTime(day.year, day.month, day.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      try {
        final snapshot = await _firestore
            .collection('stress_mood_readings')
            .where('userId', isEqualTo: userId)
            .where('createdAt',
                isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
            .where('createdAt', isLessThan: Timestamp.fromDate(endOfDay))
            .get();

        if (snapshot.docs.isEmpty) continue;

        // ── Compute aggregates ────────────────────────────────────────────
        double sumStress = 0;
        double sumRelaxed = 0;
        double sumFatigue = 0;
        int sumAttention = 0;
        int sumMeditation = 0;
        final Map<String, int> moodDist = {};
        double peakStress = 0;
        String? peakStressTime;

        for (final doc in snapshot.docs) {
          final d = doc.data();
          final stress = (d['stressScore'] as num?)?.toDouble() ?? 0;
          final relaxed = (d['relaxedScore'] as num?)?.toDouble() ?? 0;
          final fatigue = (d['fatigueScore'] as num?)?.toDouble() ?? 0;
          final attn = (d['attention'] as num?)?.toInt() ?? 0;
          final med = (d['meditation'] as num?)?.toInt() ?? 0;
          final mood = (d['currentMood'] as String?) ?? 'Neutral';

          sumStress += stress;
          sumRelaxed += relaxed;
          sumFatigue += fatigue;
          sumAttention += attn;
          sumMeditation += med;
          moodDist[mood] = (moodDist[mood] ?? 0) + 1;

          if (stress > peakStress) {
            peakStress = stress;
            // Parse timestamp for peak time
            final ts = d['createdAt'];
            if (ts is Timestamp) {
              final dt = ts.toDate();
              peakStressTime =
                  '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
            }
          }
        }

        final count = snapshot.docs.length;
        final avgStress = sumStress / count;
        final avgRelaxed = sumRelaxed / count;
        final avgFatigue = sumFatigue / count;
        final avgAttn = (sumAttention / count).round();
        final avgMed = (sumMeditation / count).round();

        // Dominant mood = most frequent
        final dominantMood = moodDist.entries
            .reduce((a, b) => a.value >= b.value ? a : b)
            .key;

        // Week number
        final weekNum = _isoWeekNumber(day);

        // ── Write summary ─────────────────────────────────────────────────
        final docId = '${userId}_$dateStr';
        await _firestore
            .collection('emotion_daily_summary')
            .doc(docId)
            .set({
          'userId': userId,
          'date': dateStr,
          'avgStressScore': double.parse(avgStress.toStringAsFixed(4)),
          'avgRelaxedScore': double.parse(avgRelaxed.toStringAsFixed(4)),
          'avgFatigueScore': double.parse(avgFatigue.toStringAsFixed(4)),
          'avgAttention': avgAttn,
          'avgMeditation': avgMed,
          'dominantMood': dominantMood,
          'moodDistribution': moodDist,
          'readingCount': count,
          'peakStressScore': double.parse(peakStress.toStringAsFixed(4)),
          'peakStressTime': peakStressTime,
          'weekNumber': weekNum,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        debugPrint('  ✅ $dateStr: $count readings | avgStress=${avgStress.toStringAsFixed(2)} | dominant=$dominantMood');
      } catch (e) {
        debugPrint('  ❌ Error aggregating $dateStr: $e');
      }
    }

    debugPrint('📊 EmotionAggregator: done.');
  }

  /// Fetches the last 7 daily summaries for the given userId, sorted by date.
  Future<List<Map<String, dynamic>>> getLast7Days(String userId) async {
    final now = DateTime.now();
    final fmt = DateFormat('yyyy-MM-dd');
    final List<Map<String, dynamic>> results = [];

    for (int i = 6; i >= 0; i--) {
      final day = now.subtract(Duration(days: i));
      final dateStr = fmt.format(day);
      final docId = '${userId}_$dateStr';

      try {
        final doc = await _firestore
            .collection('emotion_daily_summary')
            .doc(docId)
            .get();

        if (doc.exists) {
          results.add({...doc.data()!, 'date': dateStr});
        } else {
          // No data for this day
          results.add({
            'date': dateStr,
            'avgStressScore': null,
            'dominantMood': null,
            'readingCount': 0,
          });
        }
      } catch (_) {
        results.add({
          'date': dateStr,
          'avgStressScore': null,
          'dominantMood': null,
          'readingCount': 0,
        });
      }
    }

    return results;
  }

  int _isoWeekNumber(DateTime date) {
    final thursday = date.add(Duration(days: 4 - date.weekday));
    final firstThursday = DateTime(thursday.year, 1, 4);
    return 1 +
        ((thursday.difference(firstThursday)).inDays / 7).floor();
  }
}
