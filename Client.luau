-- Connected Discord-GitHub

-- ════════════════════════════════════════════════════════════════════════════════
-- Services
-- ════════════════════════════════════════════════════════════════════════════════

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

-- ════════════════════════════════════════════════════════════════════════════════
-- Player & Camera references
-- ════════════════════════════════════════════════════════════════════════════════

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

-- Character reference that updates on respawn so movement never breaks
local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()

LocalPlayer.CharacterAdded:Connect(function(newCharacter)
	Character = newCharacter
end)

-- ════════════════════════════════════════════════════════════════════════════════
-- Remote & Module references
-- ════════════════════════════════════════════════════════════════════════════════

local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local ModulesFolder = ReplicatedStorage:WaitForChild("Modules")
local ShatterPacket = RemotesFolder:WaitForChild("ShatterPacket")

local ItemsFolder = workspace.Items

-- ════════════════════════════════════════════════════════════════════════════════
-- Item Configuration
-- ════════════════════════════════════════════════════════════════════════════════

local RawItemInfo = require(ModulesFolder.Items)

local DefaultItemConfig = {
	Responsiveness = 25,
	OrientationResponsiveness = 10,
	Rotatable = true,
	SpeedMX = 40,
}

local ItemInfo = setmetatable({}, {
	__index = function(_, itemName)
		local raw = RawItemInfo[itemName]
		if raw then
			-- Wrap the existing config so missing fields inside it also fall back
			return setmetatable(raw, { __index = DefaultItemConfig })
		end
		-- Item has no entry at all — return the full defaults table
		return DefaultItemConfig
	end,
})

-- ════════════════════════════════════════════════════════════════════════════════
-- Camera-Relative Movement System
-- ════════════════════════════════════════════════════════════════════════════════

local targetMoveVelocity = Vector3.new()
local moveVelocity = Vector3.new()
local moveAcceleration = 8

-- Each entry pairs a KeyCode with a NormalId that represents a unit axis
local walkKeyBinds = {
	Forward = {Key = Enum.KeyCode.W, Direction = Enum.NormalId.Front},
	Backward = {Key = Enum.KeyCode.S, Direction = Enum.NormalId.Back},
	Left = {Key = Enum.KeyCode.A, Direction = Enum.NormalId.Left},
	Right = {Key = Enum.KeyCode.D, Direction = Enum.NormalId.Right}
}

local function getWalkDirectionCameraSpace(): Vector3
	local walkDir = Vector3.new()

	for _, keyBind in pairs(walkKeyBinds) do
		if UserInputService:IsKeyDown(keyBind.Key) then
			walkDir += Vector3.FromNormalId(keyBind.Direction)
		end
	end

	if walkDir.Magnitude > 0 then
		walkDir = walkDir.Unit
	end

	return walkDir
end

-- Converts camera space walk direction into world space and strips the vertical component so the character stays grounded.
local function getWalkDirectionWorldSpace(): Vector3
	local walkDir = Camera.CFrame:VectorToWorldSpace(getWalkDirectionCameraSpace())
	walkDir *= Vector3.new(1, 0, 1)

	if walkDir.Magnitude > 0 then
		walkDir = walkDir.Unit
	end

	return walkDir
end

-- Called every frame inside RenderStepped, for smooth deceleration and acceleration.
local function updateMovement(dt: number)
	local humanoid = Character:FindFirstChild("Humanoid")
	if not humanoid then return end

	targetMoveVelocity = getWalkDirectionWorldSpace()

	moveVelocity = moveVelocity:Lerp(targetMoveVelocity, math.clamp(dt * moveAcceleration, 0, 1))
	humanoid:Move(moveVelocity)
end

-- ════════════════════════════════════════════════════════════════════════════════
-- Physics Drag System
-- ════════════════════════════════════════════════════════════════════════════════

local DraggedItem: BasePart? = nil -- the part currently being dragged

-- Scroll wheel controls how far from the Camera the held item floats
local holdDistance = 2

UserInputService.PointerAction:Connect(function(wheel, _pan, _pinch, gameProcessed)
	if gameProcessed then return end

	if wheel >= 0 then
		holdDistance = math.clamp(holdDistance + 1, 2, 10)
	else
		holdDistance = math.clamp(holdDistance - 1, 2, 10)
	end
end)

-- Visual indicator

local HighlightIndicator = Instance.new("Highlight")
HighlightIndicator.FillColor = Color3.fromRGB(151, 5, 255)
HighlightIndicator.FillTransparency = 1
HighlightIndicator.OutlineColor = Color3.fromRGB(255, 255, 255)

-- Tweens for each highlight state

local highlightTweenInfo = TweenInfo.new(0.25)

local highlightRotateTween = TweenService:Create(HighlightIndicator, highlightTweenInfo, {
	FillTransparency = 0.75,
	OutlineTransparency = 0,
	OutlineColor = Color3.fromRGB(151, 5, 255),
})

local highlightDefaultTween = TweenService:Create(HighlightIndicator, highlightTweenInfo, {
	FillTransparency = 1,
	OutlineTransparency = 0,
	OutlineColor = Color3.fromRGB(255, 255, 255),
})

local highlightHoverTween = TweenService:Create(HighlightIndicator, highlightTweenInfo, {
	FillTransparency = 1,
	OutlineTransparency = 0,
	OutlineColor = Color3.fromRGB(147, 255, 192),
})

local highlightUnhoverTween = TweenService:Create(HighlightIndicator, highlightTweenInfo, {
	FillTransparency = 1,
	OutlineTransparency = 1,
	OutlineColor = Color3.fromRGB(255, 255, 255),
})

local rotatingAttributeContainer = script.Rotating.at
local holdingAttributeContainer  = script.Holding.at

-- Invisible parts used as constraint targets

local function makeAnchorPart(name: string): (Part, Attachment)
	local part = Instance.new("Part")
	part.Anchored = true
	part.Size = Vector3.one
	part.Transparency = 1
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Name = name
	part.Parent = workspace

	local attachment = Instance.new("Attachment")
	attachment.Parent = part

	return part, attachment
end

local LookAtPart, CameraAttachment = makeAnchorPart("LookAtPart")
local CameraPart, MainCamAttachment = makeAnchorPart("CameraPart")
local LegPart, LegAttachment = makeAnchorPart("LegPart")

-- Visual line from camera to held item

local GrabBeam = script.GrabBeam
GrabBeam.Parent = CameraPart
GrabBeam.Attachment0 = MainCamAttachment

-- ════════════════════════════════════════════════════════════════════════════════
-- Rotation System
-- ════════════════════════════════════════════════════════════════════════════════

local isRotating = false
local rotationSpeed = 0.005
local lastMousePos: Vector2? = nil
local storedRotation: CFrame? = nil
local frozenOrientation: Vector3? = nil

local function beginRotation()
	isRotating = true

	-- Freeze the mouse sensitivity so camera doesn't move while we focus on rotating the object via mouse movements.

	UserInputService.MouseDeltaSensitivity = 0
	lastMousePos   = UserInputService:GetMouseLocation()
	storedRotation = DraggedItem and DraggedItem.CFrame or CFrame.new()

	UserInputService.MouseIconEnabled = false

	highlightRotateTween:Play()
	GrabBeam.Color = ColorSequence.new(Color3.fromRGB(104, 3, 255))

	-- Disable the holding state indicators during rotation.
	for _, child in holdingAttributeContainer:GetChildren() do
		child.Enabled = false
	end

	TweenService:Create(script.RotatingSFX, TweenInfo.new(0.1), { Volume = 0.5 }):Play()
	TweenService:Create(script.HoldingSFX,  TweenInfo.new(0.1), { Volume = 0   }):Play()
end

local function endRotation()
	isRotating = false
	UserInputService.MouseDeltaSensitivity = 1
	UserInputService.MouseIconEnabled = true

	highlightDefaultTween:Play()
	GrabBeam.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))

	for _, child in holdingAttributeContainer:GetChildren() do
		child.Enabled = true
	end

	TweenService:Create(script.RotatingSFX, TweenInfo.new(0.1), { Volume = 0 }):Play()
	TweenService:Create(script.HoldingSFX,  TweenInfo.new(0.1), { Volume = 0.5 }):Play()
end

-- Right mouse button toggles rotation mode
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if input.UserInputType ~= Enum.UserInputType.MouseButton2 then return end
	if not DraggedItem then return end
	if not ItemInfo[DraggedItem.Name].Rotatable then return end
	beginRotation()
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseButton2 then return end
	if not DraggedItem then return end
	if not ItemInfo[DraggedItem.Name].Rotatable then return end
	endRotation()
end)

-- ════════════════════════════════════════════════════════════════════════════════
-- Per Item Setup (DragDetector wiring)
-- ════════════════════════════════════════════════════════════════════════════════

-- Table of per item update closures, populated in setupItem()
local itemUpdateCallbacks: { () -> () } = {}

local function setupItem(item: BasePart)
	local dragDetector: DragDetector = item:WaitForChild("DragDetector")

	local posAttachment = Instance.new("Attachment")
	posAttachment.Parent = item

	local config = ItemInfo[item.Name]
	local responsiveness = config.Responsiveness
	local orientResponsive = config.OrientationResponsiveness

	-- Pulls the item toward the camera lookat anchor part
	local alignPos = Instance.new("AlignPosition")
	alignPos.Attachment0 = posAttachment
	alignPos.Responsiveness = responsiveness
	alignPos.Enabled = false
	alignPos.Parent = item

	-- Keeps the item oriented relative to the camera
	local alignOrient = Instance.new("AlignOrientation")
	alignOrient.Attachment0 = posAttachment
	alignOrient.Responsiveness = orientResponsive
	alignOrient.Enabled = false
	alignOrient.Parent = item

	-- Record the item's spawn height for MaxVelocity dampening calculations later on
	local originY = item.Position.Y
	local isCart = (item.Name == "Cart")

	-- Grab callback

	local function onDragStart()
		GrabBeam.Attachment1 = posAttachment
		holdingAttributeContainer.Parent = item
		DraggedItem = item

		alignPos.Attachment1 = isCart and LegAttachment or CameraAttachment
		alignPos.Enabled = true

		alignOrient.Attachment1 = CameraAttachment
		if orientResponsive > 0 then
			alignOrient.Enabled = true
		end

		HighlightIndicator.Parent = item
		HighlightIndicator.Enabled = true
		highlightDefaultTween:Play()

		TweenService:Create(script.HoldingSFX, TweenInfo.new(1), { Volume = 0.5 }):Play()
	end

	-- Release callback

	local function onDragEnd()
		endRotation()

		GrabBeam.Attachment1 = nil
		holdingAttributeContainer.Parent = script.Holding
		DraggedItem = nil

		alignPos.Attachment1 = nil
		alignPos.Enabled = false
		alignOrient.Attachment1 = nil
		alignOrient.Enabled = false

		storedRotation = nil
		frozenOrientation = nil

		highlightUnhoverTween:Play()
		TweenService:Create(script.HoldingSFX, TweenInfo.new(1), { Volume = 0 }):Play()
	end

	dragDetector.DragStart:Connect(onDragStart)
	dragDetector.DragEnd:Connect(onDragEnd)

	-- Green outline while the cursor is over a grabbable item
	dragDetector.MouseHoverEnter:Connect(function()
		highlightHoverTween:Play()
		HighlightIndicator.Parent = item
	end)

	dragDetector.MouseHoverLeave:Connect(function()
		highlightUnhoverTween:Play()
	end)

	-- Per item frame update stored as a closure, called from the main render loop
	local function perItemUpdate()
		local distFromCam = (item.Position - Camera.CFrame.Position).Magnitude

		-- release if the item is too far from the camera
		if distFromCam >= 35 then
			dragDetector.Enabled = false
			if DraggedItem == item then
				onDragEnd()
			end
		else
			dragDetector.Enabled = true
		end

		-- The higher above its origin, the slower it can be pushed. simulating weight.
		local liftDelta = item.Position.Y - originY
		alignPos.MaxVelocity = responsiveness - liftDelta
	end

	-- Store the per item updater and its cleanup in a table so the main loop can call it
	table.insert(itemUpdateCallbacks, perItemUpdate)
end

-- ════════════════════════════════════════════════════════════════════════════════
-- Shatter Particle Effect
-- ════════════════════════════════════════════════════════════════════════════════

local breakTemplate = ReplicatedStorage:WaitForChild("Break")

ShatterPacket.OnClientEvent:Connect(function(position: Vector3)
	local particle = breakTemplate:Clone()
	particle.Position = position
	particle.Parent = workspace

	local emitter = particle:FindFirstChildWhichIsA("ParticleEmitter")
	if emitter then
		emitter:Emit(emitter:GetAttribute("BurstCount") or 15)
	end

	-- cleanup
	task.delay(3, function()
		if particle and particle.Parent then
			particle:Destroy()
		end
	end)
end)

-- ════════════════════════════════════════════════════════════════════════════════
-- Unified RenderStepped Loop
-- ════════════════════════════════════════════════════════════════════════════════

local SHATTER_RENDER_DISTANCE = 30

RunService.RenderStepped:Connect(function(dt: number)

	-- Anchor part positioning

	local camCF = Camera.CFrame
	local lookVec = camCF.LookVector
	local camPos = camCF.Position

	LookAtPart.CFrame = camCF + (lookVec * holdDistance)
	CameraPart.CFrame = camCF

	-- LegPart sits at foot level, projected forward along the horizontal look direction, so that cart items are dragged along the ground rather than floating.

	local footY = camPos.Y - 2
	local flatLook = Vector3.new(lookVec.X, 0, lookVec.Z)
	LegPart.CFrame = CFrame.new(camPos.X, footY, camPos.Z) + (flatLook * (5 + holdDistance))

	-- Rotation mode handling

	if DraggedItem and isRotating then
		rotatingAttributeContainer.Parent = DraggedItem
	else
		rotatingAttributeContainer.Parent = script.Rotating
	end

	if DraggedItem then
		if isRotating and lastMousePos and storedRotation then
			local currentMousePos = UserInputService:GetMouseLocation()
			local mouseDelta = currentMousePos - lastMousePos

			-- Convert pixel delta to radians

			local yaw = -mouseDelta.X * rotationSpeed
			local pitch = -mouseDelta.Y * rotationSpeed

			-- Incremental rotation onto the stored cframe

			DraggedItem.CFrame = storedRotation * CFrame.Angles(pitch, yaw, 0)

			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			lastMousePos = UserInputService:GetMouseLocation()
			storedRotation  = DraggedItem.CFrame
			frozenOrientation = DraggedItem.Orientation
		elseif frozenOrientation then

			-- If not actively rotating, keep it locked.

			DraggedItem.Orientation = frozenOrientation
		end
	else
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	end

	-- Movement
	updateMovement(dt)

	-- Per item updates
	for _, updateFn in itemUpdateCallbacks do
		updateFn()
	end

	-- For each item that is close to the camera, we will cast a ray along it's velocity vector, and if the ray hits something and the item is moving faster than its configured maximum "safe speed", we fire the shatterpacket to the server.
	for _, item: BasePart in ipairs(ItemsFolder:GetChildren()) do
		local dist = (camPos - item.Position).Magnitude
		if dist >= SHATTER_RENDER_DISTANCE then continue end

		local velocity = item.AssemblyLinearVelocity or item.Velocity
		local speed = velocity.Magnitude
		if speed < 1 then continue end

		local castReach = item.Size.Magnitude + 1
		local ray = Ray.new(item.Position, velocity.Unit * castReach)

		local hit, hitPos = workspace:FindPartOnRayWithIgnoreList(ray, { Character, item })
		if hit then
			local maxSpeed = ItemInfo[item.Name].SpeedMX
			if speed > maxSpeed then
				ShatterPacket:FireServer(hitPos, item)
			end
		end
	end
end)
-- ════════════════════════════════════════════════════════════════════════════════
-- Item Initialisation
-- ════════════════════════════════════════════════════════════════════════════════

for _, item in ItemsFolder:GetChildren() do
	setupItem(item)
end

ItemsFolder.ChildAdded:Connect(setupItem)