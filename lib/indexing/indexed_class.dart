import 'package:apex_lsp/completion/completion.dart';
import 'package:apex_lsp/indexing/indexer.dart' as indexer;
import 'package:apex_lsp/type_name.dart';
import 'package:apex_reflection/apex_reflection.dart' as apex_reflection;

/// Contract for indexed classes completion data.
abstract class IndexedClassProvider {
  Iterable<String> get classNames;

  Future<IndexedType?> typeByNameAsync(String name);
}

/// Adapter to expose [ApexIndexer] as a [IndexedClassProvider].
final class ApexIndexerWorkspaceIndexAdapter implements IndexedClassProvider {
  ApexIndexerWorkspaceIndexAdapter(this._indexer);

  final indexer.ApexIndexer _indexer;

  @override
  Iterable<String> get classNames => _indexer.indexedClassNames;

  @override
  Future<IndexedType?> typeByNameAsync(String name) async {
    final parts = name.split('.');
    if (parts.isEmpty) return null;

    // Load the top-level type
    final topLevelTypeMirror = await _indexer.getIndexedClassInfo(parts[0]);
    if (topLevelTypeMirror == null) return null;

    IndexedType current = switch (topLevelTypeMirror) {
      indexer.ClassMirrorWrapper(:final typeMirror) => ClassMirrorWrapper(
        classMirror: typeMirror,
      ),
      indexer.EnumMirrorWrapper(:final typeMirror) => EnumMirrorWrapper(
        enumMirror: typeMirror,
      ),
      indexer.InterfaceMirrorWrapper(:final typeMirror) =>
        InterfaceMirrorWrapper(interfaceMirror: typeMirror),
    };

    if (parts.length == 1) {
      return current;
    }

    // Apex only supports up to one level of indexing, so we asume
    // that we can only take the second part when dealing with an inner
    // type.
    return current.nestedTypeByName(parts[1]);
  }
}

abstract class IndexedType {
  List<String> get memberNames;
  Future<List<String>> memberNamesByTypeAsync(
    MemberType type,
    IndexedClassProvider provider,
  );
  bool hasMemberPrefix(String prefix);

  /// Returns the names of nested types (inner classes, interfaces, enums).
  List<String> get nestedTypeNames;

  /// Returns a nested type by name, or null if not found.
  IndexedType? nestedTypeByName(String name);
}

/// Represents an indexed class.
class ClassMirrorWrapper implements IndexedType {
  ClassMirrorWrapper({required this.classMirror});

  final apex_reflection.ClassMirror classMirror;

  /// Combined member list.
  @override
  List<String> get memberNames {
    final all = <String>{
      ...classMirror.fields.map((f) => f.name),
      ...classMirror.properties.map((p) => p.name),
      ...classMirror.methods.map((m) => m.name),
    };
    return all.toList();
  }

  @override
  Future<List<String>> memberNamesByTypeAsync(
    MemberType type,
    IndexedClassProvider provider,
  ) async {
    final ownMembers = switch (type) {
      .static => [
        ...classMirror.fields.where((f) => f.isStatic).map((f) => f.name),
        ...classMirror.properties.where((f) => f.isStatic).map((f) => f.name),
        ...classMirror.methods.where((f) => f.isStatic).map((f) => f.name),
        ...nestedTypeNames,
      ],
      .instance => [
        ...classMirror.fields.where((f) => !f.isStatic).map((f) => f.name),
        ...classMirror.properties.where((f) => !f.isStatic).map((f) => f.name),
        ...classMirror.methods.where((f) => !f.isStatic).map((f) => f.name),
      ],
    };

    // Collect parent members
    final allMembers = <String>{...ownMembers};

    // Add members from parent class
    if (classMirror.extendedClass != null) {
      final parentType = await provider.typeByNameAsync(
        classMirror.extendedClass!,
      );
      if (parentType != null) {
        final parentMembers = await parentType.memberNamesByTypeAsync(
          type,
          provider,
        );
        allMembers.addAll(parentMembers);
      }
    }

    // Add members from implemented interfaces (instance members only)
    if (type == MemberType.instance) {
      for (final interfaceName in classMirror.implementedInterfaces) {
        final interfaceType = await provider.typeByNameAsync(interfaceName);
        if (interfaceType != null) {
          final interfaceMembers = await interfaceType.memberNamesByTypeAsync(
            type,
            provider,
          );
          allMembers.addAll(interfaceMembers);
        }
      }
    }

    return allMembers.toList();
  }

  @override
  bool hasMemberPrefix(String prefix) {
    return memberNames.any(
      (current) => DeclarationName(current).startsWith(prefix),
    );
  }

  @override
  List<String> get nestedTypeNames => [
    ...classMirror.classes.map((c) => c.name),
    ...classMirror.interfaces.map((i) => i.name),
    ...classMirror.enums.map((e) => e.name),
  ];

  @override
  IndexedType? nestedTypeByName(String name) {
    final target = DeclarationName(name);
    for (final c in classMirror.classes) {
      if (DeclarationName(c.name) == target) {
        return ClassMirrorWrapper(classMirror: c);
      }
    }
    for (final i in classMirror.interfaces) {
      if (DeclarationName(i.name) == target) {
        return InterfaceMirrorWrapper(interfaceMirror: i);
      }
    }
    for (final e in classMirror.enums) {
      if (DeclarationName(e.name) == target) {
        return EnumMirrorWrapper(enumMirror: e);
      }
    }
    return null;
  }
}

class EnumMirrorWrapper implements IndexedType {
  EnumMirrorWrapper({required this.enumMirror});

  final apex_reflection.EnumMirror enumMirror;

  /// Combined member list.
  @override
  List<String> get memberNames {
    final all = <String>{...enumMirror.values.map((v) => v.name)};
    return all.toList();
  }

  @override
  Future<List<String>> memberNamesByTypeAsync(
    MemberType type,
    IndexedClassProvider provider,
  ) async {
    return switch (type) {
      .static => [...enumMirror.values.map((v) => v.name)],
      .instance => [],
    };
  }

  @override
  bool hasMemberPrefix(String prefix) {
    return memberNames.any(
      (current) => DeclarationName(current).startsWith(prefix),
    );
  }

  @override
  List<String> get nestedTypeNames => const [];

  @override
  IndexedType? nestedTypeByName(String name) => null;
}

class InterfaceMirrorWrapper implements IndexedType {
  InterfaceMirrorWrapper({required this.interfaceMirror});

  final apex_reflection.InterfaceMirror interfaceMirror;

  @override
  List<String> get memberNames {
    final all = <String>{...interfaceMirror.methods.map((m) => m.name)};
    return all.toList();
  }

  @override
  Future<List<String>> memberNamesByTypeAsync(
    MemberType type,
    IndexedClassProvider provider,
  ) async {
    return switch (type) {
      .static => [],
      .instance => [...interfaceMirror.methods.map((m) => m.name)],
    };
  }

  @override
  bool hasMemberPrefix(String prefix) {
    return memberNames.any(
      (current) => DeclarationName(current).startsWith(prefix),
    );
  }

  @override
  List<String> get nestedTypeNames => const [];

  @override
  IndexedType? nestedTypeByName(String name) => null;
}

extension on apex_reflection.MemberModifiersAwareness {
  bool get isStatic =>
      memberModifiers.contains(apex_reflection.MemberModifier.static);
}
