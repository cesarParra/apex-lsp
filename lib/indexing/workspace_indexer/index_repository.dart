import 'dart:convert';

import 'package:apex_lsp/indexing/declarations.dart';
import 'package:apex_lsp/indexing/index_paths.dart';
import 'package:apex_lsp/type_name.dart';
import 'package:apex_lsp/utils/platform.dart';
import 'package:apex_reflection/apex_reflection.dart' as apex_reflection;
import 'package:file/file.dart';

/// Optional logging callback for index repository diagnostics.
typedef IndexRepositoryLog = void Function(String message);

final class IndexRepository {
  IndexRepository({
    required FileSystem fileSystem,
    required LspPlatform platform,
    required List<Uri> workspaceRootUris,
    IndexRepositoryLog? log,
  }) : _fileSystem = fileSystem,
       _platform = platform,
       _workspaceRootUris = workspaceRootUris,
       _log = log;

  final FileSystem _fileSystem;
  final LspPlatform _platform;
  final List<Uri> _workspaceRootUris;
  final IndexRepositoryLog? _log;

  // Populated on first access and retained for the lifetime of this instance.
  // A new IndexRepository is created after each re-index, so no explicit
  // invalidation is needed.
  final Map<Uri, Map<String, IndexedType>> _apexCache = {};
  final Map<Uri, Map<String, IndexedSObject>> _sobjectCache = {};

  Future<List<IndexedType>> getDeclarations() async {
    final declarations = <IndexedType>[];
    for (final root in _workspaceRootUris) {
      declarations.addAll((await _loadApexForWorkspace(root)).values);
      declarations.addAll((await _loadSObjectsForWorkspace(root)).values);
    }
    return declarations;
  }

  Future<IndexedType?> getIndexedType(String typeName) async {
    if (typeName.isEmpty) return null;
    final key = typeName.toLowerCase();

    for (final root in _workspaceRootUris) {
      final apex = await _loadApexForWorkspace(root);
      if (apex.containsKey(key)) return apex[key];

      final sobjects = await _loadSObjectsForWorkspace(root);
      if (sobjects.containsKey(key)) return sobjects[key];
    }

    return null;
  }

  Future<Map<String, IndexedType>> _loadApexForWorkspace(
    Uri workspaceRoot,
  ) async {
    return _loadFromCache(
      cache: _apexCache,
      workspaceRoot: workspaceRoot,
      subFolder: apexIndexFolderName,
      parse: (decoded) {
        final indexedType = _parseApex(decoded);
        if (indexedType == null) {
          final typeMirror = decoded is Map ? decoded['typeMirror'] : null;
          final typeNameValue = typeMirror is Map
              ? typeMirror['type_name']
              : 'unknown';
          _log?.call(
            'SKIPPED: _parseApex returned null (type_name=$typeNameValue)',
          );
          return null;
        }
        return indexedType;
      },
      onDirectoryMissing: () {
        _log?.call('Index directory does not exist');
      },
      onFileLoaded: (count, total) {
        _log?.call('Found $total JSON files, loaded $count types');
      },
      onDuplicate: (key) {
        _log?.call('DUPLICATE key "$key" overwritten');
      },
      onError: (path, error) {
        _log?.call('ERROR reading $path: $error');
      },
    );
  }

  Future<Map<String, IndexedSObject>> _loadSObjectsForWorkspace(
    Uri workspaceRoot,
  ) async {
    return _loadFromCache(
      cache: _sobjectCache,
      workspaceRoot: workspaceRoot,
      subFolder: sobjectIndexFolderName,
      parse: (decoded) {
        if (decoded is! Map<String, dynamic>) return null;
        return _parseSObject(decoded);
      },
      onError: (path, error) {
        _log?.call('ERROR reading $path: $error');
      },
    );
  }

  /// Loads and caches typed index entries from a subfolder of the index root.
  ///
  /// Shared between Apex and SObject loading — both follow the same pattern of
  /// listing JSON files in a known directory, parsing each, and caching by
  /// lower-cased name.
  Future<Map<String, T>> _loadFromCache<T extends IndexedType>({
    required Map<Uri, Map<String, T>> cache,
    required Uri workspaceRoot,
    required String subFolder,
    required T? Function(Object? decoded) parse,
    void Function()? onDirectoryMissing,
    void Function(int loaded, int total)? onFileLoaded,
    void Function(String key)? onDuplicate,
    void Function(String path, Object error)? onError,
  }) async {
    if (cache.containsKey(workspaceRoot)) return cache[workspaceRoot]!;

    final rootPath = workspaceRoot.toFilePath(windows: _platform.isWindows);
    final indexDir = _fileSystem.directory(
      _fileSystem.path.join(rootPath, indexRootFolderName, subFolder),
    );

    if (!indexDir.existsSync()) {
      onDirectoryMissing?.call();
      return cache[workspaceRoot] = {};
    }

    final jsonFiles = indexDir
        .listSync(recursive: false, followLinks: false)
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.json'))
        .toList();

    final byName = <String, T>{};
    for (final file in jsonFiles) {
      try {
        if (!await file.exists()) continue;
        final decoded = jsonDecode(await file.readAsString());
        final entry = parse(decoded);
        if (entry == null) continue;
        final key = entry.name.value.toLowerCase();
        if (byName.containsKey(key)) onDuplicate?.call(key);
        byName[key] = entry;
      } catch (error) {
        onError?.call(file.path, error);
      }
    }

    onFileLoaded?.call(byName.length, jsonFiles.length);
    return cache[workspaceRoot] = byName;
  }

  IndexedSObject? _parseSObject(Map<String, dynamic> decoded) {
    final objectApiName = decoded['objectApiName'] as String?;
    if (objectApiName == null) return null;

    final metadata = decoded['objectMetadata'];
    if (metadata is! Map<String, dynamic>) return null;

    final rawFields = metadata['fields'];
    final fields = <FieldMember>[];
    if (rawFields is List) {
      for (final rawField in rawFields) {
        if (rawField is! Map<String, dynamic>) continue;
        final apiName = rawField['apiName'] as String?;
        if (apiName == null) continue;
        final type = rawField['type'] as String?;
        fields.add(
          FieldMember(
            DeclarationName(apiName),
            isStatic: false,
            visibility: AlwaysVisible(),
            typeName: type != null ? DeclarationName(type) : null,
          ),
        );
      }
    }

    return IndexedSObject(
      DeclarationName(objectApiName),
      fields: fields,
      visibility: AlwaysVisible(),
    );
  }

  IndexedType? _parseApex(Object? decoded) {
    if (decoded is! Map) return null;
    final typeMirror = decoded['typeMirror'];
    if (typeMirror is! Map) return null;

    final typeMirrorJson = typeMirror as Map<String, dynamic>;

    IndexedEnum fromEnumMirror(apex_reflection.EnumMirror mirror) =>
        IndexedEnum(
          DeclarationName(mirror.name),
          visibility: mirror.isAlwaysVisible ? AlwaysVisible() : NeverVisible(),
          values: mirror.values
              .map((value) => EnumValueMember(DeclarationName(value.name)))
              .toList(),
        );

    IndexedInterface fromInterfaceMirror(
      apex_reflection.InterfaceMirror mirror,
    ) =>
        // TODO: Parse and populate super
        IndexedInterface(
          DeclarationName(mirror.name),
          visibility: mirror.isAlwaysVisible ? AlwaysVisible() : NeverVisible(),
          methods: mirror.methods
              .map(
                (method) => MethodDeclaration(
                  DeclarationName(method.name),
                  body: Block.empty(),
                  isStatic: method.isStatic,
                  returnType: method.typeReference.rawDeclaration,
                  // Interface methods are always accessible
                  visibility: AlwaysVisible(),
                  parameters: method.parameters
                      .map(
                        (parameter) => (
                          type: parameter.typeReference.rawDeclaration,
                          name: parameter.name,
                        ),
                      )
                      .toList(),
                ),
              )
              .toList(),
          superInterface: null,
        );

    IndexedClass fromClassMirror(apex_reflection.ClassMirror mirror) =>
        IndexedClass(
          DeclarationName(mirror.name),
          visibility: mirror.isAlwaysVisible ? AlwaysVisible() : NeverVisible(),
          members: [
            ...mirror.classes.map(fromClassMirror),
            ...mirror.enums.map(fromEnumMirror),
            ...mirror.interfaces.map(fromInterfaceMirror),
            ...mirror.fields.map(
              (field) => FieldMember(
                DeclarationName(field.name),
                isStatic: field.isStatic,
                typeName: DeclarationName(field.typeReference.type),
                visibility: field.isAlwaysVisible
                    ? AlwaysVisible()
                    : NeverVisible(),
              ),
            ),
            ...mirror.properties.map(
              (property) => FieldMember(
                DeclarationName(property.name),
                isStatic: property.isStatic,
                typeName: DeclarationName(property.typeReference.type),
                visibility: property.isAlwaysVisible
                    ? AlwaysVisible()
                    : NeverVisible(),
              ),
            ),
            ...mirror.methods.map(
              (method) => MethodDeclaration(
                DeclarationName(method.name),
                body: Block.empty(),
                isStatic: method.isStatic,
                returnType: method.typeReference.rawDeclaration,
                visibility: method.isAlwaysVisible
                    ? AlwaysVisible()
                    : NeverVisible(),
                parameters: method.parameters
                    .map(
                      (parameter) => (
                        type: parameter.typeReference.rawDeclaration,
                        name: parameter.name,
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
          superClass: null, // TODO: Parse and populate superclass
        );

    return switch (typeMirrorJson['type_name']) {
      'enum' => fromEnumMirror(
        apex_reflection.EnumMirror.fromJson(typeMirrorJson),
      ),
      'class' => fromClassMirror(
        apex_reflection.ClassMirror.fromJson(typeMirrorJson),
      ),
      'interface' => fromInterfaceMirror(
        apex_reflection.InterfaceMirror.fromJson(typeMirrorJson),
      ),
      _ => null,
    };
  }
}

extension on apex_reflection.MemberModifiersAwareness {
  bool get isStatic =>
      memberModifiers.contains(apex_reflection.MemberModifier.static);
}

extension on apex_reflection.AccessModifierAwareness {
  bool get isAlwaysVisible => isPublic as bool || isGlobal as bool;
}
