#!/bin/bash
# publish.yml uploads to R2 and appends publish-log.jsonl. A fork with
# those secrets unset used to fail the report job (NoSuchBucket) after
# the publish itself had nothing to do. These cases run the workflow's
# own shell: empty credentials exit 0 before curl, docker, or rclone.
set -euo pipefail
ROOT=$(realpath "${BASH_SOURCE[0]%/*}/..")
failures=0

extract_run() {
  python3 - "$ROOT/.github/workflows/publish.yml" "$1" <<'PY'
import pathlib, re, sys
path, step = sys.argv[1], sys.argv[2]
lines = pathlib.Path(path).read_text().splitlines()
name_re = re.compile(r"^(\s*)- name: " + re.escape(step) + r"\s*$")
found = None
for i, line in enumerate(lines):
    match = name_re.match(line)
    if not match:
        continue
    name_indent = len(match.group(1))
    j = i + 1
    while j < len(lines):
        raw = lines[j]
        if raw.strip() == "":
            j += 1
            continue
        indent = len(raw) - len(raw.lstrip(" "))
        if indent <= name_indent and raw.lstrip().startswith("- "):
            break
        run = re.match(r"^(\s*)run:\s*\|[ \t]*$", raw)
        if run and indent > name_indent:
            run_indent = len(run.group(1))
            j += 1
            chunk = []
            while j < len(lines):
                nxt = lines[j]
                if nxt.strip() == "" or (len(nxt) - len(nxt.lstrip(" "))) > run_indent:
                    chunk.append(nxt)
                    j += 1
                else:
                    break
            nonempty = [c for c in chunk if c.strip()]
            pad = min(len(c) - len(c.lstrip(" ")) for c in nonempty)
            found = "\n".join(c[pad:] if c.strip() else "" for c in chunk) + "\n"
            break
        j += 1
    if found is not None:
        break
if found is None:
    sys.exit(f"no run script for step {step!r}")
sys.stdout.write(found)
PY
}

# Actions substitutes ${{ }} before bash. The tests replace those
# expressions so the extracted script can run locally.
substitute() {
  python3 -c 'import re,sys; sys.stdout.write(re.sub(r"\$\{\{.*?\}\}", "test-value", sys.stdin.read()).replace("--arg outcome \"test-value\"", "--arg outcome \"success\""))'
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
bin="$work/bin"
mkdir -p "$bin"
called="$work/called"
touch "$called"
export CALLED="$called"
for cmd in curl docker rclone unzip sha256sum; do
  cat > "$bin/$cmd" <<'EOF'
#!/bin/bash
echo "$0" >> "$CALLED"
exit 99
EOF
  chmod +x "$bin/$cmd"
done

publish_script=$work/publish.sh
log_script=$work/log.sh
render_script=$work/render.sh
extract_run "Publish" | substitute > "$publish_script"
extract_run "Append to the publish log in the bucket" | substitute > "$log_script"
extract_run "Render" | substitute > "$render_script"

matrix='{"include":[{"package":"foo","arch":"x86_64","channels":"edge","publish_arches":"x86_64"}]}'

reset_tree() {
  rm -rf "$work/tree"
  mkdir -p "$work/tree"
  printf '%s\n' '{"package":"foo","arch":"x86_64","source":"pr-artifact"}' > "$work/tree/sources.jsonl"
  : > "$called"
}

run_in_tree() {
  (
    cd "$work/tree"
    env -u RCLONE_CONFIG_R2_ACCESS_KEY_ID \
      -u RCLONE_CONFIG_R2_SECRET_ACCESS_KEY \
      -u RCLONE_CONFIG_R2_ENDPOINT \
      PATH="$bin:$PATH" \
      PLAN_MATRIX="$matrix" \
      CALLED="$called" \
      "$@"
  )
}

check() {
  local name=$1 status=$2
  if [[ $status -eq 0 ]]; then
    echo "PASS: $name"
  else
    echo "FAIL: $name"
    failures=1
  fi
}

# Packages to upload, no credentials: succeed, record the skip, do not
# reach docker or rclone.
reset_tree
mkdir -p "$work/tree/build-output/edge/x86_64"
touch "$work/tree/build-output/edge/x86_64/foo-1.0-1-x86_64.pkg.tar.zst"
if run_in_tree bash "$publish_script" >"$work/out" 2>"$work/err"; then
  publish_status=0
else
  publish_status=$?
fi
ok=0
[[ $publish_status -eq 0 ]] || ok=1
grep -q 'skipping publish' "$work/out" || ok=1
[[ ! -s "$called" ]] || ok=1
jq -e '.note == "r2-credentials-missing" and .slots == []' "$work/tree/publish-record.json" >/dev/null || ok=1
check "publish step skips the upload when R2 credentials are unset" $ok

# One of the three set is still not enough. GitHub passes an unset secret
# as an empty string; cover both.
reset_tree
mkdir -p "$work/tree/build-output/edge/x86_64"
touch "$work/tree/build-output/edge/x86_64/foo-1.0-1-x86_64.pkg.tar.zst"
if (
  cd "$work/tree"
  env RCLONE_CONFIG_R2_ACCESS_KEY_ID=present \
    RCLONE_CONFIG_R2_SECRET_ACCESS_KEY= \
    RCLONE_CONFIG_R2_ENDPOINT= \
    PATH="$bin:$PATH" \
    PLAN_MATRIX="$matrix" \
    CALLED="$called" \
    bash "$publish_script" >"$work/out" 2>"$work/err"
); then
  partial_status=0
else
  partial_status=$?
fi
ok=0
[[ $partial_status -eq 0 ]] || ok=1
[[ ! -s "$called" ]] || ok=1
jq -e '.note == "r2-credentials-missing"' "$work/tree/publish-record.json" >/dev/null || ok=1
check "publish step skips when only one R2 credential is set" $ok

# All three credentials set: do not take the skip. docker is the next
# command, and the stub makes it fail before any upload.
reset_tree
mkdir -p "$work/tree/build-output/edge/x86_64"
touch "$work/tree/build-output/edge/x86_64/foo-1.0-1-x86_64.pkg.tar.zst"
if (
  cd "$work/tree"
  env RCLONE_CONFIG_R2_ACCESS_KEY_ID=present \
    RCLONE_CONFIG_R2_SECRET_ACCESS_KEY=present \
    RCLONE_CONFIG_R2_ENDPOINT=https://example.test \
    PATH="$bin:$PATH" \
    PLAN_MATRIX="$matrix" \
    CALLED="$called" \
    bash "$publish_script" >"$work/out" 2>"$work/err"
); then
  live_publish_status=0
else
  live_publish_status=$?
fi
ok=0
[[ $live_publish_status -ne 0 ]] || ok=1
grep -q '/docker$' "$called" || ok=1
[[ ! -f "$work/tree/publish-record.json" ]] || ok=1
grep -q 'skipping publish' "$work/out" && ok=1
check "publish step does not skip when R2 credentials are set" $ok

# Nothing to upload: the existing short-circuit still wins, and it does
# not claim the credentials were missing.
reset_tree
if run_in_tree bash "$publish_script" >"$work/out" 2>"$work/err"; then
  empty_status=0
else
  empty_status=$?
fi
ok=0
[[ $empty_status -eq 0 ]] || ok=1
grep -q 'already published' "$work/out" || ok=1
[[ ! -s "$called" ]] || ok=1
jq -e 'has("note") | not' "$work/tree/publish-record.json" >/dev/null || ok=1
check "already-published short-circuit does not require R2" $ok

# The log step is what failed run 40961748433. Empty keys must not curl.
reset_tree
printf '%s\n' '{}' > "$work/tree/publish-record.json"
if run_in_tree bash -e "$log_script" >"$work/out" 2>"$work/err"; then
  log_status=0
else
  log_status=$?
fi
ok=0
[[ $log_status -eq 0 ]] || ok=1
grep -q 'skipping the publish log' "$work/out" || ok=1
[[ ! -s "$called" ]] || ok=1
check "publish log skips rclone when R2 credentials are unset" $ok

# Credentials present: the log step still tries to download rclone.
reset_tree
printf '%s\n' '{}' > "$work/tree/publish-record.json"
if (
  cd "$work/tree"
  env RCLONE_CONFIG_R2_ACCESS_KEY_ID=present \
    RCLONE_CONFIG_R2_SECRET_ACCESS_KEY=present \
    RCLONE_CONFIG_R2_ENDPOINT=https://example.test \
    PATH="$bin:$PATH" \
    CALLED="$called" \
    bash -e "$log_script" >"$work/out" 2>"$work/err"
); then
  live_status=0
else
  live_status=$?
fi
ok=0
[[ $live_status -ne 0 ]] || ok=1
grep -q '/curl$' "$called" || ok=1
check "publish log still fetches rclone when R2 credentials are set" $ok

render_case() {
  local name=$1 record=$2 want=$3 absent=$4
  printf '%s\n' "$record" > "$work/tree/publish-record.json"
  if (cd "$work/tree" && bash "$render_script" >"$work/out" 2>"$work/err"); then
    :
  else
    echo "FAIL: $name (render exited $?)"
    cat "$work/err"
    failures=1
    return
  fi
  local comment
  comment=$(cat "$work/tree/comment.md")
  if grep -q "$want" <<<"$comment" && ! grep -q "$absent" <<<"$comment"; then
    echo "PASS: $name"
  else
    echo "FAIL: $name"
    printf '%s\n' "$comment"
    failures=1
  fi
}

reset_tree
render_case "comment names a missing R2 configuration" \
  '{"commit":"f7e1ea7c5e417ec9ca7730255756c6894b9804d1","run":"https://example.test/run","target":"live","plan":[{"package":"foo"}],"sources":[{"package":"foo","arch":"x86_64","source":"pr-artifact"}],"slots":[],"note":"r2-credentials-missing"}' \
  "R2 credentials are not set" \
  "earlier slot failed"
render_case "comment still reports an already-published package" \
  '{"commit":"f7e1ea7c5e417ec9ca7730255756c6894b9804d1","run":"https://example.test/run","target":"live","plan":[{"package":"foo"}],"sources":[{"package":"foo","arch":"aarch64","source":"already-published"}],"slots":[]}' \
  "already at master's version everywhere" \
  "R2 credentials are not set"
render_case "comment still lists a published slot" \
  '{"commit":"f7e1ea7c5e417ec9ca7730255756c6894b9804d1","run":"https://example.test/run","target":"live","plan":[{"package":"foo"}],"sources":[{"package":"foo","arch":"x86_64","source":"pr-artifact"}],"slots":[{"mirror":"edge","arch":"x86_64","status":"published","packages":["foo-1.0-1-x86_64"]}]}' \
  "edge/x86_64" \
  "R2 credentials are not set"

# The skip has to stay ahead of the upload. A later edit that moves the
# check below docker would still pass a text search, so the runs above
# are the proof. This only catches a deleted notice.
grep -q 'skipping publish' "$publish_script" \
  && echo "PASS: publish script contains the skip notice" \
  || { echo "FAIL: publish script lost the skip notice"; failures=1; }
grep -q 'skipping the publish log' "$log_script" \
  && echo "PASS: log script contains the skip notice" \
  || { echo "FAIL: log script lost the skip notice"; failures=1; }

exit "$failures"
