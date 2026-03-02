import 'dart:convert';

import 'package:apex_lsp/indexing/declarations.dart';
import 'package:apex_lsp/indexing/index_paths.dart';
import 'package:apex_lsp/indexing/workspace_indexer/index_repository.dart';
import 'package:apex_lsp/utils/platform.dart';
import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:test/test.dart';

final class _FakePlatform implements LspPlatform {
  @override
  final bool isWindows = false;

  @override
  final String pathSeparator = '/';
}

/// Minimal valid ApexIndexEntry JSON for a class named [className].
Map<String, Object?> _apexJson(String className) => {
  'schemaVersion': 1,
  'className': className,
  'source': {
    'uri': 'file:///repo/$className.cls',
    'relativePath': '$className.cls',
  },
  'typeMirror': {
    'type_name': 'class',
    'name': className,
    'annotations': <Object?>[],
    'modifiers': <Object?>[],
    'memberModifiers': <Object?>[],
    'interfaces': <Object?>[],
    'classes': <Object?>[],
    'enums': <Object?>[],
    'interfaces_': <Object?>[],
    'fields': <Object?>[],
    'properties': <Object?>[],
    'methods': <Object?>[],
    'constructors': <Object?>[],
  },
};

/// Minimal valid SObjectIndexEntry JSON for an object named [objectName].
Map<String, Object?> _sobjectJson(
  String objectName, {
  List<Map<String, Object?>> fields = const [],
}) => {
  'schemaVersion': 1,
  'objectApiName': objectName,
  'source': {
    'objectMetaUri':
        'file:///repo/objects/$objectName/$objectName.object-meta.xml',
    'relativePath': 'objects/$objectName',
  },
  'objectMetadata': {
    'apiName': objectName,
    'label': objectName,
    'pluralLabel': '${objectName}s',
    'description': null,
    'fields': fields,
  },
};

void main() {
  late FileSystem fs;
  late _FakePlatform platform;
  late Directory workspaceRoot;
  late Uri workspaceUri;
  late Directory apexIndexDir;
  late Directory sobjectIndexDir;

  setUp(() {
    fs = MemoryFileSystem();
    platform = _FakePlatform();
    workspaceRoot = fs.directory('/repo')..createSync();
    workspaceUri = Uri.directory(workspaceRoot.path);
    apexIndexDir = fs.directory(
      fs.path.join(
        workspaceRoot.path,
        indexRootFolderName,
        apexIndexFolderName,
      ),
    )..createSync(recursive: true);
    sobjectIndexDir = fs.directory(
      fs.path.join(
        workspaceRoot.path,
        indexRootFolderName,
        sobjectIndexFolderName,
      ),
    )..createSync(recursive: true);
  });

  IndexRepository makeRepository() => IndexRepository(
    fileSystem: fs,
    platform: platform,
    workspaceRootUris: [workspaceUri],
  );

  group('IndexRepository.upsertFromFile', () {
    test('inserts a new entry when the cache is already populated', () async {
      // Prime the cache with an empty workspace (no JSON files yet).
      final repo = makeRepository();
      final before = await repo.getDeclarations();
      expect(before, isEmpty);

      // Write a JSON file and upsert it.
      apexIndexDir
          .childFile('Widget.json')
          .writeAsStringSync(jsonEncode(_apexJson('Widget')));
      await repo.upsertFromFile(
        Uri.file(apexIndexDir.childFile('Widget.json').path),
        workspaceUri,
      );

      final after = await repo.getDeclarations();
      expect(after.map((d) => d.name.value), contains('Widget'));
    });

    test('replaces an existing entry with updated content', () async {
      // Seed the index with Widget as a class.
      apexIndexDir
          .childFile('Widget.json')
          .writeAsStringSync(jsonEncode(_apexJson('Widget')));

      final repo = makeRepository();
      final before = await repo.getDeclarations();
      expect(
        before.whereType<IndexedClass>().map((d) => d.name.value),
        contains('Widget'),
      );
      expect(before.whereType<IndexedEnum>(), isEmpty);

      // Update the JSON on disk so Widget is now an enum.
      final updatedJson = _apexJson('Widget');
      (updatedJson['typeMirror'] as Map<String, Object?>)['type_name'] = 'enum';
      (updatedJson['typeMirror'] as Map<String, Object?>)['values'] =
          <Object?>[];
      apexIndexDir
          .childFile('Widget.json')
          .writeAsStringSync(jsonEncode(updatedJson));

      await repo.upsertFromFile(
        Uri.file(apexIndexDir.childFile('Widget.json').path),
        workspaceUri,
      );

      final after = await repo.getDeclarations();
      // The old IndexedClass entry must be gone; an IndexedEnum must be present.
      expect(
        after.whereType<IndexedClass>().map((d) => d.name.value),
        isNot(contains('Widget')),
      );
      expect(
        after.whereType<IndexedEnum>().map((d) => d.name.value),
        contains('Widget'),
      );
    });

    test(
      'is a no-op when the cache for that root has never been loaded',
      () async {
        // Do NOT call getDeclarations() here (the cache is unpopulated).
        final repo = makeRepository();

        // Write a JSON file and upsert, which should not throw.
        apexIndexDir
            .childFile('Widget.json')
            .writeAsStringSync(jsonEncode(_apexJson('Widget')));
        await expectLater(
          repo.upsertFromFile(
            Uri.file(apexIndexDir.childFile('Widget.json').path),
            workspaceUri,
          ),
          completes,
        );

        // On first full load, the entry is present (disk was already written).
        final declarations = await repo.getDeclarations();
        expect(declarations.map((d) => d.name.value), contains('Widget'));
      },
    );
  });

  group('IndexRepository.evict', () {
    test('removes an existing entry from the cache', () async {
      apexIndexDir
          .childFile('Widget.json')
          .writeAsStringSync(jsonEncode(_apexJson('Widget')));

      final repo = makeRepository();
      final before = await repo.getDeclarations();
      expect(before.map((d) => d.name.value), contains('Widget'));

      repo.evict('Widget', workspaceUri);

      final after = await repo.getDeclarations();
      expect(after.map((d) => d.name.value), isNot(contains('Widget')));
    });

    test('is a no-op when the entry does not exist', () async {
      final repo = makeRepository();
      await repo.getDeclarations(); // prime cache

      // Should not throw.
      expect(() => repo.evict('NonExistent', workspaceUri), returnsNormally);
    });

    test(
      'is a no-op when the cache for that root has never been loaded',
      () async {
        final repo = makeRepository();

        // Should not throw even though cache is empty.
        expect(() => repo.evict('Widget', workspaceUri), returnsNormally);
      },
    );
  });

  group('IndexRepository.upsertSObjectFromFile', () {
    test(
      'inserts a new SObject entry when the cache is already populated',
      () async {
        final repo = makeRepository();
        final before = await repo.getDeclarations();
        expect(before, isEmpty);

        sobjectIndexDir
            .childFile('Account.json')
            .writeAsStringSync(jsonEncode(_sobjectJson('Account')));
        await repo.upsertSObjectFromFile(
          Uri.file(sobjectIndexDir.childFile('Account.json').path),
          workspaceUri,
        );

        final after = await repo.getDeclarations();
        expect(
          after.whereType<IndexedSObject>().map((d) => d.name.value),
          contains('Account'),
        );
      },
    );

    test('replaces an existing SObject entry with updated content', () async {
      sobjectIndexDir
          .childFile('Account.json')
          .writeAsStringSync(jsonEncode(_sobjectJson('Account')));

      final repo = makeRepository();
      final before = await repo.getDeclarations();
      final account = before.whereType<IndexedSObject>().firstWhere(
        (d) => d.name.value == 'Account',
      );
      expect(account.fields, isEmpty);

      // Update with a new field.
      sobjectIndexDir
          .childFile('Account.json')
          .writeAsStringSync(
            jsonEncode(
              _sobjectJson(
                'Account',
                fields: [
                  {
                    'apiName': 'Industry__c',
                    'label': 'Industry',
                    'type': 'Picklist',
                    'description': null,
                  },
                ],
              ),
            ),
          );
      await repo.upsertSObjectFromFile(
        Uri.file(sobjectIndexDir.childFile('Account.json').path),
        workspaceUri,
      );

      final after = await repo.getDeclarations();
      final updated = after.whereType<IndexedSObject>().firstWhere(
        (d) => d.name.value == 'Account',
      );
      expect(updated.fields.map((f) => f.name.value), contains('Industry__c'));
    });

    test(
      'is a no-op when the cache for that root has never been loaded',
      () async {
        final repo = makeRepository();

        sobjectIndexDir
            .childFile('Account.json')
            .writeAsStringSync(jsonEncode(_sobjectJson('Account')));
        await expectLater(
          repo.upsertSObjectFromFile(
            Uri.file(sobjectIndexDir.childFile('Account.json').path),
            workspaceUri,
          ),
          completes,
        );

        // On first full load, the entry is present (disk was already written).
        final declarations = await repo.getDeclarations();
        expect(
          declarations.whereType<IndexedSObject>().map((d) => d.name.value),
          contains('Account'),
        );
      },
    );
  });

  group('IndexRepository.evictSObject', () {
    test('removes an existing SObject entry from the cache', () async {
      sobjectIndexDir
          .childFile('Account.json')
          .writeAsStringSync(jsonEncode(_sobjectJson('Account')));

      final repo = makeRepository();
      final before = await repo.getDeclarations();
      expect(
        before.whereType<IndexedSObject>().map((d) => d.name.value),
        contains('Account'),
      );

      repo.evictSObject('Account', workspaceUri);

      final after = await repo.getDeclarations();
      expect(
        after.whereType<IndexedSObject>().map((d) => d.name.value),
        isNot(contains('Account')),
      );
    });

    test('is a no-op when the entry does not exist', () async {
      final repo = makeRepository();
      await repo.getDeclarations(); // prime cache

      expect(
        () => repo.evictSObject('NonExistent', workspaceUri),
        returnsNormally,
      );
    });

    test(
      'is a no-op when the cache for that root has never been loaded',
      () async {
        final repo = makeRepository();
        expect(
          () => repo.evictSObject('Account', workspaceUri),
          returnsNormally,
        );
      },
    );
  });
}
