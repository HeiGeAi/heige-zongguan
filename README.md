# 总管工作法（heige-zongguan）

![License](https://img.shields.io/badge/license-MIT-green.svg)
![Agents](https://img.shields.io/badge/agents-universal-orange.svg)
![Shell](https://img.shields.io/badge/bash-3.2%2B-0e7490.svg)

中文 | [English](#english)

一个窗口管所有 AI。你只跟一个 AI 说话，它当总管：把你的一串需求拆成几条任务线，同一个产品的改动留在一个会话里按顺序做，互不相干的事各开一个子会话并行，需要专长或第二意见的活派给电脑上的其他 AI。干完都回到主窗口汇报，你只负责拍板和验收。

**谁当总管、谁当成员，你自己定。** 主力用 Claude Code 的，让它当总管；主力用 Codex、Antigravity、WorkBuddy 的，让自己顺手的那个当。其他 AI 登记成成员，写清楚各自擅长什么、怎么叫到它。ChatGPT、豆包这类网页版也能进团队，走手动接力：总管写好简报，你转交过去，再把结论贴回来。

做法依据 DeepSeek Harness 团队公开的 Super-agent 设计（一个只负责分派的总管，加一排上下文隔离的干活会话），和作者本人两个多月、近 600 单的本机多 AI 协作实践。

## 它解决什么

| 你遇到的情况 | 总管工作法的做法 |
|---|---|
| 开到第 4 个 AI 窗口，忘了第 2 个交代过什么 | 只跟一个总管窗口说话，其他窗口由它开、由它盯 |
| 一个窗口包所有事，活一多就排队 | 互不相干的事 fork 子会话并行 |
| 同一个产品拆到几个窗口改，A 修好的被 B 改回去 | 同一个产品、同一份文件的活定为一条线，只在一个会话里做 |
| 跟 AI 说「合适时可以分活」，它从来不分 | 派不派活写成规矩，团队表写死谁擅长什么 |
| 别的 AI 交回来的东西直接用，出了错才发现 | 成员产出一律当初稿，总管对照原文核过才交给你 |
| AI 什么都来问你，一天被打断几十次 | 只有删除、花钱、对外发消息、改权限这几类事才问你，写成决策卡，推荐选项放第一个，你点一下就行 |
| 同一个问题，AI 隔几天又来问一遍 | 你拍过板的事、明确不做的事，带原话记进决策记录，定过的不问第二遍 |
| 两个 AI 互相审查，挑错挑个没完 | 审查只报真会出错的问题，最多 3 轮 |
| 你不开口，什么都不会发生 | 规则表加定时任务和事件，到点、来新消息、出错时成员自己被叫醒，只把要拍板的事递给你 |

## 快速开始

```bash
git clone https://github.com/HeiGeAi/heige-zongguan.git
bash heige-zongguan/scripts/install.sh
```

安装脚本会以软链方式装进 `~/.claude/skills`、`~/.codex/skills`、`~/.gemini/config/skills`、`~/.workbuddy/skills`、`~/.codebuddy/skills`，没装的产品自动跳过。想装成独立副本加 `--copy`，卸载加 `--uninstall`。

然后建团队表：

```bash
bash heige-zongguan/scripts/team.sh init --manager "Claude Code"
```

它会探测你电脑上装了哪些 AI，生成一张草稿。也可以直接对总管说「帮我设置总管工作法的团队」，它会问你谁当总管、谁擅长什么，再帮你写好。团队表长这样：

```
总管 = Claude Code

成员 = codex | 写代码、查 bug、代码审查 | preset:codex
成员 = kimi | 读长篇中文材料 | preset:kimi
成员 = 快批 | 批量分类、打标签 | cmd:dsh headless {prompt}
成员 = 豆包网页版 | 查资料 | manual
```

最后把 `templates/rules-template.md` 里的派单规矩贴进总管的规矩文件（`CLAUDE.md`、`AGENTS.md` 或 `GEMINI.md`）。

装好后在总管里直接说：

- 「你当总管，这几件事同时推进：……」
- 「fork 一个子会话去写播客稿，写完回这里汇报」
- 「把这段代码派给 codex 只读审一遍」

## 三档用法，按需要往上走

| 档 | 你要做的 | 适合 |
|---|---|---|
| 一个窗口当总管 | 装好 skill，对总管说「你当总管」 | 所有人，网页版也能用手动接力 |
| 按团队表派活 | 建团队表，写清谁擅长什么 | 电脑上装了两个以上 AI 的人 |
| 不等你开口 | 在团队表里写规则，交给定时任务或事件触发（`run-rule.sh`） | 有固定的巡检、日报、处理反馈这类重复活的人 |

再往上，来源多到管不过来时，`references/event-hub.md` 讲怎么搭一个事件中台。

## 成员的三种调用方式

| 写法 | 适合 | 只读控制 |
|---|---|---|
| `preset:codex` / `claude` / `kimi` / `antigravity` | 装了对应命令行或 App | Codex 硬沙箱；Claude 只开读文件工具；其余靠简报叮嘱 |
| `cmd:命令模板` | 其他任何有命令行的 AI | 靠简报叮嘱 |
| `manual` | 没有命令行的产品（网页版、桌面 App） | 你本人转交，你自己把关 |

项目目录里的团队表要你运行 `team.sh trust` 之后，里面的自定义命令才会执行，防止别人在仓库里塞恶意命令。

## 实测过什么

在 macOS 上真实跑过：Codex、Antigravity 当总管，按团队表把任务派给其他 AI 并行完成、汇总、核对；Claude Code 当总管，用自带子 agent 并行完成；内置预设、自定义命令、手动接力三种成员都真派过单。没测过的：Linux、Windows、WorkBuddy 当总管、网页版当总管、CodeBuddy 命令行。完整记录见 `tests/实测记录-20261102.md`。

## 目录

| 文件 | 内容 |
|---|---|
| `SKILL.md` | AI 读的工作流程 |
| `references/methodology.md` | 方法论：为什么这么做，三条坑，安全边界 |
| `references/team-setup.md` | 团队表：谁当总管、谁当成员、各种产品怎么写 |
| `references/platforms.md` | 各家产品怎么开子会话、派活、回报 |
| `references/examples.md` | 内容、开发、办公三个完整例子 |
| `references/decision-card.md` | 必须问人的清单和决策卡格式 |
| `references/automation.md` | 规则表、定时任务、事件触发 |
| `references/event-hub.md` | 进阶：事件中台和代码上线流水线的设计 |
| `templates/brief-template.md` | 派单简报模板 |
| `templates/rules-template.md` | 贴进规矩文件的派单规矩 |
| `templates/decisions-template.md` | 决策记录：定了的事、定了不做的事 |
| `scripts/team.sh` | 团队表管理：init、show、check、set-manager、add、remove、trust |
| `scripts/dispatch.sh` | 按团队表派成员，带线名锁和台账 |
| `scripts/run-rule.sh` | 按规则触发一单：去重、派单、只在需要时通知 |
| `scripts/stats.sh` | 台账统计：每个成员、每条线的单数、成功、失败、耗时 |
| `scripts/install.sh` | 安装和卸载 |

## 要求

macOS 或 Linux，bash 3.2 以上，不需要装别的依赖。用命令行调用的成员要先装好并登录；Antigravity 用它自带的 `agentapi`，需要 App 开着。

## English

**One window to run all your AIs.** You talk to a single AI, the manager. It splits your requests into task lines: changes to the same product stay in one session, unrelated work is forked into parallel sub-sessions, and specialist work goes to other AI tools on your machine. Everything reports back to the main window, where you only approve and review.

**It only asks you when it has to.** Deleting, spending, messaging outsiders and changing permissions go to you as a decision card with a recommended option; everything you decided once is logged and never asked again. Rules plus schedules or events let members wake up on their own.

**You choose who manages and who works.** Claude Code, Codex, Antigravity or WorkBuddy can be the manager. Every other AI is registered as a member in a plain-text team table, with what it is good at and how to call it: a built-in preset, a custom command template, or `manual` relay for web-only chat products.

Based on the Super-agent design published by the DeepSeek Harness team, and two months of real multi-agent work by the author (close to 600 dispatched jobs).

```bash
git clone https://github.com/HeiGeAi/heige-zongguan.git
bash heige-zongguan/scripts/install.sh
bash heige-zongguan/scripts/team.sh init --manager "Claude Code"
```

The skill and docs are written in Chinese. Tested on macOS: Codex and Antigravity as managers dispatching through the team table, Claude Code as manager with its own sub-agents.

## 致谢 | Credits

由 [@HeiGeAi](https://github.com/HeiGeAi) 打造。方法论参考 DeepSeek Harness 团队《Super-agent 设计探索：迈向更自主的 Agent 系统》。

## 许可证 | License

MIT。随便用，随便改，随便分享。

MIT License. Use it, fork it, share it.
