import 'package:apex_lsp/message.dart';
import 'package:apex_lsp/version.dart';

InitializeResult onInitialize(InitializeRequest req) {
  return InitializeResult(
    capabilities: ServerCapabilities(
      textDocumentSync: TextDocumentSyncOptions(
        change: 1, // TextDocumentSyncKind.Full
        save: true,
      ),
      completionProvider: CompletionOptions(triggerCharacters: ['.']),
      hoverProvider: true,
    ),
    serverInfo: ServerInfo(name: 'apex-lsp', version: packageVersion),
  );
}
