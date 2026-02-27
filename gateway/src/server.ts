import { WebSocketServer } from "ws";
import express from "express";
import { createServer } from "http";
import { SessionRegistry } from "./sessions/SessionRegistry";
import { EventRouter } from "./events/EventRouter";
import { createHookReceiver } from "./events/HookReceiver";
import { ClientHandler } from "./transport/ClientHandler";

const PORT = parseInt(process.env.AGENTCOCKPIT_PORT ?? "19000", 10);

async function main() {
  const registry = new SessionRegistry();
  const router = new EventRouter();

  await registry.start();

  const app = express();
  app.use(express.json({ limit: "10mb" }));
  app.use(createHookReceiver(router, registry));

  const httpServer = createServer(app);
  const wss = new WebSocketServer({ server: httpServer });

  wss.on("connection", (ws) => {
    new ClientHandler(ws, registry, router);
  });

  httpServer.listen(PORT, "0.0.0.0", () => {
    console.log(`[gateway] Listening on port ${PORT}`);
    console.log(`[gateway] WebSocket:     ws://0.0.0.0:${PORT}`);
    console.log(`[gateway] Hook receiver: http://0.0.0.0:${PORT}/hook`);
    console.log(`[gateway] Health:        http://0.0.0.0:${PORT}/health`);
  });

  const shutdown = () => {
    console.log("[gateway] Shutting down...");
    registry.stop();
    wss.close();
    httpServer.close(() => process.exit(0));
  };
  process.on("SIGTERM", shutdown);
  process.on("SIGINT", shutdown);
}

main().catch((err) => { console.error("[gateway] Fatal:", err); process.exit(1); });
