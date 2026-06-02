-- cut down version of function library from GCVIEW
local FunctionLibrary = {}
FunctionLibrary.SafeString = function(Object)
    local Metatable = getrawmetatable(Object)
    local IsTable = typeof(Object) == "table" or typeof(Object) == "userdata"
    local __tostring = Metatable and rawget(Metatable, "__tostring")

    if not IsTable or type(__tostring) ~= "function" then
        return tostring(Object)
    end

    rawset(Metatable, "__tostring", nil)
    local String = tostring(Object)
    rawset(Metatable, "__tostring", __tostring)

    return String
end

FunctionLibrary.FunctionInfo = function(func)
    local source, line, name, numparams, vargs = debug.info(func, "slna")
    return {
        source = source,
        line = line,
        name = name,
        numparams = numparams,
        vargs = vargs,
    }
end

return FunctionLibrary
