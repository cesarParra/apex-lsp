import 'package:apex_lsp/indexing/sobject_metadata.dart';
import 'package:json_annotation/json_annotation.dart';

part 'sobject_index_entry.g.dart';

@JsonSerializable()
final class SObjectIndexSource {
  final String objectMetaUri;
  final String relativePath;

  const SObjectIndexSource({
    required this.objectMetaUri,
    required this.relativePath,
  });

  factory SObjectIndexSource.fromJson(Map<String, Object?> json) =>
      _$SObjectIndexSourceFromJson(json);

  Map<String, Object?> toJson() => _$SObjectIndexSourceToJson(this);
}

@JsonSerializable()
final class SObjectIndexEntry {
  final int schemaVersion;
  final String objectApiName;
  final SObjectIndexSource source;
  final SObjectMetadata objectMetadata;

  const SObjectIndexEntry({
    required this.schemaVersion,
    required this.objectApiName,
    required this.source,
    required this.objectMetadata,
  });

  factory SObjectIndexEntry.fromJson(Map<String, Object?> json) =>
      _$SObjectIndexEntryFromJson(json);

  Map<String, Object?> toJson() => _$SObjectIndexEntryToJson(this);
}
