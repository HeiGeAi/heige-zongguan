# 建团队表：谁当总管，谁当成员

团队表是一个纯文本文件，用户自己说了算。总管换人、成员增减，改这一张表就行，skill 本身不用动。

## 放在哪

先找到先用：

1. 环境变量 `ZONGGUAN_TEAM` 指定的文件
2. 当前项目目录往上找到的 `.zongguan/team.conf`（只对这个项目生效，比如这个项目让 Codex 当总管）
3. `~/.zongguan/team.conf`（全局默认）

## 长什么样

```
总管 = Claude Code

成员 = codex | 写代码、查 bug、代码审查 | preset:codex
成员 = kimi | 读长篇中文材料 | preset:kimi
成员 = antigravity | 第二意见、文案人味 | preset:antigravity
成员 = 快批 | 批量分类、打标签 | cmd:dsh headless {prompt}
成员 = workbuddy | 做表格、办公文档 | manual
成员 = 豆包网页版 | 查资料、生活问题 | manual
```

每个成员一行，用 `|` 分成四段：**名字 | 擅长什么 | 调用方式 | 写模式调用方式（可省）**。

- **名字**：派单时就喊这个名字，`dispatch.sh 快批 "简报"`。中文也行。
- **擅长什么**：按你自己实测的结果写。总管派单时照这一栏挑人。
- **调用方式**三选一：

| 写法 | 适合 | 只读控制 |
|---|---|---|
| `preset:codex` | 装了 Codex 命令行 | 硬沙箱，只读时还会关掉 MCP 扩展 |
| `preset:claude` | 装了 Claude Code 命令行并已登录 | 只开读文件和搜索工具，关掉 MCP |
| `preset:kimi` | 装了 Kimi Code 命令行 | 只能靠简报叮嘱 |
| `preset:antigravity` | 装了 Antigravity 桌面 App 且开着 | 只能靠简报叮嘱 |
| `cmd:命令模板` | 其他任何有命令行、能一次性回答的 AI | 只能靠简报叮嘱 |
| `manual` | 没有命令行的产品：WorkBuddy 桌面版、ChatGPT、豆包、Kimi 网页版等 | 由你本人转交，你自己把关 |

- **写模式调用方式**：只有 `cmd:` 成员需要。派单带 `-w`（允许改文件）时用这一段，比如 `cmd:mytool --allow-write -p {prompt}`。不写的话，写任务也用第三段的命令，只是不再加只读叮嘱。

`cmd:` 模板里，`{prompt}` 换成简报，`{dir}` 换成工作目录，占位符要单独成一个词（`--cwd {dir}` 可以，`--cwd={dir}` 不行）；没写 `{prompt}`，简报接在命令最后。模板按空格拆开，不经过 shell，所以不能写 `|`、引号和管道。复杂的调用先写成一个小脚本，再把脚本路径填进去。

## 项目团队表要先信任

项目里的团队表可能是别人写的，随仓库一起下载到你电脑上。为了防止别人在里面塞一条恶意的自定义命令，**项目团队表里的 `cmd:` 成员，要你先看过并运行 `team.sh trust` 才会执行**；表的内容一改，就要重新信任。内置预设和手动接力的成员不受影响。全局团队表（`~/.zongguan/team.conf`）是你自己的，不用信任。

## 怎么建

最省事是让总管带你建。对总管说「帮我设置总管工作法的团队」，它会：

1. 运行 `team.sh init --manager <它自己>`，探测你电脑上装了哪些 AI，生成草稿。
2. 问你：总管是不是它；哪些当成员、各擅长什么；有没有网页版、桌面 App 要手动接力。
3. 按你的回答改表，再运行 `team.sh check` 看每个成员能不能调用；你同意的话，`team.sh check --ping` 真派一句话试试（会花一点额度）。

也可以自己动手：

```bash
bash team.sh init --manager "Codex"
bash team.sh add "kimi | 读长材料 | preset:kimi"
bash team.sh add "workbuddy | 做表格 | manual"
bash team.sh remove claude
bash team.sh set-manager "Antigravity"
bash team.sh show
bash team.sh check
```

## 几种常见搭法

| 你主要用 | 总管 | 成员可以是 |
|---|---|---|
| Claude Code | Claude Code | codex、kimi、antigravity；网页版走 manual |
| ChatGPT 和 Codex | Codex（能跑命令） | claude、kimi；ChatGPT 网页版走 manual |
| WorkBuddy | WorkBuddy（装上 skill 后在里面对话） | codex、kimi 等命令行；豆包网页版走 manual |
| Antigravity | Antigravity | codex、kimi、claude |
| 只用网页版 | ChatGPT、豆包等任意一个 | 其他网页版全部 manual，你当传话的人，总管负责拆线、写简报、记账和验收 |

同一个 AI 在这张表里是总管，在另一个项目的表里可以是成员。

## 注意

- 总管和成员都可能读到你的简报。简报里不放密码、key、客户真名。
- 没有硬沙箱的成员，写任务只在单独的文件夹里做。
- 把团队表分享给同事前，删掉里面你自己的脚本路径。
