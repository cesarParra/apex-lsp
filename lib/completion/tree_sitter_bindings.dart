// Tree-sitter FFI bindings for Apex parsing.
// This file provides minimal, direct FFI bindings to the C Tree-sitter API
// and the Apex language symbol exported by the tree-sitter-sfapex library.
//
// IMPORTANT:
// - This is a low-level binding layer only. No parsing logic is implemented here.
// - A native library that exports the Tree-sitter C API must be shipped,
//   plus `tree_sitter_apex` from tree-sitter-sfapex.
//
// Expected native symbols:
//   - tree_sitter_apex (from tree-sitter-sfapex apex parser.c)
//   - ts_parser_new / ts_parser_delete / ts_parser_set_language / ts_parser_parse_string
//   - ts_tree_delete / ts_tree_root_node / ts_node_*
//
// See: https://docs.flutter.dev/platform-integration/bind-native-code

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef ResolveFromCurrentDirectory = String Function(String);

String defaultResolver(String location) => location;

/// Minimal opaque handles to Tree-sitter objects.
final class TSParser extends Opaque {}

final class TSTree extends Opaque {}

final class TSLanguage extends Opaque {}

/// Tree-sitter node (value type, not a pointer).
///
/// See tree_sitter/api.h for details.
base class TSNode extends Struct {
  @Array(4)
  external Array<Uint32> context;

  external Pointer<Void> id;

  external Pointer<TSTree> tree;
}

/// FFI bindings to the Tree-sitter C API and Apex language function.
final class TreeSitterBindings {
  TreeSitterBindings._(this._lib)
    : ts_parser_new = _lib
          .lookupFunction<_ts_parser_new_c, _ts_parser_new_dart>(
            'ts_parser_new',
          ),
      ts_parser_delete = _lib
          .lookupFunction<_ts_parser_delete_c, _ts_parser_delete_dart>(
            'ts_parser_delete',
          ),
      ts_parser_set_language = _lib
          .lookupFunction<
            _ts_parser_set_language_c,
            _ts_parser_set_language_dart
          >('ts_parser_set_language'),
      ts_parser_parse_string = _lib
          .lookupFunction<
            _ts_parser_parse_string_c,
            _ts_parser_parse_string_dart
          >('ts_parser_parse_string'),
      ts_tree_delete = _lib
          .lookupFunction<_ts_tree_delete_c, _ts_tree_delete_dart>(
            'ts_tree_delete',
          ),
      ts_tree_root_node = _lib
          .lookupFunction<_ts_tree_root_node_c, _ts_tree_root_node_dart>(
            'ts_tree_root_node',
          ),
      ts_node_type = _lib.lookupFunction<_ts_node_type_c, _ts_node_type_dart>(
        'ts_node_type',
      ),
      ts_node_child_count = _lib
          .lookupFunction<_ts_node_child_count_c, _ts_node_child_count_dart>(
            'ts_node_child_count',
          ),
      ts_node_child = _lib
          .lookupFunction<_ts_node_child_c, _ts_node_child_dart>(
            'ts_node_child',
          ),
      ts_node_named_child_count = _lib
          .lookupFunction<
            _ts_node_named_child_count_c,
            _ts_node_named_child_count_dart
          >('ts_node_named_child_count'),
      ts_node_named_child = _lib
          .lookupFunction<_ts_node_named_child_c, _ts_node_named_child_dart>(
            'ts_node_named_child',
          ),
      ts_node_start_byte = _lib
          .lookupFunction<_ts_node_start_byte_c, _ts_node_start_byte_dart>(
            'ts_node_start_byte',
          ),
      ts_node_end_byte = _lib
          .lookupFunction<_ts_node_end_byte_c, _ts_node_end_byte_dart>(
            'ts_node_end_byte',
          ),
      ts_node_child_by_field_name = _lib
          .lookupFunction<
            _ts_node_child_by_field_name_c,
            _ts_node_child_by_field_name_dart
          >('ts_node_child_by_field_name'),
      ts_node_field_name_for_child = _lib
          .lookupFunction<
            _ts_node_field_name_for_child_c,
            _ts_node_field_name_for_child_dart
          >('ts_node_field_name_for_child'),
      tree_sitter_apex = _lib
          .lookupFunction<_tree_sitter_apex_c, _tree_sitter_apex_dart>(
            'tree_sitter_apex',
          );

  final DynamicLibrary _lib;

  /// Loads the bindings from a dynamic library on disk.
  ///
  /// [path] can be an absolute or relative path to the compiled library.
  /// For example on macOS you might use something like:
  ///   `libtree_sitter_sfapex.dylib`
  ///
  /// If you want to load from the process (e.g., statically linked),
  /// pass `DynamicLibrary.process()` in [loadFromProcess].
  static TreeSitterBindings load({
    ResolveFromCurrentDirectory pathResolver = defaultResolver,
    String? path,
    bool loadFromProcess = false,
  }) {
    if (loadFromProcess) {
      return TreeSitterBindings._(DynamicLibrary.process());
    }

    final resolved = _resolveLibraryPath(
      pathResolver: pathResolver,
      path: path,
    );
    return TreeSitterBindings._(DynamicLibrary.open(resolved));
  }

  /// Resolve platform-specific library filename if a short name is provided.
  static String _resolveLibraryPath({
    required ResolveFromCurrentDirectory pathResolver,
    String? path,
  }) {
    if (path != null && path.isNotEmpty) {
      return path;
    }

    // Fallback to platform naming conventions.
    if (Platform.isMacOS) {
      return pathResolver('libtree_sitter_sfapex.dylib');
    }
    if (Platform.isLinux) {
      return pathResolver('libtree_sitter_sfapex.so');
    }
    if (Platform.isWindows) {
      return pathResolver('tree_sitter_sfapex.dll');
    }

    // Default (unknown platform): attempt POSIX .so
    return pathResolver('libtree_sitter_sfapex.so');
  }

  // ====== C API bindings ======

  final _ts_parser_new_dart ts_parser_new;
  final _ts_parser_delete_dart ts_parser_delete;
  final _ts_parser_set_language_dart ts_parser_set_language;
  final _ts_parser_parse_string_dart ts_parser_parse_string;

  final _ts_tree_delete_dart ts_tree_delete;
  final _ts_tree_root_node_dart ts_tree_root_node;

  final _ts_node_type_dart ts_node_type;
  final _ts_node_child_count_dart ts_node_child_count;
  final _ts_node_child_dart ts_node_child;
  final _ts_node_named_child_count_dart ts_node_named_child_count;
  final _ts_node_named_child_dart ts_node_named_child;
  final _ts_node_start_byte_dart ts_node_start_byte;
  final _ts_node_end_byte_dart ts_node_end_byte;
  final _ts_node_child_by_field_name_dart ts_node_child_by_field_name;
  final _ts_node_field_name_for_child_dart ts_node_field_name_for_child;

  // Apex language entrypoint.
  final _tree_sitter_apex_dart tree_sitter_apex;
}

// ====== C function signatures ======

typedef _ts_parser_new_c = Pointer<TSParser> Function();
typedef _ts_parser_new_dart = Pointer<TSParser> Function();

typedef _ts_parser_delete_c = Void Function(Pointer<TSParser>);
typedef _ts_parser_delete_dart = void Function(Pointer<TSParser>);

typedef _ts_parser_set_language_c =
    Uint8 Function(Pointer<TSParser>, Pointer<TSLanguage>);
typedef _ts_parser_set_language_dart =
    int Function(Pointer<TSParser>, Pointer<TSLanguage>);

typedef _ts_parser_parse_string_c =
    Pointer<TSTree> Function(
      Pointer<TSParser>,
      Pointer<TSTree>,
      Pointer<Utf8>,
      Uint32,
    );
typedef _ts_parser_parse_string_dart =
    Pointer<TSTree> Function(
      Pointer<TSParser>,
      Pointer<TSTree>,
      Pointer<Utf8>,
      int,
    );

typedef _ts_tree_delete_c = Void Function(Pointer<TSTree>);
typedef _ts_tree_delete_dart = void Function(Pointer<TSTree>);

typedef _ts_tree_root_node_c = TSNode Function(Pointer<TSTree>);
typedef _ts_tree_root_node_dart = TSNode Function(Pointer<TSTree>);

typedef _ts_node_type_c = Pointer<Utf8> Function(TSNode);
typedef _ts_node_type_dart = Pointer<Utf8> Function(TSNode);

typedef _ts_node_child_count_c = Uint32 Function(TSNode);
typedef _ts_node_child_count_dart = int Function(TSNode);

typedef _ts_node_child_c = TSNode Function(TSNode, Uint32);
typedef _ts_node_child_dart = TSNode Function(TSNode, int);

typedef _ts_node_named_child_count_c = Uint32 Function(TSNode);
typedef _ts_node_named_child_count_dart = int Function(TSNode);

typedef _ts_node_named_child_c = TSNode Function(TSNode, Uint32);
typedef _ts_node_named_child_dart = TSNode Function(TSNode, int);

typedef _ts_node_start_byte_c = Uint32 Function(TSNode);
typedef _ts_node_start_byte_dart = int Function(TSNode);

typedef _ts_node_end_byte_c = Uint32 Function(TSNode);
typedef _ts_node_end_byte_dart = int Function(TSNode);

typedef _ts_node_child_by_field_name_c =
    TSNode Function(TSNode, Pointer<Utf8>, Uint32);
typedef _ts_node_child_by_field_name_dart =
    TSNode Function(TSNode, Pointer<Utf8>, int);

typedef _ts_node_field_name_for_child_c =
    Pointer<Utf8> Function(TSNode, Uint32);
typedef _ts_node_field_name_for_child_dart =
    Pointer<Utf8> Function(TSNode, int);

typedef _tree_sitter_apex_c = Pointer<TSLanguage> Function();
typedef _tree_sitter_apex_dart = Pointer<TSLanguage> Function();
