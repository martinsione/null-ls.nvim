local h = require("null-ls.helpers")
local methods = require("null-ls.methods")

local FORMATTING = methods.internal.FORMATTING

return h.make_builtin({
    name = "fourmolu",
    method = FORMATTING,
    filetypes = { "haskell" },
    generator_opts = {
        command = "fourmolu",
        to_stdin = true,
    },
    factory = h.formatter_factory,
})
