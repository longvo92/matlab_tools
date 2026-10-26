function testSignalNaming()
%TESTSIGNALNAMING Verify resolved Goto visibility in CLI and GUI on a scratch model.
    previousPath = path;
    restore = onCleanup(@() path(previousPath));
    repo = fileparts(fileparts(mfilename('fullpath')));
    addpath(fullfile(repo, 'tools', 'signal_naming'));
    [~, model] = fileparts(tempname);
    new_system(model);
    cleanup = onCleanup(@() close_system(model, 0));
    add_block('built-in/Subsystem', [model '/AOther']);
    wrongLine = local_addSource([model '/AOther'], 'SharedTag', 'local');
    add_block('built-in/Subsystem', [model '/ZActual']);
    scopedLine = local_addSource([model '/ZActual'], 'SharedTag', 'scoped');
    add_block('built-in/GotoTagVisibility', [model '/ZActual/Visibility'], ...
        'GotoTag', 'SharedTag');
    consumer = [model '/ZActual/Consumer'];
    add_block('built-in/Subsystem', consumer);
    local_addConsumer(consumer, 'SharedTag', 'ScopedValue');

    add_block('built-in/Subsystem', [model '/Local']);
    localLine = local_addSource([model '/Local'], 'LocalTag', 'local');
    local_addConsumer([model '/Local'], 'LocalTag', 'LocalValue');
    globalLine = local_addSource(model, 'GlobalTag', 'global');
    add_block('built-in/Subsystem', [model '/GlobalConsumer']);
    local_addConsumer([model '/GlobalConsumer'], 'GlobalTag', 'GlobalValue');
    set_param(model, 'SimulationCommand', 'update');

    opts = struct('dryRun', true, 'verbose', false, 'propagate', false);
    report = nameBusElementSignals(consumer, opts);
    assert(strcmp(report.parent, [model '/ZActual']));
    assert(isempty(get_param(wrongLine, 'Name')) && isempty(get_param(scopedLine, 'Name')));
    fig = nameBusElementSignalsGui(consumer, opts);
    figCleanup = onCleanup(@() delete(fig));
    button = findall(fig, 'Tag', 'Preview');
    button.ButtonPushedFcn(button, []);
    assert(strcmp(fig.UserData.Mode, 'Preview') && isempty(fig.UserData.Error));
    assert(isempty(get_param(scopedLine, 'Name')) && isempty(get_param(wrongLine, 'Name')));
    button = findall(fig, 'Tag', 'Apply');
    button.ButtonPushedFcn(button, []);
    assert(strcmp(fig.UserData.Mode, 'Apply') && isempty(fig.UserData.Error));
    assert(strcmp(get_param(scopedLine, 'Name'), 'ScopedValue'));
    assert(isempty(get_param(wrongLine, 'Name')));
    clear figCleanup;
    opts.dryRun = false;
    nameBusElementSignals([model '/Local'], opts);
    nameBusElementSignals([model '/GlobalConsumer'], opts);
    assert(strcmp(get_param(localLine, 'Name'), 'LocalValue'));
    assert(strcmp(get_param(globalLine, 'Name'), 'GlobalValue'));
    assert(isempty(get_param(wrongLine, 'Name')));
    fprintf('PASS: local/scoped/global Goto routing, CLI/GUI preview and apply isolation.\n');
end

function line = local_addSource(parent, tag, visibility)
    add_block('built-in/Constant', [parent '/Source']);
    add_block('built-in/Goto', [parent '/Goto'], 'GotoTag', tag, 'TagVisibility', visibility);
    line = add_line(parent, 'Source/1', 'Goto/1');
end

function local_addConsumer(parent, tag, element)
    add_block('built-in/From', [parent '/From'], 'GotoTag', tag);
    add_block('simulink/Ports & Subsystems/Out Bus Element', [parent '/Out'], ...
        'PortName', 'OutputBus', 'Element', element);
    add_line(parent, 'From/1', 'Out/1');
end
