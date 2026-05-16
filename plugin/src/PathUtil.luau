--!strict
-- Resolve "game.X.Y.Z" style paths against the DataModel.

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
		local svcOk, svc = pcall(function()
			return game:GetService(first)
		end)
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

-- Resolve parent and return (parent, finalName). For "game.X.Y" returns (X, "Y").
function PathUtil.resolveParent(path: string): (Instance?, string?)
	local parts = split(path)
	if #parts < 2 then return nil, nil end
	local last = table.remove(parts, #parts)
	local parentPath = table.concat(parts, ".")
	local parent = PathUtil.resolve(parentPath)
	return parent, last
end

function PathUtil.fullName(inst: Instance): string
	return inst:GetFullName()
end

return PathUtil
