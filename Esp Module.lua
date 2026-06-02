local Players       = game:GetService("Players")
local RunService    = game:GetService("RunService")
local Workspace     = game:GetService("Workspace")
local CoreGui       = game:GetService("CoreGui")
local LocalPlayer   = Players.LocalPlayer

local ESP = {}

local HullColor          = Color3.fromRGB(220, 40, 40)
local TurretColor        = Color3.fromRGB(220, 40, 40)
local AmmoColor          = Color3.fromRGB(255, 235, 0)
local CrewColor          = Color3.fromRGB(0, 255, 80)
local FillTransparency   = 0.5
local OutlineTransparency= 0.2
local MaxDistance        = 20000
local VehicleScanInterval= 0.5

local ESPEnabled       = false
local TeamCheck        = false
local EnableFill       = false
local EnableOutline    = true
local ShowDistance     = false
local AmmoEspEnabled   = false
local CrewEspEnabled   = false

local ESPInstances     = {}
local AmmoHighlights   = {}
local CrewHighlights   = {}

local ESPFolder = Instance.new("Folder")
ESPFolder.Name = "ESPData"
ESPFolder.Parent = CoreGui

local function IsEspTarget(chassisName)
    if not TeamCheck then return true end
    local ownerName = chassisName:match("^Chassis(.+)$")
    if not ownerName then return true end
    local plr = Players:FindFirstChild(ownerName)
    if not plr or plr == LocalPlayer then return plr ~= LocalPlayer end
    if not LocalPlayer.Team or not plr.Team then return true end
    return plr.Team ~= LocalPlayer.Team
end

local function CreateESP(target, color, isHull)
    if ESPInstances[target] then return end
    local h = Instance.new("Highlight")
    h.FillColor = color
    h.FillTransparency = EnableFill and FillTransparency or 1
    h.OutlineColor = color
    h.OutlineTransparency = EnableOutline and OutlineTransparency or 1
    h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    h.Adornee = ESPEnabled and target or nil
    h.Parent = ESPFolder

    local bill, lbl = nil, nil
    if isHull then
        bill = Instance.new("BillboardGui")
        bill.Size = UDim2.new(0, 200, 0, 40)
        bill.StudsOffset = Vector3.new(0, -3, 0)
        bill.AlwaysOnTop = true
        bill.Adornee = target
        bill.Enabled = ESPEnabled and ShowDistance
        bill.Parent = ESPFolder

        lbl = Instance.new("TextLabel")
        lbl.BackgroundTransparency = 1
        lbl.Size = UDim2.new(1, 0, 1, 0)
        lbl.Font = Enum.Font.GothamBold
        lbl.TextSize = 15
        lbl.TextColor3 = color
        lbl.TextStrokeTransparency = 0
        lbl.Text = "0 m"
        lbl.Parent = bill
    end

    ESPInstances[target] = {
        Instance = h, DistanceBillboard = bill, DistanceLabel = lbl,
        Color = color, IsHull = isHull,
    }
end

local function ProcessChassis(c)
    if not c:IsA("Actor") then return end
    if not c.Name:match("^Chassis") then return end
    if c.Name == "Chassis" .. LocalPlayer.Name then return end
    if not IsEspTarget(c.Name) then return end

    local hull = c:FindFirstChild("Hull")
    if hull then
        for _, o in ipairs(hull:GetChildren()) do
            if o:IsA("Model") then
                CreateESP(o, HullColor, true)
                if ESPInstances[o] then ESPInstances[o].ChassisName = c.Name end
                break
            end
        end
    end
    local turret = c:FindFirstChild("Turret")
    if turret then
        for _, o in ipairs(turret:GetChildren()) do
            if o:IsA("Model") then
                CreateESP(o, TurretColor, false)
                if ESPInstances[o] then ESPInstances[o].ChassisName = c.Name end
                break
            end
        end
    end
end

local function IsCrewName(name)
    if not name then return false end
    return name:match("^Driver%d*$")
        or name:match("^Loader%d*$")
        or name:match("^Gunner%d*$")
        or name:match("^Commander%d*$")
end

local function SetExtraHighlight(store, obj, color, enabled, chassisName)
    if enabled and IsEspTarget(chassisName) then
        if not store[obj] then
            local h = Instance.new("Highlight")
            h.FillColor = color
            h.FillTransparency = 0.5
            h.OutlineColor = color
            h.OutlineTransparency = 0
            h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            h.Adornee = obj
            h.Parent = ESPFolder
            store[obj] = { Instance = h, ChassisName = chassisName }
        else
            store[obj].Instance.Adornee = obj
            store[obj].ChassisName = chassisName
        end
    else
        if store[obj] then store[obj].Instance.Adornee = nil end
    end
end

local function ProcessChassisExtras(c)
    if not c:IsA("Actor") then return end
    if not c.Name:match("^Chassis") then return end
    if c.Name == "Chassis" .. LocalPlayer.Name then return end

    for _, d in ipairs(c:GetDescendants()) do
        if d:IsA("Model") or d:IsA("BasePart") then
            if d.Name == "Ammunition" then
                SetExtraHighlight(AmmoHighlights, d, AmmoColor, AmmoEspEnabled, c.Name)
            elseif IsCrewName(d.Name) then
                SetExtraHighlight(CrewHighlights, d, CrewColor, CrewEspEnabled, c.Name)
            end
        end
    end
end

local function ScanVehicles()
    if not (ESPEnabled or AmmoEspEnabled or CrewEspEnabled) then return end
    local vf = Workspace:FindFirstChild("Vehicles")
    if not vf then return end
    for _, c in ipairs(vf:GetChildren()) do
        if ESPEnabled then ProcessChassis(c) end
        ProcessChassisExtras(c)
    end
end

local function CleanupESP()
    for obj, data in pairs(ESPInstances) do
        if not obj or not obj:IsDescendantOf(game) then
            if data.Instance then pcall(function() data.Instance:Destroy() end) end
            if data.DistanceBillboard then pcall(function() data.DistanceBillboard:Destroy() end) end
            ESPInstances[obj] = nil
        end
    end
end

local function UpdateESP()
    local cam = Workspace.CurrentCamera
    if not cam then return end
    local cp = cam.CFrame.Position
    for obj, data in pairs(ESPInstances) do
        if obj and obj:IsDescendantOf(workspace) then
            local dist = (obj:GetPivot().Position - cp).Magnitude
            local teamOk = (not data.ChassisName) or IsEspTarget(data.ChassisName)
            local vis = ESPEnabled and dist <= MaxDistance and teamOk
            if data.Instance then data.Instance.Adornee = vis and obj or nil end
            if data.IsHull and data.DistanceBillboard then
                data.DistanceBillboard.Enabled = vis and ShowDistance
                if data.DistanceLabel then
                    data.DistanceLabel.Text = math.floor(dist / 3) .. " m"
                end
            end
        end
    end
    for obj, data in pairs(AmmoHighlights) do
        if obj and obj:IsDescendantOf(workspace) then
            local teamOk = IsEspTarget(data.ChassisName)
            data.Instance.Adornee = (AmmoEspEnabled and teamOk) and obj or nil
        else
            if data.Instance then data.Instance:Destroy() end
            AmmoHighlights[obj] = nil
        end
    end
    for obj, data in pairs(CrewHighlights) do
        if obj and obj:IsDescendantOf(workspace) then
            local teamOk = IsEspTarget(data.ChassisName)
            data.Instance.Adornee = (CrewEspEnabled and teamOk) and obj or nil
        else
            if data.Instance then data.Instance:Destroy() end
            CrewHighlights[obj] = nil
        end
    end
end

local _connection
local function StartLoop()
    if _connection then return end
    local espT, cleanT = 0, 0
    _connection = RunService.RenderStepped:Connect(function(dt)
        espT   = espT   + dt
        cleanT = cleanT + dt
        if espT   >= VehicleScanInterval then espT = 0   ScanVehicles() end
        if cleanT >= 5                    then cleanT = 0 CleanupESP()   end
        UpdateESP()
    end)
end

function ESP.Init()
    StartLoop()
end

function ESP.SetEnabled(v)
    ESPEnabled = v
    for obj, data in pairs(ESPInstances) do
        local show = v and IsEspTarget(data.ChassisName or "")
        if data.Instance then data.Instance.Adornee = show and obj or nil end
        if data.DistanceBillboard then data.DistanceBillboard.Enabled = show and ShowDistance end
    end
end

function ESP.SetFill(v)
    EnableFill = v
    for _, data in pairs(ESPInstances) do
        if data.Instance then
            data.Instance.FillTransparency = v and FillTransparency or 1
        end
    end
end

function ESP.SetDistance(v)
    ShowDistance = v
    for obj, data in pairs(ESPInstances) do
        if data.DistanceBillboard then
            data.DistanceBillboard.Enabled = ESPEnabled and v and IsEspTarget(data.ChassisName or "")
        end
    end
end

function ESP.SetTeamCheck(v)
    TeamCheck = v
    for obj, data in pairs(ESPInstances) do
        local show = ESPEnabled and IsEspTarget(data.ChassisName or "")
        if data.Instance then data.Instance.Adornee = show and obj or nil end
        if data.DistanceBillboard then data.DistanceBillboard.Enabled = show and ShowDistance end
    end
end

function ESP.SetAmmoEsp(v)
    AmmoEspEnabled = v
    for obj, data in pairs(AmmoHighlights) do
        local teamOk = IsEspTarget(data.ChassisName)
        if data.Instance then data.Instance.Adornee = (v and teamOk) and obj or nil end
    end
end

function ESP.SetCrewEsp(v)
    CrewEspEnabled = v
    for obj, data in pairs(CrewHighlights) do
        local teamOk = IsEspTarget(data.ChassisName)
        if data.Instance then data.Instance.Adornee = (v and teamOk) and obj or nil end
    end
end

return ESP
