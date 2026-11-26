import { cp, mkdir, readFile, writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";

const webRoot = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "..",
);
const source = path.resolve(webRoot, "../..");
const destination = path.join(webRoot, "public", "landing");
// Copy the existing adjacent site; the committed snapshot works in standalone clones.
const html = await readFile(path.join(source, "index.html"), "utf8");
await mkdir(destination, { recursive: true });
for (const name of ["styles.css", "app.js"])
  await cp(path.join(source, name), path.join(destination, name));
await cp(path.join(source, "assets"), path.join(destination, "assets"), {
  recursive: true,
});
const integratedHtml = html
  .replaceAll('href="assets/', 'href="/landing/assets/')
  .replaceAll('src="assets/', 'src="/landing/assets/')
  .replaceAll('content="assets/', 'content="/landing/assets/')
  .replace('href="styles.css"', 'href="/landing/styles.css"')
  .replace('src="config.js"', 'src="/landing/config.js"')
  .replace('src="app.js"', 'src="/landing/app.js"');
await writeFile(path.join(destination, "index.html"), integratedHtml);
await writeFile(
  path.join(destination, "config.js"),
  "/* Open this deployment's authenticated app, including on preview URLs. */\nwindow.CONNECT_CONFIG = { webAppUrl: '/app' };\n",
);
process.stdout.write(
  "Existing landing page copied to public/landing; demo entry is /app.\n",
);
