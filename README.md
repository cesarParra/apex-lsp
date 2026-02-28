# apex-lsp

An Apex Language Server Protocol (LSP) server written in Dart.

Binaries are compiled for each Operating System (Windows, MacOs, Linux) and
can be downloaded from the release page.

When using the (sf-zed)[https://github.com/cesarParra/sf-zed] plugin, the latest
version is automatically installed for you.

## Features

### Indexing

### Limitations
- Only local files
- Only Apex files (no SObjects)

### Autocompletion

### Limitations
- No inheritance support (`super.` calls are not autocompleted)
- No Apexdocs support

- ### Hover

### Limitations
- No Apexdocs support

### Contributing

### Requirements

- Dart SDK (>= 3.0)
- Integration tests: `git`, `make`, and `clang` (Xcode Command Line Tools on macOS, `build-essential` on Linux)

### Run

From the repo root:

```/dev/null/commands.sh#L1-L2
dart run bin/apex_lsp.dart
```

### Integration tests (Tree-sitter)

The integration tests use a native Tree-sitter Apex library built by `tool/build_tree_sitter_lib.sh`. The script clones the Tree-sitter runtime and `tree-sitter-sfapex` into `.tree-sitter-build`, so the grammar does not need to live in this repo. This setup is supported on macOS (`.dylib`) and Linux (`.so`).

If the script is not executable, run:
```/dev/null/commands.sh#L1-L1
chmod +x tool/build_tree_sitter_lib.sh
```

Build the library, set the env var, and run the integration tests:
```/dev/null/commands.sh#L1-L4
./tool/build_tree_sitter_lib.sh
# For macOS:
export TS_SFAPEX_LIB="$(pwd)/bin/libtree_sitter_sfapex.dylib"
# For Linux:
export TS_SFAPEX_LIB="$(pwd)/bin/libtree_sitter_sfapex.so"

dart test test/completion/tree_sitter_integration_test.dart
```
