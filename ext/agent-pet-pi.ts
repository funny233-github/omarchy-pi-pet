/**
 * agent-pet 状态上报扩展（宿主侧）。
 *
 * 不装进 ~/.pi/agent/extensions/：那样每个 pi 会话都会加载，包括你干活的那些。
 * 用显式导入，只有你带上它的会话才会上报：
 *     pi -e <插件目录>/ext/agent-pet-pi.ts
 * 想长期用就做成别名（pi-pet），普通 `pi` 完全不加载这段代码。
 *
 * 只做一件事：把 pi 的生命周期事件压成一行 JSON，写进宠物监听的 unix socket。
 * 单向 —— 从不读回包（宠物进程不在时静默丢弃）。
 *
 * 三条硬约束：
 * 1) 这段代码跑在用户的 pi 进程里，任何异常都必须吞掉，绝不能影响会话；
 * 2) 只在 TUI 模式下上报（脚本里跑的 `pi -p` 不该让宠物跳起来）；
 * 3) AGENT_PET_INTERNAL=1 时直接不注册 —— 宠物自己 spawn 的子 pi 不上报，
 *    否则会出现"宠物说话 → 宠物以为自己在干活"的自噬。
 */
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { connect } from "node:net";

// ---------------------------------------------------------------- 传输

function sockPath(): string {
	const runtime = process.env.XDG_RUNTIME_DIR || `/run/user/${uid()}`;
	return `${runtime}/agent-pet/events.sock`;
}

function uid(): number {
	try {
		// getuid 在 Linux 上存在；用 typeof 判断以避开非 POSIX 平台的类型差异。
		const fn = (process as unknown as { getuid?: () => number }).getuid;
		return typeof fn === "function" ? fn() : 1000;
	} catch {
		return 1000;
	}
}

/** 写一行 JSON；连不上、写失败、超时都静默放弃。 */
function send(payload: Record<string, unknown>): void {
	let line: string;
	try {
		line = `${JSON.stringify(payload)}\n`;
	} catch {
		return;
	}
	try {
		const socket = connect(sockPath());
		const timer = setTimeout(() => {
			try {
				socket.destroy();
			} catch {}
		}, 500);
		socket.on("error", () => {
			clearTimeout(timer);
			try {
				socket.destroy();
			} catch {}
		});
		socket.on("connect", () => {
			try {
				socket.write(line);
				socket.end();
			} catch {
				try {
					socket.destroy();
				} catch {}
			}
		});
		socket.on("close", () => clearTimeout(timer));
	} catch {}
}

// ---------------------------------------------------------------- 焦点判断

let focusCacheAt = 0;
let focusCacheValue = false;

/**
 * 发事件的终端是否在前台：从本进程沿父进程链向上，看能否碰到 Hyprland 当前窗口的 pid。
 * hyprctl 是同步调用（约 5ms），所以只在要发通知的三类事件上算，并缓存 1 秒。
 */
function focused(): boolean {
	const now = Date.now();
	if (now - focusCacheAt < 1000) return focusCacheValue;
	focusCacheAt = now;
	focusCacheValue = detectFocused();
	return focusCacheValue;
}

function detectFocused(): boolean {
	try {
		const raw = execFileSync("hyprctl", ["activewindow", "-j"], {
			encoding: "utf8",
			timeout: 400,
			stdio: ["ignore", "pipe", "ignore"],
		});
		const active = JSON.parse(raw) as { pid?: number };
		const target = active?.pid;
		if (typeof target !== "number" || !Number.isInteger(target)) return false;
		let pid = process.pid;
		for (let i = 0; i < 64 && pid > 1; i++) {
			if (pid === target) return true;
			// /proc/<pid>/stat: "pid (comm) state ppid ..."，comm 可能含空格和括号
			const stat = readFileSync(`/proc/${pid}/stat`, "utf8");
			const rest = stat.slice(stat.lastIndexOf(")") + 2).split(" ");
			pid = Number(rest[1]);
			if (!Number.isInteger(pid)) break;
		}
	} catch {}
	return false;
}

// ---------------------------------------------------------------- 事件整形

/** 工具参数 → 气泡里的一行短文本（与 work-status 的 formatDetail 同口径，但更保守）。 */
function detailOf(args: unknown): string {
	let value = "";
	try {
		if (typeof args === "string") value = args;
		else if (args && typeof args === "object") {
			const record = args as Record<string, unknown>;
			const keys = ["command", "cmd", "file_path", "path", "pattern", "url", "query", "description", "prompt", "text"];
			for (const key of keys) {
				const candidate = record[key];
				if (typeof candidate === "string" && candidate) {
					value = candidate;
					break;
				}
				if (Array.isArray(candidate) && candidate.length && candidate.every((v) => typeof v === "string")) {
					value = candidate.join(" ");
					break;
				}
			}
		}
	} catch {}
	return String(value).split("\n")[0].replace(/\s+/g, " ").trim().slice(0, 120);
}

function sessionOf(ctx: ExtensionContext): string {
	try {
		return ctx.sessionManager.getSessionId();
	} catch {
		return "";
	}
}

function transcriptOf(ctx: ExtensionContext): string {
	try {
		return ctx.sessionManager.getSessionFile() || "";
	} catch {
		return "";
	}
}

function inTui(ctx: ExtensionContext): boolean {
	try {
		return ctx.mode === "tui";
	} catch {
		return false;
	}
}

// ---------------------------------------------------------------- 注册

export default function agentPetReporter(pi: ExtensionAPI): void {
	if (process.env.AGENT_PET_INTERNAL === "1") return;

	const base = (ctx: ExtensionContext): Record<string, unknown> => ({
		v: 1,
		src: "host",
		s: sessionOf(ctx),
	});

	pi.on("session_start", (_event, ctx) => {
		try {
			if (!inTui(ctx)) return;
			send({ ...base(ctx), e: "begin", cwd: ctx.cwd, tr: transcriptOf(ctx) });
		} catch {}
	});

	pi.on("before_agent_start", (event, ctx) => {
		try {
			if (!inTui(ctx) || event.messageType !== "user") return;
			send({ ...base(ctx), e: "think", p: String(event.prompt || "").slice(0, 300) });
		} catch {}
	});

	pi.on("tool_execution_start", (event, ctx) => {
		try {
			// 嵌套调用（例如 codemode 脚本里发起的工具）不单独上报，气泡只显示外层意图
			if (!inTui(ctx) || event.parentToolCallId) return;
			send({ ...base(ctx), e: "tool", n: event.toolName, d: detailOf(event.args) });
		} catch {}
	});

	pi.on("tool_execution_end", (event, ctx) => {
		try {
			if (!inTui(ctx) || event.parentToolCallId) return;
			send({ ...base(ctx), e: "tooled", n: event.toolName });
		} catch {}
	});

	pi.on("ui_prompt_start", (event, ctx) => {
		try {
			if (!inTui(ctx)) return;
			send({ ...base(ctx), e: "wait", d: String(event.title || event.kind || "").slice(0, 120), focused: focused() });
		} catch {}
	});

	pi.on("ui_prompt_end", (_event, ctx) => {
		try {
			if (!inTui(ctx)) return;
			send({ ...base(ctx), e: "unwait" });
		} catch {}
	});

	// 上下文占用：每轮结束更新一次，末轮再确认一次（压缩后 tokens 可能为 null，宠物侧保持上一档）
	pi.on("turn_end", (_event, ctx) => {
		try {
			if (!inTui(ctx)) return;
			const usage = ctx.getContextUsage?.();
			if (!usage) return;
			send({ ...base(ctx), e: "ctx", pct: usage.percent, tok: usage.tokens, win: usage.contextWindow });
		} catch {}
	});

	// 助手消息以 error 结束才算这一轮失败（工具非零退出不算）
	pi.on("message_end", (event, ctx) => {
		try {
			if (!inTui(ctx)) return;
			const message = event.message as { role?: string; stopReason?: string; errorMessage?: string };
			if (message?.role !== "assistant" || message.stopReason !== "error") return;
			send({
				...base(ctx),
				e: "fail",
				m: String(message.errorMessage || "error").slice(0, 200),
				focused: focused(),
			});
		} catch {}
	});

	pi.on("agent_settled", (event, ctx) => {
		try {
			if (!inTui(ctx)) return;
			const usage = ctx.getContextUsage?.();
			if (usage) send({ ...base(ctx), e: "ctx", pct: usage.percent, tok: usage.tokens, win: usage.contextWindow });
			send({ ...base(ctx), e: "done", aborted: event.aborted === true, focused: focused() });
		} catch {}
	});

	pi.on("session_shutdown", (_event, ctx) => {
		try {
			if (!inTui(ctx)) return;
			send({ ...base(ctx), e: "bye" });
		} catch {}
	});
}
