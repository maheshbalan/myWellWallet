import 'package:json_annotation/json_annotation.dart';

part 'patient.g.dart';

@JsonSerializable()
class Patient {
  final String? id;
  final List<HumanName>? name;
  final String? gender;
  final String? birthDate;
  final List<Identifier>? identifier;
  final List<Address>? address;
  final List<ContactPoint>? telecom;

  Patient({
    this.id,
    this.name,
    this.gender,
    this.birthDate,
    this.identifier,
    this.address,
    this.telecom,
  });

  factory Patient.fromJson(Map<String, dynamic> json) =>
      _$PatientFromJson(json);

  Map<String, dynamic> toJson() => _$PatientToJson(this);

  String get displayName {
    if (name == null || name!.isEmpty) return 'Unknown';
    final firstName = name!.first;
    final given = firstName.given?.join(' ') ?? '';
    final family = firstName.family ?? '';
    return '$given $family'.trim().isEmpty ? 'Unknown' : '$given $family'.trim();
  }

  String get fullAddress {
    if (address == null || address!.isEmpty) return 'No address';
    final addr = address!.first;
    final parts = <String>[];
    if (addr.line != null) parts.addAll(addr.line!);
    if (addr.city != null) parts.add(addr.city!);
    if (addr.state != null) parts.add(addr.state!);
    if (addr.postalCode != null) parts.add(addr.postalCode!);
    return parts.join(', ');
  }
}

@JsonSerializable()
class HumanName {
  final String? use;
  final List<String>? given;
  final String? family;

  HumanName({this.use, this.given, this.family});

  factory HumanName.fromJson(Map<String, dynamic> json) =>
      _$HumanNameFromJson(json);

  Map<String, dynamic> toJson() => _$HumanNameToJson(this);
}

@JsonSerializable()
class Identifier {
  final String? system;
  final String? value;
  final String? type;

  Identifier({this.system, this.value, this.type});

  factory Identifier.fromJson(Map<String, dynamic> json) =>
      _$IdentifierFromJson(json);

  Map<String, dynamic> toJson() => _$IdentifierToJson(this);
}

@JsonSerializable()
class Address {
  final List<String>? line;
  final String? city;
  final String? state;
  final String? postalCode;
  final String? country;

  Address({
    this.line,
    this.city,
    this.state,
    this.postalCode,
    this.country,
  });

  factory Address.fromJson(Map<String, dynamic> json) =>
      _$AddressFromJson(json);

  Map<String, dynamic> toJson() => _$AddressToJson(this);
}

@JsonSerializable()
class ContactPoint {
  final String? system;
  final String? value;
  final String? use;

  ContactPoint({this.system, this.value, this.use});

  factory ContactPoint.fromJson(Map<String, dynamic> json) =>
      _$ContactPointFromJson(json);

  Map<String, dynamic> toJson() => _$ContactPointToJson(this);
}

