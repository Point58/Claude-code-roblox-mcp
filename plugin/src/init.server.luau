--!strict
-- Claude Roblox Bridge — Studio plugin entry point.
-- Polls a local MCP server and dispatches tool requests to handlers.

local HttpService = game:GetService("HttpService")

local Poller = require(script:WaitForChild("Poller"))
local Handlers = require(script:WaitForChild("Handlers"))

local DEFAULT_URL = "http://127.0.0.1:31416"
local SETTING_URL = "ClaudeRobloxBridge_Url"
local SETTING_TOKEN = "ClaudeRobloxBridge_Token"

local function getSetting(key: string, fallback: string): string
	local ok, value = pcall(function()
		return plugin:GetSetting(key)
	end)
	if ok and typeof(value) == "string" and value ~= "" then
		return value
	end
	return fallback
end

local function setSetting(key: string, value: string)
	pcall(function()
		plugin:SetSetting(key, value)
	end)
end

local toolbar = plugin:CreateToolbar("Claude Bridge")
local connectButton = toolbar:CreateButton(
	"Connect",
	"Connect to local Claude MCP server",
	"rbxasset://textures/AnimationEditor/icon_axisX.png"
)
connectButton.ClickableWhenViewportHidden = true

local configButton = toolbar:CreateButton(
	"Config",
	"Set MCP server URL and token",
	"rbxasset://textures/AnimationEditor/icon_filter.png"
)
configButton.ClickableWhenViewportHidden = true

local state = {
	connected = false,
	stop = nil :: (() -> ())?,
}

local function log(msg: string)
	print(("[ClaudeBridge] %s"):format(msg))
end

local function warnf(msg: string)
	warn(("[ClaudeBridge] %s"):format(msg))
end

local function updateButton()
	if state.connected then
		connectButton.Icon = "rbxasset://textures/AnimationEditor/icon_axisY.png"
	else
		connectButton.Icon = "rbxasset://textures/AnimationEditor/icon_axisX.png"
	end
end

local function disconnect()
	if state.stop then
		state.stop()
		state.stop = nil
	end
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
		url = url,
		token = token,
		onRequest = function(req)
			local handler = Handlers[req.tool]
			if not handler then
				return false, ("unknown tool: %s"):format(tostring(req.tool))
			end
			local ok, result = pcall(handler, req.args)
			if not ok then
				return false, tostring(result)
			end
			return true, result
		end,
		log = log,
		warn = warnf,
	})
	state.connected = true
	updateButton()
	log(("connected to %s"):format(url))
end

connectButton.Click:Connect(function()
	if state.connected then
		disconnect()
	else
		connect()
	end
end)

configButton.Click:Connect(function()
	-- Simple flow: prompt via Studio's built-in PromptHelper… there isn't one for plugins.
	-- Use SetSetting via a small ScreenGui in CoreGui for a one-time input.
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
		l.Text = text
		l.BackgroundTransparency = 1
		l.TextColor3 = Color3.fromRGB(220, 220, 220)
		l.Font = Enum.Font.Code
		l.TextSize = 14
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.Size = UDim2.new(1, -20, 0, 20)
		l.Position = UDim2.new(0, 10, 0, y)
		l.Parent = panel
	end

	local function mkInput(default: string, y: number): TextBox
		local b = Instance.new("TextBox")
		b.Text = default
		b.PlaceholderText = ""
		b.ClearTextOnFocus = false
		b.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
		b.TextColor3 = Color3.fromRGB(240, 240, 240)
		b.Font = Enum.Font.Code
		b.TextSize = 14
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
	saveBtn.Font = Enum.Font.SourceSansBold
	saveBtn.TextSize = 16
	saveBtn.BorderSizePixel = 0
	saveBtn.Parent = panel

	local cancelBtn = Instance.new("TextButton")
	cancelBtn.Text = "Cancel"
	cancelBtn.Size = UDim2.new(0, 80, 0, 28)
	cancelBtn.Position = UDim2.new(1, -180, 1, -40)
	cancelBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
	cancelBtn.TextColor3 = Color3.fromRGB(230, 230, 230)
	cancelBtn.Font = Enum.Font.SourceSansBold
	cancelBtn.TextSize = 16
	cancelBtn.BorderSizePixel = 0
	cancelBtn.Parent = panel

	saveBtn.MouseButton1Click:Connect(function()
		setSetting(SETTING_URL, urlBox.Text)
		setSetting(SETTING_TOKEN, tokenBox.Text)
		log("config saved")
		gui:Destroy()
	end)
	cancelBtn.MouseButton1Click:Connect(function()
		gui:Destroy()
	end)
end)

plugin.Unloading:Connect(disconnect)

log("plugin loaded. Click 'Config' first, then 'Connect'.")
