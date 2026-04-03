import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'app_theme.dart';
import 'history_screen.dart';
import 'session.dart';
import 'pomodoro_walk_card.dart';
import 'speed_chart_card.dart';
import 'track_screen.dart';
import 'treadmill_data.dart';

const String kFtmsServiceUuid = '1826';
const String kTreadmillDataUuid = '2acd';
const String kControlPointUuid = '2ad9';
const String kDeviceMac = '54:50:A0:10:4D:8A';

const double kSpeedMin = 1.0;
const double kSpeedMax = 6.0;
const double kSpeedStep = 0.1;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort();
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'kscan_service',
      channelName: 'KSCAN — Caminadora',
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,
    ),
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: false,
    ),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.nothing(),
      autoRunOnBoot: false,
      allowWakeLock: true,
      allowWifiLock: true,
    ),
  );
  runApp(const KScanApp());
}

class KScanApp extends StatelessWidget {
  const KScanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KSCAN',
      debugShowCheckedModeBanner: false,
      theme: KScanTheme.theme,
      home: const TreadmillScreen(),
    );
  }
}

// ---------------------------------------------------------------------------
// Estado de la caminadora
// ---------------------------------------------------------------------------

enum TreadmillState { idle, running, paused }

// ---------------------------------------------------------------------------
// Pantalla principal
// ---------------------------------------------------------------------------

class TreadmillScreen extends StatefulWidget {
  const TreadmillScreen({super.key});

  @override
  State<TreadmillScreen> createState() => _TreadmillScreenState();
}

class _TreadmillScreenState extends State<TreadmillScreen> {
  BluetoothDevice? _device;
  List<BluetoothService> _services = [];
  BluetoothCharacteristic? _controlPoint;
  StreamSubscription<List<int>>? _dataSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionStateSub;
  bool _disconnecting = false;
  int _reconnectAttempts = 0;

  TreadmillData? _data;
  TreadmillState _treadmillState = TreadmillState.idle;
  double _targetSpeed = kSpeedMin;

  String _status = 'Presioná Conectar para buscar la K3';
  bool _scanning = false;
  bool _connected = false;

  // Live data notifier (para TrackScreen)
  final _dataNotifier = ValueNotifier<TreadmillData?>(null);

  // Session tracking
  SessionRepository? _repo;
  DateTime? _sessionStart;
  List<WorkoutSession> _todaySessions = [];

  // Telemetría — muestras de velocidad cada 5s
  final List<SpeedSample> _sessionSamples = [];
  Timer? _sampleTimer;
  int _sampleElapsed = 0;

  // Baseline al inicio de cada sesión (la K3 acumula contadores por conexión)
  int _baselineDistance = 0;
  int _baselineSeconds = 0;
  int _baselineCalories = 0;
  int _baselineSteps = 0;

  // PageView controller
  final _pageController = PageController();
  bool _pomodoroActive = false;

  @override
  void initState() {
    super.initState();
    SessionRepository.create().then((repo) {
      _repo = repo;
      setState(() => _todaySessions = repo.loadToday());
    });
  }

  @override
  void dispose() {
    _sampleTimer?.cancel();
    _pageController.dispose();
    _dataNotifier.dispose();
    _connectionStateSub?.cancel();
    _dataSubscription?.cancel();
    _device?.disconnect();
    super.dispose();
  }

  // ---- BLE connection ----

  Future<void> _startScan() async {
    setState(() {
      _scanning = true;
      _connected = false;
      _data = null;
      _treadmillState = TreadmillState.idle;
      _status = 'Conectando a KS-AP-RF3...';
    });
    await _connect(BluetoothDevice.fromId(kDeviceMac));
  }

  Future<void> _connect(BluetoothDevice device) async {
    setState(() => _status = 'Conectando...');
    try {
      await device.connect(license: License.free);
      setState(() {
        _device = device;
        _status = 'Descubriendo servicios...';
      });

      _connectionStateSub?.cancel();
      _connectionStateSub = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected && _connected && !_disconnecting) {
          _handleUnexpectedDisconnect();
        }
      });

      final services = await device.discoverServices();
      setState(() => _services = services);

      for (final service in services) {
        if (service.uuid.toString() == kFtmsServiceUuid) {
          for (final char in service.characteristics) {
            final uuid = char.uuid.toString();

            if (uuid == kTreadmillDataUuid) {
              await char.setNotifyValue(true);
              _dataSubscription = char.lastValueStream.listen((bytes) {
                final parsed = TreadmillData.fromBytes(bytes);
                if (parsed != null && mounted) {
                  setState(() => _data = parsed);
                  _dataNotifier.value = parsed;
                  _updateForegroundNotification();
                }
              });
            }

            if (uuid == kControlPointUuid) {
              _controlPoint = char;
              debugPrint('[KSCAN] Control Point encontrado: $uuid');
            }
          }
        }
      }

      if (_controlPoint != null) {
        // Solicitar control del FTMS antes de cualquier comando
        try {
          await _controlPoint!.write([0x00], withoutResponse: false);
          debugPrint('[KSCAN] Request Control enviado');
        } catch (e) {
          debugPrint('[KSCAN] Request Control error: $e');
        }
        setState(() {
          _connected = true;
          _scanning = false;
          _status = 'Conectado';
        });
        await _startForegroundService();
      } else {
        setState(() => _status = 'Control Point no encontrado');
      }
    } catch (e) {
      setState(() {
        _scanning = false;
        _status = 'Error al conectar: $e';
      });
    }
  }

  Future<void> _disconnect() async {
    _disconnecting = true;
    await _savePartialSession();
    await _stopForegroundService();
    await _connectionStateSub?.cancel();
    await _dataSubscription?.cancel();
    await _device?.disconnect();
    _disconnecting = false;
    _reconnectAttempts = 0;
    _dataNotifier.value = null;
    setState(() {
      _device = null;
      _services = [];
      _controlPoint = null;
      _connected = false;
      _data = null;
      _treadmillState = TreadmillState.idle;
      _sessionStart = null;
      _status = 'Desconectado';
    });
  }

  Future<void> _savePartialSession() async {
    if (_sessionStart == null || _data == null || _repo == null) return;
    if (_sessionSeconds == 0) return;
    final session = WorkoutSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      startedAt: _sessionStart!,
      endedAt: DateTime.now(),
      distanceMeters: _sessionDistance,
      calories: _sessionCalories,
      durationSeconds: _sessionSeconds,
      samples: List.unmodifiable(_sessionSamples),
    );
    await _repo!.save(session);
    _sessionStart = null;
    if (mounted) setState(() => _todaySessions = _repo!.loadToday());
  }

  Future<void> _handleUnexpectedDisconnect() async {
    await _savePartialSession();
    await _connectionStateSub?.cancel();
    await _dataSubscription?.cancel();
    if (!mounted) return;
    _dataNotifier.value = null;
    setState(() {
      _connected = false;
      _controlPoint = null;
      _data = null;
      _treadmillState = TreadmillState.idle;
      _status = 'Conexión perdida. Reconectando...';
    });
    FlutterForegroundTask.updateService(
      notificationTitle: 'KSCAN — Reconectando...',
      notificationText: 'Buscando K3',
    );
    await _retryConnect();
  }

  Future<void> _retryConnect() async {
    const maxAttempts = 5;
    while (_reconnectAttempts < maxAttempts && !_disconnecting && mounted) {
      _reconnectAttempts++;
      if (mounted) {
        setState(() => _status = 'Reconectando... (intento $_reconnectAttempts/$maxAttempts)');
      }
      await Future.delayed(const Duration(seconds: 3));
      if (_disconnecting || !mounted) return;
      await _connect(BluetoothDevice.fromId(kDeviceMac));
      if (_connected) {
        _reconnectAttempts = 0;
        return;
      }
    }
    if (mounted && !_connected) {
      setState(() => _status = 'No se pudo reconectar. Presioná Conectar.');
      await _stopForegroundService();
    }
  }

  // ---- Treadmill control ----

  Future<void> _sendCommand(List<int> bytes) async {
    if (_controlPoint == null) {
      debugPrint('[KSCAN] ERROR: controlPoint es null');
      return;
    }
    try {
      debugPrint('[KSCAN] Enviando: ${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
      await _controlPoint!.write(bytes, withoutResponse: false);
      debugPrint('[KSCAN] Enviado OK');
    } catch (e) {
      debugPrint('[KSCAN] Error al enviar: $e');
    }
  }

  Future<void> _start() async {
    if (_treadmillState == TreadmillState.idle) {
      _sessionStart = DateTime.now();
      _sessionSamples.clear();
      _sampleElapsed = 0;
      _baselineDistance = _data?.distanceMeters ?? 0;
      _baselineSeconds  = _data?.elapsedSeconds  ?? 0;
      _baselineCalories = _data?.totalEnergyKcal ?? 0;
      _baselineSteps    = _data?.steps           ?? 0;
    }
    await _sendCommand([0x07]);
    setState(() => _treadmillState = TreadmillState.running);
    _startSampleTimer();
  }

  Future<void> _pause() async {
    await _sendCommand([0x08, 0x02]);
    _sampleTimer?.cancel();
    setState(() => _treadmillState = TreadmillState.paused);
  }

  Future<void> _stop() async {
    await _sendCommand([0x08, 0x01]);
    _sampleTimer?.cancel();
    await _savePartialSession();
    setState(() {
      _treadmillState = TreadmillState.idle;
      _targetSpeed = kSpeedMin;
      _sessionSamples.clear();
      _sampleElapsed = 0;
    });
  }

  // Valores de la sesión actual (delta respecto a la baseline)
  int get _sessionDistance => (_data?.distanceMeters ?? 0) - _baselineDistance;
  int get _sessionSeconds  => (_data?.elapsedSeconds  ?? 0) - _baselineSeconds;
  int get _sessionCalories => (_data?.totalEnergyKcal ?? 0) - _baselineCalories;
  int get _sessionSteps    => (_data?.steps           ?? 0) - _baselineSteps;

  String _fmtSeconds(int s) {
    final m = s ~/ 60;
    final sec = s % 60;
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  void _startSampleTimer() {
    _sampleTimer?.cancel();
    _sampleTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_data == null) return;
      _sampleElapsed += 5;
      setState(() {
        _sessionSamples.add(SpeedSample(t: _sampleElapsed, v: _data!.speedKmh));
      });
    });
  }

  Future<void> _setSpeed(double speedKmh) async {
    final value = (speedKmh * 100).round();
    await _sendCommand([0x02, value & 0xFF, (value >> 8) & 0xFF]);
    setState(() => _targetSpeed = speedKmh);
  }

  void _increaseSpeed() {
    final next = (_targetSpeed + kSpeedStep).clamp(kSpeedMin, kSpeedMax);
    final rounded = (next * 10).round() / 10;
    _setSpeed(rounded);
  }

  void _decreaseSpeed() {
    final next = (_targetSpeed - kSpeedStep).clamp(kSpeedMin, kSpeedMax);
    final rounded = (next * 10).round() / 10;
    _setSpeed(rounded);
  }

  // ---- Foreground service ----

  Future<void> _startForegroundService() async {
    await FlutterForegroundTask.requestNotificationPermission();
    if (await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.startService(
      serviceId: 1000,
      notificationTitle: 'KSCAN — Conectado',
      notificationText: 'K3 conectada y monitoreando',
    );
  }

  Future<void> _updateForegroundNotification() async {
    if (!(await FlutterForegroundTask.isRunningService) || _data == null) return;
    final d = _data!;
    final running = _treadmillState == TreadmillState.running;
    FlutterForegroundTask.updateService(
      notificationTitle: running ? 'KSCAN — Sesión activa' : 'KSCAN — K3 conectada',
      notificationText: running
          ? '${d.speedKmh.toStringAsFixed(1)} km/h · ${_sessionDistance} m · ${_fmtSeconds(_sessionSeconds)}'
          : '$_sessionDistance m en esta sesión',
    );
  }

  Future<void> _stopForegroundService() async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }

  // ---- Navigation ----

  void _openDiagnostics() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DiagnosticScreen(services: _services),
      ),
    );
  }

  // ---- UI ----

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('KSCAN'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Historial',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => HistoryScreen(repo: _repo)),
              );
              if (mounted) setState(() => _todaySessions = _repo?.loadToday() ?? []);
            },
          ),
          if (_connected) ...[
            IconButton(
              icon: const Icon(Icons.route),
              tooltip: 'Pista 400m',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TrackScreen(
                    dataNotifier: _dataNotifier,
                    baselineDistance: _baselineDistance,
                    baselineSeconds: _baselineSeconds,
                    baselineCalories: _baselineCalories,
                    baselineSteps: _baselineSteps,
                  ),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.bug_report),
              tooltip: 'Diagnóstico BLE',
              onPressed: _openDiagnostics,
            ),
            IconButton(
              icon: const Icon(Icons.bluetooth_disabled),
              tooltip: 'Desconectar',
              onPressed: _disconnect,
            ),
          ],
        ],
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Estado de conexión
            _StatusBar(connected: _connected, status: _status),
            const SizedBox(height: 12),

            // Resumen del día
            if (_todaySessions.isNotEmpty) ...[
              _DayCard(sessions: _todaySessions),
              const SizedBox(height: 8),
            ],

            // Telemetría — PageView swipeable (siempre visible)
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    child: PageView(
                      controller: _pageController,
                      physics: _treadmillState != TreadmillState.idle || _pomodoroActive
                          ? const NeverScrollableScrollPhysics()
                          : const PageScrollPhysics(),
                      children: [
                        SpeedChartCard(
                          samples: _sessionSamples,
                          currentSpeed: _data?.speedKmh,
                          elapsedSeconds: _data != null ? _sessionSeconds : null,
                          distanceMeters: _data != null ? _sessionDistance : null,
                          calories: _data != null ? _sessionCalories : null,
                          steps: _data != null ? _sessionSteps : null,
                        ),
                        PomodoroWalkCard(
                          onTreadmillStart: _start,
                          onTreadmillStop: _stop,
                          onSetSpeed: _setSpeed,
                          onActiveChanged: (active) =>
                              setState(() => _pomodoroActive = active),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  _PageIndicator(
                    controller: _pageController,
                    count: 2,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Panel de control (siempre visible, deshabilitado sin conexión)
            if (!_pomodoroActive) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  children: [
                    _SpeedControl(
                      targetSpeed: _targetSpeed,
                      enabled: _treadmillState == TreadmillState.running,
                      onIncrease: _increaseSpeed,
                      onDecrease: _decreaseSpeed,
                      onSpeedSet: _setSpeed,
                    ),
                    const SizedBox(height: 10),
                    _ControlButtons(
                      state: _treadmillState,
                      connected: _connected,
                      onStart: _start,
                      onPause: _pause,
                      onResume: _start,
                      onStop: _stop,
                    ),
                  ],
                ),
              ),
            ],
          ],
          ),
        ),
      ),
      floatingActionButton: _connected
          ? null
          : FloatingActionButton.extended(
              onPressed: _scanning ? null : _startScan,
              label: Text(_scanning ? 'Conectando...' : 'Conectar'),
              icon: _scanning
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.bluetooth_searching),
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Widgets de control
// ---------------------------------------------------------------------------

class _StatusBar extends StatelessWidget {
  final bool connected;
  final String status;

  const _StatusBar({required this.connected, required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
      decoration: BoxDecoration(
        color: connected ? KScanColors.surfaceDark : KScanColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: connected ? KScanColors.surfaceDark : KScanColors.divider,
        ),
      ),
      child: Row(
        children: [
          Icon(
            connected ? Icons.bluetooth_connected : Icons.bluetooth,
            color: connected ? KScanColors.accent : KScanColors.muted,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              status,
              style: TextStyle(
                color: connected ? KScanColors.background : KScanColors.muted,
                fontWeight: connected ? FontWeight.w500 : FontWeight.normal,
                fontSize: 14,
              ),
            ),
          ),
          if (connected)
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: KScanColors.accent,
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
    );
  }
}

class _SpeedControl extends StatelessWidget {
  final double targetSpeed;
  final bool enabled;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;
  final ValueChanged<double> onSpeedSet;

  const _SpeedControl({
    required this.targetSpeed,
    required this.enabled,
    required this.onIncrease,
    required this.onDecrease,
    required this.onSpeedSet,
  });

  void _openSlider(BuildContext context) {
    if (!enabled) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _SpeedSliderSheet(
        initialSpeed: targetSpeed,
        onSpeedSet: onSpeedSet,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      decoration: BoxDecoration(
        color: KScanColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: KScanColors.divider),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _SpeedButton(
            icon: Icons.remove,
            onPressed: enabled && targetSpeed > kSpeedMin ? onDecrease : null,
          ),
          GestureDetector(
            onTap: () => _openSlider(context),
            child: Column(
              children: [
                Text(
                  '${targetSpeed.toStringAsFixed(1)} km/h',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    color: enabled ? KScanColors.ink : KScanColors.muted,
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  enabled ? 'tocar para ajustar' : 'velocidad objetivo',
                  style: const TextStyle(fontSize: 12, color: KScanColors.muted),
                ),
              ],
            ),
          ),
          _SpeedButton(
            icon: Icons.add,
            onPressed: enabled && targetSpeed < kSpeedMax ? onIncrease : null,
          ),
        ],
      ),
    );
  }
}

class _SpeedButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;

  const _SpeedButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final active = onPressed != null;
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: active ? KScanColors.ink : KScanColors.divider,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          color: active ? KScanColors.surface : KScanColors.muted,
          size: 22,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Modal de ajuste de velocidad con slider vertical
// ---------------------------------------------------------------------------

class _SpeedSliderSheet extends StatefulWidget {
  final double initialSpeed;
  final ValueChanged<double> onSpeedSet;

  const _SpeedSliderSheet({
    required this.initialSpeed,
    required this.onSpeedSet,
  });

  @override
  State<_SpeedSliderSheet> createState() => _SpeedSliderSheetState();
}

class _SpeedSliderSheetState extends State<_SpeedSliderSheet> {
  late double _speed;
  static const List<double> _presets = [1.0, 4.0, 6.0];

  @override
  void initState() {
    super.initState();
    _speed = widget.initialSpeed;
  }

  void _apply(double value) {
    final rounded = (value * 10).round() / 10;
    final clamped = rounded.clamp(kSpeedMin, kSpeedMax);
    if (clamped == _speed) return;
    setState(() => _speed = clamped);
    widget.onSpeedSet(clamped);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 575,
      decoration: const BoxDecoration(
        color: KScanColors.surfaceDark,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      child: Column(
        children: [
          // Handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Velocidad actual
          Text(
            _speed.toStringAsFixed(1),
            style: const TextStyle(
              fontSize: 64,
              fontWeight: FontWeight.w800,
              color: KScanColors.accent,
              letterSpacing: -2,
              height: 1,
            ),
          ),
          const Text(
            'km/h',
            style: TextStyle(fontSize: 16, color: KScanColors.muted, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 20),
          // Cinta métrica
          Expanded(
            child: _SpeedTape(speed: _speed, onChanged: _apply),
          ),
          const SizedBox(height: 20),
          // Chips de velocidades sugeridas
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: _presets.map((preset) {
              final isActive = (_speed - preset).abs() < 0.05;
              return GestureDetector(
                onTap: () => _apply(preset),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: isActive ? KScanColors.accent : Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isActive ? KScanColors.accent : Colors.white.withOpacity(0.15),
                    ),
                  ),
                  child: Text(
                    '${preset.toStringAsFixed(0)} km/h',
                    style: TextStyle(
                      color: isActive ? KScanColors.ink : KScanColors.background,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          SafeArea(top: false, child: const SizedBox(height: 16)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Cinta métrica de velocidad
// ---------------------------------------------------------------------------

class _SpeedTape extends StatefulWidget {
  final double speed;
  final ValueChanged<double> onChanged;

  const _SpeedTape({required this.speed, required this.onChanged});

  @override
  State<_SpeedTape> createState() => _SpeedTapeState();
}

class _SpeedTapeState extends State<_SpeedTape> {
  double get _pxPerStep {
    final box = context.findRenderObject() as RenderBox?;
    final h = box?.size.height ?? 200;
    final totalSteps = ((kSpeedMax - kSpeedMin) / 0.1).round();
    return h / totalSteps;
  }

  void _onDragUpdate(DragUpdateDetails d) {
    // dy negativo = dedo sube = indicador sube = velocidad mayor (top = max)
    final delta = (-d.delta.dy / _pxPerStep) * 0.1;
    final raw = widget.speed + delta;
    final rounded = (raw * 10).round() / 10;
    final clamped = rounded.clamp(kSpeedMin, kSpeedMax).toDouble();
    if (clamped != widget.speed) widget.onChanged(clamped);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: _onDragUpdate,
      child: CustomPaint(
        painter: _TapePainter(speed: widget.speed),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _TapePainter extends CustomPainter {
  final double speed;

  const _TapePainter({required this.speed});

  @override
  void paint(Canvas canvas, Size size) {
    final totalRange = kSpeedMax - kSpeedMin; // 5.0
    final totalSteps = (totalRange / 0.1).round(); // 50
    final stepHeight = size.height / totalSteps; // px por cada 0.1 km/h

    // Y=0 = kSpeedMax (top), Y=height = kSpeedMin (bottom)
    for (int i = 0; i <= totalSteps; i++) {
      final stepSpeed = (kSpeedMax * 10 - i).round() / 10.0;
      final y = i * stepHeight;

      final isMajor = (stepSpeed * 10).round() % 10 == 0;
      final isMid   = (stepSpeed * 10).round() % 5  == 0;

      final tickLen = isMajor ? 48.0 : isMid ? 30.0 : 16.0;
      final strokeW = isMajor ? 2.0  : isMid ? 1.5  : 1.0;
      final opacity = isMajor ? 0.85 : isMid ? 0.50 : 0.22;

      canvas.drawLine(
        Offset(size.width - tickLen, y),
        Offset(size.width - 6, y),
        Paint()
          ..color = Colors.white.withOpacity(opacity)
          ..strokeWidth = strokeW
          ..strokeCap = StrokeCap.round,
      );

      if (isMajor) {
        final tp = TextPainter(
          text: TextSpan(
            text: stepSpeed.toStringAsFixed(1),
            style: TextStyle(
              color: Colors.white.withOpacity(0.75),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(12, y - tp.height / 2));
      }
    }

    // Indicador dorado — se mueve con la velocidad actual
    final indicatorY = (kSpeedMax - speed) / totalRange * size.height;

    // Sombra suave detrás de la línea
    canvas.drawLine(
      Offset(0, indicatorY),
      Offset(size.width, indicatorY),
      Paint()
        ..color = KScanColors.accent.withOpacity(0.25)
        ..strokeWidth = 10,
    );

    // Línea dorada
    canvas.drawLine(
      Offset(0, indicatorY),
      Offset(size.width, indicatorY),
      Paint()
        ..color = KScanColors.accent
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );

    // Triángulo lateral
    final tri = Path()
      ..moveTo(0, indicatorY - 10)
      ..lineTo(18, indicatorY)
      ..lineTo(0, indicatorY + 10)
      ..close();
    canvas.drawPath(tri, Paint()..color = KScanColors.accent);
  }

  @override
  bool shouldRepaint(_TapePainter old) => old.speed != speed;
}

class _ControlButtons extends StatelessWidget {
  final TreadmillState state;
  final bool connected;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onStop;

  const _ControlButtons({
    required this.state,
    required this.connected,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      TreadmillState.idle => FilledButton.icon(
          onPressed: connected ? onStart : null,
          icon: const Icon(Icons.play_arrow),
          label: const Text('Iniciar'),
          // Hereda el estilo golden del tema
        ),
      TreadmillState.running => Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: onPause,
                icon: const Icon(Icons.pause),
                label: const Text('Pausar'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  backgroundColor: KScanColors.surfaceDark,
                  foregroundColor: KScanColors.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      TreadmillState.paused => Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: onResume,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Reanudar'),
                // Hereda el estilo golden del tema
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onStop,
                icon: const Icon(Icons.stop, color: KScanColors.stateStop),
                label: const Text(
                  'Detener',
                  style: TextStyle(color: KScanColors.stateStop),
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  side: const BorderSide(color: KScanColors.stateStop),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
    };
  }
}

// ---------------------------------------------------------------------------
// Widgets reutilizables
// ---------------------------------------------------------------------------

class _DataCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _DataCard({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: KScanColors.accentLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: KScanColors.accent, size: 20),
            ),
            const SizedBox(width: 14),
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                color: KScanColors.muted,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            Text(
              value,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: KScanColors.ink,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Card resumen del día
// ---------------------------------------------------------------------------

class _DayCard extends StatelessWidget {
  final List<WorkoutSession> sessions;

  const _DayCard({required this.sessions});

  @override
  Widget build(BuildContext context) {
    final totalDistance = sessions.fold(0, (sum, s) => sum + s.distanceMeters);
    final totalCalories = sessions.fold(0, (sum, s) => sum + s.calories);
    final totalSeconds = sessions.fold(0, (sum, s) => sum + s.durationSeconds);
    final totalMin = totalSeconds ~/ 60;
    final totalSec = totalSeconds % 60;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
      decoration: BoxDecoration(
        color: KScanColors.surfaceDark,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.today, size: 14, color: KScanColors.accent),
              const SizedBox(width: 6),
              Text(
                'Hoy · ${sessions.length} sesión${sessions.length > 1 ? 'es' : ''}',
                style: const TextStyle(
                  color: KScanColors.accent,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _DayStat(
                icon: Icons.straighten,
                value: '$totalDistance m',
                label: 'distancia',
              ),
              _DayStat(
                icon: Icons.timer,
                value:
                    '${totalMin.toString().padLeft(2, '0')}:${totalSec.toString().padLeft(2, '0')}',
                label: 'tiempo',
              ),
              _DayStat(
                icon: Icons.local_fire_department,
                value: '$totalCalories kcal',
                label: 'calorías',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DayStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _DayStat({required this.icon, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 16, color: KScanColors.accent),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: KScanColors.background,
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: KScanColors.muted),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Indicador de página para el PageView de telemetría
// ---------------------------------------------------------------------------

class _PageIndicator extends StatefulWidget {
  final PageController controller;
  final int count;

  const _PageIndicator({required this.controller, required this.count});

  @override
  State<_PageIndicator> createState() => _PageIndicatorState();
}

class _PageIndicatorState extends State<_PageIndicator> {
  int _current = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onPage);
  }

  void _onPage() {
    final page = widget.controller.page?.round() ?? 0;
    if (page != _current && mounted) setState(() => _current = page);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onPage);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.count <= 1) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(widget.count, (i) {
        final active = i == _current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: active ? 16 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: active ? KScanColors.accent : KScanColors.muted,
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }
}

// ---------------------------------------------------------------------------
// Pantalla de diagnóstico BLE
// ---------------------------------------------------------------------------

class DiagnosticScreen extends StatefulWidget {
  final List<BluetoothService> services;

  const DiagnosticScreen({super.key, required this.services});

  @override
  State<DiagnosticScreen> createState() => _DiagnosticScreenState();
}

class _DiagnosticScreenState extends State<DiagnosticScreen> {
  final Map<String, String> _values = {};
  final List<StreamSubscription<List<int>>> _subs = [];

  @override
  void initState() {
    super.initState();
    _exploreAll();
  }

  @override
  void dispose() {
    for (final sub in _subs) sub.cancel();
    super.dispose();
  }

  Future<void> _exploreAll() async {
    for (final service in widget.services) {
      for (final char in service.characteristics) {
        final uuid = char.uuid.toString();
        if (char.properties.read) {
          try {
            final bytes = await char.read();
            if (mounted) setState(() => _values[uuid] = _toHex(bytes));
          } catch (_) {}
        }
        if (char.properties.notify || char.properties.indicate) {
          try {
            await char.setNotifyValue(true);
            final sub = char.lastValueStream.listen((bytes) {
              if (mounted && bytes.isNotEmpty) {
                setState(() => _values[uuid] = _toHex(bytes));
              }
            });
            _subs.add(sub);
          } catch (_) {}
        }
      }
    }
  }

  String _toHex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');

  void _showWriteDialog(BluetoothCharacteristic char) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Write → ${char.uuid}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Bytes en hex separados por espacio:'),
            const SizedBox(height: 8),
            const Text('Ejemplo: 02 00 01', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'FF 01 02...'),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F ]'))],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _writeBytes(char, controller.text);
            },
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
  }

  Future<void> _writeBytes(BluetoothCharacteristic char, String hexInput) async {
    try {
      final parts = hexInput.trim().split(RegExp(r'\s+'));
      final bytes = parts.map((h) => int.parse(h, radix: 16)).toList();
      await char.write(bytes, withoutResponse: !char.properties.write);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Enviado: ${_toHex(bytes)}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnóstico BLE'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: widget.services.map((service) {
          return Card(
            margin: const EdgeInsets.only(bottom: 16),
            child: ExpansionTile(
              initiallyExpanded: true,
              title: Text(
                'Service: ${service.uuid}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              children: service.characteristics.map((char) {
                final uuid = char.uuid.toString();
                final value = _values[uuid];
                final canWrite = char.properties.write || char.properties.writeWithoutResponse;
                final props = [
                  if (char.properties.read) 'READ',
                  if (char.properties.write) 'WRITE',
                  if (char.properties.writeWithoutResponse) 'WRITE NR',
                  if (char.properties.notify) 'NOTIFY',
                  if (char.properties.indicate) 'INDICATE',
                ].join(' · ');

                return ListTile(
                  dense: true,
                  title: Text(uuid, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(props, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                      if (value != null)
                        SelectableText(
                          value,
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).colorScheme.primary,
                            fontFamily: 'monospace',
                          ),
                        ),
                    ],
                  ),
                  trailing: canWrite
                      ? IconButton(
                          icon: const Icon(Icons.send, size: 18),
                          tooltip: 'Enviar bytes',
                          onPressed: () => _showWriteDialog(char),
                        )
                      : null,
                );
              }).toList(),
            ),
          );
        }).toList(),
      ),
    );
  }
}
