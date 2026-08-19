function report = nameBusElementSignals(sys, opts)
%NAMEBUSELEMENTSIGNALS Name signals after the In/Out Bus Element block they connect to.
%
%   Built for AUTOSAR-style Simulink models whose outermost layer uses the
%   "In Bus Element" and "Out Bus Element" port blocks (the newer bus-element
%   ports, not Bus Selector / Bus Creator). Each block already knows the bus
%   element it maps to via its 'Element' parameter; this tool copies that name
%   onto the connected signal line and turns on propagated-signal display so the
%   name flows through the model without labelling every hop by hand.
%
%   REPORT = NAMEBUSELEMENTSIGNALS() operates on the current system (GCS).
%   REPORT = NAMEBUSELEMENTSIGNALS(SYS) operates on SYS (name or handle).
%   REPORT = NAMEBUSELEMENTSIGNALS(SYS, OPTS) with an options struct:
%       .direction   'in' | 'out' | 'both'   (default 'both')
%                    'in'  = name the output line of each In Bus Element block.
%                    'out' = name the input line of each Out Bus Element block.
%       .overwrite   logical (default false)  overwrite lines that already
%                    have a name; false only names unnamed lines.
%       .propagate   logical (default true)   set ShowPropagatedSignals='on'
%                    on the ports so downstream blocks display the name.
%       .recurse     logical (default true)   also descend into subsystems.
%
%   REPORT is a struct array of the signals touched: block, port, name, action.
%
%   In/Out Bus Element blocks are Inport/Outport blocks that carry an 'Element'
%   parameter; the leaf of that element path (e.g. 'busA.sub.sig' -> 'sig') is
%   used as the signal name. If 'Element' is empty the block's own name is used.
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
        blocks = find_system(sys, findArgs{:}, 'BlockType', 'Inport');
        for k = 1:numel(blocks)
            if local_isBusElementPort(blocks(k))
                report = local_nameOutgoing(blocks(k), opts, report);
            end
        end
    end

    if any(strcmp(opts.direction, {'out', 'both'}))
        blocks = find_system(sys, findArgs{:}, 'BlockType', 'Outport');
        for k = 1:numel(blocks)
            if local_isBusElementPort(blocks(k))
                report = local_nameIncoming(blocks(k), opts, report);
            end
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
function tf = local_isBusElementPort(blk)
    % In/Out Bus Element blocks are Inport/Outport blocks exposing an 'Element'
    % parameter; plain Inport/Outport blocks do not.
    op = get_param(blk, 'ObjectParameters');
    tf = isfield(op, 'Element');
end

% -------------------------------------------------------------------------
function report = local_nameOutgoing(blk, opts, report)
    % In Bus Element: name the single output line after the block's element.
    name = local_elementName(blk);
    ph = get_param(blk, 'PortHandles');
    if isempty(ph.Outport)
        return;
    end
    report = local_applyToPort(ph.Outport(1), name, blk, opts, report);
end

% -------------------------------------------------------------------------
function report = local_nameIncoming(blk, opts, report)
    % Out Bus Element: name the line driving its input after the block's element.
    name = local_elementName(blk);
    ph = get_param(blk, 'PortHandles');
    if isempty(ph.Inport)
        return;
    end
    lh = get_param(ph.Inport(1), 'Line');
    if lh == -1
        return;
    end
    src = get_param(lh, 'SrcPortHandle');
    report = local_applyToPort(src, name, blk, opts, report);
end

% -------------------------------------------------------------------------
function name = local_elementName(blk)
    op = get_param(blk, 'ObjectParameters');
    if isfield(op, 'Element')
        name = get_param(blk, 'Element');
    else
        name = '';
    end
    if isempty(name)
        name = get_param(blk, 'Name');   % fall back to the block name
    end
    name = local_leaf(name);
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
function leaf = local_leaf(elementPath)
    % Leaf element name: keep the part after the last dot ('bus.sub.sig' -> 'sig').
    parts = strsplit(elementPath, '.');
    leaf = parts{end};
end
