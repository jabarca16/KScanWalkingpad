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
