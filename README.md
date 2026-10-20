<h1 align="center">MATLAB / Simulink Helpers</h1>

<p align="center">Small, self-contained tools for everyday Model-Based Design work.</p>

<p align="center">
  <a href="https://github.com/longvo92/matlab_tools/actions/workflows/matlab-lint.yml"><img src="https://github.com/longvo92/matlab_tools/actions/workflows/matlab-lint.yml/badge.svg" alt="MATLAB lint CI"></a>
  <a href=".github/workflows/matlab-lint.yml"><img src="https://img.shields.io/badge/Python%20(CI)-3.12-3776AB?logo=python&amp;logoColor=white" alt="Python 3.12 for CI only"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-green.svg" alt="MIT License"></a>
</p>

<p align="center">
  <a href="#features">Features</a> &middot;
  <a href="#quick-start">Quick start</a> &middot;
  <a href="#interface-tools">Interface tools</a> &middot;
  <a href="https://github.com/longvo92/matlab_tools/issues">Issues</a> &middot;
  <a href="#versioning">Versions</a> &middot;
  <a href="#license">License</a>
</p>

## Features

| Tool | Version | What it does | Copy |
| --- | --- | --- | --- |
| **Bus element signal naming** | `2.0.0` | CLI and GUI to preview/apply names from In/Out Bus Element ports, trace upstream sources, and enable propagated names. | [Backend](tools/signal_naming/nameBusElementSignals.m) + optional [GUI](tools/signal_naming/nameBusElementSignalsGui.m) |
| **Forbidden block checker** | `1.0.0` | Checks models and references against JSON rules. Active violations stop the pipeline; commented blocks and blocks feeding only Terminators produce warnings. | [checkForbiddenBlocks.m](tools/forbidden_blocks/checkForbiddenBlocks.m) + [JSON rules](tools/forbidden_blocks/forbidden_blocks.json) |
| **Quick simulation setup** | `1.0.0` | Creates a model, loads MAT data and M-file scripts, links an SLDD, and reuses the first available workspace config set. | [quickSimEnv.m](tools/quick_sim/quickSimEnv.m) |
| **Interface tools** | `1.9.0` | Compares Excel buses directly with SLDD Data Interfaces; lets you tick individual element additions/removals to apply, and generates parameter M-files. | [Interface bundle](tools/interface_tools/) |

## Quick start

Copy the tool you need into a folder on your MATLAB path. No package installation
or shared repository helpers are needed. Keep adjacent JSON files with their tools;
copy the entire interface bundle when using its GUI.

```matlab
% Preview signal naming changes in the current system
report = nameBusElementSignals(gcs, struct('dryRun', true));

% Or open the signal naming GUI (copy both signal_naming M-files)
nameBusElementSignalsGui

% Check the model and its references before code generation
checkForbiddenBlocks('MyModel')

% New model with stimuli, calibration script, and a data dictionary
quickSimEnv('drive_cycle.mat', 'calib_params.m', 'project.sldd')

% Open the Excel / SLDD interface GUI
interface_tools_gui
```

Use `help <functionName>` for options and examples. `quickSimEnv` puts MAT data in
the model workspace, falling back to the base workspace for incompatible objects
such as bus objects and config sets. M-file scripts run in the base workspace.
Pass `'sldd'` to discover a dictionary, or no arguments to create an empty model
and link the first available config set.

The signal naming GUI defaults to the current model/subsystem. It provides
subsystem scope, overwrite, and propagated-name options. Names use the complete
Element path, with dots replaced by underscores. **Preview** reports proposed
changes; **Apply** edits the model in memory without saving it. Propagated labels
are enabled on supported source output ports; unsupported blocks report `n/a`.
In Bus Element selection labels require R2024b or later
([MathWorks](https://www.mathworks.com/help/simulink/ug/signal-label-propagation.html)). The CLI remains
usable from its single M-file. If propagated labels remain `<>` after Apply,
use Update Diagram (`Ctrl+D`) to resolve them; the tool does not compile models
automatically.

Since `2.0.0`, prefix and leaf-name options are removed. Existing calls with an
empty prefix or `useLeafName=false` remain accepted; active legacy values raise
`SignalNaming:RemovedOption`. Remove those options to use full Element names.

These are MATLAB/Simulink tools. Python 3.12 is used only by the
[CI lint workflow](.github/workflows/matlab-lint.yml), which runs MISS_HIT without
a MATLAB license.

## Interface tools

Requires MATLAB/Simulink R2024a or later. Copy all three M-files and the JSON config
from [`tools/interface_tools/`](tools/interface_tools/) into the same folder.

Edit [interface_tools_config.json](tools/interface_tools/interface_tools_config.json)
to set `SourceXlsx`, `ProjectRoot`, `SlddFile`, and `ParametersFile`.
Use `/` or escaped `\\` in JSON paths. `SourceXlsx` and `ProjectRoot` are relative
to the config folder; output paths are relative to the project root. Absolute
paths are accepted.

Leave `SourceXlsx` empty to choose a workbook in the GUI. Leave `ProjectRoot` empty
to discover it from the workbook, tool folder, or current folder using
`ProjectFolderName` and `ArchitectureFolder`. If the preferred SLDD is absent,
the GUI accepts a single project-local SLDD.

```matlab
% Optional: keep machine-specific paths outside the repository
interface_tools_gui(struct('ConfigFile', 'C:/local/interface_tools_config.json'))
```

| Panel | Behavior |
| --- | --- |
| **Parameter M-file** | Processes **all parameter sheets**, regardless of the SLDD selection. Confirms before overwriting the output. |
| **SLDD interfaces** | Preview compares Excel buses and lists `ADD`, `REMOVE`, and `PROPERTY_DIFF` as `bus.element`. Tick the local additions/removals you want, then click **Apply selected**. Property differences and referenced interfaces are report-only. |

Preview reads **Data Interfaces in Architectural Data** directly from the
configured SLDD. Only buses named in the selected Excel sheets are compared;
other SLDD buses are ignored. For those buses, expected elements come from all
workbook sheets to protect shared elements. Service/Physical Interfaces and
buses in Design Data are excluded. No exporter or intermediate Excel is needed.

ADD/REMOVE rows show `element` in Property. ADD shows the Excel definition and
`<missing>` in SLDD; REMOVE shows `Status=remove` and the current SLDD definition.
Definitions include DataType and dimensions (`<empty>` when blank), plus unit
and description when provided. Full definitions also appear in the Activity log.
PROPERTY_DIFF rows continue to show each changed property separately.
Each element addition/removal still has one checkbox.

The model list spans the wider SLDD panel. The Activity log streams sheet reads,
SLDD reads, comparison counts, element changes, parameter results, and warnings;
it retains the full session history. **Follow latest** shows new messages at the top, so no repeated scrolling
is needed. Turn it off to pause the view while reading earlier entries, then
turn it on to catch up. The status line continues updating while the view is paused.

Only Excel rows with **`Status = remove`** propose a deletion (case-insensitive,
with surrounding spaces ignored). Missing/blank/other Status values and elements
absent from Excel never authorize deletion. Remove rows do not create additions
or property differences, and need no DataType. Conflicting remove/keep rows for
the same `Bus.Element` across sheets stop comparison before any edits.

Run **Preview differences**, tick individual **Apply** checkboxes, then click
**Apply selected**. Checkboxes start cleared; **Select all changes** selects only
editable local ADD/REMOVE rows. Existing property differences and referenced
interfaces cannot be selected. The table refreshes after Apply and clears the
selection. Changing the workbook/sheets clears the preview. If compared data
changes after Preview, including a change to remove Status, run Preview again
before applying.

```matlab
preview = sync_bus_interfaces_from_excel('new.xlsx', 'architecture.sldd', 'all', 'preview');
% Select the rows to add/remove (indices into preview.Changes):
rows = find(preview.Selectable); % Replace with the rows you want.
opts = struct('Mode', 'apply', 'SelectedChanges', preview.Changes(rows, :), ...
    'ExpectedSnapshot', {preview.Snapshot});
summary = sync_bus_interfaces_from_excel('new.xlsx', 'architecture.sldd', 'all', opts);
```

`summary.Changes` contains the complete differences table; `summary.Selectable`
marks editable rows. `summary.Interfaces` lists matching Data Interfaces with
name, element count, and reference status. `summary.SelectedAdd/SelectedRemove`
count the selected changes; `Added/Removed` count changes actually applied.
An empty `SelectedChanges` table applies nothing. CLI calls without this option
retain apply-all behavior; `opts.Mode` defaults to preview. Both backends accept
an optional `opts.LogFcn = @(message) ...` progress callback (fourth argument;
parameter generation keeps its sheet selection as the third argument).

Preview never edits or saves the SLDD. Apply protects pending edits in the
dictionary and its references, keeps empty interfaces, and rolls back failed
changes. Legacy five-argument calls and configs with `ExportXlsx` are accepted;
the export path is ignored and never read, written, or deleted.

## Versioning

Each tool uses its own **MAJOR.MINOR.PATCH** version: breaking changes, compatible
features, and fixes. Find the current version in the feature table or with
`help <functionName>`. The three interface M-files share one bundle version.
The interface bundle continues the imported `1.4.1` version. Other
tools begin their tracked history at `1.0.0`; signal naming adds its GUI in `1.1.0`.

See [CHANGELOG.md](CHANGELOG.md) for each tool's version history.

## License

[MIT](LICENSE) &copy; 2026 Long Vo.
