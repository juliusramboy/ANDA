class PinnedLocation {
  final int? id;
  final String name;
  final String? address;
  final double latitude;
  final double longitude;
  final String category; // 'home', 'office', 'shop', 'warehouse', 'custom'
  final String updatedAt;

  PinnedLocation({
    this.id,
    required this.name,
    this.address,
    required this.latitude,
    required this.longitude,
    this.category = 'custom',
    String? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now().toUtc().toIso8601String();

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'address': address,
        'latitude': latitude,
        'longitude': longitude,
        'category': category,
        'updatedAt': updatedAt,
      };

  factory PinnedLocation.fromMap(Map<String, dynamic> map) => PinnedLocation(
        id: map['id'] is int ? map['id'] : (int.tryParse(map['id']?.toString() ?? '')),
        name: map['name']?.toString() ?? '',
        address: map['address']?.toString(),
        latitude: map['latitude'] != null
            ? (double.tryParse(map['latitude'].toString()) ?? 0.0)
            : 0.0,
        longitude: map['longitude'] != null
            ? (double.tryParse(map['longitude'].toString()) ?? 0.0)
            : 0.0,
        category: map['category']?.toString() ?? 'custom',
        updatedAt: map['updatedAt']?.toString() ?? '',
      );

  PinnedLocation copyWith({
    int? id,
    String? name,
    String? address,
    double? latitude,
    double? longitude,
    String? category,
    String? updatedAt,
  }) =>
      PinnedLocation(
        id: id ?? this.id,
        name: name ?? this.name,
        address: address ?? this.address,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        category: category ?? this.category,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
