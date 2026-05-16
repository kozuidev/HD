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
local ShatterPacket = RemotesFolder:WaitForChild("ShatterPacket") -- remote used when shattering an item that is dropped or thrown, sent to server for replication.

local ItemsFolder = workspace.Items

-- ════════════════════════════════════════════════════════════════════════════════
-- Item Configuration
-- ════════════════════════════════════════════════════════════════════════════════

local RawItemInfo = require(ModulesFolder.Items) -- raw item information containing the config for each item.

local DefaultItemConfig = {
	Responsiveness = 25,
	OrientationResponsiveness = 10,
	Rotatable = true,
	SpeedMX = 40,
}

local ItemInfo = setmetatable({}, {
	__index = function(_, itemName)
		-- Getting the raw item information.
		local raw = RawItemInfo[itemName]
		if raw then
			-- Wrap the existing config so missing fields inside it also fall back.
			return setmetatable(raw, { __index = DefaultItemConfig })
		end
		-- Item has no entry at all, return the full defaults table.
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

-- Gets the walking direction in camera space
local function getWalkDirectionCameraSpace(): Vector3
	local walkDir = Vector3.new()

    -- Accumulate directional input from active keybinds
	for _, keyBind in pairs(walkKeyBinds) do
		if UserInputService:IsKeyDown(keyBind.Key) then
			walkDir += Vector3.FromNormalId(keyBind.Direction)
		end
	end

	-- Normalize the direction to stop faster diagonal movement
	if walkDir.Magnitude > 0 then
		walkDir = walkDir.Unit
	end

	return walkDir
end

-- Converts camera space walk direction into world space and strips the vertical component so the character stays grounded.
local function getWalkDirectionWorldSpace(): Vector3
	-- Convert relative walk input into world space
	local walkDir = Camera.CFrame:VectorToWorldSpace(getWalkDirectionCameraSpace())
	walkDir *= Vector3.new(1, 0, 1)

	-- Normalizing the direction
	if walkDir.Magnitude > 0 then
		walkDir = walkDir.Unit
	end

	return walkDir
end

-- Called every frame inside RenderStepped, for smooth deceleration and acceleration.
local function updateMovement(dt: number)
	local humanoid = Character:FindFirstChild("Humanoid")
	if not humanoid then return end

	-- Getting the walk direction in world space
	targetMoveVelocity = getWalkDirectionWorldSpace()

	-- Lerping moveVelocity toward targetMoveVelocity to make it smooth
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

	-- Adding or subtracting the hold distance based on the scroll wheel input. (1 is up, -1 is down)
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
    -- Creating an invisible part to act as a constraint target.
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
	targetRotation = DraggedItem and DraggedItem.CFrame or CFrame.new()

	-- Disable the mouse icon to prevent it from obstructing the view.
	UserInputService.MouseIconEnabled = false

	-- Disable AlignOrientation while rotating so it doesn't fight the manual CFrame.
	if DraggedItem then
		local ao = DraggedItem:FindFirstChildOfClass("AlignOrientation")
		if ao then ao.Enabled = false end
	end

	-- Play the visual effects for rotation.
	highlightRotateTween:Play()
	GrabBeam.Color = ColorSequence.new(Color3.fromRGB(104, 3, 255))

	-- Disable the holding state indicators during rotation.
	for _, child in holdingAttributeContainer:GetChildren() do
		child.Enabled = false
	end

	-- Adjust volume of the rotation sound effect while also adjusting the holding sound effect..
	TweenService:Create(script.RotatingSFX, TweenInfo.new(0.1), { Volume = 0.5 }):Play()
	TweenService:Create(script.HoldingSFX,  TweenInfo.new(0.1), { Volume = 0   }):Play()
end

local function endRotation()
	isRotating = false
	UserInputService.MouseDeltaSensitivity = 1
	UserInputService.MouseIconEnabled = true

	-- Re-enable AlignOrientation now that manual rotation is done
	if DraggedItem then
		local ao = DraggedItem:FindFirstChildOfClass("AlignOrientation")
		if ao then ao.Enabled = true end
	end

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

-- End rotation mode when RMB is let go
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

    -- Load handling config
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
        -- Sets the beam to the position attachment of the item
		GrabBeam.Attachment1 = posAttachment
		holdingAttributeContainer.Parent = item
		DraggedItem = item

        -- Sets the align position attachment to either the leg attachment or the camera attachment depending on if the item is a cart or not
		alignPos.Attachment1 = isCart and LegAttachment or CameraAttachment
		alignPos.Enabled = true

        -- Sets the align orientation attachment to the camera attachment
		alignOrient.Attachment1 = CameraAttachment

		-- If orientation responsiveness is greater than 0, enable the align orientation
		if orientResponsive > 0 then
			alignOrient.Enabled = true
		end

        -- Makes the highlight indicator appear on the item
		HighlightIndicator.Parent = item
		HighlightIndicator.Enabled = true
		highlightDefaultTween:Play()

        -- Tweens the volume of the holding sound effect
		TweenService:Create(script.HoldingSFX, TweenInfo.new(1), { Volume = 0.5 }):Play()
	end

	-- Release callback
	local function onDragEnd()
        -- Ends the rotation mode
		endRotation()

        -- Resets the beam
		GrabBeam.Attachment1 = nil
        -- Moves the attribute container to the holding attribute container
		holdingAttributeContainer.Parent = script.Holding
        -- Sets the dragged item to nil
		DraggedItem = nil

        -- Sets the align position attachment to nil and disables it
		alignPos.Attachment1 = nil
		alignPos.Enabled = false

        -- Sets the align orientation attachment to nil and disables it
		alignOrient.Attachment1 = nil
		alignOrient.Enabled = false

        -- Nils the stored rotation and frozen orientation
		storedRotation = nil
		frozenOrientation = nil

        -- Plays the unhover tween
		highlightUnhoverTween:Play()
        -- Tweens the volume of the holding sound effect
		TweenService:Create(script.HoldingSFX, TweenInfo.new(1), { Volume = 0 }):Play()
	end

	dragDetector.DragStart:Connect(onDragStart)
	dragDetector.DragEnd:Connect(onDragEnd)

	-- Green outline while the cursor is over a grabbable item
	dragDetector.MouseHoverEnter:Connect(function()
		highlightHoverTween:Play()

        -- Makes the highlight indicator appear on the item
		HighlightIndicator.Parent = item
	end)

    -- Calls the unhover tween when the mouse leaves the item
	dragDetector.MouseHoverLeave:Connect(function()
		highlightUnhoverTween:Play()
	end)

	-- Per item frame update stored as a closure, called from the main render loop
	local function perItemUpdate()
		local distFromCam = (item.Position - Camera.CFrame.Position).Magnitude

		-- Release if the item is too far from the camera
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
    -- Clones the break particle part and sets its position
	local particle = breakTemplate:Clone()
	particle.Position = position
	particle.Parent = workspace

    -- Finds the particle emitter and emits if found
	local emitter = particle:FindFirstChildWhichIsA("ParticleEmitter")
	if emitter then
		emitter:Emit(emitter:GetAttribute("BurstCount") or 15)
	end

	-- cleanup after 3 seconds, aka destroy the particle part.
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

-- Setup reusable raycast params
local shatterRayParams = RaycastParams.new()
shatterRayParams.FilterType = Enum.RaycastFilterType.Exclude

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

	-- Rotation mode handling

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

        -- Reach of the raycast
		local castReach = item.Size.Magnitude + 1
        
        shatterRayParams.FilterDescendantsInstances = {Character, item}

        -- Cast forward to predict impacts
        local raycastResult = workspace:Raycast(item.Position, velocity.Unit * castReach, shatterRayParams)

		if raycastResult then
			local maxSpeed = ItemInfo[item.Name].SpeedMX
            
			if speed > maxSpeed then
				ShatterPacket:FireServer(raycastResult.Position, item)
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
