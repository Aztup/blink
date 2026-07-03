return [[local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local IsStudio = RunService:IsStudio()

-- SPLIT --
if not RunService:IsServer() then
    error("Server network module can only be required from the server.")
end

local Reliable: RemoteEvent = ReplicatedStorage:FindFirstChild(BASE_EVENT_NAME .. "_RELIABLE_REMOTE") :: RemoteEvent
if not Reliable then
    local RemoteEvent = Instance.new("RemoteEvent")
    RemoteEvent.Name = BASE_EVENT_NAME .. "_RELIABLE_REMOTE"
    RemoteEvent.Parent = ReplicatedStorage
    Reliable = RemoteEvent
end

local Unreliable: UnreliableRemoteEvent = ReplicatedStorage:FindFirstChild(BASE_EVENT_NAME .. "_UNRELIABLE_REMOTE") :: UnreliableRemoteEvent
if not Unreliable then
    local UnreliableRemoteEvent = Instance.new("UnreliableRemoteEvent")
    UnreliableRemoteEvent.Name = BASE_EVENT_NAME .. "_UNRELIABLE_REMOTE"
    UnreliableRemoteEvent.Parent = ReplicatedStorage
    Unreliable = UnreliableRemoteEvent
end

-- Maximum size (in bytes) of an incoming packet buffer.
-- Packets larger than this are dropped before the receive loop runs
-- Roblox compresses remote payloads on the wire, so a client can cheaply send a
-- buffer that decompresses to tens of MB and stalls the main thread.
-- Can be tuned to whatever value fits you the best
-- Default: 100kb
local MAX_PACKET_SIZE = 100 * 1024

-- Maximum total size (in bytes) of buffered events, per event type, while no
-- listener is connected. Once exceeded, incoming events of that type are dropped
-- in a live game (a warning is thrown)
-- Default: 1mb
local MAX_QUEUE_MEMORY = 1024 * 1024

-- Approximate per-entry memory cost (in bytes) added on top of an event's wire
-- size when accounting queue memory, so events with little or no payload still
-- count towards MAX_QUEUE_MEMORY and can't be spammed for free.
local QUEUE_ENTRY_OVERHEAD = 40

local QUEUE_INSTANCE_OVERHEAD = 40
local QUEUE_MEASURE_MAX_NODES = 4096
local QUEUE_MEASURE_MAX_DEPTH = 8
local MeasureNodes = 0

local function MeasureQueued(Value: any, Depth: number): number
    MeasureNodes += 1
    if MeasureNodes > QUEUE_MEASURE_MAX_NODES then
        return math.huge
    end

    local Kind = typeof(Value)
    if Kind == "Instance" then
        return QUEUE_INSTANCE_OVERHEAD
    elseif Kind == "buffer" then
        return buffer.len(Value)
    elseif Kind == "string" then
        return #Value
    elseif Kind == "table" then
        if Depth <= 0 then
            return math.huge
        end

        local Total = QUEUE_INSTANCE_OVERHEAD
        for Key, Sub in Value do
            Total += MeasureQueued(Key, Depth - 1) + MeasureQueued(Sub, Depth - 1)
            if Total >= MAX_QUEUE_MEMORY or MeasureNodes > QUEUE_MEASURE_MAX_NODES then
                return math.huge
            end
        end
        return Total
    end

    return QUEUE_INSTANCE_OVERHEAD
end

-- Calculates approximate memory cast of the received data
local function QueuedInstancesSize(Start: number, Finish: number): number
    MeasureNodes = 0
    local Total = 0
    for Cursor = Start + 1, Finish do
        Total += MeasureQueued(RecieveInstances[Cursor], QUEUE_MEASURE_MAX_DEPTH)
        if Total >= MAX_QUEUE_MEMORY then
            return math.huge
        end
    end
    return Total
end

local PlayersMap: {[Player]: BufferSave} = {}

Players.PlayerRemoving:Connect(function(Player)
    PlayersMap[Player] = nil

	-- Clears the queue for that player
    for _, Sizes in QueueSize.Reliable do
        Sizes[Player] = nil
    end
end)

local function StepReplication()
    for Player, Send in PlayersMap do
        if Send.Cursor <= 0 then
            continue
        end

        local Buffer = buffer.create(Send.Cursor)
        buffer.copy(Buffer, 0, Send.Buffer, 0, Send.Cursor)
        Reliable:FireClient(Player, Buffer, Send.Instances)

        Send.Size = 64
        Send.Cursor = 0
        Send.Buffer = buffer.create(64)
        table.clear(Send.Instances)
    end
end
]]
