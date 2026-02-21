import 'package:apex_lsp/completion/completion_context.dart';
import 'package:apex_lsp/completion/helpers.dart';
import 'package:apex_lsp/completion/rank.dart';
import 'package:apex_lsp/indexing/declarations.dart';
import 'package:apex_lsp/message.dart';
import 'package:apex_lsp/type_name.dart';
import 'package:apex_lsp/utils/text_utils.dart';

/// Base class for all completion candidates.
///
/// Thin wrappers around [Declaration] that categorize how a declaration
/// should be presented as a completion suggestion. The [Declaration] itself
/// is the source of truth for all data (name, type info, etc.).
///
/// See also:
///  * [ApexTypeCandidate], for type-level completions.
///  * [MemberCandidate], for member access completions.
///  * [LocalVariableCandidate], for local variable completions.
sealed class CompletionCandidate {
  String get name;
}

/// Completion candidate for a top-level Apex type.
///
/// Represents completions for classes, enums, and interfaces that can
/// appear in type positions or as standalone references.
final class ApexTypeCandidate extends CompletionCandidate {
  final IndexedType type;

  ApexTypeCandidate(this.type);

  @override
  String get name => type.name.value;
}

/// Completion candidate for a type member.
///
/// Represents completions that appear after a dot operator, such as
/// instance methods, static methods, fields, or enum values.
final class MemberCandidate extends CompletionCandidate {
  final Declaration declaration;
  final IndexedType? parentType;

  MemberCandidate(this.declaration, {this.parentType});

  @override
  String get name => declaration.name.value;
}

/// Completion candidate for a locally declared variable.
///
/// Represents variables, method parameters, and loop variables that are
/// accessible at the current cursor position.
final class LocalVariableCandidate extends CompletionCandidate {
  final IndexedVariable variable;

  LocalVariableCandidate(this.variable);

  @override
  String get name => variable.name.value;
}

/// Maximum number of completion items to return to the client.
///
/// When more candidates are available, the list is marked as incomplete,
/// prompting the client to request more specific completions as the user types.
const maxCompletionItems = 25;

CompletionItem _toCompletionItem(CompletionCandidate candidate) {
  final (kind, detail) = switch (candidate) {
    ApexTypeCandidate(:final type) => _typeKindAndDetail(type),
    MemberCandidate(:final declaration, :final parentType) =>
      _memberKindAndDetail(declaration, parentType: parentType),
    LocalVariableCandidate(:final variable) => (
      CompletionItemKind.variable,
      variable.typeName.value as String?,
    ),
  };

  final labelDetails = switch (candidate) {
    MemberCandidate(:final declaration) when declaration is MethodDeclaration =>
      _methodLabelDetails(declaration),
    _ => null,
  };

  return CompletionItem(
    label: candidate.name,
    insertText: candidate.name,
    kind: kind,
    detail: detail,
    labelDetails: labelDetails,
  );
}

(CompletionItemKind, String?) _typeKindAndDetail(IndexedType type) =>
    switch (type) {
      IndexedClass(:final superClass) => (
        CompletionItemKind.classKind,
        superClass != null ? 'extends $superClass' : 'Class',
      ),
      IndexedInterface() => (CompletionItemKind.interfaceKind, 'Interface'),
      IndexedEnum() => (CompletionItemKind.enumKind, 'Enum'),
    };

(CompletionItemKind, String?) _memberKindAndDetail(
  Declaration declaration, {
  IndexedType? parentType,
}) => switch (declaration) {
  FieldMember(:final typeName) => (CompletionItemKind.field, typeName?.value),
  MethodDeclaration() => (CompletionItemKind.method, null),
  EnumValueMember() => (CompletionItemKind.enumMember, parentType?.name.value),
  IndexedClass() => (CompletionItemKind.classKind, 'Class'),
  IndexedInterface() => (CompletionItemKind.interfaceKind, 'Interface'),
  IndexedEnum() => (CompletionItemKind.enumKind, 'Enum'),
  IndexedVariable() ||
  ConstructorDeclaration() => (CompletionItemKind.variable, null),
};

CompletionItemLabelDetails _methodLabelDetails(MethodDeclaration declaration) {
  final parameters = declaration.parameters
      .map((parameter) => '${parameter.type} ${parameter.name}')
      .join(', ');

  return CompletionItemLabelDetails(
    detail: '($parameters)',
    description: declaration.returnType,
  );
}

/// Handles a Language Server Protocol completion request.
///
/// Processes a completion request by analyzing the document text at the
/// cursor position, determining the completion context (top-level type,
/// member access, etc.), gathering candidates from the index, and ranking
/// them by relevance.
///
/// - [text]: The complete document content. Returns empty list if `null`.
/// - [position]: The cursor position (line and character) in the document.
/// - [index]: The list of declarations from parsing the current file.
/// - [rank]: The ranking function to sort candidates (defaults to [rankCandidates]).
///
/// Returns a [CompletionList] with up to [maxCompletionItems] items. The list
/// is marked as incomplete (`isIncomplete: true`) when there are more candidates
/// available, signaling the client to request updated completions as the user
/// continues typing.
///
/// **Completion contexts:**
/// - **Top-level**: Types and local variables accessible at the current scope
/// - **Member access**: Methods, fields, or enum values accessed via dot operator
/// - **None**: No valid completion context detected
///
/// Example:
/// ```dart
/// final completions = await onCompletion(
///   text: 'Account acc = new Acc',
///   position: Position(line: 0, character: 21),
///   index: localIndexer.parseAndIndex(text),
/// );
/// // Returns completions like ['Account']
/// ```
///
/// See also:
///  * [ContextDetector], which determines the completion context.
///  * [rankCandidates], which applies Levenshtein-based ranking.
///  * [LocalIndexer], which provides the declaration index.
/// Optional logging callback for completion diagnostics.
typedef CompletionLog = void Function(String message);

Future<CompletionList> onCompletion({
  required String? text,
  required Position position,
  required List<Declaration> index,
  Rank rank = rankCandidates,
  CompletionLog? log,
}) async {
  if (text == null) {
    return CompletionList(isIncomplete: false, items: <CompletionItem>[]);
  }

  final cursorOffset = offsetAtPosition(
    text: text,
    line: position.line,
    character: position.character,
  );

  final indexedTypeCount = index.whereType<IndexedType>().length;
  log?.call(
    'Completion request: line=${position.line} char=${position.character} '
    'cursorOffset=$cursorOffset indexSize=${index.length} '
    'indexedTypes=$indexedTypeCount',
  );

  final enclosing = index.enclosingAt<Declaration>(cursorOffset);
  final expandedIndex = [...index, ...getBodyDeclarations(enclosing)];

  final contextDetector = ContextDetector();
  final context = await contextDetector.detect(
    text: text,
    cursorOffset: cursorOffset,
    index: expandedIndex,
  );

  log?.call('Context: ${context.runtimeType} prefix="${context.prefix}"');

  List<CompletionCandidate> topLevelCandidates() {
    return expandedIndex
        .where((declaration) => declaration.isVisibleAt(cursorOffset))
        .map(
          (declaration) => switch (declaration) {
            IndexedType() => ApexTypeCandidate(declaration),
            IndexedVariable() => LocalVariableCandidate(declaration),
            FieldMember() ||
            MethodDeclaration() ||
            EnumValueMember() => MemberCandidate(
              declaration,
              parentType: expandedIndex.enclosingAt<IndexedType>(cursorOffset),
            ),
            ConstructorDeclaration() => throw UnsupportedError(
              'Autocompleting constructors is not supported at the moment',
            ),
          },
        )
        .toList();
  }

  List<CompletionCandidate> memberCandidates(
    CompletionContextMember memberContext,
  ) {
    if (memberContext.typeName == null) {
      return <CompletionCandidate>[];
    }

    final typeName = DeclarationName(memberContext.typeName!);

    DeclarationName? resolveVariableType(DeclarationName name) => index
        .whereType<IndexedVariable>()
        .firstWhereOrNull((v) => v.name == name)
        ?.typeName;

    IndexedType? resolveQualified(DeclarationName name) {
      final resolved = index.resolveQualifiedName(name.value);
      return resolved is IndexedType ? resolved : null;
    }

    final indexedType =
        index.findType(typeName) ??
        index.findType(
          resolveVariableType(typeName) ?? const DeclarationName(''),
        ) ??
        resolveQualified(typeName);

    final isStaticAccess = memberContext.objectName == memberContext.typeName;

    return switch (indexedType) {
      null => <CompletionCandidate>[],
      IndexedClass() =>
        indexedType.members
            .where((member) => isStaticAccess == _isStaticDeclaration(member))
            .map((member) => MemberCandidate(member, parentType: indexedType))
            .toList(),
      IndexedInterface() =>
        indexedType.methods
            .map((method) => MemberCandidate(method, parentType: indexedType))
            .toList(),
      IndexedEnum() =>
        indexedType.values
            .map((value) => MemberCandidate(value, parentType: indexedType))
            .toList(),
    };
  }

  final prefix = context.prefix;
  final candidates = switch (context) {
    CompletionContextNone() => <CompletionCandidate>[],
    CompletionContextMember() => memberCandidates(context),
    CompletionContextTopLevel() => topLevelCandidates(),
  };

  log?.call('Total candidates before filtering: ${candidates.length}');

  final filteredCandidates = candidates
      .where((candidate) => potentiallyMatches(context, candidate))
      .toList();

  log?.call(
    'After prefix filter: ${filteredCandidates.length} '
    '(prefix="${context.prefix}")',
  );

  final rankedItems = rankCandidates(
    filteredCandidates,
    prefix,
  ).take(maxCompletionItems).map(_toCompletionItem).toList();

  final isIncomplete = filteredCandidates.length > maxCompletionItems;

  log?.call(
    'Returning ${rankedItems.length} items, '
    'isIncomplete=$isIncomplete'
    '${rankedItems.isNotEmpty ? ' first=${rankedItems.first.label}' : ''}',
  );

  return CompletionList(isIncomplete: isIncomplete, items: rankedItems);
}

/// Determines if a completion candidate potentially matches the completion context.
///
/// Filters candidates based on the prefix in the completion context. A candidate
/// matches if its name starts with the context prefix, using case-insensitive
/// comparison for local variables.
///
/// - [context]: The completion context containing the prefix to match against.
/// - [candidate]: The completion candidate to check.
///
/// Returns `true` if the candidate's name starts with the context prefix,
/// `false` otherwise. Always returns `false` for [CompletionContextNone].
///
/// Example:
/// ```dart
/// final context = CompletionContextTopLevel(prefix: 'Acc');
/// final candidate = ApexTypeCandidate(IndexedClass(DeclarationName('Account')));
/// print(potentiallyMatches(context, candidate)); // true
/// ```
bool potentiallyMatches(
  CompletionContext context,
  CompletionCandidate candidate,
) {
  bool candidateNameStartsWith(String prefix) {
    return switch (candidate) {
      ApexTypeCandidate(:final type) => type.name.startsWith(prefix),
      MemberCandidate(:final declaration) => declaration.name.startsWith(
        prefix,
      ),
      LocalVariableCandidate(:final name) => name.startsWithIgnoreCase(prefix),
    };
  }

  return switch (context) {
    CompletionContextNone() => false,
    CompletionContextTopLevel(:final prefix) ||
    CompletionContextMember(:final prefix) => candidateNameStartsWith(prefix),
  };
}

bool _isStaticDeclaration(Declaration declaration) => switch (declaration) {
  FieldMember(:final isStatic) ||
  MethodDeclaration(:final isStatic) => isStatic,
  EnumValueMember() || IndexedType() || ConstructorDeclaration() => true,
  IndexedVariable() => false,
};
