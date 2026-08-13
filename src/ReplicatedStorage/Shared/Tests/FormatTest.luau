--!strict
--[[
	FormatTest
	Abbreviation, comma grouping, durations, and percentages.

	The abbreviation cases matter more than they look: the doc specifies the
	exact shapes 1.25K / 3.4M / 12.1B, which pins down three-significant-digit
	rounding *and* trailing-zero trimming. Getting one without the other passes
	casual inspection and fails these.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Format = require(ReplicatedStorage.Shared.Modules.Format)

return function(t)
	-- ---------- the doc's stated shapes ----------
	t.equal(Format.abbreviate(1250), "1.25K", "1250 -> 1.25K")
	t.equal(Format.abbreviate(3400000), "3.4M", "3.4e6 -> 3.4M")
	t.equal(Format.abbreviate(12100000000), "12.1B", "1.21e10 -> 12.1B")

	-- ---------- boundaries ----------
	t.equal(Format.abbreviate(0), "0", "zero")
	t.equal(Format.abbreviate(1), "1", "one")
	t.equal(Format.abbreviate(999), "999", "just under a thousand stays plain")
	t.equal(Format.abbreviate(1000), "1K", "exactly a thousand")
	t.equal(Format.abbreviate(999999), "1M", "999999 rounds up a suffix rather than showing 1000K")
	t.equal(Format.abbreviate(1000000), "1M", "exactly a million")

	-- ---------- significant digits ----------
	t.equal(Format.abbreviate(1234), "1.23K", "two decimals below ten")
	t.equal(Format.abbreviate(12345), "12.3K", "one decimal from ten")
	t.equal(Format.abbreviate(123456), "123K", "no decimals from a hundred")

	-- ---------- trailing zeros ----------
	t.equal(Format.abbreviate(2000), "2K", "a whole value drops its decimals")
	t.equal(Format.abbreviate(2500), "2.5K", "one significant decimal is kept")
	t.equal(Format.abbreviate(2050), "2.05K", "an internal zero is not trimmed")

	-- ---------- negatives ----------
	t.equal(Format.abbreviate(-4500), "-4.5K", "negatives keep their sign")
	t.equal(Format.abbreviate(-999), "-999", "small negatives stay plain")

	-- ---------- degenerate input ----------
	t.equal(Format.abbreviate(0 / 0), "0", "NaN does not produce nan text")
	t.ok(Format.abbreviate(math.huge):find("\u{221E}") ~= nil, "infinity renders as a symbol")

	-- ---------- comma ----------
	t.equal(Format.comma(1234567), "1,234,567", "comma grouping")
	t.equal(Format.comma(100), "100", "no comma below a thousand")
	t.equal(Format.comma(1000), "1,000", "comma at exactly a thousand")
	t.equal(Format.comma(-1234567), "-1,234,567", "negative comma grouping")

	-- ---------- duration ----------
	t.equal(Format.duration(45), "45s", "seconds only")
	t.equal(Format.duration(65), "1m 05s", "minutes pad their seconds")
	t.equal(Format.duration(12240), "3h 24m", "hours pad their minutes")
	t.equal(Format.duration(0), "0s", "zero duration")
	t.equal(Format.duration(-10), "0s", "negative duration clamps to zero")

	-- ---------- percent ----------
	t.equal(Format.percent(0.734), "73%", "percent rounds to whole by default")
	t.equal(Format.percent(0.5, 1), "50.0%", "percent honours decimal places")
	t.equal(Format.percent(1), "100%", "full percent")

	-- ---------- composites ----------
	t.equal(Format.rate(1250), "$1.25K/s", "rate wraps abbreviate")
	t.ok(Format.depth(1234):find("1,234") ~= nil, "depth uses comma grouping")
	t.equal(Format.depth(-5), "0 studs", "negative depth clamps")
end
