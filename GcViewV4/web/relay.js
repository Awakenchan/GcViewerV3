const http = require("http");
const fs = require("fs");
const path = require("path");
const { WebSocketServer } = require("ws");

const WS_PORT = Number(process.env.GCVIEW_WS_PORT || 8765);
const HTTP_PORT = Number(process.env.GCVIEW_HTTP_PORT || 8766);

const peers = new Set();
let toolSocket = null;
let toolHello = null;

const wss = new WebSocketServer({ port: WS_PORT });

function stamp() {
    return new Date().toLocaleTimeString();
}

function log(...args) {
    console.log(`[relay ${stamp()}]`, ...args);
}

function send(socket, obj) {
    if (socket && socket.readyState === socket.OPEN) {
        try { socket.send(JSON.stringify(obj)); } catch (err) {}
    }
}

function broadcastToWeb(obj) {
    for (const peer of peers) {
        if (peer !== toolSocket && peer.readyState === peer.OPEN) send(peer, obj);
    }
}

wss.on("connection", (socket) => {
    peers.add(socket);
    socket.role = "unknown";

    socket.on("message", (raw) => {
        const text = raw.toString();

        let parsed = null;
        try { parsed = JSON.parse(text); } catch (err) { parsed = null; }

        if (parsed && parsed.type === "hello") {
            socket.role = parsed.role || "unknown";

            if (socket.role === "tool" || socket.role === "game") {
                if (toolSocket && toolSocket !== socket) {
                    log("replacing previous tool connection");
                    send(toolSocket, { type: "peer", role: "relay", event: "superseded" });
                    try { toolSocket.close(); } catch (err) {}
                }
                toolSocket = socket;
                toolHello = parsed;
                log(`tool connected (${(parsed.info && parsed.info.executor) || "unknown"})`);
                broadcastToWeb(parsed);
                return;
            }

            if (socket.role === "web") {
                log("web connected");
                if (toolSocket && toolHello) send(socket, toolHello);
                send(toolSocket, parsed);
                return;
            }
            return;
        }

        if (parsed && parsed.type === "request") {
            if (toolSocket) {
                send(toolSocket, parsed);
            } else {
                send(socket, { type: "response", id: parsed.id, ok: false, error: "no executor connected" });
            }
            return;
        }

        if (parsed && parsed.type === "response") {
            broadcastToWeb(parsed);
            return;
        }

        for (const peer of peers) {
            if (peer !== socket && peer.readyState === peer.OPEN) {
                try { peer.send(text); } catch (err) {}
            }
        }
    });

    socket.on("close", () => {
        peers.delete(socket);
        if (socket === toolSocket) {
            toolSocket = null;
            toolHello = null;
            log("tool disconnected");
            broadcastToWeb({ type: "peer", role: "tool", event: "disconnect" });
        } else if (socket.role === "web") {
            log("web disconnected");
        }
    });

    socket.on("error", () => {
        peers.delete(socket);
        if (socket === toolSocket) {
            toolSocket = null;
            toolHello = null;
            broadcastToWeb({ type: "peer", role: "tool", event: "disconnect" });
        }
    });
});

const server = http.createServer((req, res) => {
    const file = path.join(__dirname, "index.html");
    fs.readFile(file, (err, data) => {
        if (err) {
            res.writeHead(404, { "Content-Type": "text/plain" });
            res.end("index.html not found");
            return;
        }
        res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
        res.end(data);
    });
});

server.listen(HTTP_PORT, () => {
    log(`websocket  ws://127.0.0.1:${WS_PORT}`);
    log(`front-end  http://127.0.0.1:${HTTP_PORT}`);
});
