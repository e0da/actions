import { test } from 'node:test';
import assert from 'node:assert/strict';
import net from 'node:net';
import { pinTcpListenersToLoopback } from '../src/view.mjs';

test('viewer listener binds only loopback with numeric and options arguments', async () => {
  const restore = pinTcpListenersToLoopback();
  try {
    for (const argument of [0, { port: 0, host: '0.0.0.0' }]) {
      const server = net.createServer();
      await new Promise(resolve => server.listen(argument, resolve));
      assert.equal(server.address().address, '127.0.0.1');
      await new Promise(resolve => server.close(resolve));
    }
  } finally { restore(); }
});
