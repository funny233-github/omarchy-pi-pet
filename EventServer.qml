import QtQuick
import Quickshell
import Quickshell.Io

// 事件入口：两个生产者往这个 Unix socket 写一行 JSON。
//   src=host  —— ~/.pi/agent/extensions/agent-pet-pi.ts，单向推送（不带 id）
//   src=child —— 宠物子进程里的 ext/pet.ts，一问一答（带 id，这里回一行）
//
// 针对 Quickshell SocketServer 的两处处理（quickshell-git 0.3.0）：
// - 对端先断开时会记一条 PeerClosedError 警告：读完一行由这边断开，写端用 shut-none 不半关闭；
// - 断开的连接对象要等监听停掉才释放（每个约 2 KB）：累计一批且没有未断开的连接时重建一次监听。
Scope {
  id: events

  // 父目录要先建好（0700）再调用 start()
  property string path: ""
  signal received(string line)

  readonly property int recycleAfter: 500
  property int accepted: 0
  property int open: 0

  function start() {
    server.active = true
  }

  function recycle() {
    if (accepted < recycleAfter || open > 0) return
    accepted = 0
    server.active = false
    server.active = true
  }

  SocketServer {
    id: server
    path: events.path

    handler: Socket {
      id: conn

      onConnectionStateChanged: {
        if (connected) {
          events.open++
          events.accepted++
        } else {
          events.open--
          Qt.callLater(events.recycle)
        }
      }

      parser: SplitParser {
        onRead: line => {
          events.received(line)
          // 带 id 的是子进程的请求：先回一行再断开；其余（host 推送）读完就断。
          var reply = events.replyFor(line)
          if (reply !== "") {
            // 写法和 Omarchy 自己的 IPC socket 一致：write → flush → 断开，
            // 少了 flush 回包可能在断开时被丢掉
            try {
              conn.write(reply + "\n")
              conn.flush()
            } catch (e) {}
          }
          Qt.callLater(() => {
            if (conn) conn.connected = false
          })
        }
      }
    }
  }

  // 由 Service 接管：返回非空字符串则写回给请求方
  property var replyHandler: null

  function replyFor(line) {
    try {
      if (!replyHandler) return ""
      var out = replyHandler(line)
      return out === undefined || out === null ? "" : String(out)
    } catch (e) {
      return ""
    }
  }
}
