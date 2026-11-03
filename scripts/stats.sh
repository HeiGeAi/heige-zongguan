#!/bin/bash
# 派单统计。有台账（ledger.tsv）就按台账算：每个成员、每条线多少单、成功、失败、超时、平均耗时，最近的失败；
# 没有台账就按旧日志数单数。
# 用法：stats.sh [天数，默认全部]
DAYS="${1:-}"
ZG_HOME="${ZONGGUAN_HOME:-$HOME/.zongguan}"
LEDGER="${ZONGGUAN_LEDGER:-${ZG_HOME}/ledger.tsv}"
LOG_DIR="${ZONGGUAN_LOG_DIR:-${ZG_HOME}/logs}"

if [ -f "${LEDGER}" ]; then
  SINCE=""
  if [ -n "${DAYS}" ]; then
    case "${DAYS}" in *[!0-9]*) echo "天数要写数字" >&2; exit 2 ;; esac
    SINCE="$(date -v-"${DAYS}"d '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -d "-${DAYS} days" '+%Y-%m-%d %H:%M:%S')"
  fi
  echo "台账：${LEDGER}${SINCE:+（${DAYS} 天内）}"
  awk -F'\t' -v since="${SINCE}" '
    NR==1 { next }
    since != "" && $1 < since { next }
    {
      m=$4; l=($5==""?"（未写线名）":$5); rc=$10; s=$3+0
      n[m]++; t[m]+=s; ln[l]++
      if (rc==0) ok[m]++; else if (rc==10) man[m]++; else if (rc==142) to[m]++; else bad[m]++
      if (rc!=0 && rc!=10) { fail[++nf]=$1 "  " m "  " l "  退出码 " rc "  " $11 }
      total++
    }
    END {
      if (total==0) { print "这段时间没有派单。"; exit }
      printf "\n%-14s %5s %5s %5s %5s %5s %8s\n", "成员", "单数", "成功", "手动", "超时", "失败", "平均秒"
      for (m in n) printf "%-14s %5d %5d %5d %5d %5d %8.0f\n", m, n[m], ok[m], man[m], to[m], bad[m], t[m]/n[m]
      printf "\n%-24s %5s\n", "线名", "单数"
      for (l in ln) printf "%-24s %5d\n", l, ln[l]
      if (nf>0) { print "\n最近的失败（最多 5 条）："; for (i=nf; i>nf-5 && i>0; i--) print "  " fail[i] }
      printf "\n合计 %d 单\n", total
    }' "${LEDGER}"
  exit 0
fi

[ -d "${LOG_DIR}" ] || { echo "还没有派单记录。"; exit 0; }
echo "还没有台账，按旧日志统计：${LOG_DIR}"
printf "%-14s %6s\n" "成员" "单数"
for f in "${LOG_DIR}"/*.log; do [ -e "$f" ] || continue; b=$(basename "$f" .log); echo "${b#*-*-*-}"; done | sort | uniq -c | awk '{printf "%-14s %6d\n", $2, $1}'
