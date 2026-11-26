#!/usr/bin/env node
/**
 * 探测代理：把 dsh-pet 的 /dsh-pet-7340 路由与渲染页放到同一 origin。
 * 用法：node tools/pet-proxy.mjs --plugin /tmp/dsh-pet-probe/pkg --upstream 3080 --port 3090
 */
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { join, extname } from 'node:path';

const args = process.argv.slice(2);
const arg = (k, d) => { const i = args.indexOf(k); return i >= 0 ? args[i + 1] : d; };
const plugin = arg('--plugin', '/tmp/dsh-pet-probe/pkg');
const upstream = Number(arg('--upstream', '3080'));
const port = Number(arg('--port', '3090'));
const helperDir = join(plugin, 'runtime', 'electron-helper');

const mime = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css',
  '.json': 'application/json', '.png': 'image/png', '.webm': 'video/webm', '.ttf': 'font/ttf' };

const server = createServer(async (req, res) => {
  const url = new URL(req.url, 'http://127.0.0.1');
  if (url.pathname.startsWith('/dsh-pet-native/')) {
    let name = url.pathname.slice('/dsh-pet-native/'.length);
    if (name === 'probe.html') {
      const html = await readFile(join(helperDir, 'index.html'), 'utf8');
      const injected = html.replace('<script src=', '<script src="/dsh-pet-native/pet-bridge-shim.js"></script>\n<script src=');
      res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
      res.end(injected);
      return;
    }
    if (name === 'pet-bridge-shim.js') {
      const js = await readFile(new URL('./pet-bridge-shim.js', import.meta.url));
      res.writeHead(200, { 'content-type': 'text/javascript' });
      res.end(js);
      return;
    }
    const file = join(helperDir, name);
    try {
      const data = await readFile(file);
      res.writeHead(200, { 'content-type': mime[extname(file)] || 'application/octet-stream' });
      res.end(data);
    } catch {
      res.writeHead(404); res.end('not found');
    }
    return;
  }
  if (url.pathname.startsWith('/dsh-pet-7340/')) {
    const up = await fetch(`http://127.0.0.1:${upstream}${url.pathname}${url.search}`, { method: req.method });
    const body = Buffer.from(await up.arrayBuffer());
    res.writeHead(up.status, { 'content-type': up.headers.get('content-type') || 'application/octet-stream' });
    res.end(body);
    return;
  }
  res.writeHead(404); res.end('not found');
});
server.listen(port, '127.0.0.1', () => {
  console.log(`[pet-proxy] http://127.0.0.1:${port}/dsh-pet-native/probe.html`);
});
