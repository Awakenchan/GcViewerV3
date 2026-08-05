const http = require("http");
const fs = require("fs");
const path = require("path");
const { WebSocketServer } = require("ws");

const WS_PORT = Number(process.env.GCVIEW_WS_PORT || 8765);
const HTTP_PORT = Number(process.env.GCVIEW_HTTP_PORT || 8766);

const peers = new Set();

const wss = new WebSocketServer({ port: WS_PORT });

wss.on("connection", (socket) => {
    peers.add(socket);
    socket.role = "unknown";

    socket.on("message", (raw) => {
        const text = raw.toString();

        try {
            const parsed = JSON.parse(text);
            if (parsed && parsed.type === "hello" && parsed.role) {
                socket.role = parsed.role;
                console.log(`[relay] ${parsed.role} connected`);
            }
        } catch (err) {
            // forward non-JSON frames untouched
        }

        for (const peer of peers) {
            if (peer !== socket && peer.readyState === peer.OPEN) {
                peer.send(text);
            }
        }
    });

    socket.on("close", () => {
        peers.delete(socket);
        console.log(`[relay] ${socket.role} disconnected`);
    });

    socket.on("error", () => {
        peers.delete(socket);
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
    console.log(`[relay] websocket  ws://127.0.0.1:${WS_PORT}`);
    console.log(`[relay] front-end  http://127.0.0.1:${HTTP_PORT}`);
});
