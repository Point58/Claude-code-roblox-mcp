--!strict
-- Long-poll loop. Calls GET /poll, dispatches a request, POSTs the result, repeats.

local HttpService = game:GetService("HttpService")

export type Request = {
	id: string,
	tool: string,
	args: any,
}

export type Options = {
	url: string,
	token: string,
	onRequest: (Request) -> (boolean, any),
	log: (string) -> (),
	warn: (string) -> (),
}

local Poller = {}

function Poller.start(opts: Options): () -> ()
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
		if not ok then
			return false, tostring(result)
		end
		if not result.Success then
			return false, ("HTTP %d: %s"):format(result.StatusCode, tostring(result.Body))
		end
		local body = result.Body
		if body and body ~= "" then
			local decoded
			local ok2, err = pcall(function()
				decoded = HttpService:JSONDecode(body)
			end)
			if not ok2 then
				return false, ("JSON decode failed: %s"):format(tostring(err))
			end
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

			if typeof(body) ~= "table" or body.idle then
				continue
			end

			local req: Request = body :: Request
			local handlerOk, payload = opts.onRequest(req)
			local resultBody = {
				id = req.id,
				ok = handlerOk,
				data = payload,
			}
			local postOk, postErr = request("POST", "/result", resultBody)
			if not postOk then
				opts.warn(("result POST failed: %s"):format(tostring(postErr)))
			end
		end
	end)

	return function()
		running = false
	end
end

return Poller
