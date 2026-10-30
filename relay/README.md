# Game server

A small server for multiplayer. It keeps the list of public games and passes messages between the host and the other players, so nobody has to open ports in their router. All of it is in `worker.js`.

It runs on [Cloudflare Workers](https://workers.cloudflare.com/) with a Durable Object, which the free plan covers. Roughly: the free plan allows about 12 hours of 4-player games a day, and more with fewer players.

## Put it online

You need [Node.js](https://nodejs.org/) and a free Cloudflare account. In this folder:

```
npm install
npx wrangler login
npx wrangler deploy
```

`wrangler login` opens your browser so you can sign in to Cloudflare. `wrangler deploy` prints the server's address, like `https://gtd-relay.yourname.workers.dev`. Put that address in `RELAY_URL` at the top of `main.gd`.

## Try it on your own computer

```
npm install
npx wrangler dev
```

Then start the game with the test server:

```
godot --path .. -- --relay=http://127.0.0.1:8787
```
