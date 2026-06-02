--!early version
local Data2Code = {}

local FunctionLibrary = require("@Utility/FunctionLibrary")

local INDENT = "    "

local SafeString = FunctionLibrary.SafeString
local FunctionInfo = FunctionLibrary.FunctionInfo

local byte = string.byte
local sub = string.sub
local format = string.format
local concat = table.concat
local insert = table.insert
local rep = string.rep
local floor = math.floor
local abs = math.abs
local round = math.round
local huge = math.huge

local function try(fn, fallback)
	local ok, res = xpcall(fn, function() return fallback end)
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
		str = SafeString(str)
	end
	local n = #str
	local out = table.create(n + 2)
	out[1] = '"'
	local len = 1
	for i = 1, n do
		local b = byte(str, i)
		local esc = ESCAPES[b]
		if esc then
			len += 1
			out[len] = esc
		elseif b >= 32 and b <= 126 then
			len += 1
			out[len] = sub(str, i, i)
		else
			len += 1
			out[len] = format("\\%03d", b)
		end
	end
	out[len + 1] = '"'
	return concat(out)
end

local function FormatNumber(n)
	if n ~= n then
		return "0/0"
	elseif n == huge then
		return "math.huge"
	elseif n == -huge then
		return "-math.huge"
	elseif n == floor(n) and abs(n) < 1e15 then
		return format("%d", n)
	end
	return format("%.14g", n)
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
			return concat(segments)
		end

		local parent = try(function() return current.Parent end, nil)
		local name = try(function() return current.Name end, "Instance")

		if parent == game then
			local isService = pcall(function()
				return game:GetService(name)
			end)
			if isService then
				table.insert(segments, 1, `game:GetService({EscapeString(name)})`)
			else
				table.insert(segments, 1, "game" .. ChildSegment(name))
			end
			return concat(segments)
		end

		if not parent then
			local className = try(function() return current.ClassName end, "Instance")
			return EscapeString(("<unparented %s: %s>"):format(className, name))
		end

		table.insert(segments, 1, ChildSegment(name))
		current = parent
	end

	return EscapeString("<unresolved instance>")
end

local function IsPureArray(t)
	local count = 0
	for _ in next, t do
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

local function SerializeScalar(value)
	local vt = try(function() return typeof(value) end, "unknown")

	if value == nil then
		return "nil"
	elseif vt == "string" then
		return EscapeString(value)
	elseif vt == "number" then
		return FormatNumber(value)
	elseif vt == "boolean" then
		return value and "true" or "false"
	elseif vt == "Instance" then
		return try(function() return GetInstancePath(value) end, '"<instance>"')
	elseif vt == "EnumItem" then
		return try(function() return SafeString(value) end, '"<EnumItem>"')
	elseif vt == "Enum" then
		return try(function() return "Enum." .. SafeString(value) end, '"<Enum>"')
	elseif vt == "Vector3" then
		return try(function()
			return ("Vector3.new(%s, %s, %s)"):format(
				FormatNumber(value.X), FormatNumber(value.Y), FormatNumber(value.Z)
			)
		end, '"<Vector3>"')
	elseif vt == "Vector2" then
		return try(function()
			return ("Vector2.new(%s, %s)"):format(FormatNumber(value.X), FormatNumber(value.Y))
		end, '"<Vector2>"')
	elseif vt == "Color3" then
		return try(function()
			return ("Color3.fromRGB(%d, %d, %d)"):format(
				round(value.R * 255), round(value.G * 255), round(value.B * 255)
			)
		end, '"<Color3>"')
	elseif vt == "CFrame" then
		return try(function()
			local comps = { value:GetComponents() }
			for i = 1, #comps do
				comps[i] = FormatNumber(comps[i])
			end
			return ("CFrame.new(%s)"):format(concat(comps, ", "))
		end, '"<CFrame>"')
	elseif vt == "UDim2" then
		return try(function()
			return ("UDim2.new(%s, %s, %s, %s)"):format(
				FormatNumber(value.X.Scale), FormatNumber(value.X.Offset),
				FormatNumber(value.Y.Scale), FormatNumber(value.Y.Offset)
			)
		end, '"<UDim2>"')
	elseif vt == "UDim" then
		return try(function()
			return ("UDim.new(%s, %s)"):format(FormatNumber(value.Scale), FormatNumber(value.Offset))
		end, '"<UDim>"')
	elseif vt == "BrickColor" then
		return try(function()
			return ("BrickColor.new(%s)"):format(EscapeString(value.Name))
		end, '"<BrickColor>"')
	elseif vt == "RBXScriptConnection" then
		return '"<RBXScriptConnection>"'
	elseif vt == "RBXScriptSignal" then
		return '"<RBXScriptSignal>"'
	elseif vt == "function" then
		return '"<function>"'
	elseif vt == "thread" then
		return '"<thread>"'
	end

	local descriptor = try(function()
		return SafeString(value):gsub("[%c]", " ")
	end, "<" .. SafeString(vt) .. ">")
	return EscapeString(("<%s: %s>"):format(vt, descriptor))
end

local function SerializeRoot(root, pretty)
	local function normalize(v)
		if try(function() return typeof(v) end, "") == "function" then
			return try(function() return FunctionInfo(v) end, "<function>")
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
		local pure, arrayLen = try(function() return IsPureArray(t) end, false)
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
		for key in next, t do
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
				return SafeString(ta) < SafeString(tb)
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
				emit("\n" .. rep(INDENT, frame.indent))
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
				emit(("\n%s%s = "):format(rep(INDENT, nextIndent), entry.keyStr))
			else
				emit("\n" .. rep(INDENT, nextIndent))
			end
		elseif entry.keyStr then
			emit(entry.keyStr .. " = ")
		end

		if try(function() return typeof(rawValue) end, "") == "table" then
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

	return concat(out)
end

function Data2Code.Convert(data, pretty)
	local ok, result = xpcall(function()
		return SerializeRoot(data, pretty)
	end, function(err)
		return "--[[ Data2Code.Convert error: " .. SafeString(err) .. " ]] nil"
	end)
	return result
end

return Data2Code
