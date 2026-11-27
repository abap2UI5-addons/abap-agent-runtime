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

### Namespace rename

- `npm run rename` and the manual workflow `build-rename`, abap2UI5's own
  mechanism: every object - and every reference to abap2UI5 and to
  headless-frontend - renamed to a customer name or a namespace, pushed as
  `rename_<name>`. This addon allows names of up to 9 characters: the ICF
  node `z2ui5_agent` has to stay within 15.
- The Messages API client `z2ui5_cl_agent_llm_anthropic` is
  `z2ui5_cl_agent_llm_claude` (25 characters at most for the rename); the
  settings' default provider follows. A provider class name stored in the
  settings must be changed by hand.
- Uses headless-frontend's shortened names (`z2ui5_cl_frontend_sim`).
- In a renamed installation the addon's own apps and the copilot stay out of
  reach of agents: the guard named them by the literal pattern
  `Z2UI5_CL_AGENT_APP_*`, which matched nothing there, so an APP allow rule
  such as `*` made the settings app agent-operable. It derives the prefix
  from its own class name now.
- `build-rename` refuses a name of 10 characters before it starts, and its
  input says 9 - it promised 10, and the rename then failed.

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
- An MCP session unused for a day is ended at its next request - the client
  gets the 404 of the Streamable HTTP contract and starts a new one. Until
  now the session was refreshed instead unless an initialize had deleted it.
- A snapshot cut to fit one answer no longer says that `app_describe`
  `max_rows` pages a table (it has no offset): as the reference, the note
  says that `rowCount` counts all rows and `app_act` reaches a cell of a later
  row by its path, and that a snapshot with nothing left to cut is still too
  large, instead of an empty list.

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
- A text clipped in the middle of an emoji loses the whole emoji, not
  half of it (README, "What an agent sees").
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
  `Z2UI5_T_17`). The endpoint is disabled after installation until an
  administrator enables it.
- Agents never fire `confirm` or `forbidden` events: a `confirm` event is
  refused with the handover URL of the prepared draft, so the user presses
  the button in the browser.
- An app an agent may not start is not operable either: every event of an
  app without opt-in that an operable app calls (`nav_app_call`), or whose
  allow rule is removed while a session runs, is `forbidden` - the opt-in was
  checked at `app_start` / `app_attach` only, and such an app's events were
  `allowed` by default.
- Every call is logged (`z2ui5_cl_agent_audit`, `Z2UI5_T_14`, the audit
  app `z2ui5_cl_agent_app_audit`), sensitive values masked - event arguments
  that read a password or sensitive field, or come from a password input,
  too (they were logged as the agent sent them); sessions in
  `Z2UI5_T_16`, MCP sessions in `Z2UI5_T_15`, always filtered by the
  request's user.
- A refusal no longer repeats the value of a password or sensitive field
  (`... holds a number - *** is none`): its text lands in the audit log as it
  is, and only the arguments were masked.
- The audit log housekeeping of the settings app also deletes the expired
  agent sessions (`z2ui5_cl_agent_session=>cleanup( )`): their snapshots and
  simulator state - the app's data, password values included - stayed in
  `Z2UI5_T_16` until the next agent call.
- `z2ui5_cl_agent_demo`: an opted-in example app with the copilot, driven by
  the unit tests.

### AI at runtime

- A language model client: `z2ui5_if_agent_llm` (one chat call),
  `z2ui5_cl_agent_llm` (factory, settings, stop reasons, JSON, audit; test
  seams `set_double` / `set_http`), `z2ui5_cl_agent_llm_claude` (the
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
- A generated view never sets `enableFormattedText`: a `MessageStrip` with
  formatted text rendered the model's or the data's text as HTML, links
  included.
- The in-app copilot (`z2ui5_cl_agent_copilot`, `z2ui5_cl_agent_assist`): a
  popup grounded in the agent snapshot of the user's screen; its proposals
  go through `app_check` / `app_act` of the session - the same policy as an
  MCP agent, nothing runs without the user's click. Off by default, like the
  prompt in the audit and the sample rows.
- A copilot proposal names the action an agent's `app_act` without a row
  fires - a screen action before a row action of the same event; the copilot
  took the first enabled one in the view, a row's. The action and the
  protected fields are resolved by the snapshot for both
  (`find_action( )`, `resolve_target( )`, `is_protected( )`).
- The copilot sends the model the conversation it keeps itself, not the
  list bound to the popup: an "assistant" turn written into that list in the
  browser reached the model as the copilot's own words.

### Tooling

- abaplint for ABAP Standard 7.50 (`abaplint.jsonc`), ABAP Cloud and the
  7.02 downport (`.github/abaplint/`), the abap2UI5 linter on the apps, the
  generated vocabulary check (`npm run genui:check`), and the ABAP Unit tests
  on abap2UI5's transpiled runtime (`npm run unit`, every risk level).
- The unit tests run on the test seam `z2ui5_cl_agent_settings=>set_test_buffer( )`:
  they no longer delete, override and commit the settings of the system they
  run in (the endpoint switched on, rules, administrators and the API key
  gone while they ran - and for good when a run aborted).
- `z2ui5_if_agent_app=>version` (`.abapgit.xml` `VERSION_CONSTANT`), this
  changelog, `RELEASING.md`, `npm run check:version` / `check:release` and the
  tag-only `release.yaml`.
- `release.yaml` and `publish-branches.yaml` keep no write token in
  `.git/config` while `npm ci` and the checks run: the release creates the
  branch tags through the API, `publish-branches` passes the push its token
  for that one command.
- `publish-branches.yaml` runs `npm ci` and abaplint in a job with a
  read-only token, and pushes `standard` / `cloud` from a second job that
  runs no npm: in one job, the installed packages could tamper with the push
  step through `$GITHUB_ENV`, `$GITHUB_PATH` or the files it runs. Neither
  branch moves unless both lint.
