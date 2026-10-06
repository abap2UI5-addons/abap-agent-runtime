# abap2UI5 agent

**Every abap2UI5 app is agent-operable.** An ABAP-native
[MCP](https://modelcontextprotocol.io) endpoint inside your SAP system: AI
agents - Claude, Copilot Studio, Joule, any MCP client - read the screen of an
abap2UI5 app as structured data, fill its fields and fire its events. As the
real SAP user, through the app's own `main( )`, with the app's own validation
and authority checks. No Node, no browser, no screen scraping.

```
agent: app_start { "app": "z2ui5_cl_agent_demo" }
  <-   { "session": "8F3A...", "title": "Travel requests",
         "fields":  [ { "id": "f1", "path": "/NAME", "label": "Name", "kind": "text", "editable": true, ... }, ... ],
         "actions": [ { "id": "a5", "event": "ADD", "label": "Add", ... },
                      { "id": "a6", "event": "SUBMIT", "label": "Submit", "policy": "confirm", ... } ],
         "tables":  [ { "id": "t1", "path": "/T_REQUEST", "rowCount": 2, "rows": [ ... ], "selectionField": "SELKZ" } ], ... }

agent: app_act { "session": "8F3A...", "values": { "NAME": "Carol", "f2": "ROM" }, "event": "ADD" }
  <-   the next snapshot - the toast "Request 3 added", the table with three rows, a new session id

agent: app_act { "session": "...", "event": "SUBMIT" }
  <-   isError: "event SUBMIT needs a human - agents never fire it (the app classifies it confirm).
        Hand over to the user: open /sap/bc/z2ui5#/app/Z2UI5_CL_AGENT_DEMO/<draft> in the browser ..."
```

On top of the endpoint, the addon brings **AI at runtime** into the SAP
system - three features built on the same snapshot engine, settings and
audit log ([AI at runtime](#ai-at-runtime)):

- a **language model client** - the Claude Messages API out of the box, any
  provider of your own (SAP AI Core, Bedrock, a gateway) by class name;
- **generative UI** - an abap2UI5 view from a sentence, over data the app
  hands over, validated against a closed vocabulary before it is built;
- an **in-app copilot** - "ask this screen" for any opted-in app, grounded in
  the agent snapshot of the screen the user is on, with proposed steps the
  user confirms.

## Why

An abap2UI5 app is one ABAP class, and its whole conversation with the outside
world is one JSON request in, one JSON response out. The browser is not the
only thing that can hold up its end: the
[headless frontend simulator](https://github.com/abap2UI5/headless-frontend)
plays the browser side of that protocol inside ABAP. This addon puts an MCP
server in front of it, so an agent operates an app **semantically** - by model
path, label and event name - the way a user operates it in the browser, and
never past it:

- **No second API.** No OData service, no RAP action, no RPC wrapper per app.
  Whatever the app lets a user do on a screen, it lets an agent do - and
  nothing more.
- **The real user.** The endpoint runs as the SAP user of the HTTP request.
  There is no technical user and no privilege escalation: an agent can never do
  what its user could not do in the browser.
- **The app's own logic.** Every act is a real roundtrip through `main( )` -
  the same draft, the same validation, the same `AUTHORITY-CHECK`s.
- **Opt-in, classified, audited.** Only apps that opt in are reachable; events
  that need a human are never fired by an agent; every call is logged.

## Architecture

```
 MCP client (Claude Code, Copilot Studio, Joule, ...)
     |  POST /sap/bc/z2ui5_agent   JSON-RPC 2.0, MCP "Streamable HTTP"
     |  logon: Basic / OAuth / certificate / principal propagation
     v
 z2ui5_cl_agent_http        (ABAP Standard: if_http_extension, ICF node)
 z2ui5_cl_agent_http_cloud  (ABAP Cloud: if_http_service_extension)
     |
 z2ui5_cl_agent_mcp         initialize, ping, tools/list, tools/call; origin check, audit commit
     |
 z2ui5_cl_agent_session     app_list / app_start / app_describe / app_act
     |    |      \__ z2ui5_cl_agent_settings   opt-in, policy (allowed/confirm/forbidden), admins
     |    |      \__ z2ui5_cl_agent_audit      Z2UI5_T_AG_LOG
     |    |      \__ Z2UI5_T_AG_SES            per session: simulator state, client work,
     |    |                                    pending values, last snapshot (owner = sy-uname)
     |    v
     |  z2ui5_cl_agent_snapshot  layers + model -> agent snapshot v1 (+ the index an act needs)
     |  z2ui5_cl_agent_viewxml   view XML, bindings, expressions, event wires
     v
 z2ui5_cl_frontend_simulator  (abap2UI5/headless-frontend)  start / resume / set_json / click / close_layer
     v
 abap2UI5 core: z2ui5_cl_ui5_handler -> your app's main( ) -> draft (Z2UI5_T_01)
```

Every MCP call is one HTTP request. A session survives between requests as the
abap2UI5 **draft** (the backend state, owned by the user, expiring with the
draft expiry of your abap2UI5 configuration) plus a row in `Z2UI5_T_AG_SES`
(what the browser would remember: the view of every layer, the pending
values). `app_describe` answers from that row without a roundtrip; `app_act`
resumes the simulator from it.

## What an agent sees: agent snapshot v1

The snapshot is the shared contract of three implementations - the
[MCP server](https://github.com/abap2UI5/mcp-server) (Node, for development),
the VS Code extension, and this addon - specified in
[docs/agent-snapshot.md](https://github.com/abap2UI5/mcp-server/blob/main/docs/agent-snapshot.md)
of the MCP server: `fields` (id, model path, label, kind, value, required,
editable, choice values), `actions` (event, arguments with descriptors such as
`$row:NAME`, label, trigger, enabled, row scope), `tables` (columns, the first
rows, selection - the selection dialogs `SelectDialog` / `TableSelectDialog`
included), `messages` (toast, message box, MessageStrip, value states, the
app's message table, the items of a `MessagePopover` / `MessageView` with
their subtitle and description), `texts`, `unsupported`, and `pending`.

`z2ui5_cl_agent_snapshot` is an ABAP port of the reference implementation
(`lib/viewxml.mjs`, `lib/snapshot.mjs`, mcp-server commit `6bd3cc3`). Measured
against it on the 15 recorded sessions of the MCP server (every step, at 20
and at 2 rows) plus 12 synthetic views (selection dialogs, row event
arguments, message lists among them): **110 of 110 snapshots
byte-identical**. One deliberate extension: an
action the app or the settings classify `confirm` or `forbidden` carries
`"policy"` - without such a classification the output is the reference's,
key for key.

## Install

Requires, in this order, each with [abapGit](https://abapgit.org):

1. [abap2UI5](https://github.com/abap2UI5/abap2UI5) - the framework
2. [abap2UI5/headless-frontend](https://github.com/abap2UI5/headless-frontend) -
   the simulator this addon runs on (`resume( )`, `get_state( )`,
   `get_layers( )`, `set_json( )` and `close_layer( )`)
3. this repository - **from the branch of your platform**:

| Platform | Branch | Contains |
| --- | --- | --- |
| ABAP Standard (on-premise, S/4HANA, NetWeaver 7.50+) | `standard` | packages 01-03, the ICF node `/sap/bc/z2ui5_agent` |
| ABAP Cloud (BTP ABAP environment, S/4HANA Cloud Public Edition) | `cloud` | packages 01, 02, 04 |

`main` holds all four packages; abapGit pulls a whole repository, and the two
HTTP entry classes cannot both activate on one system (`if_http_extension`
does not exist in ABAP Cloud, `if_http_service_extension` not on 7.50), so
`.github/workflows/publish-branches.yaml` generates `standard` and `cloud` from
every push to `main`.

| Package | Objects |
| --- | --- |
| `src/01` engine | `z2ui5_if_agent_app` (opt-in), `z2ui5_cl_agent_viewxml`, `z2ui5_cl_agent_snapshot`, `z2ui5_cl_agent_session`, `z2ui5_cl_agent_settings`, `z2ui5_cl_agent_audit`, `z2ui5_cl_agent_mcp`; AI at runtime: `z2ui5_if_agent_llm`, `z2ui5_cx_agent_llm`, `z2ui5_if_agent_llm_http`, `z2ui5_cl_agent_llm` (factory, checks, audit), `z2ui5_cl_agent_llm_anthropic`, `z2ui5_cl_agent_llm_double`, `z2ui5_cl_agent_genui`, `z2ui5_cl_agent_gen_vocab` (generated), `z2ui5_cl_agent_assist` (copilot engine); tables `Z2UI5_T_AG_SET` (settings), `Z2UI5_T_AG_SES` (sessions), `Z2UI5_T_AG_LOG` (audit), `Z2UI5_T_AG_MCP` (MCP client sessions) |
| `src/02` apps | `z2ui5_cl_agent_app_admin` (settings), `z2ui5_cl_agent_app_audit` (audit log), `z2ui5_cl_agent_demo` (an opted-in example app, with the copilot), `z2ui5_cl_agent_genui_demo` (generative UI), `z2ui5_cl_agent_copilot` (the copilot popup) |
| `src/03` ABAP Standard entry | `z2ui5_cl_agent_http` and the ICF node `/sap/bc/z2ui5_agent`; `z2ui5_cl_agent_llm_std` (the language model's HTTP call, `cl_http_client`) |
| `src/04` ABAP Cloud entry | `z2ui5_cl_agent_http_cloud`; `z2ui5_cl_agent_llm_cloud` (the language model's HTTP call, `cl_web_http_client_manager`) |

## Enabling the endpoint

The endpoint is **disabled** after installation - every tool call is refused
until an administrator enables it.

1. **Add the first agent administrator** - once, in the system, as a developer:
   execute `z2ui5_cl_agent_settings=>admin_add( '<USER>' )` and commit, e.g.
   from a small console class (`if_oo_adt_classrun`, ABAP Cloud and S/4HANA) or
   SE24 → *Test* (ABAP Standard). Further administrators are added in the app.
2. **Open the settings app** `?app_start=z2ui5_cl_agent_app_admin` (through
   your usual abap2UI5 ICF node or launchpad tile) and switch *Agents may
   operate apps* on. Here you also allow or deny app classes, classify events,
   mark sensitive fields, set the handover page and clean up the audit log.
3. **Make the HTTP endpoint reachable:**
   - **ABAP Standard:** abapGit creates the ICF node `/sap/bc/z2ui5_agent`
     with the handler `Z2UI5_CL_AGENT_HTTP`. In transaction `SICF`, activate
     it and check its logon procedure (standard logon: Basic, SSO,
     certificates, as your system allows). If your abapGit version does not
     create the node, create it by hand: SICF → `default_host/sap/bc` → new
     sub-element `z2ui5_agent`, handler list `Z2UI5_CL_AGENT_HTTP`.
   - **ABAP Cloud** *(steps to verify on your system)*: in ADT create an *HTTP
     Service* (New → Other ABAP Repository Object → Connectivity → HTTP
     Service), e.g. `Z2UI5_AGENT`, and enter `Z2UI5_CL_AGENT_HTTP_CLOUD` as
     its handler class (ADT may generate its own handler class - then let its
     `handle_request` call `z2ui5_cl_agent_mcp=>run( req = request res =
     response )`). Expose it through a communication scenario (inbound,
     with the HTTP service), a communication system and a communication
     arrangement; the inbound user of the arrangement - or, better, the
     business user via principal propagation / OAuth - is the user the agent
     runs as. The HTTP service and its scenario are system-specific objects
     and are not shipped in this repository.
4. **Opt your apps in** (next section) - nothing is reachable before that.

## Opting an app in

```abap
CLASS zcl_sales_order_app DEFINITION PUBLIC.
  PUBLIC SECTION.
    INTERFACES z2ui5_if_app.
    INTERFACES z2ui5_if_agent_app.
    ...

  METHOD z2ui5_if_agent_app~describe.
    result-description = `Create and change sales orders`.
    result-t_event = VALUE #( ( event = `DELETE*` policy = z2ui5_if_agent_app=>cs_policy-forbidden )
                              ( event = `POST`    policy = z2ui5_if_agent_app=>cs_policy-confirm ) ).
    result-t_sensitive = VALUE #( ( `/MS_PARTNER/IBAN` ) ).
  ENDMETHOD.
```

An empty `describe( )` is fine: every event is allowed then. An administrator
can also allow classes that do not implement the interface (an `APP` rule with
`allow`, patterns like `ZCL_SALES_*` work), deny classes that do (`deny` wins),
and classify events on top of what the app says - the stricter verdict wins.
`z2ui5_cl_agent_demo` is a complete example.

## Connecting a client

The endpoint speaks MCP *Streamable HTTP* (revisions 2025-11-25, 2025-06-18,
2025-03-26 and 2024-11-05) with JSON responses; any client that supports
remote HTTP servers can connect. The URL is
`https://<host>:<port>/sap/bc/z2ui5_agent` (add `?sap-client=<client>` when
your logon needs it); on ABAP Cloud, the URL of your HTTP service.

**Claude Code**

```sh
claude mcp add --transport http abap2ui5-agent https://host:44300/sap/bc/z2ui5_agent \
  --header "Authorization: Basic $(printf '%s' 'USER:PASSWORD' | base64)"
```

Basic authentication is the simplest start; prefer a token: `--header
"Authorization: Bearer <token>"` with an OAuth access token your SAP system
accepts (OAuth 2.0 client in SOAUTH2 / an ABAP Cloud communication
arrangement). SAP systems do not implement MCP's own authorization discovery,
so pass the credential as a header rather than relying on the client's OAuth
flow. Then ask Claude to `app_list` and go.

**Microsoft Copilot Studio** *(to verify)*: add an MCP server tool to the
agent (Streamable HTTP transport) with the endpoint URL, and authenticate it
with basic or OAuth 2.0 credentials of the SAP user (or via the SAP
principal-propagation setup of your landscape).

**SAP Joule** *(to verify)*: connect the endpoint as an MCP server or as a
BTP destination-backed tool of a Joule agent (Joule Studio); the destination
carries the authentication (principal propagation recommended, so Joule acts
as the logged-on business user).

## The tools

| Tool | Input | Answer |
| --- | --- | --- |
| `app_list` | `filter?` | `{ count, apps: [{ app, description, source }], hint }` - source `interface` or `setting` |
| `app_start` | `app`, `values?`, `max_rows?` (0-200, default 20) | snapshot |
| `app_describe` | `session`, `max_rows?` | snapshot from the stored session - no roundtrip |
| `app_act` | `session`, `values?`, `event?`, `args?`, `row?`, `max_rows?` | the next snapshot |

The semantics are the specification's: `values` keys address a field by id,
model path or name, or a table cell as `"<table path or id>/<row>/<COLUMN>"`
(selecting a row is setting its `selectionField`); `event` is an event name or
an action id; `row` (0-based) fills the row arguments of a row action; `args`
(positional, `null` = let the client fill it) supplies what only a browser
computes - except the `${$parameters>/...}` arguments of row events, which
are filled from the row (`listItem`, `rowIndex`, `rowContext`, a row action
item's `row`, and the call shapes views write on them:
`.getBindingContext().getProperty('X')`, `.getPath()`, `.getCells()[n].getText()`,
`.getTitle()`, ...; a `[n]` path segment is `null`, as in the browser's
JSONModel). Without `event` the values stay **pending**.

**Value helps: the pick.** A `SelectDialog` / `TableSelectDialog` is a table
of its layer, and its `confirm` is a row action: `app_act({ event: <the
confirm>, row: 2 })` picks row 2 as a click in the browser does - the row's
`selectionField` becomes `true` (single select: every other selected row's
`false`), the edits travel with the confirm as the model delta, and the
confirm's `selectedItem` / `selectedItems` / `selectedContexts` are the
selected rows. A multi-select dialog confirms what is ticked (tick rows
through `values`, `row` adds one); a single-select dialog with nothing
selected refuses an act without `row`. `@CLOSE_POPUP` /
`@CLOSE_POPOVER` close a dialog locally, as the browser does. Action ids
follow the document order, so values that show or hide a control can renumber
them: an act whose values make its action id name another event, or hide its
action, is refused - fill the values without an event first, then fire it from
the next snapshot.
Every refusal is a tool result with `isError: true` and a sentence naming what
was wrong and what is allowed - and a refused act sends nothing and changes
nothing.

## Security model

- **Disabled by default**; an administrator switches the endpoint on.
- **Opt-in per app**: only classes implementing `z2ui5_if_agent_app`, or
  allowed by an administrator, can be listed or started. The addon's own apps
  (`z2ui5_cl_agent_app_*`) are never agent-operable, whatever the settings say -
  every event of theirs is `forbidden`, also when an operable app navigates there.
- **The real SAP user, always.** Authentication is the logon of the HTTP
  request (Basic, OAuth, certificates, principal propagation) - nothing custom,
  no technical user, no user switch. The app runs as that user, with its
  authority checks.
- **Events are classified** `allowed`, `confirm` or `forbidden` by the app
  (`describe( )`) and by the settings; the stricter wins. **Agents never fire
  a `confirm` or `forbidden` event.** A `confirm` refusal hands the screen over
  to a human (below).
- **Sessions belong to their user**: every read filters by `sy-uname`, the
  draft service binds drafts to their creator, and a session expires with its
  draft. Only the current draft id of a session is accepted.
- **Audit log** (`Z2UI5_T_AG_LOG`, app `z2ui5_cl_agent_app_audit`): timestamp,
  user, session, app, operation, event, arguments (truncated; values masked for
  password inputs - and any field on the model path of one - and for fields
  the app or the settings mark sensitive),
  outcome, error text, MCP client name and version. Users see their own
  entries, administrators everybody's. Settings changes are logged too.
- **AI at runtime** is off by default (no key, no destination, copilot
  off); its model calls are audited without prompt contents, its views are
  validated against a closed vocabulary, its proposals against the same
  policy as every agent - see [AI at runtime](#ai-at-runtime).
- **Browser-side abuse is refused**: a request with an `Origin` (or `Referer`)
  of another host gets 403 - the check abap2UI5 applies to its own POSTs - and
  only `Content-Type: application/json` is accepted, so a web page cannot drive
  the endpoint with the user's SSO cookies.

### The handover flow

When an agent tries an event classified `confirm`, `app_act` refuses and answers
with the abap2UI5 URL of the session's draft, e.g.
`/sap/bc/z2ui5#/app/ZCL_SALES_ORDER_APP/8F3A...` (the base is the *handover
page* of the settings, default `/sap/bc/z2ui5`). The agent passes it to its
user, who opens it in the browser: abap2UI5 restores the very state the agent
prepared - same user, same draft - and the human checks it and presses the
button. Values the agent sent with earlier events are part of the draft;
values still pending are listed in the refusal, so the agent can send them
first with an allowed event or tell the user what to enter. A dialog that was
open is not part of the draft; the app shows its main view.

## Limits

What the snapshot cannot see is listed in the specification
([What the snapshot cannot see](https://github.com/abap2UI5/mcp-server/blob/main/docs/agent-snapshot.md#what-the-snapshot-cannot-see-yet)):
formatters and composite bindings, client-only state (an IconTabBar's open
tab, a selection without a `selected` binding), named models, custom controls,
frontend actions (`.eF` wires, `OPEN_NEW_TAB`, ... - listed, never
performed), nested tables, file uploads. On top of that, in this addon:

- **Value helps work, message popovers are read.** An F4 help built as a
  `SelectDialog` / `TableSelectDialog` (abap2UI5's `z2ui5_cl_pop_to_select`,
  the popups addon's `z2ui5_cl_popup_to_select`) is operated with the pick
  above. The items of a `MessagePopover` are messages
  (`source: "popover"`) even while the popover itself only opens in the
  browser (a frontend action this addon does not perform); a `MessageView`'s
  are `source: "messageview"`. At most 50 per list. A control-valued event
  parameter outside the row events (a MessagePopover's `${$parameters>/item}`)
  is marshalled by the browser with all its properties - pass what the app
  reads in `args`.
- **Stateful apps** (`client->set_session_stateful( )`) cannot be operated: a
  stateful session lives in one HTTP request, an MCP call is one request.
  `app_start` refuses them; an app that switches mid-session ends the session.
  What such an app - or an app whose `main( )` failed - left open in the LUW
  is rolled back, never committed with the call's audit entry.
- **Event arguments travel as text.** Model values go out typed, as the
  browser sends them: every pending value is handed to the simulator's
  `set_json( )` at its model path - a boolean as `true` / `false`, a
  `multichoice` as an array of keys, a number as a number - and the simulator
  builds the frontend's delta from them (a table cell as a row delta,
  everything else, a structure that holds a table included, as the whole
  top-level attribute). The positional event arguments (`args`, the row
  arguments of a row action) are still text, because the simulator's
  `click( )` takes them as a string table: a boolean as `X` / space, an object
  or array as its JSON.
- **`app_list` reads the class directory** (SEOMETAREL on ABAP Standard, XCO
  on ABAP Cloud) through the core's utility. Where it cannot be read it lists
  only what the settings name; `app_start` works either way.
- **One snapshot shape for every client.** Labels, texts and messages are as
  the app wrote them - in its logon language.

## AI at runtime

Three features, all inside the SAP system, all on ABAP Standard, ABAP Cloud
and the 7.02 downport, all off until an agent administrator configures a
language model. Nothing here gives a model more than the user has: the
model never runs ABAP or SQL, never picks data, and never acts without the
user's click.

```
 app (genui) / copilot popup
     |
 z2ui5_cl_agent_genui         z2ui5_cl_agent_assist  ->  z2ui5_cl_agent_session (mode copilot)
     \________________   ________/                         snapshot, app_check, app_act, policy
                      v v
 z2ui5_cl_agent_llm   factory + wrapper: settings, stop reasons, JSON, audit (Z2UI5_T_AG_LOG)
     |
 z2ui5_if_agent_llm   z2ui5_cl_agent_llm_anthropic | your class (AI Core, Bedrock, ...) | the double
     |
 z2ui5_if_agent_llm_http   z2ui5_cl_agent_llm_std (03, cl_http_client) | z2ui5_cl_agent_llm_cloud (04)
```

### Setting up the language model

In `z2ui5_cl_agent_app_admin`, section *Language model* (agent
administrators only - every change is audited):

| Setting | |
| --- | --- |
| API key | sent as `x-api-key`. Write-only: the app shows *set* / *not set*, never the key; *Remove key* deletes it. A typed key is cleared after every event, so it never stays in the app's draft - only *Save* stores it. Stored in `Z2UI5_T_AG_SET` (kind `LLM`) - protect the table like any credential store, or leave the key empty and let the destination authenticate |
| Destination | **ABAP Standard:** an SM59 destination of type G (host `api.anthropic.com`, port 443, SSL active, client identity `ANONYM` or `DFAULT`, proxy if your landscape needs one); the URL field is then the path (default `/v1/messages`). **ABAP Cloud:** a communication arrangement as `SCENARIO/SERVICE_ID` (or `SCENARIO/SERVICE_ID/COMM_SYSTEM`) - a customer communication scenario with an outbound HTTP service whose system points at `https://api.anthropic.com` (*to verify on your system*) |
| URL | without a destination the full URL, default `https://api.anthropic.com/v1/messages` (ABAP Standard: the server certificate chain must be in the `ANONYM` PSE, `STRUST`; ABAP Cloud: `cl_http_destination_provider=>create_by_url`) |
| Model / effort | default `claude-opus-5-5` / `low` (thinking is always on for this model and is never configured; `output_config.effort` is the only control - `low` keeps generated views and answers interactive) |
| Max tokens / timeout | default 16000 / 300 s (never below 120 s) |
| Refusal fallback / beta header | default on / `server-side-fallback-2026-07-01`: the request carries `"fallbacks":"default"` and the beta header, so a refusal is retried server-side on a fallback model |
| Provider class | default `z2ui5_cl_agent_llm_anthropic`; a class of your own implementing `z2ui5_if_agent_llm` (public constructor without mandatory parameters) routes every call through SAP AI Core / Generative AI Hub, Bedrock or a gateway - the checks, the JSON parsing and the audit stay the addon's |
| Audit keeps prompts and answers | default off (below) |
| Generative UI: sample rows / repair round | default off / on |
| In-app copilot / may propose actions | default off / off |

*Test call* sends one short message and shows the model, the answer and the
tokens. The request is the Messages API, non-streaming:
`POST /v1/messages` with `content-type: application/json`, `x-api-key`,
`anthropic-version: 2023-06-01` (+ `anthropic-beta` for the fallback), body
`{"model","max_tokens","system","messages","output_config":{"effort","format":{"type":"json_schema","schema"}},"fallbacks":"default"}`.
The answer is the first `text` block; `stop_reason` is checked first - a
`refusal`, a `max_tokens` and a `model_context_window_exceeded` answer raise
`z2ui5_cx_agent_llm` and are never parsed. HTTP 408, 429, 5xx and 529 raise
it with `retryable = abap_true`, other errors without; the addon does not
retry on its own.

**Your own provider:**

```abap
CLASS zcl_llm_ai_core DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    INTERFACES z2ui5_if_agent_llm.
ENDCLASS.
CLASS zcl_llm_ai_core IMPLEMENTATION.
  METHOD z2ui5_if_agent_llm~chat.
    " is_request-system, -t_message, -schema (JSON schema text, or empty), -effort, -max_tokens
    " -> call your service; answer text (the JSON for a schema), stop_reason, usage
    " -> RAISE EXCEPTION TYPE z2ui5_cx_agent_llm EXPORTING kind = `http` http_status = ... retryable = ...
  ENDMETHOD.
ENDCLASS.
```

and enter `ZCL_LLM_AI_CORE` as the provider class. Unit tests use
`z2ui5_cl_agent_llm_double` (queued canned answers, recorded requests) via
`z2ui5_cl_agent_llm=>set_double( )` - no test calls a model.

### Privacy and audit

- **Every call is audited** in `Z2UI5_T_AG_LOG` (written in the caller's
  LUW - the endpoint, `generate( )` and the copilot commit it; operation `llm`, visible in
  `z2ui5_cl_agent_app_audit`): user, app, purpose (`genui`, `copilot`,
  `test`), provider, model, effort, stop reason, input and output tokens,
  duration in ms, outcome, the error text. **No prompt and no answer** -
  unless an administrator switches *Audit keeps prompts and answers* on
  (then both are kept, cut to 2000 characters like every audit entry).
- **Generative UI** sends the names, types and labels of the fields the app
  hands over - **no data**; a few sample rows (3) only with *sample rows* on.
- **The copilot** sends the agent snapshot of the screen - the values the
  user sees, so a question about them can be answered - with every password
  input (and every other field on its model path) and every sensitive field
  (the app's `t_sensitive`, the settings' `SENSITIVE` rules) masked as `***`,
  in fields and in table columns, and
  without the actions agents may never fire. It never proposes to fill a
  masked field.
- The data goes to the provider you configure; with the shipped one, to the
  Claude API under your organisation's agreement with Anthropic.

### Generative UI

The app decides **what** data; the model decides only **how** to show it.

```abap
DATA(genui) = z2ui5_cl_agent_genui=>create( client = client app = `ZCL_MY_APP`
    )->add_table( name = `flights` val = t_flight description = `flights of the week`
                  t_label = VALUE #( ( field = `CARRID` label = `Airline` ) )
    )->add_structure( name = `header` val = ms_header
    )->add_event( event = `ROW_SELECT` description = `the user picks a flight`
                  t_arg = VALUE #( ( `CARRID` ) ( `CONNID` ) ) ).
DATA(result) = genui->generate( `the open flights as a table grouped by carrier` ).
IF result-ok = abap_true.
  client->popup_display( result-xml_popup ).   " or view_display( result-xml )
ELSE.
  " result-t_issue: why it was rejected, result-t_note: the report
ENDIF.
```

`val` is the app's attribute itself - the class binds it with
`client->_bind( )`, so the generated view binds to the app's model like a
hand-written one and its events arrive in the app's `main( )`. abap2UI5
rolls back what an app's `main( )` leaves uncommitted, so `generate( )`
commits the LUW after its model calls (their audit entries); pass `commit =
abap_false` when your LUW holds work of its own and commit it yourself. The model
answers a **UI tree as structured output** (a JSON schema, flat list of nodes -
control, parent, aggregation, properties as literals or field bindings, an
optional list binding, events), never XML, ABAP or SQL. The class validates
the tree and builds the XML itself with `z2ui5_cl_ui5_view_builder`:

| Checked | Rejected with a reason |
| --- | --- |
| controls | anything outside the **portable view profile v1** of the abap2UI5 protocol (65 controls, `z2ui5_cl_agent_gen_vocab`); also `sap.ui.core.HTML`, `Shell`, `Dialog`, `Popover`, `CustomData` and layout data |
| tree | no or two roots, a missing parent, a cycle, a duplicate id, more than 200 nodes |
| aggregations | an aggregation the parent does not have, a child of the wrong type, two children in a single aggregation |
| properties | a property the control does not have at the UI5 1.71 floor (members introduced later are not in the vocabulary); a literal of the wrong type - enum values as listed, `true`/`false`, integers, numbers, CSS sizes, icons only as `sap-icon://...`, CSS classes only the `sapUi*Margin/Padding` helpers; a binding on a property that takes none (URIs, ids) |
| bindings | a field that is not in the data handed over; relative bindings only inside the row template of a list bound to a table, absolute ones only to a structure; formats `integer` and `decimal` (typed bindings) and nothing else - no expressions, no formatters |
| lists | a list bound to a structure or an unknown dataset, sorting or grouping by an unknown field, not exactly one row template, a list inside a template |
| events | an event the control does not have, an app event not in the app's list, an argument the app did not allow for it |
| texts | never rejected - always rendered as literals (`t` of the builder: `{` and `\` escaped, XML escaped), so `<script>`, `"/><core:HTML ...>` or `{/OTHER/PATH}` in a text show as text |

Ids, custom data, frontend actions (`.eF`), custom controls and expression
bindings do not exist in the tree format at all. With *repair round* on (the
default) a rejected tree goes back to the model once with the reasons; the
second answer is validated the same way. `render( json )` validates and builds
a tree an app stored. The vocabulary is generated: `.github/genui/portable-v1.json`
is a pinned copy of `profiles/portable-v1.json` of
[abap2UI5/protocol](https://github.com/abap2UI5/protocol), typed with the UI5
metadata of the abap2UI5 linter; `npm run genui:check` fails when
`z2ui5_cl_agent_gen_vocab` is not what the pins generate, `npm run
genui:drift` when the pin is no longer upstream's (the `genui-vocab`
workflow runs both, weekly as well).

`z2ui5_cl_agent_genui_demo` is the example: flights in an internal table, a
sentence, *Generate*, the view in a popup, the validation report below; its
view may fire `ROW_SELECT` (carrier, connection, date) and `REFRESH`.

**Limits:** no filtering in the view (a filter control can fire an app event
that takes its value); no nested lists, no NEST slots, no formatters beyond
the two number formats; enum values and icon names are checked against the
1.71 floor and the icon URI pattern, not against the icon font; the model
can still build a poor layout - the validation guarantees safety, not taste.

### In-app copilot

"Ask this screen": a popup in any opted-in abap2UI5 app that answers from
what the screen shows and can do steps the user confirms. Two lines in the
app:

```abap
METHOD z2ui5_if_app~main.
  IF z2ui5_cl_agent_copilot=>attach( client ) = abap_true.
    RETURN.
  ENDIF.
  ...

" in the view, e.g. the page's headerContent:
)->tag( `Button`
    )->a( n = `icon`  v = `sap-icon://discussion`
    )->a( n = `press` v = client->_event( z2ui5_cl_agent_copilot=>c_event ) )
```

The app must be enabled for agents (it implements `z2ui5_if_agent_app` or an
administrator allows it) and the copilot switched on. `z2ui5_cl_agent_demo`
carries both lines.

**How it works.** The press is an ordinary event of the app; `attach( )`
answers it with `nav_app_call( )` of `z2ui5_cl_agent_copilot`, a popup app on
top of the screen. That roundtrip saved the caller's draft - with the values
the user had typed, which travel with every event - and the copilot reaches
it as `get( )-s_draft-id_prev_app`. `z2ui5_cl_agent_assist` copies that draft
and continues the copy headlessly (`z2ui5_cl_agent_session=>app_attach`: the
headless frontend's restore roundtrip, the app's `main( )` runs
`check_on_navigated( )`), so the copilot has the **agent snapshot v1 of the
very screen** - the same snapshot an MCP agent gets, the same session. The
user's own draft is never touched.

Each question sends the masked snapshot, the app's `describe( )` description
and the conversation so far; the model answers as structured output
`{answer, found, proposal}` and is told to say when the screen does not hold
the answer. A **proposal** (fields to fill, an action to press - only with
*may propose actions* on) is validated before it is shown:

- an action the screen does not have, a **forbidden** action (which the model
  never even sees), or a password / sensitive field: not offered, with the
  reason;
- everything else exactly as the MCP endpoint's `app_act` validates it -
  `app_check( )` runs the same code without sending (unknown field, a field
  that is not editable, a choice outside its values, a wrong type). The
  values of a proposal are text: a `multichoice` names its keys separated by
  commas, and the copilot hands them over as the array of keys `app_act`
  takes;
- nothing runs until the user clicks *Do it* / *Fill in*. An **allowed**
  action then runs through the app's own `main( )` in the session
  (`app_act`); for an action classified **confirm** the copilot only fills
  the fields and tells the user to press the button on the screen - agents
  never fire `confirm` or `forbidden` events, the copilot included.

*Close* returns to the app (`nav_app_leave`): unchanged when nothing ran;
otherwise in the state the confirmed steps left it (the session's draft,
`client->get_app( )`), with values that were only filled written into the
app's public attributes by their model path - a date (`D`) taken as
`YYYY-MM-DD` or `YYYYMMDD`, a time (`T`) as `HH:MM`, `HH:MM:SS` or `HHMMSS`;
a value that is no day of the calendar or time of the clock is not written,
the user enters it - the copilot names such a value when it fills it. The
copilot app itself is never agent-operable, and the copilot event is
classified forbidden on every screen - an agent cannot open it.

**Why this integration.** abap2UI5 routes every event to the app's own
`main( )` (only `nav_app_leave` is framework-handled), so an app has to hand
the press over - one line. The view XML of the current screen exists only in
the browser and in the app's `view_display( )` call; the released API offers
no getter for it, and reading it from the frontend would let the browser
dictate what the validation trusts. Re-rendering a copy of the draft through
the headless frontend gives the server's own view and model, reuses the
snapshot, the policy and the act validation unchanged, and needs only
released API in the apps (`nav_app_call`, `get( )`, `get_app`,
`nav_app_leave`). Rejected alternatives: a frontend-supplied snapshot (not
trustworthy), a recording `z2ui5_if_client` implementation (breaks with every
new client method), a monitor exit (one per system, no view).

**Limits:** a popup the app had open when the copilot was pressed is not
part of its draft, so the copilot sees the main view (as the handover does);
the restore roundtrip runs the app's `check_on_navigated( )` branch - an app
that does more than display there does it once more on the copy; stateful
apps cannot be continued; each question is one model call with the whole
snapshot (20 rows per table); copies of drafts expire with the abap2UI5 draft
expiry.

## Development

```sh
npm ci
npm run lint            # abaplint, ABAP Standard 7.50, the strict rule set
npm run lint:cloud      # ABAP Cloud
npm run check:abap2ui5  # the abap2UI5 linter on the apps (package 02)
npm run genui:check     # z2ui5_cl_agent_gen_vocab is what the pinned profile generates
npm run unit            # the ABAP Unit tests on abap2UI5's transpiled runtime
```

The ABAP_702 workflow downports `src/` - together with headless-frontend,
cloned into `src/zz_headless_frontend` - and lints the result as 7.02 (CI only,
never commit downported source).

**Unit tests.** `npm run unit` runs the `Z2UI5_CL_AGENT*` tests - all of them,
the `DANGEROUS` ones included - on the transpiled runtime abap2UI5 uses for its
own suite (SQLite behind the database statements); `UNIT_FILTER=ltcl_session
npm run unit` runs only those whose `OBJECT: class->method` contains the
text. `.github/scripts/unit.mjs` is the whole recipe, and the `ABAP_UNIT`
workflow runs the same script on every push and pull request: checkouts of
abap2UI5 `main` and headless-frontend in `.unit/` (git-ignored; cloned on the
first run, refreshed on every later one), `npm ci` in abap2UI5,
headless-frontend's `src/` and this repository's `src/01` and `src/02` copied
in as extra packages, `npm run downport && npm run auto_transpile`, then the
generated tests - each one printed, exit code 1 on any failure or when none
ran. The first run takes a few minutes. See [AGENTS.md](AGENTS.md).

## License

MIT - see [LICENSE](LICENSE).
