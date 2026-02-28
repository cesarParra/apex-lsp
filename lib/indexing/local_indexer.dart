import 'dart:convert';
import 'dart:ffi';

import 'package:apex_lsp/completion/tree_sitter_bindings.dart';
import 'package:apex_lsp/indexing/declarations.dart';
import 'package:apex_lsp/type_name.dart';
import 'package:ffi/ffi.dart';

typedef DeclarationBuilder<T extends Declaration> =
    T Function(Block, (int, int)?, {required List<MethodParameter> parameters});

/// Parses and indexes Apex code in the currently open file using Tree-sitter.
///
/// This indexer provides real-time analysis of the active document without
/// requiring persistent disk storage. It extracts declarations (types, methods,
/// variables) that are visible at different cursor positions, enabling accurate
/// local completion suggestions.
///
/// **Key features:**
/// - Parses Apex code using native Tree-sitter FFI bindings
/// - Extracts enums, interfaces, methods, and variables
/// - Tracks variable scope visibility for accurate completions
/// - Handles enhanced for loops and method parameters
///
/// The indexer is particularly useful for anonymous Apex blocks where
/// declarations exist at the file level without a containing class.
///
/// Example:
/// ```dart
/// final indexer = LocalIndexer(bindings: treeSitterBindings);
/// final declarations = indexer.parseAndIndex(documentText);
/// // Use declarations for completion suggestions
/// ```
///
/// See also:
///  * [ApexIndexer], which indexes workspace files persistently.
///  * [TreeSitterBindings], which provides native parser access.
class LocalIndexer {
  LocalIndexer({required TreeSitterBindings bindings})
    : _bindings = bindings,
      _parser = bindings.ts_parser_new(),
      _fieldName = _FieldNames() {
    final language = _bindings.tree_sitter_apex();
    final ok = _bindings.ts_parser_set_language(_parser, language);
    if (ok == 0) {
      throw StateError('Failed to set Tree-sitter Apex language.');
    }
  }

  final TreeSitterBindings _bindings;
  final Pointer<TSParser> _parser;

  // Pre-allocated native UTF-8 pointers for the fixed set of Tree-sitter field
  // names used during traversal. Allocating these once avoids a malloc/free
  // pair on every _getField call (hundreds of times per keystroke).
  final _FieldNames _fieldName;

  /// Parses Apex source code and extracts all declarations.
  ///
  /// Uses Tree-sitter to parse the text into a syntax tree, then traverses
  /// the tree to collect type definitions, methods, and variables with their
  /// scope information.
  ///
  /// - [text]: The complete Apex source code to parse.
  ///
  /// Returns a list of [Declaration] objects representing all indexable elements
  /// found in the code.
  ///
  /// Example:
  /// ```dart
  /// final code = 'String name = "test";';
  /// final declarations = indexer.parseAndIndex(code);
  /// ```
  List<Declaration> parseAndIndex(String text) {
    final bindings = _bindings;
    final parser = _parser;
    final sourceBytes = utf8.encode(text);
    final sourcePtr = text.toNativeUtf8();
    try {
      // Parse the source text into a syntax tree
      final tree = bindings.ts_parser_parse_string(
        parser,
        nullptr,
        sourcePtr,
        sourceBytes.length,
      );

      final root = bindings.ts_tree_root_node(tree);

      List<int> bytes = sourceBytes;

      final indexedResult = _visit(root, bytes);

      bindings.ts_tree_delete(tree);
      return indexedResult;
    } finally {
      malloc.free(sourcePtr);
    }
  }

  /// Recursively visits a syntax tree node and extracts declarations.
  ///
  /// Routes nodes to specific extraction methods based on their type.
  /// Passes [scopeEnd] down to track where variable declarations become
  /// invisible (e.g., at the end of a block or loop).
  List<Declaration> _visit(TSNode node, List<int> bytes, {int? scopeEnd}) {
    List<Declaration> results = [];
    final type = _nodeType(node);

    switch (type) {
      case 'enum_declaration':
        results.add(_extractEnum(node, bytes));
      case 'interface_declaration':
        results.add(_extractInterface(node, bytes));
      case 'class_declaration':
        results.add(_extractClass(node, bytes));
      case 'method_declaration':
        final extractedMethod = _extractConstructorOrMethod(
          node,
          bytes,
          builder: _getMethodDeclarationBuilder(node, bytes),
        );
        results.add(extractedMethod);
      case 'local_variable_declaration':
        results.addAll(_extractVariables(node, bytes, scopeEnd: scopeEnd));
      case 'block':
        // Blocks define scope boundaries - variables declared inside are
        // only visible until the block ends
        results.addAll(
          _visitChildren(
            node,
            bytes,
            scopeEnd: _bindings.ts_node_end_byte(node),
          ),
        );
      case 'for_statement':
        // For loops also define scope boundaries
        results.addAll(
          _visitChildren(
            node,
            bytes,
            scopeEnd: _bindings.ts_node_end_byte(node),
          ),
        );
      case 'enhanced_for_statement':
        results.addAll(_extractEnhancedFor(node, bytes));
      default:
        results.addAll(_visitChildren(node, bytes, scopeEnd: scopeEnd));
    }
    return results;
  }

  List<Declaration> _visitChildren(
    TSNode node,
    List<int> bytes, {
    int? scopeEnd,
  }) {
    List<Declaration> results = [];
    final count = _bindings.ts_node_named_child_count(node);
    for (var i = 0; i < count; i++) {
      final child = _bindings.ts_node_named_child(node, i);
      results.addAll(_visit(child, bytes, scopeEnd: scopeEnd));
    }
    return results;
  }

  String _nodeType(TSNode node) {
    final ptr = _bindings.ts_node_type(node);
    return ptr.toDartString();
  }

  /// Extracts an enum declaration with its values.
  ///
  /// Parses the enum name and all enum constant values from the body.
  IndexedEnum _extractEnum(TSNode node, List<int> bytes) {
    final nameNode = _getField(node, 'name');

    final enumName = _nodeText(nameNode, bytes);

    final members = <EnumValueMember>[];
    final bodyNode = _getField(node, 'body');
    if (!_isNullNode(bodyNode)) {
      final constants = _collectDirectChildrenByType(bodyNode, 'enum_constant');
      for (final constant in constants) {
        final name = _nodeText(constant, bytes);
        if (name.isNotEmpty) {
          members.add(EnumValueMember(DeclarationName(name)));
        }
      }
    }

    return IndexedEnum(
      DeclarationName(enumName),
      visibility: AlwaysVisible(),
      location: (
        _bindings.ts_node_start_byte(node),
        _bindings.ts_node_end_byte(node),
      ),
      values: members,
    );
  }

  /// Extracts an interface declaration with its method signatures.
  ///
  /// Parses the interface name and all method declarations from the body.
  IndexedInterface _extractInterface(TSNode node, List<int> bytes) {
    final nameNode = _getField(node, 'name');
    final interfaceName = _nodeText(nameNode, bytes);

    final methods = <MethodDeclaration>[];
    final bodyNode = _getField(node, 'body');
    if (!_isNullNode(bodyNode)) {
      final methodNodes = _collectDirectChildrenByType(
        bodyNode,
        'method_declaration',
      );
      for (final methodNode in methodNodes) {
        final methodNameNode = _getField(methodNode, 'name');
        final returnTypeNode = _getField(methodNode, 'type');
        final parametersNode = _getField(methodNode, 'parameters');
        final name = _nodeText(methodNameNode, bytes);
        final returnType = _nodeText(returnTypeNode, bytes);
        final parameters = _extractMethodParameters(parametersNode, bytes);
        if (name.isNotEmpty) {
          methods.add(
            MethodDeclaration.withoutBody(
              DeclarationName(name),
              isStatic: false,
              returnType: returnType.isEmpty ? null : returnType,
              parameters: parameters,
              visibility: AlwaysVisible(),
            ),
          );
        }
      }
    }

    return IndexedInterface(
      DeclarationName(interfaceName),
      methods: methods,
      visibility: AlwaysVisible(),
      location: (
        _bindings.ts_node_start_byte(node),
        _bindings.ts_node_end_byte(node),
      ),
    );
  }

  Declaration _extractClass(TSNode node, List<int> bytes) {
    final nameNode = _getField(node, 'name');
    final className = _nodeText(nameNode, bytes);

    final staticInitializers = <Block>[];
    final bodyNode = _getField(node, 'body');
    final members = <Declaration>[];
    if (!_isNullNode(bodyNode)) {
      final fieldNodes = _collectDirectChildrenByType(
        bodyNode,
        'field_declaration',
      );
      for (final fieldNode in fieldNodes) {
        final declaratorNode = _getField(fieldNode, 'declarator');
        final fieldNameNode = _getField(declaratorNode, 'name');
        final fieldName = _nodeText(fieldNameNode, bytes);

        final typeNode = _getField(fieldNode, 'type');
        final fieldTypeName = _nodeText(typeNode, bytes);

        final isStatic = _hasStaticModifier(fieldNode, bytes);

        if (fieldName.isNotEmpty) {
          final accessorLists = _collectDirectChildrenByType(
            fieldNode,
            'accessor_list',
          );
          if (accessorLists.isNotEmpty) {
            members.add(
              _extractProperty(
                fieldNode,
                accessorLists.first,
                bytes,
                name: fieldName,
                typeName: fieldTypeName,
                isStatic: isStatic,
              ),
            );
          } else {
            members.add(
              FieldMember(
                DeclarationName(fieldName),
                isStatic: isStatic,
                visibility: AlwaysVisible(),
                typeName: fieldTypeName.isNotEmpty
                    ? DeclarationName(fieldTypeName)
                    : null,
              ),
            );
          }
        }
      }

      final methodNodes = _collectDirectChildrenByType(
        bodyNode,
        'method_declaration',
      );
      for (final methodNode in methodNodes) {
        members.add(
          _extractConstructorOrMethod(
            methodNode,
            bytes,
            builder: _getMethodDeclarationBuilder(methodNode, bytes),
          ),
        );
      }

      void collectMembers(
        String nodeType,
        Declaration Function(TSNode, List<int>) extractor,
      ) {
        for (final node in _collectDirectChildrenByType(bodyNode, nodeType)) {
          members.add(extractor(node, bytes));
        }
      }

      collectMembers('enum_declaration', _extractEnum);
      collectMembers('interface_declaration', _extractInterface);
      collectMembers('class_declaration', _extractClass);

      final constructorNodes = _collectDirectChildrenByType(
        bodyNode,
        'constructor_declaration',
      );
      for (final constructorNode in constructorNodes) {
        members.add(
          _extractConstructorOrMethod(
            constructorNode,
            bytes,
            builder:
                (
                  Block block,
                  (int, int)? location, {
                  required List<MethodParameter> parameters,
                }) => ConstructorDeclaration(body: block, location: location),
          ),
        );
      }

      final staticInitNodes = _collectDirectChildrenByType(
        bodyNode,
        'static_initializer',
      );
      for (final initNode in staticInitNodes) {
        staticInitializers.add(
          Block(declarations: _visitChildren(initNode, bytes)),
        );
      }
    }

    return IndexedClass(
      DeclarationName(className),
      members: members,
      staticInitializers: staticInitializers,
      visibility: AlwaysVisible(),
      location: (
        _bindings.ts_node_start_byte(node),
        _bindings.ts_node_end_byte(node),
      ),
    );
  }

  T _extractConstructorOrMethod<T extends Declaration>(
    TSNode node,
    List<int> bytes, {
    required DeclarationBuilder<T> builder,
  }) {
    final bodyNode = _getField(node, 'body');
    final bodyScopeEnd = _isNullNode(bodyNode)
        ? null
        : _bindings.ts_node_end_byte(bodyNode);

    final declarations = <Declaration>[];

    final parametersNode = _getField(node, 'parameters');
    final methodParameters = _extractMethodParameters(parametersNode, bytes);
    if (!_isNullNode(parametersNode)) {
      final scopeVisibility = bodyScopeEnd != null
          ? VisibleBetweenDeclarationAndScopeEnd(scopeEnd: bodyScopeEnd)
          : null;
      final params = _collectDirectChildrenByType(
        parametersNode,
        'formal_parameter',
      );
      for (final param in params) {
        final paramTypeNode = _getField(param, 'type');
        final paramNameNode = _getField(param, 'name');
        final paramType = _nodeText(paramTypeNode, bytes);
        final paramName = _nodeText(paramNameNode, bytes);
        if (paramName.isNotEmpty) {
          declarations.add(
            IndexedVariable(
              DeclarationName(paramName),
              typeName: DeclarationName(paramType),
              location: (
                _bindings.ts_node_start_byte(param),
                _bindings.ts_node_end_byte(param),
              ),
              visibility: scopeVisibility,
            ),
          );
        }
      }
    }

    if (!_isNullNode(bodyNode)) {
      declarations.addAll(
        _visitChildren(bodyNode, bytes, scopeEnd: bodyScopeEnd),
      );
    }

    return builder(Block(declarations: declarations), (
      _bindings.ts_node_start_byte(node),
      _bindings.ts_node_end_byte(node),
    ), parameters: methodParameters);
  }

  /// Extracts an enhanced for loop (for-each) with its iteration variable.
  ///
  /// The iteration variable is scoped to the loop body. For example:
  /// `for (Account acc : accounts)` declares `acc` visible within the loop.
  List<Declaration> _extractEnhancedFor(TSNode node, List<int> bytes) {
    final results = <Declaration>[];
    final scopeEnd = _bindings.ts_node_end_byte(node);

    // Extract the loop variable (e.g., "acc" in "for (Account acc : accounts)")
    final typeNode = _getField(node, 'type');
    final nameNode = _getField(node, 'name');
    final typeName = _nodeText(typeNode, bytes);
    final name = _nodeText(nameNode, bytes);
    if (name.isNotEmpty) {
      results.add(
        IndexedVariable(
          DeclarationName(name),
          typeName: DeclarationName(typeName),
          location: (
            _bindings.ts_node_start_byte(nameNode),
            _bindings.ts_node_end_byte(nameNode),
          ),
          visibility: VisibleBetweenDeclarationAndScopeEnd(scopeEnd: scopeEnd),
        ),
      );
    }

    // Visit the loop body to extract any nested declarations
    final bodyNode = _getField(node, 'body');
    if (!_isNullNode(bodyNode)) {
      results.addAll(_visit(bodyNode, bytes, scopeEnd: scopeEnd));
    }

    return results;
  }

  /// Extracts local variable declarations from a declaration statement.
  ///
  /// Handles multiple variables declared on the same line, e.g.:
  /// `String firstName = 'John', lastName = 'Doe';`
  ///
  /// Variables are visible from their declaration point until [scopeEnd].
  List<IndexedVariable> _extractVariables(
    TSNode node,
    List<int> bytes, {
    int? scopeEnd,
  }) {
    final typeNode = _getField(node, 'type');
    final typeName = _nodeText(typeNode, bytes);

    final visibility = scopeEnd != null
        ? VisibleBetweenDeclarationAndScopeEnd(scopeEnd: scopeEnd)
        : null;

    // A single declaration can contain multiple variable_declarator nodes
    final results = <IndexedVariable>[];
    final childCount = _bindings.ts_node_named_child_count(node);
    for (var i = 0; i < childCount; i++) {
      final child = _bindings.ts_node_named_child(node, i);
      if (_nodeType(child) == 'variable_declarator') {
        final nameNode = _getField(child, 'name');
        final name = _nodeText(nameNode, bytes);
        if (name.isNotEmpty) {
          results.add(
            IndexedVariable(
              DeclarationName(name),
              typeName: DeclarationName(typeName),
              location: (
                _bindings.ts_node_start_byte(child),
                _bindings.ts_node_end_byte(child),
              ),
              visibility: visibility,
            ),
          );
        }
      }
    }
    return results;
  }

  /// Extracts a property declaration (field with an accessor list).
  ///
  /// Produces a [PropertyDeclaration] with getter and setter bodies populated
  /// from any `accessor_declaration` nodes that have a `block` body. Auto-
  /// properties (get; set;) have no block body and produce null getter/setter.
  PropertyDeclaration _extractProperty(
    TSNode fieldNode,
    TSNode accessorListNode,
    List<int> bytes, {
    required String name,
    required String typeName,
    required bool isStatic,
  }) {
    Block? getterBody;
    Block? setterBody;

    final accessorNodes = _collectDirectChildrenByType(
      accessorListNode,
      'accessor_declaration',
    );
    for (final accessorNode in accessorNodes) {
      final bodyNode = _getField(accessorNode, 'body');
      if (_isNullNode(bodyNode)) continue;

      final scopeEnd = _bindings.ts_node_end_byte(bodyNode);
      final declarations = _visitChildren(bodyNode, bytes, scopeEnd: scopeEnd);
      final block = Block(declarations: declarations);

      final accessorKeywordNode = _getField(accessorNode, 'accessor');
      final accessorKeyword = _nodeText(accessorKeywordNode, bytes);
      if (accessorKeyword == 'get') {
        getterBody = block;
      } else if (accessorKeyword == 'set') {
        setterBody = block;
      }
    }

    return PropertyDeclaration(
      DeclarationName(name),
      isStatic: isStatic,
      visibility: AlwaysVisible(),
      typeName: typeName.isNotEmpty ? DeclarationName(typeName) : null,
      getterBody: getterBody,
      setterBody: setterBody,
      location: (
        _bindings.ts_node_start_byte(fieldNode),
        _bindings.ts_node_end_byte(fieldNode),
      ),
    );
  }

  bool _hasStaticModifier(TSNode node, List<int> bytes) {
    final modifiersNodes = _collectDirectChildrenByType(node, 'modifiers');
    return modifiersNodes.any(
      (node) => _nodeText(node, bytes).split(RegExp(r'\s+')).contains('static'),
    );
  }

  /// Retrieves a named field from a Tree-sitter node.
  ///
  /// Tree-sitter grammars define named fields for structured access to
  /// child nodes. For example, a method_declaration has fields like 'name',
  /// 'parameters', and 'body'.
  TSNode _getField(TSNode node, String fieldName) {
    final (ptr, length) = _fieldName.lookup(fieldName);
    return _bindings.ts_node_child_by_field_name(node, ptr, length);
  }

  /// Extracts the source text for a Tree-sitter node.
  ///
  /// Uses the node's byte range to slice the original source bytes and
  /// decode them as UTF-8 text.
  String _nodeText(TSNode node, List<int> bytes) {
    final start = _bindings.ts_node_start_byte(node);
    final end = _bindings.ts_node_end_byte(node);
    if (start < 0 || end > bytes.length || start >= end) return '';
    return utf8.decode(bytes.sublist(start, end));
  }

  /// Checks if a Tree-sitter node is null (doesn't exist).
  ///
  /// Tree-sitter returns null nodes when accessing missing optional fields.
  bool _isNullNode(TSNode node) => node.id.address == 0;

  /// Collects all direct children of a node that match a specific type.
  ///
  /// Only checks immediate children, not recursive descendants. Used to
  /// find specific constructs like enum constants or method parameters.
  List<TSNode> _collectDirectChildrenByType(TSNode root, String typeName) {
    final matches = <TSNode>[];
    final namedCount = _bindings.ts_node_named_child_count(root);

    for (var i = 0; i < namedCount; i++) {
      final child = _bindings.ts_node_named_child(root, i);
      if (_nodeType(child) == typeName) {
        matches.add(child);
      }
    }

    return matches;
  }

  DeclarationBuilder _getMethodDeclarationBuilder(
    TSNode methodNode,
    List<int> bytes,
  ) {
    MethodDeclaration methodDeclarationBuilder(
      Block block,
      (int, int)? location, {
      required List<MethodParameter> parameters,
    }) {
      final methodNameNode = _getField(methodNode, 'name');
      final returnTypeNode = _getField(methodNode, 'type');
      final methodName = _nodeText(methodNameNode, bytes);
      final returnType = _nodeText(returnTypeNode, bytes);
      final isStatic = _hasStaticModifier(methodNode, bytes);

      return MethodDeclaration(
        DeclarationName(methodName),
        isStatic: isStatic,
        body: block,
        returnType: returnType.isEmpty ? null : returnType,
        parameters: parameters,
        location: location,
        visibility: AlwaysVisible(),
      );
    }

    return methodDeclarationBuilder;
  }

  List<MethodParameter> _extractMethodParameters(
    TSNode parametersNode,
    List<int> bytes,
  ) {
    if (_isNullNode(parametersNode)) return const [];

    final parameters = <MethodParameter>[];
    final params = _collectDirectChildrenByType(
      parametersNode,
      'formal_parameter',
    );
    for (final param in params) {
      final paramTypeNode = _getField(param, 'type');
      final paramNameNode = _getField(param, 'name');
      final paramType = _nodeText(paramTypeNode, bytes);
      final paramName = _nodeText(paramNameNode, bytes);
      if (paramName.isEmpty || paramType.isEmpty) continue;
      parameters.add((type: paramType, name: paramName));
    }

    return parameters;
  }
}

/// Pre-allocated native UTF-8 strings for the fixed set of Tree-sitter field
/// names. Allocated once at construction and never freed — they live for the
/// duration of the process alongside the [LocalIndexer] that owns them.
final class _FieldNames {
  _FieldNames()
    : name = 'name'.toNativeUtf8(),
      body = 'body'.toNativeUtf8(),
      type = 'type'.toNativeUtf8(),
      parameters = 'parameters'.toNativeUtf8(),
      declarator = 'declarator'.toNativeUtf8(),
      accessor = 'accessor'.toNativeUtf8();

  final Pointer<Utf8> name;
  final Pointer<Utf8> body;
  final Pointer<Utf8> type;
  final Pointer<Utf8> parameters;
  final Pointer<Utf8> declarator;
  final Pointer<Utf8> accessor;

  (Pointer<Utf8>, int) lookup(String fieldName) => switch (fieldName) {
    'name' => (name, 4),
    'body' => (body, 4),
    'type' => (type, 4),
    'parameters' => (parameters, 10),
    'declarator' => (declarator, 10),
    'accessor' => (accessor, 8),
    _ => throw ArgumentError('Unknown Tree-sitter field name: "$fieldName"'),
  };
}
