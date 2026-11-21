#!/bin/bash
# Automated regression tests for heige-zongguan shell scripts (runs in an isolated temp dir).
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

PASS=0
FAIL=0

assert_eq() {
  local label="$1" got="$2" want="$3"
  if [ "${got}" = "${want}" ]; then
    printf '  PASS  %s\n' "${label}"
    PASS=$((PASS + 1))
  else
    printf '  FAIL  %s (got=%q want=%q)\n' "${label}" "${got}" "${want}" >&2
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local label="$1" hay="$2" needle="$3"
  if printf '%s' "${hay}" | grep -qF -- "${needle}"; then
    printf '  PASS  %s\n' "${label}"
    PASS=$((PASS + 1))
  else
    printf '  FAIL  %s (missing %q in output)\n' "${label}" "${needle}" >&2
    FAIL=$((FAIL + 1))
  fi
}

# Isolate HOME and CWD completely from the host environment.
REAL_HOME="${TMP}/real-home"
LINK_HOME="${TMP}/link-home"
mkdir -p "${REAL_HOME}"
ln -s "${REAL_HOME}" "${LINK_HOME}"
export HOME="${LINK_HOME}"
unset ZONGGUAN_HOME ZONGGUAN_TEAM ZONGGUAN_LOG_DIR ZONGGUAN_LEDGER ZONGGUAN_NOTIFY_CMD
cd "${TMP}"

echo "=== 1. Syntax check ==="
for f in "${REPO}/scripts/"*.sh; do
  bash -n "${f}"; assert_eq "bash -n $(basename "${f}")" "$?" "0"
done

echo "=== 2. team.sh add/remove duplicate & empty name handling ==="
bash "${REPO}/scripts/team.sh" init --manager "Claude Code" >/dev/null
assert_eq "team.sh init exits 0" "$?" "0"

out="$(bash "${REPO}/scripts/team.sh" add "   | 擅长 | manual" 2>&1)"; rc=$?
assert_eq "team.sh add rejects empty name" "${rc}" "2"
assert_contains "empty name error message" "${out}" "不能为空"

cat >> "${HOME}/.zongguan/team.conf" <<'EOF'
成员 = dup | 第一份 | manual
成员 = dup | 第二份 | manual
EOF
out="$(bash "${REPO}/scripts/team.sh" add "dup | 第三份 | manual" 2>&1)"; rc=$?
assert_eq "team.sh add rejects when duplicates already exist" "${rc}" "1"

out="$(bash "${REPO}/scripts/team.sh" remove dup 2>&1)"; rc=$?
assert_eq "team.sh remove succeeds when duplicates exist" "${rc}" "0"
if grep -q "dup" "${HOME}/.zongguan/team.conf"; then
  assert_eq "all duplicate rows removed" "present" "absent"
else
  assert_eq "all duplicate rows removed" "absent" "absent"
fi

echo "=== 3. Symlinked HOME global team.conf trust check ==="
mkdir -p "${HOME}/work dir/sub"
cat > "${HOME}/.zongguan/team.conf" <<'EOF'
总管 = claude
成员 = echoer | test | cmd:echo {prompt}
规则 = r1 | echoer | line1 | 做检查 | 只读 | 1 | 不通知
EOF
out="$(cd "${HOME}/work dir/sub" && bash "${REPO}/scripts/run-rule.sh" r1 -e "ev0" -n 2>&1)"; rc=$?
assert_eq "run-rule.sh trusts global team.conf under symlinked HOME" "${rc}" "0"
assert_contains "dry-run brief rendered" "${out}" "派给：echoer"

out="$(cd "${HOME}/work dir/sub" && bash "${REPO}/scripts/team.sh" trust 2>&1)"; rc=$?
assert_eq "team.sh trust recognizes global team.conf under symlinked HOME" "${rc}" "0"
assert_contains "global table message" "${out}" "全局团队表本来就可信"

echo "=== 4. Project team.conf trust prefix collision & enforcement ==="
mkdir -p "${TMP}/p/.zongguan" "${TMP}/prefix/p/.zongguan"
cat > "${TMP}/p/.zongguan/team.conf" <<'EOF'
总管 = claude
成员 = echoer | test | cmd:echo {prompt}
EOF
cp "${TMP}/p/.zongguan/team.conf" "${TMP}/prefix/p/.zongguan/team.conf"

# Untrusted project table must be rejected with exit 5.
out="$(cd "${TMP}/p" && bash "${REPO}/scripts/dispatch.sh" echoer "hi" 2>&1)"; rc=$?
assert_eq "untrusted project cmd exits 5" "${rc}" "5"

# Trust prefix/p, then trust p; prefix/p entry must remain intact.
(cd "${TMP}/prefix/p" && bash "${REPO}/scripts/team.sh" trust >/dev/null)
assert_eq "trust prefix/p" "$?" "0"
(cd "${TMP}/p" && bash "${REPO}/scripts/team.sh" trust >/dev/null)
assert_eq "trust p" "$?" "0"

# Inject a synthetic suffix-colliding line whose path ends with canonical p/.zongguan/team.conf
canon_p="$(cd "${TMP}/p/.zongguan" && pwd -P)/team.conf"
printf '/other%s deadbeef\n' "${canon_p}" >> "${HOME}/.zongguan/trusted.txt"
(cd "${TMP}/p" && bash "${REPO}/scripts/team.sh" trust >/dev/null)
assert_contains "prefix-colliding trusted entry preserved" "$(cat "${HOME}/.zongguan/trusted.txt")" "/other${canon_p} deadbeef"

out="$(cd "${TMP}/p" && bash "${REPO}/scripts/dispatch.sh" echoer -C "${HOME}/work dir" "hello world" 2>/dev/null)"; rc=$?
assert_eq "trusted project cmd executes in dir with spaces" "${rc}" "0"
assert_contains "dispatch output has prompt" "${out}" "hello world"

echo "=== 5. dispatch.sh manual exit 10, line lock exit 6, and stats.sh ==="
bash "${REPO}/scripts/team.sh" add "web | 查资料 | manual" >/dev/null
out="$(bash "${REPO}/scripts/dispatch.sh" web "查一下" 2>/dev/null)"; rc=$?
assert_eq "manual member exits 10" "${rc}" "10"
assert_contains "manual relay header" "${out}" "【手动转交】"

mkdir -p "${HOME}/.zongguan/locks/busy.1"
echo $$ > "${HOME}/.zongguan/locks/busy.1/pid"
out="$(bash "${REPO}/scripts/dispatch.sh" web -l busy -s 1 "blocked" 2>&1)"; rc=$?
assert_eq "saturated line lock exits 6" "${rc}" "6"
rm -rf "${HOME}/.zongguan/locks/busy.1"

out="$(bash "${REPO}/scripts/stats.sh" 2>&1)"; rc=$?
assert_eq "stats.sh exits 0" "${rc}" "0"
assert_contains "stats.sh totals ledger rows" "${out}" "合计"

echo "=== 6. run-rule.sh empty SEEN file, missing -E, stderr propagation, dedup ==="
KEY="r1|ev-empty-seen"
H="$(printf '%s' "${KEY}" | { command -v shasum >/dev/null && shasum -a 256 || sha256sum; } | awk '{print $1}')"
mkdir -p "${HOME}/.zongguan/seen"
: > "${HOME}/.zongguan/seen/${H}"
out="$(bash "${REPO}/scripts/run-rule.sh" r1 -e "ev-empty-seen" -n 2>&1)"; rc=$?
assert_eq "empty SEEN file does not crash" "${rc}" "0"
if printf '%s' "${out}" | grep -q "syntax error"; then
  assert_eq "no bash arithmetic syntax error" "found" "none"
else
  assert_eq "no bash arithmetic syntax error" "none" "none"
fi

out="$(bash "${REPO}/scripts/run-rule.sh" r1 -E "${TMP}/no-such-file.txt" -n 2>&1)"; rc=$?
assert_eq "missing -E file exits 2" "${rc}" "2"

cat > "${HOME}/.zongguan/team.conf" <<'EOF'
总管 = claude
成员 = broken | test | cmd:nonexistent_zongguan_cmd_xyz {prompt}
规则 = rbad\test | broken | linebad | 做检查 | 只读 | 1 | 每次
EOF
NOTIFY_LOG="${TMP}/notify.log"
cat > "${TMP}/fake-notify.sh" <<EOF
#!/bin/bash
printf '%s\n' "\$1" >> "${NOTIFY_LOG}"
EOF
chmod +x "${TMP}/fake-notify.sh"
out="$(ZONGGUAN_NOTIFY_CMD="${TMP}/fake-notify.sh" bash "${REPO}/scripts/run-rule.sh" 'rbad\test' -e "ev-fail" 2>&1)"; rc=$?
assert_eq "failed cmd dispatch exits 127" "${rc}" "127"
assert_contains "run-rule surfaces dispatch stderr" "${out}" "找不到命令 nonexistent_zongguan_cmd_xyz"
assert_contains "inbox.md records failure detail" "$(cat "${HOME}/.zongguan/inbox.md")" "找不到命令 nonexistent_zongguan_cmd_xyz"
assert_contains "notify script receives failure detail" "$(cat "${NOTIFY_LOG}")" "找不到命令 nonexistent_zongguan_cmd_xyz"

echo "=== 7. install.sh link/copy/uninstall in isolated HOME ==="
mkdir -p "${HOME}/.claude"
out="$(bash "${REPO}/scripts/install.sh" 2>&1)"; rc=$?
assert_eq "install.sh link exits 0" "${rc}" "0"
[ -L "${HOME}/.claude/skills/zongguan" ]; assert_eq "symlink installed" "$?" "0"
out="$(bash "${REPO}/scripts/install.sh" --copy 2>&1)"; rc=$?
assert_eq "install.sh --copy exits 0" "${rc}" "0"
[ -d "${HOME}/.claude/skills/zongguan" ] && [ ! -L "${HOME}/.claude/skills/zongguan" ]; assert_eq "copy installed" "$?" "0"
out="$(bash "${REPO}/scripts/install.sh" --uninstall 2>&1)"; rc=$?
assert_eq "install.sh --uninstall exits 0" "${rc}" "0"
[ ! -e "${HOME}/.claude/skills/zongguan" ]; assert_eq "uninstalled cleanly" "$?" "0"

echo
printf 'Result: %d passed, %d failed\n' "${PASS}" "${FAIL}"
[ "${FAIL}" -eq 0 ]
