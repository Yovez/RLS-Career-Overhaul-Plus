-- Vehicle map identity shared by inventory loading and garage capacity accounting.
-- Saved world evidence wins; legacy storage resolves through the facility catalog, never a map-name list.
local M = {}
local levelData = require('overhaul/lib/world/levelData')
local warned = {}

local function typeLooksLikeTrailer(value)
  value = tostring(value or ""):lower()
  return value == "trailer" or value == "trailers"
end

-- Word "trailer" in names (mod trailers often keep Type=Car when built from a truck bed).
local function textLooksLikeTrailer(value)
  local text = tostring(value or ""):lower()
  return text:find("%f[%w]trailers?%f[%W]") ~= nil
end

local function aggregatesLookLikeTrailer(aggregates)
  if type(aggregates) ~= "table" then return false end
  local types = aggregates.Type
  if type(types) == "table" then
    if types.Trailer or types.trailer then return true end
    for typeName, on in pairs(types) do
      if on and typeLooksLikeTrailer(typeName) then return true end
    end
  elseif typeLooksLikeTrailer(types) then
    return true
  end
  for _, key in ipairs({ "Body Style", "Configuration", "Name" }) do
    local field = aggregates[key]
    if type(field) == "table" then
      for name, on in pairs(field) do
        if on and textLooksLikeTrailer(name) then return true end
      end
    elseif textLooksLikeTrailer(field) then
      return true
    end
  end
  return false
end

-- Trailers stay in the inventory / garage list but do not consume car slots.
function M.isTrailer(vehicle)
  if type(vehicle) ~= "table" then return false end
  if vehicle.vehOfferType == "trailer" then return true end
  if typeLooksLikeTrailer(vehicle.Type) then return true end
  if aggregatesLookLikeTrailer(vehicle.aggregates) then return true end
  if textLooksLikeTrailer(vehicle.Name) or textLooksLikeTrailer(vehicle.niceName)
    or textLooksLikeTrailer(vehicle.Configuration) then
    return true
  end

  local modelName = vehicle.model or vehicle.model_key or vehicle.JBeam
  if textLooksLikeTrailer(modelName) then return true end
  if not modelName or not core_vehicles then return false end

  local configName = vehicle.key or vehicle.config_name
  local config = vehicle.config
  if type(config) == "table" and type(config.partConfigFilename) == "string" then
    local _, fromPath = path.splitWithoutExt(config.partConfigFilename)
    configName = fromPath or configName
  end
  if configName and core_vehicles.getConfig then
    local configInfo = core_vehicles.getConfig(modelName, configName)
    if configInfo then
      if configInfo.takesNoInventorySpace then return true end
      if aggregatesLookLikeTrailer(configInfo.aggregates) then return true end
      if textLooksLikeTrailer(configInfo.Name) or textLooksLikeTrailer(configInfo.Configuration) then
        return true
      end
    end
  end
  local model = core_vehicles.getModel and core_vehicles.getModel(modelName)
  local modelData = model and (model.model or model)
  if not modelData then return false end
  if typeLooksLikeTrailer(modelData.Type) then return true end
  return textLooksLikeTrailer(modelData.Name) or textLooksLikeTrailer(modelData.Brand and (tostring(modelData.Brand) .. " " .. tostring(modelData.Name)))
end

function M.homeGarage(vehicle)
  if tostring(vehicle.location or ''):find('freightPickup:', 1, true) == 1 then
    return vehicle.freightHomeGarageId
  end
  return vehicle.location
end

function M.resolve(vehicle)
  if vehicle.lastKnownLevel and vehicle.lastKnownLevel ~= '' then return vehicle.lastKnownLevel end
  if vehicle.worldPosition and vehicle.worldPosition.level then return vehicle.worldPosition.level end
  local garageId = M.homeGarage(vehicle)
  if not garageId then return nil end
  local current = getCurrentLevelIdentifier()
  local function contains(level)
    for _, garage in ipairs(overhaul_world_facilities.getFacilitiesByType('garage', level) or {}) do
      if tostring(garage.id) == tostring(garageId) then return true end
    end
  end
  local candidates = {}
  for level in pairs(levelData.loadMaps()) do candidates[level] = true end
  if current then candidates[current] = true end
  local found, count = nil, 0
  for level in pairs(candidates) do
    if contains(level) then
      found, count = level, count + 1
    else
      candidates[level] = nil
    end
  end
  if count > 1 then
    local manager = overhaul_career_garage_garageManager
    local live = manager and manager.getGarageAcquisition and manager.getGarageAcquisition(garageId)
    local ownerLevel = live and live.level
    if not ownerLevel then
      -- Ownership is evidence only when its acquisition actually recorded a map.
      local _, savePath = overhaul_career_saveSystem.getCurrentProfile()
      local ownership = savePath and jsonReadFile(savePath .. '/career/rls_career/purchasedGarages.json')
      local acquisition = ownership and ownership.garages and ownership.garages[tostring(garageId)]
        and ownership.acquisitions and ownership.acquisitions[tostring(garageId)]
      ownerLevel = acquisition and acquisition.level
    end
    if ownerLevel and candidates[ownerLevel] then return ownerLevel end
    local key = tostring(garageId)
    if not warned[key] then
      warned[key] = true
      log('W', 'vehicleMap', 'Ambiguous garage id ' .. key .. '; leaving vehicle map unresolved')
    end
    return nil, 'ambiguous'
  end
  return found
end

function M.repair(vehicle)
  if not vehicle.lastKnownLevel or vehicle.lastKnownLevel == '' then
    vehicle.lastKnownLevel = M.resolve(vehicle)
  end
  return vehicle.lastKnownLevel
end

return M
