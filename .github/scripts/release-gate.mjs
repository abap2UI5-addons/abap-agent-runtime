#!/usr/bin/env node
/*
 * release-gate - the version of this addon lives in two files and its
 * history in a third, all edited by hand:
 *
 *   package.json                          what the toolchain reads
 *   src/01/z2ui5_if_agent_app.intf.abap   z2ui5_if_agent_app=>version - what
 *                                         abapGit shows in a system
 *                                         (.abapgit.xml VERSION_CONSTANT)
 *   CHANGELOG.md                          what a reader is told changed
 *
 * Nothing but this script keeps them together (the pattern is abap2UI5's
 * .github/scripts/release-gate.mjs, with its changelog.txt replaced by the
 * Markdown changelog the other addons and abap2UI5/mcp-server keep).
 *
 *   npm run check:version                 on every push (part of npm run check):
 *                                         both version numbers agree, CHANGELOG.md
 *                                         has its "## Unreleased" heading and no
 *                                         section for a version ahead of the bump
 *   npm run check:release                 before a tag, and by release.yaml on
 *                                         the tag (--tag X.Y.Z): additionally the
 *                                         changelog has a "## X.Y.Z - YYYY-MM-DD"
 *                                         section for the version, nothing is left
 *                                         under "## Unreleased", and the tag names
 *                                         the same version
 *
 * Everything is decided from the files, so it runs anywhere - RELEASING.md
 * is the checklist around it.
 */
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
const INTERFACE = "src/01/z2ui5_if_agent_app.intf.abap";
const CHANGELOG = "CHANGELOG.md";

const args = process.argv.slice(2);
const release = args.includes("--release") || args.includes("--tag");
const tag = (() => {
  const i = args.indexOf("--tag");
  return i === -1 ? null : String(args[i + 1] || "").replace(/^v/, "");
})();

const read = (file) => readFileSync(path.join(ROOT, file), "utf8");
const problems = [];

const pkg = JSON.parse(read("package.json")).version;
const abap = read(INTERFACE).match(/CONSTANTS\s+version\s+TYPE\s+string\s+VALUE\s+`([^`]+)`/i)?.[1] ?? null;
const changelog = read(CHANGELOG);

if (!/^\d+\.\d+\.\d+$/.test(pkg)) problems.push(`package.json version "${pkg}" is not X.Y.Z`);
if (abap === null) problems.push(`${INTERFACE} has no \`CONSTANTS version TYPE string VALUE \`...\`\``);
else if (abap !== pkg) problems.push(`package.json says ${pkg}, ${INTERFACE} says ${abap} - bump both`);

/* Sections: "## Unreleased" and "## X.Y.Z - YYYY-MM-DD". The split keeps the
 * heading line as the first line of each section. */
const sections = changelog.split(/^(?=## )/m).filter((s) => s.startsWith("## "));
const unreleased = sections.find((s) => /^## unreleased\s*$/im.test(s.split("\n")[0]));
const released = sections
  .map((s) => s.split("\n")[0].match(/^## (\d+\.\d+\.\d+) - (\d{4}-\d{2}-\d{2})\s*$/))
  .filter(Boolean)
  .map((m) => ({ version: m[1], date: m[2] }));

if (!unreleased) {
  problems.push(`${CHANGELOG} has no "## Unreleased" heading - a release cut moves the entries under the version heading and keeps this heading standing above it`);
}
for (const { version } of released) {
  if (compare(version, pkg) > 0) problems.push(`${CHANGELOG} has a section for ${version}, but the repository is at ${pkg}`);
}

if (release) {
  const left = unreleased ? unreleased.split("\n").slice(1).join("\n").trim() : "";
  if (left) {
    problems.push(`${CHANGELOG} still has entries under "## Unreleased" - the release cut MOVES them under "## ${pkg} - <YYYY-MM-DD>":\n${indent(left.slice(0, 400))}`);
  }
  if (!released.some((s) => s.version === pkg)) {
    problems.push(`${CHANGELOG} has no "## ${pkg} - <YYYY-MM-DD>" section - the version being released needs one (it becomes the release notes)`);
  }
  if (tag !== null) {
    if (!/^\d+\.\d+\.\d+$/.test(tag)) problems.push(`the tag "${tag}" is not X.Y.Z - the branch variants are tagged X.Y.Z-standard / X.Y.Z-cloud by the release job`);
    else if (tag !== pkg) problems.push(`the tag says ${tag}, package.json says ${pkg}`);
  }
}

if (problems.length) {
  console.error(`release-gate: ${problems.length} problem(s)\n`);
  for (const p of problems) console.error(`  - ${p}\n`);
  process.exit(1);
}
console.log(`release-gate: ${release ? "release " : ""}${pkg} - package.json, ${INTERFACE} and ${CHANGELOG} agree${tag ? ` with tag ${tag}` : ""}`);

function compare(a, b) {
  const x = a.split(".").map(Number);
  const y = b.split(".").map(Number);
  for (let i = 0; i < 3; i += 1) if (x[i] !== y[i]) return x[i] - y[i];
  return 0;
}
function indent(s) {
  return s.split("\n").map((l) => `        ${l}`).join("\n");
}
