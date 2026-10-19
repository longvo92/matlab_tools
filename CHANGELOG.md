# Tool version history

## Interface tools

### 1.5.0 - 2026-10-19

- Separate Parameter M-file and SLDD panels; remove the combined action.
- Configure default workbook, project, and output paths through JSON.
- Preview every `bus.element` addition, removal, and property difference in a
  scrollable table, with XLSX/SLDD values and a complete backend report.
- Continue the imported sync tool's `1.4.1` version; the three M-files now share
  the interface bundle version. Property differences remain report-only.

## Bus element signal naming

### 2.0.0 - 2026-10-19

- Remove name-prefix and leaf-element naming from CLI and GUI; always derive
  names from the complete Element path. Reject active legacy options explicitly;
  empty prefix and false leaf-name values remain accepted.
- Fix Show propagated labels by configuring the source output port rather than
  the signal line handle. Preview remains read-only.
- Compact the GUI to subsystem scope, overwrite, and propagated-label options.

### 1.1.0 - 2026-10-19

- Add an optional GUI with current-system selection, prefix and common naming
  options, Preview/Apply actions, and a complete results table.
- Preview leaves the model unchanged; Apply edits in memory without saving.
  The existing single-file CLI and its defaults remain compatible.

### 1.0.0 - 2026-10-19

- Establish the first tracked version of the existing tool: name signals from
  bus-element ports, trace upstream sources, and display propagated names.

## Forbidden block checker

### 1.0.0 - 2026-10-19

- Establish the first tracked version of the existing JSON-configured checker:
  check models and references, report warnings, and stop on active violations.

## Quick simulation setup

### 1.0.0 - 2026-10-19

- Establish the first tracked version of the existing setup tool: create a model,
  load MAT/M-file inputs, link an SLDD, and reuse a workspace configuration.
