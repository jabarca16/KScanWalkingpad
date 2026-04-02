import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'session.dart';

class HistoryScreen extends StatefulWidget {
  final SessionRepository? repo;

  const HistoryScreen({super.key, required this.repo});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late List<WorkoutSession> _sessions;

  @override
  void initState() {
    super.initState();
    _sessions = widget.repo?.loadAll() ?? [];
    // Más reciente primero
    _sessions.sort((a, b) => b.startedAt.compareTo(a.startedAt));
  }

  // Agrupa las sesiones por día (yyyy-MM-dd)
  Map<String, List<WorkoutSession>> get _grouped {
    final map = <String, List<WorkoutSession>>{};
    for (final session in _sessions) {
      final key =
          '${session.startedAt.year}-${session.startedAt.month.toString().padLeft(2, '0')}-${session.startedAt.day.toString().padLeft(2, '0')}';
      map.putIfAbsent(key, () => []).add(session);
    }
    return map;
  }

  String _dayLabel(String key) {
    final now = DateTime.now();
    final today =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final yKey =
        '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';

    if (key == today) return 'Hoy';
    if (key == yKey) return 'Ayer';
    final parts = key.split('-');
    return '${parts[2]}/${parts[1]}/${parts[0]}';
  }

  @override
  Widget build(BuildContext context) {
    if (_sessions.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Historial'),
        ),
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.directions_walk, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'No hay sesiones registradas todavía.',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    final grouped = _grouped;
    final keys = grouped.keys.toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: keys.length,
        itemBuilder: (context, i) {
          final key = keys[i];
          final daySessions = grouped[key]!;
          final totalDistance =
              daySessions.fold(0, (sum, s) => sum + s.distanceMeters);
          final totalCalories =
              daySessions.fold(0, (sum, s) => sum + s.calories);
          final totalSeconds =
              daySessions.fold(0, (sum, s) => sum + s.durationSeconds);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Encabezado del día
              Padding(
                padding: EdgeInsets.only(bottom: 8, top: i == 0 ? 0 : 16),
                child: Row(
                  children: [
                    Text(
                      _dayLabel(key),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: KScanColors.ink,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '· ${daySessions.length} sesión${daySessions.length > 1 ? 'es' : ''}',
                      style: const TextStyle(
                        color: KScanColors.muted,
                        fontSize: 13,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${totalDistance}m  ·  ${totalCalories}kcal  ·  ${_fmtSeconds(totalSeconds)}',
                      style: const TextStyle(
                        color: KScanColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              // Lista de sesiones del día
              ...daySessions.map((s) => _SessionTile(
                    session: s,
                    onDelete: () => _deleteSession(s.id),
                  )),
            ],
          );
        },
      ),
    );
  }

  Future<void> _deleteSession(String id) async {
    await widget.repo?.delete(id);
    setState(() {
      _sessions.removeWhere((s) => s.id == id);
    });
  }

  String _fmtSeconds(int total) {
    final m = total ~/ 60;
    final s = total % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

class _SessionTile extends StatelessWidget {
  final WorkoutSession session;
  final VoidCallback onDelete;

  const _SessionTile({required this.session, required this.onDelete});

  String _timeRange() {
    String fmt(DateTime dt) =>
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return '${fmt(session.startedAt)} – ${fmt(session.endedAt)}';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: KScanColors.accentLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.directions_walk,
                color: KScanColors.accent,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _timeRange(),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: KScanColors.ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${session.distanceMeters} m  ·  ${session.durationFormatted}  ·  ${session.calories} kcal',
                    style: const TextStyle(
                      fontSize: 12,
                      color: KScanColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 20, color: Colors.grey),
              onSelected: (value) {
                if (value == 'delete') onDelete();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline, size: 18, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Eliminar', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
