function model = quickSimEnv(dataFile)
%QUICKSIMENV Spin up a fresh model, load a data .mat, and grab a config set from the workspace.
%
%   Fast pre-run setup in one call:
%     1. Creates a new empty model and opens it (like Ctrl+N).
%     2. Loads the .mat you name into the base workspace.
%     3. Scans the base workspace for a Simulink.ConfigSet and links it to the
%        new model as the active configuration (a config reference, so the model
%        stays in sync with the workspace variable).
%
%   MODEL = QUICKSIMENV(DATAFILE)
%       DATAFILE   name/path of a .mat file whose variables are pushed into the
%                  base workspace. Omit or pass '' to skip data loading.
%   MODEL is the name of the new model.
%
%   The config set is found automatically: the first base workspace variable of
%   class Simulink.ConfigSet (or Simulink.ConfigSetRef) is used. If none exists,
%   the model keeps its default configuration and a note is printed.
%
%   Examples:
%       quickSimEnv('drive_cycle.mat')
%       quickSimEnv                     % new model + config, no data
%
%   Copy this file anywhere on the MATLAB path and call it; it has no
%   dependencies on other files in this repository.

    if nargin < 1
        dataFile = '';
    end

    model = local_newModel();
    open_system(model);

    if ~isempty(dataFile)
        local_loadData(dataFile);
    end

    local_attachWorkspaceConfig(model);

    if nargout == 0
        clear model;
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
function local_loadData(dataFile)
    if exist(dataFile, 'file') ~= 2
        error('quickSimEnv:noData', 'Data file not found: %s', dataFile);
    end
    S = load(dataFile);
    names = fieldnames(S);
    for i = 1:numel(names)
        assignin('base', names{i}, S.(names{i}));
    end
    fprintf('Loaded %d variable(s) from %s into base workspace.\n', ...
            numel(names), dataFile);
end

% -------------------------------------------------------------------------
function local_attachWorkspaceConfig(model)
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
