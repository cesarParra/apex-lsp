import 'dart:convert';

import 'package:apex_lsp/indexing/sobject_metadata.dart';
import 'package:apex_lsp/indexing/sobject_xml_parser.dart';
import 'package:apex_lsp/indexing/workspace_indexer/indexer_utils.dart';
import 'package:apex_lsp/utils/platform.dart';
import 'package:file/file.dart';

typedef _SObjectDir = ({
  Directory objectDir,
  String objectName,
  Directory indexDir,
});

Future<void> runSObjectIndexer({
  required FileSystem fileSystem,
  required LspPlatform platform,
  required List<Uri> packageDirectoryUris,
  required Directory indexDir,
}) => runIndexer<_SObjectDir>(
  fileSystem: fileSystem,
  platform: platform,
  packageDirectoryUris: packageDirectoryUris,
  indexDir: indexDir,
  recognize: (file) {
    final basename = fileSystem.path.basename(file.path);
    if (!basename.endsWith('.object-meta.xml')) return null;
    final objectName = basename.replaceFirst('.object-meta.xml', '');
    return (objectDir: file.parent, objectName: objectName, indexDir: indexDir);
  },
  isStale: (sobjectDir) =>
      _isStale(fileSystem: fileSystem, sobjectDir: sobjectDir),
  index: (sobjectDir) =>
      _indexSingle(fileSystem: fileSystem, sobjectDir: sobjectDir),
  nameOf: (sobjectDir) => sobjectDir.objectName,
);

Future<bool> _isStale({
  required FileSystem fileSystem,
  required _SObjectDir sobjectDir,
}) async {
  final jsonFile = fileSystem.file(
    fileSystem.path.join(
      sobjectDir.indexDir.path,
      '${sobjectDir.objectName}.json',
    ),
  );
  if (!await jsonFile.exists()) return true;

  final jsonModified = await jsonFile.lastModified();

  await for (final entity in sobjectDir.objectDir.list(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is! File) continue;
    if ((await entity.lastModified()).isAfter(jsonModified)) {
      return true;
    }
  }

  return false;
}

Future<void> _indexSingle({
  required FileSystem fileSystem,
  required _SObjectDir sobjectDir,
}) async {
  try {
    final objectName = sobjectDir.objectName;
    final objectMetaFile = fileSystem.file(
      fileSystem.path.join(
        sobjectDir.objectDir.path,
        '$objectName.object-meta.xml',
      ),
    );

    final objectXml = await objectMetaFile.readAsString();
    final metadata = parseObjectMetaXml(objectName, objectXml);
    final fields = await _parseFieldFiles(
      fileSystem: fileSystem,
      objectDir: sobjectDir.objectDir,
    );

    final metadataWithFields = SObjectMetadata(
      apiName: metadata.apiName,
      label: metadata.label,
      pluralLabel: metadata.pluralLabel,
      description: metadata.description,
      fields: fields,
    );

    final payload = <String, Object?>{
      'schemaVersion': 1,
      'objectApiName': objectName,
      'source': <String, Object?>{
        'objectMetaUri': Uri.file(objectMetaFile.path).toString(),
        'relativePath': sobjectDir.objectDir.path,
      },
      'objectMetadata': _serialize(metadataWithFields),
    };

    final outPath = fileSystem.path.join(
      sobjectDir.indexDir.path,
      '$objectName.json',
    );
    await fileSystem
        .file(outPath)
        .writeAsString(const JsonEncoder.withIndent('  ').convert(payload));
  } catch (_) {
    // Silently skip objects that fail to parse or write.
  }
}

Future<List<SObjectFieldMetadata>> _parseFieldFiles({
  required FileSystem fileSystem,
  required Directory objectDir,
}) async {
  final fieldsDir = fileSystem.directory(
    fileSystem.path.join(objectDir.path, 'fields'),
  );
  if (!await fieldsDir.exists()) return [];

  final fields = <SObjectFieldMetadata>[];
  await for (final entity in fieldsDir.list(followLinks: false)) {
    if (entity is! File) continue;
    if (!entity.path.toLowerCase().endsWith('.field-meta.xml')) continue;
    final xml = await entity.readAsString();
    final field = parseFieldMetaXml(xml);
    if (field != null) fields.add(field);
  }
  return fields;
}

Map<String, Object?> _serialize(SObjectMetadata metadata) => {
  'apiName': metadata.apiName,
  'label': metadata.label,
  'pluralLabel': metadata.pluralLabel,
  'description': metadata.description,
  'fields': metadata.fields
      .map(
        (field) => <String, Object?>{
          'apiName': field.apiName,
          'label': field.label,
          'type': field.type,
          'description': field.description,
        },
      )
      .toList(),
};
