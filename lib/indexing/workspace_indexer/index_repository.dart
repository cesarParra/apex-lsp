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
  final Map<Uri, Map<String, IndexedType>> _cache = {};

  Future<List<IndexedType>> getDeclarations() async {
    final declarations = <IndexedType>[];
    for (final root in _workspaceRootUris) {
      final indexedTypes = await _loadForWorkspace(root);
      declarations.addAll(indexedTypes.values);
    }
    return declarations;
  }

  Future<IndexedType?> getIndexedType(String typeName) async {
    if (typeName.isEmpty) return null;

    for (final root in _workspaceRootUris) {
      final indexedTypes = await _loadForWorkspace(root);
      final result = indexedTypes[typeName.toLowerCase()];
      if (result != null) return result;
    }

    return null;
  }

  Future<Map<String, IndexedType>> _loadForWorkspace(Uri workspaceRoot) async {
    if (_cache.containsKey(workspaceRoot)) return _cache[workspaceRoot]!;

    final rootPath = workspaceRoot.toFilePath(windows: _platform.isWindows);
    final indexDir = _fileSystem.directory(
      _fileSystem.path.join(rootPath, indexRootFolderName, apexIndexFolderName),
    );
    if (!indexDir.existsSync()) {
      _log?.call('Index directory does not exist: ${indexDir.path}');
      return _cache[workspaceRoot] = {};
    }

    final allFiles = indexDir.listSync(recursive: false, followLinks: false);
    final jsonFiles = allFiles
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.json'))
        .toList();

    _log?.call('Found ${jsonFiles.length} JSON files in ${indexDir.path}');

    final indexedTypesByName = <String, IndexedType>{};
    for (final file in jsonFiles) {
      try {
        if (!await file.exists()) {
          _log?.call('File does not exist: ${file.path}');
          continue;
        }

        final content = await file.readAsString();
        final decoded = jsonDecode(content);
        final indexedType = _parse(decoded);
        if (indexedType == null) {
          final typeMirror = decoded is Map ? decoded['typeMirror'] : null;
          final typeNameValue = typeMirror is Map
              ? typeMirror['type_name']
              : 'unknown';
          _log?.call(
            'SKIPPED ${file.path}: '
            '_parse returned null '
            '(type_name=$typeNameValue)',
          );
          continue;
        }
        final key = indexedType.name.value.toLowerCase();
        if (indexedTypesByName.containsKey(key)) {
          _log?.call(
            'DUPLICATE key "$key": '
            '${file.path} overwrites previous entry',
          );
        }
        indexedTypesByName[key] = indexedType;
      } catch (error) {
        _log?.call('ERROR reading ${file.path}: $error');
      }
    }

    _log?.call(
      'Loaded ${indexedTypesByName.length} types from ${jsonFiles.length} files',
    );

    _cache[workspaceRoot] = indexedTypesByName;
    return indexedTypesByName;
  }

  IndexedType? _parse(Object? decoded) {
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
