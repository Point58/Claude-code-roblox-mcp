--!strict
-- Tool dispatch table. Each handler returns plain Lua data that the Poller
-- will JSON-encode and send back to the MCP server.

local LogService = game:GetService("LogService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local PathUtil = require(script.Parent:WaitForChild("PathUtil"))
local PropertyDecode = require(script.Parent:WaitForChild("PropertyDecode"))

local Handlers = {}

-- ----- inspect -----------------------------------------------------------

local INTERESTING_PROPS: { [string]: { string } } = {
	BasePart = { "Position", "Size", "Anchored", "Material" },
	Frame = { "Size", "Position", "BackgroundColor3", "BorderSizePixel" },
	TextLabel = { "Text", "TextColor3", "TextSize", "Font" },
	ImageLabel = { "Image", "ImageColor3" },
	Script = { "Disabled", "RunContext" },
	LocalScript = { "Disabled" },
	ModuleScript = {},
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
	-- Give a tick for queued Output messages to flush.
	task.wait(0.05)
	conn:Disconnect()

	local serializedReturn: any
	pcall(function()
		serializedReturn = ret
	end)

	return {
		ok = ok,
		runtimeError = if ok then nil else tostring(ret),
		output = output,
		returnValue = if ok then tostring(serializedReturn) else nil,
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

return Handlers
