local ChatLootBidder = ChatLootBidderFrame
--if ChatLootBidder == nil then print("XML Error"); return end
local T = ChatLootBidder_i18n
local startSessionButton = getglobal(ChatLootBidder:GetName() .. "StartSession")
local endSessionButton = getglobal(ChatLootBidder:GetName() .. "EndSession")
local clearSessionButton = getglobal(ChatLootBidder:GetName() .. "ClearSession")

local gfind = string.gmatch or string.gfind
math.randomseed(time() * 100000000000)
for i=1,3 do
  math.random(10000, 65000)
end

local function Roll()
  return math.random(1, 100)
end

local addonName = "ChatLootBidder"
local addonTitle = GetAddOnMetadata(addonName, "Title")
local addonNotes = GetAddOnMetadata(addonName, "Notes")
local addonVersion = GetAddOnMetadata(addonName, "Version")
local addonAuthor = GetAddOnMetadata(addonName, "Author")
local chatPrefix = "<CL> "
local me = UnitName("player")
-- Roll tracking heavily borrowed from RollTracker: http://www.wowace.com/projects/rolltracker/
if GetLocale() == 'deDE' then RANDOM_ROLL_RESULT = "%s w\195\188rfelt. Ergebnis: %d (%d-%d)"
elseif RANDOM_ROLL_RESULT == nil then RANDOM_ROLL_RESULT = "%s rolls %d (%d-%d)" end -- Using english language https://vanilla-wow-archive.fandom.com/wiki/WoW_constants if not set
local rollRegex = string.gsub(string.gsub(string.gsub("%s rolls %d (%d-%d)", "([%(%)%-])", "%%%1"), "%%s", "%%(.+%)"), "%%d", "%%(%%d+%)")

ChatLootBidder_ChatFrame_OnEvent = ChatFrame_OnEvent

local softReserveSessionName = nil
local softReservesLocked = false
local session = nil
local sessionMode = nil
local stage = nil
local lastWhisper = nil

local function DefaultFalse(prop) return prop == true end
local function DefaultTrue(prop) return prop == nil or DefaultFalse(prop) end

local function LoadVariables()
  ChatLootBidder_Store = ChatLootBidder_Store or {}
  ChatLootBidder_Store.ItemValidation = DefaultTrue(ChatLootBidder_Store.ItemValidation)
  ChatLootBidder_Store.RollAnnounce = DefaultTrue(ChatLootBidder_Store.RollAnnounce)
  ChatLootBidder_Store.AutoStage = DefaultTrue(ChatLootBidder_Store.AutoStage)
  ChatLootBidder_Store.BidAnnounce = DefaultFalse(ChatLootBidder_Store.BidAnnounce)
  ChatLootBidder_Store.BidSummary = DefaultFalse(ChatLootBidder_Store.BidSummary)
  ChatLootBidder_Store.BidChannel = ChatLootBidder_Store.BidChannel or "OFFICER"
  ChatLootBidder_Store.SessionAnnounceChannel = ChatLootBidder_Store.SessionAnnounceChannel or "RAID"
  ChatLootBidder_Store.WinnerAnnounceChannel = ChatLootBidder_Store.WinnerAnnounceChannel or "RAID_WARNING"
  ChatLootBidder_Store.DebugLevel = ChatLootBidder_Store.DebugLevel or 0
  ChatLootBidder_Store.TimerSeconds = ChatLootBidder_Store.TimerSeconds or 30
  ChatLootBidder_Store.MaxBid = ChatLootBidder_Store.MaxBid or 5000
  ChatLootBidder_Store.MinBid = ChatLootBidder_Store.MinBid or 1
  ChatLootBidder_Store.MinRarity = ChatLootBidder_Store.MinRarity or 4
  ChatLootBidder_Store.MaxRarity = ChatLootBidder_Store.MaxRarity or 5
  ChatLootBidder_Store.DefaultSessionMode = ChatLootBidder_Store.DefaultSessionMode or "MSOS" -- DKP | MSOS
  ChatLootBidder_Store.BreakTies = DefaultTrue(ChatLootBidder_Store.BreakTies)
  ChatLootBidder_Store.AddonVersion = addonVersion
  ChatLootBidder_Store.SoftReserveSessions = ChatLootBidder_Store.SoftReserveSessions or {}
  ChatLootBidder_Store.AutoRemoveSrAfterWin = DefaultTrue(ChatLootBidder_Store.AutoRemoveSrAfterWin)
  ChatLootBidder_Store.AutoLockSoftReserve = DefaultTrue(ChatLootBidder_Store.AutoLockSoftReserve)
  -- TODO: Make this custom per Soft Reserve session and make this the default when a new list is started
  ChatLootBidder_Store.DefaultMaxSoftReserves = 1
end

local function Trim(str)
  local _start, _end, _match = string.find(str, '^%s*(.-)%s*$')
  return _match or ""
end

local function ToWholeNumber(numberString, default)
  if default == nil then default = 0 end
  if numberString == nil then return default end
  local num = math.floor(tonumber(numberString) or default)
  if default == num then return default end
  return math.max(num, default)
end

local function Error(message)
	DEFAULT_CHAT_FRAME:AddMessage("|cffbe5eff" .. chatPrefix .. "|cffff0000 "..message)
end

local function Message(message)
	DEFAULT_CHAT_FRAME:AddMessage("|cffbe5eff".. chatPrefix .."|r "..message)
end

local function Debug(message)
	if ChatLootBidder_Store.DebugLevel > 0 then
		DEFAULT_CHAT_FRAME:AddMessage("|cffbe5eff".. chatPrefix .."|cffffff00 "..message)
	end
end

local function Trace(message)
	if ChatLootBidder_Store.DebugLevel > 1 then
		DEFAULT_CHAT_FRAME:AddMessage("|cffbe5eff".. chatPrefix .."|cffffff00 "..message)
	end
end

-- Add this near the top with other helper functions
local function RoundUpToTen(number)
  return math.ceil(number / 10) * 10
end

-- Add this helper function near the top with other helper functions
local function ClearOtherBids(itemSession, bidder, keepType)
  Debug("ClearOtherBids called for " .. bidder .. ", keeping " .. (keepType or "nil"))
  
  if not itemSession then
    Debug("No itemSession provided")
    return
  end
  
  if keepType == "bid" then 
    Debug("Keeping bid type - no clearing needed")
    return 
  end
  
  local bidTypes = {"ms", "os", "tmog", "stock"}
  for _, bidType in pairs(bidTypes) do
    if bidType ~= keepType then
      if itemSession[bidType] and itemSession[bidType][bidder] then
        Debug("Clearing " .. bidType .. " bid for " .. bidder)
        itemSession[bidType][bidder] = nil
      end
    end
  end
end

-- Add helper function to get highest bid for a tier
local function GetHighestBid(itemSession, tier)
  local highest = ChatLootBidder_Store.MinBid - 1  -- Start below MinBid so first valid bid is accepted
  local bids = itemSession[tier]
  if bids then
    for _, bid in pairs(bids) do
      if tonumber(bid) > highest then
        highest = tonumber(bid)
      end
    end
  end
  return highest
end

function ChatLootBidder:SetPropValue(propName, propValue, prefix)
  if prefix then
    propName = string.sub(propName, strlen(prefix)+1)
  end
  if ChatLootBidder_Store[propName] ~= nil then
    ChatLootBidder_Store[propName] = propValue
    local v = propValue
    if type(v) == "boolean" then
      v = v and "on" or "off"
    end
    Debug((T[propName] or propName) .. " is " .. tostring(v))

    -- Special Handlers for specific properties here
    if propName == "DefaultSessionMode" then
      ChatLootBidder:RedrawStage()
    end

  else
    Error(propName .. " is not initialized")
  end
end

local ShowHelp = function()
	Message("/loot - Open GUI Options")
  Message("/loot stage [itm1] [itm2] - Stage item(s) for a future session start")
	Message("/loot start [itm1] [itm2] [#timer_optional] - Start a session for item(s) + staged items(s)")
  Message("/loot end - End a loot session and announce winner(s)")
  Message("/loot sr load [name]  - Load a SR list (by name, optional)")
	Message(addonNotes .. " for detailed instructions, bugs, and suggestions")
	Message("Written by " .. addonAuthor)
end

local function GetRaidIndex(unitName)
  if UnitInRaid("player") == 1 then
     for i = 1, GetNumRaidMembers() do
        if UnitName("raid"..i) == unitName then
           return i
        end
     end
  end
  return 0
end

local function IsInRaid(unitName)
  return GetRaidIndex(unitName) ~= 0
end

local function IsRaidAssistant(unitName)
  _, rank = GetRaidRosterInfo(GetRaidIndex(unitName));
  return rank ~= 0
end

local function GetPlayerClass(unitName)
  _, _, _, _, _, playerClass = GetRaidRosterInfo(GetRaidIndex(unitName));
  return playerClass
end

local function IsMasterLooterSet()
  local method, _ = GetLootMethod()
  return method == "master"
end

local function IsStaticChannel(channel)
  channel = channel == nil and nil or string.upper(channel)
  return channel == "RAID" or channel == "RAID_WARNING" or channel == "SAY" or channel == "EMOTE" or channel == "PARTY" or channel == "GUILD" or channel == "OFFICER" or channel == "YELL"
end

local function IsTableEmpty(tbl)
  if tbl == nil then return true end
  local next = next
  return next(tbl) == nil
end

-- Flatten a Player: [ SR1, SR2 ] structure into: { [Player, SR1], [Player, SR2] }
local function Flatten(tbl)
  if tbl == nil then return {} end
  local flattened = {}
  local k, arr, v
  for k, arr in pairs(tbl) do
    for _,v in pairs(arr) do
      table.insert(flattened, { k, v })
    end
  end
  return flattened
end

-- Take a [[Player, SR1], [Player, SR2]] data structure and Map it: { Player: [ SR1, SR2 ] }
local function UnFlatten(tbl)
  if tbl == nil then return {} end
  local unflattened = {}
  local arr
  for _, arr in pairs(tbl) do
    if unflattened[arr[1]] == nil then unflattened[arr[1]] = {} end
    if arr[2] ~= nil then
      table.insert(unflattened[Trim(arr[1])], Trim(arr[2]))
    end
  end
  return unflattened
end

local function TableContains(table, element)
  local value
  for _,value in pairs(table) do
    if value == element then
      return true
    end
  end
  return false
end

local function ParseItemNameFromItemLink(i)
  local _, _ , n = string.find(i, "|h.(.-)]")
  return n
end

local function TableLength(tbl)
  if tbl == nil then return 0 end
  local count = 0
  for _ in pairs(tbl) do count = count + 1 end
  return count
end

local function SplitBySpace(str)
  local commandlist = { }
  local command
  for command in gfind(str, "[^ ]+") do
    table.insert(commandlist, command)
  end
  return commandlist
end

local function GetKeysWhere(tbl, fn)
  if tbl == nil then return {} end
  local keys = {}
  for key,value in pairs(tbl) do
    if fn == nil or fn(key, value) then
      table.insert(keys, key)
    end
  end
  return keys
end

local function GetKeys(tbl)
  return GetKeysWhere(tbl)
end

local function GetKeysSortedByValue(tbl)
  local keys = GetKeys(tbl)
  table.sort(keys, function(a, b)
    return tbl[a] > tbl[b]
  end)
  return keys
end

local function SendToChatChannel(channel, message, prio)
  if IsStaticChannel(channel) then
    ChatThrottleLib:SendChatMessage(prio or "NORMAL", shortName, message, channel)
  else
    local channelIndex = GetChannelName(channel)
    if channelIndex > 0 then
      ChatThrottleLib:SendChatMessage(prio or "NORMAL", shortName, message, "CHANNEL", nil, channelIndex)
    else
      Error(channel .. " <Not In Channel> " .. message)
    end
  end
end

local function MessageBidSummaryChannel(message, force)
  if ChatLootBidder_Store.BidSummary or force then
    SendToChatChannel(ChatLootBidder_Store.BidChannel, message)
    Trace("<SUMMARY>" .. message)
  else
    Debug("<SUMMARY>" .. message)
  end
end

local function MessageBidChannel(message)
  if ChatLootBidder_Store.BidAnnounce then
    SendToChatChannel(ChatLootBidder_Store.BidChannel, message)
    Trace("<BID>" .. message)
  else
    Debug("<BID>" .. message)
  end
end

local function MessageWinnerChannel(message)
  SendToChatChannel(ChatLootBidder_Store.WinnerAnnounceChannel, message)
  Trace("<WIN>" .. message)
end

local function MessageStartChannel(message)
  if IsInRaid(me) then
    SendToChatChannel(ChatLootBidder_Store.SessionAnnounceChannel, message)
  else
    Message(message)
  end
  Trace("<START>" .. message)
end

local function SendResponse(message, bidder)
  if bidder == me then
    Message(message)
  else
    ChatThrottleLib:SendChatMessage("ALERT", shortName, message, "WHISPER", nil, bidder)
  end
end

local function AppendNote(note)
  return (note == nil or note == "") and "" or " [ " .. note .. " ]"
end

local function PlayerWithClassColor(unit)
  if RAID_CLASS_COLORS and pfUI then -- pfUI loads class colors
    local unitClass = GetPlayerClass(unit)
    local colorStr = RAID_CLASS_COLORS[unitClass].colorStr
    if colorStr and string.len(colorStr) == 8 then
      return "\124c" .. colorStr .. "\124Hplayer:" .. unit .. "\124h" .. unit .. "\124h\124r"
    end
  end
  return unit
end

local function Srs(n)
  local n = n or softReserveSessionName
  local srs = ChatLootBidder_Store.SoftReserveSessions[n]
  if srs ~= nil then return srs end
  ChatLootBidder_Store.SoftReserveSessions[n] = {}
  return ChatLootBidder_Store.SoftReserveSessions[n];
end

function ChatLootBidder:LoadedSoftReserveSession()
  if softReserveSessionName then
    return unpack({softReserveSessionName, ChatLootBidder_Store.SoftReserveSessions[softReserveSessionName]})
  end
  return unpack({nil, nil})
end

local function HandleSrRemove(bidder, item)
  local itemName = ParseItemNameFromItemLink(item)
  if Srs()[bidder] == nil then
    Srs()[bidder] = {}
  end
  local sr = Srs()[bidder]
  local i, v
  for i,v in pairs(sr) do
    if v == itemName then
        table.remove(sr,i)
        SendResponse("You are no longer reserving: " .. itemName, bidder)
        return
    end
  end
end

local function BidSummary(item, announceWinners)
  if not item or not session or not session[item] then
    Debug("BidSummary called with invalid item or session")
    return {}
  end

  local itemSession = session[item]
  local summary = {}
  local mainWinner = {}
  local mainWinnerBid = 0
  local mainWinnerTier = nil
  local cancel = itemSession["cancel"] or {}
  local notes = itemSession["notes"] or {}

  -- Process main bids first
  header = true
  if sessionMode == "DKP" then
    -- Handle DKP bids
    if not IsTableEmpty(itemSession["bid"]) then
      local sortedBidKeys = GetKeysSortedByValue(itemSession["bid"])
      for k,bidder in pairs(sortedBidKeys) do
        if cancel[bidder] == nil then
          if IsTableEmpty(mainWinner) then 
            table.insert(mainWinner, bidder)
            mainWinnerBid = itemSession["bid"][bidder]
            mainWinnerTier = "bid"
          elseif not IsTableEmpty(mainWinner) and mainWinnerTier == "bid" and mainWinnerBid == itemSession["bid"][bidder] then 
            table.insert(mainWinner, bidder)
          end
          table.insert(summary, "-- " .. PlayerWithClassColor(bidder) .. ": " .. itemSession["bid"][bidder] .. AppendNote(notes[bidder] or ""))
        end
      end
    else
      -- Handle MS/OS rolls if no DKP bids
      if not IsTableEmpty(itemSession["ms"]) then
        -- Roll for any unrolled MS bidders
        for bidder, _ in pairs(itemSession["ms"]) do
          if cancel[bidder] == nil and (itemSession["roll"][bidder] == nil or itemSession["roll"][bidder] == -1) then
            itemSession["roll"][bidder] = math.random(1, 100)
            MessageBidChannel(PlayerWithClassColor(bidder) .. " rolls " .. itemSession["roll"][bidder] .. " for " .. item .. " for MS")
          end
        end
        
        -- Find highest roller(s)
        local highestRoll = 0
        for bidder, _ in pairs(itemSession["ms"]) do
          if cancel[bidder] == nil then
            if itemSession["roll"][bidder] > highestRoll then
              highestRoll = itemSession["roll"][bidder]
              mainWinner = {bidder}
              mainWinnerTier = "ms"
            elseif itemSession["roll"][bidder] == highestRoll then
              table.insert(mainWinner, bidder)
            end
            table.insert(summary, "-- " .. PlayerWithClassColor(bidder) .. ": MS (" .. itemSession["roll"][bidder] .. ")" .. AppendNote(notes[bidder] or ""))
          end
        end
      end
      
      if IsTableEmpty(mainWinner) and not IsTableEmpty(itemSession["os"]) then
        -- Roll for any unrolled OS bidders
        for bidder, _ in pairs(itemSession["os"]) do
          if cancel[bidder] == nil and (itemSession["roll"][bidder] == nil or itemSession["roll"][bidder] == -1) then
            itemSession["roll"][bidder] = math.random(1, 100)
            MessageBidChannel(PlayerWithClassColor(bidder) .. " rolls " .. itemSession["roll"][bidder] .. " for " .. item .. " for OS")
          end
        end
        
        -- Find highest roller(s)
        local highestRoll = 0
        for bidder, _ in pairs(itemSession["os"]) do
          if cancel[bidder] == nil then
            if itemSession["roll"][bidder] > highestRoll then
              highestRoll = itemSession["roll"][bidder]
              mainWinner = {bidder}
              mainWinnerTier = "os"
            elseif itemSession["roll"][bidder] == highestRoll then
              table.insert(mainWinner, bidder)
            end
            table.insert(summary, "-- " .. PlayerWithClassColor(bidder) .. ": OS (" .. itemSession["roll"][bidder] .. ")" .. AppendNote(notes[bidder] or ""))
          end
        end
      end
    end
  else
    -- MSOS mode - use the same roll handling as DKP mode
    if not IsTableEmpty(itemSession["ms"]) then
      -- Roll for any unrolled MS bidders
      for bidder, _ in pairs(itemSession["ms"]) do
        if cancel[bidder] == nil and (itemSession["roll"][bidder] == nil or itemSession["roll"][bidder] == -1) then
          itemSession["roll"][bidder] = math.random(1, 100)
          MessageBidChannel(PlayerWithClassColor(bidder) .. " rolls " .. itemSession["roll"][bidder] .. " for " .. item .. " for MS")
        end
      end
      
      -- Find highest roller(s)
      local highestRoll = 0
      for bidder, _ in pairs(itemSession["ms"]) do
        if cancel[bidder] == nil then
          if itemSession["roll"][bidder] > highestRoll then
            highestRoll = itemSession["roll"][bidder]
            mainWinner = {bidder}
            mainWinnerTier = "ms"
          elseif itemSession["roll"][bidder] == highestRoll then
            table.insert(mainWinner, bidder)
          end
          table.insert(summary, "-- " .. PlayerWithClassColor(bidder) .. ": MS (" .. itemSession["roll"][bidder] .. ")" .. AppendNote(notes[bidder] or ""))
        end
      end
    end
    
    if IsTableEmpty(mainWinner) and not IsTableEmpty(itemSession["os"]) then
      -- Roll for any unrolled OS bidders
      for bidder, _ in pairs(itemSession["os"]) do
        if cancel[bidder] == nil and (itemSession["roll"][bidder] == nil or itemSession["roll"][bidder] == -1) then
          itemSession["roll"][bidder] = math.random(1, 100)
          MessageBidChannel(PlayerWithClassColor(bidder) .. " rolls " .. itemSession["roll"][bidder] .. " for " .. item .. " for OS")
        end
      end
      
      -- Find highest roller(s)
      local highestRoll = 0
      for bidder, _ in pairs(itemSession["os"]) do
        if cancel[bidder] == nil then
          if itemSession["roll"][bidder] > highestRoll then
            highestRoll = itemSession["roll"][bidder]
            mainWinner = {bidder}
            mainWinnerTier = "os"
          elseif itemSession["roll"][bidder] == highestRoll then
            table.insert(mainWinner, bidder)
          end
          table.insert(summary, "-- " .. PlayerWithClassColor(bidder) .. ": OS (" .. itemSession["roll"][bidder] .. ")" .. AppendNote(notes[bidder] or ""))
        end
      end
    end
  end

  -- Process tmog bids
  if not IsTableEmpty(itemSession["tmog"]) then
    local tmogBidders = {}
    -- Roll for any unrolled tmog bidders
    for bidder, _ in pairs(itemSession["tmog"]) do
      if cancel[bidder] == nil and (itemSession["roll"][bidder] == nil or itemSession["roll"][bidder] == -1) then
        itemSession["roll"][bidder] = math.random(1, 100)
        MessageBidChannel(PlayerWithClassColor(bidder) .. " rolls " .. itemSession["roll"][bidder] .. " for " .. item .. " for TMOG")
      end
    end
    
    -- Find highest roller(s)
    local highestRoll = 0
    local tmogWinners = {}
    for bidder, _ in pairs(itemSession["tmog"]) do
      if cancel[bidder] == nil then
        if itemSession["roll"][bidder] > highestRoll then
          highestRoll = itemSession["roll"][bidder]
          tmogWinners = {bidder}
        elseif itemSession["roll"][bidder] == highestRoll then
          table.insert(tmogWinners, bidder)
        end
        table.insert(summary, "-- " .. PlayerWithClassColor(bidder) .. ": TMOG (" .. itemSession["roll"][bidder] .. ")" .. AppendNote(notes[bidder] or ""))
      end
    end
    
    if not IsTableEmpty(tmogWinners) then
      if announceWinners then
        -- Create a new table to hold the class-colored tmog winners
        local coloredTmogWinners = {}
        for _, winner in ipairs(tmogWinners) do
            table.insert(coloredTmogWinners, PlayerWithClassColor(winner))  -- Wrap each tmogWinner in PlayerWithClassColor
        end

        -- Construct the winner message using the colored tmog winners
        local winnerMessage = "+++ " .. table.concat(coloredTmogWinners, ", ") .. (getn(tmogWinners) > 1 and " tie for " or " wins ") .. item .. " for TMOG with a roll of " .. highestRoll
        MessageWinnerChannel(winnerMessage)
      end
    end
  end

  -- Process stock bids
  if not IsTableEmpty(itemSession["stock"]) then
    local stockBidders = {}
    -- In DKP mode, only process stock if there are no DKP bids
    -- In either mode, only process stock if there are no MS/OS bids
    if (sessionMode == "DKP" and not IsTableEmpty(itemSession["bid"])) or
       not IsTableEmpty(itemSession["ms"]) or 
       not IsTableEmpty(itemSession["os"]) then
      -- Skip stock bids if there are higher priority bids
    else
      -- Roll for any unrolled stock bidders
      for bidder, _ in pairs(itemSession["stock"]) do
        if cancel[bidder] == nil and (itemSession["roll"][bidder] == nil or itemSession["roll"][bidder] == -1) then
          itemSession["roll"][bidder] = math.random(1, 100)
          MessageBidChannel(PlayerWithClassColor(bidder) .. " rolls " .. itemSession["roll"][bidder] .. " for " .. item .. " for STOCK")
        end
      end

      -- Find highest roller(s)
      local highestRoll = 0
      for bidder, _ in pairs(itemSession["stock"]) do
        if cancel[bidder] == nil then
          if itemSession["roll"][bidder] > highestRoll then
            highestRoll = itemSession["roll"][bidder]
            stockBidders = {bidder}
          elseif itemSession["roll"][bidder] == highestRoll then
            table.insert(stockBidders, bidder)
          end
          table.insert(summary, "-- " .. PlayerWithClassColor(bidder) .. ": STOCK (" .. itemSession["roll"][bidder] .. ")" .. AppendNote(notes[bidder] or ""))
        end
      end

      if not IsTableEmpty(stockBidders) then
        if announceWinners then
          -- Create a new table to hold the class-colored stock bidders
          local coloredStockBidders = {}
          for _, bidder in ipairs(stockBidders) do
              table.insert(coloredStockBidders, PlayerWithClassColor(bidder))  -- Wrap each stockBidder in PlayerWithClassColor
          end

          -- Construct the winner message using the colored stock bidders
          local winnerMessage = ">>> " .. table.concat(coloredStockBidders, ", ") .. (getn(stockBidders) > 1 and " tie for " or " wins ") .. item .. " for STOCK with a roll of " .. highestRoll
          MessageWinnerChannel(winnerMessage)
        end
      end
    end
  end

  -- Only announce "No bids" if there were no bids of any type and no soft reserves
  if IsTableEmpty(mainWinner) and IsTableEmpty(itemSession["tmog"]) and IsTableEmpty(itemSession["stock"]) then
    if announceWinners and IsTableEmpty(itemSession["sr"]) then  -- Check if there are no soft reserves
      MessageStartChannel("No bids received for " .. item)
    end
    table.insert(summary, item .. ": No Bids")
  elseif announceWinners and not IsTableEmpty(mainWinner) then
    -- Create a new table to hold the class-colored winners
    local coloredWinners = {}
    for _, winner in ipairs(mainWinner) do
        table.insert(coloredWinners, PlayerWithClassColor(winner))  -- Wrap each winner in PlayerWithClassColor
    end

    -- Construct the winner message using the colored winners
    local winnerMessage = ">>> " .. table.concat(coloredWinners, ", ") .. (getn(mainWinner) > 1 and " tie for " or " wins ") .. item
    if sessionMode == "DKP" and mainWinnerTier == "bid" then
      winnerMessage = winnerMessage .. " with a bid of " .. mainWinnerBid .. " DKP"
    else
      -- Add roll type to announcement for MS/OS/STOCK
      if mainWinnerTier then
        winnerMessage = winnerMessage .. " for " .. string.upper(mainWinnerTier)
        -- Add roll value for MS/OS/STOCK
        if itemSession["roll"][mainWinner[1]] then
          winnerMessage = winnerMessage .. " with a roll of " .. itemSession["roll"][mainWinner[1]]
        end
      end
    end
    MessageWinnerChannel(winnerMessage)
  end

  return summary
end

function ChatLootBidder:End()
  ChatThrottleLib:SendAddonMessage("BULK", "NotChatLootBidder", "endSession=1", "RAID")
  
  -- Process each item in the session
  if session then
    for item, itemSession in pairs(session) do
      -- Pass true to announce winners, but don't display the summary
      BidSummary(item, true)
    end
  end
  
  session = nil
  sessionMode = nil
  stage = nil
  endSessionButton:Hide()
  ChatLootBidder:Hide()
end

local function GetItemLinks(str)
  local itemLinks = {}
  local _start, _end, _lastEnd = nil, -1, -1
  while true do
    _start, _end = string.find(str, "|c.-|H.-|h|r", _end + 1)
    if _start == nil then
      return itemLinks, _lastEnd
    end
    _lastEnd = _end
    table.insert(itemLinks, string.sub(str, _start, _end))
  end
end

function ChatLootBidder:Start(items, timer, mode)
  if not IsRaidAssistant(me) then Error("You must be a raid leader or assistant in a raid to start a loot session"); return end
  if not IsMasterLooterSet() then Error("Master Looter must be set to start a loot session"); return end
  local mode = mode ~= nil and mode or ChatLootBidder_Store.DefaultSessionMode
  if session ~= nil then ChatLootBidder:End() end
  local stageList = GetKeysWhere(stage, function(k,v) return v == true end)
  if items == nil then
    items = stageList
  else
    for _, v in pairs(stageList) do
      table.insert(items, v)
    end
  end
  if IsTableEmpty(items) then Error("You must provide at least a single item to bid on"); return end
  ChatLootBidder:EndSessionButtonShown()
  session = {}
  sessionMode = mode
  stage = nil
  if ChatLootBidder_Store.AutoLockSoftReserve and softReserveSessionName ~= nil and not softReservesLocked then
    softReservesLocked = true
    MessageStartChannel("Soft Reserves for " .. softReserveSessionName .. " are now LOCKED")
  end
  local srs = mode == "MSOS" and softReserveSessionName ~= nil and ChatLootBidder_Store.SoftReserveSessions[softReserveSessionName] or {}
  local startChannelMessage = {}
  table.insert(startChannelMessage, "Bid on the following items:")
  local bidAddonMessage = "mode=" .. mode .. ",items="
  local exampleItem
  for k,i in pairs(items) do
    local itemName = ParseItemNameFromItemLink(i)
    local srsOnItem = GetKeysWhere(srs, function(player, playerSrs) return IsInRaid(player) and TableContains(playerSrs, itemName) end)
    local srLen = TableLength(srsOnItem)
    session[i] = {}
    if srLen == 0 then
      exampleItem = i
      table.insert(startChannelMessage, "> " .. i)
      bidAddonMessage = bidAddonMessage .. string.gsub(i, ",", "~~~")
      if sessionMode == "DKP" then
        session[i]["bid"] = {}  -- Initialize bid table for DKP mode
        session[i]["ms"] = {}   -- Also initialize MS/OS tables for rolls
        session[i]["os"] = {}
      else
        session[i]["ms"] = {}   -- Initialize MS/OS tables for MSOS mode
        session[i]["os"] = {}
      end
      session[i]["tmog"] = {}   -- Initialize tmog table for all modes
      session[i]["stock"] = {}  -- Initialize stock table for all modes
      session[i]["roll"] = {}
      session[i]["cancel"] = {}
      session[i]["notes"] = {}
    else
      session[i]["sr"] = {}
      session[i]["roll"] = {}
      
      -- Collect soft reserves and prepare to send a message
      local playersWithSR = {}  -- Table to hold players with soft reserves
      for _, sr in pairs(srsOnItem) do
        session[i]["sr"][sr] = 1
        session[i]["roll"][sr] = -1
        table.insert(playersWithSR, sr)  -- Add each player to the list
      end
      
      -- Send the message only once after processing all soft reserves
      if srLen > 1 then
        MessageBidChannel(i .. " is soft reserved by: " .. table.concat(playersWithSR, ", ") .. ". '/roll' now!")
      else
        MessageBidChannel(playersWithSR[1] .. " won " .. i .. " with a soft reserve!")
      end
    end
  end
  if exampleItem then
    if mode == "DKP" then
      table.insert(startChannelMessage, "/w " .. PlayerWithClassColor(me) .. " " .. exampleItem .. " bid [dkp-amount]/ms/os/tmog/stock")
    else
      table.insert(startChannelMessage, "/w " .. PlayerWithClassColor(me) .. " " .. exampleItem .. " ms/os/tmog/stock")
    end
    local l
    for _, l in pairs(startChannelMessage) do
      MessageStartChannel(l)
    end
    if timer == nil or timer < 0 then timer = ChatLootBidder_Store.TimerSeconds end
    if BigWigs and timer > 0 then BWCB(timer, "Bidding Ends") end
    ChatThrottleLib:SendAddonMessage("BULK", "NotChatLootBidder", bidAddonMessage, "RAID")
  else
    -- Everything was SR'd - just end now
    ChatLootBidder:End()
  end
end

function ChatLootBidder:Clear(stageOnly)
  if session == nil or stageOnly then
    if IsTableEmpty(stage) then
      Message("There is no active session or stage")
    else
      stage = nil
      Message("Cleared the stage")
      ChatLootBidder:RedrawStage()
    end
  else
    session = nil
    Message("Cleared the current loot session")
  end
end

function ChatLootBidder:Unstage(item, redraw)
  stage[item] = false
  if redraw then ChatLootBidder:RedrawStage() end
end

function ChatLootBidder:HandleSrDelete(providedName)
  if softReserveSessionName == nil and providedName == nil then
    Error("No Soft Reserve session loaded or provided for deletion")
  elseif providedName == nil then
    ChatLootBidder_Store.SoftReserveSessions[softReserveSessionName] = nil
    Message("Deleted currently loaded Soft Reserve session: " .. softReserveSessionName)
    softReserveSessionName = nil
  elseif ChatLootBidder_Store.SoftReserveSessions[providedName] == nil then
    Error("No Soft Reserve session exists with the label: " .. providedName)
  else
    ChatLootBidder_Store.SoftReserveSessions[providedName] = nil
    Message("Deleted Soft Reserve session: " .. providedName)
  end
  if providedName == nil or providedName == softReserveSessionName then
    SrEditFrame:Hide()
  end
end

local function craftName(appender)
  return date("%y-%m-%d") .. (appender == 0 and "" or ("-"..appender))
end

function ChatLootBidder:HandleSrAddDefault()
  local appender = 0
  while ChatLootBidder_Store.SoftReserveSessions[craftName(appender)] ~= nil do
    appender = appender + 1
  end
  softReserveSessionName = craftName(appender)
  local srs = Srs()
  Message("New Soft Reserve list [" .. softReserveSessionName .. "] loaded")
  SrEditFrame:Hide()
  ChatLootBidderOptionsFrame_Init(softReserveSessionName)
end

function ChatLootBidder:HandleSrLoad(providedName)
  if providedName then
    softReserveSessionName = providedName
    local srs = Srs()
    ValidateFixAndWarn(srs)
    Message("Soft Reserve list [" .. softReserveSessionName .. "] loaded with " .. TableLength(srs) .. " players with soft reserves")
    SrEditFrame:Hide()
    ChatLootBidderOptionsFrame_Init(softReserveSessionName)
  else
    ChatLootBidder:HandleSrAddDefault()
  end
end

function ChatLootBidder:HandleSrUnload()
  if softReserveSessionName == nil then
    Error("No Soft Reserve session loaded")
  else
    Message("Unloaded Soft Reserve session: " .. softReserveSessionName)
    softReserveSessionName = nil
  end
  ChatLootBidderOptionsFrame_Reload()
  SrEditFrame:Hide()
end

function ChatLootBidder:HandleSrInstructions()
  MessageStartChannel("Set your SR: /w " .. PlayerWithClassColor(me) .. " sr [item-link or exact-item-name]")
  MessageStartChannel("Get your current SR: /w " .. PlayerWithClassColor(me) .. " sr")
  MessageStartChannel("Clear your current SR: /w " .. PlayerWithClassColor(me) .. " sr clear")
end

function ChatLootBidder:HandleSrShow()
  if softReserveSessionName == nil then
    Error("No Soft Reserve session loaded")
  else
    local srs = Srs()
    if IsTableEmpty(srs) then
      Error("No Soft Reserves placed yet")
      return
    end
    MessageStartChannel("Soft Reserve Bids:")
    local keys = GetKeys(srs)
    table.sort(keys)
    local player
    for _, player in pairs(keys) do
      local sr = srs[player]
      if not IsTableEmpty(sr) then
        local msg = PlayerWithClassColor(player) .. ": " .. table.concat(sr, ", ")
        if IsInRaid(player) then
          MessageStartChannel(msg)
        else
          Message(msg)
        end
      end
    end
  end
end

local function EncodeSemicolon()
  local encoded = ""
  for k,v in pairs(Srs()) do
    encoded = encoded .. k
    for _, sr in pairs(v) do
      encoded = encoded .. " ; " .. sr
    end
    encoded = encoded .. "\n"
  end
  return encoded
end

local function EncodeRaidResFly()
  local encoded = ""
  local flat = Flatten(Srs())
  for _,arr in flat do
    -- [00:00]Autozhot: Autozhot - Band of Accuria
    encoded = (encoded or "") .. "[00:00]"..arr[1]..": "..arr[1].." - "..arr[2].."\n"
  end
  return encoded
end

-- This is the most simple pretty print function possible applciable to { key : [value, value, value] } structures only
local function PrettyPrintJson(encoded)
  -- The default empty structure should be an object, not an array
  if encoded == "[]" then return "{}" end
  encoded = string.gsub(encoded, "{", "{\n")
  encoded = string.gsub(encoded, "}", "\n}")
  encoded = string.gsub(encoded, "],", "],\n")
  return encoded
end

local function HandleChannel(prop, channel)
  if IsStaticChannel(channel) then channel = string.upper(channel) end
  ChatLootBidder_Store[prop] = channel
  Message(T[prop] .. " announce channel set to " .. channel)
  getglobal("ChatLootBidderOptionsFrame"..prop):SetValue(channel)
end

function ChatLootBidder:HandleEncoding(encodingType)
  if softReserveSessionName == nil then
    Error("No Soft Reserve list is loaded")
  else
    local encoded
    if encodingType == "csv" then
      encoded = csv:toCSV(Flatten(Srs()))
    elseif encodingType == "json" then
      encoded = PrettyPrintJson(json.encode(Srs()))
    elseif encodingType == "semicolon" then
      encoded = EncodeSemicolon()
    elseif encodingType == "raidresfly" then
      encoded = EncodeRaidResFly()
    end
    if not SrEditFrame:IsVisible() then
      SrEditFrame:Show()
    elseif SrEditFrameHeaderString:GetText() == encodingType then
      SrEditFrame:Hide()
    end
    SrEditFrameText:SetText(encoded)
    SrEditFrameHeaderString:SetText(encodingType)
  end
end

function ChatLootBidder:ToggleSrLock(command)
  if softReserveSessionName == nil then
    Error("No Soft Reserve session loaded")
  else
    if command then
      softReservesLocked = command == "lock"
    else
      softReservesLocked = not softReservesLocked
    end
    MessageStartChannel("Soft Reserves for " .. softReserveSessionName .. " are now " .. (softReservesLocked and "LOCKED" or "UNLOCKED"))
  end
end

function ChatLootBidder:IsLocked()
  return softReservesLocked
end

local InitSlashCommands = function()
	SLASH_ChatLootBidder1, SLASH_ChatLootBidder2 = "/l", "/loot"
  SLASH_ChatLootBidderShort1 = "/ls"
	SlashCmdList["ChatLootBidder"] = function(message)
		local commandlist = SplitBySpace(message)
    if commandlist[1] == nil then
      if ChatLootBidderOptionsFrame:IsVisible() then
        ChatLootBidderOptionsFrame:Hide()
      else
        ChatLootBidderOptionsFrame:Show()
      end
    elseif commandlist[1] == "help" or commandlist[1] == "info" then
			ShowHelp()
    elseif commandlist[1] == "sr" then
      if ChatLootBidder_Store.DefaultSessionMode ~= "MSOS" then
        Error("You need to be in MSOS mode to modify Soft Reserve sessions.  `/loot` to change modes.")
        return
      end
      local subcommand = commandlist[2]
      if commandlist[2] == "load" then
        ChatLootBidder:HandleSrLoad(commandlist[3])
      elseif commandlist[2] == "unload" then
        HandleSrUnload()
      elseif commandlist[2] == "delete" then
        ChatLootBidder:HandleSrDelete(commandlist[3])
      elseif commandlist[2] == "show" then
        ChatLootBidder:HandleSrShow()
      elseif commandlist[2] == "csv" or commandlist[2] == "json" or commandlist[2] == "semicolon" or commandlist[2] == "raidresfly" then
        ChatLootBidder:HandleEncoding(commandlist[2])
      elseif commandlist[2] == "lock" or commandlist[2] == "unlock" then
        ChatLootBidder:ToggleSrLock(commandlist[2])
      elseif commandlist[2] == "instructions" then
        ChatLootBidder:HandleSrInstructions()
      else
        Error("Unknown 'sr' subcommand: " .. (commandlist[2] == nil and "nil" or commandlist[2]))
        Error("Valid values are: load, unload, delete, show, lock, unlock, json, semicolon, raidresfly, csv, instructions")
      end
    elseif commandlist[1] == "debug" then
      ChatLootBidder_Store.DebugLevel = ToWholeNumber(commandlist[2])
      Message("Debug level set to " .. ChatLootBidder_Store.DebugLevel)
    elseif commandlist[1] == "bid" and commandlist[2] then
      HandleChannel("BidChannel", commandlist[2])
    elseif commandlist[1] == "session" and commandlist[2] then
      HandleChannel("SessionAnnounceChannel", commandlist[2])
    elseif commandlist[1] == "win" and commandlist[2] then
      HandleChannel("WinnerAnnounceChannel", commandlist[2])
    elseif commandlist[1] == "end" then
      ChatLootBidder:End()
    elseif commandlist[1] == "clear" then
      if commandlist[2] == nil then
        ChatLootBidder:Clear()
      elseif stage == nil then
        Error("The stage is empty")
      else
        local itemLinks = GetItemLinks(message)
        for _, item in pairs(itemLinks) do
          ChatLootBidder:Unstage(item)
        end
      end
      ChatLootBidder:RedrawStage()
    elseif commandlist[1] == "stage" then
      local itemLinks = GetItemLinks(message)
      for _, item in pairs(itemLinks) do
        local item = item
        ChatLootBidder:Stage(item, true)
      end
      ChatLootBidder:RedrawStage()
    elseif commandlist[1] == "summary" then
      BidSummary()
    elseif commandlist[1] == "start" then
      local itemLinks = GetItemLinks(message)
      local optionalTimer = ToWholeNumber(commandlist[getn(commandlist)], -1)
      ChatLootBidder:Start(itemLinks, optionalTimer)
		end
  end
  SlashCmdList["ChatLootBidderShort"] = function(message)
    local commandlist = SplitBySpace(message)
    local itemLinks = GetItemLinks(message)
    local optionalTimer = ToWholeNumber(commandlist[getn(commandlist)], -1)
    ChatLootBidder:Start(itemLinks, optionalTimer)
  end
end

local function LoadText()
  local k,v,g
  for k,v in pairs(T) do
    if type(k) == "string" then
      g = getglobal("ChatLootBidderOptionsFrame"..k.."Text")
      if g then g:SetText(v) end
    end
  end
end

local function LoadValues()
  local k,v,g,t
  for k,v in pairs(ChatLootBidder_Store) do
    t = type(v)
    g = getglobal("ChatLootBidderOptionsFrame"..k)
    if g and g.SetChecked and t == "boolean" then
      g:SetChecked(v)
    elseif g and k == "DefaultSessionMode" then
      g:SetValue(v == "MSOS" and 1 or 0)
    elseif g and g.SetValue and (t == "string" or t == "number") then
      g:SetValue(v)
    else
      Trace(k .. " <noGui> " .. tostring(v))
    end
  end
end

local function IsValidTier(tier)
  return tier == "bid" or tier == "ms" or tier == "os" or tier == "tmog" or tier == "stock" or tier == "cancel"
end

local function InvalidBidSyntax(item)
  if sessionMode == "DKP" then
    return "Invalid bid syntax for " .. item .. ". Format: '[item-link] bid " .. (ChatLootBidder_Store.MinBid + 9) .. "' or '[item-link] ms/os/tmog/stock'"
  else
    return "Invalid bid syntax for " .. item .. ". Format: '[item-link] ms' or '[item-link] os' or '[item-link] tmog' or '[item-link] stock'"
  end
end

local function of(amt)
  return sessionMode == "DKP" and (" of " .. amt) or ""
end

local function HandleSrQuery(bidder)
  local sr = Srs(softReserveSessionName)[bidder]
  local msg = "Your Soft Reserve is currently " .. (sr == nil and "not set" or ("[ " .. table.concat(sr, ", ") .. " ]"))
  if softReservesLocked then
    msg = msg .. " LOCKED"
  end
  SendResponse(msg, bidder)
end

local function AtlasLootLoaded()
  return (AtlasLoot_Data and AtlasLoot_Data["AtlasLootItems"]) ~= nil
end

-- Ex/
-- AtlasLoot_Data["AtlasLootItems"]["BWLRazorgore"][1]
-- { 16925, "INV_Belt_22", "=q4=Belt of Transcendence", "=ds=#s10#, #a1# =q9=#c5#", "11%" }
local function ValidateItemName(n)
  if not ChatLootBidder_Store.ItemValidation or not AtlasLootLoaded() then return unpack({-1, n, -1, "", ""}) end
  for raidBossKey,raidBoss in AtlasLoot_Data["AtlasLootItems"] do
    for _,dataSet in raidBoss do
      if dataSet then
        local itemNumber, icon, nameQuery, _, dropRate = unpack(dataSet)
        if nameQuery then
          local _start, _end, _quality, _name = string.find(nameQuery, '^=q(%d)=(.-)$')
          if _name and string.lower(_name) == string.lower(n) then
            return unpack({itemNumber, _name, _quality, raidBossKey, dropRate})
          end
        end
      end
    end
  end
  return nil
end

local function HandleSrAdd(bidder, itemName)
  itemName = Trim(itemName)
  if Srs(softReserveSessionName)[bidder] == nil then
    Srs(softReserveSessionName)[bidder] = {}
  end
  local sr = Srs(softReserveSessionName)[bidder]
  local itemNumber, nameFix, _quality, raidBoss, dropRate = ValidateItemName(itemName)
  if itemNumber == nil then
    SendResponse(itemName .. " does not appear to be a valid item name (AtlasLoot).  If this is incorrect, the Loot Master will need to manually input the item name or disable item validation.", bidder)
  else
    if nameFix ~= itemName then
      SendResponse(itemName .. " fixed to " .. nameFix)
      itemName = nameFix
    end
    table.insert(sr, itemName)
    if TableLength(sr) > ChatLootBidder_Store.DefaultMaxSoftReserves then
      local pop = table.remove(sr, 1)
      if not TableContains(sr, pop) then
        SendResponse("You are no longer reserving: " .. pop, bidder)
      end
    end
  end
  ChatLootBidderOptionsFrame_Reload()
end

function ChatFrame_OnEvent(event)
  -- Non-whispers are ignored; Don't react to duplicate whispers (multiple windows, usually)
  if event ~= "CHAT_MSG_WHISPER" or lastWhisper == (arg1 .. arg2) then
    ChatLootBidder_ChatFrame_OnEvent(event)
    return
  end
  lastWhisper = arg1 .. arg2
  local bidder = arg2

  -- Parse string for a item links
  local items, itemIndexEnd = GetItemLinks(arg1)
  local item = items[1]

  -- Get the single item from the session if there is only one
  local singleItem = nil
  if session then
    local itemCount = 0
    for item, _ in pairs(session) do
      itemCount = itemCount + 1
      if itemCount == 1 then
        singleItem = item
      elseif itemCount > 1 then
        singleItem = nil
        break
      end
    end
  end

  -- Handle SR Bids
  local commandlist = SplitBySpace(arg1)
  if (softReserveSessionName ~= nil and string.lower(commandlist[1] or "") == "sr") then
    if not IsInRaid(bidder) then
      SendResponse("You must be in the raid to place a Soft Reserve", bidder)
      return
    end
    if softReserveSessionName == nil then
      SendResponse("There is no Soft Reserve session loaded", bidder)
      return
    end
    -- If we're manually editing the SRs, treat it like being locked for incoming additions
    local softReservesLocked = softReservesLocked or SrEditFrame:IsVisible()
    if TableLength(commandlist) == 1 or softReservesLocked then
      -- skip, query do the query at the end
    elseif commandlist[2] == "clear" or commandlist[2] == "delete" or commandlist[2] == "remove" then
      Srs(softReserveSessionName)[bidder] = nil
    elseif item ~= nil then
      local _i
      for _,_i in pairs(items) do
        HandleSrAdd(bidder, ParseItemNameFromItemLink(_i))
      end
    else
      table.remove(commandlist, 1)
      HandleSrAdd(bidder, table.concat(commandlist, " "))
    end
    HandleSrQuery(bidder)
  -- Check for bids with or without item link
  elseif session ~= nil and (item ~= nil or singleItem ~= nil) then
    -- If no item linked but there's only one item in session, check for valid bid type
    if item == nil and singleItem then
      local firstWord = string.lower(commandlist[1] or "")
      if firstWord == "bid" or firstWord == "ms" or firstWord == "os" or firstWord == "tmog" or firstWord == "stock" then
        item = singleItem
        -- Reconstruct the bid part more safely
        if commandlist[2] then
          arg1 = firstWord .. " " .. commandlist[2]
        else
          arg1 = firstWord
        end
        itemIndexEnd = 0
      end
    end

    local itemSession = session[item]
    if itemSession == nil then
      local invalidBid = "There is no active loot session for " .. (item or "that item")
      SendResponse(invalidBid, bidder)
      return
    end
    
    if not IsInRaid(arg2) then
      local invalidBid = "You must be in the raid to send a bid on " .. item
      SendResponse(invalidBid, bidder)
      return
    end
    local mainSpec = itemSession["ms"]
    local offSpec = itemSession["os"]
    local roll = itemSession["roll"]
    local cancel = itemSession["cancel"]
    local notes = itemSession["notes"]

    local bid = SplitBySpace(string.sub(arg1, itemIndexEnd + 1))
    local tier = bid[1] and string.lower(bid[1]) or nil
    local amt = bid[2] and string.lower(bid[2]) or nil

    if IsValidTier(tier) then
      Debug("Processing valid tier: " .. tier .. " from " .. bidder)
      
      -- Validate bid tier based on mode
      if tier == "bid" then
        if sessionMode ~= "DKP" then
          SendResponse("Invalid bid type for MSOS mode. Format: '[item-link] ms' or '[item-link] os' or '[item-link] tmog' or '[item-link] stock'", bidder)
          return
        end
        -- Process DKP bid
        local numAmt = tonumber(amt)
        if numAmt == nil or numAmt < ChatLootBidder_Store.MinBid then
          SendResponse(InvalidBidSyntax(item), bidder)
          return
        end

        -- Round up to nearest 10
        numAmt = RoundUpToTen(numAmt)

        -- Check if bid exceeds maximum
        if numAmt > ChatLootBidder_Store.MaxBid then
          SendResponse("Your bid of " .. numAmt .. " exceeds the maximum bid of " .. ChatLootBidder_Store.MaxBid, bidder)
          return
        end

        -- Find current highest bid
        local highestBid = ChatLootBidder_Store.MinBid
        for _, existingBid in pairs(itemSession["bid"] or {}) do
          if tonumber(existingBid) > highestBid then
            highestBid = tonumber(existingBid)
          end
        end

        -- Check if bid is higher than highest bid
        if numAmt <= highestBid then
          SendResponse("Your bid must be higher than the current highest bid of " .. highestBid .. " DKP", bidder)
          return
        end

        -- Check if bid is higher than player's current bid
        if itemSession["bid"][bidder] and itemSession["bid"][bidder] >= numAmt then
          SendResponse("Your current bid of " .. itemSession["bid"][bidder] .. " is higher than " .. numAmt, bidder)
          return
        end

        -- Clear any existing non-DKP bids when placing a DKP bid
        if itemSession["ms"] then itemSession["ms"][bidder] = nil end
        if itemSession["os"] then itemSession["os"][bidder] = nil end
        if itemSession["tmog"] then itemSession["tmog"][bidder] = nil end
        if itemSession["stock"] then itemSession["stock"][bidder] = nil end
        if itemSession["roll"] then itemSession["roll"][bidder] = nil end

        itemSession["bid"][bidder] = numAmt
        received = PlayerWithClassColor(bidder) .. " bid " .. numAmt .. " DKP for " .. item .. AppendNote(notes[bidder] or "")

      elseif tier == "ms" then
        if itemSession["bid"] and itemSession["bid"][bidder] then
          SendResponse("You already have a DKP bid for " .. item .. ". Use '[item-link] cancel' to cancel your current bid first.", bidder)
          return
        end
        -- Clear other non-DKP bids when placing MS bid
        if itemSession["os"] then itemSession["os"][bidder] = nil end
        if itemSession["tmog"] then itemSession["tmog"][bidder] = nil end
        if itemSession["stock"] then itemSession["stock"][bidder] = nil end
        
        mainSpec[bidder] = 1
        roll[bidder] = roll[bidder] or -1
        received = PlayerWithClassColor(bidder) .. " bid Main Spec for " .. item .. AppendNote(notes[bidder] or "")

      elseif tier == "os" then
        if itemSession["bid"] and itemSession["bid"][bidder] then
          SendResponse("You already have a DKP bid for " .. item .. ". Use '[item-link] cancel' to cancel your current bid first.", bidder)
          return
        end
        -- Clear other non-DKP bids when placing OS bid
        if itemSession["ms"] then itemSession["ms"][bidder] = nil end
        if itemSession["tmog"] then itemSession["tmog"][bidder] = nil end
        if itemSession["stock"] then itemSession["stock"][bidder] = nil end
        
        offSpec[bidder] = 1
        roll[bidder] = roll[bidder] or -1
        received = PlayerWithClassColor(bidder) .. " bid Off Spec for " .. item .. AppendNote(notes[bidder] or "")

      elseif tier == "tmog" then
        if itemSession["bid"] and itemSession["bid"][bidder] then
          SendResponse("You already have a DKP bid for " .. item .. ". Use '[item-link] cancel' to cancel your current bid first.", bidder)
          return
        end
        -- Clear other non-DKP bids when placing TMOG bid
        if itemSession["ms"] then itemSession["ms"][bidder] = nil end
        if itemSession["os"] then itemSession["os"][bidder] = nil end
        if itemSession["stock"] then itemSession["stock"][bidder] = nil end
        
        itemSession["tmog"][bidder] = 1
        roll[bidder] = roll[bidder] or -1
        received = PlayerWithClassColor(bidder) .. " bid Transmog for " .. item .. AppendNote(notes[bidder] or "")

      elseif tier == "stock" then
        if itemSession["bid"] and itemSession["bid"][bidder] then
          SendResponse("You already have a DKP bid for " .. item .. ". Use '[item-link] cancel' to cancel your current bid first.", bidder)
          return
        end
        -- Clear other non-DKP bids when placing STOCK bid
        if itemSession["ms"] then itemSession["ms"][bidder] = nil end
        if itemSession["os"] then itemSession["os"][bidder] = nil end
        if itemSession["tmog"] then itemSession["tmog"][bidder] = nil end
        
        itemSession["stock"][bidder] = 1
        roll[bidder] = roll[bidder] or -1
        received = PlayerWithClassColor(bidder) .. " bid Stock for " .. item .. AppendNote(notes[bidder] or "")

      elseif tier == "cancel" then
        cancel[bidder] = true
        received = PlayerWithClassColor(bidder) .. " cancelled their bid for " .. item
      end

      -- Send response to bidder and announce bid
      MessageBidChannel(received)
      return
    else
      SendResponse(InvalidBidSyntax(item), bidder)
      return
    end
  else
    ChatLootBidder_ChatFrame_OnEvent(event)
  end
end

function ChatLootBidder:StartSessionButtonShown()
  ChatLootBidder:Show()
  startSessionButton:Show()
  clearSessionButton:Show()
end

function ChatLootBidder:EndSessionButtonShown()
  ChatLootBidder:Show()
  startSessionButton:Hide()
  clearSessionButton:Hide()
  endSessionButton:Show()
  ChatLootBidder:SetHeight(50)
  for i = 1, 8 do
    local stageItem = getglobal(ChatLootBidder:GetName() .. "Item"..i)
    local unstageButton = getglobal(ChatLootBidder:GetName() .. "UnstageButton"..i)
    unstageButton:Hide()
    stageItem:SetText("")
    stageItem:Hide()
  end
end

function ChatLootBidder:RedrawStage()
  local i=1, k, show
  for k, show in pairs(stage or {}) do
    if show then
      if i == 9 then Error("You may only stage up to 8 items.  Use /loot clear [itm] to clear specific items or /clear to wipe it clean."); return end
      if not ChatLootBidder:IsVisible() then
        ChatLootBidder:StartSessionButtonShown()
      end
      local stageItem = getglobal(ChatLootBidder:GetName() .. "Item"..i)
      local unstageButton = getglobal(ChatLootBidder:GetName() .. "UnstageButton"..i)
      unstageButton:Show()
      stageItem:SetText(k)
      stageItem:Show()
      i = i + 1
    end
  end
  if i == 1 then -- if none shown
    ChatLootBidder:Hide()
  else
    ChatLootBidder:SetHeight(240-(160-i*20))
    for i = i, 8 do
      local stageItem = getglobal(ChatLootBidder:GetName() .. "Item"..i)
      local unstageButton = getglobal(ChatLootBidder:GetName() .. "UnstageButton"..i)
      unstageButton:Hide()
      stageItem:SetText("")
      stageItem:Hide()
    end
  end
  getglobal(ChatLootBidder:GetName() .. "HeaderString"):SetText(ChatLootBidder_Store.DefaultSessionMode .. " Mode")
end

function ChatLootBidder:Stage(i, force)
  stage = stage or {}
  if force or stage[i] == nil then
    stage[i] = true
  end
end

function ChatLootBidder.CHAT_MSG_SYSTEM(msg)
  if session == nil then return end
  local _, _, name, roll, low, high = string.find(msg, rollRegex)
	if name then
    if tonumber(low) > 1 or tonumber(high) > 100 then return end -- invalid roll
    if name == me and tonumber(high) <= 40 then return end -- master looter using pfUI's random loot distribution
    local existingWhy = ""
    for item,itemSession in pairs(session) do
      local existingRoll = itemSession["roll"][name]
      if existingRoll == -1 or ((1 == getn(GetKeys(session))) and existingRoll == nil) then
        itemSession["roll"][name] = tonumber(roll)
        SendResponse("Your roll of " .. roll .. " been recorded for " .. item, name)
        return
      elseif (existingRoll or 0) > 0 then
        existingWhy = existingWhy .. "Your roll of " .. existingRoll .. " has already been recorded for " .. item .. ". "
      end
    end
    if string.len(existingWhy) > 0 then
      SendResponse("Ignoring your roll of " .. roll .. ". " .. existingWhy, name)
    elseif sessionMode == "DKP" then
      SendResponse("Ignoring your roll of " .. roll .. ". You must first declare that you are rolling on an item first: '/w " .. me .. " [item-link] roll'", name)
    else
      SendResponse("Ignoring your roll of " .. roll .. ". You must bid on an item before rolling on it: '/w " .. me .. " [item-link] ms/os/tmog/stock'", name)
    end
	end
end

function ChatLootBidder.ADDON_LOADED()
  LoadVariables()
  InitSlashCommands()
  -- Load Options.xml values
  LoadText()
  LoadValues()
  this:UnregisterEvent("ADDON_LOADED")
end

function ChatLootBidder.CHAT_MSG_ADDON(addonTag, stringMessage, channel, sender)
  if VersionUtil:CHAT_MSG_ADDON(addonName, function(ver)
    Message("New version " .. ver .. " of " .. addonTitle .. " is available! Upgrade now at " .. addonNotes)
  end) then return end
end

function ChatLootBidder.PARTY_MEMBERS_CHANGED()
  VersionUtil:PARTY_MEMBERS_CHANGED(addonName)
end

function ChatLootBidder.PLAYER_ENTERING_WORLD()
  VersionUtil:PLAYER_ENTERING_WORLD(addonName)
  if ChatLootBidder_Store.Point and getn(ChatLootBidder_Store.Point) == 4 then
    ChatLootBidder:SetPoint(ChatLootBidder_Store.Point[1], "UIParent", ChatLootBidder_Store.Point[2], ChatLootBidder_Store.Point[3], ChatLootBidder_Store.Point[4])
  end
end

function ChatLootBidder.PLAYER_LEAVING_WORLD()
  local point, _, relativePoint, xOfs, yOfs = ChatLootBidder:GetPoint()
  ChatLootBidder_Store.Point = {point, relativePoint, xOfs, yOfs}
end

function ChatLootBidder.LOOT_OPENED()
  if session ~= nil then return end
  if not ChatLootBidder_Store.AutoStage then return end
  if not IsMasterLooterSet() or not IsRaidAssistant(me) then return end
  local i
  for i=1, GetNumLootItems() do
    local lootIcon, lootName, lootQuantity, rarity, locked, isQuestItem, questId, isActive = GetLootSlotInfo(i)
    -- print(lootIcon, lootName, lootQuantity, rarity, locked, isQuestItem, questId, isActive)
    if rarity >= ChatLootBidder_Store.MinRarity and rarity <= ChatLootBidder_Store.MaxRarity then
      ChatLootBidder:Stage(GetLootSlotLink(i))
    end
  end
  ChatLootBidder:RedrawStage()
end


-- [00:00]Autozhot: Autozhot - Band of Accuria
local function ParseRaidResFly(text)
  local line, t = nil, {}
  for line in gfind(text, '([^\n]+)') do
    local _, _, name, item = string.find(line, "^.-: ([%a]-) . (.-)$")
    name = Trim(name)
    item = Trim(item)
    if t[name] == nil then t[name] = {} end
    table.insert(t[name], item)
  end
  return t
end

-- Autozhot ; Band of Accuria ; Giantstalker Boots
local function ParseSemicolon(text)
  local t, line, part, k, v = {}, nil, nil, nil, {}
  for line in gfind(text, '([^\n]+)') do
    for part in gfind(line, '([^;]+)') do
      if k == nil then
        k = Trim(part)
      else
        local sr = Trim(part)
        table.insert(v, sr)
      end
    end
    t[k] = v
    k = nil
    v = {}
  end
  return t
end

function ValidateFixAndWarn(t)
  local k,k2,v,i,len
  for k,v in pairs(t) do
    len = getn(v)
    if len > ChatLootBidder_Store.DefaultMaxSoftReserves then
      Error(k .. " has " .. len .. " soft reserves loaded (max=" .. ChatLootBidder_Store.DefaultMaxSoftReserves .. ")")
    end
    for k2,i in pairs(v) do
      local itemNumber, nameFix, _, _, _ = ValidateItemName(i)
      if itemNumber == nil then
        Error(i .. " does not appear to be a valid item name (AtlasLoot)")
      elseif nameFix ~= i then
        Message(i .. " fixed to " .. nameFix)
        v[k2] = nameFix
      end
    end
  end
end

function ChatLootBidder:DecodeAndSave(text, parent)
  local encoding = SrEditFrameHeaderString:GetText()
  local t
  if encoding == "json" then
    t = json.decode(text)
  elseif encoding == "csv" then
    t = UnFlatten(csv:fromCSV(text))
  elseif encoding == "raidresfly" then
    t = ParseRaidResFly(text)
  elseif encoding == "semicolon" then
    t = ParseSemicolon(text)
  else
    Error("No encoding provided")
    return
  end
  ValidateFixAndWarn(t)
  ChatLootBidder_Store.SoftReserveSessions[softReserveSessionName] = t
  ChatLootBidderOptionsFrame_Reload()
  parent:Hide()
end

--
-- Taken from https://github.com/laytya/WowLuaVanilla which took it from SuperMacro
function ChatLootBidder:OnVerticalScroll(scrollFrame)
	local offset = scrollFrame:GetVerticalScroll();
	local scrollbar = getglobal(scrollFrame:GetName().."ScrollBar");

	scrollbar:SetValue(offset);
	local min, max = scrollbar:GetMinMaxValues();
	local display = false;
	if ( offset == 0 ) then
	    getglobal(scrollbar:GetName().."ScrollUpButton"):Disable();
	else
	    getglobal(scrollbar:GetName().."ScrollUpButton"):Enable();
	    display = true;
	end
	if ((scrollbar:GetValue() - max) == 0) then
	    getglobal(scrollbar:GetName().."ScrollDownButton"):Disable();
	else
	    getglobal(scrollbar:GetName().."ScrollDownButton"):Enable();
	    display = true;
	end
	if ( display ) then
		scrollbar:Show();
	else
		scrollbar:Hide();
	end
end
