# Tool version history

## Interface tools

### 1.10.2 - 2026-10-26

- Generate correct numeric values and preserve multiline descriptions; keep the
  previous parameter file if generation fails.
- Detect sheets beyond column AZ and sync exactly the selected sheets.
- Keep the GUI open during an operation so closing cannot interrupt its controls.
- Use neutral interface window titles and configurable project defaults.

### 1.10.1 - 2026-10-20

- Keep Select all changes and Clear changes at the left above the differences
  table with explicit positions and fixed widths, including in narrow windows.
- Enable the resize callback so the differences table uses available window height.

### 1.10.0 - 2026-10-20

- Apply checked DataType, dimensions, Unit, and Description differences in both
  CLI and GUI, including plans containing only property changes. Leave unchecked
  and unspecified fields intact; keep referenced interfaces read-only.
- Preserve shared type definitions by copying named types into an element-specific
  ValueType when changing one element. Show property update counts in the log.
- Reject conflicting Unit/Description values for compared elements across sheets.

### 1.9.1 - 2026-10-20

- Keep the differences table usable on short windows with a minimum height and
  scrolling for overflowing panels.
- Ignore Excel buses matching Service/Physical Interfaces during comparison and
  Apply, so they cannot block valid element changes.
- Ignore conflicting rows outside the selected bus scope while retaining
  cross-sheet validation for compared buses.

### 1.9.0 - 2026-10-20

- Show element definitions in ADD/REMOVE rows, including Excel values, missing
  SLDD elements, removal Status, and current SLDD metadata.
- Stream detailed backend progress and warnings into a larger Activity log,
  retain all session messages, and add Follow latest with pause/resume.
- Enlarge the model selector across the wider SLDD panel and move sheet
  selection buttons below the list.

### 1.8.0 - 2026-10-20

- Propose deletions only for Excel rows explicitly marked `Status=remove`;
  keep elements absent from Excel or without that status. Matching ignores
  case and surrounding spaces; remove rows never generate additions.
- Require a fresh preview when remove Status changes, and stop on conflicting
  remove/keep rows for the same element across sheets.

### 1.7.0 - 2026-10-20

- Tick individual local element additions/removals in the preview table, select
  all or clear them, then apply only those changes. Property differences and
  referenced interfaces remain report-only.
- Compare only buses named in selected Excel sheets; ignore other SLDD buses.
- Refresh the table after Apply and reject stale previews if compared data
  changes. CLI options support the same selection and preview validation.

### 1.6.0 - 2026-10-20

- Compare Excel directly with every Architectural Data Data Interface, including
  references, nested/typed elements, and an inventory of empty interfaces.
- Remove the external exporter and intermediate Excel dependency from CLI and GUI;
  retain legacy calls/configs without touching their export paths.
- Include SLDD-only elements in all-sheet comparisons, retaining buses outside
  selected sheets and keeping referenced interfaces report-only.
- Protect unsaved dictionary edits during Preview/Apply and discard partial sync
  changes if an addition fails.

### 1.5.0 - 2026-10-19

- Separate Parameter M-file and SLDD panels; remove the combined action.
- Configure default workbook, project, and output paths through JSON.
- Preview every `bus.element` addition, removal, and property difference in a
  scrollable table, with XLSX/SLDD values and a complete backend report.
- Continue the imported sync tool's `1.4.1` version; the three M-files now share
  the interface bundle version. Property differences remain report-only.

## Bus element signal naming

### 2.0.1 - 2026-10-26

- Follow Simulink's resolved Goto visibility in CLI and GUI, preventing changes
  to unrelated signals with the same tag in other subsystems.

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

### 1.0.1 - 2026-10-26

- Stop incomplete referenced-model checks instead of returning a passing result.
- Report single violations consistently with multiple-violation reports.

### 1.0.0 - 2026-10-19

- Establish the first tracked version of the existing JSON-configured checker:
  check models and references, report warnings, and stop on active violations.

## Quick simulation setup

### 1.0.0 - 2026-10-19

- Establish the first tracked version of the existing setup tool: create a model,
  load MAT/M-file inputs, link an SLDD, and reuse a workspace configuration.
