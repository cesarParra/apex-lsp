import 'dart:io';

sealed class MetadataType {}

final class ApexClassType extends MetadataType {}

final class SObjectType extends MetadataType {}

final class SObjectFieldType extends MetadataType {}

final class UnsupportedType extends MetadataType {}

extension IndexedFileExtension on File {
  MetadataType get metadataType {
    final name = path.toLowerCase().split('/').last;
    if (name.endsWith('.cls')) return ApexClassType();
    if (name.endsWith('.object-meta.xml')) return SObjectType();
    if (name.endsWith('.field-meta.xml')) return SObjectFieldType();
    return UnsupportedType();
  }
}
