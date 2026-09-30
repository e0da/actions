import { spawnSync } from 'node:child_process';
import { readFile, mkdtemp, rm } from 'node:fs/promises';
import { publicationRun } from './publication-run.mjs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import os from 'node:os';

const root = fileURLToPath(new URL('../', import.meta.url));
const args = process.argv.slice(2);
const option = (name, fallback) => {
  const index = args.indexOf(name);
  return index < 0 ? fallback : args[index + 1];
};
const operator = option('--operator', process.env.PROMPTFOO_SERVICE_OPERATOR
  ?? path.join(os.homedir(), 'src/ops/bin/promptfoo-service'));
const host = option('--host', 'puck');
const config = option('--config');
const temporary = await mkdtemp(path.join(os.tmpdir(), 'agency-eval-publish-'));
const operationReceipt = path.join(temporary, 'operation.json');
const run = (command, parameters, env = {}) => {
  const result = spawnSync(command, parameters, { cwd: root, stdio: 'inherit',
    env: { ...process.env, ...env } });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${command} failed (${result.status})`);
};
try {
if (args.includes('--native') && option('--run')) throw new Error('Choose a new native execution or an existing run');
if (args.includes('--native')) {
  if (!config) throw new Error('--native requires --config with an explicit selected native route');
  run(process.execPath, ['src/run.mjs', 'native', '--config', path.resolve(config),
    '--repeat', option('--repeat', '1'), '--repairs', option('--repairs', '1'),
    '--timeout-ms', option('--timeout-ms', '600000'), '--result-receipt', operationReceipt]);
} else if (!option('--run')) {
  run(process.execPath, ['src/run.mjs', 'demo', '--result-receipt', operationReceipt]);
}
const runPath = await publicationRun(option('--run'), operationReceipt);
const record = JSON.parse(await readFile(path.join(runPath, 'run.json'), 'utf8'));
if (!record.evalId) {
  const { createClient } = await import('@libsql/client');
  const client = createClient({ url: 'file:' + path.join(option('--database', path.join(root, '.promptfoo')), 'promptfoo.db') });
  try {
    const rows = await client.execute({ sql: 'SELECT id, config FROM evals WHERE config LIKE ?', args: ['%' + record.runId + '%'] });
    const matches = rows.rows.filter(row => JSON.parse(row.config).description === `Native agent commissioning (${record.mode}): ${record.runId}`);
    if (matches.length !== 1) throw new Error('Existing run must bind to exactly one native eval record');
    record.evalId = matches[0].id;
  } finally { client.close(); }
}
if (!record.evalId) throw new Error('Run record has no Promptfoo eval id');
  const exported = path.join(temporary, 'eval.json');
  run(process.execPath, ['node_modules/promptfoo/dist/src/main.js', 'export', 'eval',
    record.evalId, '--include-media', '-o', exported], {
    PROMPTFOO_CONFIG_DIR: option('--database', path.join(root, '.promptfoo')),
    PROMPTFOO_DISABLE_TELEMETRY: '1', PROMPTFOO_DISABLE_UPDATE: '1',
    PROMPTFOO_DISABLE_REMOTE_GENERATION: '1', PROMPTFOO_DISABLE_SHARING: '1'
  });
  run(operator, ['--host', host, 'import', exported]);
  run(operator, ['--host', host, 'archive', runPath]);
  console.log(`Published ${record.evalId} and retained trial evidence on ${host}.`);
} finally {
  await rm(temporary, { recursive: true, force: true });
}
