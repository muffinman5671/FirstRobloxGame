--!strict
--[[
	SwingAnimator
	The pickaxe swing, posed procedurally on the character's own joints.

	Why joints rather than only Tool.Grip: a Grip tween pivots the pickaxe
	inside a frozen hand, which reads as a lever on a hinge rather than a person
	hitting a rock. The weight of a swing lives in the shoulder and the waist.
	So this drives Motor6D.Transform down the right arm -- and the waist on R15
	-- and leaves Grip for the wrist, which is the small, *lagging* part.

	No Animation assets. DESIGN.md §2 forbids asset IDs we cannot verify, and a
	procedural pose needs no upload; it also lets one swing stretch to fit
	whatever cooldown the equipped pickaxe happens to have.

	Transform, not C0: C0 is the rig's rest offset and the Animator never
	touches it, so writing C0 would fight every other animation the character is
	playing. Transform is the per-frame pose slot. We multiply into whatever the
	Animator wrote this frame, which is why the bind sits one step *after*
	Enum.RenderPriority.Character -- ahead of it the Animator overwrites us and
	the arm never moves.

	Local only. Other players still see a still pickaxe; replicating the pose
	needs a remote and belongs with the rest of the effects work.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local SwingAnimator = {}

local BIND_NAME = "PickaxeSwing"

-- ==========================================================================
-- The swing curve
-- ==========================================================================
--[[
	One scalar drives the whole pose: -1 is fully wound up, +1 is fully struck
	through, 0 is rest. Every joint is a lerp between rest and one of two
	extremes, so the limbs cannot drift out of sync with each other.

	    t      0 ------- windup ------- strike --------------- 1
	    s(t)   0 \___ -1 /                +1 \  ~~~~~~~~ 0
	             ease out  accelerate          damped rebound

	The old version was three segments that met at matching *angles* but not
	matching *speeds*: the wind up decelerated to a stop, the strike then began
	at full speed (a twitch), and the strike ended by braking to a dead stop at
	the block (no impact at all). Both boundaries are fixed here.

	  - wind up: ease-out cubic, so it arrives at the loaded pose slowing down
	    and hangs there for a beat.
	  - strike: ease-in quadratic. Its speed at the start is zero, which is
	    where the wind up left off, so the two join smoothly -- and it is still
	    accelerating when it reaches the block, which is where the speed should
	    peak.
	  - rebound: a damped cosine starting at +1. The reversal at contact is a
	    real velocity discontinuity, and that is the point: an impact *is* one.
	    It overshoots about a tenth of the way back past rest, then settles.
]]
local function swingCurve(t: number): number
	if t <= 0 or t >= 1 then
		return 0
	end

	local windup = GameConfig.SwingAnimWindupEnd
	local strike = GameConfig.SwingAnimStrikeEnd

	if t < windup then
		local k = 1 - t / windup
		return -(1 - k * k * k)
	elseif t < strike then
		local k = (t - windup) / (strike - windup)
		return -1 + 2 * k * k
	end

	local k = (t - strike) / (1 - strike)
	return math.exp(-GameConfig.SwingAnimReboundDecay * k)
		* math.cos(math.pi * GameConfig.SwingAnimReboundCycles * k)
end

-- ==========================================================================
-- Rig
-- ==========================================================================
--[[
	Joint angles live here rather than in GameConfig: they are facts about the
	rig, not numbers anyone would tune for balance. What GameConfig owns is the
	*feel* -- timing, rebound, wrist lag, idle sway.

	Axis derivation, because the two rigs do not agree and guessing costs a
	rebuild. A Motor6D poses Part1 as `Part0 * C0 * Transform * C1:Inverse()`,
	so Transform acts in the frame C0 leaves behind.

	R15's arm attachments carry no rotation, so that frame is the character's
	own: +X right, +Y up, -Z forward. The arm hangs along -Y, and rotating about
	+X sweeps -Y toward -Z, i.e. the arm raises *forward*. So X is the swing
	axis, and Z -- which sweeps the arm out to the right -- is the flare.

	R6's shoulder C0 is yawed 90 degrees about Y, which maps its local +X onto
	world -Z and its local +Z onto world +X. The raise therefore happens about
	Z, and the flare about X, with the flare sign inverted since that local X
	now points forward rather than right. Same angles, relabelled axes.
]]
type Pose = { swing: number, flare: number }

type Rig = {
	shoulder: Motor6D,
	elbow: Motor6D?,
	waist: Motor6D?,
	swingAxis: Vector3,
	flareAxis: Vector3,
	shoulderWindup: Pose,
	shoulderStrike: Pose,
}

local X_AXIS = Vector3.xAxis
local Y_AXIS = Vector3.yAxis
local Z_AXIS = Vector3.zAxis

-- R15 spreads the swing over three joints, so the shoulder does not have to
-- cover the whole arc on its own.
local R15_SHOULDER_WINDUP: Pose = { swing = 78, flare = 20 }
local R15_SHOULDER_STRIKE: Pose = { swing = -62, flare = -10 }

-- R6 has one joint in the entire arm. It gets the elbow's share added on, or
-- the swing barely travels.
local R6_SHOULDER_WINDUP: Pose = { swing = 96, flare = 22 }
local R6_SHOULDER_STRIKE: Pose = { swing = -72, flare = -10 }

-- Cock the forearm back on the wind up, then drive it straight through the
-- block. Positive is flexion, by the same -Y-toward-forward reasoning above.
local ELBOW_WINDUP = 52
local ELBOW_STRIKE = -14

-- The waist is what sells the weight, and also what looks drunk when overdone
-- -- it carries the head and the far arm with it. Deliberately small.
local WAIST_WINDUP_LEAN, WAIST_WINDUP_TWIST = -7, -10
local WAIST_STRIKE_LEAN, WAIST_STRIKE_TWIST = 12, 7

local function findMotor(parent: Instance?, name: string): Motor6D?
	if not parent then
		return nil
	end
	local found = parent:FindFirstChild(name)
	return if found and found:IsA("Motor6D") then found else nil
end

local function buildRig(character: Model): Rig?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local r15 = humanoid == nil or humanoid.RigType == Enum.HumanoidRigType.R15

	if r15 then
		local shoulder = findMotor(character:FindFirstChild("RightUpperArm"), "RightShoulder")
		if not shoulder then
			return nil
		end
		return {
			shoulder = shoulder,
			elbow = findMotor(character:FindFirstChild("RightLowerArm"), "RightElbow"),
			waist = findMotor(character:FindFirstChild("UpperTorso"), "Waist"),
			swingAxis = X_AXIS,
			flareAxis = Z_AXIS,
			shoulderWindup = R15_SHOULDER_WINDUP,
			shoulderStrike = R15_SHOULDER_STRIKE,
		}
	end

	local shoulder = findMotor(character:FindFirstChild("Torso"), "Right Shoulder")
	if not shoulder then
		return nil
	end
	return {
		shoulder = shoulder,
		elbow = nil,
		waist = nil,
		swingAxis = Z_AXIS,
		flareAxis = -X_AXIS,
		shoulderWindup = R6_SHOULDER_WINDUP,
		shoulderStrike = R6_SHOULDER_STRIKE,
	}
end

-- ==========================================================================
-- State
-- ==========================================================================

local rig: Rig? = nil
local character: Model? = nil
local tool: Tool? = nil

-- R15 limbs stream in after CharacterAdded fires, so the arm motors are often
-- missing on the frame we first look. Retried on a slow timer rather than every
-- frame, and abandoned entirely the moment the rig resolves.
local RIG_RETRY_SECONDS = 0.5
local nextRigRetry = 0

local swingStart = -math.huge
local swingLength = GameConfig.SwingAnimSeconds
local impactFired = true
local impactCallbacks: { () -> () } = {}

-- Blend weight, so an unequip mid-swing fades the pose out instead of dropping
-- the arm in one frame. The curve already starts and ends at rest, so this only
-- ever matters for an interruption.
local weight = 0
local bound = false

local function poseFor(target: Pose, amount: number, current: Rig): CFrame
	return CFrame.fromAxisAngle(current.swingAxis, math.rad(target.swing * amount))
		* CFrame.fromAxisAngle(current.flareAxis, math.rad(target.flare * amount))
end

-- ==========================================================================
-- Per-frame pose
-- ==========================================================================

local function applyJoints(s: number, current: Rig)
	--[[
		Each joint is rest lerped toward whichever extreme the sign of s points
		at, so one number keeps shoulder, elbow and waist in phase.

		The rebound drives s slightly negative, which eases the limbs a little
		way back toward the wind up pose -- exactly the recoil we want, free.
	]]
	local back = math.max(-s, 0) * weight
	local through = math.max(s, 0) * weight

	local shoulder = if s < 0
		then poseFor(current.shoulderWindup, back, current)
		else poseFor(current.shoulderStrike, through, current)
	current.shoulder.Transform *= shoulder

	local elbow = current.elbow
	if elbow then
		local angle = if s < 0 then ELBOW_WINDUP * back else ELBOW_STRIKE * through
		elbow.Transform *= CFrame.fromAxisAngle(X_AXIS, math.rad(angle))
	end

	local waist = current.waist
	if waist then
		local lean = if s < 0 then WAIST_WINDUP_LEAN * back else WAIST_STRIKE_LEAN * through
		local twist = if s < 0 then WAIST_WINDUP_TWIST * back else WAIST_STRIKE_TWIST * through
		waist.Transform *= CFrame.fromAxisAngle(X_AXIS, math.rad(lean))
			* CFrame.fromAxisAngle(Y_AXIS, math.rad(twist))
	end
end

--[[
	Wrist.

	The Grip follows the same curve sampled a few hundredths of a second
	*behind* the arm, so the pickaxe head trails the hand and whips through at
	the end. Overlapping action: it is the cheapest thing on this list and it is
	most of what makes a swing read as heavy rather than as a rotating prop.

	Between swings the same Grip carries a slow sway on two incommensurate
	periods, so an equipped pickaxe breathes instead of hanging like scenery.
]]
local function applyGrip(t: number, held: Tool)
	local base = GameConfig.SwingAnimBaseGrip

	if weight <= 0.001 then
		local clock = os.clock()
		local sway = GameConfig.SwingAnimIdleSway
		local rate = GameConfig.SwingAnimIdleRate
		held.Grip = base
			* CFrame.Angles(
				math.rad(math.sin(clock * rate) * sway),
				0,
				math.rad(math.cos(clock * rate * 0.61) * sway * 0.5)
			)
		return
	end

	local lagged = swingCurve(t - GameConfig.SwingAnimWristLag) * weight
	held.Grip = base
		* CFrame.Angles(
			math.rad(-lagged * GameConfig.SwingAnimGripPitch),
			0,
			math.rad(lagged * GameConfig.SwingAnimGripRoll)
		)
end

local function step(dt: number)
	local held = tool
	if not held or not held.Parent then
		return
	end

	local now = os.clock()
	local waiting = character
	if not rig and waiting and waiting.Parent and now >= nextRigRetry then
		nextRigRetry = now + RIG_RETRY_SECONDS
		rig = buildRig(waiting)
	end
	local current = rig

	local elapsed = os.clock() - swingStart
	local swinging = elapsed >= 0 and elapsed < swingLength
	local t = if swinging then elapsed / swingLength else 0

	-- Fast, but not instant: a hard cut to 0 on the frame a swing ends would
	-- pop if the curve were ever interrupted away from rest.
	local target = if swinging then 1 else 0
	weight += (target - weight) * math.min(1, dt * 18)

	if swinging and not impactFired and t >= GameConfig.SwingAnimStrikeEnd then
		impactFired = true
		for _, callback in impactCallbacks do
			callback()
		end
	end

	applyGrip(t, held)

	--[[
		Below the threshold we stop writing joints entirely and let the Animator
		own the arm again. That is also the safety net for the one way this
		technique can misbehave: we multiply into Transform assuming the
		Animator rewrote it this frame, so on a character with no tracks playing
		at all the offsets would compound. Dropping out at rest bounds that to a
		single swing rather than letting it spiral.
	]]
	if current and weight > 0.001 then
		applyJoints(swingCurve(t), current)
	end
end

-- ==========================================================================
-- API
-- ==========================================================================

function SwingAnimator.attach(model: Model)
	character = model
	rig = buildRig(model)
	nextRigRetry = 0
	weight = 0
	swingStart = -math.huge
	impactFired = true

	if not bound then
		RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Character.Value + 1, step)
		bound = true
	end
end

function SwingAnimator.detach()
	rig = nil
	character = nil
	tool = nil
	weight = 0
	if bound then
		RunService:UnbindFromRenderStep(BIND_NAME)
		bound = false
	end
end

-- nil parks the animator: the Grip stops being written, and the joints are
-- already back with the Animator because no swing is in flight.
function SwingAnimator.setTool(held: Tool?)
	tool = held
	if not held then
		weight = 0
		swingStart = -math.huge
	end
end

--[[
	Starts a swing sized to fit `cooldown`, and returns how long until the head
	lands -- so the caller can line its hit feedback up with the animation
	rather than with a server round trip.
]]
function SwingAnimator.swing(cooldown: number): number
	-- Never let a swing outlast the cooldown, or two would overlap and the
	-- pickaxe would stutter at high swing speeds.
	swingLength = math.min(GameConfig.SwingAnimSeconds, cooldown * 0.9)
	swingStart = os.clock()
	impactFired = false
	return swingLength * GameConfig.SwingAnimStrikeEnd
end

function SwingAnimator.onImpact(callback: () -> ())
	table.insert(impactCallbacks, callback)
end

return SwingAnimator
