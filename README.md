# matlab_tools

[![MATLAB lint](https://github.com/longvo92/matlab_tools/actions/workflows/matlab-lint.yml/badge.svg)](https://github.com/longvo92/matlab_tools/actions/workflows/matlab-lint.yml)

Small, self-contained MATLAB / Simulink helper tools for day-to-day MBD work.

Every tool is a single `.m` file (two at most) with **no cross-tool dependencies**.
That means you can grab a tool straight from the GitHub web UI — open the file,
copy its contents into your MATLAB path — without cloning or downloading the repo.

## Layout

```
tools/
  <tool_name>/<mainFunction>.m   # one folder per tool, function name = file name
```

Each `.m` file starts with an `help` block documenting its arguments, options,
and an example, so `help <functionName>` works after you copy it in.

## Tools

| Tool | File | What it does |
|------|------|--------------|
| Bus element signal naming | [`tools/signal_naming/nameBusElementSignals.m`](tools/signal_naming/nameBusElementSignals.m) | Names the signal on each In/Out Bus Element block after that block's `Element`, tracing upstream through From/Goto and subsystems to find the real source for Out Bus Elements, and turns on propagated-signal display. Built for AUTOSAR-style models. |
| Quick simulation setup | [`tools/quick_sim/quickSimEnv.m`](tools/quick_sim/quickSimEnv.m) | Creates a new empty model, loads a data `.mat` you name into the base workspace, and auto-links the first config set found in the base workspace. |

## Usage

Copy a tool's `.m` file somewhere on your MATLAB path, then call it. Examples:

```matlab
% Name the current system's bus element signals and show propagated names
nameBusElementSignals(gcs)

% New model + load stimuli + auto-link a config set from the base workspace
quickSimEnv('drive_cycle.mat')
```

See each file's header (`help nameBusElementSignals`, `help quickSimEnv`) for the
full option list.

## Continuous checks

Every push and pull request runs [MISS_HIT](https://florianschanda.github.io/miss_hit/)
over all `.m` files ([workflow](.github/workflows/matlab-lint.yml)). It is a
pure-Python analyzer, so the checks need no MATLAB license.

- **`mh_lint`** parses each file and flags likely bugs — a syntax error or a lint
  finding fails the build.
- **`mh_style`** and **`mh_metric`** report formatting and complexity as advisory
  output; they never block a merge.

Run the same checks locally before pushing:

```bash
pip install miss_hit
mh_lint .      # gate: syntax + bug checks
mh_style .     # advisory: formatting
mh_metric .    # advisory: complexity
```

## License

MIT — see [LICENSE](LICENSE).
