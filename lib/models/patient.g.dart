// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'patient.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Patient _$PatientFromJson(Map<String, dynamic> json) => Patient(
  id: json['id'] as String?,
  name: (json['name'] as List<dynamic>?)
      ?.map((e) => HumanName.fromJson(e as Map<String, dynamic>))
      .toList(),
  gender: json['gender'] as String?,
  birthDate: json['birthDate'] as String?,
  identifier: (json['identifier'] as List<dynamic>?)
      ?.map((e) => Identifier.fromJson(e as Map<String, dynamic>))
      .toList(),
  address: (json['address'] as List<dynamic>?)
      ?.map((e) => Address.fromJson(e as Map<String, dynamic>))
      .toList(),
  telecom: (json['telecom'] as List<dynamic>?)
      ?.map((e) => ContactPoint.fromJson(e as Map<String, dynamic>))
      .toList(),
);

Map<String, dynamic> _$PatientToJson(Patient instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'gender': instance.gender,
  'birthDate': instance.birthDate,
  'identifier': instance.identifier,
  'address': instance.address,
  'telecom': instance.telecom,
};

HumanName _$HumanNameFromJson(Map<String, dynamic> json) => HumanName(
  use: json['use'] as String?,
  given: (json['given'] as List<dynamic>?)?.map((e) => e as String).toList(),
  family: json['family'] as String?,
);

Map<String, dynamic> _$HumanNameToJson(HumanName instance) => <String, dynamic>{
  'use': instance.use,
  'given': instance.given,
  'family': instance.family,
};

Identifier _$IdentifierFromJson(Map<String, dynamic> json) => Identifier(
  system: json['system'] as String?,
  value: json['value'] as String?,
  type: json['type'] as String?,
);

Map<String, dynamic> _$IdentifierToJson(Identifier instance) =>
    <String, dynamic>{
      'system': instance.system,
      'value': instance.value,
      'type': instance.type,
    };

Address _$AddressFromJson(Map<String, dynamic> json) => Address(
  line: (json['line'] as List<dynamic>?)?.map((e) => e as String).toList(),
  city: json['city'] as String?,
  state: json['state'] as String?,
  postalCode: json['postalCode'] as String?,
  country: json['country'] as String?,
);

Map<String, dynamic> _$AddressToJson(Address instance) => <String, dynamic>{
  'line': instance.line,
  'city': instance.city,
  'state': instance.state,
  'postalCode': instance.postalCode,
  'country': instance.country,
};

ContactPoint _$ContactPointFromJson(Map<String, dynamic> json) => ContactPoint(
  system: json['system'] as String?,
  value: json['value'] as String?,
  use: json['use'] as String?,
);

Map<String, dynamic> _$ContactPointToJson(ContactPoint instance) =>
    <String, dynamic>{
      'system': instance.system,
      'value': instance.value,
      'use': instance.use,
    };
