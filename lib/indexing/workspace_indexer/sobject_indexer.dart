import 'dart:convert';
import 'dart:io' show Platform;

import 'package:apex_lsp/indexing/sobject_metadata.dart';
import 'package:apex_lsp/indexing/sobject_xml_parser.dart';
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
}) async {
  final dirs = await _collect(
    fileSystem: fileSystem,
    platform: platform,
    packageDirectoryUris: packageDirectoryUris,
    indexDir: indexDir,
  );
  final stale = await _filterStale(fileSystem: fileSystem, dirs: dirs);
  await _indexInParallel(fileSystem: fileSystem, dirs: stale);
  await _removeOrphans(
    fileSystem: fileSystem,
    sobjectDirs: dirs,
    indexDir: indexDir,
  );
}

Future<List<_SObjectDir>> _collect({
  required FileSystem fileSystem,
  required LspPlatform platform,
  required List<Uri> packageDirectoryUris,
  required Directory indexDir,
}) async {
  final sobjectDirs = <_SObjectDir>[];

  for (final pkgDirUri in packageDirectoryUris) {
    final pkgDirPath = pkgDirUri.toFilePath(windows: platform.isWindows);
    final pkgDir = fileSystem.directory(pkgDirPath);

    if (!await pkgDir.exists()) continue;

    await for (final entity in pkgDir.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;

      final basename = fileSystem.path.basename(entity.path);
      if (!basename.endsWith('.object-meta.xml')) continue;

      // The object name is the filename stem, e.g. "Account" from
      // "Account.object-meta.xml". The object directory is the parent.
      final objectName = basename.replaceFirst('.object-meta.xml', '');
      final objectDir = entity.parent;

      sobjectDirs.add((
        objectDir: objectDir,
        objectName: objectName,
        indexDir: indexDir,
      ));
    }
  }

  return sobjectDirs;
}

Future<List<_SObjectDir>> _filterStale({
  required FileSystem fileSystem,
  required List<_SObjectDir> dirs,
}) async {
  final stale = <_SObjectDir>[];
  for (final dir in dirs) {
    if (await _isStale(fileSystem: fileSystem, sobjectDir: dir)) stale.add(dir);
  }
  return stale;
}

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

Future<void> _indexInParallel({
  required FileSystem fileSystem,
  required List<_SObjectDir> dirs,
}) async {
  final batchSize = Platform.numberOfProcessors;
  for (var offset = 0; offset < dirs.length; offset += batchSize) {
    final batch = dirs.skip(offset).take(batchSize).toList();
    await Future.wait(
      batch.map((d) => _indexSingle(fileSystem: fileSystem, sobjectDir: d)),
    );
  }
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

Future<void> _removeOrphans({
  required FileSystem fileSystem,
  required List<_SObjectDir> sobjectDirs,
  required Directory indexDir,
}) async {
  final knownNames = sobjectDirs.map((d) => d.objectName.toLowerCase()).toSet();

  await for (final entity in indexDir.list()) {
    if (entity is! File || !entity.path.endsWith('.json')) continue;
    final stem = fileSystem.path
        .basenameWithoutExtension(entity.path)
        .toLowerCase();
    if (!knownNames.contains(stem)) await entity.delete();
  }
}
