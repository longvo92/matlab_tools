function testAutosarCodeMapping()
%TESTAUTOSARCODEMAPPING Native property configuration and recovery coverage.
    oldPath = path;
    restorePath = onCleanup(@() path(oldPath));
    repo = fileparts(fileparts(mfilename('fullpath')));
    addpath(fullfile(repo, 'tools', 'autosar_mapping'));
    sandbox = tempname;
    mkdir(sandbox);
    removeSandbox = onCleanup(@() rmdir(sandbox, 's'));
    [~, model] = fileparts(tempname);
    new_system(model);
    closeModel = onCleanup(@() close_system(model, 0));
    local_fixture(model);
    mapping = autosar.api.getSimulinkMapping(model);
    baseline = exportAutosarMapping(model);
    sample = readAutosarCodeMappingRules(fullfile(repo, 'tools', 'autosar_mapping', ...
        'autosar_code_mapping.csv'));
    assert(any(sample.Property == "SwAddrMethod") && ...
        any(sample.Property == "DataAccessMode"));
    optional = local_rules(model, ["Signals"; "Inports"], ...
        ["type?:ArTypedPerInstanceMemory"; "Input"], ...
        ["SwAddrMethod"; "DataAccessMode"], ["AppPim"; "ExplicitReceive"]);
    optionalPreview = configureAutosarMapping(model, optional);
    assert(height(optionalPreview.SkippedRules) == 1 && ...
        optionalPreview.SkippedRules.Element == "type?:ArTypedPerInstanceMemory");
    strict = optional(1, :);
    strict.Element = "type:ArTypedPerInstanceMemory";
    local_error(@() configureAutosarMapping(model, strict), 'AutosarMapping:UnmatchedRule');
    strict.Element = "type?:UnknownRole";
    local_error(@() configureAutosarMapping(model, strict), 'AutosarMapping:Value');
    assert(all(ismember(["Inports", "Outports", "Functions", "FunctionCallers", ...
        "ModelParameters", "ModelParameterArguments", "Signals", "States", ...
        "DataStores", "SynthesizedDataStores", "Defaults"], unique(baseline.Category))));
    csv = fullfile(sandbox, 'code_mapping.csv');
    exportAutosarMapping(model, csv);
    assert(isequal(baseline, readAutosarCodeMappingRules(csv)));
    local_error(@() exportAutosarMapping(model, csv), 'AutosarMapping:FileExists');
    saved = fullfile(sandbox, [model '.slx']);
    save_system(model, saved);
    bytes = local_bytes(saved);
    roundtrip = configureAutosarMapping(model, csv, struct('Mode', 'apply'));
    assert(roundtrip.Compliant && roundtrip.Applied == 0 && strcmp(get_param(model, 'Dirty'), 'off'));
    local_errors(model, baseline);
    local_failureRecovery(model);

    % Every native data-access mode applicable to the ordinary S/R interface.
    for mode = ["ImplicitReceive", "ExplicitReceive", "ExplicitReceiveByVal", ...
            "QueuedExplicitReceive", "ErrorStatus", "IsUpdated", "EndToEndRead"]
        r = configureAutosarMapping(model, local_rules(model, "Inports", "*", "DataAccessMode", mode), struct('Mode', 'apply'));
        assert(r.Compliant);
        [~, ~, value] = mapping.getInport('Input');
        assert(string(value) == mode);
    end
    for mode = ["ImplicitSend", "ImplicitSendByRef", "ExplicitSend", "QueuedExplicitSend", "EndToEndWrite"]
        local_apply(model, local_rules(model, "Outports", "*", "DataAccessMode", mode));
        [~, ~, value] = mapping.getOutport('Output');
        assert(string(value) == mode);
    end
    local_apply(model, baseline);
    modeRules = local_rules(model, ["Inports"; "Inports"; "Inports"; "Outports"; "Outports"; "Outports"], ...
        ["Input"; "Input"; "Input"; "Output"; "Output"; "Output"], ...
        ["Port"; "DataElement"; "DataAccessMode"; "Port"; "DataElement"; "DataAccessMode"], ...
        ["ModeR"; "Mode"; "ModeReceive"; "ModeS"; "Mode"; "ModeSend"]);
    modes = configureAutosarMapping(model, modeRules, struct('Mode', 'apply'));
    assert(modes.Compliant && configureAutosarMapping(model, exportAutosarMapping(model)).Compliant);
    local_apply(model, baseline);
    changes = local_rules(model, ...
        ["Signals"; "Signals"; "ModelParameters"; "ModelParameters"; "DataStores"; ...
        "DataStores"; "DataStores"; "States"; "ModelParameterArguments"; "SynthesizedDataStores"; ...
        "FunctionCallers"; "Defaults"; "Defaults"; "Defaults"; "Functions"; "Functions"], ...
        ["type:StaticMemory"; "type:StaticMemory"; "K"; "C"; "Memory"; "Memory"; "Memory"; ...
        "Delay"; "Arg"; "Synth"; "Service"; "InternalData"; "InternalData"; "InportsOutports"; "Periodic"; "Periodic"], ...
        ["SwCalibrationAccess"; "IsVolatile"; "DisplayFormat"; "IsConst"; "NeedsNVRAMAccess"; ...
        "RestoreAtStart"; "StoreAtShutdown"; "LongName"; "MappedTo"; "SwAddrMethod"; ...
        "Port"; "Packaging"; "GroupInternalDataByFunction"; "EndToEndProtectionMethod"; "SwAddrMethod"; "SwAddrMethodForInternalData"], ...
        ["ReadWrite"; "true"; "%3.5f"; "true"; "true"; "false"; "false"; "Delay state"; ...
        "PerInstanceParameter"; "VAR"; "Client2"; "PrivateGlobal"; "on"; "TransformerError"; "CODE"; "VAR"]);
    before = exportAutosarMapping(model);
    preview = configureAutosarMapping(model, changes);
    assert(preview.Changed > 10 && preview.Applied == 0 && isequal(before, exportAutosarMapping(model)));
    applied = configureAutosarMapping(model, changes, struct('Mode', 'apply'));
    assert(applied.Compliant && applied.Applied == preview.Changed);
    assert(isequal(bytes, local_bytes(saved)), 'Apply must never save the model.');
    assert(string(mapping.getParameter('Arg')) == "PerInstanceParameter");
    assert(string(mapping.getDataStore([model '/Memory'], 'NeedsNVRAMAccess')) == "true");
    assert(string(mapping.getState([model '/Delay'], '', 'LongName')) == "Delay state");
    [port, ~] = mapping.getFunctionCaller('Service');
    assert(strcmp(port, 'Client2'));
    assert(configureAutosarMapping(model, changes, struct('Mode', 'apply')).Applied == 0);

    % Coupled role/attributes are applied once, independent of CSV row order.
    changeRole = local_rules(model, repmat("Signals", 3, 1), repmat("Gain:1", 3, 1), ...
        ["SwAddrMethod"; "ShortName"; "MappedTo"], ["VAR"; "GainPim"; "ArTypedPerInstanceMemory"]);
    local_apply(model, changeRole);
    ph = get_param([model '/Gain'], 'PortHandles');
    assert(strcmp(mapping.getSignal(ph.Outport), 'ArTypedPerInstanceMemory'));
    assert(strcmp(mapping.getSignal(ph.Outport, 'ShortName'), 'GainPim'));
    portParameter = local_rules(model, repmat("ModelParameterArguments", 3, 1), repmat("Arg", 3, 1), ...
        ["DataElement"; "MappedTo"; "Port"], ["Param"; "PortParameter"; "CalPort"]);
    pp = configureAutosarMapping(model, portParameter, struct('Mode', 'apply'));
    assert(pp.Compliant && strcmp(mapping.getParameter('Arg'), 'PortParameter'));
    namedState = local_rules(model, "States", "Delay#DelayState", "LongName", "Named delay state");
    ns = configureAutosarMapping(model, namedState, struct('Mode', 'apply'));
    assert(ns.Compliant);
    local_registration(model);
    local_transfers();
    local_rateTransfers();
    local_sharedEntityRollback();
    local_inactiveNvBlockNeeds();
    local_busPorts();
    fprintf('PASS: Code Mapping export/CSV, access modes, data/argument/NVRAM/default/function settings, registration, IRV, bus ports, inactive NvBlockNeeds, shared-entity rollback.\n');
end

function local_fixture(model)
    set_param(model, 'SystemTargetFile', 'autosar.tlc', 'Solver', 'FixedStepDiscrete', 'FixedStep', '0.1');
    add_block('simulink/Sources/In1', [model '/Input']);
    add_block('simulink/Discrete/Unit Delay', [model '/Delay'], 'StateName', 'DelayState');
    add_block('simulink/Math Operations/Gain', [model '/Gain'], 'Gain', 'K');
    add_block('simulink/Math Operations/Gain', [model '/ArgGain'], 'Gain', 'Arg');
    add_block('simulink/Sinks/Out1', [model '/Output']);
    add_line(model, 'Input/1', 'Delay/1');
    add_line(model, 'Delay/1', 'Gain/1');
    add_line(model, 'Gain/1', 'ArgGain/1');
    add_line(model, 'ArgGain/1', 'Output/1');
    add_block('simulink/Sources/Constant', [model '/Constant'], 'Value', 'C');
    add_block('simulink/Sinks/Terminator', [model '/End']);
    add_line(model, 'Constant/1', 'End/1');
    add_block('simulink/Signal Routing/Data Store Memory', [model '/Memory'], 'DataStoreName', 'Memory');
    add_block('simulink/Signal Routing/Data Store Read', [model '/Read'], 'DataStoreName', 'Synth');
    add_block('simulink/User-Defined Functions/Function Caller', [model '/Caller'], ...
        'FunctionPrototype', 'Service()', 'InputArgumentSpecifications', '', 'OutputArgumentSpecifications', '');
    workspace = get_param(model, 'ModelWorkspace');
    for name = {'K', 'C', 'Arg'}, assignin(workspace, name{1}, Simulink.Parameter(2)); end
    signal = Simulink.Signal;
    signal.Dimensions = 1;
    signal.DataType = 'double';
    signal.Complexity = 'real';
    assignin(workspace, 'Synth', signal);
    set_param(model, 'ParameterArgumentNames', 'Arg');
    autosar.api.create(model, 'default');
    autosar.api.syncModel(model);
    mapping = autosar.api.getSimulinkMapping(model);
    mapping.mapParameter('K', 'SharedParameter');
    mapping.mapParameter('C', 'ConstantMemory');
    mapping.mapState([model '/Delay'], '', 'StaticMemory');
    mapping.mapDataStore([model '/Memory'], 'ArTypedPerInstanceMemory');
    ph = get_param([model '/Gain'], 'PortHandles');
    mapping.addSignal(ph.Outport);
    mapping.mapSignal(ph.Outport, 'StaticMemory', 'ShortName', 'GainMemory');
    mapping.addSynthesizedDataStore('Synth');
    mapping.mapSynthesizedDataStore('Synth', 'StaticMemory');
    properties = autosar.api.getAUTOSARProperties(model);
    properties.addPackageableElement('ClientServerInterface', '/Test/Interfaces', 'ServiceIf');
    properties.add('/Test/Interfaces/ServiceIf', 'Operations', 'Service');
    component = properties.find([], 'AtomicComponent', 'PathType', 'FullyQualified');
    for name = {'Client', 'Client2'}
        properties.add(component{1}, 'ClientPorts', name{1}, 'Interface', '/Test/Interfaces/ServiceIf');
    end
    mapping.mapFunctionCaller('Service', 'Client', 'Service');
    properties.addPackageableElement('ParameterInterface', '/Test/Interfaces', 'ParamIf');
    properties.add('/Test/Interfaces/ParamIf', 'DataElements', 'Param');
    properties.add(component{1}, 'ParameterReceiverPorts', 'CalPort', 'Interface', '/Test/Interfaces/ParamIf');
    properties.addPackageableElement('ModeDeclarationGroup', '/Test/Interfaces', 'Modes');
    properties.add('/Test/Interfaces/Modes', 'Mode', 'Off', 'Value', 0);
    properties.addPackageableElement('ModeSwitchInterface', '/Test/Interfaces', 'ModeIf');
    properties.add('/Test/Interfaces/ModeIf', 'ModeGroup', 'Mode');
    properties.set('/Test/Interfaces/ModeIf/Mode', 'ModeGroup', '/Test/Interfaces/Modes');
    properties.add(component{1}, 'ModeReceiverPorts', 'ModeR', 'Interface', '/Test/Interfaces/ModeIf');
    properties.add(component{1}, 'ModeSenderPorts', 'ModeS', 'Interface', '/Test/Interfaces/ModeIf');
end

function local_failureRecovery(model)
    before = exportAutosarMapping(model);
    set_param(model, 'Dirty', 'off');
    bad = local_rules(model, ["Defaults"; "Inports"; "Outports"], ...
        ["InternalData"; "Input"; "Output"], ["Packaging"; "DataAccessMode"; "Port"], ...
        ["PublicGlobal"; "ExplicitReceive"; "MissingPort"]);
    failure = local_error(@() configureAutosarMapping(model, bad, struct('Mode', 'apply')), 'AutosarMapping:ApplyFailed');
    assert(isscalar(failure.cause), 'Native rollback must succeed.');
    assert(isequal(before, exportAutosarMapping(model)) && strcmp(get_param(model, 'Dirty'), 'off'));
end

function local_registration(model)
    add = local_rules(model, repmat("Signals", 3, 1), repmat("ArgGain:1", 3, 1), ...
        ["Registered"; "MappedTo"; "SwAddrMethod"], ["true"; "StaticMemory"; "VAR"]);
    local_apply(model, add);
    remove = add(1, :);
    remove.Value = "false";
    local_apply(model, remove);
    assert(configureAutosarMapping(model, remove).Changed == 0);
    synth = local_rules(model, "SynthesizedDataStores", "Synth", "Registered", "false");
    local_apply(model, synth);
    synth.Value = "true";
    local_apply(model, synth);
end

function local_transfers()
    [~, model] = fileparts(tempname);
    new_system(model);
    cleanup = onCleanup(@() close_system(model, 0));
    set_param(model, 'SystemTargetFile', 'autosar.tlc', 'Solver', 'FixedStepDiscrete', ...
        'FixedStep', '0.1', 'IsExportFunctionModel', 'on');
    for name = {'RunA', 'RunB'}
        add_block('simulink/Sources/In1', [model '/' name{1}], 'OutputFunctionCall', 'on');
    end
    add_block('simulink/Sources/Constant', [model '/Input']);
    for name = {'Producer', 'Consumer'}
        add_block('simulink/Ports & Subsystems/Function-Call Subsystem', [model '/' name{1}]);
    end
    add_block('simulink/Sinks/Out1', [model '/Output']);
    add_line(model, 'RunA/1', 'Producer/trigger');
    add_line(model, 'RunB/1', 'Consumer/trigger');
    add_line(model, 'Input/1', 'Producer/1');
    line = add_line(model, 'Producer/1', 'Consumer/1');
    set_param(line, 'Name', 'Transfer');
    add_line(model, 'Consumer/1', 'Output/1');
    autosar.api.create(model, 'default');
    autosar.api.syncModel(model);
    properties = autosar.api.getAUTOSARProperties(model);
    component = properties.find([], 'AtomicComponent', 'PathType', 'FullyQualified');
    behavior = properties.get(component{1}, 'Behavior');
    properties.add(behavior, 'IRV', 'Shared');
    for mode = ["Implicit", "Explicit"]
        rules = local_rules(model, ["DataTransfers"; "DataTransfers"], ["Transfer"; "Transfer"], ...
            ["DataAccessMode"; "InterRunnableVariable"], [mode; "Shared"]);
        local_apply(model, rules);
        roundtrip = configureAutosarMapping(model, exportAutosarMapping(model));
        assert(roundtrip.Compliant);
    end
end

function local_rateTransfers()
    [~, model] = fileparts(tempname);
    new_system(model);
    cleanup = onCleanup(@() close_system(model, 0));
    set_param(model, 'SystemTargetFile', 'autosar.tlc', 'Solver', 'FixedStepDiscrete', ...
        'FixedStep', '0.1', 'SolverMode', 'MultiTasking');
    add_block('simulink/Sources/In1', [model '/Input'], 'SampleTime', '0.1');
    add_block('simulink/Signal Attributes/Rate Transition', [model '/Transfer'], ...
        'OutPortSampleTime', '0.2', 'Integrity', 'on', 'Deterministic', 'off');
    add_block('simulink/Sinks/Out1', [model '/Output']);
    add_line(model, 'Input/1', 'Transfer/1');
    add_line(model, 'Transfer/1', 'Output/1');
    autosar.api.create(model, 'default');
    properties = autosar.api.getAUTOSARProperties(model);
    component = properties.find([], 'AtomicComponent', 'PathType', 'FullyQualified');
    behavior = properties.get(component{1}, 'Behavior');
    properties.add(behavior, 'IRV', 'TestIRV');
    mapping = autosar.api.getSimulinkMapping(model);
    mapping.mapDataTransfer([model '/Transfer'], 'TestIRV', 'Implicit');
    exported = exportAutosarMapping(model);
    transfer = exported(exported.Category == "DataTransfers", :);
    assert(height(transfer) == 2 && all(transfer.Element == "Transfer"));
    assert(configureAutosarMapping(model, transfer).Compliant);
    transfer.Value(transfer.Property == "DataAccessMode") = "Explicit";
    result = configureAutosarMapping(model, transfer, struct('Mode', 'apply'));
    assert(result.Compliant && result.Applied == 1);
    [~, mode] = mapping.getDataTransfer([model '/Transfer']);
    assert(strcmp(mode, 'Explicit'));
end

function local_sharedEntityRollback()
    [~, model] = fileparts(tempname);
    new_system(model);
    cleanup = onCleanup(@() close_system(model, 0));
    set_param(model, 'Dirty', 'off');
    oldShared = struct('SwAddrMethod', "OldShared");
    newShared = struct('SwAddrMethod', "NewShared");
    oldOther = struct('SwAddrMethod', "OldOther");
    newOther = struct('SwAddrMethod', "NewOther");
    values = {oldShared, oldShared, oldOther};
    injectFailure = true;
    adapter = struct('Model', string(model), 'read', @read, 'write', @write);
    records = struct('Index', {1, 2, 3}, 'Element', {"First", "Shared", "Failing"});
    tasks = struct('Record', num2cell(records), ...
        'Before', {oldShared, oldShared, oldOther}, ...
        'After', {newShared, oldShared, newOther}, ...
        'Changed', {true, false, true});
    failure = local_error(@() autosarMapping.applyCodeMapping(adapter, tasks), ...
        'AutosarMapping:ApplyFailed');
    assert(numel(failure.cause) == 1 && ...
        strcmp(failure.cause{1}.identifier, 'Test:InjectedWrite'));
    assert(isequal(values, {oldShared, oldShared, oldOther}));
    assert(strcmp(get_param(model, 'Dirty'), 'off'));

    function value = read(record)
        value = values{record.Index};
    end

    function write(record, desired, previous)
        if record.Index == 3 && injectFailure
            injectFailure = false;
            error('Test:InjectedWrite', 'Simulated native setter failure.');
        end
        if ~isfield(previous, 'SwAddrMethod') || ...
                previous.SwAddrMethod ~= desired.SwAddrMethod
            values{record.Index} = desired;
            if record.Index <= 2
                values{3 - record.Index} = desired;
            end
        end
    end
end

function local_inactiveNvBlockNeeds()
    [~, model] = fileparts(tempname);
    new_system(model);
    cleanup = onCleanup(@() close_system(model, 0));
    set_param(model, 'SystemTargetFile', 'autosar.tlc');
    add_block('simulink/Signal Routing/Data Store Memory', [model '/Memory'], ...
        'DataStoreName', 'Memory');
    autosar.api.create(model, 'default');
    mapping = autosar.api.getSimulinkMapping(model);
    block = [model '/Memory'];
    mapping.mapDataStore(block, 'ArTypedPerInstanceMemory');
    exported = exportAutosarMapping(model);
    rows = exported(exported.Category == "DataStores", :);
    assert(~any(ismember(rows.Property, ["RestoreAtStart", "StoreAtShutdown"])));

    % Older exports include latent true values while NVRAM access is false.
    legacy = [rows; local_rules(model, ["DataStores"; "DataStores"], ...
        ["Memory"; "Memory"], ["RestoreAtStart"; "StoreAtShutdown"], ...
        ["true"; "true"])];
    mapping.mapDataStore(block, 'Auto');
    preview = configureAutosarMapping(model, legacy);
    ignored = preview.Elements(preview.Elements.Status == "Ignored", :);
    assert(height(ignored) == 2 && ...
        all(ismember(ignored.Property, ["RestoreAtStart", "StoreAtShutdown"])));
    applied = configureAutosarMapping(model, legacy, struct('Mode', 'apply'));
    assert(applied.Compliant && strcmp(mapping.getDataStore(block), 'ArTypedPerInstanceMemory'));
    assert(strcmp(mapping.getDataStore(block, 'NeedsNVRAMAccess'), 'false'));
    assert(configureAutosarMapping(model, legacy).Changed == 0);
end

function local_busPorts()
    [~, model] = fileparts(tempname);
    new_system(model);
    cleanup = onCleanup(@() close_system(model, 0));
    set_param(model, 'SystemTargetFile', 'autosar.tlc');
    add_block('simulink/Ports & Subsystems/In Bus Element', [model '/SpeedInput'], ...
        'PortName', 'Sensors', 'Element', 'Speed');
    add_block('simulink/Sinks/Terminator', [model '/End']);
    add_line(model, 'SpeedInput/1', 'End/1');
    autosar.api.create(model, 'default');
    rules = local_rules(model, "Inports", "SpeedInput", "DataAccessMode", "ExplicitReceive");
    local_apply(model, rules);
    mapping = autosar.api.getSimulinkMapping(model);
    [~, ~, mode] = mapping.getInport('SpeedInput');
    assert(strcmp(mode, 'ExplicitReceive') && strcmp(get_param([model '/SpeedInput'], 'IsBusElementPort'), 'on'));
end

function local_errors(model, baseline)
    unknown = local_rules(model, "Inports", "*", "DataAccessMode", "Typo");
    local_error(@() configureAutosarMapping(model, unknown), 'AutosarMapping:Value');
    unknown.Property = "Typo";
    local_error(@() configureAutosarMapping(model, unknown), 'AutosarMapping:Property');
    unknown = local_rules(model, "Inports", "Missing", "DataAccessMode", "ExplicitReceive");
    local_error(@() configureAutosarMapping(model, unknown), 'AutosarMapping:UnmatchedRule');
    duplicate = baseline(1, :);
    local_error(@() readAutosarCodeMappingRules([duplicate; duplicate]), 'AutosarMapping:DuplicateRule');
    overlap = local_rules(model, ["Inports"; "Inports"], ["*"; "Input"], ...
        ["DataAccessMode"; "DataAccessMode"], ["ExplicitReceive"; "ExplicitReceive"]);
    local_error(@() configureAutosarMapping(model, overlap), 'AutosarMapping:OverlappingRule');
    newer = local_rules(model, "Defaults", "Constants", "SwAddrMethod", "CONST");
    local_error(@() configureAutosarMapping(model, newer), 'AutosarMapping:UnmatchedRule');
    assert(isequal(baseline, exportAutosarMapping(model)));
end

function rules = local_rules(model, category, element, property, value)
    n = max([numel(category), numel(element), numel(property), numel(value)]);
    rules = table(repmat(string(model), n, 1), reshape(category, [], 1), reshape(element, [], 1), ...
        reshape(property, [], 1), reshape(value, [], 1), 'VariableNames', {'Model', 'Category', 'Element', 'Property', 'Value'});
end

function report = local_apply(model, rules)
    report = configureAutosarMapping(model, rules, struct('Mode', 'apply'));
end

function failure = local_error(action, identifier)
    try
        action();
    catch cause
        if ~strcmp(cause.identifier, identifier), rethrow(cause); end
        failure = cause;
        return;
    end
    error('Test:MissingError', 'Expected %s.', identifier);
end

function bytes = local_bytes(file)
    fid = fopen(file, 'rb');
    cleanup = onCleanup(@() fclose(fid));
    bytes = fread(fid, Inf, '*uint8');
end
