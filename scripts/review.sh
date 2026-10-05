#!/usr/bin/env bash
set -euo pipefail
revision=aa48d347080940b8a2b8d2f48228674e280a3514
exec nix shell "github:NixOS/nixpkgs/$revision#llama-cpp" \
  "github:NixOS/nixpkgs/$revision#python3" -c python3 scripts/agent_review.py "$@"
