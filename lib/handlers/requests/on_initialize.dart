import 'package:apex_lsp/message.dart';

InitializeResult onInitialize(InitializeRequest req) {
  // TODO: Get version from pubspec or dynamic source.
  return InitializeResult(
    capabilities: ServerCapabilities(
      textDocumentSync: 1, // TextDocumentSyncKind.Full
      completionProvider: CompletionOptions(triggerCharacters: ['.']),
      hoverProvider: true,
    ),
    serverInfo: ServerInfo(name: 'apex-lsp', version: '0.0.1'),
  );
}
