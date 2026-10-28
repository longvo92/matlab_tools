function elements = sortReportElements(elements)
%SORTREPORTELEMENTS List changes first and unchanged rows last (v1.3.2).
%   Keep the original order within each group. Call only after native writes
%   and snapshot creation so display order cannot change transaction targets.
    changed = ismember(elements.Status, ["Change", "Applied"]);
    unchanged = elements.Status == "Unchanged";
    elements = elements([find(changed); find(~changed & ~unchanged); find(unchanged)], :);
end
