# Pi Pet

[English](README.md) | 简体中文

Omarchy 桌面宠物，只盯着 **pi**，并且用它自己的声音跟你说话。

这是 [agent-pet](https://github.com/chthollyphile/agent-pet) / [dsh-pet](https://github.com/PC2005-cloud/dsh-pet)
的 pi-only 分支。给 Claude Code、Codex、额度统计、步骤总结做的东西全部删掉了：一个 agent、一个事件源、一个模型。

## 它会做什么

- **宠物行为**：待机、随机小动作、走动、点击回应，以及基于物理的拖拽和甩抛。
- **实时工作状态**：六档（思考中、干活、看结果、等你确认、完成、出错），由一个小 pi 扩展驱动，同时显示项目名、
  正在跑的工具和命令、上下文占用。
- **碎碎念**：每隔几分钟说一句短话，由你自己的 `pi` 和模型生成，流式上屏，能看见她"正在想"的那几行。
- **提醒**：pi 需要你确认、跑完、出错时发桌面通知。只在终端不在前台时发，且只带 agent 名和状态。

## 依赖

- Omarchy 4
- `qt6-imageformats`（Qt 的 WebP 解码）；装完跑一次 `omarchy-restart-shell`
- `PATH` 里有 `pi`
- `notify-send`（桌面通知）

不再需要 `jq`、`socat`、`python`，也不需要任何额度采集器。

## 安装

```bash
omarchy plugin add <这个仓库的地址> --enable
~/.config/omarchy/plugins/local.pi-pet/bin/agent-pet-install  # 装宿主侧扩展的符号链接，之后重启 pi
```

`bin/agent-pet-install --uninstall` 只删除它自己创建的那条链接，并且尊重 `PI_CODING_AGENT_DIR`。

## 配置

内置默认值在 `assets/config.json`，自己的改动写 `$XDG_CONFIG_HOME/agent-pet/config.jsonc`（默认
`~/.config/agent-pet/config.jsonc`，允许注释，保存即生效）。运行状态目录同样跟随 `XDG_STATE_HOME`。

合并方式是**深合并**：对象逐键合并、数组整体替换、`null` 表示删掉这个键（回退到内置默认）。只需要写你改的部分：

```jsonc
{
  "pet": { "size": 260 },
  "bubble": { "detail": true },
  "murmur": { "enabled": true, "model": "anthropic/claude-haiku-4-5" }
}
```

### 碎碎念

```jsonc
"murmur": {
  "enabled": false,              // 关闭时完全不调用模型
  "model": "",                   // 必填，写成 provider/model；留空等于关闭这个功能
  "provider": "",                // 只在同名模型需要消歧时填
  "thinking": "low",             // off | minimal | low | medium | high | xhigh | max
  "session": "agent-pet",        // 持久会话 ID；留空 = 每次请求无状态
  "extensions": [],              // 额外扩展路径；相对路径按配置目录解析
  "tools": ["pet_state"],        // 工具白名单；空数组 = 一个工具都不给
  "intervalSec": 600,
  "stream": true,                // false 退回 `--mode text`，一次性输出
  "typewriterCps": 30,           // 0 = 按 delta 原速吐字
  "showThinking": true,          // 灰字显示她"正在想"的内容
  "firstTokenTimeoutSec": 15,
  "timeoutSec": 120
}
```

`model` 为空时不会启动任何进程，也不会退回 pi 的默认模型——写错名字的代价最多是"她不说话"，而不是默默花掉你的额度。

## 两个 pi 进程的关系

```
你的 pi（TUI）
  └─ ext/agent-pet-pi.ts        装在 ~/.pi/agent/extensions，只写不读
        │  unix socket  $XDG_RUNTIME_DIR/agent-pet/events.sock
        ▼
    omarchy-shell（本插件的 Service.qml）
        ▲  只有带 id 的请求才回一行
  └─ 宠物自己的 pi（无头）      由 bin/agent-pet-pi 启动，严格隔离
        └─ ext/pet.ts            它注册的唯一工具：pet_state
```

两套扩展永远不会互相加载：宿主那个靠目录自动发现（子进程用 `--no-extensions` 关掉），宠物那个靠显式 `-e`
（你的 TUI 不会去加载它，它也不在 agent 目录里）。

## 宠物自己的 pi 是隔离的

`bin/agent-pet-pi` 是唯一允许启动子 pi 的地方，所有 flag 写死在脚本里：

- `--no-extensions`，只 `-e` 白名单里的路径；再加上 `--no-mcp --no-skills --no-prompt-templates --no-context-files
  --no-approve`
- 工作目录固定在 `~/.local/state/agent-pet/pi-cwd`（空目录），从根上找不到项目 `.pi`
- 工具面由 `murmur.tools` 全量替换，空数组等价于 `-nt`
- 剥掉继承来的 `PI_CODING_AGENT_DIR`、`PI_MODEL` 等变量，强制 `PI_TELEMETRY=0 PI_SKIP_VERSION_CHECK=1
  PI_OFFLINE=1`（`PI_OFFLINE` 只关版本检查和目录刷新，不关模型请求）
- 提示词走 stdin，系统提示词在 `assets/persona.*.md`，都不进进程参数

限制的是**模型能调什么**，不是扩展能做什么：`murmur.extensions` 里列出的扩展以你的用户身份跑在 pi 进程内，
加路径等于加信任。

## IPC

```bash
omarchy-shell agent-pet state     # JSON：会话、工作状态、上下文占用、说话状态
omarchy-shell agent-pet say "你好"
omarchy-shell agent-pet play 写代码
omarchy-shell agent-pet murmur    # 现在就说一句
omarchy-shell agent-pet context   # 上下文占用
omarchy-shell agent-pet toggle    # 隐藏 / 显示
omarchy-shell agent-pet reload    # 重载配置
omarchy-shell agent-pet forget    # 清空她的持久会话
```

## 运行时文件

| 路径 | 说明 |
|---|---|
| `Service.qml` | 配置、会话状态、说话、通知、IPC |
| `Pi.qml` | 启动子 pi、解析事件流、驱动相位机 |
| `EventServer.qml` | 两个生产者共用的 unix socket |
| `ext/agent-pet-pi.ts` | 宿主侧上报扩展，装进 pi 的扩展目录 |
| `ext/pet.ts` | 子进程侧的 `pet_state` 工具 |
| `bin/agent-pet-pi` | 唯一启动点，隔离 flag 都在这里 |
| `~/.local/state/agent-pet/pi-sessions/` | 她的持久会话（`agent-pet forget` 清空） |

## 致谢

- **[dsh-pet](https://github.com/PC2005-cloud/dsh-pet)**（MIT，© PC2005-cloud）——角色、106 段动画、表情包、默认
  配置，以及 `lib/shared.mjs` 里的物理与动画逻辑。该文件由上游生成，不要手改。
- **[agent-pet](https://github.com/chthollyphile/agent-pet)**（MIT，© lia）——本仓库的起点。
- **[Omarchy](https://github.com/basecamp/omarchy)**（MIT，© David Heinemeier Hansson）——`EventServer.qml` 里的
  socket 写法，以及本插件遵循的整体约定。

以 MIT 协议发布，见 [LICENSE](LICENSE)。
