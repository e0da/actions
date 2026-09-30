import { readFile } from 'node:fs/promises';
import path from 'node:path';

export async function publicationRun(explicitRun, operationReceipt) {
  if (explicitRun) return path.resolve(explicitRun);
  const receipt = JSON.parse(await readFile(operationReceipt, 'utf8'));
  if (typeof receipt.directory !== 'string' || !path.isAbsolute(receipt.directory)) {
    throw new Error('Operation receipt must bind an absolute run directory');
  }
  const run = JSON.parse(await readFile(path.join(receipt.directory, 'run.json'), 'utf8'));
  if (run.runId !== receipt.runId || run.evalId !== receipt.evalId || !receipt.evalId) {
    throw new Error('Operation receipt and completed run disagree');
  }
  return receipt.directory;
}
