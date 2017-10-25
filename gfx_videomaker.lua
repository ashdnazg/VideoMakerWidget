function widget:GetInfo()
	return {
		name      = "Video Maker",
		desc      = "Plops lots of images and shit",
		author    = "ashdnazg",
		date      = "18 Nov 2016",
		license   = "GNU GPL, v2 or later",
		layer     = 99999999,
		enabled   = true,
	}
end

--Constants

local GAME_SPEED = 30
-------------------------------------
-------------- CHILI ----------------
-------------------------------------

local COLOR_REGULAR     = {1,1,1, 1}
local COLOR_SELECTED = {0.8, 0, 0, 1}

-----------------------
-- Control window
-----------------------
local keyFrameButton
local loadFrameButton
local newShotButton
local deleteButton
local playButton
local recordButton
local controlWindow
local shotsTree
local shotsScroll
local loadButton
local saveButton
local playReplayButton
local recordReplayButton

-----------------------
-- Timeline window
-----------------------
local timeline
local timelineWindow
local prevFrameButton
local prevSecButton
local nextFrameButton
local nextSecButton
local timelineLabel

-------------------------------------
-------------- /CHILI ---------------
-------------------------------------

local CAPTURES_DIR = "captures"
local SAVED_SHOTS_DIR = "cache"

-----------------------
-- Timeline Vars
-----------------------
local timelineHoverFrame = -1
local timelineFrame = 0
local maxFrame = 2000
-----------------------
-- /Timeline Vars
-----------------------

local gameID

-----------------------
-- Control Vars
-----------------------

local numShots = 0
local nodeToShot = {}
local nodeToKeyFrame = {}
local shots = {} -- {shotNum = { frame = camState }}
local shotSortedKeyFrames = {}
local playedShot
local playedFrame
local recording = false
local vsx, vsy

local recordQueue = {}
local isReplay = Spring.IsReplay()

-----------------------
-- /Util funcs
-----------------------

function UnlinkSafe(link)
	local link = link
	while (type(link) == "userdata") do
		link = link()
	end
	return link
end

local function ClampFrame(f)
	f = math.min(maxFrame, f)
	f = math.max(0, f)
	return f
end

local function FrameToTime(f)
	f = ClampFrame(f)
	local seconds, frame = math.modf(f/GAME_SPEED)
	local minute, second = math.modf(seconds/60)
	frame = frame * GAME_SPEED
	second = 60 * second
	return string.format ("%d:%02d::%02d" , minute, second, frame)
end

local function InterpRotation(ratio, ratio2, rot1, rot2)
	if math.max(rot1, rot2) - math.min(rot1, rot2) > math.pi then
		if rot1 > rot2 then
			rot2 = rot2 + 2 * math.pi
		else
			rot1 = rot1 + 2 * math.pi
		end
	end
	return rot1 * ratio + rot2 * ratio2
end

local function GetInterpolatedCameraState(ratio, state1, state2)
	local interpState = {}
	for k,v in pairs(state1) do
		interpState[k] = v
	end
	local ratio2 = 1 - ratio
	interpState.px  = state1.px  * ratio2 + state2.px  * ratio
	interpState.py  = state1.py  * ratio2 + state2.py  * ratio
	interpState.pz  = state1.pz  * ratio2 + state2.pz  * ratio
	interpState.fov = state1.fov * ratio2 + state2.fov * ratio

	local rxz1 = math.atan2(state1.dx, state1.dz)
	local rxz2 = math.atan2(state2.dx, state2.dz)
	local ry1 = math.acos(state1.dy)
	local ry2 = math.acos(state2.dy)

	local ry = InterpRotation(ratio2, ratio, ry1, ry2)
	local rxz = InterpRotation(ratio2, ratio, rxz1, rxz2)

	interpState.dy = math.cos(ry)

	interpState.dx = math.sin(rxz) * math.sin(ry)
	interpState.dz = math.cos(rxz) * math.sin(ry)

	return interpState
end

local function GetFilename()
	return (Game.gameID or "game1") .. ".lua"
end

-----------------------
-- /Util Funcs
-----------------------

-----------------------
-- Timeline Funcs
-----------------------

local function ChangeTimelineFrame(newFrame)
	newFrame = ClampFrame(newFrame)
	timelineFrame = newFrame
	timeline:SetValue(newFrame)
	local t = FrameToTime(newFrame)
	timeline:SetCaption(t)
end

-----------------------
-- /Timeline Funcs
-----------------------

-----------------------
-- Control Funcs
-----------------------

local function GetSelectedNode()
	local selected = shotsTree.selected
	if not selected then
		return nil
	end
	local node = UnlinkSafe(selected)
	if not node then
		return nil
	end
	return node
end

local function NewShot()
	numShots = numShots + 1
	local newNode = shotsTree.root:Add("Shot " .. numShots)
	newNode = UnlinkSafe(newNode)
	nodeToShot[newNode] = numShots
	shots[numShots] = {}
	shotSortedKeyFrames[numShots] = {}
	shotsTree.selected = false
	shotsTree:Select(newNode)
end

local function DeleteShot(shot)
	shots[shot] = nil
end

local function RegenerateSortedKeyFrames(shot)
	local tempTable = {}
	for frame, _ in pairs(shots[shot]) do
		table.insert(tempTable, frame)
	end

	table.sort(tempTable)
	shotSortedKeyFrames[shot] = tempTable
end


local function DeleteKeyFrame(shot, keyFrame)
	shots[shot][keyFrame] = nil
	RegenerateSortedKeyFrames(shot)
end

local function SetKeyFrame()
	local node = GetSelectedNode()
	if not node then
		return
	end
	if nodeToKeyFrame[node] then
		node = UnlinkSafe(node.parent)
	end
	if nodeToShot[node] then
		local parentShot = nodeToShot[node]
		if not shots[parentShot][timelineFrame] then
			shots[parentShot][timelineFrame] = Spring.GetCameraState()

			node:ClearChildren()
			RegenerateSortedKeyFrames(parentShot)

			local addedNode

			for _, frame in pairs(shotSortedKeyFrames[parentShot]) do
				local newNode = node:Add(FrameToTime(frame))
				newNode = UnlinkSafe(newNode)
				nodeToKeyFrame[newNode] = frame
				if frame == timelineFrame then
					addedNode = newNode
				end
			end
			shotsTree.selected = false
			shotsTree:Select(addedNode)
		else
			shots[parentShot][timelineFrame] = Spring.GetCameraState()
		end
	end
end

local function GetFrame()
	local node = GetSelectedNode()
	if not node then
		return
	end
	if not nodeToKeyFrame[node] then
		return
	end
	local keyFrame = nodeToKeyFrame[node]
	local parentShot = nodeToShot[UnlinkSafe(node.parent)]
	Spring.SetCameraState(shots[parentShot][keyFrame])
end


local function DeleteNode()
	local node = GetSelectedNode()
	if not node then
		return
	end
	if nodeToShot[node] then
		local deletedShot = nodeToShot[node]
		node:Dispose()
		shotsTree.selected = false
		nodeToShot[node] = nil
		DeleteShot(deletedShot)
	end
	if nodeToKeyFrame[node] then
		local deletedKeyFrame = nodeToKeyFrame[node]
		local parentShot = nodeToShot[UnlinkSafe(node.parent)]
		node:Dispose()
		shotsTree.selected = false
		shotsTree:Select(parentShot)
		nodeToKeyFrame[node] = nil
		DeleteKeyFrame(parentShot, deletedKeyFrame)
	end
end


local function QueueShot(shotNum, offset, record)
	local numKeyFrames = #shotSortedKeyFrames[shotNum]
	if numKeyFrames < 2 then
		Spring.Echo("A shot must have a start and an end")
		return
	end
	for kf = shotSortedKeyFrames[shotNum][1],shotSortedKeyFrames[shotNum][numKeyFrames] do
		local frame = offset + kf - shotSortedKeyFrames[shotNum][1]
		-- shouldn't happen, but for safety
		if not recordQueue[frame] then
			recordQueue[frame] = {}
		end
		table.insert(recordQueue[frame], {shotNum, kf, record})
	end
end

local function QueueCurrentShot(offset, record)
	local node = GetSelectedNode()
	if not node then
		return
	end
	local keyFrame = nodeToKeyFrame[node]
	if keyFrame then
		node = UnlinkSafe(node.parent)
	end
	local shotNum = nodeToShot[node]
	if not shotNum then
		return
	end
	QueueShot(shotNum, offset, record)
end

local function QueueAllShots(offset, record)
	for i, _ in pairs(shots) do
		QueueShot(i, offset, record)
	end
end


-----------------------
-- /Control Funcs
-----------------------


-----------------------
-- Serialization Funcs
-----------------------

local function SaveShots()
	local t = {
		numShots = numShots,
		shots = shots,
		shotSortedKeyFrames = shotSortedKeyFrames
	}
	table.save(t, SAVED_SHOTS_DIR .. "/" .. GetFilename())
end

local function LoadShots()
	local t = VFS.Include(SAVED_SHOTS_DIR .. "/" .. GetFilename())
	shots = t.shots
	shotSortedKeyFrames = t.shotSortedKeyFrames
	numShots = t.numShots

	nodeToShot = {}
	nodeToKeyFrame = {}
	shotsTree.root:ClearChildren()

	-- create shot nodes
	for i, _ in pairs(shots) do
		local newNode = shotsTree.root:Add("Shot " .. i)
		newNode = UnlinkSafe(newNode)
		nodeToShot[newNode] = i
		RegenerateSortedKeyFrames(i)

		-- create frame nodes
		for _, frame in pairs(shotSortedKeyFrames[i]) do
			local subnode = newNode:Add(FrameToTime(frame))
			subnode = UnlinkSafe(subnode)
			nodeToKeyFrame[subnode] = frame
		end

		if i == 1 then
			shotsTree:Select(newNode)
		end
	end
end
-----------------------
-- /Serialization Funcs
-----------------------


-----------------------
-- Callins && Crap
-----------------------

local function InitGUI()
	local Chili = WG.Chili
	local currentY = 10

	keyFrameButton = Chili.Button:New{
		y = currentY,
		x = 0,
		width = 100,
		caption = "Set KeyFrame",
		OnClick = {
			function(self)
				SetKeyFrame()
			end
		}
	}

	loadFrameButton = Chili.Button:New{
		y = currentY,
		x = 110,
		width = 100,
		caption = "Get Frame",
		OnClick = {
			function(self)
				GetFrame()
			end
		}
	}
	currentY = currentY + 20

	newShotButton = Chili.Button:New{
		y = currentY,
		x = 0,
		width = 100,
		caption = "New Shot",
		OnClick = {
			function(self)
				NewShot()
			end
		}
	}

	deleteButton = Chili.Button:New{
		y = currentY,
		x = 110,
		width = 100,
		caption = "Delete",
		OnClick = {
			function(self)
				DeleteNode()
			end
		}
	}
	currentY = currentY + 20

	playButton = Chili.Button:New{
		y = currentY,
		x = 0,
		width = 100,
		caption = "Play Shot",
		OnClick = {
			function(self)
				QueueCurrentShot(Spring.GetGameFrame() + 1, false)
			end
		}
	}

	recordButton = Chili.Button:New{
		y = currentY,
		x = 110,
		width = 100,
		caption = "Record Shot",
		OnClick = {
			function(self)
				QueueCurrentShot(Spring.GetGameFrame() + 1, true)
			end
		}
	}
	currentY = currentY + 20

	playReplayButton = Chili.Button:New{
		y = currentY,
		x = 0,
		width = 100,
		caption = "Play Replay",
		OnClick = {
			function(self)
				if not isReplay then
					Spring.Echo("Not playing a replay!")
					return
				end
				QueueAllShots(0, false)
			end
		}
	}

	recordReplayButton = Chili.Button:New{
		y = currentY,
		x = 110,
		width = 100,
		caption = "Record Replay",
		OnClick = {
			function(self)
				if not isReplay then
					Spring.Echo("Not playing a replay!")
					return
				end
				QueueAllShots(0, true)
			end
		}
	}
	currentY = currentY + 20

	shotsTree = Chili.TreeView:New{
		y = 0,
		x = 0,
		right = 0,
		bottom = 0,
		defaultExpanded = true,
		nodes = {
		},
	}

	shotsScroll = Chili.ScrollPanel:New{
		y = currentY,
		x = 0,
		right = 0,
		bottom = 20,
		children = {
			shotsTree
		},
	}

	saveButton = Chili.Button:New{
		bottom = 0,
		x = 0,
		width = 100,
		caption = "Save Shots",
		OnClick = {
			function(self)
				SaveShots()
			end
		}
	}

	loadButton = Chili.Button:New{
		bottom = 0,
		x = 110,
		width = 100,
		caption = "Load Shots",
		OnClick = {
			function(self)
				LoadShots()
			end
		}
	}

	controlWindow = Chili.Window:New{
		caption = "Controls",
		y = "50%",
		right = 10,
		width  = 240,
		height = "40%",
		parent = Chili.Screen0,
		--autosize = true,
		--savespace = true,
		children = {
			keyFrameButton,
			loadFrameButton,
			newShotButton,
			deleteButton,
			playButton,
			recordButton,
			playReplayButton,
			recordReplayButton,
			shotsScroll,
			saveButton,
			loadButton
		},
	}


	prevSecButton = Chili.Button:New{
		caption = "<<",
		y = 20,
		x = 0,
		width = 15,
		OnMouseOver = {
			function(self)
				timelineLabel:SetCaption("-1 Second")
			end
		},
		OnMouseOut = {
			function(self)
				timelineLabel:SetCaption("")
			end
		},
		OnClick = {
			function(self)
				ChangeTimelineFrame(timelineFrame - GAME_SPEED)
			end
		}
	}

	prevFrameButton = Chili.Button:New{
		caption = "<",
		y = 20,
		x = 20,
		width = 15,
		OnMouseOver = {
			function(self)
				timelineLabel:SetCaption("-1 Frame")
			end
		},
		OnMouseOut = {
			function(self)
				timelineLabel:SetCaption("")
			end
		},
		OnClick = {
			function(self)
				ChangeTimelineFrame(timelineFrame - 1)
			end
		}
	}

	nextFrameButton = Chili.Button:New{
		caption = ">",
		y = 20,
		width = 15,
		right = 20,
		OnMouseOver = {
			function(self)
				timelineLabel:SetCaption("+1 Frame")
			end
		},
		OnMouseOut = {
			function(self)
				timelineLabel:SetCaption("")
			end
		},
		OnClick = {
			function(self)
				ChangeTimelineFrame(timelineFrame + 1)
			end
		}
	}

	nextSecButton = Chili.Button:New{
		caption = ">>",
		y = 20,
		width = 15,
		right = 0,
		OnMouseOver = {
			function(self)
				timelineLabel:SetCaption("+1 Second")
			end
		},
		OnMouseOut = {
			function(self)
				timelineLabel:SetCaption("")
			end
		},
		OnClick = {
			function(self)
				ChangeTimelineFrame(timelineFrame + GAME_SPEED)
			end
		}
	}
	timelineLabel = Chili.Label:New{
		caption = "",
		y = 40,
		x = "45%",
	}

	timeline = Chili.Progressbar:New{
		x = 40,
		y = 20,
		height = 20,
		--width = "90%",
		right = 40,
		value = 0,
		max = 2000,
		OnMouseDown = {
			function(self)
				ChangeTimelineFrame(timelineHoverFrame)
				return true
			end
		},
		-- OnMouseOver = {
			-- function(self)
				-- timelineLabel:SetCaption("bla")
			-- end
		-- },
		OnMouseOut = {
			function(self)
				timelineLabel:SetCaption("")
			end
		},
		OnMouseMove = {
			function(self, x, y, dx, dy, button)
				local target = x / (self.width - 12)
				timelineHoverFrame = math.floor(target * self.max)
				local t = FrameToTime(timelineHoverFrame)
				timelineLabel:SetCaption("Goto: " .. t)
				if (button == 1) then
					ChangeTimelineFrame(timelineHoverFrame)
				end
			end
		},
		HitTest = function(self,x,y)
			return self
		end
	}
	timelineWindow = Chili.Window:New{
		caption = "TimeLine",
		y = "90%",
		right = 10,
		width  = "50%",
		height = 120,
		parent = Chili.Screen0,
		children = {
			prevSecButton,
			prevFrameButton,
			nextFrameButton,
			nextSecButton,
			timelineLabel,
			timeline,
		},
	}
	NewShot()
end

--------------
--  CALLINS --
--------------

local gameFrame

local function RecordFrame()
	if recording then
		gl.SaveImage(0,0,vsx,vsy,string.format(CAPTURES_DIR .. "/capture_%06d_%06d.png", playedShot, playedFrame));
	end
	return true
end


local function SetupCamera()
	local keyFrames = shots[playedShot]
	local sortedKeyFrames = shotSortedKeyFrames[playedShot]
	local prevKeyFrame
	local nextKeyFrame
	for _, keyFrame in pairs(sortedKeyFrames) do
		nextKeyFrame = keyFrame

		if playedFrame < keyFrame then
			break
		end

		prevKeyFrame = keyFrame
	end


	-- will also happen on last keyframe
	if playedFrame == prevKeyFrame then
		Spring.SetCameraState(keyFrames[playedFrame])
	else
		local ratio = (playedFrame - prevKeyFrame) / (nextKeyFrame - prevKeyFrame)
		Spring.SetCameraState(GetInterpolatedCameraState(ratio, keyFrames[prevKeyFrame], keyFrames[nextKeyFrame]))
	end
end


local function PopFromQueue()
	local currentQueue = recordQueue[gameFrame]
	if not currentQueue or #currentQueue == 0 then
		return false
	end
	playedShot, playedFrame, recording = currentQueue[#currentQueue][1], currentQueue[#currentQueue][2], currentQueue[#currentQueue][3]
	currentQueue[#currentQueue] = nil
	return true
end


function widget:GameFrame()
	gameFrame = Spring.GetGameFrame()
	if isReplay then
		ChangeTimelineFrame(gameFrame)
	end
	recordQueue[gameFrame - 1] = nil
	if not recordQueue[gameFrame] then
		return
	end
	Spring.SendCommands("pause 1")
	PopFromQueue()
	--Spring.Echo(playedShot, playedFrame)
	SetupCamera()
	Spring.SetVideoCapturingMode(true)
	Spring.SendCommands("hideinterface 1")
	vsx, vsy = widgetHandler:GetViewSizes()
end


function widget:DrawScreenEffects()
	if not playedShot or not playedFrame then
		return
	end

	if RecordFrame() then
		if PopFromQueue() then
			SetupCamera()
			if not isReplay then
				ChangeTimelineFrame(playedFrame)
			end
		else
			Spring.SetVideoCapturingMode(false)
			Spring.SendCommands("hideinterface 0")
			Spring.SendCommands("pause 0")
			playedFrame = nil
			playedShot = nil
			recording = false
		end
	end
end

function widget:Initialize()
	Spring.CreateDir(CAPTURES_DIR)
	InitGUI()
	ChangeTimelineFrame(0)
end

function widget:GameID(gid)
	gameID = gid
end

-----------------------
-- /Callins && Crap
-----------------------
