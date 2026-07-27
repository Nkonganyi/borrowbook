class ProfileModel {
  final String id;
  final String fullName;
  final String phone;
  final String role;

  ProfileModel({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.role,
  });

  factory ProfileModel.fromJson(Map<String, dynamic> json) {
    return ProfileModel(
      id: json['id'],
      fullName: json['full_name'],
      phone: json['phone'] ?? '',
      role: json['role'] ?? 'seller',
    );
  }
}