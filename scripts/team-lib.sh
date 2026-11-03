#!/bin/bash
# 团队表的读取函数，dispatch.sh 和 team.sh 共用。用 source 引入。
# 团队表找法（先找到先用）：$ZONGGUAN_TEAM，当前目录往上的 .zongguan/team.conf，~/.zongguan/team.conf

zg_trim() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }

zg_team_file() {
  if [ -n "${ZONGGUAN_TEAM:-}" ]; then printf '%s' "${ZONGGUAN_TEAM}"; return; fi
  local d; d="$(pwd -P)"
  while [ -n "$d" ] && [ "$d" != "/" ]; do
    if [ -f "$d/.zongguan/team.conf" ]; then printf '%s' "$d/.zongguan/team.conf"; return; fi
    d="$(dirname "$d")"
  done
  printf '%s' "$HOME/.zongguan/team.conf"
}

# 输出总管名字
zg_manager() {
  local f; f="$(zg_team_file)"; [ -f "$f" ] || return 1
  local line key val
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in \#*|'') continue ;; esac
    key="$(zg_trim "${line%%=*}")"; val="$(zg_trim "${line#*=}")"
    case "$key" in 总管|manager) printf '%s\n' "$val"; return 0 ;; esac
  done < "$f"
  return 1
}

# 每个成员输出一行，字段之间用 \037 分隔（空字段不会被吞）：名字 擅长 调用方式 写模式调用方式
ZG_SEP=$'\037'
zg_members() {
  local f; f="$(zg_team_file)"; [ -f "$f" ] || return 1
  local line key val name skill call wcall
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in \#*|'') continue ;; esac
    key="$(zg_trim "${line%%=*}")"; val="${line#*=}"
    case "$key" in 成员|member) ;; *) continue ;; esac
    IFS='|' read -r name skill call wcall <<<"$val"
    printf '%s\037%s\037%s\037%s\n' "$(zg_trim "$name")" "$(zg_trim "$skill")" "$(zg_trim "$call")" "$(zg_trim "${wcall:-}")"
  done < "$f"
}

# 按名字找成员，找到输出那一行；没找到返回 1，有重名返回 3
zg_lookup() {
  local want="$1" n line found="" cnt=0
  while IFS= read -r line; do
    n="${line%%$'\037'*}"
    if [ "$n" = "$want" ]; then found="$line"; cnt=$((cnt+1)); fi
  done < <(zg_members 2>/dev/null)
  [ "$cnt" -gt 1 ] && return 3
  [ "$cnt" = 1 ] || return 1
  printf '%s\n' "$found"
}

# 团队表可信吗：全局表、ZONGGUAN_TEAM 指定的表自动可信；项目里的表要用户 team.sh trust 过，且内容没变
ZG_TRUST_FILE="$HOME/.zongguan/trusted.txt"
zg_hash() { if command -v shasum >/dev/null; then shasum -a 256 "$1" | awk '{print $1}'; else sha256sum "$1" | awk '{print $1}'; fi; }
zg_trusted() {
  local f; f="$(zg_team_file)"
  [ -n "${ZONGGUAN_TEAM:-}" ] && return 0
  [ "$f" = "$HOME/.zongguan/team.conf" ] && return 0
  [ -f "$f" ] && [ -f "$ZG_TRUST_FILE" ] || return 1
  grep -qxF "$(cd "$(dirname "$f")" && pwd -P)/$(basename "$f") $(zg_hash "$f")" "$ZG_TRUST_FILE"
}
