function applyCodeMapping(adapter, tasks)
%APPLYCODEMAPPING Apply grouped native mappings with recovery (v1.3.1).
    dirty = get_param(char(adapter.Model), 'Dirty');
    attempted = [];
    try
        for k = 1:numel(tasks)
            if ~tasks(k).Changed, continue; end
            attempted(end + 1) = k; %#ok<AGROW>
            adapter.write(tasks(k).Record, tasks(k).After, tasks(k).Before);
        end
        for k = 1:numel(tasks)
            local_verify(adapter.read(tasks(k).Record), tasks(k).After, tasks(k).Record.Element);
        end
    catch cause
        failure = MException('AutosarMapping:ApplyFailed', ...
            'Code Mapping apply failed in %s; attempted mapping rollback. Inspect exception causes.', adapter.Model);
        failure = addCause(failure, cause);
        restored = true;
        % Native mappings can share an AUTOSAR entity. Restore matching rows
        % too if another setter changed their underlying entity indirectly.
        restore = false(1, numel(tasks));
        restore(attempted) = true;
        for k = 1:numel(tasks)
            if restore(k), continue; end
            try
                local_verify(adapter.read(tasks(k).Record), tasks(k).Before, tasks(k).Record.Element);
            catch
                restore(k) = true;
            end
        end
        for k = fliplr(find(restore))
            try
                try
                    current = adapter.read(tasks(k).Record);
                catch
                    % A partial native write may make the mapping unreadable.
                    % In that case, attempt a full restore from the snapshot.
                    current = struct();
                end
                adapter.write(tasks(k).Record, tasks(k).Before, current);
                local_verify(adapter.read(tasks(k).Record), tasks(k).Before, tasks(k).Record.Element);
            catch rollbackCause
                restored = false;
                failure = addCause(failure, rollbackCause);
            end
        end
        if restored, set_param(char(adapter.Model), 'Dirty', dirty); end
        throwAsCaller(failure);
    end
end

function local_verify(actual, expected, element)
    for name = string(fieldnames(expected))'
        if ~isfield(actual, char(name)) || actual.(char(name)) ~= expected.(char(name))
            error('AutosarMapping:Readback', 'Readback failed for %s/%s.', element, name);
        end
    end
end
