# Contributing

Every abap2UI5 app is agent-operable - an ABAP-native MCP endpoint.

## Before you open a pull request

Run what CI runs:

```sh
npm ci
npm run check
```

`npm run check` is the set of steps the workflows run on a pull request, so a
green run locally is a green run there.

## What the gates are

| Gate | What it proves |
| --- | --- |
| `npm run lint`, `npm run lint:cloud` | abaplint for Standard ABAP 7.50 and ABAP Cloud |
| `npm run check:abap2ui5` | the [abap2UI5-linter](https://github.com/abap2UI5/linter) over the app classes and their views |
| `npm run genui:check` | the generated UI vocabulary matches its source |
| `npm run check:version` | package.json, the interface's version and CHANGELOG.md agree |
| `npm run rename` | the namespace rename still works |
| `npm run unit` | the ABAP Unit tests on abap2UI5's transpiled runtime (not part of `check`: it builds a checkout of abap2UI5) |

AGENTS.md has the snapshot contract with abap2UI5/mcp-server and the security rules - read them before touching `src/01`.

## Conventions

English for code, comments, commit messages and pull requests. Commit subjects
are written in the imperative and describe the outcome, not the mechanics. One
topic per pull request. The wider rules the whole ecosystem follows live in
[abap2UI5's CONVENTIONS.md](https://github.com/abap2UI5/abap2UI5/blob/main/.github/shared/CONVENTIONS.md).
