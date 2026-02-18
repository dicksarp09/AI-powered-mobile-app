/// Represents the device hardware profile and resource state.
/// 
/// This class contains immutable information about the device's
/// capabilities and current resource status.
class DeviceProfile {
  /// Total RAM available on the device in gigabytes
  final double ramGB;
  
  /// Number of CPU cores available
  final int cpuCores;
  
  /// Current battery level as a percentage (0-100)
  final int batteryLevel;
  
  /// Whether the device is currently experiencing low memory pressure
  final bool isLowMemory;

  const DeviceProfile({
    required this.ramGB,
    required this.cpuCores,
    required this.batteryLevel,
    required this.isLowMemory,
  });

  /// Creates a DeviceProfile from a platform channel response map
  factory DeviceProfile.fromMap(Map<String, dynamic> map) {
    return DeviceProfile(
      ramGB: (map['ramGB'] as num).toDouble(),
      cpuCores: map['cpuCores'] as int,
      batteryLevel: map['batteryLevel'] as int,
      isLowMemory: map['isLowMemory'] as bool,
    );
  }

  /// Converts this profile to a map for serialization
  Map<String, dynamic> toMap() {
    return {
      'ramGB': ramGB,
      'cpuCores': cpuCores,
      'batteryLevel': batteryLevel,
      'isLowMemory': isLowMemory,
    };
  }

  @override
  String toString() {
    return 'DeviceProfile(ramGB: ${ramGB.toStringAsFixed(1)}, '
        'cpuCores: $cpuCores, batteryLevel: $batteryLevel%, '
        'isLowMemory: $isLowMemory)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DeviceProfile &&
        other.ramGB == ramGB &&
        other.cpuCores == cpuCores &&
        other.batteryLevel == batteryLevel &&
        other.isLowMemory == isLowMemory;
  }

  @override
  int get hashCode {
    return ramGB.hashCode ^
        cpuCores.hashCode ^
        batteryLevel.hashCode ^
        isLowMemory.hashCode;
  }
}
