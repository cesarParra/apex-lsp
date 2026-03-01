import 'dart:convert';

import 'package:apex_lsp/indexing/declarations.dart';
import 'package:apex_lsp/indexing/index_paths.dart';
import 'package:apex_lsp/indexing/workspace_indexer/apex_index_entry.dart';
import 'package:apex_lsp/indexing/workspace_indexer/sobject_index_entry.dart';
import 'package:apex_lsp/type_name.dart';
import 'package:apex_lsp/utils/platform.dart';
import 'package:apex_reflection/apex_reflection.dart' as apex_reflection;
import 'package:file/file.dart';

/// Callback invoked when a JSON index file cannot be read or parsed.
typedef IndexReadErrorLog = void Function(String path, Object error);

final class IndexRepository {
  IndexRepository({
    required FileSystem fileSystem,
    required LspPlatform platform,
    required List<Uri> workspaceRootUris,
    IndexReadErrorLog? onError,
  }) : _fileSystem = fileSystem,
       _platform = platform,
       _workspaceRootUris = workspaceRootUris,
       _onError = onError;

  final FileSystem _fileSystem;
  final LspPlatform _platform;
  final List<Uri> _workspaceRootUris;
  final IndexReadErrorLog? _onError;

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
      parse: _parseApex,
      onError: _onError,
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
      onError: _onError,
    );
  }

  /// Loads and caches typed index entries from a subfolder of the index root.
  Future<Map<String, T>> _loadFromCache<T extends IndexedType>({
    required Map<Uri, Map<String, T>> cache,
    required Uri workspaceRoot,
    required String subFolder,
    required T? Function(Object? decoded) parse,
    IndexReadErrorLog? onError,
  }) async {
    if (cache.containsKey(workspaceRoot)) return cache[workspaceRoot]!;

    final rootPath = workspaceRoot.toFilePath(windows: _platform.isWindows);
    final indexDir = _fileSystem.directory(
      _fileSystem.path.join(rootPath, indexRootFolderName, subFolder),
    );

    if (!indexDir.existsSync()) {
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
        byName[key] = entry;
      } catch (error) {
        onError?.call(file.path, error);
      }
    }

    return cache[workspaceRoot] = byName;
  }

  IndexedSObject? _parseSObject(Map<String, dynamic> decoded) {
    final entry = SObjectIndexEntry.fromJson(decoded);
    final fields = entry.objectMetadata.fields
        .map(
          (field) => FieldMember(
            DeclarationName(field.apiName),
            isStatic: false,
            visibility: AlwaysVisible(),
            typeName: field.type != null ? DeclarationName(field.type!) : null,
          ),
        )
        .toList();

    return IndexedSObject(
      DeclarationName(entry.objectApiName),
      fields: fields,
      visibility: AlwaysVisible(),
    );
  }

  IndexedType? _parseApex(Object? decoded) {
    if (decoded is! Map<String, dynamic>) return null;
    final entry = ApexIndexEntry.fromJson(decoded);
    final typeMirrorJson = entry.typeMirror;

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
