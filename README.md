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
| **Interface tools** | `1.6.0` | Compares Excel directly with SLDD Data Interfaces; previews every `bus.element` difference, syncs selected interfaces, and generates parameter M-files. | [Interface bundle](tools/interface_tools/) |

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
| **SLDD interfaces** | Preview lists every `ADD`, `REMOVE`, and `PROPERTY_DIFF` as `bus.element`, with XLSX/SLDD property values. Sync confirms before applying additions/removals for selected sheets. Existing property differences remain report-only. |

Preview reads **all Data Interfaces in Architectural Data**, including referenced
and empty interfaces, directly from the configured SLDD. Service/Physical
Interfaces and buses in Design Data are excluded. No `sldd2excel_main` or
intermediate Excel workbook is needed.

With all sheets selected, comparison includes SLDD-only elements. With a subset,
it compares buses named in those sheets, collecting their expected elements from
all workbook sheets to protect shared elements. Sync only changes local buses
named in selected sheets; SLDD-only buses and references remain report-only.
Empty interfaces are retained. Apply refuses pending edits in the dictionary or its references.

```matlab
summary = sync_bus_interfaces_from_excel('new.xlsx', 'architecture.sldd', 'all', 'preview');
% Review summary.Changes, then apply additions/removals:
summary = sync_bus_interfaces_from_excel('new.xlsx', 'architecture.sldd', 'all', 'apply');
```

`summary.Changes` contains the complete differences table. `summary.Interfaces`
lists each Data Interface's name, element count, and reference status;
`summary.OutOfScope` counts report-only removals outside selected buses.
Preview never edits or saves the SLDD. Existing property differences remain
report-only. Legacy five-argument calls and configs with `ExportXlsx` are accepted;
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
