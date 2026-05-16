--!strict
-- Claude Roblox Bridge — single-file Studio plugin.
-- Drop this file into your Roblox Studio Plugins folder.

local HttpService = game:GetService("HttpService")
local LogService = game:GetService("LogService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local Selection = game:GetService("Selection")

local DEFAULT_URL = "http://127.0.0.1:31416"
local SETTING_URL = "ClaudeRobloxBridge_Url"
local SETTING_TOKEN = "ClaudeRobloxBridge_Token"

-- =========================================================================
-- PathUtil
-- =========================================================================
local PathUtil = {}

local function split(path: string): { string }
	local out: { string } = {}
	for part in path:gmatch("[^%.]+") do
		table.insert(out, part)
	end
	return out
end

function PathUtil.resolve(path: string): Instance?
	local parts = split(path)
	if #parts == 0 then return nil end
	local first = parts[1]
	local root: Instance
	if first == "game" or first == "DataModel" then
		root = game
	else
		local svcOk, svc = pcall(function() return game:GetService(first) end)
		if svcOk and svc then
			root = svc
		else
			return nil
		end
	end
	local current: Instance = root
	for i = 2, #parts do
		local child = current:FindFirstChild(parts[i])
		if not child then return nil end
		current = child
	end
	return current
end

function PathUtil.resolveParent(path: string): (Instance?, string?)
	local parts = split(path)
	if #parts < 2 then return nil, nil end
	local last = table.remove(parts, #parts)
	local parentPath = table.concat(parts, ".")
	local parent = PathUtil.resolve(parentPath)
	return parent, last
end

-- =========================================================================
-- PropertyDecode
-- =========================================================================
local PropertyDecode = {}

function PropertyDecode.decode(value: any): any
	if typeof(value) ~= "table" then return value end
	local kind = value.type
	if kind == "UDim2" then
		return UDim2.new(value.scaleX or 0, value.offX or 0, value.scaleY or 0, value.offY or 0)
	elseif kind == "UDim" then
		return UDim.new(value.scale or 0, value.offset or 0)
	elseif kind == "Color3" then
		local r, g, b = value.r or 0, value.g or 0, value.b or 0
		if r > 1 or g > 1 or b > 1 then
			return Color3.fromRGB(r, g, b)
		end
		return Color3.new(r, g, b)
	elseif kind == "Vector2" then
		return Vector2.new(value.x or 0, value.y or 0)
	elseif kind == "Vector3" then
		return Vector3.new(value.x or 0, value.y or 0, value.z or 0)
	elseif kind == "CFrame" then
		local x, y, z = value.x or 0, value.y or 0, value.z or 0
		if typeof(value.angles) == "table" then
			return CFrame.new(x, y, z) * CFrame.Angles(math.rad(value.angles.x or 0), math.rad(value.angles.y or 0), math.rad(value.angles.z or 0))
		end
		if typeof(value.lookAt) == "table" then
			return CFrame.lookAt(Vector3.new(x, y, z), Vector3.new(value.lookAt.x or 0, value.lookAt.y or 0, value.lookAt.z or 0))
		end
		return CFrame.new(x, y, z)
	elseif kind == "NumberRange" then
		local mn = value.min or 0
		return NumberRange.new(mn, value.max or mn)
	elseif kind == "BrickColor" then
		if value.name then return BrickColor.new(value.name) end
		if value.number then return BrickColor.new(value.number) end
		return BrickColor.new(1, 1, 1)
	elseif kind == "Rect" then
		return Rect.new(value.minX or 0, value.minY or 0, value.maxX or 0, value.maxY or 0)
	elseif kind == "Enum" then
		local enumType = (Enum :: any)[value.enumType]
		if enumType then return enumType[value.name] end
		return nil
	end
	return value
end

-- =========================================================================
-- Handlers
-- =========================================================================
local Handlers = {}

local INTERESTING_PROPS: { [string]: { string } } = {
	BasePart = { "Position", "Size", "Anchored", "Material", "CFrame", "Color", "Transparency", "CanCollide" },
	Frame = { "Size", "Position", "BackgroundColor3", "BorderSizePixel", "Visible" },
	TextLabel = { "Text", "TextColor3", "TextSize", "Font", "Visible" },
	TextButton = { "Text", "TextColor3", "TextSize", "Font", "Visible" },
	ImageLabel = { "Image", "ImageColor3", "Visible" },
	ScreenGui = { "Enabled", "ResetOnSpawn", "IgnoreGuiInset" },
	Script = { "Disabled", "RunContext" },
	LocalScript = { "Disabled" },
	ModuleScript = {},
	Sound = { "SoundId", "Volume", "Playing", "Looped" },
	Folder = {},
}

local function gatherProps(inst: Instance): { [string]: any }
	local out: { [string]: any } = {}
	out.Name = inst.Name
	out.ClassName = inst.ClassName
	for class, props in pairs(INTERESTING_PROPS) do
		if inst:IsA(class) then
			for _, p in props do
				local ok, v = pcall(function() return (inst :: any)[p] end)
				if ok then out[p] = tostring(v) end
			end
		end
	end
	return out
end

local function applyProperties(inst: Instance, props: any): ({ string }, { [string]: string })
	local applied: { string } = {}
	local failed: { [string]: string } = {}
	if typeof(props) ~= "table" then return applied, failed end
	for key, raw in pairs(props) do
		local value = PropertyDecode.decode(raw)
		local ok, err = pcall(function() (inst :: any)[key] = value end)
		if ok then table.insert(applied, key)
		else failed[key] = tostring(err) end
	end
	return applied, failed
end

local function walk(inst: Instance, depth: number, maxDepth: number, includeProps: boolean): any
	local node: any = { name = inst.Name, className = inst.ClassName }
	if includeProps then node.properties = gatherProps(inst) end
	if depth < maxDepth then
		local children = inst:GetChildren()
		if #children > 0 then
			node.children = {}
			for _, child in children do
				table.insert(node.children, walk(child, depth + 1, maxDepth, includeProps))
			end
		end
	else
		local count = #inst:GetChildren()
		if count > 0 then node.truncatedChildren = count end
	end
	return node
end

function Handlers.inspect(args: any): any
	local root = PathUtil.resolve(args.path or "game")
	if not root then error(("path not found: %s"):format(tostring(args.path))) end
	return walk(root, 0, args.maxDepth or 3, args.includeProperties == true)
end

function Handlers.run_code(args: any): any
	local code = args.code
	if typeof(code) ~= "string" then error("code must be a string") end
	local output: { string } = {}
	local conn = LogService.MessageOut:Connect(function(msg: string, msgType: Enum.MessageType)
		table.insert(output, ("[%s] %s"):format(tostring(msgType.Name), msg))
	end)
	local chunk, compileErr = loadstring(code, "claude_run_code")
	if not chunk then
		conn:Disconnect()
		return { ok = false, compileError = compileErr, output = output }
	end
	local ok, ret = pcall(chunk)
	task.wait(0.05)
	conn:Disconnect()
	return {
		ok = ok,
		runtimeError = if ok then nil else tostring(ret),
		output = output,
		returnValue = if ok then tostring(ret) else nil,
	}
end

function Handlers.edit_script(args: any): any
	local path = args.path
	local source = args.source
	if typeof(path) ~= "string" or typeof(source) ~= "string" then
		error("path and source are required strings")
	end
	local recording = ChangeHistoryService:TryBeginRecording("ClaudeBridge_EditScript")
	local target = PathUtil.resolve(path)
	if not target and args.createIfMissing then
		local parent, name = PathUtil.resolveParent(path)
		if not parent or not name then
			if recording then ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Cancel) end
			error(("parent path not found for: %s"):format(path))
		end
		local className = args.className or "ModuleScript"
		target = Instance.new(className)
		target.Name = name
		target.Parent = parent
	end
	if not target then
		if recording then ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Cancel) end
		error(("script not found: %s (set createIfMissing=true to create it)"):format(path))
	end
	if not (target:IsA("LuaSourceContainer")) then
		if recording then ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Cancel) end
		error(("target is not a script: %s (%s)"):format(path, target.ClassName))
	end
	(target :: any).Source = source
	if recording then ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit) end
	return { path = target:GetFullName(), className = target.ClassName, bytes = #source }
end

local function buildNode(node: any): Instance
	local className = node.className or error("missing className in node")
	local inst = Instance.new(className)
	if node.name then inst.Name = node.name end
	if typeof(node.properties) == "table" then
		for key, raw in pairs(node.properties) do
			local value = PropertyDecode.decode(raw)
			local ok, err = pcall(function() (inst :: any)[key] = value end)
			if not ok then warn(("[ClaudeBridge] make_gui: failed to set %s.%s: %s"):format(className, key, tostring(err))) end
		end
	end
	if typeof(node.children) == "table" then
		for _, child in ipairs(node.children) do
			local childInst = buildNode(child)
			childInst.Parent = inst
		end
	end
	return inst
end

function Handlers.make_gui(args: any): any
	local parentPath = args.parent or "game.StarterGui"
	local parent = PathUtil.resolve(parentPath)
	if not parent then error(("parent not found: %s"):format(parentPath)) end
	local tree = args.tree
	if typeof(tree) ~= "table" then error("tree is required") end
	local recording = ChangeHistoryService:TryBeginRecording("ClaudeBridge_MakeGui")
	if args.replaceExisting and tree.name then
		local existing = parent:FindFirstChild(tree.name)
		if existing then existing:Destroy() end
	end
	local ok, root = pcall(buildNode, tree)
	if not ok then
		if recording then ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Cancel) end
		error(root)
	end
	root.Parent = parent
	if recording then ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit) end
	return { path = root:GetFullName(), className = root.ClassName }
end

function Handlers.read_script(args: any): any
	local path = args.path
	if typeof(path) ~= "string" then error("path is required") end
	local target = PathUtil.resolve(path)
	if not target then error(("script not found: %s"):format(path)) end
	if not target:IsA("LuaSourceContainer") then
		error(("target is not a script: %s (%s)"):format(path, target.ClassName))
	end
	local source = (target :: any).Source
	return { path = target:GetFullName(), className = target.ClassName, source = source, bytes = #source }
end

function Handlers.create_instance(args: any): any
	local className = args.className
	local parentPath = args.parent
	if typeof(className) ~= "string" then error("className is required") end
	if typeof(parentPath) ~= "string" then error("parent is required") end
	local parent = PathUtil.resolve(parentPath)
	if not parent then error(("parent not found: %s"):format(parentPath)) end
	local recording = ChangeHistoryService:TryBeginRecording("ClaudeBridge_CreateInstance")
	if args.replaceExisting and typeof(args.name) == "string" then
		local existing = parent:FindFirstChild(args.name)
		if existing then existing:Destroy() end
	end
	local ok, instOrErr = pcall(Instance.new, className)
	if not ok then
		if recording then ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Cancel) end
		error(("cannot create %s: %s"):format(className, tostring(instOrErr)))
	end
	local inst = instOrErr :: Instance
	if typeof(args.name) == "string" then inst.Name = args.name end
	local applied, failed = applyProperties(inst, args.properties)
	inst.Parent = parent
	if recording then ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit) end
	return { path = inst:GetFullName(), className = inst.ClassName, name = inst.Name, applied = applied, failed = failed }
end

function Handlers.set_properties(args: any): any
	local target = PathUtil.resolve(args.path or "")
	if not target then error(("not found: %s"):format(tostring(args.path))) end
	if typeof(args.properties) ~= "table" then error("properties table is required") end
	local recording = ChangeHistoryService:TryBeginRecording("ClaudeBridge_SetProperties")
	local applied, failed = applyProperties(target, args.properties)
	if recording then ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit) end
	return { path = target:GetFullName(), applied = applied, failed = failed }
end

function Handlers.get_properties(args: any): any
	local target = PathUtil.resolve(args.path or "")
	if not target then error(("not found: %s"):format(tostring(args.path))) end
	local out: { [string]: any } = {}
	if typeof(args.properties) == "table" and #args.properties > 0 then
		for _, key in args.properties do
			local ok, v = pcall(function() return (target :: any)[key] end)
			if ok then out[key] = tostring(v) end
		end
	else
		out = gatherProps(target)
	end
	return { path = target:GetFullName(), properties = out }
end

function Handlers.delete(args: any): any
	local paths: { string }
	if typeof(args.path) == "string" then paths = { args.path }
	elseif typeof(args.path) == "table" then paths = args.path
	else error("path must be a string or array of strings") end
	local recording = ChangeHistoryService:TryBeginRecording("ClaudeBridge_Delete")
	local deleted: { string } = {}
	local notFound: { string } = {}
	for _, p in paths do
		local target = PathUtil.resolve(p)
		if target and target ~= game then
			table.insert(deleted, target:GetFullName())
			target:Destroy()
		else
			table.insert(notFound, p)
		end
	end
	if recording then ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit) end
	return { deleted = deleted, notFound = notFound }
end

function Handlers.search(args: any): any
	local root = PathUtil.resolve(args.root or "game")
	if not root then error(("root not found: %s"):format(tostring(args.root))) end
	local maxResults = args.maxResults or 100
	local maxDepth = args.maxDepth or 10
	local namePat: string? = if typeof(args.namePattern) == "string" then args.namePattern else nil
	local className: string? = if typeof(args.className) == "string" then args.className else nil
	local out: { any } = {}
	local function recurse(inst: Instance, depth: number)
		if #out >= maxResults then return end
		if depth > 0 then
			local nameOk = (not namePat) or (string.find(inst.Name, namePat :: string) ~= nil)
			local classOk = (not className) or inst:IsA(className :: string) or inst.ClassName == className
			if nameOk and classOk then
				table.insert(out, { name = inst.Name, className = inst.ClassName, path = inst:GetFullName() })
			end
		end
		if depth >= maxDepth then return end
		for _, child in inst:GetChildren() do
			recurse(child, depth + 1)
			if #out >= maxResults then return end
		end
	end
	recurse(root, 0)
	return { count = #out, truncated = #out >= maxResults, results = out }
end

function Handlers.get_selection(args: any): any
	local includeProps = args.includeProperties == true
	local sel = Selection:Get()
	local items: { any } = {}
	for _, inst in sel do
		local node: any = { name = inst.Name, className = inst.ClassName, path = inst:GetFullName() }
		if includeProps then node.properties = gatherProps(inst) end
		table.insert(items, node)
	end
	return { count = #items, items = items }
end

function Handlers.select(args: any): any
	if typeof(args.paths) ~= "table" then error("paths array is required") end
	local items: { Instance } = {}
	local notFound: { string } = {}
	for _, p in args.paths do
		local inst = PathUtil.resolve(p)
		if inst then table.insert(items, inst) else table.insert(notFound, p) end
	end
	if args.add then
		for _, i in Selection:Get() do table.insert(items, i) end
	end
	Selection:Set(items)
	return { selected = #items, notFound = notFound }
end

function Handlers.undo(args: any): any
	local count = math.max(1, math.min(args.count or 1, 50))
	local undone = 0
	for _ = 1, count do
		local ok = pcall(function() ChangeHistoryService:Undo() end)
		if ok then undone = undone + 1 else break end
	end
	return { undone = undone, requested = count }
end

-- =========================================================================
-- Poller
-- =========================================================================
local Poller = {}

type Request = { id: string, tool: string, args: any }
type PollerOptions = {
	url: string,
	token: string,
	onRequest: (Request) -> (boolean, any),
	log: (string) -> (),
	warn: (string) -> (),
}

function Poller.start(opts: PollerOptions): () -> ()
	local running = true

	local function request(method: string, path: string, body: any?): (boolean, any)
		local ok, result = pcall(function()
			return HttpService:RequestAsync({
				Url = opts.url .. path,
				Method = method,
				Headers = {
					["Authorization"] = "Bearer " .. opts.token,
					["Content-Type"] = "application/json",
				},
				Body = if body ~= nil then HttpService:JSONEncode(body) else nil,
			})
		end)
		if not ok then return false, tostring(result) end
		if not result.Success then
			return false, ("HTTP %d: %s"):format(result.StatusCode, tostring(result.Body))
		end
		if result.Body and result.Body ~= "" then
			local decoded
			local ok2, err = pcall(function() decoded = HttpService:JSONDecode(result.Body) end)
			if not ok2 then return false, ("JSON decode failed: %s"):format(tostring(err)) end
			return true, decoded
		end
		return true, nil
	end

	task.spawn(function()
		local backoff = 1
		while running do
			local ok, body = request("GET", "/poll")
			if not ok then
				opts.warn(("poll failed: %s — retrying in %ds"):format(tostring(body), backoff))
				task.wait(backoff)
				backoff = math.min(backoff * 2, 30)
				continue
			end
			backoff = 1
			if typeof(body) ~= "table" or body.idle then continue end
			local req: Request = body :: Request
			local handlerOk, payload = opts.onRequest(req)
			local _, postErr = request("POST", "/result", { id = req.id, ok = handlerOk, data = payload })
			if postErr then opts.warn(("result POST failed: %s"):format(tostring(postErr))) end
		end
	end)

	return function() running = false end
end

-- =========================================================================
-- Plugin entry / UI
-- =========================================================================
local function getSetting(key: string, fallback: string): string
	local ok, value = pcall(function() return plugin:GetSetting(key) end)
	if ok and typeof(value) == "string" and value ~= "" then return value end
	return fallback
end

local function setSetting(key: string, value: string)
	pcall(function() plugin:SetSetting(key, value) end)
end

local function log(msg: string) print(("[ClaudeBridge] %s"):format(msg)) end
local function warnf(msg: string) warn(("[ClaudeBridge] %s"):format(msg)) end

local toolbar = plugin:CreateToolbar("Claude Bridge")
local connectButton = toolbar:CreateButton(
	"Connect",
	"Connect to local Claude MCP server",
	"rbxasset://textures/AnimationEditor/icon_axisX.png"
)
local configButton = toolbar:CreateButton(
	"Config",
	"Set MCP server URL and token",
	"rbxasset://textures/AnimationEditor/icon_filter.png"
)

local state = { connected = false, stop = nil :: (() -> ())? }

local function updateButton()
	if state.connected then
		connectButton.Icon = "rbxasset://textures/AnimationEditor/icon_axisY.png"
	else
		connectButton.Icon = "rbxasset://textures/AnimationEditor/icon_axisX.png"
	end
end

local function disconnect()
	if state.stop then state.stop(); state.stop = nil end
	state.connected = false
	updateButton()
	log("disconnected")
end

local function connect()
	local url = getSetting(SETTING_URL, DEFAULT_URL)
	local token = getSetting(SETTING_TOKEN, "")
	if token == "" then
		warnf("No token configured. Click 'Config' to set CLAUDE_ROBLOX_TOKEN.")
		return
	end
	state.stop = Poller.start({
		url = url, token = token,
		onRequest = function(req)
			local handler = Handlers[req.tool]
			if not handler then return false, ("unknown tool: %s"):format(tostring(req.tool)) end
			local ok, result = pcall(handler, req.args)
			if not ok then return false, tostring(result) end
			return true, result
		end,
		log = log, warn = warnf,
	})
	state.connected = true
	updateButton()
	log(("connected to %s"):format(url))
end

connectButton.Click:Connect(function()
	if state.connected then disconnect() else connect() end
end)

configButton.Click:Connect(function()
	local CoreGui = game:GetService("CoreGui")
	local existing = CoreGui:FindFirstChild("ClaudeBridgeConfig")
	if existing then existing:Destroy() end

	local gui = Instance.new("ScreenGui")
	gui.Name = "ClaudeBridgeConfig"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = CoreGui

	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0, 380, 0, 200)
	panel.Position = UDim2.new(0.5, -190, 0.5, -100)
	panel.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
	panel.BorderSizePixel = 0
	panel.Parent = gui

	local function mkLabel(text: string, y: number)
		local l = Instance.new("TextLabel")
		l.Text = text; l.BackgroundTransparency = 1
		l.TextColor3 = Color3.fromRGB(220, 220, 220)
		l.Font = Enum.Font.Code; l.TextSize = 14
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.Size = UDim2.new(1, -20, 0, 20)
		l.Position = UDim2.new(0, 10, 0, y)
		l.Parent = panel
	end

	local function mkInput(default: string, y: number): TextBox
		local b = Instance.new("TextBox")
		b.Text = default; b.ClearTextOnFocus = false
		b.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
		b.TextColor3 = Color3.fromRGB(240, 240, 240)
		b.Font = Enum.Font.Code; b.TextSize = 14
		b.TextXAlignment = Enum.TextXAlignment.Left
		b.Size = UDim2.new(1, -20, 0, 28)
		b.Position = UDim2.new(0, 10, 0, y)
		b.BorderSizePixel = 0
		b.Parent = panel
		return b
	end

	mkLabel("MCP server URL:", 10)
	local urlBox = mkInput(getSetting(SETTING_URL, DEFAULT_URL), 30)
	mkLabel("Token (CLAUDE_ROBLOX_TOKEN):", 65)
	local tokenBox = mkInput(getSetting(SETTING_TOKEN, ""), 85)

	local saveBtn = Instance.new("TextButton")
	saveBtn.Text = "Save"
	saveBtn.Size = UDim2.new(0, 80, 0, 28)
	saveBtn.Position = UDim2.new(1, -90, 1, -40)
	saveBtn.BackgroundColor3 = Color3.fromRGB(60, 120, 200)
	saveBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	saveBtn.Font = Enum.Font.SourceSansBold; saveBtn.TextSize = 16
	saveBtn.BorderSizePixel = 0
	saveBtn.Parent = panel

	local cancelBtn = Instance.new("TextButton")
	cancelBtn.Text = "Cancel"
	cancelBtn.Size = UDim2.new(0, 80, 0, 28)
	cancelBtn.Position = UDim2.new(1, -180, 1, -40)
	cancelBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
	cancelBtn.TextColor3 = Color3.fromRGB(230, 230, 230)
	cancelBtn.Font = Enum.Font.SourceSansBold; cancelBtn.TextSize = 16
	cancelBtn.BorderSizePixel = 0
	cancelBtn.Parent = panel

	saveBtn.MouseButton1Click:Connect(function()
		setSetting(SETTING_URL, urlBox.Text)
		setSetting(SETTING_TOKEN, tokenBox.Text)
		log("config saved")
		gui:Destroy()
	end)
	cancelBtn.MouseButton1Click:Connect(function() gui:Destroy() end)
end)

plugin.Unloading:Connect(disconnect)
log("plugin loaded. Click 'Config' first, then 'Connect'.")
