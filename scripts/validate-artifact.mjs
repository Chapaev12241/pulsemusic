import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const projectRoot = resolve(fileURLToPath(new URL("..", import.meta.url)));
const workerPath = resolve(projectRoot, "dist/server/index.js");
const manifestPath = resolve(projectRoot, "dist/.openai/hosting.json");

const [source, manifest] = await Promise.all([
  readFile(workerPath, "utf8"),
  readFile(manifestPath, "utf8"),
]);
JSON.parse(manifest);
const release = JSON.parse(await readFile(resolve(projectRoot, 'docs/release.json'), 'utf8'));
for (const file of ['index.html', 'import.html']) {
  const html = await readFile(resolve(projectRoot, 'docs', file), 'utf8');
  assert(html.includes(`id="appVersion" data-build="${release.build}">Сборка ${release.build}`), `${file}: build label must match release.json`);
  assert(html.includes(`./release.js?v=${release.build}`), `${file}: updater version must match release.json`);
  assert(!html.includes('onclick="location.replace'), `${file}: updater must not hardcode a release URL`);
  for (const [,version] of html.matchAll(/<script[^>]*src="[^"?]+\?v=(\d+)"/g)) assert.equal(Number(version),release.build,`${file}: script build mismatch`);
}

// A data URL forces ESM parsing even though the generated output has no package.json.
const moduleUrl = `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`;
const workerModule = await import(moduleUrl);
assert.equal(
  typeof workerModule.default?.fetch,
  "function",
  `${pathToFileURL(workerPath)} must export default.fetch`,
);

console.log("Artifact is valid ESM and exports default.fetch");
