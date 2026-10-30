// The game server for Gettic's first TD, running on Cloudflare Workers.
// It keeps the list of public games and passes game messages between the host
// and the other players, so nobody has to open ports in their router.
//
// Every game connects with a WebSocket:
//   /host?version=1.12      the host gets a 5-letter code ({"t":"hosted","code":...})
//   /join?code=ABCDE        a player gets an id ({"t":"joined","id":...})
//   /games?version=1.12     (plain web request) the public games for that version
//
// Game messages are binary: [peer id: int32][channel: byte][mode: byte][data].
// The sender puts the receiver's id first (the host may use 0 for everyone, or
// -id for everyone but that player). The server swaps in the sender's id.
// Players can only send to the host. The host sends small text messages:
//   {"t":"info","public":true,"players":2,"wave":5}   update the game list
//   {"t":"kick","id":12345}                           drop a player
// and gets {"t":"peer","id":...} and {"t":"left","id":...} when players come and go.

import { DurableObject } from "cloudflare:workers";

const LETTERS = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"; // the same letters the game uses
const MAX_PLAYERS = 4;
const MAX_LISTED = 20;

export default {
  async fetch(request, env) {
    const path = new URL(request.url).pathname;
    if (!["/host", "/join", "/games"].includes(path)) {
      return new Response("Gettic's first TD game server", { status: 404 });
    }
    // One object holds every game, so the list and the codes are all in one place
    return env.LOBBY.get(env.LOBBY.idFromName("lobby")).fetch(request);
  },
};

export class Lobby extends DurableObject {
  async fetch(request) {
    const url = new URL(request.url);
    const query = url.searchParams;
    if (url.pathname === "/games") {
      return Response.json(this.publicGames(query.get("version") || ""));
    }
    if (request.headers.get("Upgrade") !== "websocket") {
      return new Response("Connect with a WebSocket", { status: 426 });
    }
    const [client, server] = Object.values(new WebSocketPair());
    if (url.pathname === "/host") {
      this.host(server, query.get("version") || "");
    } else {
      this.join(server, (query.get("code") || "").toUpperCase());
    }
    return new Response(null, { status: 101, webSocket: client });
  }

  publicGames(version) {
    const games = [];
    for (const ws of this.ctx.getWebSockets("host")) {
      const game = ws.deserializeAttachment();
      if (game.public && game.version === version && game.players < MAX_PLAYERS) {
        games.push({ code: game.code, players: game.players, wave: game.wave });
      }
    }
    // Games with the most players first
    games.sort((a, b) => b.players - a.players);
    return games.slice(0, MAX_LISTED);
  }

  host(ws, version) {
    let code;
    do {
      code = randomCode();
    } while (this.ctx.getWebSockets("room:" + code).length > 0);
    // Tags let us find sockets again after the object has slept between messages
    this.ctx.acceptWebSocket(ws, ["host", "room:" + code, `to:${code}:1`]);
    ws.serializeAttachment({ code, id: 1, version, public: false, players: 1, wave: 0 });
    ws.send(JSON.stringify({ t: "hosted", code }));
  }

  join(ws, code) {
    const host = this.ctx.getWebSockets(`to:${code}:1`)[0];
    let problem = "";
    if (!host) {
      problem = "There's no game with that code. Check the code, and that the host is still hosting.";
    } else if (this.ctx.getWebSockets("room:" + code).length >= MAX_PLAYERS) {
      problem = "That game is full (4 players).";
    }
    if (problem) {
      // The game closes the connection once it has read why
      this.ctx.acceptWebSocket(ws, ["refused"]);
      ws.send(JSON.stringify({ t: "error", text: problem }));
      return;
    }
    let id;
    do {
      id = 2 + Math.floor(Math.random() * 0x7ffffff0);
    } while (this.ctx.getWebSockets(`to:${code}:${id}`).length > 0);
    this.ctx.acceptWebSocket(ws, ["room:" + code, `to:${code}:${id}`]);
    ws.serializeAttachment({ code, id });
    ws.send(JSON.stringify({ t: "joined", id }));
    send(host, JSON.stringify({ t: "peer", id }));
  }

  webSocketMessage(ws, message) {
    const me = ws.deserializeAttachment();
    if (!me) {
      return;
    }
    if (typeof message === "string") {
      this.hostMessage(ws, me, message);
      return;
    }
    if (message.byteLength < 6) {
      return;
    }
    const view = new DataView(message);
    const target = view.getInt32(0, true);
    view.setInt32(0, me.id, true);
    let receivers;
    if (me.id !== 1) {
      receivers = this.ctx.getWebSockets(`to:${me.code}:1`);
    } else if (target > 0) {
      receivers = this.ctx.getWebSockets(`to:${me.code}:${target}`);
    } else {
      receivers = this.ctx.getWebSockets("room:" + me.code).filter((p) => {
        const id = p.deserializeAttachment()?.id;
        return id !== 1 && id !== -target;
      });
    }
    for (const p of receivers) {
      send(p, message);
    }
  }

  hostMessage(ws, me, text) {
    if (me.id !== 1) {
      return;
    }
    let m;
    try {
      m = JSON.parse(text);
    } catch {
      return;
    }
    if (m.t === "info") {
      me.public = m.public === true;
      me.players = Math.max(1, Math.min(MAX_PLAYERS, Number(m.players) || 1));
      me.wave = Math.max(0, Math.min(999, Number(m.wave) || 0));
      ws.serializeAttachment(me);
    } else if (m.t === "kick") {
      for (const p of this.ctx.getWebSockets(`to:${me.code}:${Number(m.id)}`)) {
        p.close(4001, "kicked");
      }
    }
  }

  webSocketClose(ws) {
    this.left(ws);
  }

  webSocketError(ws) {
    this.left(ws);
  }

  // The host leaving ends the game for everyone; a player leaving is told to the host.
  left(ws) {
    const me = ws.deserializeAttachment();
    if (!me) {
      close(ws, 1000, "bye");
      return;
    }
    ws.serializeAttachment(null);
    if (me.id === 1) {
      for (const p of this.ctx.getWebSockets("room:" + me.code)) {
        if (p !== ws) {
          p.serializeAttachment(null);
          close(p, 4002, "host left");
        }
      }
    } else {
      for (const h of this.ctx.getWebSockets(`to:${me.code}:1`)) {
        send(h, JSON.stringify({ t: "left", id: me.id }));
      }
    }
    close(ws, 1000, "bye");
  }
}

function randomCode() {
  const bytes = crypto.getRandomValues(new Uint8Array(5));
  return Array.from(bytes, (b) => LETTERS[b & 31]).join("");
}

// Sockets can close at any moment, so sending or closing may fail
function send(ws, message) {
  try {
    ws.send(message);
  } catch {}
}

function close(ws, code, reason) {
  try {
    ws.close(code, reason);
  } catch {}
}
