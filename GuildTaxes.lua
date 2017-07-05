--
-- GuildTaxes - keep your guild bank full
-- Author: Неогик@Галакронд
--

-- Addon settings
local VERSION = "@project-version@"
local DEVELOPMENT = false
local SLASH_COMMAND = "gt"
local MESSAGE_PREFIX = "GT"

local DEFAULTS = {
	realm = {
		history = {},
		status = {}
	},
	profile = {
		version = 0,
		debug = false,
		verbose = false,
		logging = true,
		autopay = true,
	},
	char = {
		rate = 0.10,
	},
}


-- Instantiate
GuildTaxes = LibStub("AceAddon-3.0"):NewAddon("GuildTaxes", "AceConsole-3.0", "AceEvent-3.0", "AceComm-3.0", "AceHook-3.0")

getmetatable(GuildTaxes).__tostring = function (self)
	return GT_CHAT_PREFIX
end


--------------------------------------------------------------------------------
-- Initialization
--------------------------------------------------------------------------------
function GuildTaxes:OnInitialize()
	-- User's settings
	self.db = LibStub("AceDB-3.0"):New("GuildTaxesDB", DEFAULTS, true)

	-- Local state vars
	self.guildId = nil
	self.guildName = nil
	self.guildRealm = nil
	self.playerMoney = 0
	self.isMailOpened = false
	self.isBankOpened = false
	self.isPayingTax = false
	self.numberMembers = nil
	self.numberMembersOnline = nil
end


--------------------------------------------------------------------------------
-- Utilites
--------------------------------------------------------------------------------
function GuildTaxes:HistoryKey(year, month)
	return year .. "-" .. month
end

--------------------------------------------------------------------------------
function GuildTaxes:TimeStamp(year, month, day, hour, minute, second)
	if second == nil then
		second = 0
	end
	local dict = {
		year = year,
		month = month,
		day = day,
		hour = hour,
		minute = minute,
		second = 0
	}
	return time(dict)
end

--------------------------------------------------------------------------------
function GuildTaxes:Debug(message, n)
	if (DEVELOPMENT or self.db.profile.debug) then
		self:Print("|cff999999" .. message .. "|r")
	end
end

--------------------------------------------------------------------------------
function GuildTaxes:PrintGeneralInfo()
	if self.guildId then
		self:Printf(GT_CHAT_GENERAL_INFO, 100 * self.db.char.rate, self.guildName, self.guildRealm)
	end
end

--------------------------------------------------------------------------------
function GuildTaxes:PrintTax()
	local message
	if self:GetTax() >= 1 then
		message = format(GT_CHAT_TAX, GetCoinTextureString(self:GetTax()))
		if (self.isBankOpened and not self.db.profile.autopay) then
			message = message .. " |Hitem:GuildTaxes:create:|h|cffff8000[" .. GT_CHAT_TAX_CLICK .. "]|r|h"
		end
	else
		message = GT_CHAT_ALL_PAYED
	end
	self:Print(message)
end

--------------------------------------------------------------------------------
function GuildTaxes:PrintTransaction(income, tax)
	if self.db.profile.logging then
		self:Printf(GT_CHAT_TRANSACTION, GetCoinTextureString(income), GetCoinTextureString(tax))
	end
end

--------------------------------------------------------------------------------
function GuildTaxes:PrintPayingTax(tax)
	self:Printf(GT_CHAT_PAYING_TAX, GetCoinTextureString(tax))
end

--------------------------------------------------------------------------------
function GuildTaxes:PrintNothingToPay()
	self:Print(GT_CHAT_NOTHING_TO_PAY)
end

--------------------------------------------------------------------------------
function GuildTaxes:GetTax()
	return self.db.char[self.guildId].tax
end

--------------------------------------------------------------------------------
function GuildTaxes:GetRate()
	return GuildTaxes.db.char.rate
end

--------------------------------------------------------------------------------
function GuildTaxes:GetGuildName()
	return self.guildName
end

--------------------------------------------------------------------------------
function GuildTaxes:GetGuildDB()
	local guildDB = self.db.realm[self.guildId]
	if not guildDB then
		guildDB = {
			["history"] = {},
			["status"] = {}
		}
		self.db.realm[self.guildId] = guildDB
	end
	return guildDB
end

--------------------------------------------------------------------------------
function GuildTaxes:GetStatusDB()
	return self:GetGuildDB().status
end

--------------------------------------------------------------------------------
function GuildTaxes:GetHistoryDB()
	return self:GetGuildDB().status
end

--------------------------------------------------------------------------------
function GuildTaxes:UpdatePlayerMoney(playerMoney)
	if not playerMoney then
		playerMoney = GetMoney()
	end
	self.playerMoney = playerMoney
end

--------------------------------------------------------------------------------
function GuildTaxes:MigrateDatabase()
	-- Old GuildId
	local oldGuildId = format("%s-%s", self.guildName, self.guildRealm):lower()
	if self.db.char[oldGuildId] then
		self.db.char[self.guildId] = self.db.char[oldGuildId]
		self.db.char[oldGuildId] = nil
	end

	-- Create new char db
	if not self.db.char[self.guildId] then
		self.db.char[self.guildId] = {
			tax = 0;
		}
	end

	-- Migrate amount -> tax
	if self.db.char[self.guildId].amount ~= nil then
		self.db.char[self.guildId].tax = self.db.char[self.guildId].amount
		self.db.char[self.guildId].amount = nil
	end

	-- Create realm data
	if not self.db.realm then
		self.db.realm = {}
	end
	if not self.db.realm[self.guildId] then
		self.db.realm[self.guildId] = {}
	end

	-- Migrate history & status database
	if self.db.char[self.guildId].status ~= nil then
		self.db.realm[self.guildId].status = self.db.char[self.guildId].status
		self.db.char[self.guildId].status = nil
	end
	if self.db.char[self.guildId].history ~= nil then
		self.db.realm[self.guildId].history = self.db.char[self.guildId].history
		self.db.char[self.guildId].history = nil
	end
end

--------------------------------------------------------------------------------
function GuildTaxes:UpdateGuildInfo()
	self:Debug("Update guild info")
	if IsInGuild() then
		if not self.guildId then
			self.guildName, self.guildRealm = GetGuildInfo("player"), GetRealmName()
			if self.guildName and self.guildRealm then
				self.guildId = format("%s - %s", self.guildName, self.guildRealm)
			end
		end
		if self.guildId then
			self:MigrateDatabase()
			self.GUI:UpdatePayedStatus()
		end
	else
		self.guildId = nil
	end
end

--------------------------------------------------------------------------------
function GuildTaxes:UpdateGuildRoster()
	GuildRoster()
end

--------------------------------------------------------------------------------
function GuildTaxes:AccrueTax(income, tax)
	self:Debug("Accrue tax with " .. tax)
	self.db.char[self.guildId].tax = self:GetTax() + tax
	self:PrintTransaction(income, tax)
	self.GUI:UpdatePayedStatus()
end

--------------------------------------------------------------------------------
function GuildTaxes:ReduceTax(tax)
	self:Debug("Reduce tax with " .. tax)
	self.db.char[self.guildId].tax = self:GetTax() - tax
	self.GUI:UpdatePayedStatus()
end

--------------------------------------------------------------------------------
function GuildTaxes:PayTax()
	self:Debug("Paying tax")
	if not self.isBankOpened then
		self:Print(GT_CHAT_OPEN_BANK)
		return
	end
	self.isPayingTax = true
	self:PrintPayingTax(self:GetTax())
	DepositGuildBankMoney(self:GetTax())
	self.GUI:UpdatePayedStatus()
end

--------------------------------------------------------------------------------
function GuildTaxes:UpdateHistoryRecord()
	--Ambiguate
end

--------------------------------------------------------------------------------
function GuildTaxes:SendMessage(data)
	SendAddonMessage(MESSAGE_PREFIX, table.concat(data, "\t"), "GUILD")
end

--------------------------------------------------------------------------------
function GuildTaxes:NotifyStatus(player)
	if self.guildId then
		self:Debug("Notify status")
		local _, month, day, year = CalendarGetDate()
		local hour, minute = GetGameTime()
		local version = GetAddOnMetadata("GuildTaxes", "Version")
		if player == nil then
			player = UnitFullName("player")
		end
		local data = {
			"T",
			version,
			time(),
			player,
			self:GetRate(),
			self:GetTax()
		}
		self:SendMessage(data)
	end
end

--------------------------------------------------------------------------------
function GuildTaxes:PurgeOldData()
	-- TODO: purge old guild info, if guild chnaged
	-- TODO: purge old history records
	-- TODO: purge player's data that left guild
end


--------------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------------
GuildTaxes.commands = {
	[""]       = "OnGUICommand";
	["sync"]   = "OnSyncCommand";
	["status"] = "OnPrintTaxCommand";
}

--------------------------------------------------------------------------------
function GuildTaxes:OnPrintTaxCommand()
	self:PrintTax()
end

--------------------------------------------------------------------------------
function GuildTaxes:OnGUICommand()
	self.GUI:Toggle()
	if self.GUI:IsShown() then
		self.GUI:RefreshTable()
	end
end

--------------------------------------------------------------------------------
function GuildTaxes:OnSyncCommand()
	self:SendMessage({"S"})
end

--------------------------------------------------------------------------------
function GuildTaxes:OnSlashCommand(input, val)
	local args = {}
	for word in input:gmatch("%S+") do
		table.insert(args, word)
	end

	local _, operation = next(args)
	if operation == nil then
		operation = ""
	end

	if self.commands[operation] then
		self[self.commands[operation]](self)
	else
		self:Debug("Unknown command: " .. operation)
	end
end


--------------------------------------------------------------------------------
-- Communication events
--------------------------------------------------------------------------------
GuildTaxes.events = {

	-- Sync command
	["S"] = function (sender, ...)
		GuildTaxes:Debug("Sync command received")
		GuildTaxes:NotifyStatus()
	end,

	-- Player's status
	["T"] = function (sender, version, timestamp, player, rate, tax)
		GuildTaxes:Debug("Receive status message for " .. tostring(player))
		timestamp = tonumber(timestamp)
		local statusDB = GuildTaxes:GetStatusDB()
		if statusDB[player] == nil then
			statusDB[player] = {}
		end
		playerDB = statusDB[player]
		if playerDB.timestamp == nil or playerDB.timestamp < timestamp then
			GuildTaxes:Debug("Updating status for " .. player)
			playerDB.timestamp = timestamp
			playerDB.version = version
			playerDB.rate = rate
			playerDB.tax = tax
			if GuildTaxes.GUI.IsShown() then
				GuildTaxes.GUI:RefreshTable()
			end
		end
	end,
}

function GuildTaxes:OnCommReceived(prefix, message, channel, sender)
	if prefix == MESSAGE_PREFIX and message and channel == "GUILD" then
		local data = {}
		for word in string.gmatch(message, "[^\t]+") do
			data[#data + 1] = word
		end
		if #data > 0 then
			local command = table.remove(data, 1)
			local handler = GuildTaxes.events[command]
			if handler then
				handler(sender, unpack(data))
			else
				GuildTaxes:Debug("Unknown command received: ".. command)
			end
		end
	end
end


--------------------------------------------------------------------------------
-- Hyperlink chat handler
--------------------------------------------------------------------------------
function GuildTaxes:ChatFrame_OnHyperlinkShow(chat, link, text, button)
	local command = strsub(link, 1, 4);
	if command == "item" then
		local _, addonName = strsplit(":", link)
		if addonName == "GuildTaxes" then
			local tax = floor(self:GetTax())
			if tax > 0 then
				self:PayTax()
			else
				self:PrintNothingToPay()
			end
		end
	end
end


--------------------------------------------------------------------------------
-- WoW events handlers
--------------------------------------------------------------------------------
function GuildTaxes:PLAYER_LOGIN( ... )
	self:PrintGeneralInfo()
end

function GuildTaxes:PLAYER_ENTERING_WORLD( ... )
	-- Create GUI
	self.GUI:Create()

	-- Update data
	self:UpdatePlayerMoney()
	self:UpdateGuildInfo()
	self:UpdateGuildRoster()
end

--------------------------------------------------------------------------------
function GuildTaxes:PLAYER_MONEY( ... )

	local newPlayerMoney = GetMoney()
	local delta = newPlayerMoney - self.playerMoney

	self:Debug("Player money, delta=" .. tostring(delta))

	if delta > 0 then
		if not self.guildId then
			self:Debug("Not in guild, transaction ignored")
		elseif self.isMailOpened then
			self:Debug("Mailbox is open, transaction ignored")
		elseif self.isBankOpened then
			self:Debug("Guild bank is open, transaction ignored")
		else
			self:AccrueTax(delta, delta * self.db.char.rate)
			self:NotifyStatus()
		end

	elseif self.isBankOpened and self.isPayingTax then
		self:ReduceTax(-delta)
		self.isPayingTax = false
		self:PrintTax()
		self:NotifyStatus()
	else
		self:Debug("Ignoring withdraw")
	end

	self:UpdatePlayerMoney(newPlayerMoney)
end

--------------------------------------------------------------------------------
function GuildTaxes:GUILDBANKFRAME_OPENED( ... )
	self:Debug("Guild bank opened")
	self.isBankOpened = true

	local tax = floor(self:GetTax())
	if tax >= 1 and self.db.profile.autopay then
		self:PayTax()
	else
		self:PrintTax()
	end

end

--------------------------------------------------------------------------------
function GuildTaxes:GUILDBANKFRAME_CLOSED( ... )
	if self.isBankOpened then
		self:Debug("Guild bank closed")
		self.isBankOpened = false
		self.isPayingTax = false
	end
end

--------------------------------------------------------------------------------
function GuildTaxes:MAIL_SHOW( ... )
	self:Debug("Mailbox opened")
	self.isMailOpened = true
end

--------------------------------------------------------------------------------
function GuildTaxes:MAIL_CLOSED( ... )
	if self.isMailOpened then
		self:Debug("Mailbox closed")
		self.isMailOpened = false
	end
end

--------------------------------------------------------------------------------
function GuildTaxes:PLAYER_GUILD_UPDATE(event, unit)
	if unit == "player" then
		self:Debug("Player guild info updated")
		self:UpdateGuildInfo()
	end
end

--------------------------------------------------------------------------------
function GuildTaxes:GUILD_ROSTER_UPDATE( ... )
	local needRefresh = false
	local numMembers, numOnline, _ = GetNumGuildMembers()
	if self.numberMembers ~= numMembers then
		if self.numberMembers ~= nil then
			self:Debug("Number of guild members changed: " .. self.numberMembers .. " -> " .. numMembers)
		end
		self.numberMembers = numMembers
		needRefresh = true
	end
	if self.numberMembersOnline ~= numOnline then
		if self.numberMembersOnline ~= nil then
			self:Debug("Number of online members changed: " .. self.numberMembersOnline .. " -> " .. numOnline)
		end
		self.numberMembersOnline = numOnline
		needRefresh = true
	end
	if needRefresh then
		if self.GUI:IsShown() then
			self.GUI:RefreshTable()
		end
	end
end


--------------------------------------------------------------------------------
-- Register events & commands
--------------------------------------------------------------------------------
GuildTaxes:Hook("ChatFrame_OnHyperlinkShow", true)

GuildTaxes:RegisterComm(MESSAGE_PREFIX)

GuildTaxes:RegisterChatCommand(SLASH_COMMAND, "OnSlashCommand")

GuildTaxes:RegisterEvent("PLAYER_LOGIN")
GuildTaxes:RegisterEvent("PLAYER_ENTERING_WORLD")
GuildTaxes:RegisterEvent("PLAYER_MONEY")
GuildTaxes:RegisterEvent("GUILDBANKFRAME_OPENED")
GuildTaxes:RegisterEvent("GUILDBANKFRAME_CLOSED")
GuildTaxes:RegisterEvent("MAIL_SHOW")
GuildTaxes:RegisterEvent("MAIL_CLOSED")
GuildTaxes:RegisterEvent("PLAYER_GUILD_UPDATE")
GuildTaxes:RegisterEvent("GUILD_ROSTER_UPDATE")
