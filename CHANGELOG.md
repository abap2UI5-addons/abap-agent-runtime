# Changelog

Every change a user of this addon can notice, newest first. A release moves
the entries under `## Unreleased` to a `## X.Y.Z - YYYY-MM-DD` heading and
keeps the empty `## Unreleased` heading standing above it (RELEASING.md); the
release workflow publishes that section as the release notes, and
`npm run check:version` / `npm run check:release` hold this file, `package.json`
and `z2ui5_if_agent_app=>version` together.

## Unreleased

**No release yet.** Everything below is on `main` (and in the generated
`standard` and `cloud` branches) and is what the first release, 0.1.0, will
carry. The addon is experimental: it is verified on the transpiled runtime
and by its lint targets, not yet on a system in production use, and its API -
`z2ui5_if_agent_app`, the MCP tool arguments, the snapshot extension
`policy`, the settings - may still change before 1.0 (README, "Status").

### The MCP endpoint

- An ABAP-native MCP server (JSON-RPC 2.0 over MCP Streamable HTTP, protocol
  version negotiated with the client) with the four app tools of the
  abap2UI5/mcp-server reference: `app_list`, `app_start`, `app_describe`,
  `app_act` - `z2ui5_cl_agent_mcp`, `z2ui5_cl_agent_session`.
- Two HTTP entries, one per platform: `z2ui5_cl_agent_http`
  (`if_http_extension`, ICF node `/sap/bc/z2ui5_agent`, package 03) for ABAP
  Standard 7.50+, `z2ui5_cl_agent_http_cloud` (`if_http_service_extension`,
  package 04) for ABAP Cloud. `publish-branches.yaml` generates the installable
  branches `standard` (without 04) and `cloud` (without 03) from every push to
  `main`.
- Every call runs as the SAP user of the HTTP request through the app's own
  `main( )` on the headless-frontend simulator; no technical user, no second
  API. Stateful apps are refused.

### The agent snapshot v1

- `z2ui5_cl_agent_snapshot` and `z2ui5_cl_agent_viewxml`: an ABAP port of the
  reference's `lib/snapshot.mjs` / `lib/viewxml.mjs` - fields, actions,
  tables (selection dialogs included), messages (toast, box, strip, value
  states, message table, `MessagePopover` / `MessageView` items), texts,
  unsupported, pending; byte-identical with the reference on its recorded
  sessions and 12 synthetic views (110 of 110 snapshots).
- The one extension: an action the app or the settings classify `confirm` or
  `forbidden` carries `"policy"`; the snapshot otherwise validates against
  abap2UI5/protocol `schema/snapshot.schema.json`.
- The act: values by field id or model path, events with their wire
  arguments (`$row`, `$source`, `$parameters`, expressions), row actions, the
  pick of a selection dialog, the browser's `@CLOSE_POPUP` / `@CLOSE_POPOVER`;
  the action is re-read after the values are applied, a disabled or renumbered
  action is refused, and a refused act changes nothing.

### Opt-in, policy, audit

- `z2ui5_if_agent_app`: an app opts in and classifies its events (`allowed`,
  `confirm`, `forbidden`) and its sensitive paths in `describe( )`;
  administrators allow or deny apps, classify events and mark fields in the
  settings app `z2ui5_cl_agent_app_admin` (`z2ui5_cl_agent_settings`, table
  `Z2UI5_T_AG_SET`). The endpoint is disabled after installation until an
  administrator enables it.
- Agents never fire `confirm` or `forbidden` events: a `confirm` event is
  refused with the handover URL of the prepared draft, so the user presses
  the button in the browser.
- Every call is logged (`z2ui5_cl_agent_audit`, `Z2UI5_T_AG_LOG`, the audit
  app `z2ui5_cl_agent_app_audit`), sensitive values masked; sessions in
  `Z2UI5_T_AG_SES`, MCP sessions in `Z2UI5_T_AG_MCP`, always filtered by the
  request's user.
- `z2ui5_cl_agent_demo`: an opted-in example app with the copilot, driven by
  the unit tests.

### AI at runtime

- A language model client: `z2ui5_if_agent_llm` (one chat call),
  `z2ui5_cl_agent_llm` (factory, settings, stop reasons, JSON, audit; test
  seams `set_double` / `set_http`), `z2ui5_cl_agent_llm_anthropic` (the
  Messages API, structured output), `z2ui5_cl_agent_llm_double` (canned
  answers for tests), the outbound POST per platform (`z2ui5_cl_agent_llm_std`
  with `cl_http_client`, `z2ui5_cl_agent_llm_cloud` with
  `cl_web_http_client_manager`). Configured in the admin app's *Language
  model* section; the API key is write-only.
- Generative UI (`z2ui5_cl_agent_genui`, `z2ui5_cl_agent_genui_demo`): a UI
  tree the model answers as structured output, validated node by node against
  the generated vocabulary `z2ui5_cl_agent_gen_vocab` (abap2UI5/protocol
  `profiles/portable-v1.json`, UI5 1.71 floor) and built with the view
  builder - the model never writes XML.
- The in-app copilot (`z2ui5_cl_agent_copilot`, `z2ui5_cl_agent_assist`): a
  popup grounded in the agent snapshot of the user's screen; its proposals
  go through `app_check` / `app_act` of the session - the same policy as an
  MCP agent, nothing runs without the user's click. Off by default, like the
  prompt in the audit and the sample rows.

### Tooling

- abaplint for ABAP Standard 7.50 (`abaplint.jsonc`), ABAP Cloud and the
  7.02 downport (`.github/abaplint/`), the abap2UI5 linter on the apps, the
  generated vocabulary check (`npm run genui:check`), and the ABAP Unit tests
  on abap2UI5's transpiled runtime (`npm run unit`, every risk level).
- `z2ui5_if_agent_app=>version` (`.abapgit.xml` `VERSION_CONSTANT`), this
  changelog, `RELEASING.md`, `npm run check:version` / `check:release` and the
  tag-only `release.yaml`.
