import 'package:apex_lsp/message.dart';

class OpenDocuments {
  // Minimal in-memory document store so we can compute basic completions.
  final Map<String, String> _openDocuments = <String, String>{};

  String? get(String uri) => _openDocuments[uri];

  void didOpen(DidOpenTextDocumentParams params) {
    // Store the opened document in the document store.
    _openDocuments[params.textDocument.uri] = params.textDocument.text;
  }

  void didChange(DidChangeTextDocumentParams params) {
    // Full sync: contentChanges[0].text is the whole document.
    if (params.contentChanges.isEmpty) return;
    final text = params.contentChanges.first.text;
    _openDocuments[params.textDocument.uri] = text;
  }

  void didClose(DidCloseTextDocumentParams params) {
    _openDocuments.remove(params.textDocument.uri);
  }
}
