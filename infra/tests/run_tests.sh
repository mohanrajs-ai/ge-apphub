#!/usr/bin/env bash
# Master Automated Test Runner & Coverage Reporter
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
COVERAGE_DIR="${PROJECT_ROOT}/.coverage"
rm -rf "${COVERAGE_DIR}"
mkdir -p "${COVERAGE_DIR}"

echo "============================================================"
echo " Gemini Enterprise Deployment Automation — Test Suite"
echo "============================================================"

# 1. Bash Syntax Check (-n) across all scripts
echo "[1/3] Validating Bash syntax (bash -n)..."
while IFS= read -r -d '' sh_file; do
  bash -n "${sh_file}"
done < <(find "${PROJECT_ROOT}" -name "*.sh" -not -path "*/.git/*" -print0)
echo "  [OK] All shell scripts passed syntax check."

# 2. Execute all test_*.sh files with xtrace line tracking
echo "[2/3] Executing unit and integration test suites..."
TRACE_FILE="${COVERAGE_DIR}/xtrace.log"
: > "${TRACE_FILE}"

SUITE_COUNT=0
for test_file in "${SCRIPT_DIR}"/test_*.sh; do
  [[ "$(basename "${test_file}")" == "test_helper.sh" ]] && continue
  SUITE_COUNT=$((SUITE_COUNT + 1))
  PS4='+TRACE:${BASH_SOURCE[0]:-unknown}:${LINENO}: ' bash -x "${test_file}" 2> >(grep '^+*TRACE:' >> "${TRACE_FILE}" || true)
done

echo "  [OK] All ${SUITE_COUNT} test suite(s) passed."

# 3. Compute code coverage across scripts/ and deploy.sh
echo "[3/3] Computing line coverage across implementation scripts..."
python3 - "${PROJECT_ROOT}" "${TRACE_FILE}" <<'PYEOF'
import os
import re
import sys

project_root = os.path.realpath(sys.argv[1])
trace_file = sys.argv[2]

executed = set()
trace_re = re.compile(r'^\++TRACE:([^:]+):(\d+): ')
with open(trace_file, 'r', encoding='utf-8', errors='ignore') as f:
    for line in f:
        m = trace_re.match(line)
        if m:
            filepath = os.path.realpath(m.group(1))
            lineno = int(m.group(2))
            executed.add((filepath, lineno))

target_files = []
scripts_dir = os.path.join(project_root, 'scripts')
if os.path.isdir(scripts_dir):
    for root, _, files in os.walk(scripts_dir):
        for fn in sorted(files):
            if fn.endswith('.sh'):
                target_files.append(os.path.realpath(os.path.join(root, fn)))
deploy_sh = os.path.realpath(os.path.join(project_root, 'deploy.sh'))
if os.path.isfile(deploy_sh):
    target_files.append(deploy_sh)

if not target_files:
    print("  [INFO] No implementation scripts in scripts/ or deploy.sh yet (Coverage: 100.0%).")
    sys.exit(0)

total_coverable = 0
total_hit = 0

skip_re = re.compile(r'^\s*(#|$|then$|else$|fi$|do$|done$|esac$|\{$|\}$|\(\)\s*\{$|;;$|[a-zA-Z0-9_*|-]+\)$)')

for tf in target_files:
    rel = os.path.relpath(tf, project_root)
    file_cov = 0
    file_hit = 0
    in_heredoc = False
    heredoc_delim = None
    prev_continued = False
    with open(tf, 'r', encoding='utf-8') as f:
        for idx, raw in enumerate(f, start=1):
            stripped = raw.strip()
            if in_heredoc:
                if stripped == heredoc_delim:
                    in_heredoc = False
                continue
            hd = re.search(r"<<-?\s*['\"]?([A-Za-z0-9_]+)['\"]?", stripped)
            if hd:
                in_heredoc = True
                heredoc_delim = hd.group(1)
            is_continued = stripped.endswith('\\')
            if prev_continued:
                prev_continued = is_continued
                continue
            prev_continued = is_continued
            if skip_re.match(stripped):
                continue
            file_cov += 1
            if (tf, idx) in executed:
                file_hit += 1
    total_coverable += file_cov
    total_hit += file_hit
    pct = (file_hit / file_cov * 100.0) if file_cov > 0 else 100.0
    print(f"  - {rel}: {file_hit}/{file_cov} lines ({pct:.1f}%)")

overall = (total_hit / total_coverable * 100.0) if total_coverable > 0 else 100.0
print(f"  [COVERAGE] Total: {total_hit}/{total_coverable} lines ({overall:.1f}%)")
if overall < 80.0:
    print(f"  [FAIL] Coverage {overall:.1f}% is below 80.0% threshold!", file=sys.stderr)
    sys.exit(1)
PYEOF
