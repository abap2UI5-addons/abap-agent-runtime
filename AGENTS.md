# AGENTS.md — AI Assistant Guide for the abap2UI5 agent addon

> This file follows the cross-tool AGENTS.md convention and is the single
> agent instruction file of this repository. `CLAUDE.md` next to it is a
> pointer at this file, nothing more.

## What this repository is

An abap2UI5 addon that makes every abap2UI5 app **agent-operable**: an
ABAP-native MCP endpoint (JSON-RPC 2.0 over MCP "Streamable HTTP") through
which an AI agent reads an app's screen as an *agent snapshot v1*, fills fields
and fires events - as the SAP user of the HTTP request, through the app's own
`main( )`. Installed with abapGit after abap2UI5 and
[abap2UI5/headless-frontend](https://github.com/abap2UI5/headless-frontend),
whose `z2ui5_cl_frontend_simulator` is the engine. README.md is the user
documentation; keep it in step with every change.

**Language:** English for all code, comments, docs, commit messages, PRs.

## Layout

| Path | |
|---|---|
| `src/01/` | The engine - activates on ABAP Standard, ABAP Cloud and (downported) 7.02: `z2ui5_if_agent_app` (opt-in), `z2ui5_cl_agent_viewxml` (XML / binding / expression / wire parsers), `z2ui5_cl_agent_snapshot` (snapshot builder + act index), `z2ui5_cl_agent_session` (the four operations), `z2ui5_cl_agent_settings` (opt-in, policy, admins), `z2ui5_cl_agent_audit`, `z2ui5_cl_agent_mcp` (the protocol), tables `Z2UI5_T_AG_*` |
| `src/02/` | abap2UI5 apps: `z2ui5_cl_agent_app_admin`, `z2ui5_cl_agent_app_audit`, `z2ui5_cl_agent_demo` (opted-in example, driven by the unit tests) |
| `src/03/` | ABAP Standard entry: `z2ui5_cl_agent_http` (`if_http_extension`) + ICF node `/sap/bc/z2ui5_agent` (SICF) |
| `src/04/` | ABAP Cloud entry: `z2ui5_cl_agent_http_cloud` (`if_http_service_extension`) |
| `.github/abaplint/` | `abap_cloud.jsonc` (excludes 03), `abap_702.jsonc` (excludes 04, downport) |
| `.github/workflows/` | `ABAP_STANDARD`, `ABAP_CLOUD`, `ABAP_702`, `ABAP_UNIT`, `check-abap2UI5`, `publish-branches` |
| `.github/scripts/unit.mjs` | `npm run unit` - the ABAP Unit tests on abap2UI5's transpiled runtime, in `.unit/` (git-ignored); `ABAP_UNIT` runs it |
| `abaplint.jsonc` | ABAP Standard 7.50, the strict rule set (excludes 04) |
| `abap2ui5lint.jsonc` | the abap2UI5 linter (UI5 1.71 floor, `chain-house-layout`) |

## Rules that are easy to break

- **The snapshot is a contract.** `z2ui5_cl_agent_snapshot` ports
  `lib/snapshot.mjs` / `lib/viewxml.mjs` of abap2UI5/mcp-server and must
  produce the same shape for the same input (`docs/agent-snapshot.md` there).
  Change the reference first, or record a deviation in README ("What an agent
  sees") - never drift silently. The unit tests compare whole snapshots against
  the reference's output; regenerate their fixtures from the reference, do not
  edit expected JSON by hand.
- **Agents never fire `confirm` / `forbidden` events**, and the addon's own
  apps (`z2ui5_cl_agent_app_*`) are never agent-operable
  (`z2ui5_cl_agent_settings=>check_app`). Do not add an override.
- **Always the request's user.** No technical user, no `sy-uname` substitute,
  no custom authentication. Every session read filters by `sy-uname`.
- **A refused act changes nothing** - validate everything before the
  simulator sends; restore the pending values on any error.
- **Packages 03 and 04 stay thin** (one call into `z2ui5_cl_agent_mcp=>run`).
  abapGit pulls whole repositories, so users install the generated branches
  `standard` (main without 04) or `cloud` (main without 03) -
  `publish-branches.yaml` writes them; never commit to them.
- **Engine vs. apps.** Package 01 may use abap2UI5 internals
  (`z2ui5_cl_ajson`, `z2ui5_cl_ui5_util_context`, `z2ui5_cl_ui5_util_http`,
  `z2ui5_cl_ui5_user_exit`, the draft seam) - it is an engine, like the
  simulator. The apps in 02 name only the released abap2UI5 objects (`src/02`
  of the core) plus this addon's classes; the abap2UI5 linter's
  `non-released-api` rule checks them.
- **The 7.02 downport hoists table expressions** in front of the statement:
  never put `tab[ ... ]` inside an `IF`/`COND` guarded by another condition -
  read it ahead with `VALUE #( tab[ ... ] OPTIONAL )`.
- **The simulator builds the delta.** `send( )` hands every pending value of
  the action's model to `z2ui5_cl_frontend_simulator=>set_json( )` (the JSON
  of the value at its model path, `layer` = the action's model) and fires with
  `click( layer )` - the simulator applies the frontend's
  `buildDeltaFromPaths`. Never rebuild the delta here, and never send values
  as text. Only the event arguments are text (`sim_text`, `click( )` takes a
  string table).
- **A layer closed in the browser** (`@CLOSE_POPUP` / `@CLOSE_POPOVER`) is
  closed with the simulator's `close_layer( )` - never edit its `get_state( )`
  JSON.

## Code rules

- abaplint (`abaplint.jsonc`) is the style: upper-case keywords,
  `definitions_top`, no default keys, `omit_parameter_name`, types `ty_*`.
- Object names: classes `z2ui5_cl_agent*`, interfaces `z2ui5_if_agent*`,
  tables `z2ui5_t_ag_*` (≤ 16 characters); every object name ≤ 25 characters
  (namespace rename budget).
- abapGit file format (abap2UI5's `abap-check` skill): `.xml` with BOM, LF,
  one final newline, no trailing blanks, lines ≤ 255, no `'` in `<DESCRIPT>`;
  TABL sidecars only in the field shapes of exported tables (CHAR, INT4, STRG,
  data elements MANDT / TIMESTAMPL).
- `"#EC CI_SORTSEQ` on sequential reads (LOOP ... WHERE, READ TABLE ... WITH
  KEY, component-keyed table expressions), `##NO_HANDLER` on empty CATCH
  blocks, ABAP Doc (`"!`) inside chained `TYPES:` / `CONSTANTS:` directly above
  the declaration it documents.
- Views: `z2ui5_cl_ui5_view_builder`, the house chain layout
  (`npm run fmt:chains`), UI5 1.71 floor.

## Gates

```
npm ci
npm run lint && npm run lint:cloud && npm run check:abap2ui5
npm run unit        # ABAP Unit, transpiled - minutes on the first run
```

`ABAP_702` (CI): headless-frontend cloned into `src/zz_headless_frontend`,
`npm run downport`, `npx abaplint .github/abaplint/abap_702.jsonc` - on a copy,
never commit. Unit tests (`ABAP_UNIT`, `npm run unit`): transpiled runtime of
abap2UI5 (README, "Development"), every risk level; `ltcl_session` /
`ltcl_mcp` are `RISK LEVEL DANGEROUS` (they write the addon's tables and
restore them in `teardown`), the parser and snapshot tests are `HARMLESS`.

**Temporary:** until headless-frontend merges the session API (`resume`,
`get_state`, `get_layers`, `get_actions`, `set_json`, `close_layer`), `abaplint.jsonc`,
`abap_cloud.jsonc`, `ABAP_702.yaml`, `ABAP_UNIT.yaml` and
`.github/scripts/unit.mjs` resolve it from its branch
`claude/abap2ui5-project-brainstorm-nt7ifs`; switch them to `main` then.
Local runs can pre-fill `.abaplint-deps/` (git-ignored) - abaplint uses a
dependency folder that exists instead of cloning.
