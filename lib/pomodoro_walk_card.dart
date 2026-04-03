import 'dart:async';
import 'package:flutter/material.dart';
import 'app_theme.dart';

// ---------------------------------------------------------------------------
// PomodoroWalkCard
// Página 2 del PageView principal. Setup + sesión estilo pomodoro:
// bloques de trabajo/descanso con control automático de velocidad vía BLE.
// ---------------------------------------------------------------------------

enum PomodoroPhase { setup, work, rest, done }

class PomodoroWalkCard extends StatefulWidget {
  final Future<void> Function() onTreadmillStart;
  final Future<void> Function() onTreadmillStop;
  final Future<void> Function(double speed) onSetSpeed;
  final void Function(bool active) onActiveChanged;

  const PomodoroWalkCard({
    super.key,
    required this.onTreadmillStart,
    required this.onTreadmillStop,
    required this.onSetSpeed,
    required this.onActiveChanged,
  });

  @override
  State<PomodoroWalkCard> createState() => _PomodoroWalkCardState();
}

class _PomodoroWalkCardState extends State<PomodoroWalkCard> {
  // --- Config ---
  int _workMinutes = 25;
  int _restMinutes = 5;
  double _workSpeed = 3.5;
  double _restSpeed = 2.0;
  int _totalCycles = 4;

  // --- Runtime ---
  PomodoroPhase _phase = PomodoroPhase.setup;
  int _remainingSeconds = 0;
  int _completedCycles = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // ---- Actions ----

  Future<void> _startPomodoro() async {
    await widget.onTreadmillStart();
    await widget.onSetSpeed(_workSpeed);
    if (!mounted) return;
    setState(() {
      _phase = PomodoroPhase.work;
      _remainingSeconds = _workMinutes * 60;
      _completedCycles = 0;
    });
    widget.onActiveChanged(true);
    _tick();
  }

  void _tick() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_remainingSeconds > 1) {
        setState(() => _remainingSeconds--);
      } else {
        _onPhaseEnd();
      }
    });
  }

  Future<void> _onPhaseEnd() async {
    _timer?.cancel();
    if (_phase == PomodoroPhase.work) {
      final cycles = _completedCycles + 1;
      if (cycles >= _totalCycles) {
        await widget.onTreadmillStop();
        if (!mounted) return;
        setState(() {
          _phase = PomodoroPhase.done;
          _completedCycles = cycles;
        });
        widget.onActiveChanged(false);
      } else {
        await widget.onSetSpeed(_restSpeed);
        if (!mounted) return;
        setState(() {
          _phase = PomodoroPhase.rest;
          _remainingSeconds = _restMinutes * 60;
          _completedCycles = cycles;
        });
        _tick();
      }
    } else if (_phase == PomodoroPhase.rest) {
      await widget.onSetSpeed(_workSpeed);
      if (!mounted) return;
      setState(() {
        _phase = PomodoroPhase.work;
        _remainingSeconds = _workMinutes * 60;
      });
      _tick();
    }
  }

  Future<void> _cancel() async {
    _timer?.cancel();
    await widget.onTreadmillStop();
    if (!mounted) return;
    setState(() {
      _phase = PomodoroPhase.setup;
      _completedCycles = 0;
    });
    widget.onActiveChanged(false);
  }

  // ---- Helpers ----

  String _fmt(int s) {
    final m = s ~/ 60;
    final sec = s % 60;
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  void _setWorkSpeed(double v) {
    setState(() {
      _workSpeed = v.clamp(1.5, 6.0);
      if (_restSpeed >= _workSpeed) {
        _restSpeed = (_workSpeed - 0.5).clamp(1.0, 6.0);
      }
    });
  }

  void _setRestSpeed(double v) {
    setState(() {
      _restSpeed = v.clamp(1.0, _workSpeed - 0.5);
    });
  }

  // ---- Build ----

  @override
  Widget build(BuildContext context) {
    return switch (_phase) {
      PomodoroPhase.setup => _buildSetup(context),
      PomodoroPhase.work || PomodoroPhase.rest => _buildActive(context),
      PomodoroPhase.done => _buildDone(context),
    };
  }

  // --- Setup screen ---

  Widget _buildSetup(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: KScanColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: KScanColors.divider),
      ),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: KScanColors.accentLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(child: Text('🍅', style: TextStyle(fontSize: 16))),
              ),
              const SizedBox(width: 10),
              Text(
                'Pomodoro Walk',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _ConfigRow(
            label: 'Trabajo',
            display: '$_workMinutes min',
            onDecrease: _workMinutes > 5 ? () => setState(() => _workMinutes -= 5) : null,
            onIncrease: _workMinutes < 60 ? () => setState(() => _workMinutes += 5) : null,
          ),
          const SizedBox(height: 10),
          _ConfigRow(
            label: 'Descanso',
            display: '$_restMinutes min',
            onDecrease: _restMinutes > 1 ? () => setState(() => _restMinutes -= 1) : null,
            onIncrease: _restMinutes < 30 ? () => setState(() => _restMinutes += 1) : null,
          ),
          const SizedBox(height: 10),
          _ConfigRow(
            label: 'Vel. trabajo',
            display: '${_workSpeed.toStringAsFixed(1)} km/h',
            onDecrease: _workSpeed > 1.5 ? () => _setWorkSpeed(_workSpeed - 0.5) : null,
            onIncrease: _workSpeed < 6.0 ? () => _setWorkSpeed(_workSpeed + 0.5) : null,
          ),
          const SizedBox(height: 10),
          _ConfigRow(
            label: 'Vel. descanso',
            display: '${_restSpeed.toStringAsFixed(1)} km/h',
            onDecrease: _restSpeed > 1.0 ? () => _setRestSpeed(_restSpeed - 0.5) : null,
            onIncrease: _restSpeed < _workSpeed - 0.5 ? () => _setRestSpeed(_restSpeed + 0.5) : null,
          ),
          const SizedBox(height: 10),
          _ConfigRow(
            label: 'Ciclos',
            display: '$_totalCycles',
            onDecrease: _totalCycles > 1 ? () => setState(() => _totalCycles--) : null,
            onIncrease: _totalCycles < 8 ? () => setState(() => _totalCycles++) : null,
          ),
          const Spacer(),
          FilledButton(
            onPressed: _startPomodoro,
            child: const Text('INICIAR'),
          ),
        ],
      ),
    );
  }

  // --- Active screen (work / rest) ---

  Widget _buildActive(BuildContext context) {
    final isWork = _phase == PomodoroPhase.work;
    final bgColor = isWork ? KScanColors.surfaceDark : KScanColors.accentLight;
    final primaryText = isWork ? KScanColors.background : KScanColors.ink;
    final secondaryText = isWork ? KScanColors.muted : const Color(0xFF888888);
    final accentDot = isWork ? KScanColors.accent : KScanColors.ink;
    final phaseLabel = isWork ? 'TRABAJO' : 'DESCANSO';
    final currentSpeed = isWork ? _workSpeed : _restSpeed;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Phase label + cycle dots
          Row(
            children: [
              Text(
                phaseLabel,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: accentDot,
                  letterSpacing: 1.5,
                ),
              ),
              const Spacer(),
              Row(
                children: List.generate(_totalCycles, (i) {
                  return Container(
                    margin: const EdgeInsets.only(left: 6),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i < _completedCycles
                          ? accentDot
                          : accentDot.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                  );
                }),
              ),
            ],
          ),
          const Spacer(),
          // Countdown
          Center(
            child: Text(
              _fmt(_remainingSeconds),
              style: TextStyle(
                fontSize: 72,
                fontWeight: FontWeight.w800,
                color: primaryText,
                letterSpacing: -3,
                height: 1,
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Speed
          Center(
            child: Text(
              '${currentSpeed.toStringAsFixed(1)} km/h',
              style: TextStyle(
                fontSize: 15,
                color: secondaryText,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const Spacer(),
          // Cancel
          OutlinedButton(
            onPressed: _cancel,
            style: OutlinedButton.styleFrom(
              foregroundColor: primaryText,
              side: BorderSide(color: primaryText.withOpacity(0.3)),
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('CANCELAR'),
          ),
        ],
      ),
    );
  }

  // --- Done screen ---

  Widget _buildDone(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: KScanColors.surfaceDark,
        borderRadius: BorderRadius.all(Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Center(child: Text('🍅', style: TextStyle(fontSize: 48))),
          const SizedBox(height: 16),
          Text(
            '$_completedCycles pomodoros',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: KScanColors.background,
              height: 1,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Sesión completada',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: KScanColors.muted),
          ),
          const Spacer(),
          FilledButton(
            onPressed: () => setState(() => _phase = PomodoroPhase.setup),
            child: const Text('NUEVA SESIÓN'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _ConfigRow — label + valor + botones -/+
// ---------------------------------------------------------------------------

class _ConfigRow extends StatelessWidget {
  final String label;
  final String display;
  final VoidCallback? onDecrease;
  final VoidCallback? onIncrease;

  const _ConfigRow({
    required this.label,
    required this.display,
    this.onDecrease,
    this.onIncrease,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: KScanColors.ink,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        _StepButton(icon: Icons.remove, onTap: onDecrease),
        SizedBox(
          width: 80,
          child: Text(
            display,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: KScanColors.ink,
            ),
          ),
        ),
        _StepButton(icon: Icons.add, onTap: onIncrease),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _StepButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: enabled ? KScanColors.ink : KScanColors.divider,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          size: 16,
          color: enabled ? KScanColors.surface : KScanColors.muted,
        ),
      ),
    );
  }
}
