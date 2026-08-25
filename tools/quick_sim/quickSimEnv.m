function [model, report] = quickSimEnv(varargin)
%QUICKSIMENV Spin up a fresh model, load data files, and grab a config set from the workspace.
%
%   Fast pre-run setup in one call:
%     1. Creates a new empty model and opens it (like Ctrl+N).
%     2. Pushes every data file you name into the base workspace: .mat files are
%        loaded, .m files are run there as scripts.
%     3. Scans the base workspace for a Simulink.ConfigSet and links it to the
%        new model as the active configuration (a config reference, so the model
%        stays in sync with the workspace variable).
%
%   MODEL = QUICKSIMENV
%   MODEL = QUICKSIMENV(FILE1, FILE2, ...)
%   MODEL = QUICKSIMENV({FILE1, FILE2, ...})
%   [MODEL, REPORT] = QUICKSIMENV(...)
%
%       FILEn    name/path of a .mat or .m data file; files are processed in the
%                order given. A name without extension is resolved as .mat first,
%                then .m. Pass no file at all to only create the model and link
%                the config.
%       MODEL    name of the new model.
%       REPORT   struct describing what happened:
%                  .model    model name
%                  .loaded   struct array (name, type, vars) of files that loaded
%                  .skipped  struct array (name, reason) of files that did not
%                  .config   base workspace config variable linked, '' if none
%
%   No data file is required and none is fatal: a file that is missing, has an
%   unsupported extension, or errors while loading is reported as skipped with a
%   warning, the remaining files still load, and the model and config work is
%   still done.
%
%   The config set is found automatically: the first base workspace variable of
%   class Simulink.ConfigSet (or Simulink.ConfigSetRef) is used. If none exists,
%   the model keeps its default configuration and a note is printed.
%
%   Examples:
%       quickSimEnv('drive_cycle.mat')
%       quickSimEnv('drive_cycle.mat', 'calib_params.m', 'bus_defs.mat')
%       quickSimEnv({'drive_cycle.mat', 'calib_params.m'})
%       quickSimEnv                     % new model + config, no data
%
%   Copy this file anywhere on the MATLAB path and call it; it has no
%   dependencies on other files in this repository.

    files = local_fileList(varargin);

    model = local_newModel();
    open_system(model);

    report = struct('model', model, ...
                    'loaded',  struct('name', {}, 'type', {}, 'vars', {}), ...
                    'skipped', struct('name', {}, 'reason', {}), ...
                    'config', '');

    for i = 1:numel(files)
        [ok, kind, vars, reason] = local_loadOne(files{i});
        if ok
            report.loaded(end+1) = struct('name', files{i}, 'type', kind, 'vars', {vars});
            fprintf('Loaded %d variable(s) from %s into base workspace.\n', ...
                    numel(vars), files{i});
        else
            report.skipped(end+1) = struct('name', files{i}, 'reason', reason);
            warning('quickSimEnv:skipped', 'Skipped %s: %s', files{i}, reason);
        end
    end

    report.config = local_attachWorkspaceConfig(model);

    if nargout == 0
        fprintf('%s: %d file(s) loaded, %d skipped, config %s.\n', ...
                model, numel(report.loaded), numel(report.skipped), ...
                local_configText(report.config));
        clear model report;
    end
end

% -------------------------------------------------------------------------
function files = local_fileList(args)
    % Flatten the argument list: char names, string arrays and nested cells.
    files = {};
    for i = 1:numel(args)
        a = args{i};
        if isempty(a)
            continue;   % '' or {} means "no data file", not an error
        elseif ischar(a)
            files{end+1} = a; %#ok<AGROW>
        elseif isa(a, 'string')
            files = [files, cellstr(reshape(a, 1, []))]; %#ok<AGROW>
        elseif iscell(a)
            files = [files, local_fileList(a)]; %#ok<AGROW>
        else
            error('quickSimEnv:badArg', ...
                  'File names must be char, string, or cell arrays of those.');
        end
    end
end

% -------------------------------------------------------------------------
function name = local_newModel()
    % Mimic Ctrl+N: create a uniquely named empty model without asking for a name.
    base = 'untitled';
    name = base;
    k = 0;
    while exist(name, 'file') == 4 || bdIsLoaded(name)
        k = k + 1;
        name = sprintf('%s%d', base, k);
    end
    new_system(name, 'Model');
end

% -------------------------------------------------------------------------
function [ok, kind, vars, reason] = local_loadOne(fileName)
    ok = false;
    kind = '';
    vars = {};
    reason = '';

    [~, ~, ext] = fileparts(fileName);
    if ~isempty(ext) && ~any(strcmpi(ext, {'.mat', '.m'}))
        reason = sprintf('unsupported file type ''%s'' (.mat and .m only)', ext);
        return;
    end

    [fullPath, kind] = local_resolve(fileName);
    if isempty(fullPath)
        reason = 'file not found';
        return;
    end

    before = evalin('base', 'who');
    try
        if strcmp(kind, 'mat')
            vars = who('-file', fullPath);   % names without pulling the data twice
            evalin('base', sprintf('load(''%s'');', local_quote(fullPath)));
        else
            % Run in the base workspace so the script's variables land there.
            evalin('base', sprintf('run(''%s'');', local_quote(fullPath)));
            vars = setdiff(evalin('base', 'who'), before);
        end
    catch err
        kind = '';
        vars = {};
        reason = err.message;
        return;
    end
    vars = reshape(vars, 1, []);
    ok = true;
end

% -------------------------------------------------------------------------
function [fullPath, kind] = local_resolve(fileName)
    % Locate the file (as given, or by trying .mat then .m) and classify it.
    fullPath = '';
    kind = '';

    [~, ~, ext] = fileparts(fileName);
    if isempty(ext)
        candidates = {[fileName '.mat'], [fileName '.m']};
    else
        candidates = {fileName};
    end

    for i = 1:numel(candidates)
        p = local_fullPath(candidates{i});
        if ~isempty(p)
            [~, ~, e] = fileparts(candidates{i});
            fullPath = p;
            kind = lower(e(2:end));
            return;
        end
    end
end

% -------------------------------------------------------------------------
function p = local_fullPath(f)
    p = '';
    if exist(f, 'file') ~= 2
        return;
    end
    p = which(f);
    if ~isempty(p) && exist(p, 'file') == 2
        return;
    end
    % On disk but not resolvable through the MATLAB path (relative folder, say).
    [d, n, e] = fileparts(f);
    if isempty(d)
        d = pwd;
    end
    p = fullfile(d, [n e]);
end

% -------------------------------------------------------------------------
function s = local_quote(s)
    % Escape single quotes so the path survives being embedded in an eval string.
    s = strrep(s, '''', '''''');
end

% -------------------------------------------------------------------------
function varName = local_attachWorkspaceConfig(model)
    varName = local_findConfigVar();
    if isempty(varName)
        fprintf('No Simulink.ConfigSet found in base workspace; using default config.\n');
        return;
    end

    refName = 'CfgRef';
    csr = Simulink.ConfigSetRef;
    csr.Name = refName;
    csr.SourceName = varName;   % live link to the base workspace variable

    if ~isempty(getConfigSet(model, refName))
        detachConfigSet(model, refName);
    end
    attachConfigSet(model, csr, true);
    setActiveConfigSet(model, refName);
    fprintf('Linked config ''%s'' from base workspace to %s.\n', varName, model);
end

% -------------------------------------------------------------------------
function varName = local_findConfigVar()
    % First base workspace variable holding a config set (or config reference).
    varName = '';
    vars = evalin('base', 'whos');
    for i = 1:numel(vars)
        if any(strcmp(vars(i).class, {'Simulink.ConfigSet', 'Simulink.ConfigSetRef'}))
            varName = vars(i).name;
            return;
        end
    end
end

% -------------------------------------------------------------------------
function txt = local_configText(varName)
    if isempty(varName)
        txt = 'default';
    else
        txt = sprintf('''%s''', varName);
    end
end
