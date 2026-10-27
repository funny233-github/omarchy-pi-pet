/**
 * 宠物子进程专用扩展：只给"宠物自己的 pi"用（bin/agent-pet-pi 通过 -e 显式加载）。
 *
 * 两个职责：
 *   1) 注册唯一工具 pet_state：让模型回头看桌面宠物此刻知道的状态（你在干嘛、上下文多满）。
 *      这是需要回包的通道，走一问一答：带 id 请求，收一行应答。
 *   2) 每轮结束时把"宠物自己"这个持久会话的上下文占用上报回主进程（单向，src=child, e=petctx），
 *      供「查看上下文」菜单显示——不是看你的 TUI 会话，是看她自己的脑袋装了多少。
 *
 * 注意：这个文件只会在子进程里被加载，因此不检查 AGENT_PET_INTERNAL（子进程里它就是 1）。
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { connect } from "node:net";
import { Type } from "typebox";

const REQUEST_TIMEOUT_MS = 700;

function sockPath(): string {
	const runtime = process.env.XDG_RUNTIME_DIR || `/run/user/${uid()}`;
	return `${runtime}/agent-pet/events.sock`;
}

function uid(): number {
	try {
		const fn = (process as unknown as { getuid?: () => number }).getuid;
		return typeof fn === "function" ? fn() : 1000;
	} catch {
		return 1000;
	}
}

/** 单向推送一行，不等回包；宠物没在运行就静默丢弃。 */
function sendOne(payload: Record<string, unknown>): void {
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
				socket.write(`${JSON.stringify(payload)}\n`);
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

/** 向宠物要一份当前状态快照；宠物没在运行或超时都返回 null。 */
function requestState(): Promise<Record<string, unknown> | null> {
	return new Promise((resolve) => {
		let settled = false;
		let socket: ReturnType<typeof connect> | undefined;
		let timer: ReturnType<typeof setTimeout> | undefined;

		const finish = (value: Record<string, unknown> | null): void => {
			if (settled) return;
			settled = true;
			if (timer) clearTimeout(timer);
			try {
				socket?.destroy();
			} catch {}
			resolve(value);
		};

		try {
			socket = connect(sockPath());
		} catch {
			finish(null);
			return;
		}

		timer = setTimeout(() => finish(null), REQUEST_TIMEOUT_MS);
		let buffer = "";

		socket.on("connect", () => {
			try {
				socket!.write(`${JSON.stringify({ v: 1, src: "child", id: "state", e: "state" })}\n`);
			} catch {
				finish(null);
			}
		});

		socket.on("data", (chunk: Buffer) => {
			buffer += chunk.toString("utf8");
			const newline = buffer.indexOf("\n");
			if (newline < 0) return;
			try {
				const reply = JSON.parse(buffer.slice(0, newline)) as { state?: Record<string, unknown> };
				finish(reply?.state ?? null);
			} catch {
				finish(null);
			}
		});

		socket.on("error", () => finish(null));
		socket.on("close", () => finish(null));
	});
}

export default function petState(pi: ExtensionAPI): void {
	// 每轮结束上报自己的上下文占用（压缩后 percent 可能为 null，跳过，保留上一份）
	pi.on("turn_end", (_event, ctx) => {
		try {
			const usage = ctx.getContextUsage?.();
			if (!usage) return;
			if (usage.percent === null || usage.percent === undefined) return;
			sendOne({ v: 1, src: "child", e: "petctx", pct: usage.percent, tok: usage.tokens, win: usage.contextWindow });
		} catch {}
	});

	pi.registerTool({
		name: "pet_state",
		label: "Pet state",
		description:
			"Look at the desktop pet's current view of the user's own Pi session: state (thinking/working/result/waiting/success/error), project name, running tool, context usage percent, and whether the pet is hidden. Call it when a glance makes your line more specific; skip it when a generic remark is enough.",
		parameters: Type.Object({}),
		async execute(_toolCallId, _params) {
			const state = await requestState();
			return {
				content: [
					{
						type: "text" as const,
						text: state ? JSON.stringify(state) : "（桌宠没在运行，看不到）",
					},
				],
				details: { ok: state !== null },
			};
		},
	});
}
