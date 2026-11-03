---
layout: home

hero:
  name: "ABAP Agent Runtime"
  text: "An MCP endpoint in ABAP: AI agents operate your apps as the real user."
  image:
    src: /favicon.png
    alt: abap2UI5
  actions:
    - theme: brand
      text: Get started
      link: /guide
    - theme: alt
      text: GitHub
      link: https://github.com/abap2UI5-addons/abap-agent-runtime
    - theme: alt
      text: All addons
      link: https://abap2ui5-addons.github.io/

features:
  - title: "MCP Streamable HTTP endpoint with the tools app_list, app_start, app_describe and app_act"
  - title: "Agent snapshot v1 of the screen: fields, actions, tables, messages, pending values"
  - title: "Runs as the real SAP user through the app's own main( ), no technical user"
  - title: "Opt-in per app, events classified allowed/confirm/forbidden, handover to a human"
  - title: "Audit log of every call, settings app and audit app included"
  - title: "Language model client (Claude API or own provider), generative UI, in-app copilot"
  - title: "Disabled after installation until an administrator switches it on"
---

## What it does

An MCP server inside the SAP system, built on the headless frontend simulator, through which AI agents such as Claude, Copilot Studio or Joule read the screen of an abap2UI5 app as structured data, fill its fields and fire its events. Every call runs as the SAP user of the HTTP request through the app's own main( ), with its validation and authority checks; no second API per app is needed. Apps opt in with the interface z2ui5_if_agent_app, events can be classified allowed, confirm or forbidden, and every call is audited. On top of the endpoint it brings a language model client, generative UI and an in-app copilot, all off by default.

## Requirements

- abap2UI5 (installed first)
- abap2UI5/headless-frontend (installed before this addon)
- ABAP Cloud (BTP ABAP environment, S/4HANA Cloud Public Edition) or ABAP Standard 7.50 or higher
- ABAP 7.02 downport is lint-only in CI, not run on a 7.02 system

## Installation

With [abapGit](https://abapgit.org), from [the repository](https://github.com/abap2UI5-addons/abap-agent-runtime):

- Install in this order with abapGit: abap2UI5, abap2UI5/headless-frontend, then this repository
- Pull from the branch of your platform: standard (ABAP Standard, packages 01-03 and ICF node /sap/bc/z2ui5_agent) or cloud (ABAP Cloud, packages 01, 02, 04); main holds all four packages and does not activate on one system
- Not yet in a release; a release will tag the branches as X.Y.Z-standard and X.Y.Z-cloud
- After installation the endpoint is disabled: add the first agent administrator with z2ui5_cl_agent_settings=&gt;admin_add( '&lt;USER&gt;' ) and commit
- Open the settings app ?app_start=z2ui5_cl_agent_app_admin and switch 'Agents may operate apps' on
- ABAP Standard: activate the ICF node /sap/bc/z2ui5_agent in SICF; ABAP Cloud: create an HTTP service with handler class Z2UI5_CL_AGENT_HTTP_CLOUD and expose it through a communication arrangement (to verify)
- Opt your apps in with the interface z2ui5_if_agent_app; z2ui5_cl_agent_demo is a complete example

The [Guide](/guide) has every step.

## A first app

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

## Links

- [abap2UI5/headless-frontend](https://github.com/abap2UI5/headless-frontend)
- [abap2UI5/mcp-server (reference implementation)](https://github.com/abap2UI5/mcp-server)
- [Agent snapshot specification](https://github.com/abap2UI5/mcp-server/blob/main/docs/agent-snapshot.md)
- [abap2UI5/protocol snapshot schema](https://github.com/abap2UI5/protocol/blob/main/schema/snapshot.schema.json)
- [Model Context Protocol](https://modelcontextprotocol.io)
- [abap2UI5](https://github.com/abap2UI5/abap2UI5)
- [The repository](https://github.com/abap2UI5-addons/abap-agent-runtime) - issues and pull requests welcome
