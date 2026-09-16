function result = checkForbiddenBlocks(modelName, opts)
%CHECKFORBIDDENBLOCKS Check a Simulink model for blocks prohibited by JSON rules.
%
%   RESULT = CHECKFORBIDDENBLOCKS() checks the current model.
%   RESULT = CHECKFORBIDDENBLOCKS(MODELNAME) checks MODELNAME and, by
%            default, every referenced model that can be resolved.
%   RESULT = CHECKFORBIDDENBLOCKS(MODELNAME, OPTS) overrides settings from
%            forbidden_blocks.json with an options struct:
%
%     .followLinks           (true)  inspect blocks under library links
%     .lookUnderMasks        ('all') inspect blocks under masks
%     .checkReferencedModels (true)  also inspect referenced models
%     .failOnWarning         (false) treat warnings as a failed check
%     .verbose               (false) print every violation and its reason
%
%   RESULT contains Model, ConfigFile, ModelsChecked, Passed, ErrorCount,
%   WarningCount, and a Violations table. A failed check throws
%   BlockChecker:Failed after building and printing the report so a CI or
%   code-generation pipeline stops immediately.
%
%   Rules may match BlockType, MaskType, ReferenceBlock, a regular
%   expression for ReferenceBlock, block path, or block name. Multiple match
%   fields in one rule use AND logic. A matched block is downgraded to a
%   warning when it is commented, is inside a commented subsystem, or every
%   output is connected only to Terminator blocks.
%
%   Example:
%     result = checkForbiddenBlocks('EVCC_ChargeCtrl');
%     result = checkForbiddenBlocks('EVCC_ChargeCtrl', ...
%         struct('checkReferencedModels', false, 'verbose', true));
%
%   Copy this file together with forbidden_blocks.json anywhere on the
%   MATLAB path and call it; it has no dependencies on other files in this
%   repository.

    if nargin < 1 || isempty(modelName)
        modelName = bdroot(gcs);
        if isempty(modelName)
            error('BlockChecker:ModelRequired', ...
                'Open a model or provide a model name.');
        end
    end
    if nargin < 2
        opts = struct();
    end

    toolDir = fileparts(mfilename('fullpath'));
    configFile = fullfile(toolDir, 'forbidden_blocks.json');
    config = local_readConfig(configFile);
    opts = local_defaults(opts, config);

    rootModel = char(modelName);
    if endsWith(rootModel, '.slx', 'IgnoreCase', true)
        rootModel = rootModel(1:end - 4);
    end
    if ~bdIsLoaded(rootModel)
        try
            load_system(rootModel);
        catch exc
            error('BlockChecker:ModelLoad', ...
                'Cannot load model ''%s''.%s%s', ...
                rootModel, newline, exc.message);
        end
    end

    modelsToCheck = local_collectModels(rootModel, ...
        opts.checkReferencedModels);
    violations = local_emptyViolations();
    followLinks = 'off';
    if opts.followLinks
        followLinks = 'on';
    end

    for modelIndex = 1:numel(modelsToCheck)
        currentModel = modelsToCheck{modelIndex};
        if ~bdIsLoaded(currentModel)
            try
                load_system(currentModel);
            catch exc
                error('BlockChecker:ModelLoad', ...
                    'Cannot load model ''%s''.%s%s', ...
                    currentModel, newline, exc.message);
            end
        end

        blocks = find_system(currentModel, ...
            'FollowLinks', followLinks, ...
            'LookUnderMasks', opts.lookUnderMasks, ...
            'Type', 'Block');

        for blockIndex = 1:numel(blocks)
            block = blocks{blockIndex};
            for ruleIndex = 1:numel(config.rules)
                rule = config.rules(ruleIndex);
                if local_isRuleEnabled(rule) && local_matchesRule(block, rule)
                    severity = upper(local_getRuleText( ...
                        rule, 'severity', 'ERROR'));
                    [downgrade, note] = local_shouldDowngrade(block);
                    if downgrade
                        severity = 'WARNING';
                    end

                    violation = struct( ...
                        'Model', currentModel, ...
                        'Block', block, ...
                        'BlockType', local_safeGetParam(block, 'BlockType'), ...
                        'MaskType', local_safeGetParam(block, 'MaskType'), ...
                        'ReferenceBlock', local_safeGetParam( ...
                            block, 'ReferenceBlock'), ...
                        'RuleID', local_getRuleText( ...
                            rule, 'id', 'UNKNOWN'), ...
                        'Severity', severity, ...
                        'Message', local_getRuleText(rule, 'message', ...
                            'Forbidden block detected.'), ...
                        'Note', note);
                    violations(end + 1) = violation; %#ok<AGROW>
                end
            end
        end
    end

    if isempty(violations)
        violationTable = table();
    else
        violationTable = struct2table(violations);
    end

    errorCount = local_countSeverity(violationTable, 'ERROR');
    warningCount = local_countSeverity(violationTable, 'WARNING');
    passed = errorCount == 0 && (~opts.failOnWarning || warningCount == 0);

    result = struct( ...
        'Model', rootModel, ...
        'ConfigFile', configFile, ...
        'ModelsChecked', {modelsToCheck}, ...
        'Passed', passed, ...
        'ErrorCount', errorCount, ...
        'WarningCount', warningCount, ...
        'Violations', violationTable);

    if opts.verbose
        local_printViolations(result);
    end
    if nargout == 0 || ~result.Passed
        fprintf('Forbidden block check: %s (%d errors, %d warnings, %d models).\n', ...
            local_passText(result.Passed), result.ErrorCount, ...
            result.WarningCount, numel(result.ModelsChecked));
    end

    if ~result.Passed
        error('BlockChecker:Failed', ...
            ['Forbidden block check failed with %d error(s) and ' ...
            '%d warning(s). Code generation is not allowed.'], ...
            result.ErrorCount, result.WarningCount);
    end
end

function config = local_readConfig(configFile)
    if ~isfile(configFile)
        error('BlockChecker:ConfigNotFound', ...
            'Config file not found:%s%s', newline, configFile);
    end
    try
        config = jsondecode(fileread(configFile));
    catch exc
        error('BlockChecker:InvalidConfig', ...
            'Cannot read config file:%s%s%s%s', ...
            newline, configFile, newline, exc.message);
    end
    if ~isfield(config, 'rules') || ~isstruct(config.rules)
        error('BlockChecker:InvalidConfig', ...
            'Config file must contain a JSON array named "rules".');
    end
end

function opts = local_defaults(opts, config)
    defaults = struct( ...
        'followLinks', local_getSetting(config, 'followLinks', true), ...
        'lookUnderMasks', local_getSetting( ...
            config, 'lookUnderMasks', 'all'), ...
        'checkReferencedModels', local_getSetting( ...
            config, 'checkReferencedModels', true), ...
        'failOnWarning', local_getSetting( ...
            config, 'failOnWarning', false), ...
        'verbose', local_getSetting(config, 'verbose', false));
    fields = fieldnames(defaults);
    for i = 1:numel(fields)
        field = fields{i};
        if ~isfield(opts, field) || isempty(opts.(field))
            opts.(field) = defaults.(field);
        end
    end
    opts.lookUnderMasks = char(opts.lookUnderMasks);
end

function value = local_getSetting(config, name, defaultValue)
    value = defaultValue;
    if isfield(config, 'settings') && isfield(config.settings, name)
        value = config.settings.(name);
    end
end

function models = local_collectModels(rootModel, checkReferencedModels)
    models = {rootModel};
    if ~checkReferencedModels
        return;
    end
    try
        referencedModels = find_mdlrefs(rootModel);
        referencedModels = cellstr(string(referencedModels));
        for i = 1:numel(referencedModels)
            if endsWith(referencedModels{i}, '.slx', 'IgnoreCase', true)
                referencedModels{i} = referencedModels{i}(1:end - 4);
            end
        end
        models = unique([{rootModel}; referencedModels(:)], 'stable');
    catch exc
        warning('BlockChecker:ReferencedModel', ...
            'Could not resolve referenced models: %s', exc.message);
    end
end

function violations = local_emptyViolations()
    violations = struct( ...
        'Model', {}, ...
        'Block', {}, ...
        'BlockType', {}, ...
        'MaskType', {}, ...
        'ReferenceBlock', {}, ...
        'RuleID', {}, ...
        'Severity', {}, ...
        'Message', {}, ...
        'Note', {});
end

function enabled = local_isRuleEnabled(rule)
    enabled = ~isfield(rule, 'enabled') || rule.enabled;
end

function matched = local_matchesRule(block, rule)
    if ~isfield(rule, 'match')
        matched = false;
        return;
    end

    fields = fieldnames(rule.match);
    matched = true;
    for i = 1:numel(fields)
        field = fields{i};
        expected = rule.match.(field);
        switch field
            case 'BlockType'
                actual = local_safeGetParam(block, 'BlockType');
                matched = local_valueMatches(actual, expected);
            case 'MaskType'
                actual = local_safeGetParam(block, 'MaskType');
                matched = local_valueMatches(actual, expected);
            case 'ReferenceBlock'
                actual = local_safeGetParam(block, 'ReferenceBlock');
                matched = local_valueMatches(actual, expected);
            case 'ReferenceBlockRegex'
                actual = local_safeGetParam(block, 'ReferenceBlock');
                matched = local_regexMatches(actual, expected);
            case 'PathRegex'
                matched = local_regexMatches(block, expected);
            case 'NameRegex'
                actual = local_safeGetParam(block, 'Name');
                matched = local_regexMatches(actual, expected);
            otherwise
                warning('BlockChecker:UnknownRule', ...
                    'Unknown rule match field: %s', field);
                matched = false;
        end
        if ~matched
            return;
        end
    end
end

function matched = local_valueMatches(actual, expected)
    matched = any(strcmp(char(actual), local_toCellstr(expected)));
end

function matched = local_regexMatches(actual, patterns)
    patterns = local_toCellstr(patterns);
    matched = false;
    for i = 1:numel(patterns)
        if ~isempty(regexp(char(actual), patterns{i}, 'once'))
            matched = true;
            return;
        end
    end
end

function values = local_toCellstr(value)
    values = cellstr(string(value));
end

function value = local_safeGetParam(block, parameter)
    try
        value = char(string(get_param(block, parameter)));
    catch
        value = '';
    end
end

function value = local_getRuleText(rule, name, defaultValue)
    value = defaultValue;
    if isfield(rule, name)
        value = char(string(rule.(name)));
    end
end

function [downgrade, note] = local_shouldDowngrade(block)
    downgrade = false;
    note = '';
    if local_isEffectivelyCommented(block)
        downgrade = true;
        note = 'Severity downgraded because block is commented.';
    elseif local_isOutputOnlyToTerminators(block)
        downgrade = true;
        note = ['Severity downgraded because all block outputs are ' ...
            'connected only to Terminator blocks.'];
    end
end

function commented = local_isEffectivelyCommented(block)
    commented = false;
    currentBlock = block;
    while ~isempty(currentBlock)
        commentState = local_safeGetParam(currentBlock, 'Commented');
        if any(strcmpi(commentState, {'on', 'through'}))
            commented = true;
            return;
        end
        try
            parent = get_param(currentBlock, 'Parent');
        catch
            return;
        end
        if isempty(parent) || strcmp(parent, currentBlock)
            return;
        end
        currentBlock = parent;
    end
end

function terminated = local_isOutputOnlyToTerminators(block)
    terminated = false;
    try
        portHandles = get_param(block, 'PortHandles');
    catch
        return;
    end
    if ~isfield(portHandles, 'Outport') || isempty(portHandles.Outport)
        return;
    end

    foundConnection = false;
    for i = 1:numel(portHandles.Outport)
        try
            lineHandle = get_param(portHandles.Outport(i), 'Line');
            if isempty(lineHandle) || any(lineHandle == -1)
                return;
            end
            destinationBlocks = get_param(lineHandle, 'DstBlockHandle');
            if isempty(destinationBlocks) || any(destinationBlocks == -1)
                return;
            end
        catch
            return;
        end

        foundConnection = true;
        for j = 1:numel(destinationBlocks)
            try
                blockType = get_param(destinationBlocks(j), 'BlockType');
            catch
                return;
            end
            if ~strcmp(blockType, 'Terminator')
                return;
            end
        end
    end
    terminated = foundConnection;
end

function count = local_countSeverity(tbl, severity)
    if isempty(tbl)
        count = 0;
    else
        count = sum(strcmpi(tbl.Severity, severity));
    end
end

function local_printViolations(result)
    if isempty(result.Violations)
        fprintf('No forbidden blocks found.\n');
        return;
    end
    for i = 1:height(result.Violations)
        row = result.Violations(i, :);
        fprintf('[%s] %s | %s\n', ...
            row.Severity{1}, row.RuleID{1}, row.Block{1});
        fprintf('       Reason: %s\n', row.Message{1});
        if ~isempty(row.Note{1})
            fprintf('       Note: %s\n', row.Note{1});
        end
    end
end

function text = local_passText(passed)
    if passed
        text = 'PASS';
    else
        text = 'FAIL';
    end
end
