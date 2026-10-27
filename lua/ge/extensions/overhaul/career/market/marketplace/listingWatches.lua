-- RLS Career Overhaul · https://github.com/RLS-Modding/rls_career_overhaul
-- Listing watches: notify when a matching private-party vehicle appears on the Marketplace.

local M = {}
local vehicleMap = require('overhaul/career/garage/inventory/vehicleMap')

local MAX_WATCHES = 24
local PRIVATE_SELLER_ID = "private"

local function trim(value)
  return tostring(value or ""):match("^%s*(.-)%s*$") or ""
end

local function vehicleBodyStyle(vehicle)
  return trim(vehicle and (vehicle["Body Style"] or vehicle.BodyStyle))
end

-- Catalog class (Car / Truck / Trailer / …). Prefer this over Body Style for "Type" watches.
local function vehicleCatalogType(vehicle)
  if not vehicle then return "" end
  if vehicleMap.isTrailer(vehicle) then return "Trailer" end
  local aggregates = vehicle.aggregates
  if type(aggregates) == "table" and type(aggregates.Type) == "table" then
    for typeName, flag in pairs(aggregates.Type) do
      if flag and type(typeName) == "string" then
        local name = trim(typeName)
        if name ~= "" then return name end
      end
    end
  end
  return trim(vehicle.Type)
end

local function vehicleBrand(vehicle)
  return trim(vehicle and vehicle.Brand)
end

local function vehicleModelKey(vehicle)
  return trim(vehicle and vehicle.model_key)
end

local function vehicleModelLabel(vehicle)
  local brand = vehicleBrand(vehicle)
  local name = trim(vehicle and vehicle.Name)
  if brand ~= "" and name ~= "" then return brand .. " " .. name end
  if name ~= "" then return name end
  if brand ~= "" then return brand end
  return vehicleModelKey(vehicle)
end

local function isLivePrivateListing(vehicle)
  if not vehicle or type(vehicle) ~= "table" then return false end
  if tostring(vehicle.sellerId or "") ~= PRIVATE_SELLER_ID then return false end
  if vehicle.__sold or vehicle.soldViewCounter then return false end
  return vehicle.shopId ~= nil
end

local function watchMatches(watch, vehicle)
  if not watch or type(watch) ~= "table" then return false end
  local kind = watch.kind
  local value = trim(watch.value)
  if value == "" then return false end
  if kind == "type" then
    local lowered = value:lower()
    if lowered == "trailer" then
      return vehicleMap.isTrailer(vehicle) or vehicleCatalogType(vehicle):lower() == "trailer"
    end
    -- Type tab lists catalog Type and Body Style; match either so older body-style watches still work.
    return vehicleCatalogType(vehicle) == value or vehicleBodyStyle(vehicle) == value
  end
  if kind == "brand" then return vehicleBrand(vehicle) == value end
  if kind == "model" then return vehicleModelKey(vehicle) == value end
  return false
end

local function watchKindPrefix(kind)
  if kind == "type" then return "Type"
  end
  if kind == "brand" then return "Brand"
  end
  if kind == "model" then return "Model"
  end
  return "Watch"
end

local function matchingWatchLabels(watches, vehicle)
  local labels = {}
  local seen = {}
  for _, watch in ipairs(watches or {}) do
    if watchMatches(watch, vehicle) then
      local label = trim(watch.label)
      if label == "" then label = trim(watch.value) end
      if label ~= "" then
        -- Spell out kind so a model alert is not mistaken for a brand-wide alert.
        label = watchKindPrefix(watch.kind) .. ": " .. label
        if not seen[label] then
          seen[label] = true
          table.insert(labels, label)
        end
      end
    end
  end
  return labels
end

function M.new(api)
  local watches = {}
  local notifiedShopIds = {}

  local function normalizeWatch(entry)
    if type(entry) ~= "table" then return nil end
    local kind = entry.kind
    if kind ~= "type" and kind ~= "brand" and kind ~= "model" then return nil end
    local value = trim(entry.value)
    if value == "" then return nil end
    local label = trim(entry.label)
    if label == "" then
      if kind == "type" then label = value .. " listings"
      elseif kind == "brand" then label = value
      else label = value
      end
    end
    local id = trim(entry.id)
    if id == "" then id = kind .. ":" .. value end
    return { id = id, kind = kind, value = value, label = label }
  end

  local function loadState(data)
    watches = {}
    notifiedShopIds = {}
    if type(data) ~= "table" then return end
    for _, entry in ipairs(data.listingWatches or {}) do
      local watch = normalizeWatch(entry)
      if watch and #watches < MAX_WATCHES then
        table.insert(watches, watch)
      end
    end
    for shopId, flag in pairs(data.listingWatchNotified or {}) do
      if flag and shopId ~= nil then
        notifiedShopIds[tostring(shopId)] = true
      end
    end
  end

  local function saveState()
    local notified = {}
    for shopId, flag in pairs(notifiedShopIds) do
      if flag then notified[shopId] = true end
    end
    return {
      listingWatches = watches,
      listingWatchNotified = notified,
    }
  end

  local function getWatches()
    local copy = {}
    for _, watch in ipairs(watches) do
      table.insert(copy, {
        id = watch.id,
        kind = watch.kind,
        value = watch.value,
        label = watch.label,
      })
    end
    return copy
  end

  local function findWatchIndex(kind, value)
    kind = trim(kind)
    value = trim(value)
    for index, watch in ipairs(watches) do
      if watch.kind == kind and watch.value == value then return index end
    end
    return nil
  end

  local function findWatchById(id)
    id = trim(id)
    for index, watch in ipairs(watches) do
      if watch.id == id then return index, watch end
    end
    return nil
  end

  local function notifyForVehicle(vehicle, labels)
    if not isLivePrivateListing(vehicle) then return false end
    local shopId = tostring(vehicle.shopId)
    if notifiedShopIds[shopId] then return false end
    if not labels or #labels == 0 then return false end

    local title = "Marketplace"
    local name = vehicleModelLabel(vehicle)
    local year = trim(vehicle.year)
    local headline = name
    if year ~= "" then headline = year .. " " .. name end

    local meta
    if #labels == 1 then
      meta = labels[1]
    else
      meta = table.concat(labels, " · ")
    end

    local modelKey = vehicleModelKey(vehicle)
    local message = headline .. " is available"
    -- Flat deep-link fields: nested routeParams tables are unreliable across guihooks.
    local fired = api.fireNotification(
      "marketplace.listingWatch",
      title,
      message,
      meta,
      "invite",
      {
        replaceKey = "marketplace.listingWatch." .. shopId,
        routeName = "phone-marketplace-vehicle",
        routeKind = "listing",
        routeVehicleId = shopId,
        routeModelKey = modelKey,
        ttl = 12,
        forceTtl = true,
      }
    )
    if fired then
      notifiedShopIds[shopId] = true
    end
    return fired and true or false
  end

  local function scanVehicle(vehicle, onlyWatch)
    if #watches == 0 then return false end
    local labels
    if onlyWatch then
      if not watchMatches(onlyWatch, vehicle) then return false end
      local label = trim(onlyWatch.label)
      if label == "" then label = trim(onlyWatch.value) end
      labels = { watchKindPrefix(onlyWatch.kind) .. ": " .. label }
    else
      labels = matchingWatchLabels(watches, vehicle)
    end
    if #labels == 0 then return false end
    return notifyForVehicle(vehicle, labels)
  end

  local function pruneNotified(liveShopIds)
    if type(liveShopIds) ~= "table" then return end
    local live = {}
    for _, shopId in ipairs(liveShopIds) do
      live[tostring(shopId)] = true
    end
    for shopId in pairs(notifiedShopIds) do
      if not live[shopId] then
        notifiedShopIds[shopId] = nil
      end
    end
  end

  local function scanPrivateListings(maxNotify, onlyWatch)
    if #watches == 0 then return 0 end
    local listings = api.getPrivateListings and api.getPrivateListings() or {}
    local liveIds = {}
    local notified = 0
    local notifyCap = tonumber(maxNotify)
    if not notifyCap or notifyCap < 0 then notifyCap = 3 end
    for _, vehicle in ipairs(listings) do
      if isLivePrivateListing(vehicle) then
        table.insert(liveIds, vehicle.shopId)
        local matches = onlyWatch and watchMatches(onlyWatch, vehicle) or (#matchingWatchLabels(watches, vehicle) > 0)
        if matches then
          if notified < notifyCap and scanVehicle(vehicle, onlyWatch) then
            notified = notified + 1
          elseif notified >= notifyCap then
            -- Mark remaining matches seen so adding another alert does not dump a backlog.
            notifiedShopIds[tostring(vehicle.shopId)] = true
          end
        end
      end
    end
    pruneNotified(liveIds)
    return notified
  end

  local function onPrivateListingAdded(vehicle)
    if #watches == 0 then return false end
    if not isLivePrivateListing(vehicle) then return false end
    return scanVehicle(vehicle, nil)
  end

  local function addWatch(kind, value, label)
    local watch = normalizeWatch({ kind = kind, value = value, label = label })
    if not watch then return { ok = false, reason = "invalid" } end
    local existing = findWatchIndex(watch.kind, watch.value)
    if existing then
      return { ok = true, watch = watches[existing], already = true }
    end
    if #watches >= MAX_WATCHES then
      return { ok = false, reason = "limit", limit = MAX_WATCHES }
    end
    table.insert(watches, watch)
    -- Only scan for this new watch — re-scanning every watch re-fired unrelated brand/type alerts.
    scanPrivateListings(3, watch)
    return { ok = true, watch = watch }
  end

  local function removeWatch(id)
    local index = findWatchById(id)
    if not index then return false end
    table.remove(watches, index)
    return true
  end

  local function removeWatchByKindValue(kind, value)
    local index = findWatchIndex(kind, value)
    if not index then return false end
    table.remove(watches, index)
    return true
  end

  local function hasWatch(kind, value)
    return findWatchIndex(kind, value) ~= nil
  end

  -- Click target for a listing-watch notification. Prefer shopId when it still points at the
  -- same model; otherwise find a live private listing with that model (shop ids are reused).
  local function resolveAlertTarget(shopId, modelKey)
    shopId = trim(shopId)
    modelKey = trim(modelKey)
    local listings = api.getPrivateListings and api.getPrivateListings() or {}

    local function asTarget(vehicle)
      if not isLivePrivateListing(vehicle) then return nil end
      return {
        routeName = "phone-marketplace-vehicle",
        routeKind = "listing",
        routeVehicleId = tostring(vehicle.shopId),
        routeModelKey = vehicleModelKey(vehicle),
      }
    end

    if shopId ~= "" then
      for _, vehicle in ipairs(listings) do
        if tostring(vehicle.shopId) == shopId then
          if modelKey == "" or vehicleModelKey(vehicle) == modelKey then
            return asTarget(vehicle)
          end
          break
        end
      end
    end

    if modelKey ~= "" then
      for _, vehicle in ipairs(listings) do
        if vehicleModelKey(vehicle) == modelKey then
          return asTarget(vehicle)
        end
      end
    end

    return {
      routeName = "phone-marketplace",
      routeKind = "",
      routeVehicleId = "",
      routeModelKey = "",
    }
  end

  local function collectOptions()
    local listings = api.getShopListings and api.getShopListings() or {}
    local types, brands, models = {}, {}, {}
    local typeSeen, brandSeen, modelSeen = {}, {}, {}

    local function addType(value)
      value = trim(value)
      if value == "" or typeSeen[value] then return end
      typeSeen[value] = true
      table.insert(types, { value = value, label = value })
    end
    local function addBrand(value)
      value = trim(value)
      if value == "" or brandSeen[value] then return end
      brandSeen[value] = true
      table.insert(brands, { value = value, label = value })
    end
    local function addModel(vehicle)
      local key = vehicleModelKey(vehicle)
      if key == "" or modelSeen[key] then return end
      modelSeen[key] = true
      local catalogType = vehicleCatalogType(vehicle)
      table.insert(models, {
        value = key,
        label = vehicleModelLabel(vehicle),
        brand = vehicleBrand(vehicle),
        catalogType = catalogType,
        isTrailer = catalogType == "Trailer" or vehicleMap.isTrailer(vehicle),
      })
    end

    for _, vehicle in ipairs(listings) do
      if vehicle and not vehicle.__sold and not vehicle.soldViewCounter then
        addType(vehicleCatalogType(vehicle))
        addType(vehicleBodyStyle(vehicle))
        addBrand(vehicleBrand(vehicle))
        addModel(vehicle)
      end
    end

    for _, watch in ipairs(watches) do
      if watch.kind == "type" then addType(watch.value)
      elseif watch.kind == "brand" then addBrand(watch.value)
      elseif watch.kind == "model" then
        if not modelSeen[watch.value] then
          modelSeen[watch.value] = true
          table.insert(models, { value = watch.value, label = watch.label, brand = "", catalogType = "", isTrailer = false })
        end
      end
    end

    table.sort(types, function(a, b) return a.label < b.label end)
    table.sort(brands, function(a, b) return a.label < b.label end)
    table.sort(models, function(a, b) return a.label < b.label end)

    return { types = types, brands = brands, models = models, limit = MAX_WATCHES }
  end

  return {
    loadState = loadState,
    saveState = saveState,
    getWatches = getWatches,
    addWatch = addWatch,
    removeWatch = removeWatch,
    removeWatchByKindValue = removeWatchByKindValue,
    hasWatch = hasWatch,
    onPrivateListingAdded = onPrivateListingAdded,
    scanPrivateListings = scanPrivateListings,
    resolveAlertTarget = resolveAlertTarget,
    collectOptions = collectOptions,
    MAX_WATCHES = MAX_WATCHES,
  }
end

return M
