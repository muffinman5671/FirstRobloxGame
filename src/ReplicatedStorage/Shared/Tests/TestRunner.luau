--!strict
--[[
	TestRunner
	A deliberately tiny assertion harness. No framework, no dependencies -- the
	doc asks for "plain-Luau assertion scripts", and a test suite that needs its
	own install step is a test suite nobody runs.

	Usage from the Studio command bar, or from a Script during a play test:

	    local Tests = require(game.ReplicatedStorage.Shared.Tests.TestRunner)
	    print(Tests.runAll())

	Each suite module returns a function taking a `t` handle and calling
	t.equal / t.ok / t.near / t.throws. A suite that errors is reported as a
	failure rather than taking the run down.
]]

local Tests = {}

export type Handle = {
	ok: (condition: any, label: string, detail: any?) -> (),
	equal: (actual: any, expected: any, label: string) -> (),
	near: (actual: number, expected: number, tolerance: number, label: string) -> (),
	throws: (fn: () -> (), label: string) -> (),
}

type Result = {
	suite: string,
	passed: number,
	failed: number,
	lines: { string },
}

local function newHandle(result: Result): Handle
	local function record(passed: boolean, label: string, detail: any?)
		if passed then
			result.passed += 1
			table.insert(result.lines, "  ok   " .. label)
		else
			result.failed += 1
			table.insert(result.lines, ("  FAIL %s%s"):format(label, if detail ~= nil then "  -> " .. tostring(detail) else ""))
		end
	end

	return {
		ok = function(condition, label, detail)
			record(condition and true or false, label, detail)
		end,

		equal = function(actual, expected, label)
			record(actual == expected, label, if actual == expected then nil else `got {tostring(actual)}, want {tostring(expected)}`)
		end,

		near = function(actual, expected, tolerance, label)
			local delta = math.abs(actual - expected)
			record(delta <= tolerance, label, if delta <= tolerance then nil else `got {actual}, want {expected} +/- {tolerance}`)
		end,

		throws = function(fn, label)
			local ok = pcall(fn)
			record(not ok, label, if not ok then nil else "did not throw")
		end,
	}
end

-- Suites are listed rather than discovered so the run order is stable and a
-- half-written module can't silently join the suite.
local SUITE_NAMES = { "RarityTest", "FormatTest", "EconomyTest", "ConversionTest", "SessionLockTest" }

function Tests.runAll(): string
	local out = {}
	local totalPassed, totalFailed = 0, 0

	for _, name in SUITE_NAMES do
		local module = script.Parent:FindFirstChild(name)
		if not module then
			totalFailed += 1
			table.insert(out, `{name}\n  FAIL suite module missing`)
		else
			local result: Result = { suite = name, passed = 0, failed = 0, lines = {} }
			local ok, err = pcall(function()
				require(module)(newHandle(result))
			end)

			if not ok then
				result.failed += 1
				table.insert(result.lines, `  FAIL suite errored -> {err}`)
			end

			totalPassed += result.passed
			totalFailed += result.failed
			table.insert(out, `{name}  ({result.passed} passed, {result.failed} failed)`)
			table.insert(out, table.concat(result.lines, "\n"))
		end
	end

	table.insert(out, ("\n%d passed, %d failed"):format(totalPassed, totalFailed))
	return table.concat(out, "\n")
end

return Tests
