# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A grab-bag of small MATLAB / Simulink helper tools for MBD work. It is **not** a
library or a toolbox — it is a collection of independent snippets that engineers
copy one at a time straight from the GitHub web UI into their own MATLAB path.

## The one hard rule: tools stay copy-pasteable

Each tool must be usable by copying a **single `.m` file** (two files maximum)
out of the repo — no cloning, no `addpath` of shared folders, no download step.

Consequences that override normal DRY instincts:

- **No shared/common utility files.** A tool may not `require`/call helper `.m`
  files that live elsewhere in the repo. If two tools need the same helper,
  each keeps its **own private copy** as a local function at the bottom of its file.
- **Local functions, not separate files**, for a tool's internal helpers
  (prefix them `local_` as the existing tools do).
- One folder per tool under `tools/<tool_name>/`; the main function name must
  equal the file name (MATLAB requirement).
- Every tool file opens with a `help` block: purpose, args, an `.opts` struct
  table, and at least one example — this is the tool's only documentation and
  must stay accurate.
- End each header with the line noting the file has no repo-internal dependencies.

When asked to add a tool, follow this shape; do not introduce a `+package`,
class folder, or shared `utils/` directory.

## Conventions

- Function names: `camelCase`, verb-first (`nameBusElementSignals`, `quickSimEnv`).
- Options passed as a single `opts` struct with a `local_defaults` merge helper,
  not long positional argument lists. Keep the default that is safe/non-destructive
  (e.g. `overwrite` defaults to false where it would clobber existing user data).
- Model-mutating tools default their target to the current system (`gcs`/`bdroot`)
  so they can be run with no arguments on whatever the user has open.
- Return a `report`/result and also print a one-line summary when called with
  `nargout == 0`.

## Verifying changes

There is **no automated test suite and no build step** — every tool needs a live
MATLAB session with Simulink to exercise (Bus Selector/Creator blocks, ConfigSet
objects, `find_system`, etc.). Claude cannot run these here.

So: after editing a tool, state plainly that it is **not verified — needs a MATLAB
session to confirm**, rather than implying it works. Do sanity-check the MATLAB
syntax and API usage (parameter names like `OutputSignals`, `ShowPropagatedSignals`,
`ConfigSetRef.SourceName`) against known Simulink behavior.

## Docs are part of the product

This is a public repo (README + LICENSE). When a tool's behavior, arguments, or
options change, update the file's `help` header **and** the tool table in
[README.md](README.md) in the same change. All repo content is English.

## Domain notes

Models here are AUTOSAR-style and use the **In Bus Element / Out Bus Element**
port blocks (bus-element ports), not Bus Selector / Bus Creator. These are
`Inport`/`Outport` blocks that carry an `Element` parameter naming the bus
element they map to; tools key off that parameter. Detect them with
`strcmp(get_param(blk,'IsBusElementPort'),'on')` — a plain Inport/Outport
still exposes the `Element` dialog parameter (just inactive), so checking
`ObjectParameters` for `Element` alone gives false positives.
