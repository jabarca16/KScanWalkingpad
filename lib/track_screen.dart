import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'app_theme.dart';
import 'treadmill_data.dart';

class TrackScreen extends StatefulWidget {
  final ValueNotifier<TreadmillData?> dataNotifier;

  const TrackScreen({super.key, required this.dataNotifier});

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
      _simulatedDistance = data.distanceMeters.toDouble();
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
    _realDistance = data.distanceMeters.toDouble();
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
      // Corrección suave si se acumula drift respecto al dato real
      final drift = _realDistance - _simulatedDistance;
      if (drift.abs() > 2.0) {
        _simulatedDistance += drift * 0.1;
      }
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
      appBar: AppBar(
        title: const Text('Pista'),
      ),
      body: Column(
        children: [
          _LapHeader(
            laps: laps,
            metersInLap: metersInLap,
            lapDistance: _lapDistance,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 100, label: Text('100 m')),
                ButtonSegment(value: 200, label: Text('200 m')),
                ButtonSegment(value: 400, label: Text('400 m')),
              ],
              selected: {_lapDistance},
              onSelectionChanged: (s) => setState(() => _lapDistance = s.first),
              style: const ButtonStyle(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 1.8,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 8),
                  child: CustomPaint(
                    painter: _TrackPainter(progress: lapProgress),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
          if (data != null) _MetricsBar(data: data),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Encabezado con vuelta actual y barra de progreso
// ---------------------------------------------------------------------------

class _LapHeader extends StatelessWidget {
  final int laps;
  final double metersInLap;
  final int lapDistance;

  const _LapHeader({
    required this.laps,
    required this.metersInLap,
    required this.lapDistance,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Vuelta',
                style: TextStyle(
                  fontSize: 12,
                  color: KScanColors.muted,
                ),
              ),
              Text(
                '$laps',
                style: const TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.w800,
                  color: KScanColors.ink,
                  letterSpacing: -1,
                ),
              ),
            ],
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${metersInLap.toStringAsFixed(0)} / $lapDistance m',
                  style: const TextStyle(
                    fontSize: 12,
                    color: KScanColors.muted,
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: metersInLap / lapDistance,
                    minHeight: 10,
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
// Barra de métricas
// ---------------------------------------------------------------------------

class _MetricsBar extends StatelessWidget {
  final TreadmillData data;

  const _MetricsBar({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: KScanColors.surfaceDark,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _Metric(
            icon: Icons.speed,
            value: data.speedKmh.toStringAsFixed(1),
            unit: 'km/h',
          ),
          _Metric(
            icon: Icons.timer,
            value: data.elapsedFormatted,
            unit: 'tiempo',
          ),
          _Metric(
            icon: Icons.straighten,
            value: '${data.distanceMeters}',
            unit: 'metros',
          ),
          _Metric(
            icon: Icons.local_fire_department,
            value: '${data.totalEnergyKcal}',
            unit: 'kcal',
          ),
          _Metric(
            icon: Icons.directions_walk,
            value: '${data.steps}',
            unit: 'pasos/min',
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final IconData icon;
  final String value;
  final String unit;

  const _Metric(
      {required this.icon, required this.value, required this.unit});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: KScanColors.accent),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: KScanColors.background,
          ),
        ),
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
  final double progress; // 0.0 a 1.0

  const _TrackPainter({required this.progress});

  static const double _laneWidth = 26.0;
  static const Color _trackColor = Color(0xFFC0392B);
  static const Color _grassColor = Color(0xFF4CAF50);
  static const Color _grassDark = Color(0xFF388E3C);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Óvalo exterior: ocupa todo el canvas con pequeño padding
    const pad = 4.0;
    final outerRect =
        Rect.fromLTWH(pad, pad, size.width - pad * 2, size.height - pad * 2);
    final outerRadius = outerRect.height / 2;
    final outerRRect =
        RRect.fromRectAndRadius(outerRect, Radius.circular(outerRadius));

    // Óvalo interior (campo)
    final innerRadius = math.max(0.0, outerRadius - _laneWidth);
    final innerRect = outerRect.deflate(_laneWidth);
    final innerRRect =
        RRect.fromRectAndRadius(innerRect, Radius.circular(innerRadius));

    // 1. Superficie de la pista (rojo atletismo)
    canvas.drawRRect(outerRRect, Paint()..color = _trackColor);

    // 2. Campo interior (verde)
    canvas.drawRRect(innerRRect, Paint()..color = _grassColor);

    // 3. Línea de carril central
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

    // Trail: sub-path desde 0 hasta la posición actual
    if (progress > 0) {
      final trailPath = metric.extractPath(0, metric.length * progress.clamp(0.0, 1.0));
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

    // 6. Marcador del corredor
    final tangent =
        metric.getTangentForOffset(metric.length * progress.clamp(0.0, 1.0));
    if (tangent != null) {
      _drawRunner(canvas, tangent.position);
    }
  }

  void _drawRunner(Canvas canvas, Offset pos) {
    // Sombra
    canvas.drawCircle(
      pos + const Offset(1.5, 1.5),
      9,
      Paint()..color = Colors.black.withOpacity(0.25),
    );
    // Círculo principal
    canvas.drawCircle(pos, 9, Paint()..color = KScanColors.accent);
    // Highlight
    canvas.drawCircle(
      pos - const Offset(2.5, 2.5),
      3.5,
      Paint()..color = Colors.white.withOpacity(0.55),
    );
  }

  @override
  bool shouldRepaint(_TrackPainter old) => old.progress != progress;
}
