--!strict
-- Decode JSON-friendly typed values into Roblox datatypes.
-- Supports primitives plus {type="UDim2"|"UDim"|"Color3"|"Vector2"|"Vector3"|"Enum", ...}

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
