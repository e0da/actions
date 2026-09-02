#!/usr/bin/env node

import { readFile, writeFile } from "node:fs/promises";

const readJson = async (path) => JSON.parse(await readFile(path, "utf8"));
const writeJson = (path, value) => writeFile(path, `${JSON.stringify(value, null, 2)}\n`);
const names = (files, label) => {
  if (typeof files !== "object" || files === null || Array.isArray(files)) {
    throw new Error(`${label}.files must be an object`);
  }
  return Object.keys(files).sort();
};
const equalNames = (left, right) =>
  left.length === right.length && left.every((name, index) => name === right[index]);
const requireCompleteListing = (gist, label) => {
  if (gist.truncated !== false) {
    throw new Error(`${label} does not contain a complete Gist file listing`);
  }
};
const manifestNames = (gist, manifestFile, label) => {
  const content = gist.files?.[manifestFile]?.content;
  if (typeof content !== "string") throw new Error(`${label} is missing ${manifestFile}`);
  const manifest = JSON.parse(content);
  if (!Array.isArray(manifest.files)) throw new Error(`${label} ${manifestFile}.files must be an array`);
  const managed = manifest.files.map((entry, index) => {
    if (typeof entry?.path !== "string" || entry.path.length === 0) {
      throw new Error(`${label} ${manifestFile}.files[${index}].path must be a non-empty string`);
    }
    return entry.path;
  });
  if (new Set(managed).size !== managed.length) throw new Error(`${label} ${manifestFile} has duplicate paths`);
  return managed.sort();
};

const [verb, ...args] = process.argv.slice(2);

if (verb === "prepare") {
  const [beforePath, payloadPath, manifestFile, requestPath, expectationPath] = args;
  if (!beforePath || !payloadPath || requestPath === undefined || expectationPath === undefined) {
    throw new Error("usage: reconcile-gist-files prepare <before> <payload> <manifest-file-or-empty> <request> <expectation>");
  }
  const before = await readJson(beforePath);
  const payload = await readJson(payloadPath);
  const payloadNames = names(payload.files, "payload");
  const request = structuredClone(payload);

  if (!manifestFile) {
    await writeJson(requestPath, request);
    await writeJson(expectationPath, { mode: "subset", expected_names: payloadNames });
    process.exit(0);
  }

  requireCompleteListing(before, "existing gist");
  const beforeNames = names(before.files, "existing gist");
  const previousManaged = before.files[manifestFile]
    ? manifestNames(before, manifestFile, "existing gist")
    : beforeNames;
  const nextManaged = manifestNames(payload, manifestFile, "payload");
  if (!equalNames(payloadNames, nextManaged)) {
    throw new Error("payload filenames must exactly match its managed manifest");
  }
  const previousManagedSet = new Set(previousManaged);
  const nextManagedSet = new Set(nextManaged);
  const unmanaged = beforeNames.filter((name) => !previousManagedSet.has(name));
  for (const name of previousManaged) {
    if (!nextManagedSet.has(name)) request.files[name] = null;
  }

  await writeJson(requestPath, request);
  await writeJson(expectationPath, {
    mode: "exact",
    expected_names: [...new Set([...unmanaged, ...nextManaged])].sort(),
  });
  process.exit(0);
}

if (verb === "verify") {
  const [responsePath, payloadPath, expectationPath] = args;
  if (!responsePath || !payloadPath || !expectationPath) {
    throw new Error("usage: reconcile-gist-files verify <response> <payload> <expectation>");
  }
  const actual = await readJson(responsePath);
  const expected = await readJson(payloadPath);
  const expectation = await readJson(expectationPath);
  const actualNames = names(actual.files, "gist response");
  if (expectation.mode === "exact") {
    requireCompleteListing(actual, "gist response");
    if (!equalNames(actualNames, expectation.expected_names)) {
      throw new Error(`Gist filename read-back mismatch: expected ${expectation.expected_names.join(",")}; received ${actualNames.join(",")}`);
    }
  }
  for (const [name, file] of Object.entries(expected.files)) {
    if (actual.files?.[name]?.content !== file.content) {
      throw new Error(`Gist read-back mismatch: ${name}`);
    }
  }
  process.exit(0);
}

throw new Error("usage: reconcile-gist-files <prepare|verify> ...");
