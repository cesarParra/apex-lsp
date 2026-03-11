#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

OS="$(uname -s)"
if [ "$OS" = "Darwin" ]; then
  LIB="${ROOT_DIR}/bin/libtree_sitter_sfapex.dylib"
elif [ "$OS" = "Linux" ]; then
  LIB="${ROOT_DIR}/bin/libtree_sitter_sfapex.so"
else
  echo "Unsupported OS: $OS" >&2
  exit 1
fi

if [ ! -f "$LIB" ]; then
  echo "Native library not found at $LIB."
  echo "Run ./tool/build_tree_sitter_lib.sh first."
  exit 1
fi

TS_SFAPEX_LIB="$LIB" dart test "$@"
