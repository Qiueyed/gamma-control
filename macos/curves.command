#!/bin/bash
cd "$(dirname "$0")"
BIN="$PWD/.curves_bin"

# Compile only when source changed or binary missing (fixes slow startup)
if [ ! -x "$BIN" ] || [ curves.swift -nt "$BIN" ]; then
  echo "Compiling (first run or source changed)..."
  if ! swiftc -O -parse-as-library -o "$BIN" curves.swift 2>&1; then
    echo "Compilation failed. Install Xcode Command Line Tools."
    exit 1
  fi
fi

exec "$BIN"
