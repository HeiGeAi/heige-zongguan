#!/bin/bash
# 把总管工作法装进 Claude Code、Codex、Antigravity、WorkBuddy、CodeBuddy 的全局技能目录（没装的产品自动跳过）
# 用法：bash install.sh            软链安装（改源文件即全部生效）
#       bash install.sh --copy     复制一份安装
#       bash install.sh --uninstall 卸载（只移除本源目录装的软链或副本）
set -euo pipefail
SRC="$(cd "$(dirname "$0")/.." && pwd -P)"
NAME="zongguan"   # 装进各产品的目录名固定为 zongguan，和 SKILL.md 的 name 一致；仓库目录叫什么都行
MODE=link
[ $# -gt 1 ] && { echo "一次只能给一个选项" >&2; exit 2; }
case "${1:-}" in
  "") ;; --copy) MODE=copy ;; --uninstall) MODE=uninstall ;;
  *) echo "未知选项：${1}（可选 --copy、--uninstall）" >&2; exit 2 ;;
esac

TARGETS=("$HOME/.claude/skills" "$HOME/.codex/skills" "$HOME/.gemini/config/skills" "$HOME/.workbuddy/skills" "$HOME/.codebuddy/skills")
LABELS=("Claude Code" "Codex" "Antigravity" "WorkBuddy" "CodeBuddy")
MARK=".zongguan-source"

chmod +x "${SRC}/scripts/"*.sh
for i in 0 1 2 3 4; do
  T="${TARGETS[$i]}"; L="${LABELS[$i]}"; D="${T}/${NAME}"
  P="$(dirname "${T}")"
  if [ ! -d "${P}" ]; then echo "跳过 ${L}：没找到 ${P}（没装这个产品）"; continue; fi
  OURS=0
  if [ -L "${D}" ] && [ "$(cd "${D}" 2>/dev/null && pwd -P)" = "${SRC}" ]; then OURS=1; fi
  if [ -d "${D}" ] && [ ! -L "${D}" ] && [ -f "${D}/${MARK}" ] && [ "$(cat "${D}/${MARK}")" = "${SRC}" ]; then OURS=1; fi
  if [ "${MODE}" = uninstall ]; then
    if [ "${OURS}" = 1 ]; then rm -rf "${D}"; echo "已从 ${L} 移除"; else echo "跳过 ${L}：没有本源目录装的 ${NAME}"; fi
    continue
  fi
  if [ -e "${D}" ] || [ -L "${D}" ]; then
    if [ "${OURS}" = 0 ]; then echo "跳过 ${L}：${D} 已存在且不是本源目录装的，请先手动处理"; continue; fi
    rm -rf "${D}"
  fi
  mkdir -p "${T}"
  if [ "${MODE}" = copy ]; then cp -R "${SRC}" "${D}"; echo "${SRC}" > "${D}/${MARK}"; else ln -s "${SRC}" "${D}"; fi
  echo "已装进 ${L}：${D}"
done
[ "${MODE}" = uninstall ] && exit 0
echo
printf '下一步：1）建团队表，指定谁当总管、谁当成员：bash %q init --manager 你的总管\n' "${SRC}/scripts/team.sh"
echo "        2）把 ${SRC}/templates/rules-template.md 里的派单规矩贴进总管的规矩文件。"
echo "只能聊天的产品（ChatGPT、豆包网页版等）读不了技能目录，把 SKILL.md 和团队表贴进对话即可。"
printf '派外部 AI：bash %q codex "简报"\n' "${SRC}/scripts/dispatch.sh"
