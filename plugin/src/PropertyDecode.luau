--!strict
-- Decode JSON-friendly typed values into Roblox datatypes.
-- Supports primitives plus {type="UDim2"|"UDim"|"Color3"|"Vector2"|"Vector3"
-- |"CFrame"|"NumberRange"|"BrickColor"|"Rect"|"Enum", ...}

local PropertyDecode = {}

function PropertyDecode.decode(value: any): any
	if typeof(value) ~= "table" then
		return value
	end
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
			local ax = math.rad(value.angles.x or 0)
			local ay = math.rad(value.angles.y or 0)
			local az = math.rad(value.angles.z or 0)
			return CFrame.new(x, y, z) * CFrame.Angles(ax, ay, az)
		end
		if typeof(value.lookAt) == "table" then
			return CFrame.lookAt(
				Vector3.new(x, y, z),
				Vector3.new(value.lookAt.x or 0, value.lookAt.y or 0, value.lookAt.z or 0)
			)
		end
		return CFrame.new(x, y, z)
	elseif kind == "NumberRange" then
		local mn = value.min or 0
		local mx = value.max or mn
		return NumberRange.new(mn, mx)
	elseif kind == "BrickColor" then
		if value.name then return BrickColor.new(value.name) end
		if value.number then return BrickColor.new(value.number) end
		return BrickColor.new(1, 1, 1)
	elseif kind == "Rect" then
		return Rect.new(value.minX or 0, value.minY or 0, value.maxX or 0, value.maxY or 0)
	elseif kind == "Enum" then
		local enumType = (Enum :: any)[value.enumType]
		if enumType then
			return enumType[value.name]
		end
		return nil
	end
	return value
end

return PropertyDecode
