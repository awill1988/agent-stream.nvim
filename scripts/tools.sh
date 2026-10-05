#!/usr/bin/env bash
set -euo pipefail
revision=aa48d347080940b8a2b8d2f48228674e280a3514
packages=(python3 stylua luajitPackages.luacheck shellcheck actionlint ruff ffmpeg git-cliff gitleaks)
args=()
for package in "${packages[@]}"; do
  args+=("github:NixOS/nixpkgs/$revision#$package")
done
exec nix shell "${args[@]}" -c "$@"
