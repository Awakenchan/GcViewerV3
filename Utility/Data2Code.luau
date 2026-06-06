--!early version
--!edited bundler version
local Data2Code = {}
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


local INDENT = "    "

local function try(fn, fallback)
	local ok, res = xpcall(fn, function()
		return fallback
	end)
	if ok then
		return res
	end
	return fallback
end

local function IsIdentifier(str)
	return type(str) == "string" and str:match("^[%a_][%w_]*$") ~= nil
end

local ESCAPES = {
	[34] = '\\"',
	[92] = "\\\\",
	[7] = "\\a",
	[8] = "\\b",
	[9] = "\\t",
	[10] = "\\n",
	[11] = "\\v",
	[12] = "\\f",
	[13] = "\\r",
}

local function EscapeString(str)
	if type(str) ~= "string" then
		str = FunctionLibrary.SafeString(str)
	end
	local n = #str
	local out = table.create(n + 2)
	out[1] = '"'
	local len = 1
	for i = 1, n do
		local b = string.byte(str, i)
		local esc = ESCAPES[b]
		if esc then
			len += 1
			out[len] = esc
		elseif b >= 32 and b <= 126 then
			len += 1
			out[len] = string.sub(str, i, i)
		else
			len += 1
			out[len] = string.format("\\%03d", b)
		end
	end
	out[len + 1] = '"'
	return table.concat(out)
end

local function FormatNumber(n)
	if n ~= n then
		return "0/0"
	elseif n == math.huge then
		return "math.huge"
	elseif n == -math.huge then
		return "-math.huge"
	elseif n == math.floor(n) and math.abs(n) < 1e15 then
		return string.format("%d", n)
	end
	return string.format("%.14g", n)
end

local function ChildSegment(name)
	if IsIdentifier(name) then
		return "." .. name
	end
	return "[" .. EscapeString(name) .. "]"
end

local function GetInstancePath(instance)
	if instance == game then
		return "game"
	end

	local segments = {}
	local current = instance
	local guard = 0

	while current do
		guard += 1
		if guard > 512 then
			return EscapeString("<deep instance>")
		end

		if current == game then
			table.insert(segments, 1, "game")
			return table.concat(segments)
		end

		local parent = try(function()
			return current.Parent
		end, nil)
		local name = try(function()
			return current.Name
		end, "Instance")

		if parent == game then
			local isService = pcall(function()
				return game:GetService(name)
			end)
			if isService then
				table.insert(segments, 1, `game:GetService({EscapeString(name)})`)
			else
				table.insert(segments, 1, "game" .. ChildSegment(name))
			end
			return table.concat(segments)
		end

		if not parent then
			local className = try(function()
				return current.ClassName
			end, "Instance")
			return EscapeString(("<unparented %s: %s>"):format(className, name))
		end

		table.insert(segments, 1, ChildSegment(name))
		current = parent
	end

	return EscapeString("<unresolved instance>")
end

local function IsPureArray(t)
	local count = 0
	for _ in t do
		count += 1
	end
	local len = rawlen(t)
	if count ~= len then
		return false, len
	end
	for i = 1, len do
		if rawget(t, i) == nil then
			return false, len
		end
	end
	return true, len
end

local SCALAR_HANDLERS = {
	string = function(value)
		return EscapeString(value)
	end,
	number = function(value)
		return FormatNumber(value)
	end,
	boolean = function(value)
		return value and "true" or "false"
	end,
	Instance = function(value)
		return try(function()
			return GetInstancePath(value)
		end, '"<instance>"')
	end,
	EnumItem = function(value)
		return try(function()
			return FunctionLibrary.SafeString(value)
		end, '"<EnumItem>"')
	end,
	Enum = function(value)
		return try(function()
			return "Enum." .. FunctionLibrary.SafeString(value)
		end, '"<Enum>"')
	end,
	Vector3 = function(value)
		return try(function()
			return ("Vector3.new(%s, %s, %s)"):format(
				FormatNumber(value.X),
				FormatNumber(value.Y),
				FormatNumber(value.Z)
			)
		end, '"<Vector3>"')
	end,
	Vector2 = function(value)
		return try(function()
			return ("Vector2.new(%s, %s)"):format(FormatNumber(value.X), FormatNumber(value.Y))
		end, '"<Vector2>"')
	end,
	Color3 = function(value)
		return try(function()
			return ("Color3.fromRGB(%d, %d, %d)"):format(
				math.round(value.R * 255),
				math.round(value.G * 255),
				math.round(value.B * 255)
			)
		end, '"<Color3>"')
	end,
	CFrame = function(value)
		return try(function()
			local comps = { value:GetComponents() }
			for i = 1, #comps do
				comps[i] = FormatNumber(comps[i])
			end
			return ("CFrame.new(%s)"):format(table.concat(comps, ", "))
		end, '"<CFrame>"')
	end,
	UDim2 = function(value)
		return try(function()
			return ("UDim2.new(%s, %s, %s, %s)"):format(
				FormatNumber(value.X.Scale),
				FormatNumber(value.X.Offset),
				FormatNumber(value.Y.Scale),
				FormatNumber(value.Y.Offset)
			)
		end, '"<UDim2>"')
	end,
	UDim = function(value)
		return try(function()
			return ("UDim.new(%s, %s)"):format(FormatNumber(value.Scale), FormatNumber(value.Offset))
		end, '"<UDim>"')
	end,
	BrickColor = function(value)
		return try(function()
			return ("BrickColor.new(%s)"):format(EscapeString(value.Name))
		end, '"<BrickColor>"')
	end,
	RBXScriptConnection = function()
		return '"<RBXScriptConnection>"'
	end,
	RBXScriptSignal = function()
		return '"<RBXScriptSignal>"'
	end,
	["function"] = function()
		return '"<function>"'
	end,
	thread = function()
		return '"<thread>"'
	end,
}

local function SerializeScalar(value)
	if value == nil then
		return "nil"
	end

	local vt = try(function()
		return typeof(value)
	end, "unknown")

	local handler = SCALAR_HANDLERS[vt]
	if handler then
		return handler(value)
	end

	local descriptor = try(function()
		return (FunctionLibrary.SafeString(value):gsub("[%c]", " "))
	end, "<" .. FunctionLibrary.SafeString(vt) .. ">")
	return EscapeString(("<%s: %s>"):format(vt, descriptor))
end

local function SerializeRoot(root, pretty)
	local function normalize(v)
		if try(function()
			return typeof(v)
		end, "") == "function" then
			return try(function()
				return FunctionLibrary.FunctionInfo(v)
			end, "<function>")
		end
		return v
	end

	root = normalize(root)

	if typeof(root) ~= "table" then
		return SerializeScalar(root)
	end

	local out = {}
	local len = 0
	local visited = {}

	local function emit(s)
		len += 1
		out[len] = s
	end

	local function buildEntries(t)
		local entries = {}
		local ecount = 0
		local pure, arrayLen = try(function()
			return IsPureArray(t)
		end, false)
		arrayLen = arrayLen or rawlen(t)

		if pure then
			for idx = 1, arrayLen do
				ecount += 1
				entries[ecount] = { keyStr = nil, value = rawget(t, idx) }
			end
			return entries
		end

		local seen = {}
		for idx = 1, arrayLen do
			if rawget(t, idx) == nil then
				break
			end
			seen[idx] = true
			ecount += 1
			entries[ecount] = { keyStr = nil, value = rawget(t, idx) }
		end

		local keyed = {}
		local kcount = 0
		for key in t do
			if not seen[key] then
				kcount += 1
				keyed[kcount] = key
			end
		end

		pcall(function()
			table.sort(keyed, function(a, b)
				local ta, tb = typeof(a), typeof(b)
				if ta == "string" and tb == "string" then
					return a < b
				end
				return FunctionLibrary.SafeString(ta) < FunctionLibrary.SafeString(tb)
			end)
		end)

		for i = 1, kcount do
			local key = keyed[i]
			local keyStr
			if type(key) == "string" and IsIdentifier(key) then
				keyStr = key
			else
				keyStr = "[" .. SerializeScalar(normalize(key)) .. "]"
			end
			ecount += 1
			entries[ecount] = { keyStr = keyStr, value = rawget(t, key) }
		end

		return entries
	end

	local sep = pretty and "," or ", "

	visited[root] = true
	local stack = { { entries = buildEntries(root), i = 1, indent = 0, tableRef = root, sep = "" } }
	local depth = 1
	emit("{")

	while depth > 0 do
		local frame = stack[depth]
		local entries = frame.entries
		local fi = frame.i

		if fi > #entries then
			if pretty and #entries > 0 then
				emit("\n" .. string.rep(INDENT, frame.indent))
			end
			emit("}")
			emit(frame.sep)
			visited[frame.tableRef] = nil
			stack[depth] = nil
			depth -= 1
			continue
		end

		local entry = entries[fi]
		frame.i = fi + 1

		local rawValue = normalize(entry.value)
		local nextIndent = frame.indent + 1

		if pretty then
			if entry.keyStr then
				emit(("\n%s%s = "):format(string.rep(INDENT, nextIndent), entry.keyStr))
			else
				emit("\n" .. string.rep(INDENT, nextIndent))
			end
		elseif entry.keyStr then
			emit(entry.keyStr .. " = ")
		end

		if try(function()
			return typeof(rawValue)
		end, "") == "table" then
			if visited[rawValue] then
				emit('"<cyclic table>"')
				emit(sep)
			else
				visited[rawValue] = true
				emit("{")
				depth += 1
				stack[depth] = {
					entries = buildEntries(rawValue),
					i = 1,
					indent = nextIndent,
					tableRef = rawValue,
					sep = sep,
				}
			end
		else
			emit(SerializeScalar(rawValue))
			emit(sep)
		end
	end

	return table.concat(out)
end

function Data2Code.Convert(data, pretty)
	local ok, result = xpcall(function()
		return SerializeRoot(data, pretty)
	end, function(err)
		return "--[[ Data2Code.Convert error: " .. FunctionLibrary.SafeString(err) .. " ]] nil"
	end)
	return result
end

return Data2Code
