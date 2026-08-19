function quickSimEnv(model, dataFile, configVar, opts)
%QUICKSIMENV Load a data .mat into the base workspace and link a config set to a model.
%
%   Fast one-call setup before hitting "Run": drop your simulation data into the
%   base workspace and attach a configuration set that stays *linked* to a
%   workspace variable (a config reference), so editing the variable keeps the
%   model in sync instead of baking in a private copy.
%
%   QUICKSIMENV(MODEL, DATAFILE, CONFIGVAR)
%       MODEL      model name or handle. Opened (load_system) if not loaded.
%       DATAFILE   path to a .mat file; every variable in it is pushed into the
%                  base workspace. Pass '' to skip data loading.
%       CONFIGVAR  name of a Simulink.ConfigSet variable already in the base
%                  workspace, to attach to MODEL. Pass '' to skip config setup.
%
%   QUICKSIMENV(..., OPTS) with an options struct:
%       .link       logical (default true)   true attaches a Simulink.ConfigSetRef
%                   pointing at CONFIGVAR (stays linked); false attaches a copy
%                   of the ConfigSet itself.
%       .refName    char   (default 'CfgRef') name of the attached config set.
%       .makeActive logical (default true)    make the attached config active.
%       .overwrite  logical (default true)    overwrite base workspace variables
%                   that collide with names in DATAFILE.
%
%   Examples:
%       quickSimEnv('myPlant', 'stimuli/drive_cycle.mat', 'simCfg')
%       quickSimEnv(gcs, 'io.mat', 'cfg', struct('link', false))
%
%   Copy this file anywhere on the MATLAB path and call it; it has no
%   dependencies on other files in this repository.

    if nargin < 1 || isempty(model)
        model = bdroot(gcs);
    end
    if nargin < 2, dataFile = ''; end
    if nargin < 3, configVar = ''; end
    if nargin < 4, opts = struct(); end
    opts = local_defaults(opts);

    modelName = local_ensureLoaded(model);

    if ~isempty(dataFile)
        local_loadData(dataFile, opts.overwrite);
    end

    if ~isempty(configVar)
        local_attachConfig(modelName, configVar, opts);
    end
end

% -------------------------------------------------------------------------
function opts = local_defaults(opts)
    defaults = struct('link', true, 'refName', 'CfgRef', ...
                      'makeActive', true, 'overwrite', true);
    fn = fieldnames(defaults);
    for i = 1:numel(fn)
        if ~isfield(opts, fn{i}) || isempty(opts.(fn{i}))
            opts.(fn{i}) = defaults.(fn{i});
        end
    end
end

% -------------------------------------------------------------------------
function modelName = local_ensureLoaded(model)
    if ischar(model) || isstring(model)
        modelName = char(model);
    else
        modelName = get_param(model, 'Name');
    end
    if isempty(modelName)
        error('quickSimEnv:noModel', 'No model given and no current system.');
    end
    if ~bdIsLoaded(modelName)
        load_system(modelName);
    end
end

% -------------------------------------------------------------------------
function local_loadData(dataFile, overwrite)
    if exist(dataFile, 'file') ~= 2
        error('quickSimEnv:noData', 'Data file not found: %s', dataFile);
    end
    S = load(dataFile);
    names = fieldnames(S);
    for i = 1:numel(names)
        if ~overwrite && evalin('base', sprintf('exist(''%s'', ''var'')', names{i}))
            continue;
        end
        assignin('base', names{i}, S.(names{i}));
    end
    fprintf('Loaded %d variable(s) from %s into base workspace.\n', ...
            numel(names), dataFile);
end

% -------------------------------------------------------------------------
function local_attachConfig(modelName, configVar, opts)
    if ~evalin('base', sprintf('exist(''%s'', ''var'')', configVar))
        error('quickSimEnv:noConfigVar', ...
              'Config variable ''%s'' not found in base workspace.', configVar);
    end

    if opts.link
        csObj = Simulink.ConfigSetRef;
        csObj.Name = opts.refName;
        csObj.SourceName = configVar;   % live link to the base workspace variable
    else
        csObj = copy(evalin('base', configVar));
        csObj.Name = opts.refName;
    end

    % Replace an existing config set of the same name before attaching.
    existing = getConfigSet(modelName, opts.refName);
    if ~isempty(existing)
        detachConfigSet(modelName, opts.refName);
    end
    attachConfigSet(modelName, csObj, true);

    if opts.makeActive
        setActiveConfigSet(modelName, opts.refName);
    end
    fprintf('Attached config ''%s'' (%s) to %s.\n', opts.refName, ...
            ternary(opts.link, 'linked', 'copy'), modelName);
end

% -------------------------------------------------------------------------
function out = ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end
