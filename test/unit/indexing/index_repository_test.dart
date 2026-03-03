import 'dart:convert';

import 'package:apex_lsp/indexing/declarations.dart';
import 'package:apex_lsp/indexing/index_paths.dart';
import 'package:apex_lsp/indexing/sfdx_workspace_locator.dart';
import 'package:apex_lsp/indexing/workspace_indexer/workspace_indexer.dart';
import 'package:apex_lsp/message.dart';
import 'package:apex_lsp/type_name.dart';

import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:test/test.dart';

import '../../support/fake_platform.dart';

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
  group('cache lifecycle', () {
    late FileSystem fs;
    late FakeLspPlatform platform;
    late Directory workspaceRoot;
    late Uri workspaceUri;
    late Directory apexIndexDir;
    late Directory sobjectIndexDir;

    setUp(() {
      fs = MemoryFileSystem();
      platform = FakeLspPlatform();
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

    group('upsertFromFile', () {
      test('inserts a new entry when the cache is already populated', () async {
        final repo = makeRepository();
        final before = await repo.getDeclarations();
        expect(before, isEmpty);

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

        final updatedJson = _apexJson('Widget');
        (updatedJson['typeMirror'] as Map<String, Object?>)['type_name'] =
            'enum';
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
          final repo = makeRepository();

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

          final declarations = await repo.getDeclarations();
          expect(declarations.map((d) => d.name.value), contains('Widget'));
        },
      );
    });

    group('evict', () {
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
        await repo.getDeclarations();

        expect(() => repo.evict('NonExistent', workspaceUri), returnsNormally);
      });

      test(
        'is a no-op when the cache for that root has never been loaded',
        () async {
          final repo = makeRepository();

          expect(() => repo.evict('Widget', workspaceUri), returnsNormally);
        },
      );
    });

    group('upsertSObjectFromFile', () {
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
        expect(
          updated.fields.map((f) => f.name.value),
          contains('Industry__c'),
        );
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

          final declarations = await repo.getDeclarations();
          expect(
            declarations.whereType<IndexedSObject>().map((d) => d.name.value),
            contains('Account'),
          );
        },
      );
    });

    group('evictSObject', () {
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
        await repo.getDeclarations();

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
  });

  group('declaration content', () {
    late FileSystem fs;
    late FakeLspPlatform platform;
    late Directory workspaceRoot;
    late Uri workspaceUri;

    setUp(() {
      fs = MemoryFileSystem();
      platform = FakeLspPlatform();
      workspaceRoot = fs.directory('/repo')..createSync();
      workspaceUri = Uri.directory(workspaceRoot.path);
    });

    /// Runs the workspace indexer to produce `.sf-zed` metadata from `.cls`
    /// source strings, then returns the resulting [IndexRepository].
    Future<IndexRepository> indexAndCreateRepository({
      required List<({String name, String source})> classFiles,
    }) async {
      workspaceRoot
          .childFile('sfdx-project.json')
          .writeAsStringSync(
            jsonEncode({
              'packageDirectories': [
                {'path': 'force-app', 'default': true},
              ],
            }),
          );

      final classesDir = fs.directory('/repo/force-app/main/default/classes')
        ..createSync(recursive: true);

      for (final classFile in classFiles) {
        classesDir
            .childFile(classFile.name)
            .writeAsStringSync(classFile.source);
      }

      final indexer = WorkspaceIndexer(
        sfdxWorkspaceLocator: SfdxWorkspaceLocator(
          fileSystem: fs,
          platform: platform,
        ),
        fileSystem: fs,
        platform: platform,
      );

      await indexer
          .index(
            InitializedParams([
              WorkspaceFolder(workspaceUri.toString(), 'repo'),
            ]),
            token: ProgressToken.string('test-token'),
          )
          .drain<void>();

      return indexer.getIndexLoader()!;
    }

    group('enums', () {
      test('indexes top level enums', () async {
        final repository = await indexAndCreateRepository(
          classFiles: [
            (
              name: 'Season.cls',
              source: 'public enum Season { SPRING, SUMMER, FALL, WINTER }',
            ),
          ],
        );

        final result = await repository.getIndexedType('Season');

        expect(result, isA<IndexedEnum>());
        expect(result!.name, equals(DeclarationName('Season')));
      });

      test('indexes enum values', () async {
        final repository = await indexAndCreateRepository(
          classFiles: [
            (
              name: 'Season.cls',
              source: 'public enum Season { SPRING, SUMMER, FALL, WINTER }',
            ),
          ],
        );

        final result = await repository.getIndexedType('Season') as IndexedEnum;

        expect(
          result.values.map((value) => value.name.value).toList(),
          equals(['SPRING', 'SUMMER', 'FALL', 'WINTER']),
        );
      });
    });

    group('interfaces', () {
      test('indexes top level interfaces', () async {
        final repository = await indexAndCreateRepository(
          classFiles: [
            (
              name: 'Greeter.cls',
              source:
                  'public interface Greeter { String greet(); void sayGoodbye(); }',
            ),
          ],
        );

        final result = await repository.getIndexedType('Greeter');

        expect(result, isA<IndexedInterface>());
        expect(result!.name, equals(DeclarationName('Greeter')));
      });

      test('indexes interface methods', () async {
        final repository = await indexAndCreateRepository(
          classFiles: [
            (
              name: 'Greeter.cls',
              source:
                  'public interface Greeter { String greet(); void sayGoodbye(); }',
            ),
          ],
        );

        final result =
            await repository.getIndexedType('Greeter') as IndexedInterface;

        expect(
          result.methods.map((method) => method.name.value).toList(),
          equals(['greet', 'sayGoodbye']),
        );
      });

      test('captures interface method signatures', () async {
        final repository = await indexAndCreateRepository(
          classFiles: [
            (
              name: 'Greeter.cls',
              source:
                  'public interface Greeter { String greet(String name); void sayGoodbye(); }',
            ),
          ],
        );

        final result =
            await repository.getIndexedType('Greeter') as IndexedInterface;
        final greet = result.methods.firstWhere(
          (method) => method.name.value == 'greet',
        );
        final goodbye = result.methods.firstWhere(
          (method) => method.name.value == 'sayGoodbye',
        );

        expect(greet.returnType, 'String');
        expect(greet.parameters, [(type: 'String', name: 'name')]);
        expect(goodbye.returnType, 'void');
        expect(goodbye.parameters, isEmpty);
      });
    });

    group('classes', () {
      test('indexes top level classes', () async {
        final repository = await indexAndCreateRepository(
          classFiles: [
            (name: 'Account.cls', source: 'public class Account {}'),
          ],
        );

        final result = await repository.getIndexedType('Account');

        expect(result, isA<IndexedClass>());
        expect(result!.name, equals(DeclarationName('Account')));
      });

      test('indexes static class fields', () async {
        final repository = await indexAndCreateRepository(
          classFiles: [
            (
              name: 'Foo.cls',
              source: 'public class Foo { static String bar; }',
            ),
          ],
        );

        final result = await repository.getIndexedType('Foo') as IndexedClass;
        final field = result.members.whereType<FieldMember>().first;

        expect(field.name, equals(DeclarationName('bar')));
        expect(field.isStatic, isTrue);
      });

      test('sets visibility for private fields', () async {
        final repository = await indexAndCreateRepository(
          classFiles: [
            (
              name: 'Foo.cls',
              source: 'public class Foo { static String bar; }',
            ),
          ],
        );

        final result = await repository.getIndexedType('Foo') as IndexedClass;
        final field = result.members.whereType<FieldMember>().first;

        expect(field.visibility, isA<NeverVisible>());
      });

      test('indexes instance class fields', () async {
        final repository = await indexAndCreateRepository(
          classFiles: [
            (name: 'Foo.cls', source: 'public class Foo { String bar; }'),
          ],
        );

        final result = await repository.getIndexedType('Foo') as IndexedClass;
        final field = result.members.whereType<FieldMember>().first;

        expect(field.name, equals(DeclarationName('bar')));
        expect(field.isStatic, isFalse);
      });

      test('indexes field type name', () async {
        final repository = await indexAndCreateRepository(
          classFiles: [
            (name: 'Foo.cls', source: 'public class Foo { String bar; }'),
          ],
        );

        final result = await repository.getIndexedType('Foo') as IndexedClass;
        final field = result.members.whereType<FieldMember>().first;

        expect(field.typeName, equals(DeclarationName('String')));
      });

      test('indexes property type name', () async {
        final repository = await indexAndCreateRepository(
          classFiles: [
            (
              name: 'Foo.cls',
              source: 'public class Foo { public String bar { get; set; } }',
            ),
          ],
        );

        final result = await repository.getIndexedType('Foo') as IndexedClass;
        final field = result.members.whereType<FieldMember>().first;

        expect(field.typeName, equals(DeclarationName('String')));
      });

      test('indexes class properties as fields', () async {
        final repository = await indexAndCreateRepository(
          classFiles: [
            (
              name: 'Foo.cls',
              source: 'public class Foo { public String bar { get; set; } }',
            ),
          ],
        );

        final result = await repository.getIndexedType('Foo') as IndexedClass;
        final field = result.members.whereType<FieldMember>().first;

        expect(field.name, equals(DeclarationName('bar')));
      });

      test('indexes static class methods', () async {
        final repository = await indexAndCreateRepository(
          classFiles: [
            (
              name: 'Foo.cls',
              source: 'public class Foo { static void doWork() {} }',
            ),
          ],
        );

        final result = await repository.getIndexedType('Foo') as IndexedClass;
        final method = result.members.whereType<MethodDeclaration>().first;

        expect(method.name, equals(DeclarationName('doWork')));
        expect(method.isStatic, isTrue);
      });

      test('sets visibility for private methods', () async {
        final repository = await indexAndCreateRepository(
          classFiles: [
            (
              name: 'Foo.cls',
              source: 'public class Foo { static void doWork() {} }',
            ),
          ],
        );

        final result = await repository.getIndexedType('Foo') as IndexedClass;
        final method = result.members.whereType<MethodDeclaration>().first;

        expect(method.visibility, isA<NeverVisible>());
      });

      test('captures class method signatures', () async {
        final repository = await indexAndCreateRepository(
          classFiles: [
            (
              name: 'Foo.cls',
              source:
                  'public class Foo { static Integer doWork(String name, Integer count) { return count; } }',
            ),
          ],
        );

        final result = await repository.getIndexedType('Foo') as IndexedClass;
        final method = result.members.whereType<MethodDeclaration>().first;

        expect(method.returnType, 'Integer');
        expect(method.parameters, [
          (type: 'String', name: 'name'),
          (type: 'Integer', name: 'count'),
        ]);
      });

      test('indexes instance class methods', () async {
        final repository = await indexAndCreateRepository(
          classFiles: [
            (name: 'Foo.cls', source: 'public class Foo { void doWork() {} }'),
          ],
        );

        final result = await repository.getIndexedType('Foo') as IndexedClass;
        final method = result.members.whereType<MethodDeclaration>().first;

        expect(method.name, equals(DeclarationName('doWork')));
        expect(method.isStatic, isFalse);
      });

      test('indexes inner classes as members', () async {
        final repository = await indexAndCreateRepository(
          classFiles: [
            (
              name: 'Foo.cls',
              source:
                  'public class Foo { public class Bar { String name; void doWork() {} } }',
            ),
          ],
        );

        final result = await repository.getIndexedType('Foo') as IndexedClass;
        final innerClasses = result.members.whereType<IndexedClass>().toList();

        expect(innerClasses, hasLength(1));
        expect(innerClasses.first.name, equals(DeclarationName('Bar')));
        expect(innerClasses.first.members, hasLength(2));
      });

      test('sets visibility for inner classes', () async {
        final repository = await indexAndCreateRepository(
          classFiles: [
            (
              name: 'Foo.cls',
              source: 'public class Foo { private class Bar { } }',
            ),
          ],
        );

        final result = await repository.getIndexedType('Foo') as IndexedClass;
        final innerClasses = result.members.whereType<IndexedClass>().toList();

        expect(innerClasses, hasLength(1));
        expect(innerClasses.first.visibility, isA<NeverVisible>());
      });

      test('indexes inner interfaces as members', () async {
        final repository = await indexAndCreateRepository(
          classFiles: [
            (
              name: 'Foo.cls',
              source:
                  'public class Foo { public interface Bar { void doWork(); String getName(); } }',
            ),
          ],
        );

        final result = await repository.getIndexedType('Foo') as IndexedClass;
        final innerInterfaces = result.members
            .whereType<IndexedInterface>()
            .toList();

        expect(innerInterfaces, hasLength(1));
        expect(innerInterfaces.first.name, equals(DeclarationName('Bar')));
        expect(innerInterfaces.first.methods, hasLength(2));
      });

      test('sets visibility for inner interfaces', () async {
        final repository = await indexAndCreateRepository(
          classFiles: [
            (
              name: 'Foo.cls',
              source:
                  'public class Foo { private interface Bar { void doWork(); String getName(); } }',
            ),
          ],
        );

        final result = await repository.getIndexedType('Foo') as IndexedClass;
        final innerInterfaces = result.members
            .whereType<IndexedInterface>()
            .toList();

        expect(innerInterfaces, hasLength(1));
        expect(innerInterfaces.first.visibility, isA<NeverVisible>());
      });

      test('indexes inner enums as members', () async {
        final repository = await indexAndCreateRepository(
          classFiles: [
            (
              name: 'Foo.cls',
              source:
                  'public class Foo { public enum Status { ACTIVE, INACTIVE } }',
            ),
          ],
        );

        final result = await repository.getIndexedType('Foo') as IndexedClass;
        final innerEnums = result.members.whereType<IndexedEnum>().toList();

        expect(innerEnums, hasLength(1));
        expect(innerEnums.first.name, equals(DeclarationName('Status')));
        expect(innerEnums.first.values, hasLength(2));
      });

      test('sets inner enum visibility', () async {
        final repository = await indexAndCreateRepository(
          classFiles: [
            (
              name: 'Foo.cls',
              source:
                  'public class Foo { private enum Status { ACTIVE, INACTIVE } }',
            ),
          ],
        );

        final result = await repository.getIndexedType('Foo') as IndexedClass;
        final innerEnums = result.members.whereType<IndexedEnum>().toList();

        expect(innerEnums, hasLength(1));
        expect(innerEnums.first.visibility, isA<NeverVisible>());
      });
    });
  });
}
