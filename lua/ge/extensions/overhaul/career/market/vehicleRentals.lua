-- Player vehicle rentals via Marketplace: list, NPC offers, prepaid terms, return damage.
local M = {}

local ensureDir = require("overhaul/lib/save/ensureDir")
local phoneLayout = require("overhaul/lib/phone/layoutOwner")
local financeMeta = require("overhaul/lib/finance/metadata")

local SIM_SECONDS_PER_GAME_DAY = require("overhaul/lib/career/gameTime").SIM_SECONDS_PER_GAME_DAY
local DAILY_RATE_FRACTION = 0.01
local ASK_SCALE_MIN = 0.70
local ASK_SCALE_MAX = 1.50
local MIN_TERM_DAYS = 1
local MAX_TERM_DAYS = 7
local DEPOSIT_DAYS = 2
local TIME_BETWEEN_OFFERS_BASE = 95
local OFFER_TTL = 500
local OFFER_POLL_INTERVAL_S = 5
local UPDATE_STEP_S = 5
local SAVE_DIR = "/career/rls_career"
local SAVE_FILE = SAVE_DIR .. "/vehicleRentals.json"

local state = {
  listings = {}, -- [inventoryId] = listing
  active = {}, -- [inventoryId] = rental
}
local accumulatedSimTime = 0
local updateTimer = 0
local offerUpdateAccumulator = 0

local function notifyChanged()
  guihooks.trigger("vehicleRentals:updated")
  guihooks.trigger("marketplaceListingsUpdated")
end

local function fireNotif(channel, title, message, meta)
  local layout = phoneLayout.get()
  if layout and layout.fireNotification then
    layout.fireNotification(channel, {
      title = title,
      message = message,
      meta = meta,
      kind = "invite",
      ttl = 8,
      source = "Marketplace",
      sound = { soundClass = "AudioGui", type = "event:>UI>Missions>Info_Open" },
    })
  end
end

local function getVehicle(inventoryId)
  if not overhaul_career_garage_inventory then return nil end
  local vehicles = overhaul_career_garage_inventory.getVehicles()
  return vehicles and vehicles[inventoryId]
end

local function marketSellValue(inventoryId)
  if overhaul_career_market_valueCalculator and overhaul_career_market_valueCalculator.getInventoryVehicleSellValue then
    local v = overhaul_career_market_valueCalculator.getInventoryVehicleSellValue(inventoryId)
    if v and v > 0 then return math.floor(v + 0.5) end
  end
  return 0
end

local function marketDailyRate(inventoryId)
  return math.max(25, math.floor(marketSellValue(inventoryId) * DAILY_RATE_FRACTION + 0.5))
end

local function depositFor(marketDaily)
  return math.floor((marketDaily or 0) * DEPOSIT_DAYS + 0.5)
end

local function lerp(a, b, t) return a + (b - a) * t end
local function inverseLerp(a, b, v)
  if b == a then return 0 end
  return (v - a) / (b - a)
end

local function offerTimeMultiplierForRatio(marketRatio)
  if marketRatio >= 0.98 and marketRatio <= 1.1 then return 1 end
  if marketRatio < 0.98 then
    local t = math.max(0, math.min(1, inverseLerp(0.98, 0.85, marketRatio)))
    return lerp(1, 0.4, t)
  end
  if marketRatio > 1.1 then
    local t = math.max(0, math.min(1, inverseLerp(1.1, 1.5, marketRatio)))
    return lerp(1, 4.0, t)
  end
  return 1
end

local function scheduleNextOffer(listing, timeNow)
  local mult = listing.offerTimeMultiplier or 1
  listing.timeOfNextOffer = timeNow + (TIME_BETWEEN_OFFERS_BASE * mult)
    + (math.random(-60, 60) / 100 * TIME_BETWEEN_OFFERS_BASE * mult)
end

local function isMarketplaceListed(inventoryId)
  if overhaul_career_market_marketplace and overhaul_career_market_marketplace.findVehicleListing then
    return overhaul_career_market_marketplace.findVehicleListing(inventoryId) ~= nil
  end
  return false
end

local function rentalBlock(vehicle, inventoryId)
  if not vehicle then return "missing" end
  if vehicle.owned ~= true then return "notOwned" end
  if vehicle.loanType then return "loaner" end
  if vehicle.listedForAuction then return "listed" end
  if vehicle.timeToAccess and vehicle.delayReason ~= "rentedOut" then return "unavailable" end
  if vehicle.rentedOut or state.active[inventoryId] then return "alreadyRented" end
  if state.listings[inventoryId] then return "alreadyListed" end
  if isMarketplaceListed(inventoryId) then return "listedForSale" end
  local current = overhaul_career_garage_inventory.getCurrentVehicle and overhaul_career_garage_inventory.getCurrentVehicle()
  if current and tostring(current) == tostring(inventoryId) then return "entered" end
  if type(vehicle.location) == "string" and vehicle.location:find("freightPickup:", 1, true) == 1 then
    return "freight"
  end
  if overhaul_career_logistics_general and overhaul_career_logistics_general.allowRemoval then
    local ok = overhaul_career_logistics_general.allowRemoval(inventoryId)
    if ok == false then return "freight" end
  end
  if overhaul_career_market_auction_consignment and overhaul_career_market_auction_consignment.saleBlockReason then
    local reason = overhaul_career_market_auction_consignment.saleBlockReason(inventoryId, vehicle)
    if reason and reason ~= "listed" then return reason end
  end
  return nil
end

local function canList(inventoryId)
  local vehicle = getVehicle(inventoryId)
  local reason = rentalBlock(vehicle, inventoryId)
  return reason == nil, reason
end

local function snapshotConditions(vehicle)
  if not vehicle or type(vehicle.partConditions) ~= "table" then return {} end
  return deepcopy(vehicle.partConditions)
end

local function listForRent(inventoryId, askingDaily)
  inventoryId = tonumber(inventoryId) or inventoryId
  local ok, reason = canList(inventoryId)
  if not ok then return false, reason end
  local market = marketDailyRate(inventoryId)
  local ask = tonumber(askingDaily) or market
  local minAsk = math.floor(market * ASK_SCALE_MIN + 0.5)
  local maxAsk = math.floor(market * ASK_SCALE_MAX + 0.5)
  ask = math.max(minAsk, math.min(maxAsk, math.max(25, math.floor((ask + 12) / 25) * 25)))
  local ratio = ask / math.max(1, market)
  local vehicle = getVehicle(inventoryId)
  local now = os.time()
  state.listings[inventoryId] = {
    inventoryId = inventoryId,
    askingDailyRate = ask,
    marketDailyRate = market,
    marketRatio = ratio,
    offerTimeMultiplier = offerTimeMultiplierForRatio(ratio),
    timeOfNextOffer = nil,
    offers = {},
    listedAt = now,
    niceName = vehicle and vehicle.niceName or ("Vehicle " .. tostring(inventoryId)),
    conditionSnapshot = snapshotConditions(vehicle),
  }
  scheduleNextOffer(state.listings[inventoryId], now)
  notifyChanged()
  return true
end

local function removeListing(inventoryId)
  inventoryId = tonumber(inventoryId) or inventoryId
  if not state.listings[inventoryId] then return false end
  state.listings[inventoryId] = nil
  notifyChanged()
  return true
end

local function getListing(inventoryId)
  inventoryId = tonumber(inventoryId) or inventoryId
  return state.listings[inventoryId]
end

local function isListedForRent(inventoryId)
  inventoryId = tonumber(inventoryId) or inventoryId
  return state.listings[inventoryId] ~= nil
end

local function isRentedOut(inventoryId)
  inventoryId = tonumber(inventoryId) or inventoryId
  return state.active[inventoryId] ~= nil
end

local function getPriceGuidance(inventoryId, askingDaily)
  inventoryId = tonumber(inventoryId) or inventoryId
  local market = marketDailyRate(inventoryId)
  local ask = tonumber(askingDaily) or 0
  if market <= 0 or ask <= 0 then return nil end
  local ratio = ask / market
  local tier, label, description = "fair", "Fair", "Normal offer flow."
  if ratio < 0.98 then
    tier, label, description = "low", "Below market", "Faster offers expected."
  elseif ratio > 1.10 then
    tier, label, description = "high", "Over market", "Fewer offers; more lowballs."
  end
  return {
    marketDailyRate = market,
    askingDailyRate = ask,
    marketRatio = ratio,
    tier = tier,
    label = label,
    description = description,
    deposit = depositFor(market),
    offerTimeMultiplier = offerTimeMultiplierForRatio(ratio),
  }
end

local function rewardMoney(amount, label, description)
  if amount <= 0 or not overhaul_career_economy_payment then return false end
  return overhaul_career_economy_payment.reward(
    { money = { amount = amount, canBeNegative = false } },
    financeMeta.tag({ label = label, description = description }, "sale", { vehicleRelated = true }),
    true
  )
end

local function payMoney(amount, label, description)
  if amount <= 0 or not overhaul_career_economy_payment then return false end
  return overhaul_career_economy_payment.pay(
    { money = { amount = amount, canBeNegative = false } },
    financeMeta.tag({ label = label, description = description }, "sale", { vehicleRelated = true })
  )
end

local function clearVehicleFromWorld(inventoryId, vehicle)
  if overhaul_career_garage_inventory.removeVehicleObject then
    overhaul_career_garage_inventory.removeVehicleObject(inventoryId)
  end
  if vehicle then
    vehicle.location = nil
    vehicle.rentedOut = true
    vehicle.delayReason = "rentedOut"
    vehicle.timeToAccess = 999999
    if overhaul_career_garage_inventory.setVehicleDirty then
      overhaul_career_garage_inventory.setVehicleDirty(inventoryId)
    end
  end
end

local function restoreVehicleAccess(inventoryId, vehicle, targetGarageId)
  if not vehicle then return end
  vehicle.rentedOut = nil
  vehicle.delayReason = nil
  vehicle.timeToAccess = nil
  if targetGarageId then
    vehicle.location = targetGarageId
  end
  if overhaul_career_garage_inventory.setVehicleDirty then
    overhaul_career_garage_inventory.setVehicleDirty(inventoryId)
  end
end

local function pickReturnGarage()
  if not overhaul_career_garage_garageManager then return nil end
  local data = overhaul_career_garage_garageManager.getGarageCapacityData and overhaul_career_garage_garageManager.getGarageCapacityData()
  if type(data) ~= "table" then return nil end
  for garageId, info in pairs(data) do
    if info and (info.freeSlots or 0) > 0 then
      return garageId
    end
  end
  return nil
end

local function damageSeverity(termDays, marketRatio)
  -- Higher term / cheaper ask → harsher.
  local cheap = math.max(0, 1.1 - (marketRatio or 1))
  local length = (termDays or 1) / MAX_TERM_DAYS
  local score = cheap * 0.45 + length * 0.35 + math.random() * 0.35
  if score < 0.35 then return "pristine"
  elseif score < 0.55 then return "minor"
  elseif score < 0.75 then return "moderate"
  elseif score < 0.90 then return "heavy"
  end
  return "totaled"
end

local function applyDamageNeverImprove(vehicle, snapshot, severity)
  if not vehicle then return false end
  local parts = vehicle.partConditions
  if type(parts) ~= "table" then
    parts = deepcopy(snapshot or {})
    vehicle.partConditions = parts
  end
  local worsened = false
  local mult = 1
  if severity == "pristine" then mult = 1
  elseif severity == "minor" then mult = 0.97
  elseif severity == "moderate" then mult = 0.88
  elseif severity == "heavy" then mult = 0.70
  else mult = 0.08 end -- totaled — extreme integrity hit (no separate write-off pipeline)

  for path, info in pairs(parts) do
    if type(info) == "table" then
      local snap = snapshot and snapshot[path]
      local floor = 0
      if type(snap) == "table" and snap.integrityValue ~= nil then
        floor = math.min(1, math.max(0, tonumber(snap.integrityValue) or 0))
      end
      if info.integrityValue ~= nil then
        local current = tonumber(info.integrityValue) or 1
        local nextVal = current
        if severity == "pristine" then
          nextVal = math.min(current, floor > 0 and floor or current)
        elseif severity == "totaled" then
          nextVal = 0
        else
          nextVal = math.min(current, current * mult)
          if floor > 0 then nextVal = math.min(nextVal, floor) end
        end
        nextVal = math.max(0, math.min(1, nextVal))
        if nextVal < current - 0.0001 then worsened = true end
        info.integrityValue = nextVal
      end
    end
  end
  if severity == "totaled" then
    vehicle.needsRepair = true
    ui_message("Your rented vehicle was returned totaled. Deposit kept — heavy repairs needed.", 10, "vehicleInventory")
  elseif severity == "heavy" then
    vehicle.needsRepair = true
  end
  return worsened or severity ~= "pristine"
end

local function finishRental(inventoryId, opts)
  opts = opts or {}
  inventoryId = tonumber(inventoryId) or inventoryId
  local rental = state.active[inventoryId]
  if not rental then return false end
  local vehicle = getVehicle(inventoryId)
  local refund = tonumber(opts.prorateRefund) or 0
  if refund > 0 then
    payMoney(refund, "Vehicle rental refund", "Unused rental term refunded to renter")
  end

  local severity = damageSeverity(rental.termDays, rental.marketRatio)
  local worsened = applyDamageNeverImprove(vehicle, rental.conditionSnapshot, severity)
  local keepDeposit = opts.forceKeepDeposit == true or worsened
  if not keepDeposit and rental.deposit and rental.deposit > 0 then
    payMoney(rental.deposit, "Vehicle rental deposit return", "Deposit returned after clean rental")
  elseif keepDeposit then
    fireNotif("marketplace.rentalDamage", opts.forceKeepDeposit and "Renter walked early" or "Rental returned damaged",
      rental.niceName or "Vehicle", "Deposit kept · " .. severity)
  end

  local garageId = pickReturnGarage()
  restoreVehicleAccess(inventoryId, vehicle, garageId)
  state.active[inventoryId] = nil
  if overhaul_career_garage_garageManager and overhaul_career_garage_garageManager.buildGarageSizes then
    overhaul_career_garage_garageManager.buildGarageSizes()
  end
  fireNotif("marketplace.rentalEnded", opts.title or "Rental ended",
    rental.niceName or "Vehicle", severity == "pristine" and "Returned clean" or ("Condition: " .. severity))
  notifyChanged()
  overhaul_career_saveSystem.saveCurrent()
  return true
end

local function computeProrateRefund(rental)
  if not rental then return 0 end
  local elapsed = accumulatedSimTime - (rental.startSimTime or 0)
  local total = (rental.termDays or 1) * SIM_SECONDS_PER_GAME_DAY
  local remainingFrac = math.max(0, 1 - (elapsed / math.max(1, total)))
  return math.floor((rental.prepaidRent or 0) * remainingFrac + 0.5)
end

local function endRentalEarly(inventoryId)
  inventoryId = tonumber(inventoryId) or inventoryId
  local rental = state.active[inventoryId]
  if not rental then return false end
  return finishRental(inventoryId, {
    prorateRefund = computeProrateRefund(rental),
    title = "Rental ended early",
  })
end

local function acceptOffer(inventoryId, offerIndex)
  inventoryId = tonumber(inventoryId) or inventoryId
  local listing = state.listings[inventoryId]
  if not listing or not listing.offers then return false end
  local index = tonumber(offerIndex)
  if not index or index < 1 or index > #listing.offers then return false end
  local offer = listing.offers[index]
  if not offer then return false end
  local vehicle = getVehicle(inventoryId)
  if not vehicle then return false end
  if vehicle.rentedOut or state.active[inventoryId] then return false end

  local daily = tonumber(offer.negotiatedRate or offer.value) or listing.askingDailyRate
  local termDays = math.random(MIN_TERM_DAYS, MAX_TERM_DAYS)
  local marketDaily = listing.marketDailyRate or marketDailyRate(inventoryId)
  local deposit = depositFor(marketDaily)
  local prepaid = math.floor(daily * termDays + 0.5)
  rewardMoney(prepaid + deposit, "Vehicle rental income",
    string.format("Rented out for %d day(s)", termDays))

  local snap = snapshotConditions(vehicle)
  clearVehicleFromWorld(inventoryId, vehicle)
  state.active[inventoryId] = {
    inventoryId = inventoryId,
    agreedDailyRate = daily,
    marketDailyRate = marketDaily,
    marketRatio = listing.marketRatio or 1,
    termDays = termDays,
    prepaidRent = prepaid,
    deposit = deposit,
    startSimTime = accumulatedSimTime,
    endSimTime = accumulatedSimTime + termDays * SIM_SECONDS_PER_GAME_DAY,
    conditionSnapshot = snap,
    niceName = listing.niceName or (vehicle.niceName or tostring(inventoryId)),
    renterName = offer.buyerName or "Renter",
  }
  state.listings[inventoryId] = nil
  fireNotif("marketplace.rentalStarted", "Vehicle rented out",
    state.active[inventoryId].niceName, string.format("$%d for %d day(s)", prepaid, termDays))
  notifyChanged()
  overhaul_career_saveSystem.saveCurrent()
  return true
end

local function declineOffer(inventoryId, offerIndex)
  inventoryId = tonumber(inventoryId) or inventoryId
  local listing = state.listings[inventoryId]
  if not listing or not listing.offers then return false end
  local index = tonumber(offerIndex)
  if not index or index < 1 or index > #listing.offers then return false end
  table.remove(listing.offers, index)
  notifyChanged()
  return true
end

local negotiation = {
  active = false,
  inventoryId = nil,
  offerIndex = nil,
  startingPrice = 0,
  marketValue = 0,
  theirOffer = 0,
  myOffer = nil,
  patience = 0.75,
  status = "initial",
  offerHistory = {},
  opponentName = "Renter",
  opponentQuote = "What's your daily rate?",
  niceName = "",
  thumbnail = "",
  token = 0,
}

local NEGOTIATION_HOOK = "vehicleRentNegotiationData"

local function resetNegotiation()
  negotiation.token = negotiation.token + 1
  negotiation.active = false
  negotiation.inventoryId = nil
  negotiation.offerIndex = nil
  negotiation.startingPrice = 0
  negotiation.marketValue = 0
  negotiation.theirOffer = 0
  negotiation.myOffer = nil
  negotiation.patience = 0.75
  negotiation.status = "initial"
  negotiation.offerHistory = {}
  negotiation.opponentName = "Renter"
  negotiation.opponentQuote = ""
  negotiation.niceName = ""
  negotiation.thumbnail = ""
end

local function getNegotiationState()
  return {
    active = negotiation.active,
    amISelling = true,
    startingPrice = negotiation.startingPrice,
    patience = negotiation.patience,
    myOffer = negotiation.myOffer,
    theirOffer = negotiation.theirOffer,
    thinking = negotiation.status == "thinking" or negotiation.status == "typing",
    status = negotiation.status,
    negotiationStatus = negotiation.status,
    opponentName = negotiation.opponentName,
    opponentQuote = negotiation.opponentQuote,
    vehicleNiceName = negotiation.niceName,
    vehicleThumbnail = negotiation.thumbnail,
    hideMarketValue = false,
    playerStartsNegotiation = false,
    hasVisibleTheirOffer = true,
    purchaseAfterAccept = false,
    purchaseFailureReason = nil,
    offerHistory = negotiation.offerHistory,
    marketValue = negotiation.marketValue,
    isRent = true,
    priceUnit = "/day",
  }
end

local function startNegotiateRentOffer(inventoryId, offerIndex, fromPhone)
  inventoryId = tonumber(inventoryId) or inventoryId
  local listing = state.listings[inventoryId]
  if not listing or not listing.offers then return false end
  local index = tonumber(offerIndex)
  if not index or index < 1 or index > #listing.offers then return false end
  local offer = listing.offers[index]
  if not offer or offer.negotiationPossible == false then return false end

  resetNegotiation()
  negotiation.active = true
  negotiation.inventoryId = inventoryId
  negotiation.offerIndex = index
  negotiation.startingPrice = listing.askingDailyRate or offer.value
  negotiation.marketValue = listing.marketDailyRate or negotiation.startingPrice
  negotiation.theirOffer = offer.negotiatedRate or offer.value
  negotiation.myOffer = negotiation.startingPrice
  negotiation.opponentName = offer.buyerName or "Renter"
  negotiation.niceName = listing.niceName or ("Vehicle " .. tostring(inventoryId))
  negotiation.opponentQuote = "I can do about $" .. tostring(negotiation.theirOffer) .. " a day."
  negotiation.offerHistory = {
    { myOffer = negotiation.myOffer, negotiationStatus = "initial" },
    { theirOffer = negotiation.theirOffer, negotiationStatus = "initial" },
  }
  negotiation.status = "initial"
  if overhaul_career_garage_inventory and overhaul_career_garage_inventory.getVehicleThumbnail then
    negotiation.thumbnail = overhaul_career_garage_inventory.getVehicleThumbnail(inventoryId) or ""
  end
  guihooks.trigger(NEGOTIATION_HOOK, getNegotiationState())
  if fromPhone then
    extensions.ui_router.navigate("phone-marketplace-negotiate")
  end
  return true
end

local function respondToRentOffer(job, token)
  if token ~= negotiation.token or not negotiation.active then return end
  negotiation.status = "thinking"
  guihooks.trigger(NEGOTIATION_HOOK, getNegotiationState())
  job.sleep(0.8 + math.random() * 0.8)
  if token ~= negotiation.token or not negotiation.active then return end
  negotiation.status = "typing"
  guihooks.trigger(NEGOTIATION_HOOK, getNegotiationState())
  job.sleep(0.6 + math.random() * 0.6)
  if token ~= negotiation.token or not negotiation.active then return end

  local ask = negotiation.startingPrice
  local mine = negotiation.myOffer or ask
  local theirs = negotiation.theirOffer
  local market = negotiation.marketValue
  -- Accept if player came down enough; otherwise counter or walk.
  if mine <= theirs * 1.02 then
    negotiation.theirOffer = mine
    negotiation.status = "accepted"
    negotiation.opponentQuote = "Deal — I'll take it at that daily rate."
    table.insert(negotiation.offerHistory, { theirOffer = negotiation.theirOffer, negotiationStatus = "accepted" })
  elseif mine > market * 1.35 then
    negotiation.patience = math.max(0, negotiation.patience - 0.35)
    if negotiation.patience <= 0.05 then
      negotiation.status = "failed"
      negotiation.opponentQuote = "That's too high for a rental. I'm out."
      table.insert(negotiation.offerHistory, { theirOffer = theirs, negotiationStatus = "failed" })
    else
      local counter = math.max(25, math.floor(((theirs + market) / 2 + 12) / 25) * 25)
      negotiation.theirOffer = counter
      negotiation.status = "initial"
      negotiation.opponentQuote = "Best I can do is $" .. tostring(counter) .. "/day."
      table.insert(negotiation.offerHistory, { theirOffer = counter, negotiationStatus = "counter" })
    end
  else
    local mid = math.max(25, math.floor(((mine + theirs) / 2 + 12) / 25) * 25)
    negotiation.theirOffer = mid
    negotiation.patience = math.max(0.1, negotiation.patience - 0.12)
    negotiation.status = "initial"
    negotiation.opponentQuote = "How about $" .. tostring(mid) .. " a day?"
    table.insert(negotiation.offerHistory, { theirOffer = mid, negotiationStatus = "counter" })
  end
  guihooks.trigger(NEGOTIATION_HOOK, getNegotiationState())
end

local function makeNegotiationOffer(price)
  if not negotiation.active then return false end
  local amount = tonumber(price)
  if not amount or amount <= 0 then return false end
  amount = math.max(25, math.floor((amount + 12) / 25) * 25)
  negotiation.myOffer = amount
  table.insert(negotiation.offerHistory, { myOffer = amount, negotiationStatus = "offer" })
  negotiation.status = "thinking"
  guihooks.trigger(NEGOTIATION_HOOK, getNegotiationState())
  local token = negotiation.token
  core_jobsystem.create(function(job)
    respondToRentOffer(job, token)
  end)
  return true
end

local function takeTheirOffer()
  if not negotiation.active then return { ok = false, reason = "No active negotiation." } end
  if not negotiation.theirOffer or negotiation.theirOffer <= 0 then
    return { ok = false, reason = "No offer to accept." }
  end
  local inventoryId = negotiation.inventoryId
  local listing = state.listings[inventoryId]
  if not listing or not listing.offers or not listing.offers[negotiation.offerIndex] then
    resetNegotiation()
    return { ok = false, reason = "This offer is no longer available." }
  end
  listing.offers[negotiation.offerIndex].negotiatedRate = negotiation.theirOffer
  local ok = acceptOffer(inventoryId, negotiation.offerIndex)
  if ok then
    negotiation.status = "accepted"
    guihooks.trigger(NEGOTIATION_HOOK, getNegotiationState())
    resetNegotiation()
    return { ok = true }
  end
  return { ok = false, reason = "Could not start the rental." }
end

local function cancelNegotiation()
  resetNegotiation()
  guihooks.trigger(NEGOTIATION_HOOK, getNegotiationState())
  return true
end

local function dismissNegotiation()
  return cancelNegotiation()
end

local function finishPhonePurchase()
  return false
end

local function negotiateAndAcceptOffer(inventoryId, offerIndex)
  return startNegotiateRentOffer(inventoryId, offerIndex, true)
end

local function generateOffer(inventoryId)
  local listing = state.listings[inventoryId]
  if not listing then return nil end
  local market = listing.marketDailyRate or marketDailyRate(inventoryId)
  local ask = listing.askingDailyRate or market
  local noise = 0.88 + math.random() * 0.18
  local value = market * noise
  local ratio = listing.marketRatio or 1
  if ratio < 0.98 then
    value = math.min(value, ask)
  elseif ratio > 1.1 then
    value = math.min(value, market * (0.90 + math.random() * 0.08))
  else
    value = math.min(value, ask * 1.01)
  end
  value = math.max(25, math.floor((value + 12) / 25) * 25)
  local offer = {
    timestamp = os.time(),
    value = value,
    ttl = OFFER_TTL,
    negotiationPossible = true,
    buyerName = "Renter " .. string.char(64 + math.random(1, 26)),
  }
  table.insert(listing.offers, offer)
  return offer
end

local function generateNewOffers()
  local now = os.time()
  for inventoryId, listing in pairs(state.listings) do
    for i = #(listing.offers or {}), 1, -1 do
      local offer = listing.offers[i]
      if offer and now - (offer.timestamp or now) > (offer.ttl or OFFER_TTL) then
        table.remove(listing.offers, i)
      end
    end
    if not listing.timeOfNextOffer then scheduleNextOffer(listing, now) end
    if listing.timeOfNextOffer and now >= listing.timeOfNextOffer then
      listing.timeOfNextOffer = nil
      local offer = generateOffer(inventoryId)
      if offer then
        fireNotif("marketplace.newRentOffer", "New rental offer",
          listing.niceName or "Vehicle", "$" .. tostring(offer.value) .. "/day")
        notifyChanged()
      end
      scheduleNextOffer(listing, now)
    end
  end
end

local function tickActiveRentals()
  local ids = {}
  for inventoryId in pairs(state.active) do table.insert(ids, inventoryId) end
  for _, inventoryId in ipairs(ids) do
    local rental = state.active[inventoryId]
    if rental then
      if accumulatedSimTime >= (rental.endSimTime or 0) then
        finishRental(inventoryId, { title = "Rental complete" })
      else
        -- Rare NPC early return / walk-away: keep deposit, refund unused rent.
        local elapsed = accumulatedSimTime - (rental.startSimTime or 0)
        local total = math.max(1, (rental.endSimTime or 0) - (rental.startSimTime or 0))
        if elapsed > total * 0.25 and not rental.walkChecked and math.random() < 0.02 then
          rental.walkChecked = true
          finishRental(inventoryId, {
            title = "Renter returned early",
            prorateRefund = computeProrateRefund(rental),
            forceKeepDeposit = true,
          })
        else
          local vehicle = getVehicle(inventoryId)
          if vehicle and vehicle.rentedOut then
            vehicle.timeToAccess = 999999
            vehicle.delayReason = "rentedOut"
          end
        end
      end
    end
  end
end

local function onUpdate(_dtReal, dtSim)
  if not overhaul_career_career or not overhaul_career_career.isActive() then return end
  accumulatedSimTime = accumulatedSimTime + (dtSim or 0)
  updateTimer = updateTimer + (dtSim or 0)
  offerUpdateAccumulator = offerUpdateAccumulator + (dtSim or 0)
  if offerUpdateAccumulator >= OFFER_POLL_INTERVAL_S then
    offerUpdateAccumulator = 0
    generateNewOffers()
  end
  if updateTimer < UPDATE_STEP_S then return end
  updateTimer = 0
  tickActiveRentals()
end

local function getListings()
  local result = {}
  for inventoryId, listing in pairs(state.listings) do
    local entry = deepcopy(listing)
    entry.inventoryId = inventoryId
    entry.offerCount = listing.offers and #listing.offers or 0
    table.insert(result, entry)
  end
  return result
end

local function getActiveRentals()
  local result = {}
  for inventoryId, rental in pairs(state.active) do
    local entry = deepcopy(rental)
    entry.inventoryId = inventoryId
    entry.secondsRemaining = math.max(0, (rental.endSimTime or 0) - accumulatedSimTime)
    table.insert(result, entry)
  end
  return result
end

local function getListingOffersData(inventoryId)
  inventoryId = tonumber(inventoryId) or inventoryId
  local listing = state.listings[inventoryId]
  if not listing then return nil end
  local offers = {}
  for index, offer in ipairs(listing.offers or {}) do
    table.insert(offers, {
      index = index,
      value = offer.value,
      negotiatedRate = offer.negotiatedRate,
      buyerName = offer.buyerName or "Renter",
      timestamp = offer.timestamp,
      negotiationPossible = offer.negotiationPossible ~= false,
    })
  end
  return {
    inventoryId = inventoryId,
    niceName = listing.niceName,
    askingDailyRate = listing.askingDailyRate,
    marketDailyRate = listing.marketDailyRate,
    offers = offers,
  }
end

local function getEligibility(inventoryId)
  inventoryId = tonumber(inventoryId) or inventoryId
  local ok, reason = canList(inventoryId)
  local market = marketDailyRate(inventoryId)
  return {
    canList = ok,
    reason = reason,
    marketDailyRate = market,
    minAsk = math.floor(market * ASK_SCALE_MIN + 0.5),
    maxAsk = math.floor(market * ASK_SCALE_MAX + 0.5),
    deposit = depositFor(market),
    isListedForRent = isListedForRent(inventoryId),
    isRentedOut = isRentedOut(inventoryId),
  }
end

local function loadState()
  local _, currentSavePath = overhaul_career_saveSystem.getCurrentProfile()
  if not currentSavePath then return end
  local data = jsonReadFile(currentSavePath .. SAVE_FILE)
  if type(data) == "table" then
    state.listings = data.listings or {}
    state.active = data.active or {}
    accumulatedSimTime = data.simTime or 0
  end
end

local function saveState(currentSavePath, writer)
  if not currentSavePath then
    local _, profilePath = overhaul_career_saveSystem.getCurrentProfile()
    currentSavePath = profilePath
    if not currentSavePath then return end
  end
  ensureDir.directory(writer, currentSavePath .. SAVE_DIR)
  overhaul_career_saveSystem.jsonWriteFileSafe(currentSavePath .. SAVE_FILE, {
    listings = state.listings,
    active = state.active,
    simTime = accumulatedSimTime,
  }, true)
end

local function onOverhaulSaveCurrentProfile(currentSavePath, _, writer)
  writer = writer or overhaul_career_saveSystem.getSaveWriter()
  saveState(currentSavePath, writer)
end

local function onOverhaulVehicleRemoved(inventoryId)
  inventoryId = tonumber(inventoryId) or inventoryId
  state.listings[inventoryId] = nil
  state.active[inventoryId] = nil
end

local function onExtensionLoaded()
  loadState()
end

local function reapplyActiveLocks()
  for inventoryId, rental in pairs(state.active) do
    local vehicle = getVehicle(inventoryId)
    if vehicle then
      vehicle.rentedOut = true
      vehicle.delayReason = "rentedOut"
      vehicle.timeToAccess = 999999
      vehicle.location = nil
      if overhaul_career_garage_inventory.setVehicleDirty then
        overhaul_career_garage_inventory.setVehicleDirty(inventoryId)
      end
    else
      -- Vehicle gone; drop orphan rental.
      state.active[inventoryId] = nil
    end
  end
end

local function onCareerActivated()
  local _, currentSavePath = overhaul_career_saveSystem.getCurrentProfile()
  if not currentSavePath then return end
  if FS:fileExists(currentSavePath .. SAVE_FILE) then
    loadState()
  else
    state = { listings = {}, active = {} }
    accumulatedSimTime = 0
  end
  reapplyActiveLocks()
end

M.listForRent = listForRent
M.removeListing = removeListing
M.getListing = getListing
M.isListedForRent = isListedForRent
M.isRentedOut = isRentedOut
M.getPriceGuidance = getPriceGuidance
M.acceptOffer = acceptOffer
M.declineOffer = declineOffer
M.negotiateAndAcceptOffer = negotiateAndAcceptOffer
M.startNegotiateRentOffer = startNegotiateRentOffer
M.makeNegotiationOffer = makeNegotiationOffer
M.takeTheirOffer = takeTheirOffer
M.cancelNegotiation = cancelNegotiation
M.dismissNegotiation = dismissNegotiation
M.finishPhonePurchase = finishPhonePurchase
M.getNegotiationState = getNegotiationState
M.endRentalEarly = endRentalEarly
M.getListings = getListings
M.getActiveRentals = getActiveRentals
M.getListingOffersData = getListingOffersData
M.getEligibility = getEligibility
M.marketDailyRate = marketDailyRate
M.rentalBlock = rentalBlock

M.onUpdate = onUpdate
M.onOverhaulSaveCurrentProfile = onOverhaulSaveCurrentProfile
M.onOverhaulVehicleRemoved = onOverhaulVehicleRemoved
M.onExtensionLoaded = onExtensionLoaded
M.onCareerActivated = onCareerActivated

return M
