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


local byte = string.byte
local sub = string.sub

local function lookupify(src, list)
    list = list or {}

    if type(src) == "string" then
        for i = 1, #src do
            list[byte(src, i)] = true
        end
    elseif type(src) == "table" then
        for i = 1, #src do
            list[src[i]] = true
        end
    end

    return list
end

local base_ident = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_"
local base_digits = "0123456789"
local base_operators = "+-*/^%#"

local chars = {
    whitespace = lookupify(" \n\t\r"),
    validEscapes = lookupify("abfnrtv\"'\\"),
    ident = lookupify(base_ident .. base_digits, {
        start = lookupify(base_ident),
    }),
    digits = lookupify(base_digits, {
        hex = lookupify(base_digits .. "abcdefABCDEF"),
    }),
    symbols = lookupify(base_operators .. ",{}[]();.:", {
        equality = lookupify("~=><"),
        operators = lookupify(base_operators),
    }),
}

local keywords = {
    structure = lookupify({
        "and",
        "break",
        "do",
        "else",
        "elseif",
        "end",
        "for",
        "function",
        "goto",
        "if",
        "in",
        "local",
        "not",
        "or",
        "repeat",
        "return",
        "then",
        "until",
        "while",
    }),
    values = lookupify({ "true", "false", "nil" }),
}

local NEWLINE = 10
local DASH = 45
local SQUOTE = 39
local DQUOTE = 34
local BACKSLASH = 92
local LBRACKET = 91
local RBRACKET = 93
local EQUALS = 61
local DOT = 46
local COLON = 58
local ZERO = 48
local LOWER_X = 120
local LOWER_E = 101
local UPPER_E = 69

local Lex = function(text)
    local pos = 1
    local start = 1
    local buffer = {}
    local lines = {}

    local function look(delta)
        return byte(text, pos + (delta or 0))
    end

    local function get()
        pos = pos + 1
        return byte(text, pos - 1)
    end

    local function getDataLevel()
        local num = 0

        while byte(text, pos + num) == EQUALS do
            num = num + 1
        end

        if byte(text, pos + num) == LBRACKET then
            pos = pos + num + 1

            return num
        end
    end

    local function getCurrentTokenText()
        return sub(text, start, pos - 1)
    end

    local currentLineLength = 0
    local lineoffset = 0

    local function pushToken(ty)
        local s = start
        local e = pos - 1
        local tlen = e - s + 1

        if tlen > 0 then
            local tk = buffer[#buffer]

            if not tk or tk.type ~= ty then
                buffer[#buffer + 1] = {
                    type = ty,
                    _s = s,
                    _e = e,
                    posFirst = s - lineoffset,
                    posLast = e - lineoffset,
                }
            else
                tk._e = e
                tk.posLast = tk.posLast + tlen
            end

            currentLineLength = currentLineLength + tlen
        end

        start = pos
    end

    local function newline()
        lines[#lines + 1] = buffer
        buffer = {}

        get()
        pushToken("newline")
        buffer[1] = nil

        lineoffset = lineoffset + currentLineLength
        currentLineLength = 0
    end

    local function getData(level, ty)
        while true do
            local char = get()

            if char == nil then
                return
            elseif char == NEWLINE then
                pos = pos - 1
                pushToken(ty)
                newline()
            elseif char == RBRACKET then
                local valid = true

                for _ = 1, level do
                    if look() == EQUALS then
                        pos = pos + 1
                    else
                        valid = false
                        break
                    end
                end

                if valid and look() == RBRACKET then
                    pos = pos - level - 1

                    return
                end
            end
        end
    end

    local function chompWhitespace()
        while true do
            local char = look()

            if char == NEWLINE then
                pushToken("whitespace")
                newline()
            elseif chars.whitespace[char] then
                pos = pos + 1
            else
                break
            end
        end

        pushToken("whitespace")
    end

    while true do
        chompWhitespace()

        local char = get()

        if char == nil then
            break
        elseif char == DASH and look() == DASH then
            pos = pos + 1

            if look() == LBRACKET then
                pos = pos + 1

                local level = getDataLevel()

                if level then
                    getData(level, "comment")

                    pos = pos + level + 2
                    pushToken("comment")
                else
                    while true do
                        local char2 = get()

                        if char2 == nil or char2 == NEWLINE then
                            pos = pos - 1
                            pushToken("comment")

                            if char2 == NEWLINE then
                                newline()
                            end

                            break
                        end
                    end
                end
            else
                while true do
                    local char2 = get()

                    if char2 == nil or char2 == NEWLINE then
                        pos = pos - 1
                        pushToken("comment")

                        if char2 == NEWLINE then
                            newline()
                        end

                        break
                    end
                end
            end

            pushToken("comment")
        elseif char == SQUOTE or char == DQUOTE then
            pushToken("string_start")

            while true do
                local char2 = get()

                if char2 == BACKSLASH then
                    pos = pos - 1
                    pushToken("string")
                    get()

                    local char3 = get()

                    if chars.digits[char3] then
                        for _ = 1, 2 do
                            if chars.digits[look()] then
                                pos = pos + 1
                            end
                        end
                    elseif char3 == LOWER_X then
                        if chars.digits.hex[look()] and chars.digits.hex[look(1)] then
                            pos = pos + 2
                        else
                            pushToken("unidentified")
                        end
                    elseif char3 == NEWLINE then
                        pos = pos - 1
                        pushToken("escape")
                        newline()
                    elseif not chars.validEscapes[char3] then
                        pushToken("unidentified")
                    end

                    pushToken("escape")
                elseif char2 == NEWLINE then
                    pos = pos - 1
                    pushToken("string")
                    newline()

                    break
                elseif char2 == char or char2 == nil then
                    pos = pos - 1
                    pushToken("string")
                    get()

                    break
                end
            end

            pushToken("string_end")
        elseif chars.ident.start[char] then
            while chars.ident[look()] do
                pos = pos + 1
            end

            local word = getCurrentTokenText()

            if keywords.structure[word] then
                pushToken("keyword")
            elseif keywords.values[word] then
                pushToken("value")
            else
                pushToken("ident")
            end
        elseif chars.digits[char] or (char == DOT and chars.digits[look()]) then
            if char == ZERO and look() == LOWER_X then
                pos = pos + 1

                while chars.digits.hex[look()] do
                    pos = pos + 1
                end
            else
                while chars.digits[look()] do
                    pos = pos + 1
                end

                if look() == DOT then
                    pos = pos + 1

                    while chars.digits[look()] do
                        pos = pos + 1
                    end
                end

                local e = look()
                if e == LOWER_E or e == UPPER_E then
                    pos = pos + 1

                    if look() == DASH then
                        pos = pos + 1
                    end

                    while chars.digits[look()] do
                        pos = pos + 1
                    end
                end
            end

            pushToken("number")
        elseif char == LBRACKET then
            local level = getDataLevel()

            if level then
                pushToken("string_start")

                getData(level, "string")
                pushToken("string")

                pos = pos + level + 2
                pushToken("string_end")
            else
                pushToken("symbol")
            end
        elseif char == DOT then
            if look() == DOT then
                pos = pos + 1

                if look() == DOT then
                    pos = pos + 1
                end
            end

            if pos - start == 3 then
                pushToken("vararg")
            else
                pushToken("symbol")
            end
        elseif char == COLON and look() == COLON then
            get()

            pushToken("label_start")

            chompWhitespace()

            if chars.ident.start[look()] then
                get()

                while chars.ident[look()] do
                    get()
                end

                pushToken("label")

                chompWhitespace()

                if look() == COLON and look(1) == COLON then
                    get()
                    get()

                    pushToken("label_end")
                end
            end
        elseif chars.symbols.equality[char] then
            if look() == EQUALS then
                pos = pos + 1
            end

            pushToken("operator")
        elseif chars.symbols[char] then
            if chars.symbols.operators[char] then
                pushToken("operator")
            else
                pushToken("symbol")
            end
        else
            pushToken("unidentified")
        end
    end

    lines[#lines + 1] = buffer

    for li = 1, #lines do
        local line = lines[li]
        for ti = 1, #line do
            local tk = line[ti]
            tk.data = sub(text, tk._s, tk._e)
            tk._s = nil
            tk._e = nil
        end
    end

    return lines
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
	if type(n) ~= "number" then
		n = tonumber(n) or 0
	end
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

local function Vec3(v)
	return ("Vector3.new(%s, %s, %s)"):format(FormatNumber(v.X), FormatNumber(v.Y), FormatNumber(v.Z))
end

local function Color3Lit(v)
	return ("Color3.fromRGB(%d, %d, %d)"):format(
		math.round(v.R * 255),
		math.round(v.G * 255),
		math.round(v.B * 255)
	)
end

local function EnumLit(item)
	return "Enum." .. tostring(item.EnumType) .. "." .. item.Name
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
	local k = next(t)
	while k ~= nil do
		count += 1
		k = next(t, k)
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
	["function"] = function(value)
		return try(function()
			local name, line = debug.info(value, "nl")
			name = (type(name) == "string" and name ~= "") and name or "?"
			return EscapeString(("<function %s@%s>"):format(name, tostring(line or "?")))
		end, '"<function>"')
	end,
	thread = function()
		return '"<thread>"'
	end,
}

local function register(name, builder, fallback)
	SCALAR_HANDLERS[name] = function(value)
		return try(function()
			return builder(value)
		end, fallback or ('"<' .. name .. '>"'))
	end
end

register("Vector3int16", function(v)
	return ("Vector3int16.new(%s, %s, %s)"):format(FormatNumber(v.X), FormatNumber(v.Y), FormatNumber(v.Z))
end)

register("Vector2int16", function(v)
	return ("Vector2int16.new(%s, %s)"):format(FormatNumber(v.X), FormatNumber(v.Y))
end)

register("NumberRange", function(v)
	return ("NumberRange.new(%s, %s)"):format(FormatNumber(v.Min), FormatNumber(v.Max))
end)

register("NumberSequenceKeypoint", function(v)
	return ("NumberSequenceKeypoint.new(%s, %s, %s)"):format(
		FormatNumber(v.Time),
		FormatNumber(v.Value),
		FormatNumber(v.Envelope)
	)
end)

register("NumberSequence", function(v)
	local kps = v.Keypoints
	local parts = {}
	for i = 1, #kps do
		local kp = kps[i]
		parts[i] = ("NumberSequenceKeypoint.new(%s, %s, %s)"):format(
			FormatNumber(kp.Time),
			FormatNumber(kp.Value),
			FormatNumber(kp.Envelope)
		)
	end
	return ("NumberSequence.new({%s})"):format(table.concat(parts, ", "))
end)

register("ColorSequenceKeypoint", function(v)
	return ("ColorSequenceKeypoint.new(%s, %s)"):format(FormatNumber(v.Time), Color3Lit(v.Value))
end)

register("ColorSequence", function(v)
	local kps = v.Keypoints
	local parts = {}
	for i = 1, #kps do
		local kp = kps[i]
		parts[i] = ("ColorSequenceKeypoint.new(%s, %s)"):format(FormatNumber(kp.Time), Color3Lit(kp.Value))
	end
	return ("ColorSequence.new({%s})"):format(table.concat(parts, ", "))
end)

register("Rect", function(v)
	return ("Rect.new(%s, %s, %s, %s)"):format(
		FormatNumber(v.Min.X),
		FormatNumber(v.Min.Y),
		FormatNumber(v.Max.X),
		FormatNumber(v.Max.Y)
	)
end)

register("Ray", function(v)
	return ("Ray.new(%s, %s)"):format(Vec3(v.Origin), Vec3(v.Direction))
end)

register("Region3", function(v)
	local cf = v.CFrame
	local size = v.Size
	local pos = cf.Position
	return ("Region3.new(%s, %s)"):format(Vec3(pos - size / 2), Vec3(pos + size / 2))
end)

register("Region3int16", function(v)
	return ("Region3int16.new(Vector3int16.new(%s, %s, %s), Vector3int16.new(%s, %s, %s))"):format(
		FormatNumber(v.Min.X),
		FormatNumber(v.Min.Y),
		FormatNumber(v.Min.Z),
		FormatNumber(v.Max.X),
		FormatNumber(v.Max.Y),
		FormatNumber(v.Max.Z)
	)
end)

register("Faces", function(v)
	local on = {}
	for _, f in { "Top", "Bottom", "Left", "Right", "Back", "Front" } do
		if v[f] then
			on[#on + 1] = "Enum.NormalId." .. f
		end
	end
	return ("Faces.new(%s)"):format(table.concat(on, ", "))
end)

register("Axes", function(v)
	local on = {}
	for _, a in { "X", "Y", "Z" } do
		if v[a] then
			on[#on + 1] = "Enum.Axis." .. a
		end
	end
	return ("Axes.new(%s)"):format(table.concat(on, ", "))
end)

register("PhysicalProperties", function(v)
	return ("PhysicalProperties.new(%s, %s, %s, %s, %s)"):format(
		FormatNumber(v.Density),
		FormatNumber(v.Friction),
		FormatNumber(v.Elasticity),
		FormatNumber(v.FrictionWeight),
		FormatNumber(v.ElasticityWeight)
	)
end)

register("Font", function(v)
	return ("Font.new(%s, %s, %s)"):format(EscapeString(v.Family), EnumLit(v.Weight), EnumLit(v.Style))
end)

register("TweenInfo", function(v)
	return ("TweenInfo.new(%s, %s, %s, %s, %s, %s)"):format(
		FormatNumber(v.Time),
		EnumLit(v.EasingStyle),
		EnumLit(v.EasingDirection),
		FormatNumber(v.RepeatCount),
		v.Reverses and "true" or "false",
		FormatNumber(v.DelayTime)
	)
end)

register("DateTime", function(v)
	return ("DateTime.fromUnixTimestampMillis(%s)"):format(FormatNumber(v.UnixTimestampMillis))
end)

register("PathWaypoint", function(v)
	return ("PathWaypoint.new(%s, %s)"):format(Vec3(v.Position), EnumLit(v.Action))
end)

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
	if string.sub(descriptor, 1, #vt + 1) == vt .. ":" then
		return EscapeString("<" .. descriptor .. ">")
	end
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
		local key = next(t)
		while key ~= nil do
			if not seen[key] then
				kcount += 1
				keyed[kcount] = key
			end
			key = next(t, key)
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
				keyStr = "[" .. SerializeScalar(key) .. "]"
			end
			ecount += 1
			entries[ecount] = { keyStr = keyStr, value = rawget(t, key) }
		end

		return entries
	end

	local function safeBuildEntries(t)
		return try(function()
			return buildEntries(t)
		end, {})
	end

	local sep = pretty and "," or ", "

	visited[root] = true
	local stack = { { entries = safeBuildEntries(root), i = 1, indent = 0, tableRef = root, sep = "" } }
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
					entries = safeBuildEntries(rawValue),
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

local function Format(code)
	local lines = Lex(code)

	local toks = {}
	local n = 0
	for _, line in lines do
		for _, tk in line do
			local ty = tk.type
			if ty == "whitespace" or ty == "newline" then
				continue
			end
			if ty == "symbol" then
				local data = tk.data
				for c = 1, #data do
					n += 1
					toks[n] = { type = "symbol", data = string.sub(data, c, c) }
				end
			else
				n += 1
				toks[n] = tk
			end
		end
	end

	local out = {}
	local len = 0
	local indent = 0
	local stack = {}
	local sp = 0

	local function emit(s)
		len += 1
		out[len] = s
	end

	local function newline()
		emit("\n" .. string.rep(INDENT, indent))
	end

	local i = 1
	while i <= n do
		local tk = toks[i]
		local d = tk.data

		if d == "{" then
			local nxt = toks[i + 1]
			if nxt and nxt.data == "}" then
				emit("{}")
				i += 2
				continue
			end
			emit("{")
			indent += 1
			sp += 1
			stack[sp] = "{"
			newline()
		elseif d == "}" then
			indent -= 1
			if stack[sp] == "{" then
				stack[sp] = nil
				sp -= 1
			end
			newline()
			emit("}")
		elseif d == "(" then
			emit("(")
			sp += 1
			stack[sp] = "("
		elseif d == ")" then
			if stack[sp] == "(" then
				stack[sp] = nil
				sp -= 1
			end
			emit(")")
		elseif d == "," then
			local nxt = toks[i + 1]
			if nxt and nxt.data == "}" then
				i += 1
				continue
			end
			emit(",")
			if stack[sp] == "{" then
				newline()
			else
				emit(" ")
			end
		elseif tk.type == "operator" and d == "=" then
			emit(" = ")
		else
			emit(d)
		end

		i += 1
	end

	return table.concat(out)
end

Data2Code.Format = Format

function Data2Code.Convert(data, pretty)
	local errHandler = function(err)
		return "--[[ Data2Code.Convert error: " .. FunctionLibrary.SafeString(err) .. " ]] nil"
	end

	local ok, compact = xpcall(function()
		return SerializeRoot(data, false)
	end, errHandler)
	if not ok then
		return compact
	end

	if not pretty then
		return compact
	end

	local fok, formatted = pcall(Format, compact)
	if fok and type(formatted) == "string" and formatted ~= "" then
		return formatted
	end

	local ok2, legacy = xpcall(function()
		return SerializeRoot(data, true)
	end, errHandler)
	if ok2 then
		return legacy
	end
	return compact
end
