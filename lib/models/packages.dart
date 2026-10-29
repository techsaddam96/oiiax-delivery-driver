class PackageResponse {
  final bool success;
  final List<Package> packages;

  PackageResponse({required this.success, required this.packages});

  factory PackageResponse.fromJson(Map<String, dynamic> json) {
    return PackageResponse(
      success: json['success'] ?? false,
      packages:
          (json['packages'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map(Package.fromJson)
              .toList() ??
          [],
    );
  }
}

class Package {
  final int id;
  final String slug;
  final String nameEn;
  final String nameAr;
  final String descriptionEn;
  final String descriptionAr;
  final int price;
  final String currency;
  final String linkContact;
  final int isActive;
  final List<Features> features;

  Package({
    required this.id,
    required this.slug,
    required this.nameEn,
    required this.nameAr,
    required this.descriptionEn,
    required this.descriptionAr,
    required this.price,
    required this.currency,
    required this.linkContact,
    required this.isActive,
    required this.features,
  });

  factory Package.fromJson(Map<String, dynamic> json) {
    return Package(
      id: _asInt(json['id']),
      slug: json['slug']?.toString() ?? '',
      nameEn: json['name_en']?.toString() ?? '',
      nameAr: json['name_ar']?.toString() ?? '',
      descriptionEn: json['description_en']?.toString() ?? '',
      descriptionAr: json['description_ar']?.toString() ?? '',
      price: _asInt(json['price']),
      currency: json['currency']?.toString() ?? '',
      linkContact: json['link_contact']?.toString() ?? '',
      isActive: _asBool(json['is_active']) ? 1 : 0,
      features:
          (json['features'] as List<dynamic>? ?? [])
              .whereType<Map<String, dynamic>>()
              .map(Features.fromJson)
              .toList(),
    );
  }
}

class Features {
  String? feature;
  String? featureAr;
  String? featureEn;

  Features.fromJson(Map<String, dynamic> json) {
    feature = json['feature']?.toString();
    featureAr = json['feature_ar']?.toString();
    featureEn = json['feature_en']?.toString();
  }
}

int _asInt(dynamic value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

bool _asBool(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final normalized = value?.toString().toLowerCase();
  return normalized == 'true' || normalized == '1';
}
