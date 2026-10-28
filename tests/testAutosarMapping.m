function testAutosarMapping()
%TESTAUTOSARMAPPING Verify per-model/type SwAddrMethods on native mappings.
    previousPath = path;
    restorePath = onCleanup(@() path(previousPath));
    repo = fileparts(fileparts(mfilename('fullpath')));
    addpath(fullfile(repo, 'tools', 'autosar_mapping'));
    local_reportOrdering();
    sandbox = tempname;
    mkdir(sandbox);
    removeSandbox = onCleanup(@() rmdir(sandbox, 's'));
    [~, model] = fileparts(tempname);
    new_system(model);
    closeModel = onCleanup(@() close_system(model, 0));
    local_fixture(model);
    mapping = autosar.api.getSimulinkMapping(model);
    properties = autosar.api.getAUTOSARProperties(model);
    types = ["Runnable"; "RunnableInternalData"; "ConstantMemory"; ...
        "SharedParameter"; "StaticMemory"; "ArTypedPerInstanceMemory"];
    methods = ["AppCode"; "AppVar"; "AppConst"; "AppCal"; "AppVar"; "AppPim"];
    sections = ["Code"; "Var"; "Const"; "Calprm"; "Var"; "Var"];
    for k = [1:4, 6]
        properties.addPackageableElement('SwAddrMethod', '/Test/Sections', ...
            char(methods(k)), 'SectionType', char(sections(k)));
    end
    rules = table(repmat(string(model), 6, 1), types, methods, ...
        'VariableNames', {'Model', 'Type', 'SwAddrMethod'});
    other = rules;
    other.Model(:) = "OtherModel";
    other.SwAddrMethod(:) = "NotInThisModel";
    config = fullfile(sandbox, 'mapping.csv');
    writetable([rules; other], config, 'Encoding', 'UTF-8');
    imported = readAutosarMappingRules(config);
    assert(isequal(imported, [rules; other]));
    local_configErrors(rules, sandbox);

    saved = fullfile(sandbox, [model '.slx']);
    mapping.mapParameter('C', 'ConstantMemory', 'SwAddrMethod', 'AppConst');
    save_system(model, saved);
    fileBefore = local_bytes(saved);
    before = local_snapshot(mapping);
    preview = mapAutosarSwAddrMethods(model, config);
    assert(~preview.Compliant && preview.Changed >= 9 && preview.Applied == 0);
    assert(all(preview.Rules.Matched > 0));
    assert(any(preview.Elements.Status == "Ignored"));
    assert(any(preview.Elements.Status == "Unchanged"));
    local_assertOrder(preview.Elements);
    assert(strcmp(get_param(model, 'Dirty'), 'off'));
    assert(isequal(before, local_snapshot(mapping)));
    local_preflightErrors(model, rules, mapping, before);

    result = mapAutosarSwAddrMethods(model, config, struct('Mode', 'apply'));
    assert(result.Compliant && result.Applied == preview.Changed);
    assert(all(result.Elements.Status ~= "Change"));
    local_assertOrder(result.Elements);
    assert(strcmp(get_param(model, 'Dirty'), 'on'));
    assert(isequal(fileBefore, local_bytes(saved)), 'Apply must not save the model.');
    after = local_snapshot(mapping);
    assert(isequal(before.Preserved, after.Preserved), 'Unrelated mapping properties changed.');
    assert(all(after.Static == "AppVar") && all(after.Pim == "AppPim"));
    assert(all(after.Code == "AppCode") && all(after.Internal == "AppVar"));
    assert(after.Constant == "AppConst" && after.Parameter == "AppCal");
    assert(after.Auto == "Auto");

    repeated = mapAutosarSwAddrMethods(model, rules, struct('Mode', 'apply'));
    assert(repeated.Compliant && repeated.Applied == 0 && repeated.Changed == 0);
    subset = rules(rules.Type == "Runnable", :);
    limited = mapAutosarSwAddrMethods(model, subset);
    assert(limited.Compliant && any(limited.Elements.Status == "Unconfigured"));
    local_assertOrder(limited.Elements);
    byHandle = mapAutosarSwAddrMethods(get_param(model, 'Handle'), subset);
    assert(isequal(byHandle.Elements, limited.Elements));
    assert(isequal(after, local_snapshot(mapping)));
    unused = rules(1, :);
    unused.Type = "ConstantMemory";
    unused.SwAddrMethod = "AppConst";
    mapping.mapParameter('C', 'Auto');
    unmatched = mapAutosarSwAddrMethods(model, unused, struct('Mode', 'apply'));
    assert(~unmatched.Compliant && unmatched.Rules.Matched == 0 && unmatched.Applied == 0);
    mapping.mapParameter('C', 'ConstantMemory', 'SwAddrMethod', 'AppConst');

    % A second native model uses its own rule, even in a shared CSV/table.
    [~, second] = fileparts(tempname);
    new_system(second);
    closeSecond = onCleanup(@() close_system(second, 0));
    local_fixture(second);
    secondRule = table(string(second), "Runnable", "CODE", ...
        'VariableNames', {'Model', 'Type', 'SwAddrMethod'});
    secondResult = mapAutosarSwAddrMethods(second, [rules; secondRule], struct('Mode', 'apply'));
    assert(secondResult.Compliant && height(secondResult.Rules) == 1);
    assert(isequal(after, local_snapshot(mapping)));
    local_transactionTests(second);
    local_constantMemoryCalibration(model);
    fprintf('PASS: CSV validation, native mapping coverage, preflight, isolation, preservation, idempotence, no-save, rollback.\n');
end

function local_constantMemoryCalibration(model)
    mapping = autosar.api.getSimulinkMapping(model);
    before = local_snapshot(mapping);
    rules = table(string(model), "ConstantMemory", "AppCal", ...
        'VariableNames', {'Model', 'Type', 'SwAddrMethod'});
    preview = mapAutosarSwAddrMethods(model, rules);
    assert(preview.Changed == 1 && preview.Applied == 0 && isequal(before, local_snapshot(mapping)));
    result = mapAutosarSwAddrMethods(model, rules, struct('Mode', 'apply'));
    assert(result.Compliant && result.Applied == 1);
    assert(strcmp(mapping.getParameter('C'), 'ConstantMemory'));
    assert(strcmp(mapping.getParameter('C', 'SwAddrMethod'), 'AppCal'));
    after = local_snapshot(mapping);
    assert(isequal(before.Preserved, after.Preserved));
    assert(mapAutosarSwAddrMethods(model, rules, struct('Mode', 'apply')).Applied == 0);
    for method = ["AppCode", "AppVar"]
        bad = rules;
        bad.SwAddrMethod = method;
        local_expectError(@() mapAutosarSwAddrMethods(model, bad, struct('Mode', 'apply')), ...
            'AutosarMapping:SectionType');
        assert(isequal(after, local_snapshot(mapping)), 'Invalid section changed native mappings.');
    end
end

function local_reportOrdering()
    elements = table((1:8)', ["Unchanged"; "Ignored"; "Change"; "Unchanged"; ...
        "Applied"; "Unconfigured"; "Change"; "Ignored"], 'VariableNames', {'Id', 'Status'});
    sorted = autosarMapping.sortReportElements(elements);
    assert(isequal(sorted.Id, [3; 5; 7; 2; 6; 8; 1; 4]));
    assert(isequal(sorted, autosarMapping.sortReportElements(sorted)));
    assert(isequal(elements([], :), autosarMapping.sortReportElements(elements([], :))));
end

function local_assertOrder(elements)
    changed = ismember(elements.Status, ["Change", "Applied"]);
    priority = ones(height(elements), 1);
    priority(changed) = 0;
    priority(elements.Status == "Unchanged") = 2;
    assert(issorted(priority), 'Changes must appear first and unchanged rows last.');
end

function local_transactionTests(model)
    values = [""; "OldVar"];
    plan = table(["First"; "Second"], values, ["NewCode"; "NewVar"], ["Change"; "Change"], ...
        'VariableNames', {'Element', 'Current', 'Desired', 'Status'});
    failureMode = "write";
    set_param(model, 'Dirty', 'off');
    failure = local_expectError(@() autosarMapping.applyChanges(model, plan, @read, @write), ...
        'AutosarMapping:ApplyFailed');
    assert(isequal(values, plan.Current) && strcmp(get_param(model, 'Dirty'), 'off'));
    assert(strcmp(failure.cause{1}.identifier, 'Test:InjectedWrite'));
    failureMode = "readback";
    local_expectError(@() autosarMapping.applyChanges(model, plan, @read, @write), ...
        'AutosarMapping:ApplyFailed');
    assert(isequal(values, plan.Current) && strcmp(get_param(model, 'Dirty'), 'off'));
    failureMode = "write";
    set_param(model, 'Dirty', 'on');
    local_expectError(@() autosarMapping.applyChanges(model, plan, @read, @write), ...
        'AutosarMapping:ApplyFailed');
    assert(isequal(values, plan.Current) && strcmp(get_param(model, 'Dirty'), 'on'));
    failureMode = "rollback";
    set_param(model, 'Dirty', 'off');
    failure = local_expectError(@() autosarMapping.applyChanges(model, plan, @read, @write), ...
        'AutosarMapping:ApplyFailed');
    assert(numel(failure.cause) == 2 && strcmp(get_param(model, 'Dirty'), 'on'));
    assert(strcmp(failure.cause{2}.identifier, 'Test:InjectedRollback'));

    function value = read(index)
        value = values(index);
    end

    function write(index, value)
        set_param(model, 'Dirty', 'on');
        if failureMode == "rollback" && index == 1 && value == plan.Current(index)
            error('Test:InjectedRollback', 'Injected rollback failure.');
        end
        values(index) = value;
        if index == 2 && value == plan.Desired(index)
            if failureMode == "readback"
                values(index) = "WrongReadback";
            else
                error('Test:InjectedWrite', 'Injected failure after partial mutation.');
            end
        end
    end
end

function local_fixture(model)
    set_param(model, 'SystemTargetFile', 'autosar.tlc', ...
        'Solver', 'FixedStepDiscrete', 'FixedStep', '0.1', 'GroupInternalDataByFunction', 'on');
    add_block('simulink/Sources/Constant', [model '/Input'], 'Value', 'C');
    add_block('simulink/Discrete/Unit Delay', [model '/Delay']);
    add_block('simulink/Math Operations/Gain', [model '/Gain'], 'Gain', 'K');
    add_block('simulink/Math Operations/Gain', [model '/AutoGain'], 'Gain', 'AutoGain');
    add_block('simulink/Sinks/Terminator', [model '/End']);
    add_block('simulink/Signal Routing/Data Store Memory', [model '/Memory'], 'DataStoreName', 'Store');
    add_block('simulink/Signal Routing/Data Store Memory', [model '/PimMemory'], 'DataStoreName', 'PimStore');
    add_line(model, 'Input/1', 'Delay/1');
    add_line(model, 'Delay/1', 'Gain/1');
    add_line(model, 'Gain/1', 'AutoGain/1');
    add_line(model, 'AutoGain/1', 'End/1');
    workspace = get_param(model, 'ModelWorkspace');
    assignin(workspace, 'K', Simulink.Parameter(2));
    assignin(workspace, 'C', Simulink.Parameter(1));
    assignin(workspace, 'AutoGain', Simulink.Parameter(3));
    autosar.api.create(model, 'default');
    mapping = autosar.api.getSimulinkMapping(model);
    mapping.mapParameter('K', 'SharedParameter', 'LongName', 'Calibration K', ...
        'SwCalibrationAccess', 'ReadWrite', 'DisplayFormat', '%2.3f');
    mapping.mapParameter('C', 'ConstantMemory');
    mapping.mapState([model '/Delay'], '', 'ArTypedPerInstanceMemory', 'ShortName', 'StateMemory');
    mapping.mapDataStore([model '/Memory'], 'StaticMemory', 'ShortName', 'StoreMemory');
    mapping.mapDataStore([model '/PimMemory'], 'ArTypedPerInstanceMemory');
    for name = {'Input', 'Delay', 'Gain', 'AutoGain'}
        port = get_param([model '/' name{1}], 'PortHandles');
        mapping.addSignal(port.Outport);
        if strcmp(name{1}, 'AutoGain'), continue; end
        role = 'StaticMemory';
        if strcmp(name{1}, 'Delay'), role = 'ArTypedPerInstanceMemory'; end
        mapping.mapSignal(port.Outport, role, 'ShortName', [name{1} 'Memory'], ...
            'SwCalibrationAccess', 'ReadOnly', 'IsVolatile', true);
    end
end

function local_configErrors(rules, sandbox)
    local_expectError(@() readAutosarMappingRules([rules; rules(1, :)]), 'AutosarMapping:DuplicateRule');
    bad = rules;
    bad.Type(1) = "Functions";
    local_expectError(@() readAutosarMappingRules(bad), 'AutosarMapping:Type');
    bad = rules;
    bad.SwAddrMethod(1) = "";
    local_expectError(@() readAutosarMappingRules(bad), 'AutosarMapping:Schema');
    bad.SwAddrMethod(1) = "/Package/CODE";
    local_expectError(@() readAutosarMappingRules(bad), 'AutosarMapping:MethodName');
    bad = rules;
    bad.Model(1) = "Model.slx";
    local_expectError(@() readAutosarMappingRules(bad), 'AutosarMapping:ModelName');
    local_expectError(@() readAutosarMappingRules(rules(:, 1:2)), 'AutosarMapping:Schema');
    local_expectError(@() readAutosarMappingRules(rules([], :)), 'AutosarMapping:Schema');
    bad = rules;
    bad.Type = lower(bad.Type);
    bad.Model = "  " + bad.Model + "  ";
    assert(isequal(readAutosarMappingRules(bad), rules));
    file = fullfile(sandbox, 'malformed.csv');
    fid = fopen(file, 'w');
    closeFile = onCleanup(@() fclose(fid));
    fprintf(fid, 'Model,Type,SwAddrMethod,Typo\nMotorCtrl,Runnable,CODE,x\n');
    clear closeFile;
    local_expectError(@() readAutosarMappingRules(file), 'AutosarMapping:Schema');
end

function local_preflightErrors(model, rules, mapping, before)
    bad = rules;
    bad.SwAddrMethod(end) = "MissingMethod";
    local_expectError(@() mapAutosarSwAddrMethods(model, bad, struct('Mode', 'apply')), ...
        'AutosarMapping:MethodResolution');
    bad = rules;
    bad.SwAddrMethod(end) = "AppCode";
    local_expectError(@() mapAutosarSwAddrMethods(model, bad, struct('Mode', 'apply')), ...
        'AutosarMapping:SectionType');
    properties = autosar.api.getAUTOSARProperties(model);
    properties.addPackageableElement('SwAddrMethod', '/Other/Sections', 'AppCode', 'SectionType', 'Code');
    local_expectError(@() mapAutosarSwAddrMethods(model, rules, struct('Mode', 'apply')), ...
        'AutosarMapping:MethodResolution');
    properties.delete('/Other/Sections/AppCode');
    set_param(model, 'GroupInternalDataByFunction', 'off');
    local_expectError(@() mapAutosarSwAddrMethods(model, rules, struct('Mode', 'apply')), ...
        'AutosarMapping:InternalDataGrouping');
    set_param(model, 'GroupInternalDataByFunction', 'on');
    partial = mapAutosarSwAddrMethods(model, rules(rules.Type == "Runnable", :));
    assert(partial.Changed > 0);
    bad = rules;
    bad.Model(:) = "DifferentModel";
    local_expectError(@() mapAutosarSwAddrMethods(model, bad), 'AutosarMapping:MissingModelRule');
    local_expectError(@() mapAutosarSwAddrMethods(model, rules, struct('Typo', true)), 'AutosarMapping:Options');
    assert(isequal(before, local_snapshot(mapping)), 'Preflight changed existing mappings.');
end

function snapshot = local_snapshot(mapping)
    functions = mapping.find('Functions');
    code = strings(numel(functions), 1);
    internal = strings(0, 1);
    runnable = code;
    for k = 1:numel(functions)
        [runnable(k), code(k), data] = mapping.getFunction(char(functions(k)));
        if startsWith(functions(k), ["Periodic", "Partition:", "ExportedFunction:", "SimulinkFunction:"])
            internal(end + 1) = string(data); %#ok<AGROW>
        end
    end
    statics = strings(0, 1);
    pim = strings(0, 1);
    preserved = runnable;
    signals = mapping.find('Signals');
    for k = 1:numel(signals)
        role = string(mapping.getSignal(signals(k)));
        if role == "Auto", continue; end
        method = string(mapping.getSignal(signals(k), 'SwAddrMethod'));
        if role == "StaticMemory", statics(end + 1) = method; else, pim(end + 1) = method; end %#ok<AGROW>
        preserved = [preserved; role; string(mapping.getSignal(signals(k), 'ShortName')); ...
            string(mapping.getSignal(signals(k), 'SwCalibrationAccess')); ...
            string(mapping.getSignal(signals(k), 'IsVolatile'))]; %#ok<AGROW>
    end
    states = mapping.find('States');
    pim(end + 1) = string(mapping.getState(char(states(1)), '', 'SwAddrMethod'));
    preserved(end + 1) = string(mapping.getState(char(states(1)), '', 'ShortName'));
    stores = mapping.find('DataStores');
    for k = 1:numel(stores)
        role = string(mapping.getDataStore(stores(k)));
        method = string(mapping.getDataStore(stores(k), 'SwAddrMethod'));
        if role == "StaticMemory", statics(end + 1) = method; else, pim(end + 1) = method; end %#ok<AGROW>
        preserved = [preserved; role; string(mapping.getDataStore(stores(k), 'ShortName'))]; %#ok<AGROW>
    end
    preserved = [preserved; string(mapping.getParameter('K', 'LongName')); ...
        string(mapping.getParameter('K', 'SwCalibrationAccess')); string(mapping.getParameter('K', 'DisplayFormat'))];
    snapshot = struct('Code', code, 'Internal', internal, 'Static', statics, 'Pim', pim, ...
        'Constant', string(mapping.getParameter('C', 'SwAddrMethod')), ...
        'Parameter', string(mapping.getParameter('K', 'SwAddrMethod')), ...
        'Auto', string(mapping.getParameter('AutoGain')), 'Preserved', preserved);
end

function bytes = local_bytes(file)
    fid = fopen(file, 'rb');
    cleanup = onCleanup(@() fclose(fid));
    bytes = fread(fid, Inf, '*uint8');
end

function failure = local_expectError(action, identifier)
    try
        action();
    catch cause
        if ~strcmp(cause.identifier, identifier), rethrow(cause); end
        failure = cause;
        return;
    end
    error('Test:MissingError', 'Expected error: %s', identifier);
end
