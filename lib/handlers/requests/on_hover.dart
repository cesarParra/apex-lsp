import 'package:apex_lsp/hover/hover_formatter.dart';
import 'package:apex_lsp/hover/symbol_resolver.dart';
import 'package:apex_lsp/indexing/local_indexer.dart';
import 'package:apex_lsp/indexing/workspace_indexer.dart';
import 'package:apex_lsp/message.dart';
import 'package:apex_lsp/utils/text_utils.dart';

Future<Hover?> onHover({
  required Object id,
  required String? openDocumentText,
  required HoverParams params,
  required LocalIndexer localIndexer,
  required IndexRepository? indexRepository,
}) async {
  if (openDocumentText == null) {
    return null;
  }

  final localIndex = localIndexer.parseAndIndex(openDocumentText);
  final workspaceTypes = await indexRepository?.getDeclarations() ?? [];
  final index = [...localIndex, ...workspaceTypes];

  final cursorOffset = offsetAtPosition(
    text: openDocumentText,
    line: params.position.line,
    character: params.position.character,
  );

  final resolved = resolveSymbolAt(
    cursorOffset: cursorOffset,
    text: openDocumentText,
    index: index,
  );

  return resolved != null ? formatHover(resolved) : null;
}
