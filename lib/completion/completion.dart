import 'dart:async';

import 'package:apex_lsp/completion/completion_context.dart';
import 'package:apex_lsp/completion/helpers.dart';
import 'package:apex_lsp/completion/rank.dart';
import 'package:apex_lsp/indexing/declarations.dart';
import 'package:apex_lsp/message.dart';
import 'package:apex_lsp/type_name.dart';

/// Base class for all completion candidates.
///
/// A completion candidate represents a potential code completion suggestion
/// that can be shown to the user. Candidates are filtered and ranked based
/// on the completion context and user input.
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
///
/// Example:
/// ```dart
/// final candidate = ApexTypeCandidate(Local(name: TypeName('Account')));
/// print(candidate.name); // 'Account'
/// ```
final class ApexTypeCandidate extends CompletionCandidate {
  final ApexType type;

  ApexTypeCandidate(this.type);

  @override
  String get name => type.name.value;
}

/// Completion candidate for a type member.
///
/// Represents completions that appear after a dot operator, such as
/// instance methods, static methods, or enum values.
///
/// Example:
/// ```dart
/// final member = Member(
///   name: TypeName('getName'),
///   parentType: Local(name: TypeName('Account')),
///   type: MemberType.instance,
/// );
/// final candidate = MemberCandidate(member);
/// ```
final class MemberCandidate extends CompletionCandidate {
  final Member member;

  MemberCandidate(this.member);

  @override
  String get name => member.name.value;
}

/// Indicates whether a member is static or instance-level.
enum MemberType { static, instance }

/// Represents a type member with its parent type and access type.
///
/// Used to track completions for fields, methods, and enum values along
/// with their containing type and whether they are static or instance members.
final class Member {
  final DeclarationName name;
  final ApexType parentType;
  final MemberType type;

  Member({required this.name, required this.parentType, required this.type});
}

/// Completion candidate for a locally declared variable.
///
/// Represents variables, method parameters, and loop variables that are
/// accessible at the current cursor position. This is particularly common
/// in anonymous Apex blocks where variables are declared at the file level.
///
/// Example:
/// ```dart
/// final candidate = LocalVariableCandidate('accountName');
/// print(candidate.name); // 'accountName'
/// ```
final class LocalVariableCandidate extends CompletionCandidate {
  final String _name;

  LocalVariableCandidate(String name) : _name = name;

  @override
  String get name => _name;
}

/// Base class for Apex type sources.
///
/// Tracks where a type is defined relative to the current file being edited.
/// This distinction is important for understanding scope and accessibility.
///
/// See also:
///  * [Indexed], for types in other workspace files.
///  * [Local], for types in the current file.
///  * [Self], for the type currently being edited.
sealed class ApexType {
  final DeclarationName name;

  ApexType({required this.name});
}

/// An Apex type defined in the workspace index.
///
/// Represents classes, enums, and interfaces that exist in other files
/// within the workspace and have been indexed by [ApexIndexer].
final class Indexed extends ApexType {
  Indexed({required super.name});
}

/// An Apex type defined locally in the current file.
///
/// Represents types declared in the same file being edited, such as
/// inner classes or types in anonymous Apex blocks.
final class Local extends ApexType {
  Local({required super.name});
}

/// The Apex type currently being edited.
///
/// Represents the primary type definition in the current file, allowing
/// for self-referential completions like accessing own members.
final class Self extends ApexType {
  Self({required super.name});
}

/// Interface for completion suggestion providers.
///
/// Implementations provide completion candidates based on the completion
/// context, which includes cursor position and surrounding code.
abstract interface class CompletionSuggestion {
  /// Generates completion candidates for the given context.
  ///
  /// - [context]: The completion context including prefix and position.
  ///
  /// Returns a list of completion candidates appropriate for the context.
  FutureOr<List<CompletionCandidate>> suggest({
    required CompletionContext context,
  });
}

/// Maximum number of completion items to return to the client.
///
/// When more candidates are available, the list is marked as incomplete,
/// prompting the client to request more specific completions as the user types.
const maxCompletionItems = 25;

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

  final cursorOffset = _offsetAtPosition(
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

  List<CompletionCandidate> topLevelCandidates() {
    final enclosing = index.enclosingAt<Declaration>(cursorOffset);

    return [...index, ..._getBodyDeclarations(enclosing)]
        .where((declaration) => declaration.isVisibleAt(cursorOffset))
        .map(
          (declaration) => switch (declaration) {
            IndexedType() => ApexTypeCandidate(Local(name: declaration.name)),
            IndexedVariable() => LocalVariableCandidate(declaration.name.value),
            FieldMember() => LocalVariableCandidate(declaration.name.value),
            MethodDeclaration() => LocalVariableCandidate(
              declaration.name.value,
            ),
            EnumValueMember() => LocalVariableCandidate(declaration.name.value),
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

    MemberType getMemberType(Declaration declaration) => switch (declaration) {
      FieldMember(:final isStatic) ||
      MethodDeclaration(:final isStatic) => isStatic ? .static : .instance,

      EnumValueMember() ||
      IndexedClass() ||
      IndexedInterface() ||
      IndexedEnum() => .static,

      IndexedVariable() || ConstructorDeclaration() => .instance,
    };

    return switch (indexedType) {
      null => <CompletionCandidate>[],
      IndexedClass() =>
        indexedType.members
            .map(
              (value) => MemberCandidate(
                Member(
                  name: value.name,
                  parentType: Local(name: indexedType.name),
                  type: getMemberType(value),
                ),
              ),
            )
            .where((candidate) {
              final targetMemberType =
                  memberContext.objectName == memberContext.typeName
                  ? MemberType.static
                  : MemberType.instance;

              return candidate.member.type == targetMemberType;
            })
            .toList(),
      IndexedInterface() =>
        indexedType.methods
            .map(
              (method) => MemberCandidate(
                Member(
                  name: method.name,
                  parentType: Local(name: indexedType.name),
                  type: MemberType.instance,
                ),
              ),
            )
            .toList(),
      IndexedEnum() =>
        indexedType.values
            .map(
              (value) => MemberCandidate(
                Member(
                  name: value.name,
                  parentType: Local(name: indexedType.name),
                  type: MemberType.static,
                ),
              ),
            )
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

  final filteredCandidates = candidates.where(
    (candidate) => potentiallyMatches(context, candidate),
  ).toList();

  log?.call(
    'After prefix filter: ${filteredCandidates.length} '
    '(prefix="${context.prefix}")',
  );

  final rankedItems = rankCandidates(filteredCandidates, prefix)
      .take(maxCompletionItems)
      .map(
        (candidate) =>
            CompletionItem(label: candidate.name, insertText: candidate.name),
      )
      .toList();

  final isIncomplete = filteredCandidates.length > maxCompletionItems;

  log?.call(
    'Returning ${rankedItems.length} items, '
    'isIncomplete=$isIncomplete'
    '${rankedItems.isNotEmpty ? ' first=${rankedItems.first.label}' : ''}',
  );

  return CompletionList(
    isIncomplete: isIncomplete,
    items: rankedItems,
  );
}

/// Converts a line and character position to a byte offset within the text.
///
/// This utility function calculates the zero-based byte offset corresponding to
/// a given line and character position in a multiline text string. Lines are
/// assumed to be separated by `\n` characters.
///
/// - [text]: The complete text content to calculate offsets within.
/// - [line]: Zero-based line number.
/// - [character]: Zero-based character position within the line.
///
/// Returns the byte offset as an integer. If the line number is negative,
/// returns 0. If the line number exceeds the text length, returns the length
/// of the text. The character position is clamped to the line's length.
///
/// Example:
/// ```dart
/// final offset = _offsetAtPosition(
///   text: 'Hello\nWorld',
///   line: 1,      // Second line
///   character: 2, // Third character ('r')
/// );
/// print(offset); // 8 (6 for 'Hello\n' + 2 for 'Wo')
/// ```
int _offsetAtPosition({
  required String text,
  required int line,
  required int character,
}) {
  if (line < 0) return 0;

  final lines = text.split('\n');
  if (lines.isEmpty) return 0;
  if (line >= lines.length) return text.length;

  var offset = 0;
  for (var i = 0; i < line; i++) {
    offset += lines[i].length + 1;
  }

  final lineText = lines[line];
  final clamped = character.clamp(0, lineText.length).toInt();
  return offset + clamped;
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
/// final candidate = ApexTypeCandidate(Local(name: TypeName('Account')));
/// print(potentiallyMatches(context, candidate)); // true
/// ```
bool potentiallyMatches(
  CompletionContext context,
  CompletionCandidate candidate,
) {
  bool candidateNameStartsWith(String prefix) {
    return switch (candidate) {
      ApexTypeCandidate(:final type) => type.name.startsWith(prefix),
      MemberCandidate(:final member) => member.name.startsWith(prefix),
      LocalVariableCandidate(:final name) => name.startsWithIgnoreCase(prefix),
    };
  }

  return switch (context) {
    CompletionContextNone() => false,
    CompletionContextTopLevel(:final prefix) ||
    CompletionContextMember(:final prefix) => candidateNameStartsWith(prefix),
  };
}

List<Declaration> _getBodyDeclarations(Declaration? declaration) {
  return switch (declaration) {
    null ||
    FieldMember() ||
    EnumValueMember() ||
    IndexedVariable() ||
    IndexedInterface() ||
    IndexedEnum() => const [],

    // Declarations with body
    ConstructorDeclaration(:final body) ||
    MethodDeclaration(:final body) => body.declarations,

    IndexedClass() => [
      ...declaration.members,
      ...declaration.members.expand(_getBodyDeclarations),
      ...declaration.staticInitializers.expand((s) => s.declarations),
    ],
  };
}
