// Local smoke server. Private assets must also stay outside this root.
import { createServer } from 'node:http';
import { readFile, stat, realpath } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, join, resolve, relative, isAbsolute, extname } from 'node:path';

const DEFAULT_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const MIME = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8', '.csv': 'text/csv; charset=utf-8',
  '.svg': 'image/svg+xml', '.png': 'image/png', '.ico': 'image/x-icon',
};
const PRIVATE_SEGMENT = /^(?:\..*|backups?|secrets?|credentials?|evidence|scripts|tests|docs|node_modules)$/i;
const PRIVATE_FILE = /^(?:package(?:-lock)?\.json|vercel\.json|.*(?:\.sql|\.zip|\.7z|\.pem|\.key))$/i;
function within(root, target) {
  const rel = relative(root, target);
  return rel === '' || (!isAbsolute(rel) && rel !== '..' && !rel.startsWith('../') && !rel.startsWith('..\\'));
}
function allowed(parts) {
  return parts.every(p => !PRIVATE_SEGMENT.test(p) && !PRIVATE_FILE.test(p) &&
    !/[\\:\x00-\x1f]/.test(p) && !/[. ]$/.test(p));
}
export async function createStaticServer({ root = DEFAULT_ROOT } = {}) {
  const rootPath = await realpath(root);
  return createServer(async (req, res) => {
    const reply = (status, text) => {
      res.writeHead(status, { 'Content-Type': 'text/plain; charset=utf-8', 'Cache-Control': 'no-store' });
      res.end(req.method === 'HEAD' ? undefined : text);
    };
    if (!['GET', 'HEAD'].includes(req.method)) {
      res.setHeader('Allow', 'GET, HEAD'); reply(405, 'Method Not Allowed'); return;
    }
    try {
      // Inspect raw path before URL normalization can erase parent segments.
      const raw = req.url.split(/[?#]/, 1)[0];
      if (!raw.startsWith('/') || raw.startsWith('//')) { reply(403, 'Forbidden'); return; }
      let decoded;
      try { decoded = decodeURIComponent(raw); } catch { reply(400, 'Bad Request'); return; }
      const parts = decoded.split('/').filter(Boolean);
      if (!allowed(parts)) { reply(403, 'Forbidden'); return; }
      let target = resolve(rootPath, ...parts);
      if (!within(rootPath, target)) { reply(403, 'Forbidden'); return; }
      let actual = await realpath(target);
      if (!within(rootPath, actual)) { reply(403, 'Forbidden'); return; }
      let info = await stat(actual);
      if (info.isDirectory()) {
        target = join(actual, 'index.html'); actual = await realpath(target); info = await stat(actual);
      }
      if (!within(rootPath, actual) || !allowed(relative(rootPath, actual).split(/[\\/]/))) {
        reply(403, 'Forbidden'); return;
      }
      const mime = MIME[extname(actual).toLowerCase()];
      if (!info.isFile() || !mime) { reply(403, 'Forbidden'); return; }
      const body = req.method === 'HEAD' ? undefined : await readFile(actual);
      res.writeHead(200, { 'Content-Type': mime, 'Content-Length': info.size, 'X-Content-Type-Options': 'nosniff' });
      res.end(body);
    } catch (err) { reply(['ENOENT', 'ENOTDIR'].includes(err.code) ? 404 : 403, 'Not Found'); }
  });
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const server = await createStaticServer();
  server.listen(Number(process.env.PORT || 4173), '127.0.0.1', () => {
    console.log(`[static-server] serving ${DEFAULT_ROOT} at http://127.0.0.1:${server.address().port}`);
  });
}
