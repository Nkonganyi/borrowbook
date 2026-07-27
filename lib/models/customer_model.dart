class Customer {
  final String id;
  final String name;
  final String? phone;
  final String? location;
  final String? notes;

  Customer({
    required this.id,
    required this.name,
    this.phone,
    this.location,
    this.notes,
  });

  factory Customer.fromJson(Map<String, dynamic> json) {
    return Customer(
      id: json['id'],
      name: json['name'],
      phone: json['phone'],
      location: json['location'],
      notes: json['notes'],
    );
  }
}