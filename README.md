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
  <a href="#autosar-mapping">AUTOSAR mapping</a> &middot;
  <a href="https://github.com/longvo92/matlab_tools/issues">Issues</a> &middot;
  <a href="#versioning">Versions</a> &middot;
  <a href="#license">License</a>
</p>

## Features

| Tool | Version | What it does | Copy |
| --- | --- | --- | --- |
| **Bus element signal naming** | `2.0.1` | CLI and GUI to preview/apply names from In/Out Bus Element ports, trace upstream sources, and enable propagated names. | [Backend](tools/signal_naming/nameBusElementSignals.m) + optional [GUI](tools/signal_naming/nameBusElementSignalsGui.m) |
| **Forbidden block checker** | `1.0.1` | Checks models and references against JSON rules. Active violations stop the pipeline; commented blocks and blocks feeding only Terminators produce warnings. | [checkForbiddenBlocks.m](tools/forbidden_blocks/checkForbiddenBlocks.m) + [JSON rules](tools/forbidden_blocks/forbidden_blocks.json) |
| **Quick simulation setup** | `1.0.1` | Creates a model, loads MAT data and M-file scripts, links an SLDD, and reuses the first available workspace config set. | [quickSimEnv.m](tools/quick_sim/quickSimEnv.m) |
| **Interface tools** | `1.10.2` | Compares Excel buses directly with SLDD Data Interfaces; lets you tick individual element/property changes to apply, and generates parameter M-files. | [Interface bundle](tools/interface_tools/) |
| **AUTOSAR Code Mappings** | `1.2.0` | CLI/GUI to preview/apply per-model mapping rules, with global calibration regexp, access modes, memory/calibration/NVRAM settings and defaults. | [AUTOSAR mapping bundle](tools/autosar_mapping/) |

## Quick start

Copy the tool you need into a folder on your MATLAB path. No package installation
or shared repository helpers are needed. Keep adjacent JSON files with their tools;
copy the entire interface bundle when using its GUI. Copy the entire AUTOSAR
mapping folder, including `+autosarMapping`, when using Code Mappings.

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
and link the first available config set. Linking an external SLDD adds its folder
to the session's MATLAB path and reports the verified full path in `report.sldd`.
Failed links leave the model unlinked and restore the previous path.

The forbidden block checker stops if a referenced model cannot be resolved.
Set `opts.checkReferencedModels=false` to explicitly check only the given model.

The signal naming GUI defaults to the current model/subsystem. It provides
subsystem scope, overwrite, and propagated-name options. Names use the complete
Element path, with dots replaced by underscores. Goto tracing follows Simulink's
local, scoped, and global tag resolution. **Preview** reports proposed
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

## AUTOSAR mapping

Requires MATLAB/Simulink R2024a or later, AUTOSAR Blockset, and a loaded AUTOSAR
Classic component model. Open the GUI with:

```matlab
addpath('tools/autosar_mapping')
autosarMappingGui
```

Choose or load a model, optionally select its CSV, edit the global calibration
JSON, then click **Preview** and **Apply preview**. The table shows current and
desired values and the matching global pattern. Leave Model CSV empty to use
global calibration rules alone. **Export CSV** writes a new settings file;
**Edit** opens an existing config in the MATLAB editor. Changing inputs clears
the preview. Apply rejects model/CSV/JSON changes made since Preview. Closing
is deferred during operations. Changes stay in memory; save in Simulink after
review. The CLI uses the same backend:

```matlab
addpath('tools/autosar_mapping')
load_system('MotorCtrl')
rules = exportAutosarMapping('MotorCtrl', 'code_mapping.csv'); % New file only.
% Edit code_mapping.csv, retaining the rows you want to manage.
r = configureAutosarMapping('MotorCtrl', 'code_mapping.csv'); % Preview.
disp(r.Elements)
r = configureAutosarMapping('MotorCtrl', 'code_mapping.csv', struct('Mode', 'apply'));
save_system('MotorCtrl') % Explicit save after review.
```

Global naming rules live in
[autosar_calibration_config.json](tools/autosar_mapping/autosar_calibration_config.json),
shared by every model and both CLI/GUI. The file is read on each run and has no
model-specific sections. `IncludePatterns` starts empty so no naming convention
is assumed. For example, adapt these patterns to your project's names:

```json
{
  "IncludePatterns": ["^(Cal_|K_)"],
  "ExcludePatterns": ["_Test$"],
  "IgnoreCase": false,
  "PreserveExplicitMappings": true
}
```

A model parameter/argument matches any include and no exclude. Patterns use
MATLAB regexp syntax; double backslashes inside JSON strings. Invalid patterns
and dynamic MATLAB commands in patterns are rejected. Defaults map matching
Auto parameters to SharedParameter, Auto arguments to PerInstanceParameter,
and set SwCalibrationAccess=ReadWrite. `PreserveExplicitMappings` keeps existing
non-Auto **roles**; calibration access still follows the global config. The file
also exposes ModelParameterMapping, ArgumentMapping, SwCalibrationAccess and
Enabled. Explicit model CSV fields take precedence; MappedTo=Auto opts an
element out of these defaults. Exported CSV rows are explicit too: remove rows
you want global defaults to manage.

Use `calibration:*` in a parameter category to select the matching names, even
before their Auto mappings become calibration parameters. For example:

```csv
Model,Category,Element,Property,Value
MotorCtrl,ModelParameters,calibration:*,SwAddrMethod,CONST
```

```matlab
r = configureAutosarMapping('MotorCtrl'); % Global calibration rules only.
opts = struct('CalibrationConfig', 'company_calibration.json');
r = configureAutosarMapping('MotorCtrl', [], opts); % Another shared config.
```

Set opts.CalibrationConfig='' to disable global rules for a call. Reports expose
CalibrationMatches and CalibrationConfig. Pass a preview's Snapshot through
opts.ExpectedSnapshot for guarded CLI apply. The original SwAddrMethod-only
shorthand below retains its original behavior and does not classify calibration.

The property schema is `Model,Category,Element,Property,Value`. Example rules
are in [autosar_code_mapping.csv](tools/autosar_mapping/autosar_code_mapping.csv):

```csv
Model,Category,Element,Property,Value
MotorCtrl,Inports,*,DataAccessMode,ExplicitReceive
MotorCtrl,Outports,*,DataAccessMode,ExplicitSend
MotorCtrl,Signals,type:StaticMemory,SwAddrMethod,VAR
MotorCtrl,Defaults,InternalData,Packaging,PrivateGlobal
```

| Category | Settings |
| --- | --- |
| `Inports`, `Outports` | Port, DataElement, DataAccessMode: implicit, explicit, queued, E2E, status and mode-switch modes supported by the native API. Bus-element ports use their block names. |
| `Functions` | Runnable, SwAddrMethod, SwAddrMethodForInternalData on eligible entry points. |
| `FunctionCallers`, `DataTransfers` | Client Port/Operation; InterRunnableVariable and Implicit/Explicit DataAccessMode. |
| `ModelParameters`, `ModelParameterArguments` | MappedTo, native calibration attributes, ConstantMemory qualifiers, Port/DataElement for PortParameter arguments. |
| `Signals`, `States`, `DataStores`, `SynthesizedDataStores` | MappedTo, ShortName, LongName, SwAddrMethod, SwCalibrationAccess, DisplayFormat; IsVolatile/Qualifier for StaticMemory; NeedsNVRAMAccess/RestoreAtStart/StoreAtShutdown for per-instance memory. |
| `Defaults` | InternalData: Packaging and GroupInternalDataByFunction; InportsOutports: EndToEndProtectionMethod. InternalData/Constants SwAddrMethod defaults are available only on releases exposing those public APIs. |

Use exact exported identifiers, `*` for a category, or `type:StaticMemory` (etc.)
for its **current** memory type. Signals use `block/path:port`; named states can
be targeted with `block/path#StateName`. Native state discovery exports block
owners; add named-state rules explicitly for blocks with multiple named states.
`Registered=true/false` explicitly adds/removes signal or synthesized-store
mappings; Registered=false must be the only rule for that element.
New synthesized stores require a model-workspace Simulink.Signal.

Models use exact names without folders/extensions. Categories ignore case;
properties and native enum values use their exported spelling. Empty Value
explicitly clears an attribute; omitting a row leaves it unmanaged. Each resolved
element/property may have one rule, so overlapping selectors are rejected.
Unmatched selectors and unknown/unavailable settings are errors. CSV files
resolve in the current folder, then on the MATLAB path; tables are also accepted.
Pass `[]` as the model to use the current model.

Coupled properties are applied together regardless of CSV row order. Changing
MappedTo preserves compatible settings and discards properties unavailable for
the new role. Defaults apply first; native readback verifies all configured
settings. Failed operations attempt to restore full readable settings and
registration; exception causes include rollback failures. The tool never saves
the model or traverses references. Run each referenced model explicitly.

Preview validates schema, selectors, property applicability, method section types
and scalar enums. Apply also invokes the native setters, which can reject
context-dependent combinations. For example, ModeReceive/ModeSend require
mode-switch ports, and queued/E2E modes need appropriate interface configuration
and code-generation validation. No compilation, code generation, dictionary
element creation, or Adaptive-platform configuration is performed. Export lists
only properties available on the installed release; R2026b default-method APIs
are unavailable on R2024a. Run `tests/testAutosarCodeMapping.m` for native fixture
coverage and `tests/testAutosarCalibrationAndGui.m` for global regexp and GUI
callbacks. Production-model code generation is a separate validation step.

The original SwAddrMethod-only API remains available with
[autosar_mapping.csv](tools/autosar_mapping/autosar_mapping.csv):

```csv
Model,Type,SwAddrMethod
MotorCtrl,Runnable,CODE
MotorCtrl,ConstantMemory,CONST
MotorCtrl,SharedParameter,CONST
MotorCtrl,StaticMemory,VAR
MotorCtrl,ArTypedPerInstanceMemory,VAR
BatteryCtrl,Runnable,BATTERY_CODE
```

Each `(Model, Type)` occurs once; types ignore case. Supported types are
Runnable, RunnableInternalData, ConstantMemory, SharedParameter, StaticMemory,
and ArTypedPerInstanceMemory. All explicit mappings of a type use the same
method in that model. This shorthand leaves Auto mappings and unconfigured types
unchanged and operates on model workspace parameters, registered signals, states,
and Data Store Memory blocks. Use the property API above for parameter arguments
and other settings.

```matlab
r = mapAutosarSwAddrMethods('MotorCtrl', 'autosar_mapping.csv');
r = mapAutosarSwAddrMethods('MotorCtrl', 'autosar_mapping.csv', struct('Mode', 'apply'));
```

`r.Rules.Matched` exposes rules with no matching elements; `r.Compliant` requires
every rule to match and every configured element to have the desired method.

Methods must already exist in the model with unique SHORT-NAMEs. SectionType
must be `Code` for Runnable, `Const` for ConstantMemory, `Const` or `Calprm` for
SharedParameter, and `Var` for variable memory. The optional
`RunnableInternalData` type requires `GroupInternalDataByFunction='on'` and a
`Var` method. Initialize, terminate, and reset functions have no configurable
internal-data method and are reported as ignored. Unsupported or ambiguous
rules stop the operation before any mapping changes.

Run `tests/testAutosarMapping.m` for shorthand API regression coverage. The native
workflow is described in [MathWorks AUTOSAR mapping API](https://www.mathworks.com/help/autosar/ref/autosar.api.getsimulinkmapping.html).

## Interface tools

Requires MATLAB/Simulink R2024a or later. Copy all three M-files and the JSON config
from [`tools/interface_tools/`](tools/interface_tools/) into the same folder.

Edit [interface_tools_config.json](tools/interface_tools/interface_tools_config.json)
to set `SourceXlsx`, `ProjectRoot`, `SlddFile`, and `ParametersFile`.
The bundled defaults use neutral `project` and `architecture` folder names,
`Interfaces.sldd`, and `Parameters.m`; adjust them to your project.
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
| **Parameter M-file** | Processes **all parameter sheets**, regardless of the SLDD selection. Confirms before overwriting; preserves the previous file if generation fails. |
| **SLDD interfaces** | Preview compares Excel buses and lists `ADD`, `REMOVE`, and `PROPERTY_DIFF` as `bus.element`. Tick local additions/removals and individual property changes, then click **Apply selected**. Referenced interfaces remain read-only. |

Generated parameters normalize numeric text such as `1,000` to `1000` and retain
line breaks in descriptions. Generation uses a temporary file before replacing
the output.

Preview reads **Data Interfaces in Architectural Data** directly from the
configured SLDD. Only buses named in the selected Excel sheets are compared;
other SLDD buses are ignored. For those buses, expected elements come from all
workbook sheets to protect shared elements. Service/Physical Interfaces and
buses in Design Data are excluded. Excel names matching Service/Physical Interfaces
are ignored instead of becoming additions. No exporter or intermediate Excel is needed.

ADD/REMOVE rows show `element` in Property. ADD shows the Excel definition and
`<missing>` in SLDD; REMOVE shows `Status=remove` and the current SLDD definition.
Definitions include DataType and dimensions (`<empty>` when blank), plus unit
and description when provided. Full definitions also appear in the Activity log.
PROPERTY_DIFF rows show each changed property separately. Apply updates the checked
DataType, dimensions, Unit, and Description fields from Excel. Blank Excel fields
remain unspecified. Unchecked fields are preserved. If an element uses a named
or shared type, the tool creates an element-specific ValueType for its updated
properties, preserving the original type and other elements that use it.
Each element addition/removal still has one checkbox.

The model list spans the wider SLDD panel. On short windows, the differences
table keeps a minimum height; scroll the main window to reach the lower panels.
The Activity log streams sheet reads,
SLDD reads, comparison counts, element changes, parameter results, and warnings;
it retains the full session history. **Follow latest** shows new messages at the top, so no repeated scrolling
is needed. Turn it off to pause the view while reading earlier entries, then
turn it on to catch up. The status line continues updating while the view is paused.

Only Excel rows with **`Status = remove`** propose a deletion (case-insensitive,
with surrounding spaces ignored). Missing/blank/other Status values and elements
absent from Excel never authorize deletion. Remove rows do not create additions
or property differences, and need no DataType. Conflicting remove/keep rows for
the same compared `Bus.Element` across sheets stop comparison before any edits.
Conflicting specified Unit/Description values across shared sheets are also
rejected. Conflicts in buses outside the selected scope are ignored.

Run **Preview differences**, tick individual **Apply** checkboxes, then click
**Apply selected**. **Select all changes** and **Clear changes** sit at the left
above the differences table, including in narrow windows. Checkboxes start cleared;
**Select all changes** selects
editable local ADD/REMOVE/PROPERTY_DIFF rows. Referenced interfaces cannot be
selected. The table refreshes after Apply and clears the selection. Changing
the workbook/sheets clears the preview. Operations use exactly the selected
sheet names, including sheets with headers beyond column AZ. Close the window
after the current operation finishes. If compared data changes after Preview,
including a change to remove Status, run Preview again before applying.

```matlab
preview = sync_bus_interfaces_from_excel('new.xlsx', 'architecture.sldd', 'all', 'preview');
% Select element/property changes (indices into preview.Changes):
rows = find(preview.Selectable); % Replace with the rows you want.
opts = struct('Mode', 'apply', 'SelectedChanges', preview.Changes(rows, :), ...
    'ExpectedSnapshot', {preview.Snapshot});
summary = sync_bus_interfaces_from_excel('new.xlsx', 'architecture.sldd', 'all', opts);
```

`summary.Changes` contains the complete differences table; `summary.Selectable`
marks editable rows. `summary.Interfaces` lists matching Data Interfaces with
name, element count, and reference status. `summary.SelectedAdd/SelectedRemove`
count selected element changes; `Added/Removed` count element changes applied.
`SelectedUpdate/Updated` count selected/applied individual property changes.
For PROPERTY_DIFF selections, the table must include `Action`, `Interface`, and
`Property`; multiple fields on one element can be selected independently.
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
