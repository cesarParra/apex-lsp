/// All metadata extracted from a single SObject's XML files.
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
}

/// Metadata extracted from a single *.field-meta.xml file.
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
}
