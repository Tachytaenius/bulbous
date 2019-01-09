local metadata = {
	name = "Bulbous",
	description = "A simple lighting library.",
	version = "0.1.0",
	author = "Tachytaenius",
	license = [[
		MIT License
		
		Copyright (c) 2018 Henry Fleminger Thomson
		
		Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
		
		The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

		THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
	]]
}

local shader = love.graphics.newShader([[
	extern vec4 info; // draw x, draw y, fov, angle
	extern Image viewLocations;
	extern Image occluders;
	extern bool lamp; // or view
	extern bool penetrationDampening; // lamps dont penetrate if the view is on the other side of an occluder?
	extern vec2 size; // of the canvas, in pixels
	extern number viewCount;
	extern number basePenetrationThreshold;
	const number tau = 6.28318530717958647692;
	vec4 effect(vec4 colour, Image texture, vec2 textureCoords, vec2 windowCoords) {
		textureCoords = textureCoords * 2 - 1;
		number intensity = 1 - length(textureCoords);
		if (intensity <= 0) {
			return vec4(0, 0, 0, 1);
		}
		if (!lamp) {
			intensity = ceil(intensity);
		}
		
		vec2 path = windowCoords - info.xy;
		vec2 direction = normalize(path);
		number angle = atan(direction.x, direction.y);
		number signedAngle = mod(angle + info[3], tau) - tau / 2;
		if (abs(signedAngle) <= info[2] / 2) {
			number len = length(path);
			number penetrationThreshold = basePenetrationThreshold;
			if (lamp && penetrationDampening) {
				number length = viewCount;
				if (floor(viewCount / 2) != viewCount / 2) {
					length += 1;
				}
				number best = 0;
				for (int i = 0; i < viewCount; ++i) {
					vec2 eyeLocation;
					vec4 texel = Texel(viewLocations, vec2(floor(i / length / 2), 0));
					if (floor(float(i) / 2) == i / 2) {
						eyeLocation = texel.rg;
					} else {
						eyeLocation = texel.ba;
					}
					vec2 eyeVector = windowCoords - eyeLocation * size;
					number eyeAngle = atan(eyeVector.x, eyeVector.y);
					number angleCloseness = 1 - abs(mod(angle - eyeAngle + tau / 2, tau) - tau / 2) / (tau / 2);
					best = max(best, angleCloseness);
				}
				penetrationThreshold *= best;
			}
			vec3 alpha = vec3(0);
			vec3 last = vec3(1);
			vec3 downwards = vec3(0);
			vec3 colour2 = vec3(1);
			vec3 penetration = vec3(0);
			for (int i = 0; i < len; ++i) {
				vec2 location = info.xy + direction * i;
				vec3 through = Texel(occluders, location / size).rgb;
				colour2 = min(colour2, through);
				downwards += max(last - through, 0);
				vec3 currentUpwards = max(through - last, 0);
				last = through;
				penetration += basePenetrationThreshold * currentUpwards + downwards;
			}
			if (penetration.r > penetrationThreshold) {
				colour.r *= colour2.r;
			}
			if (penetration.g > penetrationThreshold) {
				colour.g *= colour2.g;
			}
			if (penetration.b > penetrationThreshold) {
				colour.b *= colour2.b;
			}
			return colour * intensity;
		} else {
			return vec4(0);
		}
	}
]])

local null = love.graphics.newImage(love.image.newImageData(1, 1))
local tau = math.tau or math.pi * 2
local sqrt = math.sqrt
local vec = {}
local setColour, draw, setPointSize, points, setShader, setBlendMode, setCanvas = love.graphics.setColor, love.graphics.draw, love.graphics.setPointSize, love.graphics.points, love.graphics.setShader, love.graphics.setBlendMode, love.graphics.setCanvas

local function emit(x, y, radius, r, g, b, fov, angle)
	r, g, b = r or 1, g or 1, b or 1
	fov, angle = fov or tau, angle or 0
	setColour(r, g, b)
	vec[1], vec[2], vec[3], vec[4] = x, y, fov, angle
	shader:send("info", vec)
	draw(null, x - radius, y - radius, 0, radius * 2)
end

--[[Parameters:
the occluder canvas should be a canvas with the "background colour" 1, 1, 1, 1 and have "occluders" (light filters) of colours r, g, b, 1.

basePenetrationThreshold defines how far into an occluder light may go before succumbing to the influence of the occluder. This is useful in games where you want to see a texture underneath the occluder for a certain distance (nil for zero)

lights is a list (or nil to not draw any lights) where each value is a table of emission info:
	x and y coordinates for the draw location, a radius for the size, r, g and b for the colour, fov-- an angle in radians expressing how wide the influence of the emission is and just "angle", another radians angle describing where the centre of the field of view is. it would not have any effect if fov were set to tau

the light canvas is a canvas (normally cleared to a uniform base light level (daylight!!)), the same size as the occluder canvas. it has lights drawn onto it (not needed if there are no lights)
set to nil to draw no views, the views is a list of emissions that represent the views that can see the light
not needed without views, the view canvas is where view emissions are drawn. normally you would multiply the light canvas by it to get the final canvas
penetrationDampening is a boolean that defines whether light emissions can penetrate through an occluder if the eyeLocation is on the other side. it looks good, so it's recommended to turn it on.
]]

local viewInfoCanvas = love.graphics.newCanvas(1, 1)

local function getMaxViews()
	return viewInfoCanvas:getWidth()
end

local function setMaxViews(x)
	viewInfoCanvas = love.graphics.newCanvas(x, 1)
end

-- Your graphics state is not backed up for performance reasons.
local function drawEmissions(occluderCanvas, basePenetrationThreshold, lights, lightCanvas, views, viewCanvas, disablePenetrationDampening)
	love.graphics.push("all")
	
	-- assert uniform canvas dimensions
	local w, h = occluderCanvas:getDimensions()
	if lights then
		local w2, h2 = lightCanvas:getDimensions()
		assert(w == w2 and h == h2, "All the canvasses must have the same dimensions.")
	end
	if views then
		local w2, h2 = viewCanvas:getDimensions()
		assert(w == w2 and h == h2, "All the canvasses must have the same dimensions.")
	end
	
	setShader(nil)
	
	if views and not disablePenetrationDampening then
		if getMaxViews() < #views then
			setMaxViews(length)
		end
		setCanvas(viewInfoCanvas)
		setPointSize(1)
		for i = 1, #views, 2 do
			local view1 = views[i]
			local view2 = views[i+1]
			setColour(view1.x / w, view1.y / h, view2 and view2.x / h or 0, view2 and view2.y / h or 0)
			points(i - 1, 0)
		end
		shader:send("viewLocations", viewInfoCanvas)
		shader:send("viewCount", #views)
	end
	
	setShader(shader)
	
	-- set some externs
	vec[1], vec[2] = w, h
	shader:send("size", vec)
	shader:send("occluders", occluderCanvas)
	shader:send("basePenetrationThreshold", basePenetrationThreshold or 0)
	shader:send("penetrationDampening", not disablePenetrationDampening and views and #views > 0)
	
	-- emissions combine
	setBlendMode("add", "alphamultiply")
	
	-- emit views
	if views then
		setCanvas(viewCanvas)
		shader:send("lamp", false)
		for _, view in ipairs(views) do
			emit(view.x, view.y, view.radius, view.r, view.g, view.b, view.fov, view.angle)
		end
		local length = #views
	end
	
	-- emit lights
	if lights then
		setCanvas(lightCanvas)
		shader:send("lamp", true)
		for _, light in ipairs(lights) do
			emit(light.x, light.y, light.radius, light.r, light.g, light.b, light.fov, light.angle)
		end
	end
	
	love.graphics.pop()
end

return {
	metadata = metadata,
	
	emit = emit,
	drawEmissions = drawEmissions,
	getMaxViews = getMaxViews,
	setMaxViews = setMaxViews
}
