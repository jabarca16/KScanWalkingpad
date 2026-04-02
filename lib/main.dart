import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

// UUIDs del servicio FTMS de la K3 (descubiertos con BLE Scanner)
const String kFtmsServiceUuid = '1826';
const String kTreadmillDataUuid = '2acd';
const String kDeviceName = 'KS-AP-RF3';
const String kDeviceMac = '54:50:A0:10:4D:8A';

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

// Modelo que representa los datos que manda la caminadora
// Basado en el estándar FTMS (Bluetooth 0x2ACD) + propietario KingSmith
class TreadmillData {
  final double speedKmh;      // velocidad actual en km/h
  final int distanceMeters;   // distancia acumulada en metros
  final int totalEnergyKcal;  // calorías quemadas
  final int elapsedSeconds;   // tiempo de sesión en segundos
  final int steps;            // pasos (campo propietario KingSmith, byte 14)

  const TreadmillData({
    required this.speedKmh,
    required this.distanceMeters,
    required this.totalEnergyKcal,
    required this.elapsedSeconds,
    required this.steps,
  });

  // Parsea el paquete de 17 bytes que manda la K3 via 0x2ACD
  // Formato: [flags 2B][speed 2B][distance 3B][energy 5B][time 2B][prop 1B][unk 2B]
  static TreadmillData? fromBytes(List<int> bytes) {
    if (bytes.length < 15) return null;

    final speedRaw = bytes[2] | (bytes[3] << 8);
    final distanceRaw = bytes[4] | (bytes[5] << 8) | (bytes[6] << 16);
    final totalEnergy = bytes[7] | (bytes[8] << 8);
    final elapsedTime = bytes[12] | (bytes[13] << 8);
    final byte14 = bytes[14];

    return TreadmillData(
      speedKmh: speedRaw * 0.01,
      distanceMeters: distanceRaw,
      totalEnergyKcal: totalEnergy,
      elapsedSeconds: elapsedTime,
      steps: byte14,
    );
  }

  String get elapsedFormatted {
    final m = elapsedSeconds ~/ 60;
    final s = elapsedSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

class TreadmillScreen extends StatefulWidget {
  const TreadmillScreen({super.key});

  @override
  State<TreadmillScreen> createState() => _TreadmillScreenState();
}

class _TreadmillScreenState extends State<TreadmillScreen> {
  BluetoothDevice? _device;
  StreamSubscription<List<int>>? _dataSubscription;
  TreadmillData? _data;
  String _status = 'Presioná Conectar para buscar la K3';
  bool _scanning = false;
  bool _connected = false;

  @override
  void dispose() {
    _dataSubscription?.cancel();
    _device?.disconnect();
    super.dispose();
  }

  Future<void> _startScan() async {
    setState(() {
      _scanning = true;
      _connected = false;
      _data = null;
      _status = 'Conectando a KS-AP-RF3...';
    });

    // Conexión directa por MAC — más confiable que scan por nombre
    final device = BluetoothDevice.fromId(kDeviceMac);
    await _connect(device);
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

      // Debug: imprime todos los servicios y características encontrados
      for (final s in services) {
        debugPrint('SERVICE: ${s.uuid}');
        for (final c in s.characteristics) {
          debugPrint('  CHAR: ${c.uuid}');
        }
      }

      for (final service in services) {
        if (service.uuid.toString() == kFtmsServiceUuid) {
          for (final char in service.characteristics) {
            if (char.uuid.toString() == kTreadmillDataUuid) {
              await char.setNotifyValue(true);

              setState(() {
                _connected = true;
                _scanning = false;
                _status = 'Conectado — recibiendo datos en tiempo real';
              });

              _dataSubscription = char.lastValueStream.listen((bytes) {
                final parsed = TreadmillData.fromBytes(bytes);
                if (parsed != null && mounted) {
                  setState(() => _data = parsed);
                }
              });

              return;
            }
          }
        }
      }

      setState(() => _status = 'Servicio FTMS no encontrado en el dispositivo');
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
      _connected = false;
      _data = null;
      _status = 'Desconectado';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('KSCAN — KingSmith K3'),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (_connected)
            IconButton(
              icon: const Icon(Icons.bluetooth_disabled),
              tooltip: 'Desconectar',
              onPressed: _disconnect,
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Estado de conexión
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: _connected
                    ? Colors.green.shade50
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _connected ? Colors.green : Colors.grey.shade300,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _connected ? Icons.bluetooth_connected : Icons.bluetooth,
                    color: _connected ? Colors.green : Colors.grey,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _status,
                      style: TextStyle(
                        color: _connected ? Colors.green.shade800 : Colors.grey.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Datos de la caminadora
            if (_data != null) ...[
              _DataCard(
                label: 'Velocidad',
                value: '${_data!.speedKmh.toStringAsFixed(2)} km/h',
                icon: Icons.speed,
              ),
              _DataCard(
                label: 'Distancia',
                value: '${_data!.distanceMeters} m',
                icon: Icons.straighten,
              ),
              _DataCard(
                label: 'Tiempo',
                value: _data!.elapsedFormatted,
                icon: Icons.timer,
              ),
              _DataCard(
                label: 'Calorías',
                value: '${_data!.totalEnergyKcal} kcal',
                icon: Icons.local_fire_department,
              ),
              _DataCard(
                label: 'Pasos',
                value: '${_data!.steps}',
                icon: Icons.directions_walk,
              ),
            ] else if (_connected) ...[
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'Esperando datos...\n¿Está la caminadora en movimiento?',
                    textAlign: TextAlign.center,
                  ),
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
              label: Text(_scanning ? 'Buscando...' : 'Conectar'),
              icon: _scanning
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.bluetooth_searching),
            ),
    );
  }
}

class _DataCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _DataCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Text(
              label,
              style: Theme.of(context).textTheme.titleMedium,
            ),
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
