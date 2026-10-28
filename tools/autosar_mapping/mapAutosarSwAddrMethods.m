function report = mapAutosarSwAddrMethods(model, source, opts)
%MAPAUTOSARSWADDRMETHODS Manage SwAddrMethods by model/type (version 1.3.1).
%   REPORT = mapAutosarSwAddrMethods(MODEL, CSVFILE) previews all existing
%   explicit AUTOSAR mappings covered by the model's rules. Pass [] as MODEL
%   to use the current model. MODEL must already be loaded. SOURCE can also
%   be a rules table; see readAutosarMappingRules.
%
%   REPORT = mapAutosarSwAddrMethods(MODEL, SOURCE, OPTS) accepts:
%     Mode  'preview' (default) or 'apply'. Apply changes in memory only;
%           explicitly save the model yourself after reviewing the result.
%
%   Rules have columns Model, Type, SwAddrMethod. Each model/type has one
%   rule. Types: Runnable, RunnableInternalData, ConstantMemory,
%   SharedParameter, StaticMemory, ArTypedPerInstanceMemory. StaticMemory and
%   ArTypedPerInstanceMemory span signals, states, and Data Store Memory blocks.
%   Only existing mappings are updated; Auto and unconfigured types remain
%   unchanged and appear in REPORT.Elements. References are not traversed.
%   Initialize/terminate/reset entry points have no configurable internal-data
%   SwAddrMethod; their RunnableInternalData rows are explicitly ignored.
%
%   SwAddrMethods must already exist with unique SHORT-NAMEs. Preflight
%   checks all selected rules and snapshots before any write. Runnable
%   internal data requires GroupInternalDataByFunction='on'. Failed writes
%   attempt to restore every attempted SwAddrMethod and the original dirty
%   flag. Rollback failures are included in the thrown exception.
%
%   REPORT.Elements lists Category, Element, Type, Current, Desired, Status,
%   and Reason. Current is the pre-apply value. Status is Change, Unchanged,
%   Applied, Ignored, or Unconfigured. REPORT.Rules includes Matched counts.
%   Changes appear first, ignored/unconfigured rows next, unchanged rows last;
%   the original order is preserved within each group.
%   REPORT.Compliant requires every rule to match at least one element and
%   every configured element to have the desired value. Auto is excluded.
%
%   Example:
%     r = mapAutosarSwAddrMethods('MotorCtrl', 'legacy_mapping.csv');
%     disp(r.Elements)
%     r = mapAutosarSwAddrMethods('MotorCtrl', 'legacy_mapping.csv', ...
%         struct('Mode', 'apply'));
%     save_system('MotorCtrl'); % Explicit persistence, after review.
%
%   Dependencies: MATLAB/Simulink R2024a+, AUTOSAR Blockset, an existing
%   AUTOSAR Classic component mapping. No model compilation or codegen.
%   Does not set R2026b InternalData/Constants defaults, create methods,
%   convert Auto mappings, or add unregistered signals to code mappings.

    if nargin < 3, opts = struct(); end
    if ~isstruct(opts) || ~isscalar(opts) || any(~ismember(fieldnames(opts), {'Mode'}))
        error('AutosarMapping:Options', 'opts must be a scalar struct with optional field Mode.');
    end
    if ~isfield(opts, 'Mode'), opts.Mode = 'preview'; end
    mode = validatestring(opts.Mode, {'preview', 'apply'}, mfilename, 'opts.Mode');
    rules = readAutosarMappingRules(source);
    if isempty(model), model = bdroot; end
    try
        model = get_param(bdroot(model), 'Name');
    catch cause
        failure = MException('AutosarMapping:Model', 'Specify an already loaded model.');
        throwAsCaller(addCause(failure, cause));
    end
    if ~bdIsLoaded(model) || ~strcmp(get_param(model, 'BlockDiagramType'), 'model')
        error('AutosarMapping:Model', 'Specify an already loaded model, not a library.');
    end
    selected = rules(rules.Model == string(model), :);
    if isempty(selected)
        error('AutosarMapping:MissingModelRule', 'No mapping rules for model %s.', model);
    end
    if ~strcmp(get_param(model, 'SimulationStatus'), 'stopped')
        error('AutosarMapping:ModelBusy', 'Stop simulation before managing AUTOSAR mappings.');
    end
    if strcmp(get_param(model, 'Lock'), 'on')
        error('AutosarMapping:ModelLocked', 'Unlock the model before managing AUTOSAR mappings.');
    end
    mapping = autosar.api.getSimulinkMapping(model);
    properties = autosar.api.getAUTOSARProperties(model);
    local_validateMethods(properties, selected);
    if any(selected.Type == "RunnableInternalData") && ...
            ~strcmp(get_param(model, 'GroupInternalDataByFunction'), 'on')
        error('AutosarMapping:InternalDataGrouping', ...
            'RunnableInternalData requires GroupInternalDataByFunction=''on'' in model %s.', model);
    end
    operations = local_inventory(mapping);
    elements = array2table(strings(numel(operations), 7), ...
        'VariableNames', {'Category', 'Element', 'Type', 'Current', 'Desired', 'Status', 'Reason'});
    matched = zeros(height(selected), 1);
    for k = 1:numel(operations)
        op = operations(k);
        elements{k, 1:4} = [op.Category, op.Label, op.Type, op.Current];
        index = find(selected.Type == op.Type);
        if ~op.Eligible
            elements.Status(k) = "Ignored";
            elements.Reason(k) = "Internal-data SwAddrMethod is unavailable for this entry point.";
        elseif op.Type == "Auto"
            elements.Status(k) = "Ignored";
            elements.Reason(k) = "Auto mapping has no explicit SwAddrMethod.";
        elseif isempty(index)
            elements.Status(k) = "Unconfigured";
            elements.Reason(k) = "No rule for this mapping type.";
        else
            matched(index) = matched(index) + 1;
            elements.Desired(k) = selected.SwAddrMethod(index);
            elements.Status(k) = "Unchanged";
            if op.Current ~= elements.Desired(k)
                elements.Status(k) = "Change";
            end
        end
    end
    selected.Matched = matched;
    changed = find(elements.Status == "Change");
    if strcmp(mode, 'apply') && ~isempty(changed)
        autosarMapping.applyChanges(model, elements, ...
            @(k) local_read(mapping, operations(k)), ...
            @(k, value) local_write(mapping, operations(k), value));
        elements.Status(changed) = "Applied";
    end
    elements = autosarMapping.sortReportElements(elements);
    report = struct('Model', string(model), 'Mode', string(mode), 'Rules', selected, ...
        'Elements', elements, 'Changed', numel(changed), 'Applied', 0, ...
        'Compliant', ~any(elements.Status == "Change") && all(matched > 0));
    if strcmp(mode, 'apply'), report.Applied = numel(changed); end
    if nargout == 0
        fprintf('AUTOSAR mapping [%s] %s: %d changes, %d applied, %d unmatched rules.\n', ...
            mode, model, report.Changed, report.Applied, sum(matched == 0));
        disp(elements);
    end
end

function local_validateMethods(properties, rules)
    paths = string(properties.find([], 'SwAddrMethod', 'PathType', 'FullyQualified'));
    names = regexprep(paths, '^.*/', '');
    for k = 1:height(rules)
        index = find(names == rules.SwAddrMethod(k));
        if numel(index) ~= 1
            error('AutosarMapping:MethodResolution', ...
                'SwAddrMethod %s must exist exactly once in the model (found %d).', ...
                rules.SwAddrMethod(k), numel(index));
        end
        section = string(properties.get(char(paths(index)), 'SectionType'));
        switch rules.Type(k)
            case "Runnable"
                allowed = "Code";
            case "RunnableInternalData"
                allowed = "Var";
            case "ConstantMemory"
                allowed = "Const";
            case "SharedParameter"
                allowed = ["Const", "Calprm"];
            otherwise
                allowed = "Var";
        end
        if ~any(strcmpi(section, allowed))
            error('AutosarMapping:SectionType', ...
                '%s uses %s (SectionType=%s); expected %s.', rules.Type(k), ...
                rules.SwAddrMethod(k), section, strjoin(allowed, ' or '));
        end
    end
end

function operations = local_inventory(mapping)
    template = struct('Category', "", 'Target', [], 'Label', "", 'Type', "", ...
        'Current', "", 'Role', "", 'Property', 'SwAddrMethod', 'Eligible', true);
    operations = repmat(template, 0, 1);
    categories = {'Functions', 'ModelParameters', 'Signals', 'States', 'DataStores'};
    for c = 1:numel(categories)
        category = categories{c};
        targets = mapping.find(category);
        for k = 1:numel(targets)
            if iscell(targets), target = targets{k}; else, target = targets(k); end
            if isstring(target), target = char(target); end
            op = template;
            op.Category = string(category);
            op.Target = target;
            if strcmp(category, 'Signals')
                op.Label = string(getfullname(get_param(target, 'Parent'))) + ...
                    ":" + string(get_param(target, 'PortNumber'));
            elseif isnumeric(target)
                op.Label = string(getfullname(target));
            else
                op.Label = string(target);
            end
            if strcmp(category, 'Functions')
                [runnable, code, data] = mapping.getFunction(target);
                op.Role = string(runnable);
                op.Type = "Runnable";
                op.Current = local_normalize(code);
                operations(end + 1, 1) = op; %#ok<AGROW>
                op.Type = "RunnableInternalData";
                op.Property = 'SwAddrMethodForInternalData';
                op.Current = local_normalize(data);
                op.Eligible = strcmp(target, 'Periodic') || ...
                    startsWith(target, {'Periodic:', 'Partition:', 'ExportedFunction:', 'SimulinkFunction:'});
            else
                op.Role = string(local_getData(mapping, op, ''));
                op.Type = op.Role;
                if op.Type ~= "Auto"
                    op.Current = local_normalize(local_getData(mapping, op, 'SwAddrMethod'));
                end
            end
            operations(end + 1, 1) = op; %#ok<AGROW>
        end
    end
end

function value = local_getData(mapping, op, property)
    args = {op.Target};
    if op.Category == "States", args{end + 1} = ''; end
    if ~isempty(property), args{end + 1} = property; end
    switch op.Category
        case "ModelParameters", value = mapping.getParameter(args{:});
        case "Signals", value = mapping.getSignal(args{:});
        case "States", value = mapping.getState(args{:});
        case "DataStores", value = mapping.getDataStore(args{:});
    end
end

function value = local_read(mapping, op)
    if op.Category == "Functions"
        [~, code, data] = mapping.getFunction(op.Target);
        if op.Type == "Runnable", value = code; else, value = data; end
    else
        value = local_getData(mapping, op, op.Property);
    end
    value = local_normalize(value);
end

function local_write(mapping, op, value)
    value = char(value);
    if op.Category == "Functions"
        if isempty(value), value = '<None>'; end
        mapping.mapFunction(op.Target, char(op.Role), op.Property, value);
        return;
    end
    args = {op.Target};
    if op.Category == "States", args{end + 1} = ''; end
    args = [args, {char(op.Role), op.Property, value}];
    switch op.Category
        case "ModelParameters", mapping.mapParameter(args{:});
        case "Signals", mapping.mapSignal(args{:});
        case "States", mapping.mapState(args{:});
        case "DataStores", mapping.mapDataStore(args{:});
    end
end

function value = local_normalize(value)
    value = string(value);
    if ismissing(value) || value == "<None>", value = ""; end
end
