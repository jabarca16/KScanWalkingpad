import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'session.dart';

// ---------------------------------------------------------------------------
// SpeedChartCard
// Muestra la curva de velocidad de la sesión activa en tiempo real.
// También se usa en el historial para revisar sesiones pasadas.
// ---------------------------------------------------------------------------
class SpeedChartCard extends StatelessWidget {
  final List<SpeedSample> samples;
  final double? currentSpeed; // null = modo historial
  final int? elapsedSeconds;
  final int? distanceMeters;
  final int? calories;
  final int? steps;

  const SpeedChartCard({
    super.key,
    required this.samples,
    this.currentSpeed,
    this.elapsedSeconds,
    this.distanceMeters,
    this.calories,
    this.steps,
  });

  bool get _isLive => currentSpeed != null;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: KScanColors.surfaceDark,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(isLive: _isLive, currentSpeed: currentSpeed),
          const SizedBox(height: 16),
          Expanded(child: _Chart(samples: samples)),
          const SizedBox(height: 16),
          _MetricsRow(
            elapsedSeconds: elapsedSeconds,
            distanceMeters: distanceMeters,
            calories: calories,
            steps: steps,
            avgSpeed: _avgSpeed,
            maxSpeed: _maxSpeed,
          ),
        ],
      ),
    );
  }

  double get _avgSpeed {
    if (samples.isEmpty) return 0;
    final moving = samples.where((s) => s.v > 0).toList();
    if (moving.isEmpty) return 0;
    return moving.map((s) => s.v).reduce((a, b) => a + b) / moving.length;
  }

  double get _maxSpeed {
    if (samples.isEmpty) return 0;
    return samples.map((s) => s.v).reduce((a, b) => a > b ? a : b);
  }
}

// ---------------------------------------------------------------------------
// Header — velocidad actual grande
// ---------------------------------------------------------------------------
class _Header extends StatelessWidget {
  final bool isLive;
  final double? currentSpeed;

  const _Header({required this.isLive, required this.currentSpeed});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          currentSpeed != null
              ? currentSpeed!.toStringAsFixed(1)
              : '—',
          style: const TextStyle(
            fontSize: 52,
            fontWeight: FontWeight.w800,
            color: KScanColors.background,
            letterSpacing: -2,
            height: 1,
          ),
        ),
        const SizedBox(width: 6),
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text(
            'km/h',
            style: TextStyle(
              fontSize: 16,
              color: KScanColors.muted,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const Spacer(),
        if (isLive)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: KScanColors.accent.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: KScanColors.accent.withOpacity(0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: KScanColors.accent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                const Text(
                  'EN VIVO',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: KScanColors.accent,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Chart — gráfica de velocidad con fl_chart
// ---------------------------------------------------------------------------
class _Chart extends StatelessWidget {
  final List<SpeedSample> samples;

  const _Chart({required this.samples});

  @override
  Widget build(BuildContext context) {
    if (samples.isEmpty) {
      return const Center(
        child: Text(
          'Iniciá la sesión para ver la telemetría',
          style: TextStyle(color: KScanColors.muted, fontSize: 13),
        ),
      );
    }

    final spots = samples
        .map((s) => FlSpot(s.t.toDouble(), s.v))
        .toList();

    final maxY = (samples.map((s) => s.v).reduce((a, b) => a > b ? a : b) + 1)
        .clamp(4.0, 8.0);

    return LineChart(
      LineChartData(
        minX: spots.first.x,
        maxX: spots.last.x,
        minY: 0,
        maxY: maxY,
        clipData: const FlClipData.all(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 2,
          getDrawingHorizontalLine: (_) => FlLine(
            color: Colors.white.withOpacity(0.07),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: 2,
              getTitlesWidget: (value, _) => Text(
                value.toInt().toString(),
                style: const TextStyle(
                  color: KScanColors.muted,
                  fontSize: 10,
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 20,
              interval: _xInterval(spots),
              getTitlesWidget: (value, _) => Text(
                _fmtSeconds(value.toInt()),
                style: const TextStyle(
                  color: KScanColors.muted,
                  fontSize: 10,
                ),
              ),
            ),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => KScanColors.ink,
            getTooltipItems: (spots) => spots
                .map((s) => LineTooltipItem(
                      '${s.y.toStringAsFixed(1)} km/h',
                      const TextStyle(
                        color: KScanColors.accent,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ))
                .toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.35,
            color: KScanColors.accent,
            barWidth: 2.5,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  KScanColors.accent.withOpacity(0.25),
                  KScanColors.accent.withOpacity(0.0),
                ],
              ),
            ),
          ),
        ],
      ),
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
    );
  }

  double _xInterval(List<FlSpot> spots) {
    if (spots.isEmpty) return 60;
    final range = spots.last.x - spots.first.x;
    if (range <= 120) return 30;
    if (range <= 600) return 120;
    return 300;
  }

  String _fmtSeconds(int s) {
    final m = s ~/ 60;
    final sec = s % 60;
    return '$m:${sec.toString().padLeft(2, '0')}';
  }
}

// ---------------------------------------------------------------------------
// MetricsRow — fila de métricas debajo del gráfico
// ---------------------------------------------------------------------------
class _MetricsRow extends StatelessWidget {
  final int? elapsedSeconds;
  final int? distanceMeters;
  final int? calories;
  final int? steps;
  final double avgSpeed;
  final double maxSpeed;

  const _MetricsRow({
    required this.elapsedSeconds,
    required this.distanceMeters,
    required this.calories,
    required this.steps,
    required this.avgSpeed,
    required this.maxSpeed,
  });

  @override
  Widget build(BuildContext context) {
    String fmtTime(int? s) {
      if (s == null) return '—';
      return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _Metric(icon: Icons.timer, value: fmtTime(elapsedSeconds), label: 'tiempo'),
        _Metric(
          icon: Icons.straighten,
          value: distanceMeters != null ? '${distanceMeters}m' : '—',
          label: 'distancia',
        ),
        _Metric(
          icon: Icons.local_fire_department,
          value: calories != null ? '${calories}kcal' : '—',
          label: 'calorías',
        ),
        _Metric(
          icon: Icons.speed,
          value: avgSpeed > 0 ? avgSpeed.toStringAsFixed(1) : '—',
          label: 'prom km/h',
        ),
        _Metric(
          icon: Icons.directions_walk,
          value: steps != null ? '$steps' : '—',
          label: 'pasos/min',
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _Metric({required this.icon, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: KScanColors.accent),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: KScanColors.background,
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: KScanColors.muted),
        ),
      ],
    );
  }
}
