import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

const String kFtmsServiceUuid = '1826';
const String kTreadmillDataUuid = '2acd';
const String kControlPointUuid = '2ad9';
const String kDeviceMac = '54:50:A0:10:4D:8A';

const double kSpeedMin = 1.0;
const double kSpeedMax = 6.0;
const double kSpeedStep = 0.1;

void main() {
  runApp(const KScanApp());
}

class KScanApp extends StatelessWidget {
  const KScanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KSCAN',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const TreadmillScreen(),
    );
  }
}

// ---------------------------------------------------------------------------
// Estado de la caminadora
// ---------------------------------------------------------------------------

enum TreadmillState { idle, running, paused }

// ---------------------------------------------------------------------------
// Modelo de datos
// ---------------------------------------------------------------------------

class TreadmillData {
  final double speedKmh;
  final int distanceMeters;
  final int totalEnergyKcal;
  final int elapsedSeconds;
  final int steps;

  const TreadmillData({
    required this.speedKmh,
    required this.distanceMeters,
    required this.totalEnergyKcal,
    required this.elapsedSeconds,
    required this.steps,
  });

  // Paquete FTMS 0x2ACD (17 bytes):
  // [0-1] flags  [2-3] speed×0.01km/h  [4-6] distance m
  // [7-8] kcal   [9-10] kcal/h  [11] kcal/min
  // [12-13] elapsed s  [14] steps (propietario KingSmith)  [15-16] 0x0000
  static TreadmillData? fromBytes(List<int> bytes) {
    if (bytes.length < 15) return null;
    return TreadmillData(
      speedKmh: (bytes[2] | (bytes[3] << 8)) * 0.01,
      distanceMeters: bytes[4] | (bytes[5] << 8) | (bytes[6] << 16),
      totalEnergyKcal: bytes[7] | (bytes[8] << 8),
      elapsedSeconds: bytes[12] | (bytes[13] << 8),
      steps: bytes[14],
    );
  }

  String get elapsedFormatted {
    final m = elapsedSeconds ~/ 60;
    final s = elapsedSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

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

  TreadmillData? _data;
  TreadmillState _treadmillState = TreadmillState.idle;
  double _targetSpeed = kSpeedMin;

  String _status = 'Presioná Conectar para buscar la K3';
  bool _scanning = false;
  bool _connected = false;

  @override
  void dispose() {
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
                if (parsed != null && mounted) setState(() => _data = parsed);
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
    await _dataSubscription?.cancel();
    await _device?.disconnect();
    setState(() {
      _device = null;
      _services = [];
      _controlPoint = null;
      _connected = false;
      _data = null;
      _treadmillState = TreadmillState.idle;
      _status = 'Desconectado';
    });
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
    await _sendCommand([0x07]);
    setState(() => _treadmillState = TreadmillState.running);
  }

  Future<void> _pause() async {
    await _sendCommand([0x08, 0x02]);
    setState(() => _treadmillState = TreadmillState.paused);
  }

  Future<void> _stop() async {
    await _sendCommand([0x08, 0x01]);
    setState(() {
      _treadmillState = TreadmillState.idle;
      _targetSpeed = kSpeedMin;
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
        title: const Text('KSCAN — KingSmith K3'),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (_connected) ...[
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
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Estado de conexión
            _StatusBar(connected: _connected, status: _status),
            const SizedBox(height: 24),

            // Métricas
            if (_data != null) ...[
              _DataCard(label: 'Velocidad', value: '${_data!.speedKmh.toStringAsFixed(2)} km/h', icon: Icons.speed),
              _DataCard(label: 'Distancia', value: '${_data!.distanceMeters} m', icon: Icons.straighten),
              _DataCard(label: 'Tiempo', value: _data!.elapsedFormatted, icon: Icons.timer),
              _DataCard(label: 'Calorías', value: '${_data!.totalEnergyKcal} kcal', icon: Icons.local_fire_department),
              _DataCard(label: 'Pasos', value: '${_data!.steps}', icon: Icons.directions_walk),
            ] else if (_connected) ...[
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Esperando datos...', textAlign: TextAlign.center),
                ),
              ),
            ],

            const Spacer(),

            // Panel de control (solo cuando conectado)
            if (_connected) ...[
              SafeArea(
                top: false,
                child: Column(
                  children: [
                    _SpeedControl(
                      targetSpeed: _targetSpeed,
                      enabled: _treadmillState == TreadmillState.running,
                      onIncrease: _increaseSpeed,
                      onDecrease: _decreaseSpeed,
                    ),
                    const SizedBox(height: 16),
                    _ControlButtons(
                      state: _treadmillState,
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
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: connected ? Colors.green.shade50 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: connected ? Colors.green : Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Icon(
            connected ? Icons.bluetooth_connected : Icons.bluetooth,
            color: connected ? Colors.green : Colors.grey,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              status,
              style: TextStyle(
                color: connected ? Colors.green.shade800 : Colors.grey.shade700,
              ),
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

  const _SpeedControl({
    required this.targetSpeed,
    required this.enabled,
    required this.onIncrease,
    required this.onDecrease,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton.filled(
            onPressed: enabled && targetSpeed > kSpeedMin ? onDecrease : null,
            icon: const Icon(Icons.remove),
            iconSize: 28,
          ),
          Column(
            children: [
              Text(
                '${targetSpeed.toStringAsFixed(1)} km/h',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: enabled ? color : Colors.grey,
                ),
              ),
              Text(
                'velocidad objetivo',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
          IconButton.filled(
            onPressed: enabled && targetSpeed < kSpeedMax ? onIncrease : null,
            icon: const Icon(Icons.add),
            iconSize: 28,
          ),
        ],
      ),
    );
  }
}

class _ControlButtons extends StatelessWidget {
  final TreadmillState state;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onStop;

  const _ControlButtons({
    required this.state,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      TreadmillState.idle => FilledButton.icon(
          onPressed: onStart,
          icon: const Icon(Icons.play_arrow),
          label: const Text('Iniciar'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            backgroundColor: Colors.green,
          ),
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
                  backgroundColor: Colors.orange,
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
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  backgroundColor: Colors.green,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: onStop,
                icon: const Icon(Icons.stop),
                label: const Text('Detener'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  backgroundColor: Colors.red,
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
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Text(label, style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
          ],
        ),
      ),
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
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
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
