#!/usr/bin/env bash
# Negative and positive env-check tests run in an isolated Git worktree fixture.
# Never create a plaintext secret or decryption key in the source checkout.
set -euo pipefail

root="$(git rev-parse --show-toplevel)"
fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT
mkdir -p "$fixture/.just" "$fixture/scripts" "$fixture/env/enc" "$fixture/keyless-config" "$fixture/keyless-home"
cp "$root/justfile" "$fixture/justfile"
cp "$root/.just/env.just" "$fixture/.just/env.just"
cp "$root/.just/check-sops-envelope.py" "$fixture/.just/check-sops-envelope.py"
cp "$root/scripts/check-required-ciphertext.sh" "$fixture/scripts/check-required-ciphertext.sh"
cp "$root/.gitignore" "$fixture/.gitignore"
git -C "$fixture" init -q
git -C "$fixture" add justfile .just/env.just .just/check-sops-envelope.py scripts/check-required-ciphertext.sh .gitignore
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

# Every secret-path component must reject symlink substitution.
rmdir "$fixture/env/enc"
ln -s "$fixture/keyless-home" "$fixture/env/enc"
expect_denied "env/enc symlink" "env/enc must not be a symlink"
unlink "$fixture/env/enc"
rmdir "$fixture/env"
ln -s "$fixture/keyless-home" "$fixture/env"
expect_denied "env root symlink" "env must not be a symlink"
unlink "$fixture/env"
mkdir -p "$fixture/env/enc"

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

# Committing a private-key-shaped path must be rejected even if it was
# force-added against .gitignore. This is a fake fixture, never a real key.
printf 'FIXTURE-NOT-A-REAL-AGE-KEY\n' >"$fixture/keys.txt"
git -C "$fixture" add -f keys.txt
expect_denied "force-staged private-key filename" "possible private keys tracked"
git -C "$fixture" reset -q HEAD -- keys.txt
rm "$fixture/keys.txt"

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

# A missing Git index previously looked like an empty list of tracked files.
mv "$fixture/.git" "$fixture/.git-hidden"
expect_denied "missing git repository metadata" "requires a readable Git checkout and index"
mv "$fixture/.git-hidden" "$fixture/.git"

# A real SOPS ciphertext must pass the keyless structural control without
# decrypting or introducing keys into the temporary test repository.
cp "$root/env/enc/dev.env.enc" "$fixture/env/enc/dev.env.enc"
run_check >"$log" 2>&1 || { cat "$log" >&2; exit 1; }
echo "PASS: real SOPS ciphertext structurally valid without decryption"
rm "$fixture/env/enc/dev.env.enc"

# The original check could be fooled by three isolated marker strings.
printf '%s\n' \
  '#ENC[AES256_GCM,data:fake,iv:fake,tag:fake,type:str]' \
  'sops_mac=fixture' \
  'sops_age__list_0__map_recipient=fixture-one' \
  'sops_age__list_1__map_recipient=fixture-two' >"$fixture/env/enc/dev.env.enc"
expect_denied "forged marker-only ciphertext" "invalid SOPS AES-GCM envelope for sops_mac"
rm "$fixture/env/enc/dev.env.enc"

# A genuine encrypted assignment does not excuse an adjacent plaintext value.
cp "$root/env/enc/dev.env.enc" "$fixture/env/enc/dev.env.enc"
printf '%s\n' "PUBLIC_TEST_VALUE=plaintext-fixture-only" >>"$fixture/env/enc/dev.env.enc"
expect_denied "plaintext next to genuine ciphertext" "invalid SOPS AES-GCM envelope for PUBLIC_TEST_VALUE"
rm "$fixture/env/enc/dev.env.enc"

# A malicious plaintext dotenv value under the reserved metadata prefix
# must not be exempted by a broad startswith("sops_") check.
cp "$root/env/enc/dev.env.enc" "$fixture/env/enc/dev.env.enc"
printf '%s\n' 'sops_hidden_plaintext=fixture-not-a-real-secret' >>"$fixture/env/enc/dev.env.enc"
expect_denied "plaintext under unknown SOPS metadata prefix" "unexpected SOPS metadata key sops_hidden_plaintext"
rm "$fixture/env/enc/dev.env.enc"

# Duplicate dotenv keys can obscure which value a decoder or reviewer uses.
cp "$root/env/enc/dev.env.enc" "$fixture/env/enc/dev.env.enc"
printf '%s\n' "sops_version=3.11.0" >>"$fixture/env/enc/dev.env.enc"
expect_denied "duplicate SOPS metadata key" "duplicate dotenv key sops_version"
rm "$fixture/env/enc/dev.env.enc"

# A broken tag/nonce must not count as a properly shaped GCM envelope.
cp "$root/env/enc/dev.env.enc" "$fixture/env/enc/dev.env.enc"
python3 - "$fixture/env/enc/dev.env.enc" <<'PY'
from pathlib import Path
import re
import sys
p = Path(sys.argv[1])
lines = p.read_text().splitlines(keepends=True)
changed = 0
for i, line in enumerate(lines):
    if line.startswith("sops_mac="):
        lines[i], n = re.subn(r"tag:[A-Za-z0-9+/=]+", "tag:INVALID!", line, count=1)
        changed += n
assert changed == 1
p.write_text("".join(lines))
PY
expect_denied "invalid GCM authentication tag" "invalid SOPS AES-GCM envelope"
rm "$fixture/env/enc/dev.env.enc"

# Even a real ciphertext file must not be followed through a symlink.
ln -s "$root/env/enc/dev.env.enc" "$fixture/env/enc/dev.env.enc"
expect_denied "symlinked ciphertext file" "ciphertext path is a symlink"
unlink "$fixture/env/enc/dev.env.enc"

# Dropping a recipient's wrapped key material while retaining the recipient
# string is a metadata-corruption attack, not a passing two-recipient audit.
cp "$root/env/enc/dev.env.enc" "$fixture/env/enc/dev.env.enc"
python3 - "$fixture/env/enc/dev.env.enc" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
lines = p.read_text().splitlines(keepends=True)
lines = [line for line in lines if not line.startswith("sops_age__list_1__map_enc=")]
p.write_text("".join(lines))
PY
expect_denied "recipient without wrapped key" "missing or malformed age-wrapped data"
rm "$fixture/env/enc/dev.env.enc"

# Distinct recovery recipients are required, not two labels for one key.
cp "$root/env/enc/dev.env.enc" "$fixture/env/enc/dev.env.enc"
python3 - "$fixture/env/enc/dev.env.enc" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
lines = p.read_text().splitlines(keepends=True)
rec0 = next(s.split("=", 1)[1] for s in lines if s.startswith("sops_age__list_0__map_recipient="))
lines = [
    "sops_age__list_1__map_recipient=" + rec0
    if s.startswith("sops_age__list_1__map_recipient=")
    else s
    for s in lines
]
p.write_text("".join(lines))
PY
expect_denied "duplicate age recovery key" "duplicate age recipient"
rm "$fixture/env/enc/dev.env.enc"


# Mutate *real* encrypted bytes in an isolated fixture. Each case starts from
# an untouched source ciphertext, then proves the fail-closed reason, not just
# a nonzero exit from a broken runner. These mutations contain no real secrets.
mutate_ciphertext_case() {
  local scenario="$1" expected="$2"
  cp "$root/env/enc/dev.env.enc" "$fixture/env/enc/dev.env.enc"
  python3 - "$fixture/env/enc/dev.env.enc" "$scenario" <<'PY'
from pathlib import Path
import base64
import re
import sys

path, scenario = Path(sys.argv[1]), sys.argv[2]
original = path.read_text()
lines = original.splitlines(keepends=True)

def set_key(name, value):
    matches = [i for i, line in enumerate(lines) if line.startswith(name + "=")]
    assert len(matches) == 1, name
    lines[matches[0]] = name + "=" + value + "\n"

def mac_transform(pattern, replacement):
    matches = [i for i, line in enumerate(lines) if line.startswith("sops_mac=")]
    assert len(matches) == 1
    i = matches[0]
    lines[i], n = re.subn(pattern, replacement, lines[i], count=1)
    assert n == 1, pattern

if scenario == "short_sops_iv":
    mac_transform(r"iv:[^,]+", "iv:" + base64.b64encode(bytes(12)).decode())
elif scenario == "short_tag":
    mac_transform(r"tag:[^,]+", "tag:" + base64.b64encode(bytes(8)).decode())
elif scenario == "invalid_iv_base64":
    mac_transform(r"iv:[^,]+", "iv:A=")
elif scenario == "invalid_mac_envelope":
    set_key("sops_mac", "not-an-encrypted-MAC")
elif scenario == "missing_version":
    lines = [line for line in lines if not line.startswith("sops_version=")]
elif scenario == "malformed_version":
    set_key("sops_version", "not-semver")
elif scenario == "malformed_timestamp":
    set_key("sops_lastmodified", "yesterday")
elif scenario == "unknown_unencrypted_suffix":
    set_key("sops_unencrypted_suffix", "PASSWORD")
elif scenario == "missing_recipient_index":
    lines = [line.replace("sops_age__list_1__", "sops_age__list_9__") for line in lines]
elif scenario == "invalid_age_recipient":
    set_key("sops_age__list_1__map_recipient", "age1not-a-valid-public-key")
elif scenario == "duplicate_business_key":
    lines.append(next(line for line in lines if line.startswith("HOST=")))
elif scenario == "malformed_dotenv_line":
    lines.append("NOT_AN_ASSIGNMENT\n")
elif scenario == "unknown_sops_field":
    lines.append("sops_private_test_marker=not-a-secret\n")
elif scenario == "commented_plaintext":
    lines.append("# CLOUD_SECRET=fixture-data-only\n")
elif scenario == "oversized_file":
    lines.append("#" + "X" * 1_100_000 + "\n")
elif scenario == "invalid_utf8":
    path.write_bytes("".join(lines).encode("utf-8") + b"\xff")
    sys.exit(0)
else:
    raise AssertionError("unknown mutation " + scenario)
path.write_text("".join(lines))
PY
  expect_denied "$scenario" "$expected"
  rm "$fixture/env/enc/dev.env.enc"
}

mutate_ciphertext_case short_sops_iv "invalid SOPS iv length for sops_mac"
mutate_ciphertext_case short_tag "invalid tag length for sops_mac"
mutate_ciphertext_case invalid_iv_base64 "invalid base64 SOPS iv for sops_mac"
mutate_ciphertext_case invalid_mac_envelope "invalid SOPS AES-GCM envelope for sops_mac"
mutate_ciphertext_case missing_version "missing or invalid SOPS version"
mutate_ciphertext_case malformed_version "missing or invalid SOPS version"
mutate_ciphertext_case malformed_timestamp "missing or invalid SOPS modification timestamp"
mutate_ciphertext_case unknown_unencrypted_suffix "unexpected SOPS unencrypted suffix"
mutate_ciphertext_case missing_recipient_index "needs >= 2 contiguous age recipient entries"
mutate_ciphertext_case invalid_age_recipient "invalid or missing age recipient at index 1"
mutate_ciphertext_case duplicate_business_key "duplicate dotenv key HOST"
mutate_ciphertext_case malformed_dotenv_line "invalid dotenv assignment"
mutate_ciphertext_case unknown_sops_field "unexpected SOPS metadata key sops_private_test_marker"
mutate_ciphertext_case commented_plaintext "plaintext dotenv assignment in ciphertext comment"
mutate_ciphertext_case oversized_file "ciphertext exceeds 1 MiB structural audit budget"
mutate_ciphertext_case invalid_utf8 "ciphertext must be UTF-8 dotenv"

# Repo release policy: both encrypted environments must exist, be regular
# files, and be in Git's index (no source checkout, keys, or plaintext touched).
run_required() (
  cd "$fixture"
  bash scripts/check-required-ciphertext.sh
)
expect_required_denied() {
  local case_name="$1" expected="$2"
  if run_required >"$log" 2>&1; then
    echo "FAIL: release policy accepted $case_name" >&2
    exit 1
  fi
  if ! grep -Fq -- "$expected" "$log"; then
    echo "FAIL: release policy denied $case_name for the wrong reason:" >&2
    cat "$log" >&2
    exit 1
  fi
  echo "PASS: rejected $case_name"
}
cp "$root/env/enc/dev.env.enc" "$fixture/env/enc/dev.env.enc"
cp "$root/env/enc/prod.env.enc" "$fixture/env/enc/prod.env.enc"
git -C "$fixture" add env/enc/dev.env.enc env/enc/prod.env.enc
run_required >"$log" 2>&1 || { cat "$log" >&2; exit 1; }
echo "PASS: tracked dev and prod ciphertext release gate"

rm "$fixture/env/enc/dev.env.enc"
expect_required_denied "missing required dev ciphertext" "required ciphertext env/enc/dev.env.enc missing"
cp "$root/env/enc/dev.env.enc" "$fixture/env/enc/dev.env.enc"

git -C "$fixture" rm --cached -q -- env/enc/prod.env.enc
expect_required_denied "untracked required prod ciphertext" "required ciphertext env/enc/prod.env.enc must be tracked"
git -C "$fixture" add env/enc/prod.env.enc

rm "$fixture/env/enc/prod.env.enc"
ln -s "$root/env/enc/prod.env.enc" "$fixture/env/enc/prod.env.enc"
expect_required_denied "symlinked required prod ciphertext" "required ciphertext env/enc/prod.env.enc missing, symlinked"
unlink "$fixture/env/enc/prod.env.enc"
cp "$root/env/enc/prod.env.enc" "$fixture/env/enc/prod.env.enc"

git -C "$fixture" reset -q HEAD -- env/enc/dev.env.enc env/enc/prod.env.enc
rm "$fixture/env/enc/dev.env.enc" "$fixture/env/enc/prod.env.enc"

run_check >"$log" 2>&1 || { cat "$log" >&2; exit 1; }
test ! -e "$fixture/env/dec" && test ! -L "$fixture/env/dec" \
  || { echo "FAIL: final audit created env/dec" >&2; exit 1; }
echo "PASS: keyless clean + real ciphertext controls; 38 adversarial cases (including malformed envelopes, comments, release ciphertext, forged markers, corrupt GCM, duplicate keys, and missing Git)"
