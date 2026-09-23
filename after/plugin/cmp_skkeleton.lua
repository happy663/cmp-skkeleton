local cmp = require("cmp")
local source = require("cmp_skkeleton").new()

cmp.register_source("skkeleton", source)
source:setup(cmp)
