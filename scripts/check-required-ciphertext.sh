#!/usr/bin/env bash
# Repository-specific release gate: both approved SOPS environments must
# exist as tracked regular ciphertext files. No decryption or age key required.
set -euo pipefail
root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "missing Git repository for required ciphertext audit" >&2
  exit 1
}
cd "$root"
for name in dev prod; do
  path="env/enc/$name.env.enc"
  if [[ -L $path || ! -f $path ]]; then
    echo "required ciphertext $path missing, symlinked, or not a regular file" >&2
    exit 1
  fi
  if ! git ls-files --error-unmatch -- "$path" >/dev/null 2>&1; then
    echo "required ciphertext $path must be tracked by Git" >&2
    exit 1
  fi
done
echo "required ciphertext gate: dev and prod both present, regular and tracked"
