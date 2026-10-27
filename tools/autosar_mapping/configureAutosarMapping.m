function report = configureAutosarMapping(model, source, opts)
%CONFIGUREAUTOSARMAPPING Configure AUTOSAR Classic Code Mappings (v1.3.0).
%   REPORT = configureAutosarMapping(MODEL, CSVFILE) previews property rules
%   with columns Model,Category,Element,Property,Value. This single CSV also
%   manages SwAddrMethod. SOURCE can be a table.
%   MODEL must be loaded; [] selects the current model. Requires R2024a+,
%   Simulink and AUTOSAR Blockset. See exportAutosarMapping for identifiers.
%
%   OPTS.Mode is 'preview' (default) or 'apply'. Apply changes only in memory.
%   OPTS.CalibrationConfig selects the global calibration JSON; default is
%   the adjacent autosar_calibration_config.json. Pass '' to disable it.
%   IncludePatterns defaults to empty. Pass SOURCE=[] for calibration only.
%   Global calibration defaults apply by parameter name; explicit CSV fields
%   take precedence. Element='calibration:*' selects globally matching names.
%   OPTS.ExpectedSnapshot can be a previous preview's Snapshot to reject
%   changed model/config inputs before applying (used by autosarMappingGui).
%   All changes to one element are written together so coupled properties
%   (port/data element, memory type/attributes) never depend on CSV row order.
%   Defaults are applied before element mappings. Failure restores attempted
%   changed settings and registration if a native setter fails.
%
%   Categories: Inports, Outports, Functions, FunctionCallers, DataTransfers,
%   ModelParameters, ModelParameterArguments, Signals, States, DataStores,
%   SynthesizedDataStores, Defaults. Element can be an exported identifier,
%   '*' for a category, or 'type:StaticMemory' (or another current memory type).
%   'type?:StaticMemory' skips a missing type and reports it in SkippedRules.
%   Conflicting/overlapping rules and unmatched strict selectors are errors.
%
%   CSV properties include DataAccessMode (implicit/explicit/queued/E2E),
%   Port, DataElement, Runnable, Operation, InterRunnableVariable, MappedTo,
%   SwAddrMethod and native data attributes. Defaults use InternalData or
%   InportsOutports. Registered=true/false explicitly adds/removes Signals
%   or SynthesizedDataStores. Empty Value explicitly clears an attribute.
%   Unknown settings are errors. No config values are evaluated as MATLAB.
%
%   Preview checks schema, selectors, property applicability and scalar enums.
%   Native context restrictions (interface direction, queued/event semantics,
%   code generation constraints) are checked by the native setter on apply,
%   with readback and rollback; preview is not a code-generation validation.
%
%   Example:
%     rules = exportAutosarMapping('MotorCtrl');
%     r = configureAutosarMapping('MotorCtrl', 'code_mapping.csv');
%     r = configureAutosarMapping('MotorCtrl', 'code_mapping.csv', struct('Mode','apply'));
%     save_system('MotorCtrl'); % Explicit save after review.
    if nargin < 2, source = []; end
    if nargin < 3, opts = struct(); end
    if ~isstruct(opts) || ~isscalar(opts) || ...
            any(~ismember(fieldnames(opts), {'Mode', 'CalibrationConfig', 'ExpectedSnapshot'}))
        error('AutosarMapping:Options', 'opts accepts Mode, CalibrationConfig, ExpectedSnapshot.');
    end
    if ~isfield(opts, 'Mode'), opts.Mode = 'preview'; end
    if ~isfield(opts, 'CalibrationConfig')
        opts.CalibrationConfig = fullfile(fileparts(mfilename('fullpath')), 'autosar_calibration_config.json');
    end
    if ~isfield(opts, 'ExpectedSnapshot'), opts.ExpectedSnapshot = []; end
    mode = validatestring(opts.Mode, {'preview', 'apply'});
    config = readAutosarCalibrationConfig(opts.CalibrationConfig);
    adapter = autosarMapping.CodeMappingAdapter(model);
    if isempty(source) || (isstring(source) && isscalar(source) && strlength(source) == 0)
        rules = array2table(strings(0, 5), 'VariableNames', {'Model', 'Category', 'Element', 'Property', 'Value'});
    else
        rules = readAutosarCodeMappingRules(source);
        rules = rules(rules.Model == adapter.Model, :);
        if isempty(rules), error('AutosarMapping:MissingModelRule', 'No rules for %s.', adapter.Model); end
    end
    if strcmp(mode, 'apply') && strcmp(get_param(char(adapter.Model), 'Lock'), 'on')
        error('AutosarMapping:ModelLocked', 'Unlock the model before applying mappings.');
    end
    records = adapter.inventory();
    calibration = autosarMapping.calibrationMatches(records, config);
    before = cell(numel(records), 1);
    for k = 1:numel(records), before{k} = adapter.read(records(k)); end
    skippedRules = rules([],:);
    assignments = cell(numel(records), 1);
    for k = 1:numel(assignments), assignments{k} = struct(); end
    for row = 1:height(rules)
        category = rules.Category(row);
        element = rules.Element(row);
        scope = find([records.Category] == category);
        if element == "*"
            matches = scope;
        elseif element == "calibration:*"
            names = calibration.Element(calibration.Category == category);
            matches = scope(ismember(string([records(scope).Element]), names));
        elseif startsWith(element, "type:") || startsWith(element, "type?:")
            optional = startsWith(element, "type?:");
            if optional, role = extractAfter(element, 6);
            else, role = extractAfter(element, 5);
            end
            if category == "ModelParameters"
                validRoles = ["Auto", "SharedParameter", "ConstantMemory"];
            elseif category == "ModelParameterArguments"
                validRoles = ["Auto", "PerInstanceParameter", "PortParameter"];
            elseif any(category == ["Signals", "States", "DataStores", "SynthesizedDataStores"])
                validRoles = ["Auto", "StaticMemory", "ArTypedPerInstanceMemory"];
            else
                validRoles = strings(0, 1);
            end
            if ~any(role == validRoles)
                error('AutosarMapping:Value', 'Invalid mapping type selector %s for %s.', element, category);
            end
            matches = [];
            for k = scope
                if isfield(before{k}, 'MappedTo') && before{k}.MappedTo == role
                    matches(end + 1) = k; %#ok<AGROW>
                end
            end
            if isempty(matches) && optional
                skippedRules(end + 1, :) = rules(row, :); %#ok<AGROW>
                continue;
            end
        else
            matches = scope(string([records(scope).Element]) == element);
            if isempty(matches) && (any(category == ["Signals", "SynthesizedDataStores"]) || ...
                    (category == "States" && contains(element, "#")))
                records(end + 1, 1) = adapter.resolve(category, element); %#ok<AGROW>
                before{end + 1} = adapter.read(records(end)); %#ok<AGROW>
                assignments{end + 1} = struct(); %#ok<AGROW>
                matches = numel(records);
            end
        end
        if isempty(matches)
            error('AutosarMapping:UnmatchedRule', 'No %s element matches %s.', category, element);
        end
        for k = matches(:)'
            name = char(rules.Property(row));
            if isfield(assignments{k}, name)
                error('AutosarMapping:OverlappingRule', 'Overlapping rules for %s/%s/%s.', category, records(k).Element, name);
            end
            assignments{k}.(name) = rules.Value(row);
        end
    end
    origins = cell(numel(records), 1);
    for k = 1:numel(records)
        origins{k} = struct();
        index = find(calibration.Category == records(k).Category & calibration.Element == records(k).Element);
        if isempty(index), continue; end
        if isfield(assignments{k}, 'MappedTo') && assignments{k}.MappedTo == "Auto", continue; end
        defaults = struct('SwCalibrationAccess', config.SwCalibrationAccess);
        if before{k}.MappedTo == "Auto" || ~config.PreserveExplicitMappings
            if records(k).Category == "ModelParameters", defaults.MappedTo = config.ModelParameterMapping;
            else, defaults.MappedTo = config.ArgumentMapping;
            end
        end
        for name = string(fieldnames(defaults))'
            if ~isfield(assignments{k}, char(name))
                assignments{k}.(char(name)) = defaults.(char(name));
                origins{k}.(char(name)) = "Global calibration regexp: " + calibration.Pattern(index);
            end
        end
    end
    grouping = string(get_param(char(adapter.Model), 'GroupInternalDataByFunction'));
    for k = 1:numel(records)
        if records(k).Category == "Defaults" && records(k).Element == "InternalData" && ...
                isfield(assignments{k}, 'GroupInternalDataByFunction')
            grouping = assignments{k}.GroupInternalDataByFunction;
        end
    end
    for k = 1:numel(records)
        if isfield(assignments{k}, 'SwAddrMethodForInternalData') && ...
                assignments{k}.SwAddrMethodForInternalData ~= "" && grouping ~= "on"
            error('AutosarMapping:InternalDataGrouping', 'Runnable internal data requires GroupInternalDataByFunction=on.');
        end
    end
    plan = array2table(strings(0, 7), 'VariableNames', ...
        {'Category', 'Element', 'Property', 'Current', 'Desired', 'Status', 'Reason'});
    tasks = struct('Record', {}, 'Before', {}, 'After', {}, 'Changed', {});
    for k = 1:numel(records)
        edited = assignments{k};
        if isempty(fieldnames(edited)), continue; end
        after = autosarMapping.prepareCodeMapping(adapter, records(k), before{k}, edited);
        changed = false;
        for name = string(fieldnames(edited))'
            current = "";
            if isfield(before{k}, char(name)), current = before{k}.(char(name)); end
            desired = after.(char(name));
            status = "Unchanged";
            if current ~= desired, status = "Change"; changed = true; end
            reason = "";
            if isfield(origins{k}, char(name)), reason = origins{k}.(char(name)); end
            plan(end + 1, :) = {records(k).Category, records(k).Element, name, current, desired, status, reason}; %#ok<AGROW>
        end
        tasks(end + 1) = struct('Record', records(k), 'Before', before{k}, ...
            'After', after, 'Changed', changed); %#ok<AGROW>
    end
    changed = sum(plan.Status == "Change");
    snapshot = struct('Model', adapter.Model, 'Rules', rules, 'Calibration', config, ...
        'Records', records, 'Values', {before}, 'Plan', plan);
    if ~isempty(opts.ExpectedSnapshot) && ~isequaln(opts.ExpectedSnapshot, snapshot)
        error('AutosarMapping:StalePreview', 'Model or configuration changed after preview. Run Preview again.');
    end
    if strcmp(mode, 'apply') && changed > 0
        priority = arrayfun(@(t) t.Record.Category ~= "Defaults", tasks);
        [~, order] = sort(priority);
        autosarMapping.applyCodeMapping(adapter, tasks(order));
        plan.Status(plan.Status == "Change") = "Applied";
    end
    report = struct('Model', adapter.Model, 'Mode', string(mode), 'Elements', plan, ...
        'Changed', changed, 'Applied', sum(plan.Status == "Applied"), ...
        'Compliant', ~any(plan.Status == "Change"), 'CalibrationConfig', config.File, ...
        'CalibrationMatches', calibration, 'SkippedRules', skippedRules, 'Snapshot', snapshot);
    if nargout == 0
        fprintf('AUTOSAR Code Mappings [%s] %s: %d changes, %d applied.\n', ...
            mode, adapter.Model, changed, report.Applied);
        disp(plan);
    end
end
