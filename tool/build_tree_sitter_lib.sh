#!/usr/bin/env bash
set -euo pipefail

# Build a native Tree-sitter Apex dynamic library for integration tests.
#
# Usage:
#   ./tool/build_tree_sitter_lib.sh
#
# This script will:
# - Clone tree-sitter (if needed)
# - Build the Tree-sitter C runtime
# - Compile the Apex parser into a shared library
# - Print the TS_SFAPEX_LIB env var to use for integration tests

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="${ROOT_DIR}/bin"
WORK_DIR="${ROOT_DIR}/.tree-sitter-build"
TREE_SITTER_DIR="${WORK_DIR}/tree-sitter"
SFAPEX_DIR="${WORK_DIR}/tree-sitter-sfapex"

# Determine OS-specific extension and linker flags
OS="$(uname -s)"
if [ "$OS" = "Darwin" ]; then
  LIB_EXT="dylib"
  LINKER_FLAGS="-Wl,-force_load,${TREE_SITTER_DIR}/libtree-sitter.a"
elif [ "$OS" = "Linux" ]; then
  LIB_EXT="so"
  LINKER_FLAGS="-Wl,--whole-archive ${TREE_SITTER_DIR}/libtree-sitter.a -Wl,--no-whole-archive"
else
  echo "Unsupported OS: $OS"
  exit 1
fi

OUT_LIB="${BIN_DIR}/libtree_sitter_sfapex.${LIB_EXT}"

echo "Workspace: ${ROOT_DIR}"
echo "Build dir: ${WORK_DIR}"
echo "Target: ${OUT_LIB}"

mkdir -p "${WORK_DIR}"

if [ ! -d "${TREE_SITTER_DIR}" ]; then
  echo "Cloning tree-sitter..."
  git clone https://github.com/tree-sitter/tree-sitter.git "${TREE_SITTER_DIR}"
fi

if [ ! -d "${SFAPEX_DIR}" ]; then
  echo "Cloning tree-sitter-sfapex..."
  git clone https://github.com/aheber/tree-sitter-sfapex.git "${SFAPEX_DIR}"
fi

echo "Building Tree-sitter runtime..."
pushd "${TREE_SITTER_DIR}" >/dev/null
# Use -fPIC for the static library so it can be linked into our shared library on Linux
CFLAGS="-fPIC" make
popd >/dev/null

RUNTIME_LIB="${TREE_SITTER_DIR}/libtree-sitter.a"
INCLUDE_DIR="${TREE_SITTER_DIR}/lib/include"

if [ ! -f "${RUNTIME_LIB}" ]; then
  echo "ERROR: Tree-sitter runtime not found at ${RUNTIME_LIB}"
  exit 1
fi

APEX_PARSER="${SFAPEX_DIR}/apex/src/parser.c"

if [ ! -f "${APEX_PARSER}" ]; then
  echo "ERROR: Apex parser not found at ${APEX_PARSER}"
  exit 1
fi

echo "Building Apex shared library..."
clang -shared -fPIC \
  -o "${OUT_LIB}" \
  -I "${INCLUDE_DIR}" \
  "${APEX_PARSER}" \
  ${LINKER_FLAGS}

echo "Done."
echo "Set this environment variable to run integration tests:"
echo "  export TS_SFAPEX_LIB=\"${OUT_LIB}\""
echo "Cleaning up cloned repositories..."
rm -rf "${WORK_DIR}"
