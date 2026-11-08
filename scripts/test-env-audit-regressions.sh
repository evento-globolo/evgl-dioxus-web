#!/usr/bin/env bash
# Negative and positive env-check tests run in an isolated Git worktree fixture.
# Never create a plaintext secret or decryption key in the source checkout.
set -euo pipefail

root="$(git rev-parse --show-toplevel)"
fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT
mkdir -p "$fixture/.just" "$fixture/env/enc" "$fixture/keyless-config" "$fixture/keyless-home"
cp "$root/justfile" "$fixture/justfile"
cp "$root/.just/env.just" "$fixture/.just/env.just"
cp "$root/.gitignore" "$fixture/.gitignore"
git -C "$fixture" init -q
git -C "$fixture" add justfile .just/env.just .gitignore
git -C "$fixture" -c user.name=env-audit-test -c user.email=env-audit-test@example.invalid commit -qm "isolated fixture"

run_check() (
  cd "$fixture"
  env -u SOPS_AGE_KEY -u SOPS_AGE_KEY_FILE \
    HOME="$fixture/keyless-home" XDG_CONFIG_HOME="$fixture/keyless-config" just env-check
)

log="$fixture/check.log"
expect_denied() {
  local case_name="$1" expected="$2"
  if run_check >"$log" 2>&1; then
    echo "FAIL: audit accepted $case_name" >&2
    exit 1
  fi
  if ! grep -Fq -- "$expected" "$log"; then
    echo "FAIL: audit rejected $case_name for the wrong reason:" >&2
    cat "$log" >&2
    exit 1
  fi
  echo "PASS: rejected $case_name"
}

# Positive control: this must succeed or every negative test could pass for
# an unrelated invocation failure (missing just, bad imports, missing Git).
run_check >"$log" 2>&1 || { cat "$log" >&2; exit 1; }
test ! -e "$fixture/env/dec" && test ! -L "$fixture/env/dec" \
  || { echo "FAIL: read-only audit created env/dec" >&2; exit 1; }
echo "PASS: keyless, read-only clean fixture"

ln -s "$fixture/keyless-home" "$fixture/env/dec"
expect_denied "env/dec symlink" "env/dec must not be a symlink"
unlink "$fixture/env/dec"

: >"$fixture/env/dec"
expect_denied "env/dec file masquerading as directory" "env/dec must be a directory"
rm "$fixture/env/dec"

printf 'TEST_ONLY_VALUE=not-a-real-secret\n' >"$fixture/.env"
git -C "$fixture" add -f .env
expect_denied "force-staged plaintext dotenv" "plaintext env files are tracked"
git -C "$fixture" reset -q HEAD -- .env
rm "$fixture/.env"

# Check fail-closed behavior if a required ignore rule is removed.
sed -i '/^env\/dec\/$/d' "$fixture/.gitignore"
expect_denied "missing mandatory ignore rule" "missing .gitignore rule: env/dec/"
cp "$root/.gitignore" "$fixture/.gitignore"

printf 'TEST_ONLY_VALUE=plaintext-not-ciphertext\n' >"$fixture/env/enc/dev.env.enc"
expect_denied "plaintext inside ciphertext directory" "is NOT sops-encrypted"
rm "$fixture/env/enc/dev.env.enc"

printf '%s\n' \
  'TEST_ONLY_VALUE=ENC[AES256_GCM,data:fixture,iv:fixture,tag:fixture,type:str]' \
  'map_recipient=fixture-one' \
  'map_recipient=fixture-two' >"$fixture/env/enc/dev.env.enc"
expect_denied "ciphertext missing SOPS MAC" "has no sops MAC"
printf '%s\n' \
  'TEST_ONLY_VALUE=ENC[AES256_GCM,data:fixture,iv:fixture,tag:fixture,type:str]' \
  'sops_mac=fixture' \
  'map_recipient=fixture-one' >"$fixture/env/enc/dev.env.enc"
expect_denied "only one recovery recipient" "needs >= 2"
rm "$fixture/env/enc/dev.env.enc"

run_check >"$log" 2>&1 || { cat "$log" >&2; exit 1; }
test ! -e "$fixture/env/dec" && test ! -L "$fixture/env/dec" \
  || { echo "FAIL: final audit created env/dec" >&2; exit 1; }
echo "PASS: seven keyless env-check controls (clean, symlink, non-directory, force-stage, ignore rule, MAC, recipient count) plus plaintext denial"
