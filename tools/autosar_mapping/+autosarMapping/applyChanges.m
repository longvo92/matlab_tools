function applyChanges(model, plan, readValue, writeValue)
%APPLYCHANGES Internal SwAddrMethod transaction helper (version 1.3.2).
%   Uses the preflight plan and native mapping callbacks. Tests can inject
%   setter failures without replacing MATLAB's AUTOSAR API on the path.
    changed = find(plan.Status == "Change");
    scope = find(plan.Status == "Change" | plan.Status == "Unchanged");
    dirty = get_param(model, 'Dirty');
    attempted = [];
    try
        for k = changed'
            attempted(end + 1) = k; %#ok<AGROW>
            writeValue(k, plan.Desired(k));
        end
        % Include rows that matched before apply to detect coupled changes.
        for k = scope'
            if readValue(k) ~= plan.Desired(k)
                error('AutosarMapping:Readback', 'SwAddrMethod readback failed for %s.', plan.Element(k));
            end
        end
    catch cause
        failure = MException('AutosarMapping:ApplyFailed', ...
            'Could not apply SwAddrMethods in %s. Attempted rollback; inspect exception causes.', model);
        failure = addCause(failure, cause);
        restored = true;
        for k = fliplr(attempted)
            try
                writeValue(k, plan.Current(k));
                if readValue(k) ~= plan.Current(k)
                    error('AutosarMapping:RollbackReadback', 'Rollback readback failed for %s.', plan.Element(k));
                end
            catch rollbackCause
                restored = false;
                failure = addCause(failure, rollbackCause);
            end
        end
        if restored, set_param(model, 'Dirty', dirty); end
        throwAsCaller(failure);
    end
end
