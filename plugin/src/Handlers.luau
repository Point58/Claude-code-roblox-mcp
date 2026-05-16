--!strict
-- Tool dispatch table. Each handler returns plain Lua data that the Poller
-- will JSON-encode and send back to the MCP server.

local LogService = game:GetService("LogService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local Selection = game:GetService("Selection")

local PathUtil = require(script.Parent:WaitForChild("PathUtil"))
local PropertyDecode = require(script.Parent:WaitForChild("PropertyDecode"))

local Handlers = {}

-- ----- common helpers ---------------------------------------------------

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
				if ok then
					out[p] = tostring(v)
				end
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
		if ok then
			table.insert(applied, key)
		else
			failed[key] = tostring(err)
		end
	end
	return applied, failed
end

-- ----- inspect -----------------------------------------------------------

local function walk(inst: Instance, depth: number, maxDepth: number, includeProps: boolean): any
	local node: any = {
		name = inst.Name,
		className = inst.ClassName,
	}
	if includeProps then
		node.properties = gatherProps(inst)
	end
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
		if count > 0 then
			node.truncatedChildren = count
		end
	end
	return node
end

function Handlers.inspect(args: any): any
	local root = PathUtil.resolve(args.path or "game")
	if not root then
		error(("path not found: %s"):format(tostring(args.path)))
	end
	local depth = args.maxDepth or 3
	local includeProps = args.includeProperties == true
	return walk(root, 0, depth, includeProps)
end

-- ----- run_code ----------------------------------------------------------

function Handlers.run_code(args: any): any
	local code = args.code
	if typeof(code) ~= "string" then
		error("code must be a string")
	end

	local output: { string } = {}
	local conn = LogService.MessageOut:Connect(function(msg: string, msgType: Enum.MessageType)
		table.insert(output, ("[%s] %s"):format(tostring(msgType.Name), msg))
	end)

	local chunk, compileErr = loadstring(code, "claude_run_code")
	if not chunk then
		conn:Disconnect()
		return {
			ok = false,
			compileError = compileErr,
			output = output,
		}
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

-- ----- read_script -------------------------------------------------------

function Handlers.read_script(args: any): any
	local path = args.path
	if typeof(path) ~= "string" then error("path is required") end
	local target = PathUtil.resolve(path)
	if not target then error(("script not found: %s"):format(path)) end
	if not target:IsA("LuaSourceContainer") then
		error(("target is not a script: %s (%s)"):format(path, target.ClassName))
	end
	local source = (target :: any).Source
	return {
		path = target:GetFullName(),
		className = target.ClassName,
		source = source,
		bytes = #source,
	}
end

-- ----- edit_script -------------------------------------------------------

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

	if recording then
		ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
	end

	return {
		path = target:GetFullName(),
		className = target.ClassName,
		bytes = #source,
	}
end

-- ----- create_instance ---------------------------------------------------

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

	if recording then
		ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
	end

	return {
		path = inst:GetFullName(),
		className = inst.ClassName,
		name = inst.Name,
		applied = applied,
		failed = failed,
	}
end

-- ----- make_gui ----------------------------------------------------------

local function buildNode(node: any): Instance
	local className = node.className or error("missing className in node")
	local inst = Instance.new(className)
	if node.name then
		inst.Name = node.name
	end
	if typeof(node.properties) == "table" then
		for key, raw in pairs(node.properties) do
			local value = PropertyDecode.decode(raw)
			local ok, err = pcall(function()
				(inst :: any)[key] = value
			end)
			if not ok then
				warn(("[ClaudeBridge] make_gui: failed to set %s.%s: %s"):format(className, key, tostring(err)))
			end
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
	if not parent then
		error(("parent not found: %s"):format(parentPath))
	end

	local tree = args.tree
	if typeof(tree) ~= "table" then
		error("tree is required")
	end

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

	if recording then
		ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
	end

	return {
		path = root:GetFullName(),
		className = root.ClassName,
	}
end

-- ----- set_properties ----------------------------------------------------

function Handlers.set_properties(args: any): any
	local target = PathUtil.resolve(args.path or "")
	if not target then error(("not found: %s"):format(tostring(args.path))) end
	if typeof(args.properties) ~= "table" then error("properties table is required") end
	local recording = ChangeHistoryService:TryBeginRecording("ClaudeBridge_SetProperties")
	local applied, failed = applyProperties(target, args.properties)
	if recording then
		ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
	end
	return {
		path = target:GetFullName(),
		applied = applied,
		failed = failed,
	}
end

-- ----- get_properties ----------------------------------------------------

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
	return {
		path = target:GetFullName(),
		properties = out,
	}
end

-- ----- delete ------------------------------------------------------------

function Handlers.delete(args: any): any
	local paths: { string }
	if typeof(args.path) == "string" then
		paths = { args.path }
	elseif typeof(args.path) == "table" then
		paths = args.path
	else
		error("path must be a string or array of strings")
	end

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
	if recording then
		ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
	end
	return { deleted = deleted, notFound = notFound }
end

-- ----- search ------------------------------------------------------------

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
				table.insert(out, {
					name = inst.Name,
					className = inst.ClassName,
					path = inst:GetFullName(),
				})
			end
		end
		if depth >= maxDepth then return end
		for _, child in inst:GetChildren() do
			recurse(child, depth + 1)
			if #out >= maxResults then return end
		end
	end
	recurse(root, 0)
	return {
		count = #out,
		truncated = #out >= maxResults,
		results = out,
	}
end

-- ----- get_selection -----------------------------------------------------

function Handlers.get_selection(args: any): any
	local includeProps = args.includeProperties == true
	local sel = Selection:Get()
	local items: { any } = {}
	for _, inst in sel do
		local node: any = {
			name = inst.Name,
			className = inst.ClassName,
			path = inst:GetFullName(),
		}
		if includeProps then node.properties = gatherProps(inst) end
		table.insert(items, node)
	end
	return { count = #items, items = items }
end

-- ----- select ------------------------------------------------------------

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

-- ----- undo --------------------------------------------------------------

function Handlers.undo(args: any): any
	local count = math.max(1, math.min(args.count or 1, 50))
	local undone = 0
	for _ = 1, count do
		local ok = pcall(function() ChangeHistoryService:Undo() end)
		if ok then undone = undone + 1 else break end
	end
	return { undone = undone, requested = count }
end

return Handlers
