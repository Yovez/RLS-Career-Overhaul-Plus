-- Player-as-landlord property rentals: list owned garages for rent, NPC offers, leases, payments.
local M = {}

local propertyMoneyFactory = require("overhaul/career/garage/property/money")
local ensureDir = require("overhaul/lib/save/ensureDir")
local phoneLayout = require("overhaul/lib/phone/layoutOwner")

local SIM_SECONDS_PER_GAME_DAY = require("overhaul/lib/career/gameTime").SIM_SECONDS_PER_GAME_DAY
local RENT_PAYMENT_GAME_DAYS = 0.5
local PAYMENT_INTERVAL_S = RENT_PAYMENT_GAME_DAYS * SIM_SECONDS_PER_GAME_DAY
local UPDATE_STEP_S = 5
local OFFER_POLL_INTERVAL_S = 5
local FIXED_RENT_RATE = 0.015
local DYNAMIC_RENT_RATE = 0.012
local UPFRONT_DISCOUNT = 0.87
local FALLBACK_BASE_VALUE = 50000
local TIME_BETWEEN_OFFERS_BASE = 190
local OFFER_TTL = 1000
local MIN_LEASE_PERIODS = 4
local MAX_LEASE_PERIODS = 14
local ASK_SCALE_MIN = 0.70
local ASK_SCALE_MAX = 1.50
local LEASE_TYPES = { "fixed", "dynamic", "upfront" }
local SAVE_DIR = "/career/rls_career"
local SAVE_FILE = SAVE_DIR .. "/landlordRentals.json"
local state = {
  listings = {}, -- garageId -> listing
  active = {}, -- garageId -> lease
}
local accumulatedSimTime = 0
local updateTimer = 0
local offerUpdateAccumulator = 0

local propertyMoney = propertyMoneyFactory.new({
  category = "property",
  label = "Landlord rent",
  payDescription = "Landlord rent refund",
  rewardDescription = "Landlord rent income",
  source = "Landlord Rentals",
  deps = function()
    return overhaul_career_economy_payment, overhaul_career_economy_playerAttributes, overhaul_world_facilities,
      overhaul_phone_apps_layout
  end,
})

local function notifyChanged()
  guihooks.trigger("garageListingsUpdated")
  guihooks.trigger("landlordRentals:updated")
end

local function getBaseValue(garageId)
  if overhaul_career_garage_garageManager and overhaul_career_garage_garageManager.getGaragePurchasePrice then
    local price = overhaul_career_garage_garageManager.getGaragePurchasePrice(garageId)
    if price and price > 0 then return price end
  end
  local facility = overhaul_world_facilities.getFacility("garage", garageId)
  if facility and facility.defaultPrice then return facility.defaultPrice end
  return FALLBACK_BASE_VALUE
end

local function marketRentFor(garageId)
  return math.floor(getBaseValue(garageId) * FIXED_RENT_RATE + 0.5)
end

local function rentForType(garageId, rentalType)
  local base = getBaseValue(garageId)
  if rentalType == "dynamic" then
    return math.floor(base * DYNAMIC_RENT_RATE + 0.5)
  end
  return math.floor(base * FIXED_RENT_RATE + 0.5)
end

local function depositForRent(periodRent)
  return math.floor((periodRent or 0) * 2 + 0.5)
end

local function lerp(a, b, t)
  return a + (b - a) * t
end

local function inverseLerp(a, b, v)
  if b == a then return 0 end
  return (v - a) / (b - a)
end

local function lerpClamped(fromValue, toValue, fromRatio, toRatio, marketRatio)
  local t = inverseLerp(fromRatio, toRatio, marketRatio)
  return lerp(fromValue, toValue, math.max(0, math.min(1, t)))
end

local function priceOfferTimeMultiplier(marketRatio)
  if marketRatio <= 0.50 then
    return 0.05
  elseif marketRatio < 0.80 then
    return lerpClamped(0.2, 0.05, 0.80, 0.50, marketRatio)
  elseif marketRatio < 0.90 then
    return lerpClamped(0.5, 0.2, 0.90, 0.80, marketRatio)
  elseif marketRatio >= 0.90 and marketRatio <= 1.1 then
    return 1.0
  elseif marketRatio <= 1.3 then
    return lerpClamped(1.0, 2.5, 1.1, 1.3, marketRatio)
  elseif marketRatio <= 1.5 then
    return lerpClamped(2.5, 5.0, 1.3, 1.5, marketRatio)
  end
  return 6.0
end

local function scheduleNextOffer(listing, timeNow)
  if not listing then return end
  local mult = listing.offerTimeMultiplier or 1
  listing.timeOfNextOffer = timeNow + (TIME_BETWEEN_OFFERS_BASE * mult)
    + (math.random(-60, 60) / 100 * TIME_BETWEEN_OFFERS_BASE * mult)
end

local TENANT_NAMES = {
  "Alex R.", "Jordan M.", "Sam K.", "Casey L.", "Riley P.", "Taylor N.", "Morgan S.", "Jamie T.",
}

local function generateTenantPersonality()
  return {
    name = TENANT_NAMES[math.random(1, #TENANT_NAMES)],
    priceMultiplier = 0.92 + math.random() * 0.12,
    quote = "I'd like to rent this place.",
  }
end

local function countOwnedGarages()
  local count = 0
  if not overhaul_career_garage_garageManager or not overhaul_world_facilities then return 0 end
  local garages = overhaul_world_facilities.getFacilitiesByType("garage")
  if type(garages) ~= "table" then return 0 end
  for garageId in pairs(garages) do
    if overhaul_career_garage_garageManager.isPurchasedGarage(garageId) then
      count = count + 1
    end
  end
  return count
end

local function getPrimaryHomeId()
  if overhaul_phone_apps_realEstate and overhaul_phone_apps_realEstate.getPrimaryHomeGarageId then
    return overhaul_phone_apps_realEstate.getPrimaryHomeGarageId()
  end
  return nil
end

local function vehiclesInGarage(garageId)
  if overhaul_career_garage_garageManager and overhaul_career_garage_garageManager.getGarageOccupancy then
    return tonumber(overhaul_career_garage_garageManager.getGarageOccupancy(garageId)) or 0
  end
  return 0
end

local function isListedForSale(garageId)
  if overhaul_career_garage_property_realEstateNegotiation and overhaul_career_garage_property_realEstateNegotiation.getPropertyListing then
    return overhaul_career_garage_property_realEstateNegotiation.getPropertyListing(garageId) ~= nil
  end
  return false
end

local function listEligibility(garageId)
  if not garageId then return false, "invalid" end
  if not overhaul_career_garage_garageManager or not overhaul_career_garage_garageManager.isPurchasedGarage(garageId) then
    return false, "notOwned"
  end
  if state.active[garageId] then return false, "alreadyRented" end
  if state.listings[garageId] then return false, "alreadyListed" end
  if isListedForSale(garageId) then return false, "listedForSale" end
  local primary = getPrimaryHomeId()
  if primary and tostring(primary) == tostring(garageId) then return false, "primaryHome" end
  if countOwnedGarages() <= 1 then return false, "onlyHome" end
  if vehiclesInGarage(garageId) > 0 then return false, "vehiclesPresent" end
  local bundles = require("overhaul/lib/business/bundles")
  if bundles.forGarage and bundles.forGarage(garageId) then return false, "businessBundle" end
  return true, nil
end

local function getPriceGuidance(garageId, askingRent)
  local market = marketRentFor(garageId)
  local ask = tonumber(askingRent) or 0
  if market <= 0 or ask <= 0 then return nil end
  local ratio = ask / market
  local tier, label, description = "fair", "Fair", "Should receive normal offer flow."
  if ratio < 0.98 then
    tier, label, description = "low", "Below market", "Likely faster offers; tenants still won't overpay much."
  elseif ratio > 1.10 then
    tier, label, description = "high", "Over market", "Expect fewer offers and more lowball attempts."
  end
  return {
    marketRent = market,
    askingRent = ask,
    marketRatio = ratio,
    tier = tier,
    label = label,
    description = description,
    offerTimeMultiplier = priceOfferTimeMultiplier(ratio),
  }
end

local function listForRent(garageId, askingRent)
  local ok, reason = listEligibility(garageId)
  if not ok then return false, reason end
  local market = marketRentFor(garageId)
  local ask = tonumber(askingRent) or market
  if ask <= 0 then return false, "invalidPrice" end
  local minAsk = math.floor(market * ASK_SCALE_MIN + 0.5)
  local maxAsk = math.floor(market * ASK_SCALE_MAX + 0.5)
  ask = math.max(minAsk, math.min(maxAsk, ask))
  local guidance = getPriceGuidance(garageId, ask)
  if not guidance then return false, "noGuidance" end
  local garage = overhaul_world_facilities.getFacility("garage", garageId)
  local now = os.time()
  state.listings[garageId] = {
    listingTimestamp = now,
    askingRent = ask,
    marketRentAtListing = market,
    marketRatio = guidance.marketRatio,
    offerTimeMultiplier = guidance.offerTimeMultiplier,
    timeOfNextOffer = nil,
    offers = {},
    garageName = garage and garage.name or tostring(garageId),
    preview = garage and garage.preview or "",
  }
  scheduleNextOffer(state.listings[garageId], now)
  notifyChanged()
  return true
end

local function removeListing(garageId)
  if not garageId or not state.listings[garageId] then return false end
  state.listings[garageId] = nil
  notifyChanged()
  return true
end

local function getListing(garageId)
  return garageId and state.listings[garageId] or nil
end

local function isListedForRent(garageId)
  return state.listings[garageId] ~= nil
end

local function isLandlordRented(garageId)
  return state.active[garageId] ~= nil
end

local function isLandlordReserved(garageId)
  return isListedForRent(garageId) or isLandlordRented(garageId)
end

local function getActiveLeases()
  return state.active
end

local function generateTenantOffer(garageId)
  local listing = state.listings[garageId]
  if not listing then return nil end
  local market = marketRentFor(garageId)
  if market <= 0 then market = listing.marketRentAtListing or listing.askingRent end
  local tenant = generateTenantPersonality()
  local base = market
  local personalityMult = tenant.priceMultiplier or 0.9
  local noise = (math.random() * 0.1) + 0.92
  local finalOffer = base * personalityMult * noise
  local ratio = listing.marketRatio or 1.0
  if ratio < 0.98 then
    finalOffer = math.min(finalOffer, listing.askingRent)
  elseif ratio > 1.1 then
    local cap = market * (0.90 + math.random() * 0.08)
    finalOffer = math.min(finalOffer, cap)
  else
    finalOffer = math.min(finalOffer, listing.askingRent * 1.01)
  end
  finalOffer = math.max(50, math.floor((finalOffer + 25) / 50) * 50)
  local offer = {
    timestamp = os.time(),
    value = finalOffer,
    ttl = OFFER_TTL,
    negotiationPossible = true,
    tenantPersonality = tenant,
  }
  table.insert(listing.offers, offer)
  return offer
end

local function notifyNewOffer(garageId, listing, offer)
  local layout = phoneLayout.get()
  if layout and layout.fireNotification then
    layout.fireNotification("realEstate.newRentOffer", {
      title = "New Rent Offer",
      message = listing.garageName or "Property",
      meta = "$" .. tostring(offer.value) .. "/period",
      kind = "invite",
      ttl = 8,
      source = "Real Estate",
      sound = { soundClass = "AudioGui", type = "event:>UI>Missions>Info_Open" },
      entityId = tostring(garageId),
    }, { entityId = tostring(garageId) })
  end
  notifyChanged()
end

local function dropExpiredOffers(listing, now)
  for i = #(listing.offers or {}), 1, -1 do
    local offer = listing.offers[i]
    if offer and now - (offer.timestamp or now) > (offer.ttl or OFFER_TTL) then
      table.remove(listing.offers, i)
    end
  end
end

local function generateNewOffers()
  local now = os.time()
  for garageId, listing in pairs(state.listings) do
    dropExpiredOffers(listing, now)
    if not listing.timeOfNextOffer then
      scheduleNextOffer(listing, now)
    end
    if listing.timeOfNextOffer and now >= listing.timeOfNextOffer then
      listing.timeOfNextOffer = nil
      local offer = generateTenantOffer(garageId)
      if offer then notifyNewOffer(garageId, listing, offer) end
      scheduleNextOffer(listing, now)
    end
  end
end

local function pickLeaseType()
  return LEASE_TYPES[math.random(1, #LEASE_TYPES)]
end

local function pickLeasePeriods()
  return math.random(MIN_LEASE_PERIODS, MAX_LEASE_PERIODS)
end

local function startLease(garageId, agreedRent, personality)
  local leaseType = pickLeaseType()
  local periods = pickLeasePeriods()
  local periodRent = math.max(50, math.floor(tonumber(agreedRent) or 0))
  if leaseType == "dynamic" then
    periodRent = math.min(periodRent, rentForType(garageId, "dynamic") * 1.2)
  end
  local deposit = depositForRent(marketRentFor(garageId))
  local upfrontTotal = 0
  local firstCredit = deposit
  if leaseType == "upfront" then
    upfrontTotal = math.floor(periodRent * periods * UPFRONT_DISCOUNT + 0.5)
    firstCredit = firstCredit + upfrontTotal
  else
    firstCredit = firstCredit + periodRent
  end
  if not propertyMoney.applyMoneyDelta(firstCredit, garageId) then return false end

  state.active[garageId] = {
    type = leaseType,
    agreedRent = periodRent,
    monthlyRent = periodRent,
    securityDeposit = deposit,
    depositHeld = true,
    leaseStart = accumulatedSimTime,
    leaseTerm = periods,
    paymentsMade = leaseType == "upfront" and periods or 1,
    paymentsRemaining = leaseType == "upfront" and 0 or (periods - 1),
    consecutiveMissed = 0,
    missedPayments = 0,
    warningLevel = 0,
    nextPaymentDue = accumulatedSimTime + PAYMENT_INTERVAL_S,
    secondsUntilNextPayment = PAYMENT_INTERVAL_S,
    tenantName = personality and personality.name or "Tenant",
    prepaidRemaining = leaseType == "upfront" and upfrontTotal or 0,
  }
  state.listings[garageId] = nil
  if overhaul_career_garage_garageManager and overhaul_career_garage_garageManager.buildGarageSizes then
    overhaul_career_garage_garageManager.buildGarageSizes()
  end
  propertyMoney.notify("success", "Lease Signed",
    "Tenant signed for " .. propertyMoney.getGarageLabel(garageId) .. " (" .. leaseType .. ").",
    "landlord.leaseSigned", garageId)
  notifyChanged()
  overhaul_career_saveSystem.saveCurrent()
  return true
end

local function acceptOffer(garageId, offerIndex)
  local listing = state.listings[garageId]
  if not listing or not listing.offers then return false end
  local index = tonumber(offerIndex)
  if not index or index < 1 or index > #listing.offers then return false end
  local offer = listing.offers[index]
  if not offer then return false end
  local agreed = offer.negotiatedRent or offer.value
  return startLease(garageId, agreed, offer.tenantPersonality)
end

-- Used by realEstateNegotiation rent mode after chat accept.
local function acceptNegotiatedRent(garageId, offerIndex, agreedRent, personality)
  local listing = state.listings[garageId]
  if not listing then return false end
  local index = tonumber(offerIndex)
  local offer = listing.offers and index and listing.offers[index] or nil
  local person = personality or (offer and offer.tenantPersonality) or nil
  local rent = tonumber(agreedRent) or (offer and (offer.negotiatedRent or offer.value)) or 0
  if rent <= 0 then return false end
  return startLease(garageId, rent, person)
end

local function declineOffer(garageId, offerIndex)
  local listing = state.listings[garageId]
  if not listing or not listing.offers then return false end
  local index = tonumber(offerIndex)
  if not index or index < 1 or index > #listing.offers then return false end
  table.remove(listing.offers, index)
  notifyChanged()
  return true
end

-- Simple one-shot counter: midpoint between asking and offer, then accept.
local function negotiateAndAcceptOffer(garageId, offerIndex)
  local listing = state.listings[garageId]
  if not listing or not listing.offers then return false end
  local index = tonumber(offerIndex)
  if not index or index < 1 or index > #listing.offers then return false end
  local offer = listing.offers[index]
  if not offer then return false end
  local ask = tonumber(listing.askingRent) or 0
  local current = tonumber(offer.negotiatedRent or offer.value) or 0
  local mid = math.max(50, math.floor((((ask > 0 and ask or current) + current) / 2 + 25) / 50) * 50)
  offer.negotiatedRent = mid
  return startLease(garageId, mid, offer.tenantPersonality)
end

local function returnDeposit(garageId, lease, keep)
  if not lease or not lease.depositHeld then return end
  if not keep and lease.securityDeposit and lease.securityDeposit > 0 then
    -- Deposit was prepaid to player; returning it means paying it out.
    propertyMoney.applyMoneyDelta(-lease.securityDeposit, garageId, { category = "property" })
  end
  lease.depositHeld = false
end

local function endLease(garageId, opts)
  opts = opts or {}
  local lease = state.active[garageId]
  if not lease then return false end
  local keepDeposit = opts.keepDeposit == true
  local prorateRefund = tonumber(opts.prorateRefund) or 0

  if prorateRefund > 0 then
    propertyMoney.applyMoneyDelta(-prorateRefund, garageId)
  end
  returnDeposit(garageId, lease, keepDeposit)

  local title = opts.title or "Lease Ended"
  local msg = opts.message or ("Lease ended for " .. propertyMoney.getGarageLabel(garageId) .. ".")
  propertyMoney.notify(opts.notifyKind or "info", title, msg, "landlord.leaseEnded", garageId)

  state.active[garageId] = nil
  if overhaul_career_garage_garageManager and overhaul_career_garage_garageManager.buildGarageSizes then
    overhaul_career_garage_garageManager.buildGarageSizes()
  end
  notifyChanged()
  overhaul_career_saveSystem.saveCurrent()
  return true
end

local function computeProrateRefund(lease)
  if not lease then return 0 end
  if lease.type == "upfront" then
    local total = lease.leaseTerm * PAYMENT_INTERVAL_S
    local elapsed = accumulatedSimTime - (lease.leaseStart or 0)
    local remainingFrac = math.max(0, 1 - (elapsed / math.max(1, total)))
    local prepaid = lease.prepaidRemaining or 0
    return math.floor(prepaid * remainingFrac + 0.5)
  end
  return 0
end

local function endLeaseEarly(garageId)
  local lease = state.active[garageId]
  if not lease then return false end
  local refund = computeProrateRefund(lease)
  -- Inverse of tenant early-exit (tenant forfeits deposit): landlord ending early returns deposit.
  return endLease(garageId, {
    keepDeposit = false,
    prorateRefund = refund,
    title = "Lease Ended Early",
    message = "You ended the lease early for " .. propertyMoney.getGarageLabel(garageId) .. ". Deposit returned.",
    notifyKind = "warning",
  })
end

local function scheduleNextPayment(lease)
  lease.nextPaymentDue = accumulatedSimTime + PAYMENT_INTERVAL_S
  lease.secondsUntilNextPayment = PAYMENT_INTERVAL_S
end

local function processLandlordPayment(garageId, lease)
  if lease.type == "upfront" then return end
  if (lease.paymentsRemaining or 0) <= 0 then
    endLease(garageId, {
      keepDeposit = false,
      title = "Lease Complete",
      message = "Lease complete for " .. propertyMoney.getGarageLabel(garageId) .. ". Deposit returned.",
      notifyKind = "success",
    })
    return
  end
  if lease.type == "dynamic" then
    lease.monthlyRent = rentForType(garageId, "dynamic")
  end
  -- NPC pays: credit landlord (simulate miss chance on high ask).
  local missChance = 0.04
  if (lease.agreedRent or 0) > marketRentFor(garageId) * 1.15 then
    missChance = 0.12
  end
  if math.random() < missChance then
    lease.missedPayments = (lease.missedPayments or 0) + 1
    lease.consecutiveMissed = (lease.consecutiveMissed or 0) + 1
    scheduleNextPayment(lease)
    if lease.consecutiveMissed >= 3 then
      endLease(garageId, {
        keepDeposit = true,
        title = "Tenant Default",
        message = "Tenant defaulted on " .. propertyMoney.getGarageLabel(garageId) .. ". Deposit kept.",
        notifyKind = "error",
      })
    else
      propertyMoney.notify("warning", "Late Rent",
        "Tenant missed a payment on " .. propertyMoney.getGarageLabel(garageId) .. ".",
        "landlord.rentMissed", garageId)
    end
    return
  end
  if propertyMoney.applyMoneyDelta(lease.monthlyRent, garageId) then
    lease.paymentsMade = (lease.paymentsMade or 0) + 1
    lease.paymentsRemaining = (lease.paymentsRemaining or 1) - 1
    lease.consecutiveMissed = 0
    scheduleNextPayment(lease)
  end
end

local function tickLease(garageId, lease)
  if not lease then return end
  if lease.type == "upfront" then
    local duration = (lease.leaseTerm or 1) * PAYMENT_INTERVAL_S
    if accumulatedSimTime - (lease.leaseStart or 0) >= duration then
      endLease(garageId, {
        keepDeposit = false,
        title = "Lease Complete",
        message = "Prepaid lease ended for " .. propertyMoney.getGarageLabel(garageId) .. ". Deposit returned.",
        notifyKind = "success",
      })
    end
    return
  end
  lease.secondsUntilNextPayment = (lease.secondsUntilNextPayment or PAYMENT_INTERVAL_S) - UPDATE_STEP_S
  if lease.secondsUntilNextPayment <= 0 then
    processLandlordPayment(garageId, lease)
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
  local ids = {}
  for garageId in pairs(state.active) do table.insert(ids, garageId) end
  for _, garageId in ipairs(ids) do
    tickLease(garageId, state.active[garageId])
  end
end

local function getLeaseInfo(garageId)
  return state.active[garageId]
end

local function getListingOffersData(garageId)
  local listing = state.listings[garageId]
  if not listing then return nil end
  local garage = overhaul_world_facilities.getFacility("garage", garageId)
  local offers = {}
  for index, offer in ipairs(listing.offers or {}) do
    table.insert(offers, {
      index = index,
      value = offer.value,
      negotiatedRent = offer.negotiatedRent,
      tenantName = offer.tenantPersonality and offer.tenantPersonality.name or "Tenant",
      timestamp = offer.timestamp,
      negotiationPossible = offer.negotiationPossible ~= false,
    })
  end
  return {
    garageId = garageId,
    name = listing.garageName or (garage and garage.name) or tostring(garageId),
    preview = listing.preview or (garage and garage.preview) or "",
    askingRent = listing.askingRent,
    marketRent = listing.marketRentAtListing or marketRentFor(garageId),
    offers = offers,
  }
end

local function getListEligibilityPayload(garageId)
  local ok, reason = listEligibility(garageId)
  local market = marketRentFor(garageId)
  return {
    canList = ok,
    reason = reason,
    marketRent = market,
    minAsk = math.floor(market * ASK_SCALE_MIN + 0.5),
    maxAsk = math.floor(market * ASK_SCALE_MAX + 0.5),
    isListedForRent = isListedForRent(garageId),
    isLandlordRented = isLandlordRented(garageId),
    lease = state.active[garageId],
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

local function onExtensionLoaded()
  loadState()
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
end

M.listForRent = listForRent
M.removeListing = removeListing
M.getListing = getListing
M.isListedForRent = isListedForRent
M.isLandlordRented = isLandlordRented
M.isLandlordReserved = isLandlordReserved
M.getActiveLeases = getActiveLeases
M.getLeaseInfo = getLeaseInfo
M.acceptOffer = acceptOffer
M.acceptNegotiatedRent = acceptNegotiatedRent
M.declineOffer = declineOffer
M.negotiateAndAcceptOffer = negotiateAndAcceptOffer
M.endLeaseEarly = endLeaseEarly
M.getPriceGuidance = getPriceGuidance
M.marketRentFor = marketRentFor
M.getListingOffersData = getListingOffersData
M.getListEligibility = getListEligibilityPayload
M.listEligibility = listEligibility

M.onUpdate = onUpdate
M.onOverhaulSaveCurrentProfile = onOverhaulSaveCurrentProfile
M.onExtensionLoaded = onExtensionLoaded
M.onCareerActivated = onCareerActivated

return M
