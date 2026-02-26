import 'package:apex_lsp/completion/apex_keywords.dart';
import 'package:apex_lsp/completion/completion_context.dart';
import 'package:apex_lsp/completion/helpers.dart';
import 'package:apex_lsp/completion/rank.dart';
import 'package:apex_lsp/indexing/declarations.dart';
import 'package:apex_lsp/message.dart';
import 'package:apex_lsp/type_name.dart';
import 'package:apex_lsp/utils/text_utils.dart';

/// Base class for all completion candidates.
///
/// Thin wrappers that categorize how a declaration or keyword should be
/// presented as a completion suggestion.
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

/// Completion candidate for an Apex reserved keyword.
///
/// Keywords are offered at any top-level position, including at the file root,
/// to support anonymous Apex where statements can appear without a wrapping
/// class or method body.
final class KeywordCandidate extends CompletionCandidate {
  final String keyword;

  KeywordCandidate(this.keyword);

  @override
  String get name => keyword;
}

/// A function that produces completion candidates for a given context.
///
/// Each data source is a pure function — given the current [CompletionContext]
/// and [cursorOffset], it returns whatever candidates it can contribute.
/// Multiple sources are composed by the caller, who assembles exactly the
/// combination needed (e.g. declarations only, keywords only, or both).
typedef CompletionDataSource =
    List<CompletionCandidate> Function(
      CompletionContext context,
      int cursorOffset,
    );

/// Returns a [CompletionDataSource] that contributes candidates from [index].
///
/// [index] must already be scope-expanded for the current cursor position
/// (i.e. body declarations for the enclosing scope have been added by the
/// caller before passing it here).
///
/// Handles both top-level and member-access contexts:
/// - [CompletionContextTopLevel]: maps visible declarations to the appropriate
///   candidate subtype ([ApexTypeCandidate], [LocalVariableCandidate],
///   [MemberCandidate]).
/// - [CompletionContextMember]: resolves the type before the dot and returns
///   its members.
/// - [CompletionContextNone]: returns empty.
CompletionDataSource declarationSource(List<Declaration> index) =>
    (context, cursorOffset) => switch (context) {
      CompletionContextNone() => <CompletionCandidate>[],
      CompletionContextTopLevel() => _topLevelCandidates(index, cursorOffset),
      CompletionContextMember() => _memberCandidates(
        index,
        cursorOffset,
        context,
      ),
    };

/// A [CompletionDataSource] that contributes all Apex reserved keywords.
///
/// Keywords are only offered for [CompletionContextTopLevel] — they never
/// appear after a dot operator since `foo.for` is never valid Apex.
List<CompletionCandidate> keywordSource(
  CompletionContext context,
  int cursorOffset,
) => switch (context) {
  CompletionContextTopLevel() =>
    apexKeywords.map(KeywordCandidate.new).toList(),
  _ => <CompletionCandidate>[],
};

List<CompletionCandidate> _topLevelCandidates(
  List<Declaration> index,
  int cursorOffset,
) {
  final enclosingType = index.enclosingAt<IndexedType>(cursorOffset);
  return index
      .where((declaration) => declaration.isVisibleAt(cursorOffset))
      .map(
        (declaration) => switch (declaration) {
          IndexedType() => ApexTypeCandidate(declaration),
          IndexedVariable() => LocalVariableCandidate(declaration),
          FieldMember() || MethodDeclaration() || EnumValueMember() =>
            MemberCandidate(declaration, parentType: enclosingType),
          ConstructorDeclaration() => throw UnsupportedError(
            'Autocompleting constructors is not supported at the moment',
          ),
        },
      )
      .toList();
}

List<CompletionCandidate> _memberCandidates(
  List<Declaration> index,
  int cursorOffset,
  CompletionContextMember context,
) {
  if (context.typeName == null) {
    return <CompletionCandidate>[];
  }

  final typeName = DeclarationName(context.typeName!);

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

  final isStaticAccess = context.objectName == context.typeName;

  return switch (indexedType) {
    null => <CompletionCandidate>[],
    IndexedClass() =>
      indexedType.members
          .where((declaration) => declaration.isVisibleAt(cursorOffset))
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
    KeywordCandidate() => (CompletionItemKind.keyword, null as String?),
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
/// member access, etc.), gathering candidates from all [sources], and ranking
/// them by relevance.
///
/// - [text]: The complete document content. Returns empty list if `null`.
/// - [position]: The cursor position (line and character) in the document.
/// - [index]: The declaration index used for context detection and scope
///   expansion. Pass the combined local + workspace declarations.
/// - [sources]: The data sources to gather candidates from. Each source is a
///   [CompletionDataSource] function. Defaults to empty — pass
///   `[declarationSource(index)]` for declaration completions,
///   `[keywordSource]` for keyword completions, or both.
/// - [rank]: The ranking function to sort candidates (defaults to [rankCandidates]).
///
/// Returns a [CompletionList] with up to [maxCompletionItems] items. The list
/// is marked as incomplete (`isIncomplete: true`) when there are more candidates
/// available, signaling the client to request updated completions as the user
/// continues typing.
///
/// Example:
/// ```dart
/// final completions = await onCompletion(
///   text: 'Account acc = new Acc',
///   position: Position(line: 0, character: 21),
///   index: localIndexer.parseAndIndex(text),
///   sources: [declarationSource(index), keywordSource],
/// );
/// // Returns completions like ['Account']
/// ```
typedef CompletionLog = void Function(String message);

Future<CompletionList> onCompletion({
  required String? text,
  required Position position,
  required List<Declaration> index,
  List<CompletionDataSource> sources = const [],
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

  final contextDetector = ContextDetector();
  final context = await contextDetector.detect(
    text: text,
    cursorOffset: cursorOffset,
    index: index,
  );

  log?.call('Context: ${context.runtimeType} prefix="${context.prefix}"');

  final prefix = context.prefix;

  // Cap the number of candidates we process to one more than the max completion.
  final earlyStopLimit = maxCompletionItems + 1;

  final candidates = <CompletionCandidate>[];
  outer:
  for (final source in sources) {
    for (final candidate in source(context, cursorOffset)) {
      if (!potentiallyMatches(context, candidate)) continue;
      candidates.add(candidate);
      if (candidates.length == earlyStopLimit) {
        break outer;
      }
    }
  }

  log?.call('Candidates after filtering: ${candidates.length}');

  final isIncomplete = candidates.length > maxCompletionItems;

  final rankedItems = rankCandidates(
    candidates,
    prefix,
    limit: maxCompletionItems,
  ).map(_toCompletionItem).toList();

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
/// comparison for local variables and keywords.
///
/// Returns `true` if the candidate's name starts with the context prefix,
/// `false` otherwise. Always returns `false` for [CompletionContextNone].
bool potentiallyMatches(
  CompletionContext context,
  CompletionCandidate candidate,
) {
  bool nameStartsWith(String prefix) {
    return switch (candidate) {
      ApexTypeCandidate(:final type) => type.name.startsWith(prefix),
      MemberCandidate(:final declaration) => declaration.name.startsWith(
        prefix,
      ),
      LocalVariableCandidate(:final name) => name.startsWithIgnoreCase(prefix),
      KeywordCandidate(:final name) => name.startsWithIgnoreCase(prefix),
    };
  }

  return switch (context) {
    CompletionContextNone() => false,
    CompletionContextTopLevel(:final prefix) ||
    CompletionContextMember(:final prefix) => nameStartsWith(prefix),
  };
}

bool _isStaticDeclaration(Declaration declaration) => switch (declaration) {
  FieldMember(:final isStatic) ||
  MethodDeclaration(:final isStatic) => isStatic,
  EnumValueMember() || IndexedType() || ConstructorDeclaration() => true,
  IndexedVariable() => false,
};
