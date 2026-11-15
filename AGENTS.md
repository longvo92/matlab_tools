# MATLAB / Simulink Helpers

Small, self-contained, reusable MATLAB/Simulink tools for everyday Model-Based Design work.

## Layout
- `tools/<tool_name>/`: `autosar_mapping`, `forbidden_blocks`, `interface_tools`, `quick_sim`, `signal_naming`. Each tool runs directly without installation; keep cross-tool dependencies explicit.
- `tests/` holds one `test*.m` per tool area. `miss_hit.cfg` configures lint; CI is `.github/workflows/matlab-lint.yml` (lint only).

## Runtime
- MATLAB/Simulink R2024a or later; AUTOSAR mapping also needs AUTOSAR Blockset. CI lint uses Python 3.12 for MISS_HIT only.

## Commands
- Lint: `mh_lint .`
- Tests: run the matching `tests/test*.m` in a live MATLAB session, e.g. `tests/testInterfaceTools.m` for interface tools.

## Invariants
- Respect the loaded model state, dictionaries, architecture interfaces and existing mappings; no unintended model changes or data loss.
- Use only APIs available on the declared MATLAB release; newer default-method APIs are unavailable on R2024a.
- The interface GUI bundle (`interface_tools_gui.m`, `sync_bus_interfaces_from_excel.m`, `generate_simulink_parameters.m` and `interface_tools_config.json`) ships together at one version.
- Each tool is versioned independently (MAJOR.MINOR.PATCH), kept in sync across M-file help, README and CHANGELOG.

Working rules live in the owner's global instructions.
