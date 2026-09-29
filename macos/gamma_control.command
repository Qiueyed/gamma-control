#!/bin/bash
cd "$(dirname "$0")"
BIN="$PWD/.gamma_boost_bin"

if [ ! -x "$BIN" ] || [ gamma_boost.swift -nt "$BIN" ]; then
  if swiftc -O -o "$BIN" gamma_boost.swift 2>/dev/null; then
    exec "$BIN"
  fi
  # Compile failed: fall back to the interpreter
  exec ./gamma_boost.swift
fi
exec "$BIN"
