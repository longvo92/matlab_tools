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

### 2.0.2 - 2026-10-20

- Fix index errors in models containing Function Element Call or Function
  Element blocks by skipping bus-element blocks without data ports in CLI and
  GUI. Continue naming data signals, including Function Caller data outputs,
  without changing function prototypes or function element definitions.

### 2.0.1 - 2026-10-20

- Stop Out Bus Element upstream tracing at Signal Conversion (including Signal
  Copy) and Signal Specification, and name their output line.
- Name the first In Bus Element line without enabling Show propagated, including
  direct Out Bus connections and intermediate trace paths. Preserve existing settings.

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
