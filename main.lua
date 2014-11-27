local MAJOR = "LibBodyguard-1.0"
local MINOR = 1

local lib
if LibStub then
    lib = LibStub:NewLibrary(MAJOR, MINOR)
    if not lib then return end
else
    lib = {}
end

return lib
