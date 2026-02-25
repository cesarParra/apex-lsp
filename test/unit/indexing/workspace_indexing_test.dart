import 'dart:convert';

import 'package:apex_lsp/indexing/declarations.dart';
import 'package:apex_lsp/indexing/sfdx_workspace_locator.dart';
import 'package:apex_lsp/indexing/workspace_indexer.dart';
import 'package:apex_lsp/message.dart';
import 'package:apex_lsp/type_name.dart';
import 'package:apex_lsp/utils/platform.dart';
import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:test/test.dart';

final class FakeLspPlatform implements LspPlatform {
  FakeLspPlatform({this.isWindows = false, this.pathSeparator = '/'});

  @override
  final bool isWindows;

  @override
  final String pathSeparator;
}

void main() {
  group('Indexer', () {
    late FileSystem fs;
    late FakeLspPlatform platform;
    late WorkspaceIndexer indexer;
    late Directory workspaceRoot;
    late Uri workspaceUri;

    setUp(() {
      fs = MemoryFileSystem();
      platform = FakeLspPlatform();
      indexer = WorkspaceIndexer(
        sfdxWorkspaceLocator: SfdxWorkspaceLocator(
          fileSystem: fs,
          platform: platform,
        ),
        fileSystem: fs,
        platform: platform,
      );

      workspaceRoot = fs.directory('/repo')..createSync();
      workspaceUri = Uri.directory(workspaceRoot.path);
    });

    test('indexes Apex files and generates metadata', () async {
      final projectFile = workspaceRoot.childFile('sfdx-project.json');
      projectFile.writeAsStringSync(
        jsonEncode({
          'packageDirectories': [
            {'path': 'force-app', 'default': true},
          ],
        }),
      );

      final classesDir = fs.directory('/repo/force-app/main/default/classes')
        ..createSync(recursive: true);

      final fooFile = classesDir.childFile('Foo.cls');
      fooFile.writeAsStringSync('public class Foo { public void hello(){} }');

      final params = InitializedParams([
        WorkspaceFolder(workspaceUri.toString(), 'repo'),
      ]);

      final token = ProgressToken.string('test-token');
      final progressEvents = await indexer.index(params, token: token).toList();

      expect(progressEvents, isNotEmpty);
      expect(
        (progressEvents.first.value as WorkDoneProgressBegin).title,
        equals('Indexing Apex files'),
      );
      expect(
        (progressEvents.last.value as WorkDoneProgressEnd).message,
        equals('Indexing complete'),
      );

      final indexDir = workspaceRoot.childDirectory('.sf-zed');
      expect(indexDir.existsSync(), isTrue);

      final metadataFile = indexDir.childFile('Foo.json');
      expect(metadataFile.existsSync(), isTrue);

      final metadata = jsonDecode(metadataFile.readAsStringSync());
      expect(metadata['className'], equals('Foo'));
      expect(
        metadata['source']['relativePath'],
        equals('force-app/main/default/classes/Foo.cls'),
      );
    });

    test('skips indexing if no workspace folders provided', () async {
      final params = InitializedParams(null);
      final events = await indexer
          .index(params, token: ProgressToken.string('test-token'))
          .toList();
      expect(events, isEmpty);
    });
  });

  group('IndexRepository', () {
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

    /// Runs the Indexer to produce `.sf-zed` metadata from `.cls` files,
    /// then returns an [IndexRepository] pointed at the same workspace.
    Future<IndexRepository> indexAndCreateRepository({
      required List<({String name, String source})> classFiles,
    }) async {
      final projectFile = workspaceRoot.childFile('sfdx-project.json');
      projectFile.writeAsStringSync(
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

      return indexer.getIndexLoader();
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
    });
  });
}
