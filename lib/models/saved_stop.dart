class SavedStop {
  final int? id;
  final String name;
  final String? address;
  final double latitude;
  final double longitude;
  final int positionOrder;
  final String updatedAt;

  SavedStop({
    this.id,
    required this.name,
    this.address,
    required this.latitude,
    required this.longitude,
    required this.positionOrder,
    String? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now().toUtc().toIso8601String();

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'address': address,
        'latitude': latitude,
        'longitude': longitude,
        'positionOrder': positionOrder,
        'updatedAt': updatedAt,
      };

  factory SavedStop.fromMap(Map<String, dynamic> map) => SavedStop(
        id: map['id'],
        name: map['name'] ?? '',
        address: map['address'],
        latitude: map['latitude']?.toDouble() ?? 0.0,
        longitude: map['longitude']?.toDouble() ?? 0.0,
        positionOrder: map['positionOrder'] ?? 0,
        updatedAt: map['updatedAt'],
      );

  SavedStop copyWith({
    int? id,
    String? name,
    String? address,
    double? latitude,
    double? longitude,
    int? positionOrder,
    String? updatedAt,
  }) =>
      SavedStop(
        id: id ?? this.id,
        name: name ?? this.name,
        address: address ?? this.address,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        positionOrder: positionOrder ?? this.positionOrder,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
