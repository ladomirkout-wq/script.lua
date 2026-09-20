if not listfiles or not readfile then
    error("Your executor does not support listfiles or readfile!")
end

local inflate
do
    local LENGTH_BASE = {3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258}
    local LENGTH_EXTRA = {0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0}
    local DIST_BASE = {1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577}
    local DIST_EXTRA = {0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13}
    local CLEN_ORDER = {17,18,19,1,9,8,10,7,11,6,12,5,13,4,14,3,15,2,16}

    local function buildTable(lengths)
        local maxBits = 0
        for i = 1, #lengths do if lengths[i] > maxBits then maxBits = lengths[i] end end
        local blCount = {}
        for i = 0, maxBits do blCount[i] = 0 end
        for i = 1, #lengths do blCount[lengths[i]] = blCount[lengths[i]] + 1 end
        blCount[0] = 0
        local nextCode, code = {}, 0
        for bits = 1, maxBits do
            code = (code + blCount[bits - 1]) * 2
            nextCode[bits] = code
        end
        local map = {}
        for bits = 1, maxBits do map[bits] = {} end
        for sym = 1, #lengths do
            local len = lengths[sym]
            if len > 0 then
                map[len][nextCode[len]] = sym - 1
                nextCode[len] = nextCode[len] + 1
            end
        end
        return map, maxBits
    end

    inflate = function(data)
        local pos, bitBuf, bitCnt = 3, 0, 0
        local function getByte() local b = string.byte(data, pos); pos = pos + 1; return b or 0 end
        local function getBits(n)
            while bitCnt < n do
                bitBuf = bitBuf + getByte() * 2 ^ bitCnt
                bitCnt = bitCnt + 8
            end
            local div = 2 ^ n
            local val = bitBuf % div
            bitBuf = (bitBuf - val) / div
            bitCnt = bitCnt - n
            return val
        end
        local out, outLen = {}, 0
        local function pushByte(b) outLen = outLen + 1; out[outLen] = string.char(b) end
        local function decode(map, maxBits)
            local code = 0
            for len = 1, maxBits do
                code = code * 2 + getBits(1)
                local m = map[len]
                local s = m and m[code]
                if s then return s end
            end
            error("Invalid Huffman code")
        end
        local function decodeBlock(litMap, litMax, distMap, distMax)
            while true do
                local sym = decode(litMap, litMax)
                if sym < 256 then pushByte(sym)
                elseif sym == 256 then return
                else
                    local li = sym - 257 + 1
                    local length = LENGTH_BASE[li] + getBits(LENGTH_EXTRA[li])
                    local dsym = decode(distMap, distMax)
                    local di = dsym + 1
                    local dist = DIST_BASE[di] + getBits(DIST_EXTRA[di])
                    local start = outLen - dist + 1
                    for i = 0, length - 1 do pushByte(string.byte(out[start + i])) end
                end
            end
        end
        while true do
            local bfinal, btype = getBits(1), getBits(2)
            if btype == 0 then
                bitBuf, bitCnt = 0, 0
                local len = getByte() + getByte() * 256
                getByte(); getByte()
                for _ = 1, len do pushByte(getByte()) end
            elseif btype == 1 then
                local litLengths = {}
                for i = 1, 144 do litLengths[i] = 8 end
                for i = 145, 256 do litLengths[i] = 9 end
                for i = 257, 280 do litLengths[i] = 7 end
                for i = 281, 288 do litLengths[i] = 8 end
                local distLengths = {}
                for i = 1, 30 do distLengths[i] = 5 end
                local lm, lmax = buildTable(litLengths)
                local dm, dmax = buildTable(distLengths)
                decodeBlock(lm, lmax, dm, dmax)
            elseif btype == 2 then
                local hlit, hdist, hclen = getBits(5) + 257, getBits(5) + 1, getBits(4) + 4
                local clLengths = {}
                for i = 1, 19 do clLengths[i] = 0 end
                for i = 1, hclen do clLengths[CLEN_ORDER[i]] = getBits(3) end
                local cm, cmax = buildTable(clLengths)
                local lengths, total, i = {}, hlit + hdist, 1
                while i <= total do
                    local sym = decode(cm, cmax)
                    if sym < 16 then lengths[i] = sym; i = i + 1
                    elseif sym == 16 then
                        local prev = lengths[i - 1] or 0
                        for _ = 1, 3 + getBits(2) do lengths[i] = prev; i = i + 1 end
                    elseif sym == 17 then
                        for _ = 1, 3 + getBits(3) do lengths[i] = 0; i = i + 1 end
                    else
                        for _ = 1, 11 + getBits(7) do lengths[i] = 0; i = i + 1 end
                    end
                end
                local litLengths, distLengths = {}, {}
                for j = 1, hlit do litLengths[j] = lengths[j] end
                for j = 1, hdist do distLengths[j] = lengths[hlit + j] end
                local lm, lmax = buildTable(litLengths)
                local dm, dmax = buildTable(distLengths)
                decodeBlock(lm, lmax, dm, dmax)
            else error("Invalid deflate block type") end
            if bfinal == 1 then break end
        end
        return table.concat(out)
    end
end

local PNGDecoder = {}
PNGDecoder.__index = PNGDecoder
local CHANNELS_FOR_COLOR_TYPE = { [0]=1, [2]=3, [3]=1, [4]=2, [6]=4 }

function PNGDecoder.new(rawData)
    local self = setmetatable({}, PNGDecoder)
    self.Data = rawData
    self.Length = #rawData
    self.Offset = 1
    self.IDAT = {}
    if self:ReadBytes(8) ~= "\137PNG\r\n\26\n" then error("Invalid PNG Signature") end
    while self.Offset <= self.Length do
        local length = self:ReadInt32()
        local chunkType = self:ReadBytes(4)
        if chunkType == "IHDR" then
            self.Width, self.Height = self:ReadInt32(), self:ReadInt32()
            self.BitDepth = string.byte(self:ReadBytes(1))
            self.ColorType = string.byte(self:ReadBytes(1))
            self.Compression = string.byte(self:ReadBytes(1))
            self.Filter = string.byte(self:ReadBytes(1))
            self.Interlace = string.byte(self:ReadBytes(1))
            self:ReadBytes(4)
        elseif chunkType == "PLTE" then
            local data = self:ReadBytes(length)
            self.PLTE = {}
            for i = 1, length, 3 do
                local r, g, b = string.byte(data, i, i + 2)
                table.insert(self.PLTE, { r or 0, g or 0, b or 0 })
            end
            self:ReadBytes(4)
        elseif chunkType == "IDAT" then
            table.insert(self.IDAT, self:ReadBytes(length))
            self:ReadBytes(4)
        elseif chunkType == "IEND" then break
        else self:ReadBytes(length + 4) end
    end
    if not self.Width or not self.Height then error("Missing IHDR chunk") end
    if self.Interlace ~= 0 then error("Interlaced PNGs are not supported") end
    self:DecodePixels()
    return self
end

function PNGDecoder:ReadBytes(count)
    local val = string.sub(self.Data, self.Offset, self.Offset + count - 1)
    self.Offset = self.Offset + count
    return val
end

function PNGDecoder:ReadInt32()
    local b1, b2, b3, b4 = string.byte(self:ReadBytes(4), 1, 4)
    return (b1 * 16777216) + (b2 * 65536) + (b3 * 256) + b4
end

function PNGDecoder:DecodePixels()
    local channels = CHANNELS_FOR_COLOR_TYPE[self.ColorType]
    if not channels then error("Unsupported PNG color type") end
    local bitDepth = self.BitDepth
    if bitDepth ~= 8 and bitDepth ~= 16 then error("Unsupported PNG bit depth") end
    local bytesPerSample = bitDepth / 8
    local bpp = channels * bytesPerSample
    local stride = self.Width * bpp
    local raw = inflate(table.concat(self.IDAT))
    local filteredRows, prev = {}, {}
    for i = 1, stride do prev[i] = 0 end
    local p = 1
    for y = 1, self.Height do
        local filterType = string.byte(raw, p) or 0
        p = p + 1
        local row = { string.byte(raw, p, p + stride - 1) }
        p = p + stride
        for i = 1, stride do if not row[i] then row[i] = 0 end end
        if filterType == 1 then
            for i = 1, stride do
                local a = (i > bpp) and row[i - bpp] or 0
                row[i] = (row[i] + a) % 256
            end
        elseif filterType == 2 then
            for i = 1, stride do row[i] = (row[i] + prev[i]) % 256 end
        elseif filterType == 3 then
            for i = 1, stride do
                local a = (i > bpp) and row[i - bpp] or 0
                row[i] = (row[i] + math.floor((a + prev[i]) / 2)) % 256
            end
        elseif filterType == 4 then
            for i = 1, stride do
                local a = (i > bpp) and row[i - bpp] or 0
                local b = prev[i]
                local c = (i > bpp) and prev[i - bpp] or 0
                local pp = a + b - c
                local pa, pb, pc = math.abs(pp - a), math.abs(pp - b), math.abs(pp - c)
                local pr
                if pa <= pb and pa <= pc then pr = a
                elseif pb <= pc then pr = b
                else pr = c end
                row[i] = (row[i] + pr) % 256
            end
        elseif filterType ~= 0 then error("Unknown PNG filter type") end
        filteredRows[y] = row
        prev = row
    end
    self.Rows = {}
    for y = 1, self.Height do
        local row = filteredRows[y]
        if bitDepth == 16 then
            local r8 = {}
            local samples = self.Width * channels
            for i = 1, samples do r8[i] = row[(i - 1) * 2 + 1] end
            self.Rows[y] = r8
        else
            self.Rows[y] = row
        end
    end
    self.Channels = channels
end

function PNGDecoder:GetPixel(x, y)
    local row = self.Rows[y]
    if not row or x < 1 or x > self.Width then return nil end
    local ct = self.ColorType
    if ct == 2 then
        local i = (x - 1) * 3
        return Color3.fromRGB(row[i+1] or 0, row[i+2] or 0, row[i+3] or 0)
    elseif ct == 6 then
        local i = (x - 1) * 4
        return Color3.fromRGB(row[i+1] or 0, row[i+2] or 0, row[i+3] or 0)
    elseif ct == 0 then
        local v = row[x] or 0
        return Color3.fromRGB(v, v, v)
    elseif ct == 4 then
        local i = (x - 1) * 2
        local v = row[i + 1] or 0
        return Color3.fromRGB(v, v, v)
    elseif ct == 3 then
        local idx = (row[x] or 0) + 1
        local c = self.PLTE and self.PLTE[idx]
        if c then return Color3.fromRGB(c[1], c[2], c[3]) end
        return Color3.fromRGB(255, 255, 255)
    end
    return Color3.fromRGB(255, 255, 255)
end

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local stopRequested = false
local isRunning = false
local BATCH_SIZE = 40
local MAX_CONCURRENT = 120

local function isPlayerPart(obj)
    for _, plr in ipairs(Players:GetPlayers()) do
        local char = plr.Character
        if char and obj:IsDescendantOf(char) then return true end
    end
    return false
end

local function findPaintFunction()
    local char = player.Character
    if not char then return nil, "No character" end
    local bucket = char:FindFirstChild("PaintBucket")
    if not bucket then return nil, "PaintBucket tool not equipped" end
    local remotes = bucket:FindFirstChild("Remotes")
    if not remotes then return nil, "PaintBucket.Remotes missing" end
    local sc = remotes:FindFirstChild("ServerControls")
    if not sc then return nil, "ServerControls missing" end
    if not sc:IsA("RemoteFunction") then return nil, "ServerControls not RemoteFunction" end
    return sc, "OK"
end

local function colorsMatch(a, b, tolerance)
    tolerance = tolerance or 0.02
    return math.abs(a.R - b.R) < tolerance
       and math.abs(a.G - b.G) < tolerance
       and math.abs(a.B - b.B) < tolerance
end

local function makePrimer(color)
    local r, g, b = (color.R + 0.5) % 1, (color.G + 0.5) % 1, (color.B + 0.5) % 1
    if colorsMatch(Color3.new(r, g, b), color, 0.15) then r, g, b = 1 - r, 1 - g, 1 - b end
    return Color3.new(r, g, b)
end

local function applyRotation(u, v, rotation)
    if rotation == 90 then return v, 1 - u
    elseif rotation == 180 then return 1 - u, 1 - v
    elseif rotation == 270 then return 1 - v, u
    end
    return u, v
end

local function sortByWave(partData, waveStyle)
    if waveStyle == "Rows" then
        table.sort(partData, function(a, b)
            if math.abs(a.v - b.v) > 0.001 then return a.v < b.v end
            return a.u < b.u
        end)
    elseif waveStyle == "Columns" then
        table.sort(partData, function(a, b)
            if math.abs(a.u - b.u) > 0.001 then return a.u < b.u end
            return a.v < b.v
        end)
    elseif waveStyle == "Random" then
        for i = #partData, 2, -1 do
            local j = math.random(i)
            partData[i], partData[j] = partData[j], partData[i]
        end
    else
        table.sort(partData, function(a, b) return a.wave < b.wave end)
    end
end

local function buildPartData(imageData, cornerA, cornerB, rotation, waveStyle)
    if not cornerA or not cornerB then return nil, "No corners" end

    local regionMin = Vector3.new(
        math.min(cornerA.X, cornerB.X), math.min(cornerA.Y, cornerB.Y), math.min(cornerA.Z, cornerB.Z)
    )
    local regionMax = Vector3.new(
        math.max(cornerA.X, cornerB.X), math.max(cornerA.Y, cornerB.Y), math.max(cornerA.Z, cornerB.Z)
    )

    local parts = {}
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("BasePart") and not obj:IsA("Terrain") and not isPlayerPart(obj) then
            local p = obj.Position
            if p.X >= regionMin.X and p.X <= regionMax.X
                and p.Y >= regionMin.Y and p.Y <= regionMax.Y
                and p.Z >= regionMin.Z and p.Z <= regionMax.Z then
                table.insert(parts, obj)
            end
        end
    end
    if #parts == 0 then return nil, "No parts in region" end

    local axisList = {
        { id = 1, spread = regionMax.X - regionMin.X },
        { id = 2, spread = regionMax.Y - regionMin.Y },
        { id = 3, spread = regionMax.Z - regionMin.Z },
    }
    table.sort(axisList, function(a, b) return a.spread > b.spread end)
    local colAxis, rowAxis = axisList[1], axisList[2]

    local function getAxis(pos, id)
        if id == 1 then return pos.X end
        if id == 2 then return pos.Y end
        return pos.Z
    end

    local colA, colB = getAxis(cornerA, colAxis.id), getAxis(cornerB, colAxis.id)
    local rowA, rowB = getAxis(cornerA, rowAxis.id), getAxis(cornerB, rowAxis.id)
    local colSpan, rowSpan = colB - colA, rowB - rowA

    if math.abs(colSpan) < 0.001 or math.abs(rowSpan) < 0.001 then
        return nil, "Corners share an axis"
    end

    local imgW, imgH = imageData.Width, imageData.Height
    local invertRow = (rowAxis.id == 2)

    local partData = table.create(#parts)
    for i = 1, #parts do
        local p = parts[i]
        local c = getAxis(p.Position, colAxis.id)
        local r = getAxis(p.Position, rowAxis.id)
        local u = math.clamp((c - colA) / colSpan, 0, 1)
        local v = math.clamp((r - rowA) / rowSpan, 0, 1)
        if invertRow then v = 1 - v end

        local su, sv = applyRotation(u, v, rotation)

        local ix = math.clamp(math.floor(su * (imgW - 1)) + 1, 1, imgW)
        local iy = math.clamp(math.floor(sv * (imgH - 1)) + 1, 1, imgH)
        local color = imageData:GetPixel(ix, iy)

        partData[i] = { part = p, u = u, v = v, wave = u + v, color = color }
    end

    sortByWave(partData, waveStyle)
    return partData
end

local function previewPaint(statusLabel, filePath, cornerA, cornerB, rotation, waveStyle)
    if not filePath or filePath == "" then statusLabel.Text = "Pick an image first!"; return end
    if not cornerA or not cornerB then statusLabel.Text = "Set both corners first!"; return end

    statusLabel.Text = "Previewing..."
    local ok, rawData = pcall(readfile, filePath)
    if not (ok and rawData) then statusLabel.Text = "Read failed!"; return end

    local decodeOk, imageData = pcall(PNGDecoder.new, rawData)
    if not (decodeOk and imageData) then statusLabel.Text = "Decode failed!"; return end

    local partData, err = buildPartData(imageData, cornerA, cornerB, rotation, waveStyle)
    if not partData then statusLabel.Text = "Preview error: " .. err; return end

    local applied = 0
    for i = 1, #partData do
        local entry = partData[i]
        if entry.color then
            pcall(function() entry.part.Color = entry.color end)
            applied = applied + 1
        end
        if i % 500 == 0 then
            statusLabel.Text = string.format("Previewing... %d/%d", i, #partData)
            task.wait()
        end
    end

    statusLabel.Text = string.format("Preview ready — %d parts colored locally.", applied)
end

local function paintExistingStuds(imageData, statusLabel, cornerA, cornerB, waveDelay, forceRepaint, waveStyle, rotation)
    local paintFn, err = findPaintFunction()
    if not paintFn then
        statusLabel.Text = "Paint Bucket not ready: " .. err
        warn("[Paint] " .. err)
        return
    end

    local partData, buildErr = buildPartData(imageData, cornerA, cornerB, rotation, waveStyle)
    if not partData then statusLabel.Text = "Error: " .. buildErr; return end

    local painted, failed, primed, pending = 0, 0, 0, 0
    local total = #partData
    local startTime = os.clock()

    local function fireRemote(part, targetColor)
        pending = pending + 1
        pcall(function()
            if forceRepaint and part.Locked then part.Locked = false end
            part.Color = targetColor
        end)
        task.spawn(function()
            if forceRepaint and colorsMatch(part.Color, targetColor, 0.05) then
                local primer = makePrimer(targetColor)
                pcall(function() paintFn:InvokeServer("PaintPart", { Part = part, Color = primer }) end)
                primed = primed + 1
            end
            local ok = pcall(function()
                paintFn:InvokeServer("PaintPart", { Part = part, Color = targetColor })
            end)
            if ok then painted = painted + 1 else failed = failed + 1 end
            pending = pending - 1
        end)
    end

    statusLabel.Text = string.format("Wave [%s] %d parts  •  delay %.3fs...", waveStyle, total, waveDelay)

    for i = 1, total, BATCH_SIZE do
        if stopRequested then break end
        local batchEnd = math.min(i + BATCH_SIZE - 1, total)
        for j = i, batchEnd do
            local entry = partData[j]
            if entry.color then fireRemote(entry.part, entry.color) end
            if pending >= MAX_CONCURRENT then
                while pending >= MAX_CONCURRENT and not stopRequested do task.wait() end
            end
        end
        local elapsed = os.clock() - startTime
        local rate = (elapsed > 0) and (batchEnd / elapsed) or 0
        statusLabel.Text = string.format("Wave [%s] %d/%d  •  %.0f/s  •  primed %d",
            waveStyle, batchEnd, total, rate, primed)
        task.wait(waveDelay > 0 and waveDelay or nil)
    end

    statusLabel.Text = "Finishing " .. pending .. " requests..."
    while pending > 0 and not stopRequested do task.wait(0.05) end

    local elapsed = os.clock() - startTime
    if stopRequested then
        statusLabel.Text = string.format("STOPPED at %d/%d in %.1fs%s", painted, total, elapsed,
            failed > 0 and (" (" .. failed .. " failed)") or "")
    else
        statusLabel.Text = string.format("Done! %d/%d in %.1fs%s%s", painted, total, elapsed,
            primed > 0 and (" [" .. primed .. " primed]") or "",
            failed > 0 and (" (" .. failed .. " failed)") or "")
    end
end

local function startPaint(statusLabel, filePath, cornerA, cornerB, waveDelay, forceRepaint, waveStyle, rotation)
    if isRunning then statusLabel.Text = "Already running — press Stop."; return end
    if not filePath or filePath == "" then statusLabel.Text = "Pick an image first!"; return end
    if not cornerA or not cornerB then statusLabel.Text = "Set both corners first!"; return end

    isRunning = true
    stopRequested = false
    statusLabel.Text = "Reading: " .. filePath

    local ok, rawData = pcall(readfile, filePath)
    if not (ok and rawData) then
        statusLabel.Text = "Read failed!"; isRunning = false; return
    end
    local decodeOk, imageData = pcall(PNGDecoder.new, rawData)
    if not (decodeOk and imageData) then
        statusLabel.Text = "Decode failed!"; isRunning = false; return
    end

    local paintOk, err = pcall(paintExistingStuds, imageData, statusLabel, cornerA, cornerB, waveDelay, forceRepaint, waveStyle, rotation)
    if not paintOk then statusLabel.Text = "Paint error!"; warn(tostring(err)) end
    isRunning = false
end

local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "StudPainterUI"
screenGui.ResetOnSpawn = false
local ok, _ = pcall(function() screenGui.Parent = CoreGui end)
if not ok then screenGui.Parent = player:WaitForChild("PlayerGui") end

local FRAME_HEIGHT = 420
local TITLE_HEIGHT = 28

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 340, 0, FRAME_HEIGHT)
mainFrame.Position = UDim2.new(0.5, -170, 0.4, -210)
mainFrame.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
mainFrame.BorderSizePixel = 0
mainFrame.Active = true
mainFrame.Draggable = true
mainFrame.Parent = screenGui
Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 8)

local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, TITLE_HEIGHT)
titleBar.Position = UDim2.new(0, 0, 0, 0)
titleBar.BackgroundTransparency = 1
titleBar.Parent = mainFrame

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -70, 0, TITLE_HEIGHT)
titleLabel.Position = UDim2.new(0, 8, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "PNG Paint Bucket — Arena"
titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLabel.Font = Enum.Font.SourceSansBold
titleLabel.TextSize = 16
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Parent = mainFrame

local minBtn = Instance.new("TextButton")
minBtn.Size = UDim2.new(0, 22, 0, 22)
minBtn.Position = UDim2.new(1, -52, 0, 3)
minBtn.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
minBtn.BorderSizePixel = 0
minBtn.Text = "−"
minBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
minBtn.Font = Enum.Font.SourceSansBold
minBtn.TextSize = 18
minBtn.ZIndex = 10
minBtn.Parent = mainFrame
Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 4)

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 22, 0, 22)
closeBtn.Position = UDim2.new(1, -26, 0, 3)
closeBtn.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
closeBtn.BorderSizePixel = 0
closeBtn.Text = "×"
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.Font = Enum.Font.SourceSansBold
closeBtn.TextSize = 18
closeBtn.ZIndex = 10
closeBtn.Parent = mainFrame
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 4)

local minimizableChildren = {}

local function addMinimizable(obj)
    table.insert(minimizableChildren, obj)
    return obj
end

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, -20, 0, 24)
statusLabel.Position = UDim2.new(0, 10, 0, 28)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = "Equip the PaintBucket gear first!"
statusLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
statusLabel.Font = Enum.Font.SourceSansItalic
statusLabel.TextSize = 12
statusLabel.TextWrapped = true
statusLabel.Parent = mainFrame
addMinimizable(statusLabel)

local selectedFile = ""
local cornerA, cornerB = nil, nil
local cornerPartA, cornerPartB = nil, nil
local forceState = true
local awaitingCorner = nil
local currentRotation = 0

local waveStyles = { "Diagonal", "Rows", "Columns", "Random" }
local waveStyleIdx = 1
local waveStyle = waveStyles[waveStyleIdx]
local mouse = player:GetMouse()

local dropdownBtn = Instance.new("TextButton")
dropdownBtn.Size = UDim2.new(1, -40, 0, 28)
dropdownBtn.Position = UDim2.new(0, 20, 0, 56)
dropdownBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
dropdownBtn.BorderSizePixel = 0
dropdownBtn.Text = "Choose Image... ▼"
dropdownBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
dropdownBtn.Font = Enum.Font.SourceSans
dropdownBtn.TextSize = 14
dropdownBtn.Parent = mainFrame
Instance.new("UICorner", dropdownBtn).CornerRadius = UDim.new(0, 4)
addMinimizable(dropdownBtn)

local dropdownScroll = Instance.new("ScrollingFrame")
dropdownScroll.Size = UDim2.new(1, -40, 0, 100)
dropdownScroll.Position = UDim2.new(0, 20, 0, 88)
dropdownScroll.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
dropdownScroll.BorderSizePixel = 0
dropdownScroll.Visible = false
dropdownScroll.ZIndex = 5
dropdownScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
dropdownScroll.Parent = mainFrame
Instance.new("UICorner", dropdownScroll).CornerRadius = UDim.new(0, 4)
local scrollListLayout = Instance.new("UIListLayout")
scrollListLayout.SortOrder = Enum.SortOrder.LayoutOrder
scrollListLayout.Parent = dropdownScroll

local speedLabel = Instance.new("TextLabel")
speedLabel.Size = UDim2.new(0, 90, 0, 22)
speedLabel.Position = UDim2.new(0, 20, 0, 90)
speedLabel.BackgroundTransparency = 1
speedLabel.Text = "Wave delay:"
speedLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
speedLabel.Font = Enum.Font.SourceSans
speedLabel.TextSize = 13
speedLabel.TextXAlignment = Enum.TextXAlignment.Left
speedLabel.Parent = mainFrame
addMinimizable(speedLabel)

local speedBox = Instance.new("TextBox")
speedBox.Size = UDim2.new(0, 60, 0, 22)
speedBox.Position = UDim2.new(0, 110, 0, 90)
speedBox.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
speedBox.BorderSizePixel = 0
speedBox.Text = "0.01"
speedBox.TextColor3 = Color3.fromRGB(255, 255, 255)
speedBox.Font = Enum.Font.SourceSans
speedBox.TextSize = 13
speedBox.Parent = mainFrame
Instance.new("UICorner", speedBox).CornerRadius = UDim.new(0, 4)
addMinimizable(speedBox)

local speedUnit = Instance.new("TextLabel")
speedUnit.Size = UDim2.new(0, 130, 0, 22)
speedUnit.Position = UDim2.new(0, 180, 0, 90)
speedUnit.BackgroundTransparency = 1
speedUnit.Text = "sec between waves"
speedUnit.TextColor3 = Color3.fromRGB(150, 150, 150)
speedUnit.Font = Enum.Font.SourceSans
speedUnit.TextSize = 12
speedUnit.TextXAlignment = Enum.TextXAlignment.Left
speedUnit.Parent = mainFrame
addMinimizable(speedUnit)

local function makeSpeedBtn(text, value, xPos)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, 75, 0, 20)
    b.Position = UDim2.new(0, xPos, 0, 116)
    b.BackgroundColor3 = Color3.fromRGB(55, 55, 55)
    b.BorderSizePixel = 0
    b.Text = text
    b.TextColor3 = Color3.fromRGB(220, 220, 220)
    b.Font = Enum.Font.SourceSans
    b.TextSize = 11
    b.Parent = mainFrame
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 3)
    b.MouseButton1Click:Connect(function() speedBox.Text = tostring(value) end)
    addMinimizable(b)
end
makeSpeedBtn("Instant", 0, 20)
makeSpeedBtn("Smooth", 0.02, 103)
makeSpeedBtn("Cinematic", 0.05, 186)

local waveBtn = Instance.new("TextButton")
waveBtn.Size = UDim2.new(0, 165, 0, 22)
waveBtn.Position = UDim2.new(0, 20, 0, 142)
waveBtn.BackgroundColor3 = Color3.fromRGB(70, 70, 110)
waveBtn.BorderSizePixel = 0
waveBtn.Text = "Wave: " .. waveStyle
waveBtn.TextColor3 = Color3.fromRGB(220, 220, 255)
waveBtn.Font = Enum.Font.SourceSansBold
waveBtn.TextSize = 12
waveBtn.Parent = mainFrame
Instance.new("UICorner", waveBtn).CornerRadius = UDim.new(0, 4)
addMinimizable(waveBtn)
waveBtn.MouseButton1Click:Connect(function()
    waveStyleIdx = waveStyleIdx % #waveStyles + 1
    waveStyle = waveStyles[waveStyleIdx]
    waveBtn.Text = "Wave: " .. waveStyle
end)

local rotateBtn = Instance.new("TextButton")
rotateBtn.Size = UDim2.new(0, 145, 0, 22)
rotateBtn.Position = UDim2.new(0, 175, 0, 142)
rotateBtn.BackgroundColor3 = Color3.fromRGB(90, 60, 130)
rotateBtn.BorderSizePixel = 0
rotateBtn.Text = "Rotate: 0°"
rotateBtn.TextColor3 = Color3.fromRGB(230, 210, 255)
rotateBtn.Font = Enum.Font.SourceSansBold
rotateBtn.TextSize = 12
rotateBtn.Parent = mainFrame
Instance.new("UICorner", rotateBtn).CornerRadius = UDim.new(0, 4)
addMinimizable(rotateBtn)
rotateBtn.MouseButton1Click:Connect(function()
    currentRotation = (currentRotation + 90) % 360
    rotateBtn.Text = "Rotate: " .. currentRotation .. "°"
end)

local forceBtn = Instance.new("TextButton")
forceBtn.Size = UDim2.new(0, 20, 0, 20)
forceBtn.Position = UDim2.new(0, 20, 0, 172)
forceBtn.BackgroundColor3 = Color3.fromRGB(0, 120, 215)
forceBtn.BorderSizePixel = 0
forceBtn.Text = "✓"
forceBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
forceBtn.Font = Enum.Font.SourceSansBold
forceBtn.TextSize = 15
forceBtn.Parent = mainFrame
Instance.new("UICorner", forceBtn).CornerRadius = UDim.new(0, 3)
addMinimizable(forceBtn)

local forceLabel = Instance.new("TextLabel")
forceLabel.Size = UDim2.new(1, -60, 0, 20)
forceLabel.Position = UDim2.new(0, 46, 0, 172)
forceLabel.BackgroundTransparency = 1
forceLabel.Text = "Force Repaint (prime already-painted studs)"
forceLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
forceLabel.Font = Enum.Font.SourceSans
forceLabel.TextSize = 12
forceLabel.TextXAlignment = Enum.TextXAlignment.Left
forceLabel.Parent = mainFrame
addMinimizable(forceLabel)
forceBtn.MouseButton1Click:Connect(function()
    forceState = not forceState
    forceBtn.BackgroundColor3 = forceState and Color3.fromRGB(0, 120, 215) or Color3.fromRGB(60, 60, 60)
    forceBtn.Text = forceState and "✓" or ""
end)

local setCornerABtn = Instance.new("TextButton")
setCornerABtn.Size = UDim2.new(0, 145, 0, 26)
setCornerABtn.Position = UDim2.new(0, 20, 0, 198)
setCornerABtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
setCornerABtn.BorderSizePixel = 0
setCornerABtn.Text = "Click Corner A"
setCornerABtn.TextColor3 = Color3.fromRGB(255, 255, 255)
setCornerABtn.Font = Enum.Font.SourceSans
setCornerABtn.TextSize = 12
setCornerABtn.Parent = mainFrame
Instance.new("UICorner", setCornerABtn).CornerRadius = UDim.new(0, 4)
addMinimizable(setCornerABtn)

local setCornerBBtn = Instance.new("TextButton")
setCornerBBtn.Size = UDim2.new(0, 145, 0, 26)
setCornerBBtn.Position = UDim2.new(0, 175, 0, 198)
setCornerBBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
setCornerBBtn.BorderSizePixel = 0
setCornerBBtn.Text = "Click Corner B"
setCornerBBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
setCornerBBtn.Font = Enum.Font.SourceSans
setCornerBBtn.TextSize = 12
setCornerBBtn.Parent = mainFrame
Instance.new("UICorner", setCornerBBtn).CornerRadius = UDim.new(0, 4)
addMinimizable(setCornerBBtn)

local clearCornersBtn = Instance.new("TextButton")
clearCornersBtn.Size = UDim2.new(1, -40, 0, 20)
clearCornersBtn.Position = UDim2.new(0, 20, 0, 230)
clearCornersBtn.BackgroundColor3 = Color3.fromRGB(80, 40, 40)
clearCornersBtn.BorderSizePixel = 0
clearCornersBtn.Text = "Clear Corners"
clearCornersBtn.TextColor3 = Color3.fromRGB(255, 200, 200)
clearCornersBtn.Font = Enum.Font.SourceSans
clearCornersBtn.TextSize = 11
clearCornersBtn.Parent = mainFrame
Instance.new("UICorner", clearCornersBtn).CornerRadius = UDim.new(0, 4)
addMinimizable(clearCornersBtn)

local equipBtn = Instance.new("TextButton")
equipBtn.Size = UDim2.new(0, 145, 0, 24)
equipBtn.Position = UDim2.new(0, 20, 0, 256)
equipBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 40)
equipBtn.BorderSizePixel = 0
equipBtn.Text = "Equip PaintBucket"
equipBtn.TextColor3 = Color3.fromRGB(255, 255, 200)
equipBtn.Font = Enum.Font.SourceSansBold
equipBtn.TextSize = 11
equipBtn.Parent = mainFrame
Instance.new("UICorner", equipBtn).CornerRadius = UDim.new(0, 4)
addMinimizable(equipBtn)

local testRemoteBtn = Instance.new("TextButton")
testRemoteBtn.Size = UDim2.new(0, 145, 0, 24)
testRemoteBtn.Position = UDim2.new(0, 175, 0, 256)
testRemoteBtn.BackgroundColor3 = Color3.fromRGB(40, 80, 80)
testRemoteBtn.BorderSizePixel = 0
testRemoteBtn.Text = "Test Remote"
testRemoteBtn.TextColor3 = Color3.fromRGB(200, 255, 255)
testRemoteBtn.Font = Enum.Font.SourceSans
testRemoteBtn.TextSize = 11
testRemoteBtn.Parent = mainFrame
Instance.new("UICorner", testRemoteBtn).CornerRadius = UDim.new(0, 4)
addMinimizable(testRemoteBtn)

local previewBtn = Instance.new("TextButton")
previewBtn.Size = UDim2.new(1, -40, 0, 30)
previewBtn.Position = UDim2.new(0, 20, 0, 286)
previewBtn.BackgroundColor3 = Color3.fromRGB(120, 90, 30)
previewBtn.BorderSizePixel = 0
previewBtn.Text = "👁 Preview (local only)"
previewBtn.TextColor3 = Color3.fromRGB(255, 240, 200)
previewBtn.Font = Enum.Font.SourceSansBold
previewBtn.TextSize = 14
previewBtn.Parent = mainFrame
Instance.new("UICorner", previewBtn).CornerRadius = UDim.new(0, 4)
addMinimizable(previewBtn)

local paintBtn = Instance.new("TextButton")
paintBtn.Size = UDim2.new(0, 205, 0, 40)
paintBtn.Position = UDim2.new(0, 20, 0, 322)
paintBtn.BackgroundColor3 = Color3.fromRGB(0, 120, 215)
paintBtn.BorderSizePixel = 0
paintBtn.Text = "Paint Arena"
paintBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
paintBtn.Font = Enum.Font.SourceSansBold
paintBtn.TextSize = 16
paintBtn.Parent = mainFrame
Instance.new("UICorner", paintBtn).CornerRadius = UDim.new(0, 4)
addMinimizable(paintBtn)

local stopBtn = Instance.new("TextButton")
stopBtn.Size = UDim2.new(0, 95, 0, 40)
stopBtn.Position = UDim2.new(0, 230, 0, 322)
stopBtn.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
stopBtn.BorderSizePixel = 0
stopBtn.Text = "Stop"
stopBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
stopBtn.Font = Enum.Font.SourceSansBold
stopBtn.TextSize = 15
stopBtn.Parent = mainFrame
Instance.new("UICorner", stopBtn).CornerRadius = UDim.new(0, 4)
addMinimizable(stopBtn)

local hint = Instance.new("TextLabel")
hint.Size = UDim2.new(1, -40, 0, 40)
hint.Position = UDim2.new(0, 20, 0, 368)
hint.BackgroundTransparency = 1
hint.Text = "Preview shows colors locally. Paint commits to server.\nRotate before previewing to see the new orientation."
hint.TextColor3 = Color3.fromRGB(140, 140, 140)
hint.Font = Enum.Font.SourceSans
hint.TextSize = 11
hint.TextXAlignment = Enum.TextXAlignment.Left
hint.TextWrapped = true
hint.Parent = mainFrame
addMinimizable(hint)

local isMinimized = false
local expandedHeight = FRAME_HEIGHT
local minimizedHeight = TITLE_HEIGHT + 6

local function setMinimized(state)
    isMinimized = state
    if isMinimized then
        mainFrame.Size = UDim2.new(0, 340, 0, minimizedHeight)
        for _, obj in ipairs(minimizableChildren) do
            if obj and obj.Parent then obj.Visible = false end
        end
        if dropdownScroll then dropdownScroll.Visible = false end
        minBtn.Text = "+"
    else
        mainFrame.Size = UDim2.new(0, 340, 0, expandedHeight)
        for _, obj in ipairs(minimizableChildren) do
            if obj and obj.Parent then obj.Visible = true end
        end
        minBtn.Text = "−"
    end
end

minBtn.MouseButton1Click:Connect(function()
    setMinimized(not isMinimized)
end)

closeBtn.MouseButton1Click:Connect(function()
    if highlightContainer then highlightContainer:Destroy() end
    screenGui:Destroy()
    print("[UI] Closed.")
end)

local highlightContainer = Instance.new("Folder")
highlightContainer.Name = "CornerHighlights"
pcall(function() highlightContainer.Parent = CoreGui end)
if not highlightContainer.Parent then
    highlightContainer.Parent = player:WaitForChild("PlayerGui")
end

local highlightA, highlightB = nil, nil
local selectionA, selectionB = nil, nil

local function makeCornerVisual(part, color)
    local h = Instance.new("Highlight")
    h.FillColor = color
    h.OutlineColor = color
    h.FillTransparency = 0.4
    h.OutlineTransparency = 0
    h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    h.Adornee = part
    h.Parent = highlightContainer

    local sb = Instance.new("SelectionBox")
    sb.Adornee = part
    sb.Color3 = color
    sb.LineThickness = 0.15
    sb.SurfaceColor3 = color
    sb.SurfaceTransparency = 0.6
    sb.Transparency = 0
    sb.Parent = highlightContainer
    return h, sb
end

local function clearCornerVisual(which)
    if which == 1 then
        if highlightA then highlightA:Destroy(); highlightA = nil end
        if selectionA then selectionA:Destroy(); selectionA = nil end
    elseif which == 2 then
        if highlightB then highlightB:Destroy(); highlightB = nil end
        if selectionB then selectionB:Destroy(); selectionB = nil end
    end
end

local function setCorner(n, part)
    if n == 1 then
        clearCornerVisual(1)
        cornerPartA = part
        cornerA = part.Position
        highlightA, selectionA = makeCornerVisual(part, Color3.fromRGB(0, 255, 0))
        setCornerABtn.Text = "A: " .. part.Name
        setCornerABtn.BackgroundColor3 = Color3.fromRGB(40, 100, 40)
        print("[Corner] A set to " .. part:GetFullName())
    else
        clearCornerVisual(2)
        cornerPartB = part
        cornerB = part.Position
        highlightB, selectionB = makeCornerVisual(part, Color3.fromRGB(255, 60, 60))
        setCornerBBtn.Text = "B: " .. part.Name
        setCornerBBtn.BackgroundColor3 = Color3.fromRGB(100, 40, 40)
        print("[Corner] B set to " .. part:GetFullName())
    end
end

local function resetCorners()
    clearCornerVisual(1)
    clearCornerVisual(2)
    cornerA, cornerB = nil, nil
    cornerPartA, cornerPartB = nil, nil
    setCornerABtn.Text = "Click Corner A"
    setCornerABtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
    setCornerBBtn.Text = "Click Corner B"
    setCornerBBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
end

local function getPartUnderCursor()
    local target = mouse.Target
    if target and target:IsA("BasePart") and not isPlayerPart(target) then
        return target
    end
    local camera = workspace.CurrentCamera
    if not camera then return nil end
    local unitRay = camera:ViewportPointToRay(mouse.X, mouse.Y)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {}
    if player.Character then table.insert(params.FilterDescendantsInstances, player.Character) end
    local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * 5000, params)
    if result and result.Instance and result.Instance:IsA("BasePart") and not isPlayerPart(result.Instance) then
        return result.Instance
    end
    return nil
end

local function tryPickCorner()
    if not awaitingCorner then return false end
    local target = getPartUnderCursor()
    if not target then
        statusLabel.Text = "No part under cursor — click a stud."
        return false
    end
    local which = awaitingCorner
    awaitingCorner = nil
    setCorner(which, target)
    if which == 1 then
        setCornerABtn.BackgroundColor3 = Color3.fromRGB(40, 100, 40)
        statusLabel.Text = "Corner A set to " .. target.Name
            .. (cornerB and " — ready!" or " — now set Corner B")
    else
        setCornerBBtn.BackgroundColor3 = Color3.fromRGB(100, 40, 40)
        statusLabel.Text = "Corner B set to " .. target.Name
            .. (cornerA and " — ready!" or " — now set Corner A")
    end
    return true
end

setCornerABtn.MouseButton1Click:Connect(function()
    awaitingCorner = 1
    setCornerABtn.BackgroundColor3 = Color3.fromRGB(70, 130, 70)
    statusLabel.Text = "Click any stud for Corner A"
end)

setCornerBBtn.MouseButton1Click:Connect(function()
    awaitingCorner = 2
    setCornerBBtn.BackgroundColor3 = Color3.fromRGB(140, 60, 60)
    statusLabel.Text = "Click any stud for Corner B"
end)

clearCornersBtn.MouseButton1Click:Connect(function()
    resetCorners()
    statusLabel.Text = "Corners cleared."
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if not awaitingCorner then return end
    if input.UserInputType ~= Enum.UserInputType.MouseButton1
        and input.UserInputType ~= Enum.UserInputType.Touch then return end
    tryPickCorner()
end)

mouse.Button1Down:Connect(function()
    if not awaitingCorner then return end
    task.delay(0.05, function()
        if awaitingCorner then tryPickCorner() end
    end)
end)

equipBtn.MouseButton1Click:Connect(function()
    local backpack = player:FindFirstChild("Backpack")
    local character = player.Character
    local function findBucket(container)
        if not container then return nil end
        local b = container:FindFirstChild("PaintBucket")
        if b and b:IsA("Tool") then return b end
        for _, obj in ipairs(container:GetChildren()) do
            if obj:IsA("Tool") and obj:FindFirstChild("Remotes") then return obj end
        end
        return nil
    end
    local bucket = findBucket(character) or findBucket(backpack)
    if bucket then
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            humanoid:EquipTool(bucket)
            statusLabel.Text = "PaintBucket equipped!"
        else
            statusLabel.Text = "No Humanoid found."
        end
    else
        statusLabel.Text = "PaintBucket not in inventory!"
    end
end)

testRemoteBtn.MouseButton1Click:Connect(function()
    local fn, err = findPaintFunction()
    if fn then
        statusLabel.Text = "PaintFunction ready!"
        print("[Paint] Found: " .. fn:GetFullName())
    else
        statusLabel.Text = "Not ready: " .. err
        warn("[Paint] " .. err)
    end
end)

local function updateFileList()
    for _, child in ipairs(dropdownScroll:GetChildren()) do
        if child:IsA("TextButton") then child:Destroy() end
    end
    local files = listfiles("")
    local count = 0
    for _, filePath in ipairs(files) do
        if filePath:sub(-4):lower() == ".png" then
            count = count + 1
            local itemBtn = Instance.new("TextButton")
            itemBtn.Size = UDim2.new(1, 0, 0, 25)
            itemBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
            itemBtn.BorderSizePixel = 0
            itemBtn.Text = filePath
            itemBtn.TextColor3 = Color3.fromRGB(220, 220, 220)
            itemBtn.Font = Enum.Font.SourceSans
            itemBtn.TextSize = 14
            itemBtn.ZIndex = 6
            itemBtn.Parent = dropdownScroll
            itemBtn.MouseButton1Click:Connect(function()
                selectedFile = filePath
                dropdownBtn.Text = filePath .. " ▼"
                dropdownScroll.Visible = false
            end)
        end
    end
    dropdownScroll.CanvasSize = UDim2.new(0, 0, 0, count * 25)
end

dropdownBtn.MouseButton1Click:Connect(function()
    dropdownScroll.Visible = not dropdownScroll.Visible
    if dropdownScroll.Visible then updateFileList() end
end)

previewBtn.MouseButton1Click:Connect(function()
    dropdownScroll.Visible = false
    previewPaint(statusLabel, selectedFile, cornerA, cornerB, currentRotation, waveStyle)
end)

paintBtn.MouseButton1Click:Connect(function()
    dropdownScroll.Visible = false
    local waveDelay = tonumber(speedBox.Text)
    if not waveDelay then waveDelay = 0 end
    waveDelay = math.clamp(waveDelay, 0, 5)
    speedBox.Text = tostring(waveDelay)
    startPaint(statusLabel, selectedFile, cornerA, cornerB, waveDelay, forceState, waveStyle, currentRotation)
end)

stopBtn.MouseButton1Click:Connect(function()
    if isRunning then
        stopRequested = true
        statusLabel.Text = "Stopping..."
    else
        statusLabel.Text = "Nothing is running."
    end
end)