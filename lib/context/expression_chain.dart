import 'dart:convert';
import 'dart:ffi';

import 'package:apex_lsp/completion/tree_sitter_bindings.dart';
import 'package:ffi/ffi.dart';

/// A single segment in a chained member-access expression.
sealed class ChainSegment {
  final String name;
  const ChainSegment(this.name);
}

/// A plain identifier (variable reference or field access).
final class IdentifierSegment extends ChainSegment {
  const IdentifierSegment(super.name);
}

/// A method call invocation.
final class MethodCallSegment extends ChainSegment {
  const MethodCallSegment(super.name);
}

/// A constructor call `new TypeName(...)`. The [name] is the constructed type.
///
/// Unlike [IdentifierSegment], this signals that the result is an instance
/// of the type, not a static reference to it.
final class ObjectCreationSegment extends ChainSegment {
  const ObjectCreationSegment(super.name);
}

/// The `this` keyword.
final class ThisSegment extends ChainSegment {
  const ThisSegment() : super('this');
}

/// The `super` keyword.
final class SuperSegment extends ChainSegment {
  const SuperSegment() : super('super');
}

/// Extracts the chain of member-access segments from the tree-sitter AST at
/// [cursorOffset].
///
/// Returns a list like `[Identifier('a'), MethodCall('b'), Identifier('c')]`
/// for the expression `a.b().c`, or `null` if the cursor is not within a
/// chainable expression (`method_invocation` or `field_access`).
///
/// When the cursor is immediately after a dot (the tree may be in an error
/// state), pass the offset of the last valid character before the dot as
/// [probeOffset]. If [probeOffset] is omitted it defaults to [cursorOffset].
List<ChainSegment>? extractExpressionChain({
  required TreeSitterBindings bindings,
  required Pointer<TSTree> tree,
  required List<int> sourceBytes,
  required int cursorOffset,
  int? probeOffset,
}) {
  final root = bindings.ts_tree_root_node(tree);
  final probe = probeOffset ?? cursorOffset;

  final leaf = bindings.ts_node_descendant_for_byte_range(root, probe, probe);
  if (bindings.ts_node_is_null(leaf) != 0) return null;

  final outermost = _findOutermostChainNode(bindings, leaf);

  if (outermost != null) {
    // maxOffset excludes field/name nodes that start after the probe position,
    // preventing code after the dot (e.g. a keyword on the same line) from
    // being treated as part of the chain.
    return _collectSegments(bindings, outermost, sourceBytes, maxOffset: probe);
  }

  // Fallback for `new TypeName().` with no parsed field_access yet: the probe
  // falls inside an object_creation_expression with no chain-node ancestor.
  return _tryObjectCreationFallback(bindings, leaf, sourceBytes);
}

/// Walks up the tree from [node] to find the highest ancestor that is still a
/// `method_invocation` or `field_access`.
///
/// Climbs through any intervening non-chain nodes (like `argument_list` or `)`
/// tokens) until it finds a chain node, then continues climbing as long as the
/// parent is also a chain node.
TSNode? _findOutermostChainNode(TreeSitterBindings bindings, TSNode node) {
  TSNode? candidate;
  var current = node;

  while (true) {
    final type = _nodeType(bindings, current);
    if (type == 'method_invocation' || type == 'field_access') {
      candidate = current;
      final parent = bindings.ts_node_parent(current);
      if (bindings.ts_node_is_null(parent) != 0) break;
      final parentType = _nodeType(bindings, parent);
      if (parentType != 'method_invocation' && parentType != 'field_access') {
        break;
      }
      current = parent;
    } else {
      final parent = bindings.ts_node_parent(current);
      if (bindings.ts_node_is_null(parent) != 0) break;
      current = parent;
    }
  }

  return candidate;
}

List<ChainSegment>? _tryObjectCreationFallback(
  TreeSitterBindings bindings,
  TSNode leaf,
  List<int> sourceBytes,
) {
  var current = leaf;
  while (true) {
    if (_nodeType(bindings, current) == 'object_creation_expression') {
      final typeNode = _fieldChild(bindings, current, 'type');
      if (typeNode != null && bindings.ts_node_is_null(typeNode) == 0) {
        final typeName = _nodeText(bindings, typeNode, sourceBytes);
        return [ObjectCreationSegment(typeName)];
      }
      return null;
    }
    final parent = bindings.ts_node_parent(current);
    if (bindings.ts_node_is_null(parent) != 0) break;
    current = parent;
  }
  return null;
}

/// Recursively collects chain segments by walking the nested AST structure.
///
/// [maxOffset] restricts which field/name nodes are included: any node whose
/// start byte is after [maxOffset] is skipped. This prevents code appearing
/// after the cursor's dot (e.g. a `return` statement on the same line) from
/// being treated as part of the chain.
List<ChainSegment>? _collectSegments(
  TreeSitterBindings bindings,
  TSNode node,
  List<int> sourceBytes, {
  int? maxOffset,
}) => switch (_nodeType(bindings, node)) {
  'method_invocation' => _collectMemberAccess(
    bindings: bindings,
    node: node,
    sourceBytes: sourceBytes,
    memberField: 'name',
    makeSegment: MethodCallSegment.new,
    maxOffset: maxOffset,
  ),
  'field_access' => _collectMemberAccess(
    bindings: bindings,
    node: node,
    sourceBytes: sourceBytes,
    memberField: 'field',
    makeSegment: IdentifierSegment.new,
    maxOffset: maxOffset,
  ),
  'identifier' => [IdentifierSegment(_nodeText(bindings, node, sourceBytes))],
  'this' => [ThisSegment()],
  'super' => [SuperSegment()],
  'object_creation_expression' => _collectObjectCreation(
    bindings, node, sourceBytes,
  ),
  _ => null,
};

/// Collects segments for a `method_invocation` or `field_access` node.
///
/// Both node types share the same shape: an `object` sub-expression followed
/// by a member name (field name differs per type). [memberField] is the
/// tree-sitter field name for the member, and [makeSegment] wraps the member
/// name in the appropriate [ChainSegment] subtype.
List<ChainSegment>? _collectMemberAccess({
  required TreeSitterBindings bindings,
  required TSNode node,
  required List<int> sourceBytes,
  required String memberField,
  required ChainSegment Function(String) makeSegment,
  int? maxOffset,
}) {
  final objectNode = _fieldChild(bindings, node, 'object');
  final memberNode = _fieldChild(bindings, node, memberField);
  final segments = <ChainSegment>[];

  if (objectNode != null && bindings.ts_node_is_null(objectNode) == 0) {
    final objectSegments = _collectSegments(
      bindings,
      objectNode,
      sourceBytes,
      maxOffset: maxOffset,
    );
    if (objectSegments == null) return null;
    segments.addAll(objectSegments);
  }

  if (memberNode != null &&
      bindings.ts_node_is_null(memberNode) == 0 &&
      (maxOffset == null ||
          bindings.ts_node_start_byte(memberNode) <= maxOffset)) {
    segments.add(makeSegment(_nodeText(bindings, memberNode, sourceBytes)));
  }

  return segments;
}

List<ChainSegment>? _collectObjectCreation(
  TreeSitterBindings bindings,
  TSNode node,
  List<int> sourceBytes,
) {
  final typeNode = _fieldChild(bindings, node, 'type');
  if (typeNode == null || bindings.ts_node_is_null(typeNode) != 0) return null;
  return [ObjectCreationSegment(_nodeText(bindings, typeNode, sourceBytes))];
}

TSNode? _fieldChild(
  TreeSitterBindings bindings,
  TSNode node,
  String fieldName,
) {
  final namePtr = fieldName.toNativeUtf8();
  try {
    final child = bindings.ts_node_child_by_field_name(
      node,
      namePtr,
      fieldName.length,
    );
    if (bindings.ts_node_is_null(child) != 0) return null;
    return child;
  } finally {
    malloc.free(namePtr);
  }
}

String _nodeType(TreeSitterBindings bindings, TSNode node) =>
    bindings.ts_node_type(node).toDartString();

String _nodeText(
  TreeSitterBindings bindings,
  TSNode node,
  List<int> sourceBytes,
) {
  final start = bindings.ts_node_start_byte(node);
  final end = bindings.ts_node_end_byte(node);
  return utf8.decode(sourceBytes.sublist(start, end));
}
