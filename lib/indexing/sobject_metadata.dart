import 'package:json_annotation/json_annotation.dart';

part 'sobject_metadata.g.dart';

/// All metadata extracted from a single SObject's XML files.
@JsonSerializable()
final class SObjectMetadata {
  final String apiName;
  final String? label;
  final String? pluralLabel;
  final String? description;
  final List<SObjectFieldMetadata> fields;

  const SObjectMetadata({
    required this.apiName,
    this.label,
    this.pluralLabel,
    this.description,
    this.fields = const [],
  });

  factory SObjectMetadata.fromJson(Map<String, Object?> json) =>
      _$SObjectMetadataFromJson(json);

  Map<String, Object?> toJson() => _$SObjectMetadataToJson(this);
}

/// Metadata extracted from a single *.field-meta.xml file.
@JsonSerializable()
final class SObjectFieldMetadata {
  final String apiName;
  final String? label;
  final String? type;
  final String? description;

  const SObjectFieldMetadata({
    required this.apiName,
    this.label,
    this.type,
    this.description,
  });

  factory SObjectFieldMetadata.fromJson(Map<String, Object?> json) =>
      _$SObjectFieldMetadataFromJson(json);

  Map<String, Object?> toJson() => _$SObjectFieldMetadataToJson(this);
}
