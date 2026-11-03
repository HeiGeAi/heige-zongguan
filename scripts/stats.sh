#!/bin/bash
# 统计 dispatch.sh 派出去的单：每个 AI 多少单、超时多少、最近一单
# 用法：stats.sh [日志目录]，默认 $ZONGGUAN_LOG_DIR 或 ~/.zongguan/logs
LOG_DIR="${1:-${ZONGGUAN_LOG_DIR:-$HOME/.zongguan/logs}}"
[ -d "${LOG_DIR}" ] || { echo "还没有派单日志：${LOG_DIR}"; exit 0; }
echo "日志目录：${LOG_DIR}"
printf "%-12s %6s %6s %6s  %s\n" "AI" "单数" "成功" "超时" "最近一单"
TOTAL=0
for a in $(for f in "${LOG_DIR}"/*.log; do [ -e "$f" ] || continue; b=$(basename "$f" .log); echo "${b#*-*-*-}"; done | sort -u); do
  n=0; ok=0; to=0; last=""
  for f in "${LOG_DIR}"/*-"${a}".log; do
    [ -e "$f" ] || continue
    n=$((n+1)); last=$(basename "$f" | cut -c1-15)
    tail -1 "$f" | grep -q '^\[dispatch\] exit=0$' && ok=$((ok+1))
    tail -1 "$f" | grep -q '^\[dispatch\] exit=142$' && to=$((to+1))
  done
  TOTAL=$((TOTAL+n))
  printf "%-12s %6s %6s %6s  %s\n" "${a}" "${n}" "${ok}" "${to}" "${last}"
done
echo "合计：${TOTAL} 单（旧版日志没有结束标记，成功数可能偏少）"
