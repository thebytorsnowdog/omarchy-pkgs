#!/bin/bash
# workflow_dispatch inputs and job outputs are data. A run: script that
# pastes them in is parsed as shell, and publish.yml's publish job has the
# signing key and the bucket credentials in its environment.
set -euo pipefail
ROOT=$(realpath "${BASH_SOURCE[0]%/*}/..")
failures=0

python3 - "$ROOT" <<'PY'
import pathlib, re, sys
root = pathlib.Path(sys.argv[1]) / ".github/workflows"
bad = []
for path in sorted(root.glob("*.yml")):
    lines = path.read_text().splitlines()
    i = 0
    while i < len(lines):
        line = lines[i]
        block = re.match(r"^(\s*)run:\s*\|[ \t]*$", line)
        inline = re.match(r"^(\s*)run:\s+\S", line)
        if not block and not inline:
            i += 1
            continue
        if inline:
            script = line
            where = f"{path.name}:{i+1}"
            i += 1
        else:
            indent = len(block.group(1))
            start = i + 1
            i += 1
            chunk = []
            while i < len(lines) and (lines[i].strip() == "" or (len(lines[i]) - len(lines[i].lstrip(" "))) > indent):
                chunk.append(lines[i])
                i += 1
            script = "\n".join(chunk)
            where = f"{path.name}:{start}"
        if "${{ github.event.inputs" in script:
            bad.append(f"{where}: run script inlines github.event.inputs")
        if "${{ needs." in script and ".outputs" in script:
            bad.append(f"{where}: run script inlines a job output")
if bad:
    print("\n".join(bad))
    sys.exit(1)
print(f"PASS: no workflow run script inlines inputs or job outputs")
PY

# A name that is not an Arch pkgname must not reach a workflow matrix.
if printf "%s\n" "foo';curl" | "$ROOT/bin/build-matrix" >/dev/null 2>"$ROOT/tests/.build-matrix-name.err"; then
  echo "FAIL: build-matrix accepted a package name with a shell quote"
  failures=1
else
  grep -q "Invalid package name" "$ROOT/tests/.build-matrix-name.err" \
    && echo "PASS: build-matrix rejects a package name that is not an Arch pkgname" \
    || { echo "FAIL: build-matrix failed for another reason"; cat "$ROOT/tests/.build-matrix-name.err"; failures=1; }
fi
rm -f "$ROOT/tests/.build-matrix-name.err"

matrix=$(printf '%s\n' aether | CI_ARCHES=x86_64 "$ROOT/bin/build-matrix")
[[ "$matrix" == *'"package":"aether"'* ]] \
  && echo "PASS: build-matrix still plans a real package" \
  || { echo "FAIL: build-matrix dropped aether: $matrix"; failures=1; }

exit "$failures"
