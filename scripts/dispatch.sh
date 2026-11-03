#!/bin/bash
# 总管工作法：派外部 AI 的统一入口
# 用法：dispatch.sh <成员名> [-C 工作目录] [-w] [-m 模型] [-t 超时秒] [-o 结果文件] [-f 简报文件 | "简报"]
#   成员名：团队表（team.sh show）里的名字；没建团队表时，也可直接写 codex、claude、kimi、antigravity、custom
#   退出码 10：这个成员是手动接力，简报已打印，等用户转交后把结论贴回来
#   简报以 - 开头时，在简报前加 -- ，例如 dispatch.sh codex -- "-简报"
#   -w  允许写文件；默认只读（codex 硬沙箱并关掉 MCP；claude 限定只读工具并关掉 MCP；kimi、antigravity、custom 只能靠简报叮嘱）
#   -o  antigravity 用：让子对话把最终结果写进这个文件，脚本等文件出现再返回；不给就只开对话、立刻返回
# 结论打到 stdout，完整日志在 $ZONGGUAN_LOG_DIR（默认 ~/.zongguan/logs，仅本人可读）
set -uo pipefail
umask 077
HERE="$(cd "$(dirname "$0")" && pwd -P)"

AGENT="${1:-}"; shift || true
DIR="$PWD"; WRITE=0; MODEL=""; TIMEOUT=1800; PFILE=""; RESULT=""
while getopts "C:wm:t:f:o:" opt; do
  case $opt in
    C) DIR="$OPTARG" ;; w) WRITE=1 ;; m) MODEL="$OPTARG" ;;
    t) TIMEOUT="$OPTARG" ;; f) PFILE="$OPTARG" ;; o) RESULT="$OPTARG" ;;
    *) exit 2 ;;
  esac
done
shift $((OPTIND - 1))
case "${TIMEOUT}" in ''|*[!0-9]*) echo "超时必须是正整数秒：${TIMEOUT}" >&2; exit 2 ;; esac
if [ "${TIMEOUT}" -lt 10 ] || [ "${TIMEOUT}" -gt 86400 ]; then echo "超时要在 10 到 86400 秒之间" >&2; exit 2; fi
if [ -n "${PFILE}" ]; then PROMPT=$(cat "${PFILE}") || exit 2; else PROMPT="${1:-}"; fi
[ -z "${PROMPT}" ] && { echo "缺少简报" >&2; exit 2; }
cd "${DIR}" || { echo "工作目录不存在：${DIR}" >&2; exit 2; }
DIR=$(pwd -P)

# 按团队表找这个成员怎么调用
# shellcheck source=team-lib.sh
. "${HERE}/team-lib.sh"
CALL=""; WCALL=""; TEAM_FILE="$(zg_team_file)"
ROW="$(zg_lookup "${AGENT}")"; LRC=$?
if [ "${LRC}" = 3 ]; then echo "团队表里有多个叫「${AGENT}」的成员，请改成不重名：${TEAM_FILE}" >&2; exit 2; fi
if [ "${LRC}" = 0 ]; then
  IFS="${ZG_SEP}" read -r _n _skill CALL WCALL <<<"${ROW}"
elif [ -f "${TEAM_FILE}" ] && [ "${AGENT}" != custom ]; then
  echo "团队表里没有成员「${AGENT}」。现有成员：" >&2; zg_members 2>/dev/null | cut -d"${ZG_SEP}" -f1 | sed 's/^/  /' >&2
  echo "团队表：${TEAM_FILE}（用 team.sh add 加成员）" >&2; exit 2
fi
if [ -z "${CALL}" ]; then
  case "${AGENT}" in
    codex|claude|kimi|antigravity) CALL="preset:${AGENT}" ;;
    custom) CALL="cmd:${ZONGGUAN_CUSTOM_CMD:-}" ;;
    *) echo "团队表里没有成员「${AGENT}」。现有成员：" >&2; zg_members 2>/dev/null | cut -d"${ZG_SEP}" -f1 | sed 's/^/  /' >&2
       echo "团队表：$(zg_team_file)（用 team.sh add 加成员）" >&2; exit 2 ;;
  esac
fi
USED_WCALL=0
if [ "${WRITE}" = 1 ] && [ -n "${WCALL}" ]; then CALL="${WCALL}"; USED_WCALL=1; fi
KIND="${CALL%%:*}"; ARG="${CALL#*:}"
case "${KIND}" in
  preset) RUN="${ARG}" ;;
  cmd) RUN=cmd; [ -n "${ARG}" ] || { echo "成员「${AGENT}」的命令模板是空的" >&2; exit 2; }
       if [ "${LRC}" = 0 ] && ! zg_trusted; then
         echo "这张项目团队表还没被你信任过，不执行里面的自定义命令：${TEAM_FILE}" >&2
         echo "先打开看一遍，确认命令没问题后运行：bash ${HERE}/team.sh trust" >&2; exit 5
       fi ;;
  manual) RUN=manual ;;
  *) echo "成员「${AGENT}」的调用方式写错了：${CALL}（应为 preset:、cmd: 或 manual）" >&2; exit 2 ;;
esac
SAFE_NAME="$(printf '%s' "${AGENT}" | tr '/ ' '__')"

LOG_DIR="${ZONGGUAN_LOG_DIR:-$HOME/.zongguan/logs}"; mkdir -p "${LOG_DIR}"; chmod 700 "${LOG_DIR}" 2>/dev/null
TS=$(date +%Y%m%d-%H%M%S)-$$
LOG="${LOG_DIR}/${TS}-${SAFE_NAME}.log"; OUT="${LOG_DIR}/${TS}-${SAFE_NAME}.last.md"

READONLY_NOTE="【硬性约束】本次任务只读：禁止新建、修改、删除任何文件，禁止执行有副作用的命令，只读取和回答。完整结果直接写在回复里。"
soft_readonly() {
  if [ "${WRITE}" = 0 ]; then
    PROMPT="${READONLY_NOTE}

${PROMPT}"
    echo "[dispatch] 提醒：${AGENT} 没有硬沙箱，只读只靠简报约束" >&2
  fi
}

# 在独立进程组里运行，超时连同子进程一起结束；命令起不来返回 127
run_with_timeout() {
  perl -e '
    my $t = shift;
    my $pid = fork;
    die "fork 失败\n" unless defined $pid;
    if ($pid == 0) { setpgrp(0, 0); exec { $ARGV[0] } @ARGV or do { print STDERR "无法启动 $ARGV[0]：$!\n"; exit 127 }; }
    $SIG{ALRM} = sub { kill "TERM", -$pid; sleep 3; kill "KILL", -$pid; print STDERR "[dispatch] 超时 ${t}s，已结束整组进程\n"; exit 142 };
    alarm $t; waitpid($pid, 0); alarm 0;
    exit($? & 127 ? 128 + ($? & 127) : $? >> 8);
  ' "${TIMEOUT}" "$@" </dev/null >"${LOG}" 2>&1
}

RC=0
case "${RUN}" in
  codex)
    command -v codex >/dev/null || { echo "找不到 codex 命令" >&2; exit 127; }
    SB=read-only; [ "${WRITE}" = 1 ] && SB=workspace-write
    CMD=(codex exec --skip-git-repo-check -C "${DIR}" -s "${SB}" -o "${OUT}")
    [ "${WRITE}" = 0 ] && CMD+=(-c 'mcp_servers={}')
    [ -n "${MODEL}" ] && CMD+=(-m "${MODEL}")
    run_with_timeout "${CMD[@]}" -- "${PROMPT}"; RC=$?
    ;;
  claude)
    command -v claude >/dev/null || { echo "找不到 claude 命令" >&2; exit 127; }
    # 简报紧跟 -p：--tools 这类参数会吞掉后面所有参数
    CMD=(claude -p "${PROMPT}" --output-format text)
    [ -n "${MODEL}" ] && CMD+=(--model "${MODEL}")
    if [ "${WRITE}" = 1 ]; then CMD+=(--permission-mode acceptEdits)
    else CMD+=(--strict-mcp-config --tools "Read,Grep,Glob,WebSearch,WebFetch"); fi
    run_with_timeout "${CMD[@]}"; RC=$?
    cp "${LOG}" "${OUT}"
    ;;
  kimi)
    command -v kimi >/dev/null || { echo "找不到 kimi 命令" >&2; exit 127; }
    soft_readonly
    CMD=(kimi); [ -n "${MODEL}" ] && CMD+=(-m "${MODEL}"); CMD+=(-p)
    run_with_timeout "${CMD[@]}" "${PROMPT}"; RC=$?
    cp "${LOG}" "${OUT}"
    ;;
  antigravity)
    AGAPI="$(command -v agentapi || echo "$HOME/.gemini/antigravity/bin/agentapi")"
    [ -x "${AGAPI}" ] || { echo "找不到 agentapi，确认装了 Antigravity" >&2; exit 127; }
    if [ -z "${ANTIGRAVITY_LS_ADDRESS:-}" ]; then
      # 不在 Antigravity 对话里运行时，自己找本地服务（仅 macOS，需 App 开着）
      PID=$(pgrep -f "Antigravity.app/Contents/Resources/bin/language_server" | head -1)
      [ -n "${PID}" ] || { echo "Antigravity 没开，先打开 App" >&2; exit 3; }
      export ANTIGRAVITY_CSRF_TOKEN=$(ps -o args= -p "${PID}" | grep -oE -- '--csrf_token [^ ]+' | awk '{print $2}')
      for p in $(lsof -nP -a -p "${PID}" -iTCP -sTCP:LISTEN 2>/dev/null | awk 'NR>1{n=split($9,a,":");print a[n]}'); do
        curl -s -m 2 "http://127.0.0.1:${p}/healthz" | grep -q '"ok"' && export ANTIGRAVITY_LS_ADDRESS="127.0.0.1:${p}" && break
      done
      [ -n "${ANTIGRAVITY_LS_ADDRESS:-}" ] || { echo "找不到 Antigravity 本地服务端口" >&2; exit 3; }
      if [ -n "${ZONGGUAN_AG_PROJECT:-}" ]; then
        export ANTIGRAVITY_PROJECT_ID="${ZONGGUAN_AG_PROJECT}"
      elif [ -z "${ANTIGRAVITY_PROJECT_ID:-}" ] && command -v sqlite3 >/dev/null; then
        export ANTIGRAVITY_PROJECT_ID=$(sqlite3 "$HOME/.gemini/antigravity/conversation_summaries.db" \
          "select project_id from conversation_summaries where project_id not in ('','outside-of-project') order by last_modified_time desc limit 1;" 2>/dev/null)
        echo "[dispatch] 提醒：未指定 ZONGGUAN_AG_PROJECT，子对话会开在最近用过的 Antigravity 项目 ${ANTIGRAVITY_PROJECT_ID}" >&2
      fi
    fi
    soft_readonly
    PROMPT="工作目录：${DIR}

${PROMPT}"
    if [ -n "${RESULT}" ]; then
      case "${RESULT}" in /*) ;; *) RESULT="${DIR}/${RESULT}" ;; esac
      if [ -e "${RESULT}" ]; then mv "${RESULT}" "${RESULT}.bak-${TS}"; echo "[dispatch] 旧结果文件已改名为 ${RESULT}.bak-${TS}" >&2; fi
      PROMPT="${PROMPT}

【交付方式】做完后，先把最终结论（不超过 300 字）写进 ${RESULT}.tmp，写完再把它改名为 ${RESULT}。这是本次唯一允许写入的文件。"
    fi
    ARGS=(new-conversation --title="${ZONGGUAN_TITLE:-总管派单}")
    [ -n "${MODEL}" ] && ARGS+=(--model="${MODEL}")
    START=$(date +%s)
    run_with_timeout "${AGAPI}" "${ARGS[@]}" "${PROMPT}"; RC=$?
    CID=$(grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' "${LOG}" | head -1)
    [ -n "${CID}" ] || { cat "${LOG}" >&2; exit 4; }
    echo "[dispatch] 已开 Antigravity 子对话 ${CID}" >&2
    if [ -n "${RESULT}" ]; then
      while [ ! -s "${RESULT}" ] && [ $(( $(date +%s) - START )) -lt "${TIMEOUT}" ]; do sleep 10; done
      if [ -s "${RESULT}" ]; then cp "${RESULT}" "${OUT}"; RC=0
      else echo "[dispatch] 超时 ${TIMEOUT}s 还没拿到结果，去 App 里看对话 ${CID}" >>"${LOG}"; RC=142; fi
    else
      echo "子对话 ${CID} 已开始，结果去 Antigravity 里看，或让它用 agentapi send-message 回报。" >"${OUT}"
    fi
    ;;
  cmd)
    # 命令模板按空格拆分；{prompt} 换成简报，{dir} 换成工作目录；模板里没有 {prompt} 就把简报加在最后
    [ "${USED_WCALL}" = 1 ] || soft_readonly
    read -r -a TPL <<<"${ARG}"
    command -v "${TPL[0]}" >/dev/null || { echo "找不到命令 ${TPL[0]}" >&2; exit 127; }
    CMD=(); HAS_P=0
    for tok in "${TPL[@]}"; do
      case "${tok}" in
        "{prompt}") CMD+=("${PROMPT}"); HAS_P=1 ;;
        "{dir}") CMD+=("${DIR}") ;;
        *) CMD+=("${tok}") ;;
      esac
    done
    [ "${HAS_P}" = 1 ] || CMD+=("${PROMPT}")
    run_with_timeout "${CMD[@]}"; RC=$?
    cp "${LOG}" "${OUT}"
    ;;
  manual)
    [ "${WRITE}" = 0 ] && PROMPT="${READONLY_NOTE}

${PROMPT}"
    {
      echo "【手动转交】成员「${AGENT}」没有命令行。请把分隔线之间的简报复制到 ${AGENT} 里，做完把它的结论贴回给总管。"
      echo "------------------------------------------------------------"
      printf '工作目录：%s\n\n%s\n' "${DIR}" "${PROMPT}"
      echo "------------------------------------------------------------"
    } > "${OUT}" && cp "${OUT}" "${LOG}" || { echo "手动转交简报写入失败：${OUT}" >&2; exit 1; }
    RC=10
    ;;
  *) echo "不认识的预设：${RUN}（可选 codex、claude、kimi、antigravity）" >&2; exit 2 ;;
esac

# 10 留给手动接力；自动成员自己退出 10 时改报 1，避免总管误以为在等人转交
if [ "${RUN}" != manual ] && [ "${RC}" = 10 ]; then echo "[dispatch] 成员退出码 10，按普通失败处理" >>"${LOG}"; RC=1; fi
echo "[dispatch] exit=${RC}" >>"${LOG}"
if [ -s "${OUT}" ]; then cat "${OUT}"; else cat "${LOG}"; fi
echo "" >&2
echo "[dispatch] agent=${AGENT} exit=${RC} write=${WRITE} dir=${DIR} log=${LOG}" >&2
exit "${RC}"
