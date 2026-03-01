import 'package:json_annotation/json_annotation.dart';

part 'apex_index_entry.g.dart';

@JsonSerializable()
final class ApexIndexSource {
  final String uri;
  final String relativePath;

  const ApexIndexSource({required this.uri, required this.relativePath});

  factory ApexIndexSource.fromJson(Map<String, Object?> json) =>
      _$ApexIndexSourceFromJson(json);

  Map<String, Object?> toJson() => _$ApexIndexSourceToJson(this);
}

@JsonSerializable()
final class ApexIndexEntry {
  final int schemaVersion;
  final String className;
  final ApexIndexSource source;

  /// Raw JSON map produced by `apex_reflection` — kept as-is because
  /// `apex_reflection` owns its own deserialization via `fromJson` factories.
  final Map<String, Object?> typeMirror;

  const ApexIndexEntry({
    required this.schemaVersion,
    required this.className,
    required this.source,
    required this.typeMirror,
  });

  factory ApexIndexEntry.fromJson(Map<String, Object?> json) =>
      _$ApexIndexEntryFromJson(json);

  Map<String, Object?> toJson() => _$ApexIndexEntryToJson(this);
}
