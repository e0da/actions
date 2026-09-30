import net from 'node:net';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export function pinTcpListenersToLoopback() {
  const listen = net.Server.prototype.listen;
  net.Server.prototype.listen = function (...args) {
    if (typeof args[0] === 'number') {
      const callback = args.find(value => typeof value === 'function');
      return listen.call(this, { port: args[0], host: '127.0.0.1' }, ...(callback ? [callback] : []));
    }
    if (args[0] && typeof args[0] === 'object' && 'port' in args[0])
      args[0] = { ...args[0], host: '127.0.0.1' };
    return listen.apply(this, args);
  };
  return () => { net.Server.prototype.listen = listen; };
}

if (path.resolve(process.argv[1] ?? '') === fileURLToPath(import.meta.url)) {
  const root = fileURLToPath(new URL('../', import.meta.url));
  process.env.PROMPTFOO_CONFIG_DIR = path.join(root, '.promptfoo');
  process.env.PROMPTFOO_DISABLE_TELEMETRY = '1';
  process.env.PROMPTFOO_DISABLE_UPDATE = '1';
process.env.PROMPTFOO_DISABLE_SHARING = '1';
process.env.PROMPTFOO_DISABLE_REMOTE_GENERATION = '1';
  pinTcpListenersToLoopback();
  const entrypoint = new URL('entrypoint.js', import.meta.resolve('promptfoo'));
  process.argv = [process.execPath, fileURLToPath(entrypoint), 'view', '--port', '15500', '--no'];
  await import(entrypoint.href);
}
