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
        id: map['id'] is int ? map['id'] : (int.tryParse(map['id']?.toString() ?? '')),
        name: map['name']?.toString() ?? '',
        address: map['address']?.toString(),
        latitude: map['latitude'] != null
            ? (double.tryParse(map['latitude'].toString()) ?? 0.0)
            : 0.0,
        longitude: map['longitude'] != null
            ? (double.tryParse(map['longitude'].toString()) ?? 0.0)
            : 0.0,
        positionOrder: map['positionOrder'] is int
            ? map['positionOrder']
            : (int.tryParse(map['positionOrder']?.toString() ?? '') ?? 0),
        updatedAt: map['updatedAt']?.toString() ?? '',
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
