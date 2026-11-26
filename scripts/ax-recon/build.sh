#!/bin/sh
# Builds ax-recon next to this script into the folder given as $1 (default: ./build). Not part of the build gate.
set -eu
dir=$(cd "$(dirname "$0")" && pwd)
out=${1:-$dir/build}
mkdir -p "$out"
swiftc -O -o "$out/ax-recon" "$dir/ax-recon.swift"
echo "$out/ax-recon"
