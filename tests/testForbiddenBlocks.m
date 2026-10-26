function testForbiddenBlocks()
%TESTFORBIDDENBLOCKS Verify reference coverage cannot silently produce PASS.
    previousPath = path;
    restore = onCleanup(@() path(previousPath));
    repo = fileparts(fileparts(mfilename('fullpath')));
    addpath(fullfile(repo, 'tools', 'forbidden_blocks'));
    sandbox = tempname;
    mkdir(sandbox);
    addpath(sandbox);
    [~, root] = fileparts(tempname);
    [~, child] = fileparts(tempname);
    new_system(root);
    rootCleanup = onCleanup(@() close_system(root, 0));
    new_system(child);
    childCleanup = onCleanup(@() close_system(child, 0));
    save_system(child, fullfile(sandbox, [child '.slx']));
    block = [root '/Reference'];
    add_block('built-in/ModelReference', block, 'ModelName', child);
    result = checkForbiddenBlocks(root);
    assert(result.Passed && numel(result.ModelsChecked) == 2);
    add_block('built-in/ToWorkspace', [child '/Forbidden']);
    save_system(child);
    local_expectError(@() checkForbiddenBlocks(root), 'BlockChecker:Failed');
    [~, missing] = fileparts(tempname);
    set_param(block, 'ModelName', missing);
    local_expectError(@() checkForbiddenBlocks(root), 'BlockChecker:ReferencedModel');
    local_expectError(@() checkForbiddenBlocks(root, struct('failOnWarning', true)), ...
        'BlockChecker:ReferencedModel');
    result = checkForbiddenBlocks(root, struct('checkReferencedModels', false));
    assert(result.Passed && isequal(result.ModelsChecked, {root}));
    add_block('built-in/Scope', [root '/Scope']);
    result = checkForbiddenBlocks(root, struct('checkReferencedModels', false));
    assert(result.Passed && result.WarningCount == 1 && height(result.Violations) == 1);
    local_expectError(@() checkForbiddenBlocks(root, ...
        struct('checkReferencedModels', false, 'failOnWarning', true)), 'BlockChecker:Failed');
    add_block('built-in/Scope', [root '/OtherScope']);
    result = checkForbiddenBlocks(root, struct('checkReferencedModels', false));
    assert(result.Passed && result.WarningCount == 2 && height(result.Violations) == 2);
    fprintf('PASS: reference coverage, single/multiple violations, missing references, root-only scan.\n');
end

function local_expectError(action, identifier)
    rejected = false;
    try
        action();
    catch ME
        rejected = strcmp(ME.identifier, identifier);
        if ~rejected, rethrow(ME); end
    end
    assert(rejected, 'Expected error: %s', identifier);
end
