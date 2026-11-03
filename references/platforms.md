# 各家产品怎么开子会话、派成员、回报

先判断自己在哪个产品里：Antigravity 的终端里有环境变量 `ANTIGRAVITY_CONVERSATION_ID`；Codex 里有 `CODEX_` 开头的变量或自带 multi-agent 工具；Claude Code 里有 Agent（子 agent）工具，桌面 App 还有开新会话的工具。拿不准就直接问用户。

## Claude Code

| 动作 | 怎么做 |
|---|---|
| 开子会话（fork） | **桌面 App**：用户说「fork 一个子会话去做 X」，总管用开新会话的工具开一个子会话，带完整简报（context 选 fork 就会带上当前聊天）。子会话出现在侧栏，可以点开看；它每结束一轮，主会话会收到它的回报。**命令行**：用 Agent 工具开后台子 agent（`run_in_background`），只把结论带回主会话。要整段对话复制出去，用 `claude --resume <会话id> --fork-session`。 |
| 派外部 AI | `bash <skill目录>/scripts/dispatch.sh codex -f 简报.md`，耗时的活放后台跑 |
| 回报 | 子会话、子 agent 的最终回复自动回到主会话；简报里要求结论不超过 100 字 |

注意：用 dispatch.sh 派给 claude 命令行前，先在终端跑一次 `claude` 确认已登录。Claude Code 的子 agent 默认继承主会话权限，派写任务时在简报里写清楚只许改哪个目录。

## Codex（CLI 和桌面 App）

| 动作 | 怎么做 |
|---|---|
| 开子会话 | 用户说「开 2 个子 agent 并行去做 A 和 B」，Codex 的 multi-agent 功能（`codex features list` 里 `multi_agent` 为 true）会开子线程，各自干完把结果交回主线程。要一条独立的长线，用 `codex fork` 复制当前对话另起一条，或在桌面 App 新建对话。 |
| 派外部 AI | 同样用 `scripts/dispatch.sh`。Codex 自己的沙箱默认可能不让访问网络或别的程序的配置目录，派单命令被拦时请用户放行 |
| 回报 | 子 agent 结果自动回主线程；`dispatch.sh` 的结论打印在终端 |

注意：同一个仓库的改动别同时交给两个子 agent，除非各自在独立的 git worktree 里。

## Antigravity（桌面 App）

Antigravity 的内置子 agent 在跑的时候，主对话可能不能继续聊。要主窗口一直能聊，用它自带的 `agentapi` 开**独立的后台对话**，这就是 Antigravity 里的 fork：

```bash
# 主对话自己的编号，Antigravity 会放在环境变量里
MAIN=$ANTIGRAVITY_CONVERSATION_ID

# 开一个子对话，带简报；--model 可选 flash_lite、flash、pro
agentapi new-conversation --model=flash --title="子任务：播客口播稿" "简报全文……
做完后在终端运行这条命令向总管汇报（结论不超过 100 字）：
agentapi send-message $MAIN '【播客口播稿】完成。结论……。交付物：路径或链接'"
```

| 动作 | 怎么做 |
|---|---|
| 开子会话 | `agentapi new-conversation`，命令立刻返回子对话编号，主对话不用等 |
| 派外部 AI | `scripts/dispatch.sh`，和其他两家一样。从 Antigravity 外面派给它时，加 `-o 结果文件` 才会等结果，不加只返回子对话编号；建议设 `ZONGGUAN_AG_PROJECT` 指定项目，不设就开在最近用过的项目里 |
| 回报 | 子对话用 `agentapi send-message <主对话编号> '结论'` 把汇报发回主对话；查子对话状态用 `agentapi get-conversation-metadata <编号>` |

注意：简报里要写死主对话编号（展开成具体的值），子对话自己的环境变量里是它自己的编号，不是主对话的。

## WorkBuddy（桌面 App）

| 动作 | 怎么做 |
|---|---|
| 当总管 | 把 skill 放进 `~/.workbuddy/skills/`（install.sh 会自动放），在 WorkBuddy 里说「你当总管」。它能在终端执行命令，就能用 `dispatch.sh` 按团队表派成员 |
| 开子会话 | 按 WorkBuddy 当前版本的多任务或新建对话功能来；做不到时，互不相干的线也可以都派给成员 |
| 当成员 | 桌面版没有给别人调用的命令行，团队表里写 `manual`。腾讯另有 CodeBuddy 命令行（npm 包 `@tencent-ai/codebuddy-code`，命令 `codebuddy`），装好登录后可以写成 `cmd:` 成员，参数按你装的版本核对 |

以上 WorkBuddy 部分只核对过技能目录和命令行包，没有在 WorkBuddy 里实测当总管。

## 只能聊天的产品（ChatGPT、豆包、Kimi 等网页版或 App）

| 动作 | 怎么做 |
|---|---|
| 当总管 | 把 SKILL.md 全文和你的团队表贴进对话，或放进自定义指令。它照样拆线、写简报、记账、验收，只是每份简报要你复制给成员，再把结论贴回来 |
| 当成员 | 团队表里写 `manual`。`dispatch.sh` 会打印一份可以直接复制的简报，并返回 10，总管就知道这条线在等你转交 |

## 按团队表派成员：dispatch.sh

```bash
bash <skill目录>/scripts/dispatch.sh <成员名> [-C 工作目录] [-w] [-m 模型] [-t 超时秒] [-o 结果文件] [-f 简报文件 | "简报"]
```

- 成员名就是团队表里的名字（`team.sh show` 可看）。没建团队表时，也能直接写 `codex`、`claude`、`kimi`、`antigravity`。
- 退出码：0 成功；10 手动接力，简报已打印；5 项目团队表未信任；127 命令找不到；142 超时；其他是成员自己报的错。

- 简报以横杠开头时，前面加 `--`。
- 默认只读。`-w` 才放开写。只读时 Codex 和 Claude 会同时关掉 MCP 扩展工具，防止扩展绕过只读。
- 日志目录只有本人能读，里面有简报原文，别把它分享出去。
- 各工具的只读能力不同：Codex 有硬沙箱；Claude 命令行用工具白名单限制；Kimi 和 Antigravity 只能在简报里叮嘱，所以写任务只在隔离目录做。
- 日志默认写在 `~/.zongguan/logs/`，可用环境变量 `ZONGGUAN_LOG_DIR` 改。`scripts/stats.sh` 统计每个 AI 接了多少单。
- 想接别的命令行 AI：在团队表里加一个 `cmd:` 成员，写法见 team-setup.md。

哪个 AI 适合干什么，按自己的实测写进团队表的「擅长」一栏，别照搬别人的分工。
