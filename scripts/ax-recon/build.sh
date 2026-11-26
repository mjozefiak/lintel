#!/bin/sh
# Builds ax-recon into the folder given as $1 (default: $TMPDIR/ax-recon, outside the repository). Not part of the
# build gate.
set -eu
dir=$(cd "$(dirname "$0")" && pwd)
out=${1:-${TMPDIR:-/tmp}/ax-recon}
mkdir -p "$out"
swiftc -O -o "$out/ax-recon" "$dir/ax-recon.swift"
echo "$out/ax-recon"
