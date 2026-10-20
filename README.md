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
| **Bus element signal naming** | `2.0.1` | CLI and GUI to name In/Out Bus Element signals, stop upstream tracing at Signal Copy/Conversion or Specification, and show propagated Out Bus labels. | [Backend](tools/signal_naming/nameBusElementSignals.m) + optional [GUI](tools/signal_naming/nameBusElementSignalsGui.m) |
| **Forbidden block checker** | `1.0.0` | Checks models and references against JSON rules. Active violations stop the pipeline; commented blocks and blocks feeding only Terminators produce warnings. | [checkForbiddenBlocks.m](tools/forbidden_blocks/checkForbiddenBlocks.m) + [JSON rules](tools/forbidden_blocks/forbidden_blocks.json) |
| **Quick simulation setup** | `1.0.0` | Creates a model, loads MAT data and M-file scripts, links an SLDD, and reuses the first available workspace config set. | [quickSimEnv.m](tools/quick_sim/quickSimEnv.m) |
| **Interface tools** | `1.5.0` | Generates parameter M-files from Excel; previews every `bus.element` difference and syncs selected SLDD interfaces. Separate Parameter M-file and SLDD panels. | [Interface bundle](tools/interface_tools/) |

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
changes; **Apply** edits the model in memory without saving it. Out Bus Element
tracing crosses From/Goto and subsystems, but stops at Signal Conversion
(including Signal Copy), Signal Specification, or other source blocks and names
their output line. The first line leaving an In Bus Element gets its explicit
name without enabling Show propagated; any existing propagation setting is preserved,
even when tracing from an Out Bus Element reaches that line. Propagated Out Bus
labels are enabled on supported source output ports; unsupported blocks report `n/a`.
The CLI remains usable from its single M-file. If propagated labels remain `<>` after Apply,
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
to set `SourceXlsx`, `ProjectRoot`, `SlddFile`, `ParametersFile`, and `ExportXlsx`.
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

Preview leaves the SLDD unchanged but regenerates the export workbook. The sync
backend also returns the complete differences table in `summary.Changes`.

SLDD actions require your project's **`sldd2excel_main`** exporter on the MATLAB
path or beside `ExportXlsx`. It must run without arguments and export the configured
target dictionary to the configured path. The exporter is not included;
parameter generation works independently of it.

## Versioning

Each tool uses its own **MAJOR.MINOR.PATCH** version: breaking changes, compatible
features, and fixes. Find the current version in the feature table or with
`help <functionName>`. The three interface M-files share one bundle version.
The interface bundle continues the imported `1.4.1` version as `1.5.0`. Other
tools begin their tracked history at `1.0.0`; signal naming adds its GUI in `1.1.0`.

See [CHANGELOG.md](CHANGELOG.md) for each tool's version history.

## License

[MIT](LICENSE) &copy; 2026 Long Vo.
