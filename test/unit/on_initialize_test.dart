import 'package:apex_lsp/handlers/requests/on_initialize.dart';
import 'package:apex_lsp/message.dart';
import 'package:apex_lsp/version.dart';
import 'package:test/test.dart';

void main() {
  group('onInitialize', () {
    late InitializeResult result;

    setUp(() {
      result = onInitialize(InitializeRequest(1, InitializedParams(null)));
    });

    test('returns the version from lib/version.dart', () {
      expect(result.serverInfo?.version, equals(packageVersion));
    });

    test('server name is apex-lsp', () {
      expect(result.serverInfo?.name, equals('apex-lsp'));
    });
  });
}
