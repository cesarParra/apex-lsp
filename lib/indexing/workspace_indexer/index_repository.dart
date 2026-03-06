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

/// An in-memory cache for index entries of type [T].
/// The cache is populated lazily on the first [load] call for a given root.
final class _IndexCache<T extends IndexedType> {
  _IndexCache({
    required this.subFolder,
    required this.parse,
    required FileSystem fileSystem,
    required LspPlatform platform,
    IndexReadErrorLog? onError,
  }) : _fileSystem = fileSystem,
       _platform = platform,
       _onError = onError;

  final String subFolder;
  final T? Function(Object? decoded) parse;
  final FileSystem _fileSystem;
  final LspPlatform _platform;
  final IndexReadErrorLog? _onError;

  final Map<Uri, Map<String, T>> _store = {};

  /// Returns the cached entries for [workspaceRoot], loading from disk if
  /// this is the first access for that root.
  Future<Map<String, T>> load(Uri workspaceRoot) async {
    if (_store.containsKey(workspaceRoot)) return _store[workspaceRoot]!;

    final rootPath = workspaceRoot.toFilePath(windows: _platform.isWindows);
    final indexDir = _fileSystem.directory(
      _fileSystem.path.join(rootPath, indexRootFolderName, subFolder),
    );

    if (!indexDir.existsSync()) {
      return _store[workspaceRoot] = {};
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
        byName[entry.name.value.toLowerCase()] = entry;
      } catch (error) {
        _onError?.call(file.path, error);
      }
    }

    return _store[workspaceRoot] = byName;
  }

  /// Reads [jsonFileUri] from disk and inserts or replaces the entry in the
  /// cache for [workspaceRoot].
  ///
  /// No-op if the cache for [workspaceRoot] has not been loaded yet, because
  /// the next full [load] will pick up the file directly from disk.
  Future<void> upsert(Uri jsonFileUri, Uri workspaceRoot) async {
    final cache = _store[workspaceRoot];
    if (cache == null) return;

    final file = _fileSystem.file(
      jsonFileUri.toFilePath(windows: _platform.isWindows),
    );
    try {
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      final entry = parse(decoded);
      if (entry == null) return;
      cache[entry.name.value.toLowerCase()] = entry;
    } catch (error) {
      _onError?.call(file.path, error);
    }
  }

  /// Removes the entry for [name] from the cache for [workspaceRoot].
  ///
  /// No-op if the cache has not been loaded yet or the name is absent.
  void evict(String name, Uri workspaceRoot) {
    _store[workspaceRoot]?.remove(name.toLowerCase());
  }
}

final class IndexRepository {
  IndexRepository({
    required FileSystem fileSystem,
    required LspPlatform platform,
    required List<Uri> workspaceRootUris,
    IndexReadErrorLog? onError,
  }) : _workspaceRootUris = workspaceRootUris,
       _apexCache = _IndexCache(
         subFolder: apexIndexFolderName,
         parse: _parseApex,
         fileSystem: fileSystem,
         platform: platform,
         onError: onError,
       ),
       _sobjectCache = _IndexCache(
         subFolder: sobjectIndexFolderName,
         parse: _parseSObjectEntry,
         fileSystem: fileSystem,
         platform: platform,
         onError: onError,
       );

  final List<Uri> _workspaceRootUris;
  final _IndexCache<IndexedType> _apexCache;
  final _IndexCache<IndexedSObject> _sobjectCache;

  Future<List<IndexedType>> getDeclarations() async {
    final declarations = <IndexedType>[];
    for (final root in _workspaceRootUris) {
      declarations.addAll((await _apexCache.load(root)).values);
      declarations.addAll((await _sobjectCache.load(root)).values);
    }
    return declarations;
  }

  Future<IndexedType?> getIndexedType(String typeName) async {
    if (typeName.isEmpty) return null;
    final key = typeName.toLowerCase();

    for (final root in _workspaceRootUris) {
      final apex = await _apexCache.load(root);
      if (apex.containsKey(key)) return apex[key];

      final sobjects = await _sobjectCache.load(root);
      if (sobjects.containsKey(key)) return sobjects[key];
    }

    return null;
  }

  /// Reads [jsonFileUri] from disk, parses it, and inserts or replaces the
  /// corresponding entry in the in-memory Apex cache for [workspaceRoot].
  ///
  /// If the cache for [workspaceRoot] has not been loaded yet, this is a
  /// no-op: the full directory load triggered by the next [getDeclarations]
  /// call will already include the up-to-date file.
  Future<void> upsertFromFile(Uri jsonFileUri, Uri workspaceRoot) =>
      _apexCache.upsert(jsonFileUri, workspaceRoot);

  /// Removes the entry for [typeName] from the in-memory Apex cache for
  /// [workspaceRoot].
  ///
  /// If the cache for [workspaceRoot] has not been loaded yet, this is a
  /// no-op.
  void evict(String typeName, Uri workspaceRoot) =>
      _apexCache.evict(typeName, workspaceRoot);

  /// Reads [jsonFileUri] from disk, parses it, and inserts or replaces the
  /// corresponding entry in the in-memory SObject cache for [workspaceRoot].
  ///
  /// If the cache for [workspaceRoot] has not been loaded yet, this is a
  /// no-op: the full directory load triggered by the next [getDeclarations]
  /// call will already include the up-to-date file.
  Future<void> upsertSObjectFromFile(Uri jsonFileUri, Uri workspaceRoot) =>
      _sobjectCache.upsert(jsonFileUri, workspaceRoot);

  /// Removes the entry for [objectName] from the in-memory SObject cache for
  /// [workspaceRoot].
  ///
  /// If the cache for [workspaceRoot] has not been loaded yet, this is a
  /// no-op.
  void evictSObject(String objectName, Uri workspaceRoot) =>
      _sobjectCache.evict(objectName, workspaceRoot);
}

IndexedSObject? _parseSObjectEntry(Object? decoded) {
  if (decoded is! Map<String, dynamic>) return null;
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

  IndexedEnum fromEnumMirror(apex_reflection.EnumMirror mirror) => IndexedEnum(
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
        extendedInterfaces: mirror.extendedInterfaces,
      );

  IndexedClass fromClassMirror(
    apex_reflection.ClassMirror mirror,
  ) => IndexedClass(
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
          visibility: field.isAlwaysVisible ? AlwaysVisible() : NeverVisible(),
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
          visibility: method.isAlwaysVisible ? AlwaysVisible() : NeverVisible(),
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

extension on apex_reflection.MemberModifiersAwareness {
  bool get isStatic =>
      memberModifiers.contains(apex_reflection.MemberModifier.static);
}

extension on apex_reflection.AccessModifierAwareness {
  bool get isAlwaysVisible => isPublic as bool || isGlobal as bool;
}
