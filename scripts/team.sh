#!/bin/bash
# 总管工作法：团队表管理。谁当总管、谁当成员，由用户自己定。
# 用法：
#   team.sh init [--manager 名字] [--force]   探测本机装了哪些 AI，生成团队表草稿
#   team.sh show                               看当前团队表
#   team.sh check [--ping]                     检查每个成员能不能调用；--ping 真派一句话试试
#   team.sh set-manager 名字                   指定总管
#   team.sh add "名字 | 擅长 | 调用方式 | 写模式调用方式（可省）"
#   team.sh remove 名字
#   规则写法见 references/automation.md；触发规则用 run-rule.sh
#   team.sh trust                              信任当前项目的团队表（项目表里的自定义命令要信任后才执行；表一改要重新信任）
# 调用方式：preset:codex | preset:claude | preset:kimi | preset:antigravity
#           cmd:命令模板（{prompt} 换成简报，{dir} 换成工作目录）
#           manual（没有命令行，总管写好简报，用户复制过去，再把结论贴回来）
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd -P)"
# shellcheck source=team-lib.sh
. "${HERE}/team-lib.sh"
F="$(zg_team_file)"
CMD="${1:-show}"; shift || true

has() { command -v "$1" >/dev/null 2>&1; }
ag_ok() { has agentapi || [ -x "$HOME/.gemini/antigravity/bin/agentapi" ]; }

write_draft() {
  local manager="$1"
  mkdir -p "$(dirname "${F}")"
  {
    echo "# 总管工作法 团队表（$(date +%Y-%m-%d) 由 team.sh init 生成，可直接手改）"
    echo "#"
    echo "# 总管：你平时直接对话的那个 AI，只写一个。换总管就改这一行。"
    echo "# 成员：每行一个，用 | 分成四段：名字 | 擅长什么 | 调用方式 | 写模式调用方式（可省）"
    echo "#   调用方式三选一："
    echo "#   preset:codex / preset:claude / preset:kimi / preset:antigravity  用内置做法（只读控制最完整）"
    echo "#   cmd:命令模板   {prompt} 会换成简报，{dir} 换成工作目录；命令里不要出现 | ，复杂命令先包成脚本"
    echo "#   manual         没有命令行的产品（网页版、桌面 App），总管写好简报，你复制过去，再把结论贴回来"
    echo "#   擅长什么：按你自己实测的结果填，总管派单时照这一栏挑人。"
    echo
    echo "总管 = ${manager}"
    echo
    has codex && echo "成员 = codex | 写代码、查 bug、代码审查（请按实测改） | preset:codex"
    has claude && echo "成员 = claude | 写作、方案、代码（请按实测改） | preset:claude"
    has kimi && echo "成员 = kimi | 读长篇中文材料（请按实测改） | preset:kimi"
    ag_ok && echo "成员 = antigravity | 第二意见（请按实测改） | preset:antigravity"
    echo
    echo "# 下面是探测到、但参数要你按自己装的版本核对的工具，核对后去掉行首的 # 才生效："
    has gemini && echo "# 成员 = gemini | 擅长 | cmd:gemini -p {prompt}"
    has qwen && echo "# 成员 = qwen | 擅长 | cmd:qwen -p {prompt}"
    has codebuddy && echo "# 成员 = codebuddy | 擅长 | cmd:codebuddy -p {prompt}"
    has opencode && echo "# 成员 = opencode | 擅长 | cmd:opencode run {prompt}"
    has cursor-agent && echo "# 成员 = cursor | 擅长 | cmd:cursor-agent -p {prompt}"
    has dsh && echo "# 成员 = dsh | 擅长 | cmd:dsh headless {prompt}"
    echo "# 没有命令行的产品，用手动接力，例如："
    echo "# 成员 = workbuddy | 做表格、办公文档 | manual"
    echo "# 成员 = 豆包网页版 | 查资料 | manual"
  } > "${F}"
}

case "${CMD}" in
  init)
    MANAGER="（请填写：你平时直接对话的那个 AI）"; FORCE=0
    while [ $# -gt 0 ]; do
      case "$1" in
        --manager) [ $# -ge 2 ] && [ -n "$2" ] || { echo "--manager 后面要写总管名字" >&2; exit 2; }; MANAGER="$2"; shift 2 ;;
        --force) FORCE=1; shift ;;
        *) echo "未知参数：$1" >&2; exit 2 ;;
      esac
    done
    if [ -f "${F}" ] && [ "${FORCE}" = 0 ]; then echo "团队表已存在：${F}（要重建加 --force，旧表会备份）"; exit 1; fi
    if [ -f "${F}" ]; then cp "${F}" "${F}.bak-$(date +%Y%m%d-%H%M%S)" || { echo "旧表备份失败，没有改动" >&2; exit 1; }; fi
    write_draft "${MANAGER}" || { echo "写团队表失败：${F}" >&2; exit 1; }
    echo "已生成团队表：${F}"; echo; cat "${F}"
    ;;
  show)
    [ -f "${F}" ] || { echo "还没有团队表（${F}）。先运行：team.sh init --manager 你的总管"; exit 1; }
    echo "团队表：${F}"
    echo "总管：$(zg_manager || echo '（未指定）')"
    echo "成员："
    zg_members | while IFS="${ZG_SEP}" read -r n s c w; do
      printf '  %-14s 擅长：%s\n  %-14s 调用：%s%s\n' "$n" "$s" "" "$c" "${w:+；写模式：$w}"
    done
    if [ -n "$(zg_rules 2>/dev/null)" ]; then
      echo "规则："
      zg_rules | while IFS="${ZG_SEP}" read -r rn rm rl ri rp rpar rnoti rdir; do
        printf '  %-14s 派给 %s，线 %s，%s，并行 %s，通知：%s\n  %-14s 指令：%s\n' "$rn" "$rm" "${rl:-$rn}" "${rp:-只读}" "${rpar:-1}" "${rnoti:-需要时}" "" "$ri"
      done
    fi
    ;;
  check)
    PING=0; [ "${1:-}" = "--ping" ] && PING=1
    [ -f "${F}" ] || { echo "还没有团队表：${F}" >&2; exit 1; }
    BAD=0
    while IFS="${ZG_SEP}" read -r n s c w; do
      kind="${c%%:*}"; arg="${c#*:}"; st="正常"
      case "${kind}" in
        preset)
          case "${arg}" in
            codex|claude|kimi) has "${arg}" || st="找不到 ${arg} 命令" ;;
            antigravity) ag_ok || st="找不到 agentapi（没装 Antigravity）" ;;
            *) st="不认识的预设 ${arg}" ;;
          esac ;;
        cmd) read -r -a _tok <<<"${arg}"; first="${_tok[0]:-}"; has "${first}" || st="找不到命令 ${first}" ;;
        manual) st="手动接力（不用检查）" ;;
        *) st="调用方式写错了：${c}" ;;
      esac
      if [ "${st}" = "正常" ] && [ "${PING}" = 1 ]; then
        extra=(); [ "${c}" = "preset:antigravity" ] && extra=(-o "${TMPDIR:-/tmp}/zongguan-ping-$$.md")
        r=$(bash "${HERE}/dispatch.sh" "${n}" -t 300 "${extra[@]+"${extra[@]}"}" "这是连通测试，只回复两个字：收到。" 2>/dev/null | tail -3 | tr '\n' ' '); prc=${PIPESTATUS[0]}
        if [ "${prc}" = 0 ] && echo "${r}" | grep -q "收到"; then st="正常，已真派一单"; else st="命令在，但试派失败（退出码 ${prc}）：${r:0:80}"; fi
      fi
      case "${st}" in 正常*|手动*) ;; *) BAD=$((BAD+1)) ;; esac
      printf '  %-14s %s\n' "${n}" "${st}"
    done < <(zg_members)
    echo "总管：$(zg_manager || echo '（未指定）')"
    [ "${BAD}" = 0 ] || exit 1
    ;;
  set-manager)
    [ -n "${1:-}" ] || { echo "要写总管名字" >&2; exit 2; }
    [ -f "${F}" ] || write_draft "$1"
    tmp="${F}.tmp.$$"
    if grep -q -E '^[[:space:]]*(总管|manager)[[:space:]]*=' "${F}"; then
      ZG_M="$1" awk '{ if ($0 ~ /^[[:space:]]*(总管|manager)[[:space:]]*=/) print "总管 = " ENVIRON["ZG_M"]; else print }' "${F}" > "${tmp}" || { rm -f "${tmp}"; echo "改表失败" >&2; exit 1; }
    else
      { echo "总管 = $1"; cat "${F}"; } > "${tmp}" || { rm -f "${tmp}"; echo "改表失败" >&2; exit 1; }
    fi
    mv "${tmp}" "${F}" || exit 1; echo "总管已改为：$1"
    ;;
  add)
    [ -n "${1:-}" ] || { echo '格式：team.sh add "名字 | 擅长 | 调用方式"' >&2; exit 2; }
    n="$(zg_trim "${1%%|*}")"
    zg_lookup "${n}" >/dev/null && { echo "已有成员 ${n}，先 remove 再加" >&2; exit 1; }
    case "$1" in *"|"*"|"*) ;; *) echo '至少要三段：名字 | 擅长 | 调用方式' >&2; exit 2 ;; esac
    mkdir -p "$(dirname "${F}")"
    if [ -s "${F}" ] && [ -n "$(tail -c 1 "${F}")" ]; then echo >> "${F}"; fi
    echo "成员 = $1" >> "${F}" || { echo "写团队表失败" >&2; exit 1; }
    echo "已加成员：${n}"
    ;;
  remove)
    [ -n "${1:-}" ] || { echo "要写成员名字" >&2; exit 2; }
    zg_lookup "$1" >/dev/null || { echo "没有成员 $1" >&2; exit 1; }
    tmp="${F}.tmp.$$"
    ZG_N="$1" awk -F'|' '{
      line=$0
      if (line ~ /^[[:space:]]*(成员|member)[[:space:]]*=/) {
        name=$1; sub(/^[^=]*=/, "", name); gsub(/^[[:space:]]+|[[:space:]]+$/, "", name)
        if (name == ENVIRON["ZG_N"]) next
      }
      print line }' "${F}" > "${tmp}" && mv "${tmp}" "${F}" || { rm -f "${tmp}"; echo "改表失败" >&2; exit 1; }
    echo "已移除成员：$1"
    ;;
  trust)
    [ -f "${F}" ] || { echo "没有团队表：${F}" >&2; exit 1; }
    if [ "${F}" = "$HOME/.zongguan/team.conf" ]; then echo "全局团队表本来就可信，不用 trust"; exit 0; fi
    echo "要信任的团队表：${F}"; echo "里面的自定义命令："; grep -n -E '\|[[:space:]]*cmd:' "${F}" || echo "  （没有）"
    mkdir -p "$(dirname "${ZG_TRUST_FILE}")"
    abs="$(cd "$(dirname "${F}")" && pwd -P)/$(basename "${F}")"
    grep -v -F "${abs} " "${ZG_TRUST_FILE}" 2>/dev/null > "${ZG_TRUST_FILE}.tmp"
    echo "${abs} $(zg_hash "${F}")" >> "${ZG_TRUST_FILE}.tmp" && mv "${ZG_TRUST_FILE}.tmp" "${ZG_TRUST_FILE}" && chmod 600 "${ZG_TRUST_FILE}"
    echo "已信任。团队表内容一改，需要重新 trust。"
    ;;
  *) echo "未知命令：${CMD}（可选 init、show、check、set-manager、add、remove、trust）" >&2; exit 2 ;;
esac
