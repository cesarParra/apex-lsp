import 'package:file/file.dart';

enum MetadataType { apexClass, sObject, sObjectField, unsupported }

extension IndexedFileExtension on File {
  MetadataType get metadataType {
    final name = path.toLowerCase().split('/').last;
    if (name.endsWith('.cls')) return .apexClass;
    if (name.endsWith('.object-meta.xml')) return .sObject;
    if (name.endsWith('.field-meta.xml')) return .sObjectField;
    return .unsupported;
  }
}
