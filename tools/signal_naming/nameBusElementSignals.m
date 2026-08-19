function report = nameBusElementSignals(sys, opts)
%NAMEBUSELEMENTSIGNALS Name signals after their top-level bus element and show propagated names.
%
%   Built for AUTOSAR-style Simulink models where the outermost layer carries a
%   root input bus (RPort) and a root output bus (PPort). Inside the model:
%     * Bus Selector blocks break the input bus into element signals ("in-bus"),
%     * Bus Creator blocks assemble element signals into the output bus ("out-bus").
%
%   This tool names those element signals after the bus element they carry and
%   turns on propagated-signal display so the name flows downstream without
%   having to label every hop by hand.
%
%   REPORT = NAMEBUSELEMENTSIGNALS() operates on the current system (GCS).
%   REPORT = NAMEBUSELEMENTSIGNALS(SYS) operates on SYS (name or handle).
%   REPORT = NAMEBUSELEMENTSIGNALS(SYS, OPTS) with an options struct:
%       .direction   'in' | 'out' | 'both'   (default 'both')
%                    'in'  = name Bus Selector output signals (from in-bus).
%                    'out' = name Bus Creator input signals (into out-bus).
%       .overwrite   logical (default false)  overwrite lines that already
%                    have a name; false only names unnamed lines.
%       .propagate   logical (default true)   set ShowPropagatedSignals='on'
%                    on the ports so downstream blocks display the name.
%       .recurse     logical (default true)   also descend into subsystems.
%
%   REPORT is a struct array of the signals touched: block, port, name, action.
%
%   Element names come from the block's own selection, so no Simulink.Bus object
%   lookup is needed:
%       * Bus Selector -> 'OutputSignals' (one entry per output port).
%       * Bus Creator  -> the input line names, or the source-block names.
%
%   Copy this file anywhere on the MATLAB path and call it; it has no
%   dependencies on other files in this repository.

    if nargin < 1 || isempty(sys)
        sys = gcs;
    end
    if nargin < 2
        opts = struct();
    end
    opts = local_defaults(opts);

    report = struct('block', {}, 'port', {}, 'name', {}, 'action', {});

    findArgs = {'FindAll', 'on', 'LookUnderMasks', 'all'};
    if ~opts.recurse
        findArgs = [findArgs, {'SearchDepth', 1}];
    end

    if any(strcmp(opts.direction, {'in', 'both'}))
        selectors = find_system(sys, findArgs{:}, 'BlockType', 'BusSelector');
        for k = 1:numel(selectors)
            report = local_nameSelectorOutputs(selectors(k), opts, report);
        end
    end

    if any(strcmp(opts.direction, {'out', 'both'}))
        creators = find_system(sys, findArgs{:}, 'BlockType', 'BusCreator');
        for k = 1:numel(creators)
            report = local_nameCreatorInputs(creators(k), opts, report);
        end
    end

    if nargout == 0
        fprintf('Named %d signal(s) in %s.\n', numel(report), char(sys));
        clear report;
    end
end

% -------------------------------------------------------------------------
function opts = local_defaults(opts)
    defaults = struct('direction', 'both', 'overwrite', false, ...
                      'propagate', true, 'recurse', true);
    fn = fieldnames(defaults);
    for i = 1:numel(fn)
        if ~isfield(opts, fn{i}) || isempty(opts.(fn{i}))
            opts.(fn{i}) = defaults.(fn{i});
        end
    end
    opts.direction = validatestring(opts.direction, {'in', 'out', 'both'});
end

% -------------------------------------------------------------------------
function report = local_nameSelectorOutputs(blk, opts, report)
    signals = local_splitList(get_param(blk, 'OutputSignals'));
    ph = get_param(blk, 'PortHandles');
    n = min(numel(signals), numel(ph.Outport));
    for i = 1:n
        name = local_leaf(signals{i});
        report = local_applyToPort(ph.Outport(i), name, blk, opts, report);
    end
end

% -------------------------------------------------------------------------
function report = local_nameCreatorInputs(blk, opts, report)
    ph = get_param(blk, 'PortHandles');
    for i = 1:numel(ph.Inport)
        name = local_sourceSignalName(ph.Inport(i));
        if isempty(name)
            continue;   % nothing to derive a name from
        end
        % Name the driving line, and show propagation on the source port.
        lh = get_param(ph.Inport(i), 'Line');
        if lh == -1
            continue;
        end
        src = get_param(lh, 'SrcPortHandle');
        report = local_applyToPort(src, name, blk, opts, report);
    end
end

% -------------------------------------------------------------------------
function report = local_applyToPort(portHandle, name, blk, opts, report)
    if portHandle == -1 || isempty(name)
        return;
    end
    lh = get_param(portHandle, 'Line');
    if lh == -1
        return;   % unconnected port
    end
    existing = get_param(lh, 'Name');
    if ~isempty(existing) && ~opts.overwrite
        action = 'kept';
    else
        set_param(lh, 'Name', name);
        action = 'named';
    end
    if opts.propagate
        try
            set_param(portHandle, 'ShowPropagatedSignals', 'on');
        catch
            % Not every port type supports propagated display; ignore.
        end
    end
    report(end + 1) = struct('block', getfullname(blk), ...
                             'port', portHandle, 'name', name, 'action', action); %#ok<AGROW>
end

% -------------------------------------------------------------------------
function name = local_sourceSignalName(inPortHandle)
    % Prefer an existing line name; otherwise fall back to the source block name.
    name = '';
    lh = get_param(inPortHandle, 'Line');
    if lh == -1
        return;
    end
    name = get_param(lh, 'Name');
    if ~isempty(name)
        return;
    end
    src = get_param(lh, 'SrcBlockHandle');
    if src ~= -1
        name = get_param(src, 'Name');
    end
end

% -------------------------------------------------------------------------
function items = local_splitList(str)
    % Split a comma-separated signal list, respecting no nesting (Simulink
    % flattens selected element paths to 'a.b.c' with commas between entries).
    if isempty(str)
        items = {};
        return;
    end
    items = strtrim(strsplit(str, ','));
    items = items(~cellfun(@isempty, items));
end

% -------------------------------------------------------------------------
function leaf = local_leaf(elementPath)
    % Leaf element name: keep the part after the last dot ('bus.sub.sig' -> 'sig').
    parts = strsplit(elementPath, '.');
    leaf = parts{end};
end
