function testSignalNaming()
%TESTSIGNALNAMING Exercise naming boundaries and propagation in live Simulink.
% Uses only temporary synthetic models; no user models are edited or saved.
    repo = fileparts(fileparts(mfilename('fullpath')));
    previousPath = path;
    restore = onCleanup(@() path(previousPath));
    addpath(fullfile(repo, 'tools', 'signal_naming'), '-begin');
    local_testFunctionElements();
    local_testTraceBoundaries();
    local_testInBusPropagation();
    fprintf('PASS: CLI/GUI function elements/callers, trace boundaries, In Bus labels, read-only Preview, no autosave.\n');
end

function local_testFunctionElements()
    % Each direction must work independently as well as in a mixed model.
    kinds = {'Function Element Call', 'Function Element'};
    for k = 1:numel(kinds)
        [~, mdl] = fileparts(tempname);
        new_system(mdl);
        cleanup = onCleanup(@() close_system(mdl, 0));
        functionBlock = [mdl '/FunctionPort'];
        add_block(['simulink/Ports & Subsystems/' kinds{k}], functionBlock);
        handles = get_param(functionBlock, 'PortHandles');
        assert(isempty(handles.Inport) && isempty(handles.Outport));
        assert(strcmp(get_param(functionBlock, 'IsBusElementPort'), 'on'));
        set_param(mdl, 'Dirty', 'off');
        opts = struct('verbose', false, 'dryRun', true);
        report = nameBusElementSignals(mdl, opts);
        local_assertFunctionSkipped(report, functionBlock);
        assert(strcmp(get_param(mdl, 'Dirty'), 'off'));
        opts.dryRun = false;
        report = nameBusElementSignals(mdl, opts);
        local_assertFunctionSkipped(report, functionBlock);
        assert(strcmp(get_param(mdl, 'Dirty'), 'off'), 'Function-only Apply must not edit the model.');

        otherFunctionBlock = [mdl '/OtherFunctionPort'];
        add_block(['simulink/Ports & Subsystems/' kinds{3-k}], otherFunctionBlock);

        % A caller's data output remains a normal signal naming target.
        caller = [mdl '/Caller'];
        add_block('simulink/User-Defined Functions/Function Caller', caller, ...
            'FunctionPrototype', 'y = f(u)');
        add_block('simulink/Ports & Subsystems/In Bus Element', [mdl '/In'], ...
            'PortName', 'InputBus', 'Element', 'Request.Value');
        add_block('simulink/Ports & Subsystems/Out Bus Element', [mdl '/Out'], ...
            'PortName', 'OutputBus', 'Element', 'Result.Value');
        inputLine = add_line(mdl, 'In/1', 'Caller/1');
        outputLine = add_line(mdl, 'Caller/1', 'Out/1');
        add_block('simulink/User-Defined Functions/Function Caller', [mdl '/VoidCaller'], ...
            'FunctionPrototype', 'notify()');
        prototype = get_param(caller, 'FunctionPrototype');
        element = get_param(functionBlock, 'Element');
        set_param(mdl, 'Dirty', 'off');
        opts.dryRun = true;
        report = nameBusElementSignals(mdl, opts);
        local_assertFunctionSkipped(report, functionBlock);
        local_assertFunctionSkipped(report, otherFunctionBlock);
        assert(numel(report) == 4 && strcmp(get_param(mdl, 'Dirty'), 'off'));
        assert(isempty(get_param(inputLine, 'Name')) && isempty(get_param(outputLine, 'Name')));
        opts.dryRun = false;
        report = nameBusElementSignals(mdl, opts);
        local_assertFunctionSkipped(report, functionBlock);
        local_assertFunctionSkipped(report, otherFunctionBlock);
        assert(strcmp(get_param(inputLine, 'Name'), 'Request_Value'));
        assert(strcmp(get_param(outputLine, 'Name'), 'Result_Value'));
        assert(~any(startsWith({report.status}, 'error:') | startsWith({report.propagated}, 'err:')));
        assert(strcmp(local_propagated(inputLine), 'off'));
        assert(strcmp(get_param(caller, 'FunctionPrototype'), prototype));
        assert(strcmp(get_param(functionBlock, 'Element'), element));

        local_reset([inputLine outputLine]);
        fig = nameBusElementSignalsGui(mdl, opts);
        figCleanup = onCleanup(@() delete(fig));
        set_param(mdl, 'Dirty', 'off');
        button = findall(fig, 'Tag', 'Preview');
        button.ButtonPushedFcn(button, []);
        assert(isempty(fig.UserData.Error) && strcmp(fig.UserData.Mode, 'Preview'));
        local_assertFunctionSkipped(fig.UserData.Report, functionBlock);
        local_assertFunctionSkipped(fig.UserData.Report, otherFunctionBlock);
        assert(strcmp(get_param(mdl, 'Dirty'), 'off'));
        assert(isempty(get_param(inputLine, 'Name')) && isempty(get_param(outputLine, 'Name')));
        button = findall(fig, 'Tag', 'Apply');
        button.ButtonPushedFcn(button, []);
        assert(isempty(fig.UserData.Error) && strcmp(fig.UserData.Mode, 'Apply'));
        local_assertFunctionSkipped(fig.UserData.Report, functionBlock);
        local_assertFunctionSkipped(fig.UserData.Report, otherFunctionBlock);
        assert(strcmp(get_param(inputLine, 'Name'), 'Request_Value'));
        assert(strcmp(get_param(outputLine, 'Name'), 'Result_Value'));
        assert(strcmp(get_param(caller, 'FunctionPrototype'), prototype));
        assert(strcmp(get_param(functionBlock, 'Element'), element));
        assert(strcmp(get_param(mdl, 'Dirty'), 'on') && isempty(get_param(mdl, 'FileName')));
        clear figCleanup cleanup;
    end
end

function local_assertFunctionSkipped(report, block)
    row = report(strcmp({report.block}, block));
    assert(isscalar(row) && startsWith(row.status, 'skipped: no data '));
    assert(isempty(row.name) && isempty(row.propagated));
end

function local_testTraceBoundaries()
    [~, mdl] = fileparts(tempname);
    new_system(mdl);
    cleanup = onCleanup(@() close_system(mdl, 0));
    libraries = {'simulink/Signal Attributes/Signal Conversion', ...
        'simulink/Signal Attributes/Signal Specification', ...
        'simulink/Signal Attributes/Data Type Conversion'};
    kinds = {'Copy', 'Specification', 'DataType'};
    inputs = zeros(1, numel(kinds));
    outputs = inputs;
    for k = 1:numel(kinds)
        source = ['Source' kinds{k}];
        boundary = kinds{k};
        sink = ['Out' kinds{k}];
        add_block('simulink/Sources/Constant', [mdl '/' source]);
        add_block(libraries{k}, [mdl '/' boundary]);
        add_block('simulink/Ports & Subsystems/Out Bus Element', ...
            [mdl '/' sink], 'PortName', ['Bus' kinds{k}], 'Element', ['Result.' kinds{k}]);
        inputs(k) = add_line(mdl, [source '/1'], [boundary '/1']);
        outputs(k) = add_line(mdl, [boundary '/1'], [sink '/1']);
    end
    assert(strcmp(get_param([mdl '/Copy'], 'ConversionOutput'), 'Signal copy'));

    % Route through From/Goto and a subsystem before reaching a copy block.
    ss = [mdl '/Route'];
    add_block('built-in/Subsystem', ss);
    add_block('simulink/Sources/Constant', [ss '/Source']);
    add_block(libraries{1}, [ss '/Copy']);
    add_block('built-in/Outport', [ss '/Out']);
    routedInput = add_line(ss, 'Source/1', 'Copy/1');
    routedOutput = add_line(ss, 'Copy/1', 'Out/1');
    add_block('simulink/Signal Routing/Goto', [mdl '/Goto'], 'GotoTag', 'Routed');
    add_block('simulink/Signal Routing/From', [mdl '/From'], 'GotoTag', 'Routed');
    add_block('simulink/Ports & Subsystems/Out Bus Element', [mdl '/OutRouted'], ...
        'PortName', 'BusRouted', 'Element', 'Result.Routed');
    routeLine = add_line(mdl, 'Route/1', 'Goto/1');
    fromLine = add_line(mdl, 'From/1', 'OutRouted/1');
    allLines = [inputs outputs routedInput routedOutput routeLine fromLine];
    opts = struct('verbose', false, 'propagateTracePath', true);
    set_param(mdl, 'Dirty', 'off');
    preview = opts;
    preview.dryRun = true;
    report = nameBusElementSignals(mdl, preview);
    assert(all(startsWith({report.status}, 'dry-run')));
    assert(strcmp(get_param(mdl, 'Dirty'), 'off'));
    assert(all(cellfun(@isempty, get_param(allLines, 'Name'))));

    report = nameBusElementSignals(mdl, opts);
    for k = 1:numel(kinds)
        assert(isempty(get_param(inputs(k), 'Name')), ...
            'Tracing crossed the %s naming boundary.', kinds{k});
        assert(strcmp(get_param(outputs(k), 'Name'), ['Result_' kinds{k}]));
    end
    assert(isempty(get_param(routedInput, 'Name')));
    assert(strcmp(get_param(routedOutput, 'Name'), 'Result_Routed'));
    assert(strcmp(local_propagated(routeLine), 'on'));
    assert(strcmp(local_propagated(fromLine), 'on'));
    assert(~any(startsWith({report.status}, 'error:')));
    assert(strcmp(get_param(mdl, 'Dirty'), 'on') && isempty(get_param(mdl, 'FileName')));

    % Existing names and propagate=false retain their established contracts.
    set_param(outputs(1), 'Name', 'KeepCopy');
    nameBusElementSignals(mdl, opts);
    assert(strcmp(get_param(outputs(1), 'Name'), 'KeepCopy'));
    local_reset(allLines);
    disabled = opts;
    disabled.propagate = false;
    nameBusElementSignals(mdl, disabled);
    assert(strcmp(local_propagated(routeLine), 'off'));
    assert(strcmp(local_propagated(fromLine), 'off'));
    local_reset(allLines);

    fig = nameBusElementSignalsGui(mdl, opts);
    figCleanup = onCleanup(@() delete(fig));
    set_param(mdl, 'Dirty', 'off');
    button = findall(fig, 'Tag', 'Preview');
    button.ButtonPushedFcn(button, []);
    assert(isempty(fig.UserData.Error) && strcmp(fig.UserData.Mode, 'Preview'));
    assert(strcmp(get_param(mdl, 'Dirty'), 'off'));
    assert(all(cellfun(@isempty, get_param(allLines, 'Name'))));
    button = findall(fig, 'Tag', 'Apply');
    button.ButtonPushedFcn(button, []);
    assert(isempty(fig.UserData.Error) && strcmp(fig.UserData.Mode, 'Apply'));
    for k = 1:numel(kinds)
        assert(isempty(get_param(inputs(k), 'Name')));
        assert(strcmp(get_param(outputs(k), 'Name'), ['Result_' kinds{k}]));
    end
    assert(strcmp(get_param(routedOutput, 'Name'), 'Result_Routed'));
    assert(isempty(get_param(routedInput, 'Name')));
    assert(strcmp(local_propagated(routeLine), 'on') && strcmp(local_propagated(fromLine), 'on'));
    assert(strcmp(get_param(mdl, 'Dirty'), 'on') && isempty(get_param(mdl, 'FileName')));
end

function local_testInBusPropagation()
    [~, mdl] = fileparts(tempname);
    new_system(mdl);
    cleanup = onCleanup(@() close_system(mdl, 0));
    add_block('simulink/Ports & Subsystems/In Bus Element', [mdl '/In'], ...
        'PortName', 'InputBus', 'Element', 'Request.Value');
    add_block('simulink/Ports & Subsystems/Out Bus Element', [mdl '/Out'], ...
        'PortName', 'OutputBus', 'Element', 'Result.Value');
    line = add_line(mdl, 'In/1', 'Out/1');
    add_block('simulink/Signal Routing/Goto', [mdl '/Goto'], 'GotoTag', 'PassThrough');
    add_block('simulink/Signal Routing/From', [mdl '/From'], 'GotoTag', 'PassThrough');
    add_line(mdl, 'In/1', 'Goto/1');
    add_block('simulink/Ports & Subsystems/Out Bus Element', [mdl '/RoutedOut'], ...
        'PortName', 'RoutedBus', 'Element', 'Result.Routed');
    fromLine = add_line(mdl, 'From/1', 'RoutedOut/1');
    opts = struct('verbose', false, 'overwrite', true, 'propagateTracePath', true);
    set_param(mdl, 'Dirty', 'off');
    preview = opts;
    preview.dryRun = true;
    nameBusElementSignals(mdl, preview);
    assert(strcmp(get_param(mdl, 'Dirty'), 'off'));
    assert(isempty(get_param(line, 'Name')) && strcmp(local_propagated(line), 'off'));

    report = nameBusElementSignals(mdl, opts);
    assert(strcmp(get_param(line, 'Name'), 'Request_Value'));
    assert(strcmp(local_propagated(line), 'off'), 'The first In Bus line must not enable propagation.');
    inRow = report(strcmp({report.kind}, 'In'));
    assert(strcmp(inRow.propagated, 'skipped: In Bus Element'));
    directRow = report(strcmp({report.block}, [mdl '/Out']));
    assert(strcmp(directRow.propagated, 'skipped: In Bus Element'));
    assert(strcmp(local_propagated(fromLine), 'on'));

    local_reset([line fromLine]);
    fig = nameBusElementSignalsGui(mdl, opts);
    figCleanup = onCleanup(@() delete(fig));
    set_param(mdl, 'Dirty', 'off');
    button = findall(fig, 'Tag', 'Preview');
    button.ButtonPushedFcn(button, []);
    assert(isempty(fig.UserData.Error) && strcmp(get_param(mdl, 'Dirty'), 'off'));
    button = findall(fig, 'Tag', 'Apply');
    button.ButtonPushedFcn(button, []);
    assert(isempty(fig.UserData.Error));
    assert(strcmp(get_param(line, 'Name'), 'Request_Value'));
    assert(strcmp(local_propagated(line), 'off') && strcmp(local_propagated(fromLine), 'on'));
    inRow = fig.UserData.Report(strcmp({fig.UserData.Report.kind}, 'In'));
    assert(strcmp(inRow.propagated, 'skipped: In Bus Element'));
    assert(strcmp(get_param(mdl, 'Dirty'), 'on') && isempty(get_param(mdl, 'FileName')));
end

function value = local_propagated(line)
    value = get_param(get_param(line, 'SrcPortHandle'), 'ShowPropagatedSignals');
end

function local_reset(lines)
    for k = 1:numel(lines)
        set_param(lines(k), 'Name', '');
        if strcmp(local_propagated(lines(k)), 'on')
            set_param(get_param(lines(k), 'SrcPortHandle'), 'ShowPropagatedSignals', 'off');
        end
    end
end
