function report = nameBusElementSignals(sys, opts)
%NAMEBUSELEMENTSIGNALS Name signal lines after the Element of each In/Out Bus Element block.
%
%   IN BUS ELEMENT : the line leaving the block is named after its Element.
%   OUT BUS ELEMENT: traces upstream through virtual blocks (From/Goto,
%                    SubSystem, Signal Specification/Conversion) to the block
%                    that actually drives the signal, then names the line
%                    there after the Out Bus Element's Element.
%
%   Built for AUTOSAR-style Simulink models whose outermost layer uses the
%   "In Bus Element" / "Out Bus Element" port blocks (the newer bus-element
%   ports, not Bus Selector / Bus Creator). These are Inport/Outport blocks
%   with IsBusElementPort == 'on' and an Element parameter naming the bus
%   element they map to.
%
%   REPORT = NAMEBUSELEMENTSIGNALS() operates on the current system (GCS).
%   REPORT = NAMEBUSELEMENTSIGNALS(SYS) operates on SYS (model name, does not
%            need to be loaded yet, or a subsystem path, e.g. 'Model/Subsys').
%   REPORT = NAMEBUSELEMENTSIGNALS(SYS, OPTS) with an options struct:
%
%     .overwrite           (false) overwrite a line that already has a name
%     .recurse             (true)  also scan subsystems below SYS
%     .traceThroughGoto    (true)  trace From -> Goto when tracing an Out
%                                  Bus Element upstream
%     .traceIntoSubsystem  (true)  descend into SubSystem blocks when tracing
%     .useLeafName         (false) element 'a.b.c' -> 'c' instead of 'a_b_c'
%     .prefix              ('')    prefix added to every signal name
%     .propagate           (true)  set ShowPropagatedSignals='on' on the line
%                                  straight into/out of the bus element port
%     .propagateTracePath  (false) also set ShowPropagatedSignals='on' on the
%                                  intermediate lines walked while tracing an
%                                  Out Bus Element upstream
%     .dryRun              (false) report only, do not call set_param
%     .verbose             (true)  print the result table to the Command
%                                  Window
%     .maxDepth            (20)    max number of hops when tracing upstream
%
%   REPORT is a struct array with fields: block, kind ('In'/'Out'), element,
%   name, parent, status, propagated.
%
%   Example:
%     r = nameBusElementSignals('EVCC_ChargeCtrl', struct('dryRun', true));
%     r = nameBusElementSignals('EVCC_ChargeCtrl', struct('overwrite', true));
%     save_system('EVCC_ChargeCtrl');
%
%   Note: a signal name only anchors the generated variable name when the
%   signal survives codegen optimization / buffer reuse. For names that must
%   stay stable across builds, pair this with a Test Point or a named storage
%   class.
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

    sys = char(sys);
    mdl = strtok(sys, '/');
    if ~bdIsLoaded(mdl)
        load_system(mdl);
    end

    report = local_emptyReport();

    %% ------------------------- IN BUS ELEMENT ---------------------------
    inBlks = local_findBusElementPorts(sys, 'Inport', opts.recurse);
    for i = 1:numel(inBlks)
        blk  = inBlks{i};
        elem = local_elementName(blk);
        if isempty(elem)
            report(end + 1) = local_mkRow(blk, 'In', '', '', '', 'skipped: whole-bus port'); %#ok<AGROW>
            continue;
        end
        nm = local_buildName(elem, opts);
        ph = get_param(blk, 'PortHandles');
        ln = get_param(ph.Outport(1), 'Line');
        [st, nmFinal, parent] = local_applyName(ln, nm, opts);
        prop = local_setPropagated(ln, opts);
        report(end + 1) = local_mkRow(blk, 'In', elem, nmFinal, parent, st, prop); %#ok<AGROW>
    end

    %% ------------------------- OUT BUS ELEMENT --------------------------
    outBlks = local_findBusElementPorts(sys, 'Outport', opts.recurse);
    for i = 1:numel(outBlks)
        blk  = outBlks{i};
        elem = local_elementName(blk);
        if isempty(elem)
            report(end + 1) = local_mkRow(blk, 'Out', '', '', '', 'skipped: whole-bus port'); %#ok<AGROW>
            continue;
        end
        nm = local_buildName(elem, opts);
        ph = get_param(blk, 'PortHandles');
        ln = get_param(ph.Inport(1), 'Line');
        if ~local_isValidLine(ln)
            report(end + 1) = local_mkRow(blk, 'Out', elem, nm, '', 'skipped: unconnected'); %#ok<AGROW>
            continue;
        end
        prop = local_setPropagated(ln, opts);   % line straight into the Out Bus Element
        [lnSrc, srcBlk, note, tracePath] = local_traceUpstream(ln, opts);
        if opts.propagateTracePath
            tracePath(tracePath == ln)    = [];   % already handled above
            tracePath(tracePath == lnSrc) = [];   % this line gets the name below
            for k = 1:numel(tracePath)
                local_setPropagated(tracePath(k), opts);
            end
        end
        if ~local_isValidLine(lnSrc)
            report(end + 1) = local_mkRow(blk, 'Out', elem, nm, '', ['skipped: ' note], prop); %#ok<AGROW>
            continue;
        end
        % Don't overwrite a name already applied by the In Bus Element pass.
        if ~isempty(srcBlk) && local_isBusElementPort(srcBlk)
            report(end + 1) = local_mkRow(blk, 'Out', elem, nm, get_param(lnSrc, 'Parent'), ...
                'skipped: source is In Bus Element', prop); %#ok<AGROW>
            continue;
        end
        [st, nmFinal, parent] = local_applyName(lnSrc, nm, opts);
        if ~isempty(note)
            st = [st ' (' note ')'];
        end
        report(end + 1) = local_mkRow(blk, 'Out', elem, nmFinal, parent, st, prop); %#ok<AGROW>
    end

    %% ------------------------------ output -------------------------------
    if opts.verbose
        local_printReport(report, opts);
    end
    if nargout == 0
        clear report;
    end
end % ==================== end main ====================================


%% ======================= upstream tracing =================================
function [ln, srcBlk, note, visited] = local_traceUpstream(ln, opts)
    note    = '';
    srcBlk  = '';
    visited = [];
    for k = 1:opts.maxDepth
        ln = local_topLine(ln);
        visited(end + 1) = ln; %#ok<AGROW>
        srcPort = get_param(ln, 'SrcPortHandle');
        if srcPort == -1
            note = 'no source port'; ln = -1; return;
        end
        srcBlk = get_param(srcPort, 'Parent');
        bt     = get_param(srcBlk, 'BlockType');

        switch bt
            case 'From'
                if ~opts.traceThroughGoto, return; end
                gt = local_findMatchingGoto(srcBlk);
                if isempty(gt)
                    note = 'matching Goto not found'; return;
                end
                gph = get_param(gt, 'PortHandles');
                nxt = get_param(gph.Inport(1), 'Line');
                if ~local_isValidLine(nxt), note = 'Goto not connected'; return; end
                ln = nxt;

            case 'SubSystem'
                if ~opts.traceIntoSubsystem || local_isStateflowBlock(srcBlk)
                    return;
                end
                pn    = get_param(srcPort, 'PortNumber');
                inner = local_findInnerOutport(srcBlk, pn);
                if isempty(inner)
                    note = 'inner Outport not found'; return;
                end
                iph = get_param(inner, 'PortHandles');
                nxt = get_param(iph.Inport(1), 'Line');
                if ~local_isValidLine(nxt), note = 'inner Outport not connected'; return; end
                ln = nxt;

            case {'SignalSpecification', 'SignalConversion'}
                iph = get_param(srcBlk, 'PortHandles');
                nxt = get_param(iph.Inport(1), 'Line');
                if ~local_isValidLine(nxt), return; end
                ln = nxt;

            otherwise
                return;   % block actually driving the signal -> stop here
        end
    end
    note = 'reached maxDepth';
end

function gt = local_findMatchingGoto(fromBlk)
    gt     = '';
    tag    = get_param(fromBlk, 'GotoTag');
    parent = get_param(fromBlk, 'Parent');
    cand = find_system(parent, 'SearchDepth', 1, 'LookUnderMasks', 'all', ...
        'FollowLinks', 'on', 'BlockType', 'Goto', 'GotoTag', tag);
    if isempty(cand)
        cand = find_system(bdroot(fromBlk), 'LookUnderMasks', 'all', ...
            'FollowLinks', 'on', 'BlockType', 'Goto', 'GotoTag', tag);
    end
    if ~isempty(cand)
        gt = cand{1};
    end
end

function blk = local_findInnerOutport(ss, portNum)
    blk  = '';
    outs = find_system(ss, 'SearchDepth', 1, 'LookUnderMasks', 'all', ...
        'FollowLinks', 'on', 'BlockType', 'Outport');
    for i = 1:numel(outs)
        if str2double(get_param(outs{i}, 'Port')) == portNum
            blk = outs{i}; return;
        end
    end
end


%% ========================== line naming ====================================
function [status, nmFinal, parent] = local_applyName(ln, nm, opts)
    nmFinal = nm; parent = '';
    if ~local_isValidLine(ln)
        status = 'skipped: unconnected'; nmFinal = ''; return;
    end
    ln     = local_topLine(ln);
    parent = get_param(ln, 'Parent');
    cur    = get_param(ln, 'Name');

    if strcmp(cur, nm)
        status = 'ok: already named'; return;
    end
    if ~isempty(cur) && ~opts.overwrite
        status  = sprintf('skipped: already named "%s"', cur);
        nmFinal = cur; return;
    end

    nmFinal = local_makeUniqueName(parent, ln, nm);
    if opts.dryRun
        status = 'dry-run';
    else
        try
            set_param(ln, 'Name', nmFinal);
            status = 'set';
        catch ME
            status = ['error: ' ME.message];
        end
    end
end

function note = local_setPropagated(ln, opts)
    % Turn on propagated-signal label (<sig>) display for a line.
    note = '';
    if ~opts.propagate || ~local_isValidLine(ln)
        return;
    end
    ln = local_topLine(ln);
    try
        if strcmp(get_param(ln, 'ShowPropagatedSignals'), 'on')
            note = 'on(already)'; return;
        end
    catch
        note = 'n/a'; return;      % line does not support this property
    end
    if opts.dryRun
        note = 'dry-run'; return;
    end
    try
        set_param(ln, 'ShowPropagatedSignals', 'on');
        note = 'on';
    catch ME
        note = ['err: ' ME.message];
    end
end

function nm = local_makeUniqueName(parent, ln, nm)
    lines = find_system(parent, 'FindAll', 'on', 'SearchDepth', 1, 'Type', 'line');
    lines(lines == ln) = [];
    if isempty(lines), return; end
    names = get_param(lines, 'Name');
    if ~iscell(names), names = {names}; end
    base = nm; k = 1;
    while any(strcmp(names, nm))
        k  = k + 1;
        nm = sprintf('%s_%d', base, k);
    end
end

function nm = local_buildName(elem, opts)
    if opts.useLeafName
        parts = strsplit(elem, '.');
        elem  = parts{end};
    end
    nm = [opts.prefix elem];
    nm = regexprep(nm, '[^A-Za-z0-9_]', '_');   % '.', '-', space -> '_'
    nm = regexprep(nm, '_+', '_');
    if ~isempty(nm) && ~isempty(regexp(nm(1), '\d', 'once'))
        nm = ['s_' nm];
    end
    if numel(nm) > 60
        nm = nm(1:60);
    end
end


%% ============================ utilities ====================================
function opts = local_defaults(opts)
    defaults = struct('overwrite', false, 'recurse', true, ...
        'traceThroughGoto', true, 'traceIntoSubsystem', true, ...
        'useLeafName', false, 'prefix', '', 'propagate', true, ...
        'propagateTracePath', false, 'dryRun', false, 'verbose', true, ...
        'maxDepth', 20);
    fn = fieldnames(defaults);
    for i = 1:numel(fn)
        if ~isfield(opts, fn{i}) || isempty(opts.(fn{i}))
            opts.(fn{i}) = defaults.(fn{i});
        end
    end
    opts.prefix = char(opts.prefix);
end

function blks = local_findBusElementPorts(sys, bt, recurse)
    args = {'LookUnderMasks', 'all', 'FollowLinks', 'on', 'BlockType', bt};
    if ~recurse
        args = [{'SearchDepth', 1} args];
    end
    cand = find_system(sys, args{:});
    keep = false(size(cand));
    for i = 1:numel(cand)
        keep(i) = local_isBusElementPort(cand{i});
    end
    blks = cand(keep);
end

function tf = local_isBusElementPort(blk)
    tf = false;
    try
        tf = strcmp(get_param(blk, 'IsBusElementPort'), 'on');
    catch
    end
end

function elem = local_elementName(blk)
    elem = '';
    try
        elem = get_param(blk, 'Element');
    catch
    end
    elem = strtrim(char(elem));
    if strcmpi(elem, '?') || strcmpi(elem, '<none>')
        elem = '';
    end
end

function tf = local_isStateflowBlock(blk)
    tf = false;
    try
        sf = get_param(blk, 'SFBlockType');
        tf = ~isempty(sf) && ~strcmpi(sf, 'NONE');
    catch
    end
end

function ln = local_topLine(ln)
    for k = 1:50
        par = get_param(ln, 'LineParent');
        if isempty(par) || par == -1, break; end
        ln = par;
    end
end

function tf = local_isValidLine(ln)
    tf = ~isempty(ln) && all(ishandle(ln)) && all(ln ~= -1);
end

function r = local_emptyReport()
    r = struct('block', {}, 'kind', {}, 'element', {}, 'name', {}, ...
        'parent', {}, 'status', {}, 'propagated', {});
end

function r = local_mkRow(blk, kind, elem, nm, parent, status, prop)
    if nargin < 7, prop = ''; end
    r = struct('block', blk, 'kind', kind, 'element', elem, 'name', nm, ...
        'parent', parent, 'status', status, 'propagated', prop);
end

function local_printReport(report, opts)
    if isempty(report)
        fprintf('No In/Out Bus Element blocks found.\n'); return;
    end
    nSet  = sum(strcmp({report.status}, 'set'));
    nSkip = numel(report) - nSet;
    fprintf('\n%-4s %-4s %-26s %-26s %-10s %s\n', ...
        '#', 'Kind', 'Element', 'Name', 'Prop', 'Status');
    fprintf('%s\n', repmat('-', 1, 120));
    for i = 1:numel(report)
        fprintf('%-4d %-4s %-26s %-26s %-10s %s\n', i, report(i).kind, ...
            local_trunc(report(i).element, 26), local_trunc(report(i).name, 26), ...
            local_trunc(report(i).propagated, 10), report(i).status);
    end
    fprintf('%s\n', repmat('-', 1, 120));
    if opts.dryRun
        fprintf('DRY-RUN: %d block(s), model not modified.\n', numel(report));
    else
        fprintf('Named: %d | Skipped: %d. Remember to save_system if this looks right.\n', nSet, nSkip);
    end
end

function s = local_trunc(s, n)
    s = char(s);
    if numel(s) > n, s = ['...' s(end - n + 4:end)]; end
end
