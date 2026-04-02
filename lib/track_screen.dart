import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'app_theme.dart';
import 'treadmill_data.dart';

class TrackScreen extends StatefulWidget {
  final ValueNotifier<TreadmillData?> dataNotifier;
  final int baselineDistance;
  final int baselineSeconds;
  final int baselineCalories;
  final int baselineSteps;

  const TrackScreen({
    super.key,
    required this.dataNotifier,
    this.baselineDistance = 0,
    this.baselineSeconds = 0,
    this.baselineCalories = 0,
    this.baselineSteps = 0,
  });

  @override
  State<TrackScreen> createState() => _TrackScreenState();
}

class _TrackScreenState extends State<TrackScreen>
    with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  Duration? _lastTick;

  double _simulatedDistance = 0;
  double _realDistance = 0;
  double _speedMps = 0;
  int _lapDistance = 200;

  @override
  void initState() {
    super.initState();
    final data = widget.dataNotifier.value;
    if (data != null) {
      _simulatedDistance = (data.distanceMeters - widget.baselineDistance).toDouble();
      _realDistance = _simulatedDistance;
      _speedMps = data.speedKmh / 3.6;
    }
    widget.dataNotifier.addListener(_onData);
    _ticker = createTicker(_onTick)..start();
  }

  void _onData() {
    final data = widget.dataNotifier.value;
    if (data == null) {
      _speedMps = 0;
      return;
    }
    _realDistance = (data.distanceMeters - widget.baselineDistance).toDouble();
    _speedMps = data.speedKmh / 3.6;
  }

  void _onTick(Duration elapsed) {
    if (_lastTick == null) {
      _lastTick = elapsed;
      return;
    }
    final dt = (elapsed - _lastTick!).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (_speedMps > 0) {
      _simulatedDistance += _speedMps * dt;
      final drift = _realDistance - _simulatedDistance;
      if (drift.abs() > 2.0) _simulatedDistance += drift * 0.1;
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    widget.dataNotifier.removeListener(_onData);
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final laps = _simulatedDistance ~/ _lapDistance;
    final metersInLap = _simulatedDistance % _lapDistance;
    final lapProgress = metersInLap / _lapDistance;
    final data = widget.dataNotifier.value;

    return Scaffold(
      appBar: AppBar(title: const Text('Pista')),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Column(
          children: [
            // Header compacto: vuelta + progreso + selector
            _TrackHeader(
              laps: laps,
              metersInLap: metersInLap,
              lapDistance: _lapDistance,
              onLapChanged: (v) => setState(() => _lapDistance = v),
            ),
            const SizedBox(height: 12),

            // Pista — elemento principal
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 1.8,
                  child: CustomPaint(
                    painter: _TrackPainter(progress: lapProgress),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Métricas — 2 filas con valores de sesión (delta)
            if (data != null) _MetricsCard(
              speedKmh: data.speedKmh,
              elapsedSeconds: data.elapsedSeconds - widget.baselineSeconds,
              distanceMeters: data.distanceMeters - widget.baselineDistance,
              calories: data.totalEnergyKcal - widget.baselineCalories,
              steps: data.steps - widget.baselineSteps,
            ),

            SafeArea(top: false, child: const SizedBox(height: 12)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header: vuelta + barra de progreso + selector de distancia
// ---------------------------------------------------------------------------

class _TrackHeader extends StatelessWidget {
  final int laps;
  final double metersInLap;
  final int lapDistance;
  final ValueChanged<int> onLapChanged;

  const _TrackHeader({
    required this.laps,
    required this.metersInLap,
    required this.lapDistance,
    required this.onLapChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: KScanColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: KScanColors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Contador de vuelta
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'VUELTA',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: KScanColors.muted,
                  letterSpacing: 1.2,
                ),
              ),
              Text(
                '$laps',
                style: const TextStyle(
                  fontSize: 44,
                  fontWeight: FontWeight.w800,
                  color: KScanColors.ink,
                  letterSpacing: -1,
                  height: 1,
                ),
              ),
            ],
          ),
          const SizedBox(width: 18),
          // Progreso + selector
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${metersInLap.toStringAsFixed(0)} m',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: KScanColors.ink,
                      ),
                    ),
                    Text(
                      '$lapDistance m',
                      style: const TextStyle(
                        fontSize: 12,
                        color: KScanColors.muted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: metersInLap / lapDistance,
                    minHeight: 8,
                  ),
                ),
                const SizedBox(height: 10),
                // Selector compacto
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 100, label: Text('100 m')),
                    ButtonSegment(value: 200, label: Text('200 m')),
                    ButtonSegment(value: 400, label: Text('400 m')),
                  ],
                  selected: {lapDistance},
                  onSelectionChanged: (s) => onLapChanged(s.first),
                  style: const ButtonStyle(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Métricas — 2 filas (3 + 2 centradas)
// ---------------------------------------------------------------------------

class _MetricsCard extends StatelessWidget {
  final double speedKmh;
  final int elapsedSeconds;
  final int distanceMeters;
  final int calories;
  final int steps;

  const _MetricsCard({
    required this.speedKmh,
    required this.elapsedSeconds,
    required this.distanceMeters,
    required this.calories,
    required this.steps,
  });

  String get _elapsedFormatted {
    final m = elapsedSeconds ~/ 60;
    final s = elapsedSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: KScanColors.surfaceDark,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          // Fila 1: velocidad, tiempo, distancia
          Row(
            children: [
              Expanded(
                child: _Metric(
                  icon: Icons.speed,
                  value: speedKmh.toStringAsFixed(1),
                  unit: 'km/h',
                ),
              ),
              _Divider(),
              Expanded(
                child: _Metric(
                  icon: Icons.timer,
                  value: _elapsedFormatted,
                  unit: 'tiempo',
                ),
              ),
              _Divider(),
              Expanded(
                child: _Metric(
                  icon: Icons.straighten,
                  value: '$distanceMeters',
                  unit: 'metros',
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Divider(color: Colors.white.withOpacity(0.08), height: 1),
          ),
          // Fila 2: calorías, pasos
          Row(
            children: [
              Expanded(
                child: _Metric(
                  icon: Icons.local_fire_department,
                  value: '$calories',
                  unit: 'kcal',
                ),
              ),
              _Divider(),
              Expanded(
                child: _Metric(
                  icon: Icons.directions_walk,
                  value: '$steps',
                  unit: 'pasos/min',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 40,
      color: Colors.white.withOpacity(0.08),
    );
  }
}

class _Metric extends StatelessWidget {
  final IconData icon;
  final String value;
  final String unit;

  const _Metric({required this.icon, required this.value, required this.unit});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: KScanColors.accent),
        const SizedBox(height: 5),
        Text(
          value,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: KScanColors.background,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          unit,
          style: const TextStyle(fontSize: 11, color: KScanColors.muted),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// CustomPainter — pista de atletismo
// ---------------------------------------------------------------------------

class _TrackPainter extends CustomPainter {
  final double progress;

  const _TrackPainter({required this.progress});

  static const double _laneWidth = 26.0;
  static const Color _trackColor = Color(0xFFC0392B);
  static const Color _grassColor = Color(0xFF4CAF50);

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 4.0;
    final outerRect =
        Rect.fromLTWH(pad, pad, size.width - pad * 2, size.height - pad * 2);
    final outerRadius = outerRect.height / 2;
    final outerRRect =
        RRect.fromRectAndRadius(outerRect, Radius.circular(outerRadius));

    final innerRadius = math.max(0.0, outerRadius - _laneWidth);
    final innerRect = outerRect.deflate(_laneWidth);
    final innerRRect =
        RRect.fromRectAndRadius(innerRect, Radius.circular(innerRadius));

    // 1. Pista roja
    canvas.drawRRect(outerRRect, Paint()..color = _trackColor);

    // 2. Campo verde
    canvas.drawRRect(innerRRect, Paint()..color = _grassColor);

    // 3. Línea central de carril
    final midRadius = math.max(0.0, outerRadius - _laneWidth / 2);
    final midRect = outerRect.deflate(_laneWidth / 2);
    final midRRect =
        RRect.fromRectAndRadius(midRect, Radius.circular(midRadius));
    canvas.drawRRect(
      midRRect,
      Paint()
        ..color = Colors.white.withOpacity(0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    // 4. Bordes blancos
    final borderPaint = Paint()
      ..color = Colors.white.withOpacity(0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(outerRRect, borderPaint);
    canvas.drawRRect(innerRRect, borderPaint);

    // 5. Trail + línea de meta
    final runnerPath = Path()..addRRect(midRRect);
    final metric = runnerPath.computeMetrics().first;

    if (progress > 0) {
      final trailPath =
          metric.extractPath(0, metric.length * progress.clamp(0.0, 1.0));
      canvas.drawPath(
        trailPath,
        Paint()
          ..color = Colors.white.withOpacity(0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5.0
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    final startTangent = metric.getTangentForOffset(0);
    if (startTangent != null) {
      final angle = startTangent.angle + math.pi / 2;
      final dir = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(
        startTangent.position - dir * (_laneWidth / 2 + 2),
        startTangent.position + dir * (_laneWidth / 2 + 2),
        Paint()
          ..color = Colors.white
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round,
      );
    }

    // 6. Runner
    final tangent =
        metric.getTangentForOffset(metric.length * progress.clamp(0.0, 1.0));
    if (tangent != null) _drawRunner(canvas, tangent.position);
  }

  void _drawRunner(Canvas canvas, Offset pos) {
    canvas.drawCircle(
      pos + const Offset(1.5, 1.5),
      9,
      Paint()..color = Colors.black.withOpacity(0.25),
    );
    canvas.drawCircle(pos, 9, Paint()..color = KScanColors.accent);
    canvas.drawCircle(
      pos - const Offset(2.5, 2.5),
      3.5,
      Paint()..color = Colors.white.withOpacity(0.55),
    );
  }

  @override
  bool shouldRepaint(_TrackPainter old) => old.progress != progress;
}
