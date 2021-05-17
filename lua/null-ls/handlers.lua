local methods = require("null-ls.methods")
local code_actions = require("null-ls.code-actions")
local diagnostics = require("null-ls.diagnostics")

local lsp = vim.lsp
local handlers = lsp.handlers

local originals = {
    buf_request = lsp.buf_request,
    buf_request_all = lsp.buf_request_all,
    buf = {execute_command = lsp.buf.execute_command}
}

local capabilities_map = {[methods.lsp.CODE_ACTION] = "code_action"}

local has_capability = function(client, method)
    return client.resolved_capabilities[capabilities_map[method]]
end

local get_expected_client_count = function(bufnr, method)
    local expected = 0
    local clients = lsp.buf_get_clients(bufnr)
    if not clients then return expected end

    for _, client in pairs(clients) do
        if has_capability(client, method) then expected = expected + 1 end
    end
    return expected
end

-- many code action implementations (including the built-in vim.lsp.buf.code_action)
-- use buf_request + a handler callback, which will be called once for each server
-- that returns code action results
--
-- we use a wrapper to combine results from all servers
-- and only call the handler once we have the expected number (much like buf_request_all)
local handle_all_factory = function(handler, method, bufnr)
    local expected = get_expected_client_count(bufnr, method)
    local completed = 0

    local all_results = {}
    return function(_, _, results, client_id)
        vim.list_extend(all_results, results or {})
        completed = completed + 1

        if completed >= expected then
            handler(nil, nil, all_results, client_id, bufnr)
        end
    end
end

local should_wrap = function(method, params)
    return method == methods.lsp.CODE_ACTION and not params._null_ls_skip
end

local M = {}
M.originals = originals

M.setup = function()
    lsp.buf_request = M.buf_request
    lsp.buf_request_all = M.buf_request_all
end

M.reset = function()
    lsp.buf_request = originals.buf_request
    lsp.buf_request_all = originals.buf_request_all
end

M.buf_request = function(bufnr, method, params, original_handler)
    original_handler = original_handler or handlers[method]
    local handler = original_handler

    if should_wrap(method, params) then
        handler = handle_all_factory(original_handler, method, bufnr)
    end

    return originals.buf_request(bufnr, method, params, handler)
end

-- buf_request_all already wraps its handler,
-- so we set a flag to make sure we skip it
M.buf_request_all = function(bufnr, method, params, callback)
    if not params then params = {} end
    params._null_ls_skip = true

    return originals.buf_request_all(bufnr, method, params, callback)
end

M.setup_client = function(client)
    local original_request = client.request

    client.notify = function(method, params)
        if method == methods.lsp.DID_OPEN or method == methods.lsp.DID_CHANGE then
            params.method = method
            diagnostics.handler(params)
        end

        -- no need to send notifications to server,
        -- but we return true to indicate that the notification was received
        return true
    end

    client.request = function(method, params, handler, bufnr)
        params.method = method
        code_actions.handler(method, params, handler, bufnr)

        -- handled requests should return false to avoid cancellation attempts
        if params._null_ls_handled then return false end

        -- call original handler to pass non-handled requests through to server
        return original_request(method, params, handler, bufnr)
    end
end

return M