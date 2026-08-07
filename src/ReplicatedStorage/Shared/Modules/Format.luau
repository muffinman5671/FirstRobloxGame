--!strict
--[[
	Format
	Number and time presentation. Pure functions, no Roblox API surface, so the
	Tests/ suite can run these headless.

	abbreviate() keeps three significant digits and trims trailing zeros, which
	is what produces the doc's target shapes: 1.25K, 3.4M, 12.1B.
]]

local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }
local THRESHOLD = 1000

-- Strips "1.20" -> "1.2" and "3.00" -> "3", leaving integers untouched.
local function trimZeros(text: string): string
	if not string.find(text, "%.") then
		return text
	end
	text = string.gsub(text, "0+$", "")
	text = string.gsub(text, "%.$", "")
	return text
end

--[[
	abbreviate(1250)         -> "1.25K"
	abbreviate(3400000)      -> "3.4M"
	abbreviate(12100000000)  -> "12.1B"
	abbreviate(999)          -> "999"
	abbreviate(-4500)        -> "-4.5K"
]]
function Format.abbreviate(value: number): string
	if value ~= value then -- NaN
		return "0"
	end
	if value == math.huge then
		return "\u{221E}"
	end
	if value == -math.huge then
		return "-\u{221E}"
	end

	local sign = if value < 0 then "-" else ""
	local n = math.abs(value)

	if n < THRESHOLD then
		-- Sub-thousand values read better as plain integers.
		return sign .. tostring(math.floor(n))
	end

	local exponent = math.floor(math.log(n, THRESHOLD))
	exponent = math.clamp(exponent, 1, #SUFFIXES - 1)

	local mantissa = n / (THRESHOLD ^ exponent)

	-- Rounding can push 999.95K to 1000.00K; roll up to the next suffix.
	if mantissa >= THRESHOLD - 0.5 and exponent < #SUFFIXES - 1 then
		exponent += 1
		mantissa = n / (THRESHOLD ^ exponent)
	end

	-- Three significant digits: 0dp at 100+, 1dp at 10+, 2dp below that.
	local decimals = if mantissa >= 100 then 0 elseif mantissa >= 10 then 1 else 2
	local text = string.format("%." .. decimals .. "f", mantissa)

	return sign .. trimZeros(text) .. SUFFIXES[exponent + 1]
end

-- "1234567" -> "1,234,567". For places where exactness matters (sale receipts).
function Format.comma(value: number): string
	local sign = if value < 0 then "-" else ""
	local digits = tostring(math.floor(math.abs(value)))

	local out = digits
	local count: number
	repeat
		out, count = string.gsub(out, "^(%d+)(%d%d%d)", "%1,%2")
	until count == 0

	return sign .. out
end

-- "3h 24m" / "24m 05s" / "45s". Used by the offline-earnings popup.
function Format.duration(seconds: number): string
	seconds = math.max(0, math.floor(seconds))

	local hours = math.floor(seconds / 3600)
	local minutes = math.floor((seconds % 3600) / 60)
	local secs = seconds % 60

	if hours > 0 then
		return string.format("%dh %02dm", hours, minutes)
	elseif minutes > 0 then
		return string.format("%dm %02ds", minutes, secs)
	end
	return string.format("%ds", secs)
end

-- 0.734 -> "73%". Completion meters, not currency.
function Format.percent(fraction: number, decimals: number?): string
	local places = decimals or 0
	return string.format("%." .. places .. "f%%", fraction * 100)
end

-- "$1.25K/s" for income readouts.
function Format.rate(perSecond: number): string
	return "$" .. Format.abbreviate(perSecond) .. "/s"
end

-- Depth readout for the HUD. Always positive, always studs.
function Format.depth(studs: number): string
	return Format.comma(math.max(0, math.floor(studs))) .. " studs"
end

return table.freeze(Format)
