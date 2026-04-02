import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class WorkoutSession {
  final String id;
  final DateTime startedAt;
  final DateTime endedAt;
  final int distanceMeters;
  final int calories;
  final int durationSeconds;

  const WorkoutSession({
    required this.id,
    required this.startedAt,
    required this.endedAt,
    required this.distanceMeters,
    required this.calories,
    required this.durationSeconds,
  });

  String get durationFormatted {
    final m = durationSeconds ~/ 60;
    final s = durationSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'startedAt': startedAt.toIso8601String(),
        'endedAt': endedAt.toIso8601String(),
        'distanceMeters': distanceMeters,
        'calories': calories,
        'durationSeconds': durationSeconds,
      };

  factory WorkoutSession.fromJson(Map<String, dynamic> json) => WorkoutSession(
        id: json['id'] as String,
        startedAt: DateTime.parse(json['startedAt'] as String),
        endedAt: DateTime.parse(json['endedAt'] as String),
        distanceMeters: json['distanceMeters'] as int,
        calories: json['calories'] as int,
        durationSeconds: json['durationSeconds'] as int,
      );
}

class SessionRepository {
  static const _key = 'workout_sessions';
  final SharedPreferences _prefs;

  SessionRepository._(this._prefs);

  static Future<SessionRepository> create() async {
    final prefs = await SharedPreferences.getInstance();
    return SessionRepository._(prefs);
  }

  Future<void> save(WorkoutSession session) async {
    final all = loadAll()..add(session);
    await _prefs.setString(
      _key,
      jsonEncode(all.map((s) => s.toJson()).toList()),
    );
  }

  List<WorkoutSession> loadAll() {
    final raw = _prefs.getString(_key);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => WorkoutSession.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> delete(String id) async {
    final all = loadAll()..removeWhere((s) => s.id == id);
    await _prefs.setString(
      _key,
      jsonEncode(all.map((s) => s.toJson()).toList()),
    );
  }

  List<WorkoutSession> loadToday() {
    final now = DateTime.now();
    return loadAll()
        .where((s) =>
            s.startedAt.year == now.year &&
            s.startedAt.month == now.month &&
            s.startedAt.day == now.day)
        .toList();
  }
}
