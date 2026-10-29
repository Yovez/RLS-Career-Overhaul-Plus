-- Personal bank automation: auto-pay by category, auto-deposit income, balance sweeps.
local M = {}

local moneyCategories = require("overhaul/lib/ledger/categories")

local SPEND_CATEGORIES = {
  "shops", "vehicles", "stocks", "fines", "insurance", "loans",
  "repairs", "fuel", "services", "property", "other",
}
local INCOME_CATEGORIES = { "reward", "sale", "interest", "refund", "other" }
local OPERATORS = { lt = true, lte = true, eq = true, gte = true, gt = true }
local MIN_TRANSFER = 1
local HYSTERESIS = 50

local applying = false
local state = {
  -- accountId -> { autoPayEnabled, autoPay = { shops=true, ... }, autoDeposit = {...}, balanceRules = {...} }
  accounts = {},
  -- spendCategory -> accountId (exclusive claim)
  payClaims = {},
}

local function trim(value)
  return tostring(value or ""):match("^%s*(.-)%s*$") or ""
end

local function isPersonal(account)
  return account and (account.type or "") == "personal"
end

local function isChecking(account)
  if not isPersonal(account) then return false end
  -- Older saves may omit accountType; treat as checking (UI does the same).
  local kind = account.accountType
  return kind == nil or kind == "" or kind == "checking"
end

local function defaultAutoInvest()
  return {
    enabled = false,
    mode = "broker", -- broker | stocks
    accountFloor = 5000,
    percent = 50,
    minAmount = 100,
    tickers = {}, -- symbol -> true when mode == stocks
  }
end

local function defaultAccountAutomation()
  return {
    autoPayEnabled = false,
    autoPay = {},
    autoDeposit = {
      enabled = false,
      walletFloor = 0,
      percent = 100,
      income = { reward = true, sale = true, interest = true, refund = true, other = true },
    },
    autoInvest = defaultAutoInvest(),
    balanceRules = {},
  }
end

local function truthy(value)
  return value == true or value == 1 or value == "1" or value == "true"
end

local function normalizeAutoInvest(entry)
  local cfg = defaultAutoInvest()
  entry = type(entry) == "table" and entry or {}
  cfg.enabled = truthy(entry.enabled)
  cfg.mode = tostring(entry.mode or "") == "stocks" and "stocks" or "broker"
  cfg.accountFloor = math.max(0, tonumber(entry.accountFloor) or cfg.accountFloor)
  cfg.percent = math.max(0, math.min(100, tonumber(entry.percent) or cfg.percent))
  cfg.minAmount = math.max(1, tonumber(entry.minAmount) or cfg.minAmount)
  cfg.tickers = {}
  if type(entry.tickers) == "table" then
    for symbol, on in pairs(entry.tickers) do
      if truthy(on) then cfg.tickers[tostring(symbol):upper()] = true end
    end
  end
  return cfg
end

local function normalizeOperator(op)
  op = trim(op):lower()
  if OPERATORS[op] then return op end
  return "gte"
end

local function compare(op, balance, amount)
  if op == "lt" then return balance < amount end
  if op == "lte" then return balance <= amount end
  if op == "eq" then return math.abs(balance - amount) < 0.01 end
  if op == "gt" then return balance > amount end
  return balance >= amount -- gte
end

--- Map a ledger reason/category to an auto-pay spend bucket.
function M.spendBucket(reason)
  reason = type(reason) == "table" and reason or {}
  local category = moneyCategories.normalize(reason.category) or moneyCategories.UNKNOWN
  local finance = type(reason.finance) == "table" and reason.finance or {}
  local tags = reason.tags
  local tagSet = {}
  if type(tags) == "table" then
    if tags[1] ~= nil then
      for _, t in ipairs(tags) do tagSet[tostring(t)] = true end
    else
      for k, v in pairs(tags) do
        if v then tagSet[tostring(k)] = true end
      end
    end
  end

  if finance.kind == "stocks" or tagSet.stocks or tagSet.stockMarket then
    return "stocks"
  end
  if category == "fine" or tagSet.fine then return "fines" end
  if category == "insurance" then return "insurance" end
  if category == "loan" then return "loans" end
  if category == "repair" then return "repairs" end
  if category == "fuel" then return "fuel" end
  if category == "service" then return "services" end
  if category == "property" then return "property" end
  if category == "purchase" then
    if finance.vehicleId or tagSet.vehicleBought or tagSet.buying or tagSet.vehicle then
      return "vehicles"
    end
    return "shops"
  end
  if category == "sale" or category == "reward" or category == "interest" or category == "refund"
      or category == "transfer" or category == "business" or category == "cheat" then
    return nil -- not a personal spend bucket
  end
  return "other"
end

--- Map a credit reason to an auto-deposit income bucket.
function M.incomeBucket(reason)
  reason = type(reason) == "table" and reason or {}
  local category = moneyCategories.normalize(reason.category) or moneyCategories.UNKNOWN
  if category == "reward" or category:match("^activity:") then return "reward" end
  if category == "sale" then return "sale" end
  if category == "interest" then return "interest" end
  if category == "refund" then return "refund" end
  return "other"
end

function M.load(data)
  state.accounts = {}
  state.payClaims = {}
  data = type(data) == "table" and data or {}
  local accountsData = data.accounts or {}
  for accountId, entry in pairs(accountsData) do
    if type(entry) == "table" then
      local cfg = defaultAccountAutomation()
      cfg.autoPayEnabled = entry.autoPayEnabled == true
      if type(entry.autoPay) == "table" then
        for _, key in ipairs(SPEND_CATEGORIES) do
          if entry.autoPay[key] then cfg.autoPay[key] = true end
        end
      end
      if type(entry.autoDeposit) == "table" then
        cfg.autoDeposit.enabled = entry.autoDeposit.enabled == true
        cfg.autoDeposit.walletFloor = math.max(0, tonumber(entry.autoDeposit.walletFloor) or 0)
        cfg.autoDeposit.percent = math.max(0, math.min(100, tonumber(entry.autoDeposit.percent) or 100))
        if type(entry.autoDeposit.income) == "table" then
          for _, key in ipairs(INCOME_CATEGORIES) do
            cfg.autoDeposit.income[key] = entry.autoDeposit.income[key] ~= false
          end
        end
      end
      cfg.autoInvest = normalizeAutoInvest(entry.autoInvest)
      if type(entry.balanceRules) == "table" then
        for _, rule in ipairs(entry.balanceRules) do
          if type(rule) == "table" and trim(rule.linkedAccountId) ~= "" then
            table.insert(cfg.balanceRules, {
              id = trim(rule.id) ~= "" and trim(rule.id) or Engine.generateUUID(),
              linkedAccountId = trim(rule.linkedAccountId),
              operator = normalizeOperator(rule.operator),
              amount = math.max(0, tonumber(rule.amount) or 0),
              action = rule.action == "topUp" and "topUp" or "sweepAbove",
              enabled = rule.enabled ~= false,
            })
          end
        end
      end
      state.accounts[tostring(accountId)] = cfg
    end
  end
  if type(data.payClaims) == "table" then
    for category, accountId in pairs(data.payClaims) do
      if trim(category) ~= "" and trim(accountId) ~= "" then
        state.payClaims[tostring(category)] = tostring(accountId)
      end
    end
  end
  -- Rebuild claims from account autoPay so save stays consistent.
  state.payClaims = {}
  for accountId, cfg in pairs(state.accounts) do
    if cfg.autoPayEnabled then
      for category, on in pairs(cfg.autoPay) do
        if on then state.payClaims[category] = accountId end
      end
    end
  end
end

function M.save()
  local accountsOut = {}
  for accountId, cfg in pairs(state.accounts) do
    accountsOut[accountId] = {
      autoPayEnabled = cfg.autoPayEnabled == true,
      autoPay = cfg.autoPay or {},
      autoDeposit = cfg.autoDeposit,
      autoInvest = cfg.autoInvest or defaultAutoInvest(),
      balanceRules = cfg.balanceRules or {},
    }
  end
  return {
    accounts = accountsOut,
    payClaims = state.payClaims,
  }
end

local function ensureCfg(accountId)
  accountId = tostring(accountId)
  if not state.accounts[accountId] then
    state.accounts[accountId] = defaultAccountAutomation()
  end
  return state.accounts[accountId]
end

local function getAccount(accountId)
  local bank = overhaul_career_economy_bank
  if not bank then return nil end
  if bank.getAccountById then
    return bank.getAccountById(accountId)
  end
  if not bank.getAccounts then return nil end
  for _, acc in ipairs(bank.getAccounts() or {}) do
    if acc.id == accountId then return acc end
  end
  return nil
end

local function availableTickers()
  local sm = overhaul_career_economy_stockMarket
  if sm and sm.listTickers then
    return sm.listTickers() or {}
  end
  return {}
end

function M.getAccountAutomation(accountId)
  accountId = tostring(accountId or "")
  local cfg = ensureCfg(accountId)
  if not cfg.autoInvest then cfg.autoInvest = defaultAutoInvest() end
  local claims = {}
  for category, ownerId in pairs(state.payClaims) do
    claims[category] = ownerId
  end
  return {
    autoPayEnabled = cfg.autoPayEnabled,
    autoPay = cfg.autoPay,
    autoDeposit = cfg.autoDeposit,
    autoInvest = cfg.autoInvest,
    balanceRules = cfg.balanceRules,
    payClaims = claims,
    spendCategories = SPEND_CATEGORIES,
    incomeCategories = INCOME_CATEGORIES,
    operators = { "lt", "lte", "eq", "gte", "gt" },
    tickers = availableTickers(),
  }
end

function M.setAutoPay(accountId, enabled, categories)
  accountId = tostring(accountId or "")
  local account = getAccount(accountId)
  if not isChecking(account) then return { ok = false, reason = "checking_only" } end
  local cfg = ensureCfg(accountId)
  cfg.autoPayEnabled = enabled == true
  if type(categories) == "table" then
    cfg.autoPay = {}
    for _, key in ipairs(SPEND_CATEGORIES) do
      if categories[key] then cfg.autoPay[key] = true end
    end
  end
  -- Exclusive claims: this account owns enabled categories; clear from others.
  for category, _ in pairs(state.payClaims) do
    if state.payClaims[category] == accountId then
      state.payClaims[category] = nil
    end
  end
  if cfg.autoPayEnabled then
    for category, on in pairs(cfg.autoPay) do
      if on then
        local previous = state.payClaims[category]
        if previous and previous ~= accountId then
          local other = ensureCfg(previous)
          other.autoPay[category] = nil
        end
        state.payClaims[category] = accountId
      end
    end
  end
  return { ok = true, automation = M.getAccountAutomation(accountId) }
end

function M.setAutoDeposit(accountId, depositCfg)
  accountId = tostring(accountId or "")
  local account = getAccount(accountId)
  if not isPersonal(account) then return { ok = false, reason = "personal_only" } end
  local cfg = ensureCfg(accountId)
  depositCfg = type(depositCfg) == "table" and depositCfg or {}
  cfg.autoDeposit.enabled = depositCfg.enabled == true
  cfg.autoDeposit.walletFloor = math.max(0, tonumber(depositCfg.walletFloor) or 0)
  cfg.autoDeposit.percent = math.max(0, math.min(100, tonumber(depositCfg.percent) or 100))
  if type(depositCfg.income) == "table" then
    for _, key in ipairs(INCOME_CATEGORIES) do
      cfg.autoDeposit.income[key] = depositCfg.income[key] ~= false
    end
  end
  return { ok = true, automation = M.getAccountAutomation(accountId) }
end

function M.setAutoInvest(accountId, investCfg)
  accountId = tostring(accountId or "")
  local account = getAccount(accountId)
  if not isChecking(account) then return { ok = false, reason = "checking_only" } end
  local cfg = ensureCfg(accountId)
  cfg.autoInvest = normalizeAutoInvest(investCfg)
  return { ok = true, automation = M.getAccountAutomation(accountId) }
end

function M.setBalanceRules(accountId, rules)
  accountId = tostring(accountId or "")
  local account = getAccount(accountId)
  if not isPersonal(account) then return { ok = false, reason = "personal_only" } end
  local cfg = ensureCfg(accountId)
  cfg.balanceRules = {}
  if type(rules) ~= "table" then
    return { ok = true, automation = M.getAccountAutomation(accountId) }
  end
  for _, rule in ipairs(rules) do
    if type(rule) == "table" then
      local linked = trim(rule.linkedAccountId)
      if linked ~= "" and linked ~= accountId then
        table.insert(cfg.balanceRules, {
          id = trim(rule.id) ~= "" and trim(rule.id) or Engine.generateUUID(),
          linkedAccountId = linked,
          operator = normalizeOperator(rule.operator),
          amount = math.max(0, tonumber(rule.amount) or 0),
          action = rule.action == "topUp" and "topUp" or "sweepAbove",
          enabled = rule.enabled ~= false,
        })
      end
    end
  end
  return { ok = true, automation = M.getAccountAutomation(accountId) }
end

--- Checking account claimed for this spend bucket, if auto-pay is enabled (ignores balance).
local function resolvePayAccountId(reason)
  local bucket = M.spendBucket(reason)
  if not bucket then return nil, nil end
  local accountId = state.payClaims[bucket]
  if not accountId then return nil, bucket end
  local cfg = state.accounts[accountId]
  if not cfg or not cfg.autoPayEnabled or not cfg.autoPay[bucket] then return nil, bucket end
  local account = getAccount(accountId)
  if not isChecking(account) then return nil, bucket end
  return accountId, bucket
end

--- Resolve which checking account should pay for this spend, if any.
function M.resolvePayAccount(reason, amount)
  amount = tonumber(amount) or 0
  local accountId = resolvePayAccountId(reason)
  if not accountId then return nil end
  local account = getAccount(accountId)
  if amount > 0 and (account.balance or 0) + 0.0001 < amount then
    return nil -- fall back to wallet
  end
  return accountId
end

--- Balance on the auto-pay checking account for this reason (0 if none / not enabled).
function M.getAutoPayBalance(reason)
  local accountId = resolvePayAccountId(reason)
  if not accountId then return 0 end
  local account = getAccount(accountId)
  return math.max(0, tonumber(account and account.balance) or 0)
end

--- Wallet + auto-pay checking for this category (checking spends first; wallet covers the rest).
function M.getSpendableMoney(reason)
  local wallet = 0
  if overhaul_career_economy_playerAttributes and overhaul_career_economy_playerAttributes.getAttributeValue then
    wallet = tonumber(overhaul_career_economy_playerAttributes.getAttributeValue("money")) or 0
  end
  return wallet + M.getAutoPayBalance(reason)
end

function M.maybeAutoDeposit(amount, reason)
  if applying then return end
  amount = tonumber(amount) or 0
  if amount <= 0 then return end
  local bucket = M.incomeBucket(reason)
  local bank = overhaul_career_economy_bank
  if not bank then return end

  -- Prefer a single enabled auto-deposit account (first personal with enabled + matching income).
  local candidates = {}
  for accountId, cfg in pairs(state.accounts) do
    if cfg.autoDeposit and cfg.autoDeposit.enabled and cfg.autoDeposit.income[bucket] ~= false then
      local account = getAccount(accountId)
      if isPersonal(account) then
        table.insert(candidates, { id = accountId, cfg = cfg, createdAt = account.createdAt or 0 })
      end
    end
  end
  table.sort(candidates, function(a, b) return a.createdAt < b.createdAt end)
  local pick = candidates[1]
  if not pick then return end

  local floor = pick.cfg.autoDeposit.walletFloor or 0
  local percent = (pick.cfg.autoDeposit.percent or 100) / 100
  local wallet = overhaul_career_economy_playerAttributes.getAttributeValue("money") or 0
  local surplus = math.max(0, wallet - floor)
  local toDeposit = math.min(surplus, amount * percent)
  if toDeposit < MIN_TRANSFER then return end

  -- Hold applying during deposit so nested balance/invest hooks don't re-enter mid-move.
  -- Deposit itself fires onAccountChanged while locked (no-op), so run it again after.
  applying = true
  pcall(function()
    bank.deposit(pick.id, toDeposit)
  end)
  applying = false
  M.onAccountChanged()
end

function M.evaluateBalanceRules()
  if applying then return end
  local bank = overhaul_career_economy_bank
  if not bank then return end
  applying = true
  local ok, err = pcall(function()
    for accountId, cfg in pairs(state.accounts) do
      local source = getAccount(accountId)
      if isPersonal(source) then
        for _, rule in ipairs(cfg.balanceRules or {}) do
          if rule.enabled ~= false then
            local target = getAccount(rule.linkedAccountId)
            if isPersonal(target) then
              local balance = source.balance or 0
              local threshold = rule.amount or 0
              if compare(rule.operator, balance, threshold) then
                local amount = 0
                if rule.action == "topUp" then
                  -- Move from linked -> source until source reaches threshold (when balance is below).
                  if balance < threshold then
                    local need = threshold - balance
                    amount = math.min(need, target.balance or 0)
                    if amount >= MIN_TRANSFER + HYSTERESIS or (amount >= MIN_TRANSFER and need <= HYSTERESIS) then
                      bank.transfer(target.id, source.id, amount)
                    end
                  end
                else
                  -- sweepAbove: move surplus above threshold to linked
                  if balance > threshold + HYSTERESIS then
                    amount = balance - threshold
                    if amount >= MIN_TRANSFER then
                      bank.transfer(source.id, target.id, amount)
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
  end)
  applying = false
  if not ok then
    log("E", "bank.automation", "evaluateBalanceRules failed: " .. tostring(err))
  end
end

function M.evaluateAutoInvest()
  if applying then return end
  local sm = overhaul_career_economy_stockMarket
  if not (sm and sm.investFromAccount) then return end

  applying = true
  local ok, err = pcall(function()
    for accountId, cfg in pairs(state.accounts) do
      local invest = cfg.autoInvest
      if invest and invest.enabled then
        local account = getAccount(accountId)
        if isChecking(account) then
          local floor = invest.accountFloor or 0
          local minAmount = invest.minAmount or 100
          local surplus = (account.balance or 0) - floor
          if surplus >= minAmount + HYSTERESIS then
            local toInvest = surplus * ((invest.percent or 100) / 100)
            if toInvest >= minAmount then
              if invest.mode == "stocks" then
                local hasTicker = false
                for _, on in pairs(invest.tickers or {}) do
                  if on then hasTicker = true break end
                end
                if hasTicker then
                  sm.investFromAccount(accountId, toInvest, { mode = "stocks", tickers = invest.tickers })
                end
              else
                sm.investFromAccount(accountId, toInvest, { mode = "broker" })
              end
            end
          end
        end
      end
    end
  end)
  applying = false
  if not ok then
    log("E", "bank.automation", "evaluateAutoInvest failed: " .. tostring(err))
  end
end

function M.onAccountChanged()
  M.evaluateBalanceRules()
  M.evaluateAutoInvest()
end

function M.clearAccount(accountId)
  accountId = tostring(accountId or "")
  state.accounts[accountId] = nil
  for category, owner in pairs(state.payClaims) do
    if owner == accountId then state.payClaims[category] = nil end
  end
end

M.SPEND_CATEGORIES = SPEND_CATEGORIES
M.INCOME_CATEGORIES = INCOME_CATEGORIES

return M
