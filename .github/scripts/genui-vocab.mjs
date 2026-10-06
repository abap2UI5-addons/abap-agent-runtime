#!/usr/bin/env node
/*
 * genui-vocab - generates z2ui5_cl_agent_gen_vocab, the closed vocabulary
 * z2ui5_cl_agent_genui validates a generated UI tree against, from the
 * abap2UI5 protocol's portable view profile v1.
 *
 * Inputs (both pinned, so the output only changes when a pin moves):
 *   .github/genui/portable-v1.json        a copy of abap2UI5/protocol
 *                                          profiles/portable-v1.json
 *   @abap2ui5/linter data/properties.json  the UI5 metadata snapshot of the
 *                                          linter (package-lock.json pins it):
 *                                          property types, enum values, the
 *                                          aggregation types, class hierarchy
 *
 * What it writes: one entry per control of the profile and per member the
 * profile allows on it - default aggregation (D), property with its type
 * class (P), aggregation with its multiplicity and type (A), event (E), and
 * the types a control can stand in for (T: itself, its ancestors, its
 * interfaces) - everything filtered to the UI5 1.71 floor (a member or an
 * enum value introduced later is left out).
 *
 *   npm run genui:vocab            regenerate src/01/z2ui5_cl_agent_gen_vocab.clas.abap
 *   npm run genui:check            fail when the committed class is not what the pins generate
 *   npm run genui:drift            fail when the pinned profile differs from upstream
 *                                  (PROTOCOL_DIR=<checkout> or the raw file of protocol main)
 *   npm run genui:vocab -- --update   copy the upstream profile into the pin, then regenerate
 */
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
const PIN = path.join(ROOT, ".github", "genui", "portable-v1.json");
const META = path.join(ROOT, "node_modules", "@abap2ui5", "linter", "data", "properties.json");
const OUT = path.join(ROOT, "src", "01", "z2ui5_cl_agent_gen_vocab.clas.abap");
const UPSTREAM = "https://raw.githubusercontent.com/abap2UI5/protocol/main/profiles/portable-v1.json";
const FLOOR = "1.71";

function fail(message) {
  console.error(`::error::genui-vocab: ${message}`);
  process.exit(1);
}

function newer(since) {
  if (!since) return false;
  const a = String(since).split(".").map((x) => parseInt(x, 10) || 0);
  const b = FLOOR.split(".").map((x) => parseInt(x, 10));
  for (let i = 0; i < 2; i++) {
    if ((a[i] || 0) !== b[i]) return (a[i] || 0) > b[i];
  }
  return false;
}

async function upstream() {
  if (process.env.PROTOCOL_DIR) {
    return fs.readFileSync(path.join(process.env.PROTOCOL_DIR, "profiles", "portable-v1.json"), "utf8");
  }
  const res = await fetch(UPSTREAM);
  if (!res.ok) fail(`${UPSTREAM}: HTTP ${res.status}`);
  return res.text();
}

function generate(pinText, meta) {
  const profile = JSON.parse(pinText);
  const controls = meta.controls;

  const ancestors = (name) => {
    const result = [];
    let cur = name;
    while (cur && controls[cur]) {
      result.push(cur);
      cur = controls[cur].parent;
    }
    return result;
  };
  const member = (name, kind, key) => {
    for (const a of ancestors(name)) {
      const m = (controls[a][kind] || {})[key];
      if (m) return m;
    }
    return undefined;
  };
  const typeClass = (type) => {
    if (type === "boolean") return ["B", ""];
    if (type === "int") return ["I", ""];
    if (type === "float") return ["F", ""];
    if (type === "string") return ["S", ""];
    if (type === "sap.ui.core.CSSSize") return ["C", ""];
    if (type === "sap.ui.core.URI") return ["U", ""];
    if (meta.enums[type]) {
      const since = meta.enumSince[type] || {};
      const keys = meta.enumKeys[type] || {};
      const values = meta.enums[type].filter((v) => !newer(since[v])).map((v) => keys[v] || v);
      return ["E", values.join("|")];
    }
    // sap.ui.core.ID, any, object, a CSS shorthand, ...: never a literal
    return ["O", ""];
  };

  const rows = [];
  const names = Object.keys(profile.controls).sort();
  for (const name of names) {
    const c = profile.controls[name];
    if (!controls[name]) fail(`${name} of the profile is not in the UI5 metadata`);
    if (newer(controls[name].since)) continue;
    const defAgg = c.defaultAggregation ? member(name, "aggregations", c.defaultAggregation) : undefined;
    // a default aggregation introduced after the floor (sap.m.Title content
    // 1.87) is none at the floor - left out like the aggregation itself
    const def = defAgg && !newer(defAgg.since) ? c.defaultAggregation : "";
    if (def) {
      rows.push([name, "D", def, defAgg.multiple ? "M" : "S", defAgg.type]);
    }
    for (const p of (c.properties || []).map((x) => x.name).sort()) {
      const m = member(name, "properties", p);
      if (!m || newer(m.since) || m.deprecated) continue;
      const [t, info] = typeClass(m.type);
      rows.push([name, "P", p, t, info]);
    }
    const aggs = new Set((c.aggregations || []).map((x) => x.name));
    if (def) aggs.add(def);
    for (const a of [...aggs].sort()) {
      const m = member(name, "aggregations", a);
      if (!m || newer(m.since)) continue;
      rows.push([name, "A", a, m.multiple ? "M" : "S", m.type]);
    }
    for (const e of (c.events || []).map((x) => x.name).sort()) {
      const m = member(name, "events", e);
      if (!m || newer(m.since) || m.deprecated) continue;
      rows.push([name, "E", e, "", ""]);
    }
    const types = new Set();
    for (const a of ancestors(name)) {
      types.add(a);
      for (const i of controls[a].interfaces || []) types.add(i);
    }
    for (const t of [...types].sort()) rows.push([name, "T", t, "", ""]);
    if (c.tolerated) rows.push([name, "L", "layoutData", "", ""]);
  }

  const q = (s) => "`" + String(s).replace(/`/g, "``") + "`";
  const hash = crypto.createHash("sha256").update(pinText).digest("hex");
  const lines = [];
  lines.push(`"! GENERATED by .github/scripts/genui-vocab.mjs - do not edit by hand.`);
  lines.push(`"!`);
  lines.push(`"! The closed vocabulary of generative UI (z2ui5_cl_agent_genui): the`);
  lines.push(`"! controls of the abap2UI5 protocol's portable view profile v1`);
  lines.push(`"! (profiles/portable-v1.json, pinned as .github/genui/portable-v1.json)`);
  lines.push(`"! with the members the profile allows on them, typed from the UI5`);
  lines.push(`"! metadata of the abap2UI5 linter and filtered to the UI5 ${FLOOR} floor.`);
  lines.push(`"! npm run genui:check fails when this class drifts from the pins.`);
  lines.push(`CLASS z2ui5_cl_agent_gen_vocab DEFINITION PUBLIC FINAL CREATE PUBLIC.`);
  lines.push(``);
  lines.push(`  PUBLIC SECTION.`);
  lines.push(``);
  lines.push(`    CONSTANTS c_profile TYPE string VALUE \`portable-v1\`.`);
  lines.push(`    CONSTANTS c_floor TYPE string VALUE \`${FLOOR}\`.`);
  lines.push(`    "! sha256 of the pinned profile this class was generated from`);
  lines.push(`    CONSTANTS c_source TYPE string VALUE \`${hash}\`.`);
  lines.push(``);
  lines.push(`    TYPES:`);
  lines.push(`      "! control: the full UI5 name. kind: D default aggregation, P property,`);
  lines.push(`      "! A aggregation, E event, T a type the control stands in for (itself,`);
  lines.push(`      "! an ancestor, an interface), L a layout-data element. P: type is B`);
  lines.push(`      "! boolean, I int, F float, S string, C CSS size, U URI, E enum (info:`);
  lines.push(`      "! the values, |-separated), O no literal allowed. A and D: type is M`);
  lines.push(`      "! multiple or S single, info the type a child must stand in for.`);
  lines.push(`      BEGIN OF ty_s_entry,`);
  lines.push(`        control TYPE string,`);
  lines.push(`        kind    TYPE c LENGTH 1,`);
  lines.push(`        name    TYPE string,`);
  lines.push(`        type    TYPE c LENGTH 1,`);
  lines.push(`        info    TYPE string,`);
  lines.push(`      END OF ty_s_entry.`);
  lines.push(`    TYPES ty_t_entry TYPE STANDARD TABLE OF ty_s_entry WITH EMPTY KEY.`);
  lines.push(``);
  lines.push(`    CLASS-METHODS get`);
  lines.push(`      RETURNING`);
  lines.push(`        VALUE(result) TYPE ty_t_entry.`);
  lines.push(``);
  lines.push(`  PROTECTED SECTION.`);
  lines.push(``);
  lines.push(`  PRIVATE SECTION.`);
  lines.push(``);
  lines.push(`ENDCLASS.`);
  lines.push(``);
  lines.push(``);
  lines.push(`CLASS z2ui5_cl_agent_gen_vocab IMPLEMENTATION.`);
  lines.push(``);
  lines.push(`  METHOD get.`);
  lines.push(``);
  lines.push(`    DATA lt_raw TYPE string_table.`);
  lines.push(`    DATA lv_raw TYPE string.`);
  lines.push(`    DATA ls_entry TYPE ty_s_entry.`);
  lines.push(``);
  lines.push(`    " one line per entry - control;kind;name;type;info - in statements`);
  lines.push(`    " every release reads as they are, so the downport has nothing to do`);
  for (const row of rows) {
    if (row.some((x) => String(x).includes(";"))) fail(`a ; in ${row.join(" ")}`);
    const text = row.join(";").replace(/;+$/, "");
    if (text.length <= 200) {
      lines.push(`    APPEND ${q(text)} TO lt_raw.`);
      continue;
    }
    // a long enum list: in pieces of whole values
    const pieces = [];
    let cur = "";
    for (const part of text.split("|")) {
      const next = cur ? `${cur}|${part}` : part;
      if (next.length > 120 && cur) {
        pieces.push(cur + "|");
        cur = part;
      } else {
        cur = next;
      }
    }
    pieces.push(cur);
    lines.push(`    lv_raw = ${pieces.map(q).join("\n          && ")}.`);
    lines.push(`    APPEND lv_raw TO lt_raw.`);
  }
  lines.push(``);
  lines.push(`    LOOP AT lt_raw INTO lv_raw.`);
  lines.push(`      CLEAR ls_entry.`);
  lines.push(`      SPLIT lv_raw AT ';' INTO ls_entry-control ls_entry-kind ls_entry-name ls_entry-type ls_entry-info.`);
  lines.push(`      INSERT ls_entry INTO TABLE result.`);
  lines.push(`    ENDLOOP.`);
  lines.push(``);
  lines.push(`  ENDMETHOD.`);
  lines.push(``);
  lines.push(`ENDCLASS.`);
  return { text: lines.join("\n") + "\n", rows: rows.length, controls: names.length };
}

const args = process.argv.slice(2);
const meta = JSON.parse(fs.readFileSync(META, "utf8"));

if (args.includes("--drift") || args.includes("--update")) {
  const up = await upstream();
  const pinned = fs.readFileSync(PIN, "utf8");
  if (up === pinned) {
    console.log("genui-vocab: the pinned profile is upstream's");
  } else if (args.includes("--update")) {
    fs.writeFileSync(PIN, up);
    console.log("genui-vocab: pinned profile updated from upstream");
  } else {
    fail("the pinned .github/genui/portable-v1.json differs from abap2UI5/protocol main - " +
         "run npm run genui:vocab -- --update, review the vocabulary diff and the genui tests");
  }
  if (args.includes("--drift")) process.exit(0);
}

const pinText = fs.readFileSync(PIN, "utf8");
const out = generate(pinText, meta);
if (args.includes("--check")) {
  const current = fs.existsSync(OUT) ? fs.readFileSync(OUT, "utf8") : "";
  if (current !== out.text) fail(`${path.relative(ROOT, OUT)} is not what the pins generate - run npm run genui:vocab`);
  console.log(`genui-vocab: up to date (${out.controls} controls, ${out.rows} entries)`);
} else {
  fs.writeFileSync(OUT, out.text);
  console.log(`genui-vocab: wrote ${path.relative(ROOT, OUT)} (${out.controls} controls, ${out.rows} entries)`);
}
