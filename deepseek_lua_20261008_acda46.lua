-- ============================================================
-- FAST AUTO BUILD ENGINE
-- ============================================================
local pBuild = makePage("build")

local BUILD_CFG = {
	HeightOffset = 12,
	PlaceRetry = 0.005,      -- was 0.02/0.05
	PlaceRetryNC = 0.02,     -- was 0.06/0.2
	AfterPlace = 0,          -- no wait
	ResizeGap = 0.005,       -- was 0.02-0.08
	ResizeSide = 0.01,       -- was 0.03-0.1
	MaxAttempts = 20,        -- was 30-40
	Parallel = true,         -- fire build next block while painting current
}

local SYM = {
	["!"]=Enum.Material.SmoothPlastic, ["@"]=Enum.Material.Plastic, ["#"]=Enum.Material.CeramicTiles,
	["$"]=Enum.Material.Brick, ["%"]=Enum.Material.WoodPlanks, ["^"]=Enum.Material.Ice,
	["&"]=Enum.Material.Grass, ["*"]=Enum.Material.Sand, ["("]=Enum.Material.Snow,
	[")"]=Enum.Material.Glass, ["-"]=Enum.Material.Wood, ["_"]=Enum.Material.Slate,
	["="]=Enum.Material.Pebble, ["+"]=Enum.Material.Marble, ["["]=Enum.Material.Granite,
	["]"]=Enum.Material.DiamondPlate, ["{"]=Enum.Material.Metal, ["}"]=Enum.Material.Asphalt,
	["~"]=Enum.Material.Concrete, ["`"]=Enum.Material.Pavement, ["?"]=Enum.Material.Neon,
}

local MAT_PAINT = {
	[Enum.Material.SmoothPlastic]="smooth", [Enum.Material.Plastic]="plastic", [Enum.Material.CeramicTiles]="tiles",
	[Enum.Material.Brick]="bricks", [Enum.Material.WoodPlanks]="planks", [Enum.Material.Ice]="ice",
	[Enum.Material.Grass]="grass", [Enum.Material.Sand]="sand", [Enum.Material.Snow]="snow",
	[Enum.Material.Glass]="glass", [Enum.Material.Wood]="wood", [Enum.Material.Slate]="stone",
	[Enum.Material.Pebble]="pebble", [Enum.Material.Marble]="marble", [Enum.Material.Granite]="granite",
	[Enum.Material.DiamondPlate]="steel", [Enum.Material.Metal]="metal", [Enum.Material.Asphalt]="asphalt",
	[Enum.Material.Concrete]="concrete", [Enum.Material.Pavement]="pavement", [Enum.Material.Neon]="neon",
}

local function hexToCol(h)
	return Color3.new(tonumber(h:sub(1,2),16)/255, tonumber(h:sub(3,4),16)/255, tonumber(h:sub(5,6),16)/255)
end

local function colToHex(c)
	return string.format("%02X%02X%02X", math.floor(c.R*255+0.5), math.floor(c.G*255+0.5), math.floor(c.B*255+0.5))
end

local function matToSym(m)
	for k, v in pairs(SYM) do if v == m then return k end end
	return "@"
end

local function fastTool(name)
	if not char then return nil end
	local t = char:FindFirstChild(name)
	if t then return t end
	if not plr:FindFirstChild("Backpack") then return nil end
	local bp = plr.Backpack:FindFirstChild(name)
	if bp then bp.Parent = char return bp end
	return nil
end

local function fastRemote(name)
	local t = fastTool(name)
	if not t then return nil end
	local s = t:FindFirstChild("Script", true)
	if s then return s:FindFirstChild("Event") end
	return t:FindFirstChild("Event")
end

local function myBricks()
	local f = WS:FindFirstChild("Bricks")
	return f and f:FindFirstChild(plr.Name) or nil
end

local function brickCount()
	local f = myBricks()
	if not f then return 0 end
	local n = 0
	for _, b in ipairs(f:GetChildren()) do if b:IsA("BasePart") and b.Name == "Brick" then n = n + 1 end end
	return n
end

local function newestBrick()
	local f = myBricks()
	if not f then return nil end
	local bs = {}
	for _, b in ipairs(f:GetChildren()) do if b:IsA("BasePart") and b.Name == "Brick" then bs[#bs+1] = b end end
	return bs[#bs]
end

local function cornerPos(cp, size)
	local h = size / 2
	return Vector3.new(cp.X - h.X + 0.5, cp.Y - h.Y + 0.5, cp.Z - h.Z + 0.5)
end

local function parseBuild(str)
	local blocks = {}
	for bd in str:gmatch("|([^|]+)") do
		local colorHex = bd:sub(1, 6)
		local sym = bd:sub(7, 7)
		local rest = bd:sub(8)
		local cc = true
		if rest:sub(1,1) == "^" then cc = false; rest = rest:sub(2) end
		local sizeD, posD, extra = rest:match("^([%d,]+)%.([%-%.%d,]+)%.?(.*)")
		if sizeD and posD then
			local sx, sy, sz = sizeD:match("([%d]+),([%d]+),([%d]+)")
			local px, py, pz = posD:match("([%-]?%d+%.?%d*),([%-]?%d+%.?%d*),([%-]?%d+%.?%d*)")
			if sx and px then
				local size = Vector3.new(tonumber(sx), tonumber(sy), tonumber(sz))
				local cp = Vector3.new(tonumber(px), tonumber(py), tonumber(pz))
				local is4 = (size == Vector3.new(4,4,4))
				local m4 = function(n) return ((n % 4) + 4) % 4 end
				local onGrid = m4(cp.X) == 2 and m4(cp.Y) == 2 and m4(cp.Z) == 2
				local sprays = {}
				if extra and extra ~= "" then
					for face, text, col in extra:gmatch('(%a+)"([^"]*)""([^"]*)"') do
						local fm = {L=Enum.NormalId.Left,R=Enum.NormalId.Right,T=Enum.NormalId.Top,Bo=Enum.NormalId.Bottom,F=Enum.NormalId.Front,Ba=Enum.NormalId.Back}
						if fm[face] then sprays[#sprays+1] = {face=fm[face], text=text or "", colorHex=col} end
					end
				end
				blocks[#blocks+1] = {
					size=size, centerPos=cp, color=hexToCol(colorHex),
					material=SYM[sym] or Enum.Material.SmoothPlastic,
					canCollide=cc, needsResize=not(is4 and onGrid), sprays=sprays
				}
			end
		end
	end
	return blocks
end

-- ============================================================
-- FAST RESIZE — fires all three axes as fast as possible
-- ============================================================
local function fastResize(brick, targetSize, shapeEv, hrpPos)
	if not brick or not shapeEv then return end
	local rR = math.floor(targetSize.X - 1)
	local tR = math.floor(targetSize.Y - 1)
	local bR = math.floor(targetSize.Z - 1)
	local maxR = math.max(rR, tR, bR)
	for i = 1, maxR do
		local cur = newestBrick() or brick
		if i <= rR then shapeEv:FireServer(cur, Enum.NormalId.Right, hrpPos, "increase") end
		if i <= tR then shapeEv:FireServer(cur, Enum.NormalId.Top, hrpPos, "increase") end
		if i <= bR then shapeEv:FireServer(cur, Enum.NormalId.Back, hrpPos, "increase") end
		task.wait(BUILD_CFG.ResizeSide)
	end
end

-- ============================================================
-- FAST PLACE — fires build + paint + spray + resize, no waiting for confirm
-- ============================================================
local function fastPlace(bd, buildEv, shapeEv, paintEv, hrp)
	local tpPos = bd.needsResize and cornerPos(bd.centerPos, bd.size) or bd.centerPos
	local buildPos = tpPos + Vector3.new(0, BUILD_CFG.HeightOffset, 0)

	-- teleport (physics stops instantly)
	hrp.CFrame = CFrame.new(buildPos)
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero

	local placePos = bd.needsResize and cornerPos(bd.centerPos, bd.size) or bd.centerPos
	local mode = bd.needsResize and (bd.canCollide and "detailed" or "detailed nocollide")
		or (bd.canCollide and "normal" or "nocollide")

	local before = brickCount()

	-- spam fire until it lands, but with tiny retries
	buildEv:FireServer(WS.Terrain, Enum.NormalId.Top, placePos, mode)
	local retry = bd.canCollide and BUILD_CFG.PlaceRetry or BUILD_CFG.PlaceRetryNC
	local tries = 0
	while brickCount() == before and tries < BUILD_CFG.MaxAttempts do
		task.wait(retry)
		if brickCount() > before then break end
		tries = tries + 1
		buildEv:FireServer(WS.Terrain, Enum.NormalId.Top, placePos, mode)
	end

	if brickCount() == before then return false end
	local newB = newestBrick()
	if not newB then return false end

	-- paint + spray + nocollide in parallel with the NEXT block's build
	task.spawn(function()
		pcall(function()
			paintEv:FireServer(newB, Enum.NormalId.Left, hrp.Position, "both 🤝", bd.color, MAT_PAINT[bd.material] or "smooth", "")
		end)
		if bd.sprays and #bd.sprays > 0 then
			for _, sp in ipairs(bd.sprays) do
				pcall(function()
					paintEv:FireServer(newB, sp.face, hrp.Position, "both 🤝", hexToCol(sp.colorHex), "spray", sp.text)
				end)
			end
		end
		if not bd.canCollide then
			pcall(function()
				paintEv:FireServer(newB, Enum.NormalId.Back, hrp.Position, "material", bd.color, "collide", "")
			end)
		end
	end)

	-- resize in parallel too
	if bd.needsResize and bd.size ~= Vector3.new(1,1,1) then
		task.spawn(function()
			fastResize(newB, bd.size, shapeEv, hrp.Position)
		end)
	end

	return true
end

-- ============================================================
-- NOCLIP during build
-- ============================================================
local buildNoclipConn
local function enableBuildNoclip()
	if buildNoclipConn then buildNoclipConn:Disconnect() end
	buildNoclipConn = RS.Stepped:Connect(function()
		if char then
			for _, p in ipairs(char:GetChildren()) do
				if p:IsA("BasePart") then p.CanCollide = false end
			end
		end
	end)
end

local function disableBuildNoclip()
	if buildNoclipConn then buildNoclipConn:Disconnect(); buildNoclipConn = nil end
end

-- ============================================================
-- FAST MAIN LOOP
-- ============================================================
local buildRunning = false
local stopRequested = false

local function autoBuild(buildStr)
	if buildRunning then say("already building") return end
	local blocks = parseBuild(buildStr)
	if #blocks == 0 then say("no blocks parsed") return end

	local buildEv = fastRemote("Build")
	local shapeEv = fastRemote("Shape")
	local paintEv = fastRemote("Paint")
	if not buildEv then say("no Build tool") return end
	if not shapeEv then say("no Shape tool") return end
	if not paintEv then say("no Paint tool") return end

	buildRunning = true
	stopRequested = false
	enableBuildNoclip()

	local total = #blocks
	local done = {}
	local placed = 0
	local fails = 0

	while placed < total and not stopRequested do
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp then break end

		-- nearest unbuilt
		local best, bd = nil, math.huge
		for i, b in ipairs(blocks) do
			if not done[i] then
				local d = (hrp.Position - b.centerPos).Magnitude
				if d < bd then best, bd = i, d end
			end
		end
		if not best then break end

		local ok = fastPlace(blocks[best], buildEv, shapeEv, paintEv, hrp)
		if ok then
			done[best] = true
			placed = placed + 1
		else
			fails = fails + 1
			if fails >= 3 then
				done[best] = true
				placed = placed + 1
				fails = 0
			end
		end
		-- NO WAIT between blocks — next loop iteration goes immediately
	end

	disableBuildNoclip()
	buildRunning = false
	return placed
end

-- ============================================================
-- CAPTURE — grab existing bricks as a build string
-- ============================================================
local function captureBuild(mode)
	local folder = WS:FindFirstChild("Bricks")
	if not folder then return nil end
	local parts = {}
	for _, pf in ipairs(folder:GetChildren()) do
		if mode == "all" or pf.Name == plr.Name then
			for _, b in ipairs(pf:GetChildren()) do
				if b:IsA("BasePart") and b.Name == "Brick" then parts[#parts+1] = b end
			end
		end
	end
	if #parts == 0 then return nil end
	table.sort(parts, function(a, b)
		if a.Position.X ~= b.Position.X then return a.Position.X < b.Position.X end
		if a.Position.Y ~= b.Position.Y then return a.Position.Y < b.Position.Y end
		return a.Position.Z < b.Position.Z
	end)
	local str = ""
	for _, b in ipairs(parts) do
		str = str .. "|" .. colToHex(b.Color) .. matToSym(b.Material)
		if not b.CanCollide then str = str .. "^" end
		str = str .. string.format("%d,%d,%d.", b.Size.X, b.Size.Y, b.Size.Z)
		str = str .. string.format("%.1f,%.1f,%.1f.", b.Position.X, b.Position.Y, b.Position.Z)
	end
	return str
end

-- ============================================================
-- BUILD PAGE UI
-- ============================================================
local buildScroll = Instance.new("ScrollingFrame")
buildScroll.Size = UDim2.new(1, 0, 1, 0)
buildScroll.BackgroundTransparency = 1
buildScroll.BorderSizePixel = 0
buildScroll.ScrollBarThickness = 2
reg(buildScroll, "ScrollBarImageColor3", "acc")
buildScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
buildScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
buildScroll.Parent = pBuild

local bStack = Instance.new("UIListLayout")
bStack.Padding = UDim.new(0, 6)
bStack.SortOrder = Enum.SortOrder.LayoutOrder
bStack.Parent = buildScroll

local function mkBtn(parent, label, w, colorKey, onClick)
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(w, 24)
	b.BorderSizePixel = 0
	b.AutoButtonColor = false
	b.Font = Enum.Font.GothamMedium
	b.TextSize = 10
	b.Text = label
	b.Parent = parent
	corner(b, 5)

	if colorKey == "acc" then
		reg(b, "BackgroundColor3", "acc")
		reg(b, "TextColor3", "bg")
		border(b, "acc", 1)
	elseif colorKey == "bad" then
		reg(b, "BackgroundColor3", "bad")
		b.TextColor3 = Color3.fromRGB(255, 255, 255)
		border(b, "bad", 1)
	else
		reg(b, "BackgroundColor3", "card")
		reg(b, "TextColor3", "txt")
		border(b, "line", 1)
	end

	b.MouseEnter:Connect(function()
		local base = colorKey == "acc" and C.acc or colorKey == "bad" and C.bad or C.cardHi
		tw:Create(b, TweenInfo.new(0.1), { BackgroundColor3 = base }):Play()
	end)
	b.MouseLeave:Connect(function()
		local base = colorKey == "acc" and C.acc or colorKey == "bad" and C.bad or C.card
		tw:Create(b, TweenInfo.new(0.1), { BackgroundColor3 = base }):Play()
	end)
	b.MouseButton1Click:Connect(onClick)
	return b
end

-- FILE SECTION
local fileHead = Instance.new("Frame")
fileHead.Size = UDim2.new(1, 0, 0, 20)
fileHead.BackgroundTransparency = 1
fileHead.LayoutOrder = 1
fileHead.Parent = buildScroll

local fileLbl = Instance.new("TextLabel")
fileLbl.Text = "Build Files"
fileLbl.Size = UDim2.new(1, -60, 1, 0)
fileLbl.BackgroundTransparency = 1
fileLbl.Font = Enum.Font.GothamMedium
fileLbl.TextSize = 11
reg(fileLbl, "TextColor3", "txt")
fileLbl.TextXAlignment = Enum.TextXAlignment.Left
fileLbl.Parent = fileHead

local reloadBtn = Instance.new("TextButton")
reloadBtn.Size = UDim2.fromOffset(56, 18)
reloadBtn.Position = UDim2.new(1, -56, 0.5, -9)
reloadBtn.AnchorPoint = Vector2.new(0, 0.5)
reg(reloadBtn, "BackgroundColor3", "card")
reloadBtn.BorderSizePixel = 0
reloadBtn.AutoButtonColor = false
reloadBtn.Font = Enum.Font.GothamMedium
reloadBtn.TextSize = 9
reloadBtn.Text = "reload"
reg(reloadBtn, "TextColor3", "acc")
reloadBtn.Parent = fileHead
corner(reloadBtn, 4)
border(reloadBtn, "line", 1)

local fileList = Instance.new("Frame")
fileList.Size = UDim2.new(1, 0, 0, 110)
reg(fileList, "BackgroundColor3", "card")
fileList.BorderSizePixel = 0
fileList.LayoutOrder = 2
fileList.Parent = buildScroll
corner(fileList, 6)
border(fileList, "line", 1)

local fileScroll = Instance.new("ScrollingFrame")
fileScroll.Size = UDim2.new(1, -8, 1, -8)
fileScroll.Position = UDim2.new(0, 4, 0, 4)
fileScroll.BackgroundTransparency = 1
fileScroll.BorderSizePixel = 0
fileScroll.ScrollBarThickness = 2
reg(fileScroll, "ScrollBarImageColor3", "acc")
fileScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
fileScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
fileScroll.Parent = fileList

local fileStack = Instance.new("UIListLayout")
fileStack.Padding = UDim.new(0, 4)
fileStack.SortOrder = Enum.SortOrder.LayoutOrder
fileStack.Parent = fileScroll

local selectedFile, selectedData = nil, nil

local function clearFileRows()
	for _, c in ipairs(fileScroll:GetChildren()) do
		if c:IsA("TextButton") or c:IsA("TextLabel") then c:Destroy() end
	end
end

local function refreshFiles()
	clearFileRows()
	selectedFile, selectedData = nil, nil
	local files = listFilesSafe()
	local found = {}
	for _, path in ipairs(files) do
		local short = path:match("([^/\\]+)$") or path
		if short:match("EcBuild%.txt$") then
			local display = short:gsub("EcBuild%.txt$", ""):gsub("_", " ")
			display = display:gsub("^%s+", ""):gsub("%s+$", "")
			if display == "" then display = short end
			local data = readFileSafe(path)
			found[#found+1] = { full = path, short = short, display = display, data = data }
		end
	end
	if #found == 0 then
		local empty = Instance.new("TextLabel")
		empty.Text = "  no *EcBuild.txt files found"
		empty.Size = UDim2.new(1, 0, 0, 20)
		empty.BackgroundTransparency = 1
		empty.Font = Enum.Font.Gotham
		empty.TextSize = 10
		reg(empty, "TextColor3", "dim")
		empty.TextXAlignment = Enum.TextXAlignment.Left
		empty.LayoutOrder = 1
		empty.Parent = fileScroll
		return
	end
	for i, f in ipairs(found) do
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(1, -4, 0, 22)
		b.BackgroundColor3 = C.card
		b.BorderSizePixel = 0
		b.AutoButtonColor = false
		b.Font = Enum.Font.Gotham
		b.TextSize = 10
		b.Text = "  " .. f.display
		reg(b, "TextColor3", "txt")
		b.TextXAlignment = Enum.TextXAlignment.Left
		b.LayoutOrder = i
		b.Parent = fileScroll
		corner(b, 4)
		border(b, "line", 1)

		b.MouseEnter:Connect(function()
			if selectedFile ~= f.full then
				tw:Create(b, TweenInfo.new(0.1), { BackgroundColor3 = C.cardHi }):Play()
			end
		end)
		b.MouseLeave:Connect(function()
			if selectedFile ~= f.full then
				tw:Create(b, TweenInfo.new(0.1), { BackgroundColor3 = C.card }):Play()
			end
		end)
		b.MouseButton1Click:Connect(function()
			selectedFile = f.full
			selectedData = f.data
			say("selected: " .. f.display)
			for _, ch in ipairs(fileScroll:GetChildren()) do
				if ch:IsA("TextButton") then
					if ch == b then
						ch.TextColor3 = C.acc
						ch.BackgroundColor3 = C.cardHi
					else
						ch.TextColor3 = C.txt
						ch.BackgroundColor3 = C.card
					end
				end
			end
		end)
	end
end

reloadBtn.MouseButton1Click:Connect(function() refreshFiles(); say("reloaded files") end)
refreshFiles()

local fileActions = Instance.new("Frame")
fileActions.Size = UDim2.new(1, 0, 0, 26)
fileActions.BackgroundTransparency = 1
fileActions.LayoutOrder = 3
fileActions.Parent = buildScroll

local fileRow = Instance.new("UIListLayout")
fileRow.FillDirection = Enum.FillDirection.Horizontal
fileRow.Padding = UDim.new(0, 6)
fileRow.SortOrder = Enum.SortOrder.LayoutOrder
fileRow.Parent = fileActions

mkBtn(fileActions, "build", 70, "acc", function()
	if not selectedData then say("select a file first") return end
	say("building...")
	task.spawn(function()
		local ok = autoBuild(selectedData)
		if ok then say("built " .. tostring(ok)) else say("build failed") end
	end)
end).LayoutOrder = 1

mkBtn(fileActions, "copy", 60, nil, function()
	if not selectedData then say("select a file first") return end
	if clip(selectedData) then say("copied") else say("clipboard broke") end
end).LayoutOrder = 2

mkBtn(fileActions, "save", 60, nil, function()
	if not selectedData then say("select a file first") return end
	if writeFileSafe(selectedFile, selectedData) then say("saved") else say("no writefile") end
end).LayoutOrder = 3

mkBtn(fileActions, "delete", 60, nil, function()
	if not selectedFile then say("select a file first") return end
	pcall(function() if delfile then delfile(selectedFile) end end)
	refreshFiles()
	say("deleted")
end).LayoutOrder = 4

-- PASTE
local pasteLbl = Instance.new("TextLabel")
pasteLbl.Text = "Paste Build String"
pasteLbl.Size = UDim2.new(1, 0, 0, 16)
pasteLbl.BackgroundTransparency = 1
pasteLbl.Font = Enum.Font.GothamMedium
pasteLbl.TextSize = 11
reg(pasteLbl, "TextColor3", "txt")
pasteLbl.TextXAlignment = Enum.TextXAlignment.Left
pasteLbl.LayoutOrder = 4
pasteLbl.Parent = buildScroll

local pasteBox = Instance.new("TextBox")
pasteBox.Size = UDim2.new(1, 0, 0, 64)
reg(pasteBox, "BackgroundColor3", "card")
pasteBox.BorderSizePixel = 0
pasteBox.Font = Enum.Font.Code
pasteBox.TextSize = 9
reg(pasteBox, "TextColor3", "txt")
pasteBox.Text = ""
pasteBox.PlaceholderText = "paste your build string here..."
reg(pasteBox, "PlaceholderColor3", "dim")
pasteBox.TextWrapped = true
pasteBox.TextXAlignment = Enum.TextXAlignment.Left
pasteBox.TextYAlignment = Enum.TextYAlignment.Top
pasteBox.ClearTextOnFocus = false
pasteBox.MultiLine = true
pasteBox.LayoutOrder = 5
pasteBox.Parent = buildScroll
corner(pasteBox, 6)
border(pasteBox, "line", 1)

local pasteActions = Instance.new("Frame")
pasteActions.Size = UDim2.new(1, 0, 0, 26)
pasteActions.BackgroundTransparency = 1
pasteActions.LayoutOrder = 6
pasteActions.Parent = buildScroll

local pRow = Instance.new("UIListLayout")
pRow.FillDirection = Enum.FillDirection.Horizontal
pRow.Padding = UDim.new(0, 6)
pRow.SortOrder = Enum.SortOrder.LayoutOrder
pRow.Parent = pasteActions

mkBtn(pasteActions, "build pasted", 100, "acc", function()
	if pasteBox.Text == "" then say("nothing pasted") return end
	say("building pasted...")
	task.spawn(function()
		local ok = autoBuild(pasteBox.Text)
		if ok then say("built " .. tostring(ok)) else say("build failed") end
	end)
end).LayoutOrder = 1

mkBtn(pasteActions, "copy", 60, nil, function()
	if clip(pasteBox.Text) then say("copied") else say("clipboard broke") end
end).LayoutOrder = 2

mkBtn(pasteActions, "clear", 60, nil, function()
	pasteBox.Text = ""
	say("cleared")
end).LayoutOrder = 3

-- CAPTURE
local capLbl = Instance.new("TextLabel")
capLbl.Text = "Capture Existing Bricks"
capLbl.Size = UDim2.new(1, 0, 0, 16)
capLbl.BackgroundTransparency = 1
capLbl.Font = Enum.Font.GothamMedium
capLbl.TextSize = 11
reg(capLbl, "TextColor3", "txt")
capLbl.TextXAlignment = Enum.TextXAlignment.Left
capLbl.LayoutOrder = 7
capLbl.Parent = buildScroll

local capRow1 = Instance.new("Frame")
capRow1.Size = UDim2.new(1, 0, 0, 26)
capRow1.BackgroundTransparency = 1
capRow1.LayoutOrder = 8
capRow1.Parent = buildScroll

local capL1 = Instance.new("UIListLayout")
capL1.FillDirection = Enum.FillDirection.Horizontal
capL1.Padding = UDim.new(0, 6)
capL1.SortOrder = Enum.SortOrder.LayoutOrder
capL1.Parent = capRow1

mkBtn(capRow1, "you copy", 90, nil, function()
	local s = captureBuild("you")
	if not s then say("nothing to capture") return end
	if clip(s) then say("copied my bricks") else say("clipboard broke") end
end).LayoutOrder = 1

mkBtn(capRow1, "you save", 90, nil, function()
	local s = captureBuild("you")
	if not s then say("nothing to capture") return end
	local name = plr.Name .. "EcBuild.txt"
	if writeFileSafe(name, s) then say("saved " .. name) else say("no writefile") end
end).LayoutOrder = 2

mkBtn(capRow1, "reload", 60, nil, function()
	refreshFiles()
	say("reloaded")
end).LayoutOrder = 3

local capRow2 = Instance.new("Frame")
capRow2.Size = UDim2.new(1, 0, 0, 26)
capRow2.BackgroundTransparency = 1
capRow2.LayoutOrder = 9
capRow2.Parent = buildScroll

local capL2 = Instance.new("UIListLayout")
capL2.FillDirection = Enum.FillDirection.Horizontal
capL2.Padding = UDim.new(0, 6)
capL2.SortOrder = Enum.SortOrder.LayoutOrder
capL2.Parent = capRow2

mkBtn(capRow2, "all copy", 90, nil, function()
	local s = captureBuild("all")
	if not s then say("nothing to capture") return end
	if clip(s) then say("copied all bricks") else say("clipboard broke") end
end).LayoutOrder = 1

mkBtn(capRow2, "all save", 90, nil, function()
	local s = captureBuild("all")
	if not s then say("nothing to capture") return end
	if writeFileSafe("AllEcBuild.txt", s) then say("saved AllEcBuild.txt") else say("no writefile") end
end).LayoutOrder = 2

mkBtn(capRow2, "clear me", 90, "bad", function()
	local ev = fastRemote("Delete")
	if not ev then say("no Delete tool") return end
	local folder = myBricks()
	if not folder then say("no bricks") return end
	local n = 0
	for _, b in ipairs(folder:GetChildren()) do
		if b:IsA("BasePart") and b.Name == "Brick" then
			task.spawn(function()
				pcall(function()
					if ev.Invoke then ev:Invoke(b, b.Position)
					elseif ev.FireServer then ev:FireServer(b, b.Position) end
				end)
			end)
			n = n + 1
		end
	end
	say("deleting " .. n .. " bricks")
end).LayoutOrder = 3

local stopRow = Instance.new("Frame")
stopRow.Size = UDim2.new(1, 0, 0, 28)
stopRow.BackgroundTransparency = 1
stopRow.LayoutOrder = 10
stopRow.Parent = buildScroll

mkBtn(stopRow, "stop build", 200, "bad", function()
	if buildRunning then
		stopRequested = true
		say("stopping...")
	else
		say("nothing running")
	end
end)