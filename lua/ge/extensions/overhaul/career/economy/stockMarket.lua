-- Stock market: quotes track globalEconomy; manual trading + dump-and-forget managed broker.
-- Broker: buy-only balanced allocator, 0% buy fee, 5% sell fee on withdrawals; dividends → broker.cash.
local M = {}

local saveStore = require("overhaul/lib/save/store")
local ensureDir = require("overhaul/lib/save/ensureDir")
local metadata = require("overhaul/lib/finance/metadata")

local CONFIG_PATH = "/gameplay/overhaul/economy/stocks.json"
local HISTORY_DEFAULT = 48
local MANUAL_FEE_DEFAULT = 0
local BROKER_FEE_DEFAULT = 0.05
local DIVIDEND_INTERVAL_DEFAULT = 4
local SIM_TICKS_PER_YEAR_DEFAULT = 2880
local DEFAULT_DIVIDEND_YIELD = 0.03
local MAX_TX = 40
local MAX_BROKER_LOG = 30
local MIN_DEPLOY = 25
local DEPLOY_FRACTION = 0.4
local MAX_BUYS_PER_TICK = 5

local savePathFeature = nil
local config = nil
local state = {
  quotes = {},
  portfolio = {},
  broker = {
    cash = 0,
    enabled = false,
    profile = "balanced",
    holdings = {},
    lastActionAt = 0,
    depositTotal = 0,
  },
  transactions = {},
  brokerLog = {},
  dividendTickCounter = 0,
}

local function r2(amount)
  return math.floor((tonumber(amount) or 0) * 100 + 0.5) / 100
end

local function normalizeDividendPref(value)
  value = tostring(value or ""):lower()
  if value == "wallet" or value == "checking" or value == "reinvest" then
    return value
  end
  return "reinvest"
end

local function defaultYieldForSector(sector)
  if sector == "housingMarket" then return 0.036 end
  if sector == "jobMarket" then return 0.03 end
  if sector == "vehicleMarket" then return 0.022 end
  return DEFAULT_DIVIDEND_YIELD
end

local function loadConfig()
  if config then return config end
  local data = jsonReadFile(CONFIG_PATH) or {}
  config = {
    historyLength = math.max(8, tonumber(data.historyLength) or HISTORY_DEFAULT),
    manualFeeRate = math.max(0, tonumber(data.manualFeeRate) or MANUAL_FEE_DEFAULT),
    brokerFeeRate = math.max(0, tonumber(data.brokerFeeRate) or BROKER_FEE_DEFAULT),
    maxBrokerCashPerTicker = math.max(0.05, math.min(1, tonumber(data.maxBrokerCashPerTicker) or 0.25)),
    dividendIntervalTicks = math.max(1, math.floor(tonumber(data.dividendIntervalTicks) or DIVIDEND_INTERVAL_DEFAULT)),
    simTicksPerYear = math.max(100, math.floor(tonumber(data.simTicksPerYear) or SIM_TICKS_PER_YEAR_DEFAULT)),
    tickers = {},
  }
  for _, row in ipairs(data.tickers or {}) do
    if type(row) == "table" and row.symbol and row.name then
      local sector = tostring(row.sector or "global")
      local yield = tonumber(row.dividendYield)
      if not yield or yield < 0 then
        yield = defaultYieldForSector(sector)
      end
      table.insert(config.tickers, {
        symbol = tostring(row.symbol):upper(),
        name = tostring(row.name),
        orgId = row.orgId and tostring(row.orgId) or nil,
        sector = sector,
        basePrice = math.max(1, tonumber(row.basePrice) or 25),
        beta = math.max(0.2, tonumber(row.beta) or 1),
        dividendYield = math.max(0, math.min(0.2, yield)),
      })
    end
  end
  return config
end

local function tickerBySymbol(symbol)
  symbol = tostring(symbol or ""):upper()
  for _, t in ipairs(loadConfig().tickers) do
    if t.symbol == symbol then return t end
  end
  return nil
end

local function sectorIndex(sector)
  local ge = overhaul_career_economy_globalEconomy
  if not ge then return 1 end
  if sector == "vehicleMarket" and ge.getVehicleMarketIndex then
    return math.max(0.2, tonumber(ge.getVehicleMarketIndex()) or 1)
  end
  if sector == "housingMarket" and ge.getHousingMarketIndex then
    return math.max(0.2, tonumber(ge.getHousingMarketIndex()) or 1)
  end
  if sector == "jobMarket" and ge.getJobMarketIndex then
    return math.max(0.2, tonumber(ge.getJobMarketIndex()) or 1)
  end
  if ge.getGlobalIndex then
    return math.max(0.2, tonumber(ge.getGlobalIndex()) or 1)
  end
  return 1
end

local function noiseFor(symbol)
  local q = state.quotes[symbol]
  if not q then
    q = { noise = (math.random() - 0.5) * 0.04 }
    state.quotes[symbol] = q
  end
  q.noise = math.max(-0.06, math.min(0.06, (q.noise or 0) + (math.random() - 0.5) * 0.012))
  return q.noise
end

local function computePrice(ticker)
  local index = sectorIndex(ticker.sector)
  local noise = noiseFor(ticker.symbol)
  return r2(ticker.basePrice * (index ^ ticker.beta) * (1 + noise))
end

local function pushHistory(symbol, price)
  local q = state.quotes[symbol]
  if not q then
    q = { history = {}, noise = 0 }
    state.quotes[symbol] = q
  end
  q.history = q.history or {}
  table.insert(q.history, price)
  local maxLen = loadConfig().historyLength
  while #q.history > maxLen do
    table.remove(q.history, 1)
  end
end

local function refreshQuotes()
  loadConfig()
  for _, ticker in ipairs(config.tickers) do
    local q = state.quotes[ticker.symbol] or { history = {}, noise = (math.random() - 0.5) * 0.02 }
    local previous = q.price
    local price = computePrice(ticker)
    q.previous = previous or price
    q.price = price
    state.quotes[ticker.symbol] = q
    pushHistory(ticker.symbol, price)
  end
end

local function findHolding(list, symbol)
  symbol = tostring(symbol or ""):upper()
  for i, h in ipairs(list or {}) do
    if h.ticker == symbol then return h, i end
  end
  return nil, nil
end

local function stocksReason(label, description)
  return metadata.tag({
    label = label or "Stock trade",
    description = description or "",
  }, "purchase", { kind = "stocks" })
end

local function saleReason(label, description)
  return metadata.tag({
    label = label or "Stock sale",
    description = description or "",
  }, "sale", { kind = "stocks" })
end

local function dividendReason(label, description)
  return metadata.tag({
    label = label or "Stock dividend",
    description = description or "",
  }, "sale", { kind = "stocks", income = "dividends" })
end

local function payMoney(amount, reason, accountId)
  amount = r2(amount)
  if amount <= 0 then return true end
  local payment = overhaul_career_economy_payment
  if not payment or not payment.pay then return false end
  return payment.pay({ money = { amount = amount } }, reason, accountId) == true
end

local function rewardMoney(amount, reason, accountId)
  amount = r2(amount)
  if amount <= 0 then return true end
  local payment = overhaul_career_economy_payment
  if not payment or not payment.reward then return false end
  return payment.reward({ money = { amount = amount } }, reason, nil, accountId) == true
end

local function firstCheckingAccountId()
  local bank = overhaul_career_economy_bank
  if not (bank and bank.getAccounts) then return nil end
  for _, acc in ipairs(bank.getAccounts() or {}) do
    if (acc.type or "") == "personal" then
      local kind = acc.accountType
      if kind == nil or kind == "" or kind == "checking" then
        return acc.id
      end
    end
  end
  return nil
end

local function recordTx(entry)
  entry.id = entry.id or (Engine and Engine.generateUUID and Engine.generateUUID()) or tostring(os.time()) .. math.random(1000)
  entry.at = entry.at or (os.time and os.time() or 0)
  table.insert(state.transactions, 1, entry)
  while #state.transactions > MAX_TX do
    table.remove(state.transactions)
  end
end

local function recordBrokerLog(message, extra)
  local row = {
    id = (Engine and Engine.generateUUID and Engine.generateUUID()) or tostring(os.time()) .. math.random(1000),
    at = os.time and os.time() or 0,
    message = message,
  }
  if type(extra) == "table" then
    for k, v in pairs(extra) do row[k] = v end
  end
  table.insert(state.brokerLog, 1, row)
  while #state.brokerLog > MAX_BROKER_LOG do
    table.remove(state.brokerLog)
  end
end

local function applyBuy(list, symbol, shares, price, extras)
  shares = tonumber(shares) or 0
  if shares <= 0 then return end
  local holding = findHolding(list, symbol)
  if holding then
    local totalShares = holding.shares + shares
    holding.avgCost = ((holding.avgCost * holding.shares) + (price * shares)) / totalShares
    holding.shares = totalShares
  else
    local row = {
      ticker = symbol,
      shares = shares,
      avgCost = price,
    }
    if type(extras) == "table" then
      for k, v in pairs(extras) do row[k] = v end
    end
    if list == state.portfolio then
      row.dividendPref = normalizeDividendPref(row.dividendPref)
      row.pendingDividend = tonumber(row.pendingDividend) or 0
    end
    table.insert(list, row)
  end
end

local function applySell(list, symbol, shares)
  shares = tonumber(shares) or 0
  local holding, index = findHolding(list, symbol)
  if not holding or shares <= 0 then return 0 end
  local sold = math.min(shares, holding.shares)
  holding.shares = holding.shares - sold
  if holding.shares <= 0.0001 then
    table.remove(list, index)
  end
  return sold
end

local function quotePrice(symbol)
  symbol = tostring(symbol or ""):upper()
  local q = state.quotes[symbol]
  if q and q.price then return q.price end
  local ticker = tickerBySymbol(symbol)
  if not ticker then return nil end
  return computePrice(ticker)
end

local function saveFilePath(currentSavePath)
  if not savePathFeature then
    savePathFeature = saveStore.bind(overhaul_career_saveSystem).feature("economy.stockMarket", {
      owner = "overhaul_career_economy_stockMarket",
      files = {"career/rls_career/stockMarket.json"},
      phase = "profile",
      root = "slot",
      required = true,
    })
  end
  return currentSavePath .. "/" .. savePathFeature.path("")
end

local function defaultState()
  return {
    quotes = {},
    portfolio = {},
    broker = {
      cash = 0,
      enabled = false,
      profile = "balanced",
      holdings = {},
      lastActionAt = 0,
      depositTotal = 0,
    },
    transactions = {},
    brokerLog = {},
    dividendTickCounter = 0,
  }
end

local function loadState()
  local _, currentSavePath = overhaul_career_saveSystem.getCurrentProfile()
  if not currentSavePath then
    state = defaultState()
    return
  end
  local data = jsonReadFile(saveFilePath(currentSavePath)) or {}
  state = defaultState()
  if type(data.quotes) == "table" then
    for symbol, q in pairs(data.quotes) do
      if type(q) == "table" then
        state.quotes[tostring(symbol):upper()] = {
          price = tonumber(q.price),
          previous = tonumber(q.previous),
          noise = tonumber(q.noise) or 0,
          history = type(q.history) == "table" and q.history or {},
        }
      end
    end
  end
  if type(data.portfolio) == "table" then
    for _, h in ipairs(data.portfolio) do
      if type(h) == "table" and h.ticker and (tonumber(h.shares) or 0) > 0 then
        table.insert(state.portfolio, {
          ticker = tostring(h.ticker):upper(),
          shares = tonumber(h.shares) or 0,
          avgCost = tonumber(h.avgCost) or 0,
          dividendPref = normalizeDividendPref(h.dividendPref),
          pendingDividend = math.max(0, tonumber(h.pendingDividend) or 0),
        })
      end
    end
  end
  if type(data.broker) == "table" then
    state.broker.cash = tonumber(data.broker.cash) or 0
    state.broker.enabled = data.broker.enabled == true
    state.broker.profile = tostring(data.broker.profile or "balanced")
    if state.broker.profile ~= "safe" and state.broker.profile ~= "risky" and state.broker.profile ~= "balanced" then
      state.broker.profile = "balanced"
    end
    state.broker.lastActionAt = tonumber(data.broker.lastActionAt) or 0
    state.broker.depositTotal = tonumber(data.broker.depositTotal) or 0
    if type(data.broker.holdings) == "table" then
      for _, h in ipairs(data.broker.holdings) do
        if type(h) == "table" and h.ticker and (tonumber(h.shares) or 0) > 0 then
          table.insert(state.broker.holdings, {
            ticker = tostring(h.ticker):upper(),
            shares = tonumber(h.shares) or 0,
            avgCost = tonumber(h.avgCost) or 0,
          })
        end
      end
    end
  end
  if type(data.transactions) == "table" then
    state.transactions = data.transactions
  end
  if type(data.brokerLog) == "table" then
    state.brokerLog = data.brokerLog
  end
  state.dividendTickCounter = math.max(0, math.floor(tonumber(data.dividendTickCounter) or 0))
  refreshQuotes()
end

local function saveState(currentSavePath, writer)
  if not currentSavePath then
    local _, path = overhaul_career_saveSystem.getCurrentProfile()
    currentSavePath = path
  end
  if not currentSavePath then return end
  ensureDir.parentOf(writer, saveFilePath(currentSavePath))
  local quotesOut = {}
  for symbol, q in pairs(state.quotes) do
    quotesOut[symbol] = {
      price = q.price,
      previous = q.previous,
      noise = q.noise,
      history = q.history,
    }
  end
  overhaul_career_saveSystem.jsonWriteFileSafe(saveFilePath(currentSavePath), {
    quotes = quotesOut,
    portfolio = state.portfolio,
    broker = state.broker,
    transactions = state.transactions,
    brokerLog = state.brokerLog,
    dividendTickCounter = state.dividendTickCounter,
  }, true)
end

local function pctChange(price, previous)
  if not previous or previous <= 0 then return 0 end
  return ((price - previous) / previous) * 100
end

local function shortReturn(symbol)
  local q = state.quotes[symbol]
  if not q or not q.history or #q.history < 2 then return 0 end
  local latest = q.history[#q.history]
  local older = q.history[math.max(1, #q.history - 3)]
  if not older or older <= 0 then return 0 end
  return (latest - older) / older
end

local function recentAverage(symbol, window)
  local q = state.quotes[symbol]
  if not q or not q.history or #q.history == 0 then
    return quotePrice(symbol)
  end
  window = math.min(window or 8, #q.history)
  local sum = 0
  for i = #q.history - window + 1, #q.history do
    sum = sum + (tonumber(q.history[i]) or 0)
  end
  return sum / window
end

local function marketRows()
  local rows = {}
  for _, ticker in ipairs(loadConfig().tickers) do
    local q = state.quotes[ticker.symbol] or {}
    local price = q.price or computePrice(ticker)
    local previous = q.previous or price
    table.insert(rows, {
      symbol = ticker.symbol,
      name = ticker.name,
      orgId = ticker.orgId,
      sector = ticker.sector,
      price = price,
      previous = previous,
      changePct = pctChange(price, previous),
      history = q.history or { price },
      beta = ticker.beta,
      dividendYield = ticker.dividendYield,
    })
  end
  table.sort(rows, function(a, b) return a.symbol < b.symbol end)
  return rows
end

local function enrichHoldings(list, includeDividend)
  local rows = {}
  for _, h in ipairs(list or {}) do
    local price = quotePrice(h.ticker) or h.avgCost
    local value = r2(price * h.shares)
    local cost = r2(h.avgCost * h.shares)
    local ticker = tickerBySymbol(h.ticker) or {}
    local row = {
      ticker = h.ticker,
      shares = h.shares,
      avgCost = r2(h.avgCost),
      price = price,
      value = value,
      cost = cost,
      unrealized = r2(value - cost),
      unrealizedPct = cost > 0 and ((value - cost) / cost) * 100 or 0,
      name = ticker.name or h.ticker,
      dividendYield = ticker.dividendYield or DEFAULT_DIVIDEND_YIELD,
    }
    if includeDividend then
      row.dividendPref = normalizeDividendPref(h.dividendPref)
      row.pendingDividend = r2(h.pendingDividend or 0)
    end
    table.insert(rows, row)
  end
  return rows
end

local function brokerHoldingsNotional()
  local total = 0
  for _, h in ipairs(state.broker.holdings or {}) do
    local price = quotePrice(h.ticker) or h.avgCost or 0
    total = total + price * (h.shares or 0)
  end
  return total
end

local function withdrawableMax()
  local feeRate = loadConfig().brokerFeeRate
  return r2((state.broker.cash or 0) + brokerHoldingsNotional() * (1 - feeRate))
end

function M.getOverview()
  loadConfig()
  if not next(state.quotes) then refreshQuotes() end
  local portfolio = enrichHoldings(state.portfolio, true)
  local brokerHoldings = enrichHoldings(state.broker.holdings, false)
  local portfolioValue = 0
  for _, h in ipairs(portfolio) do portfolioValue = portfolioValue + h.value end
  local brokerHoldingsValue = 0
  for _, h in ipairs(brokerHoldings) do brokerHoldingsValue = brokerHoldingsValue + h.value end
  local feeRate = loadConfig().brokerFeeRate
  return {
    markets = marketRows(),
    portfolio = portfolio,
    portfolioValue = r2(portfolioValue),
    broker = {
      cash = r2(state.broker.cash),
      enabled = state.broker.enabled == true,
      profile = state.broker.profile or "balanced",
      holdings = brokerHoldings,
      holdingsValue = r2(brokerHoldingsValue),
      depositTotal = r2(state.broker.depositTotal),
      feeRate = feeRate,
      withdrawableMax = withdrawableMax(),
      lastActionAt = state.broker.lastActionAt,
    },
    transactions = state.transactions,
    brokerLog = state.brokerLog,
    wallet = overhaul_career_economy_playerAttributes
      and (overhaul_career_economy_playerAttributes.getAttributeValue("money") or 0) or 0,
    manualFeeRate = loadConfig().manualFeeRate,
  }
end

function M.listTickers()
  local rows = {}
  for _, ticker in ipairs(loadConfig().tickers) do
    table.insert(rows, {
      symbol = ticker.symbol,
      name = ticker.name,
      sector = ticker.sector,
      dividendYield = ticker.dividendYield,
    })
  end
  return rows
end

function M.buyShares(symbol, shares, accountId)
  symbol = tostring(symbol or ""):upper()
  shares = math.floor(tonumber(shares) or 0)
  local ticker = tickerBySymbol(symbol)
  if not ticker then return { ok = false, reason = "unknown_ticker" } end
  if shares < 1 then return { ok = false, reason = "invalid_shares" } end
  local price = quotePrice(symbol)
  if not price then return { ok = false, reason = "no_quote" } end
  local notional = r2(price * shares)
  local fee = r2(notional * loadConfig().manualFeeRate)
  local total = r2(notional + fee)
  local reason = stocksReason("Bought " .. symbol, shares .. " shares @ $" .. tostring(price))
  if not payMoney(total, reason, accountId) then
    return { ok = false, reason = "funds" }
  end
  applyBuy(state.portfolio, symbol, shares, price, { dividendPref = "reinvest", pendingDividend = 0 })
  recordTx({
    side = "buy",
    source = accountId and "auto" or "manual",
    ticker = symbol,
    shares = shares,
    price = price,
    fee = fee,
    total = total,
  })
  return { ok = true, overview = M.getOverview() }
end

function M.sellShares(symbol, shares)
  symbol = tostring(symbol or ""):upper()
  shares = math.floor(tonumber(shares) or 0)
  local holding = findHolding(state.portfolio, symbol)
  if not holding then return { ok = false, reason = "no_holding" } end
  if shares < 1 then return { ok = false, reason = "invalid_shares" } end
  shares = math.min(shares, math.floor(holding.shares))
  local price = quotePrice(symbol)
  if not price then return { ok = false, reason = "no_quote" } end
  local notional = r2(price * shares)
  local fee = r2(notional * loadConfig().manualFeeRate)
  local proceeds = r2(notional - fee)
  applySell(state.portfolio, symbol, shares)
  rewardMoney(proceeds, saleReason("Sold " .. symbol, shares .. " shares @ $" .. tostring(price)))
  recordTx({
    side = "sell",
    source = "manual",
    ticker = symbol,
    shares = shares,
    price = price,
    fee = fee,
    total = proceeds,
  })
  return { ok = true, overview = M.getOverview() }
end

function M.setDividendPreference(symbol, mode)
  symbol = tostring(symbol or ""):upper()
  local holding = findHolding(state.portfolio, symbol)
  if not holding then return { ok = false, reason = "no_holding" } end
  holding.dividendPref = normalizeDividendPref(mode)
  return { ok = true, overview = M.getOverview() }
end

function M.depositBroker(amount, accountId)
  amount = r2(amount)
  if amount < 1 then return { ok = false, reason = "invalid_amount" } end
  local reason = stocksReason(
    accountId and "Auto-invest broker deposit" or "Broker deposit",
    "Managed trading capital"
  )
  if not payMoney(amount, reason, accountId) then
    return { ok = false, reason = "funds" }
  end
  state.broker.cash = r2(state.broker.cash + amount)
  state.broker.depositTotal = r2(state.broker.depositTotal + amount)
  recordBrokerLog((accountId and "Auto-deposited $" or "Deposited $") .. tostring(amount))
  recordTx({ side = "deposit", source = accountId and "auto" or "broker", total = amount })
  return { ok = true, overview = M.getOverview() }
end

--- Spend up to `amount` from a bank account into broker cash or selected tickers.
function M.investFromAccount(accountId, amount, opts)
  accountId = tostring(accountId or "")
  amount = r2(amount)
  opts = type(opts) == "table" and opts or {}
  if accountId == "" or amount < 1 then return { ok = false, reason = "invalid" } end

  local mode = opts.mode == "stocks" and "stocks" or "broker"
  if mode == "broker" then
    local res = M.depositBroker(amount, accountId)
    return { ok = res.ok == true, invested = res.ok and amount or 0, reason = res.reason, mode = mode }
  end

  local symbols = {}
  if type(opts.tickers) == "table" then
    for symbol, on in pairs(opts.tickers) do
      if on and tickerBySymbol(symbol) then
        table.insert(symbols, tostring(symbol):upper())
      end
    end
  end
  table.sort(symbols)
  if #symbols == 0 then return { ok = false, reason = "no_tickers", mode = mode } end

  refreshQuotes()
  local budgetEach = amount / #symbols
  local invested = 0
  for _, symbol in ipairs(symbols) do
    local price = quotePrice(symbol)
    if price and price > 0 then
      local feeRate = loadConfig().manualFeeRate
      local shares = math.floor(budgetEach / (price * (1 + feeRate)))
      if shares >= 1 then
        local res = M.buyShares(symbol, shares, accountId)
        if res.ok then
          invested = r2(invested + (price * shares * (1 + feeRate)))
        end
      end
    end
  end
  return { ok = invested > 0, invested = invested, mode = mode }
end

function M.setBrokerEnabled(enabled)
  state.broker.enabled = enabled == true
  recordBrokerLog(state.broker.enabled and "Managed trading enabled" or "Managed trading paused")
  return { ok = true, overview = M.getOverview() }
end

-- Broker buys are free (fee only on withdrawal sells).
local function brokerBuy(symbol, spendCash)
  local price = quotePrice(symbol)
  if not price or price <= 0 then return 0 end
  local shares = math.floor(spendCash / price)
  if shares < 1 then return 0 end
  local cost = r2(price * shares)
  if cost > state.broker.cash + 0.0001 then return 0 end
  state.broker.cash = r2(state.broker.cash - cost)
  applyBuy(state.broker.holdings, symbol, shares, price)
  recordBrokerLog("Bought " .. shares .. " " .. symbol, { ticker = symbol, shares = shares, fee = 0 })
  recordTx({ side = "buy", source = "broker", ticker = symbol, shares = shares, price = price, fee = 0, total = cost })
  return cost
end

local function brokerSell(symbol, shares)
  local price = quotePrice(symbol)
  if not price then return 0, 0 end
  local sold = applySell(state.broker.holdings, symbol, shares)
  if sold <= 0 then return 0, 0 end
  local notional = r2(price * sold)
  local fee = r2(notional * loadConfig().brokerFeeRate)
  local proceeds = r2(notional - fee)
  state.broker.cash = r2(state.broker.cash + proceeds)
  recordBrokerLog("Sold " .. sold .. " " .. symbol, { ticker = symbol, shares = sold, fee = fee })
  recordTx({ side = "sell", source = "broker", ticker = symbol, shares = sold, price = price, fee = fee, total = proceeds })
  return proceeds, fee
end

local function sortedBrokerHoldingsForSell()
  local copies = {}
  for _, h in ipairs(state.broker.holdings or {}) do
    table.insert(copies, {
      ticker = h.ticker,
      shares = h.shares,
      avgCost = h.avgCost,
    })
  end
  table.sort(copies, function(a, b)
    local pa = quotePrice(a.ticker) or a.avgCost or 0
    local pb = quotePrice(b.ticker) or b.avgCost or 0
    local ga = (a.avgCost or 0) > 0 and ((pa - a.avgCost) / a.avgCost) or 0
    local gb = (b.avgCost or 0) > 0 and ((pb - b.avgCost) / b.avgCost) or 0
    if math.abs(ga - gb) > 1e-9 then return ga > gb end
    return (pa * a.shares) > (pb * b.shares)
  end)
  return copies
end

local function buildWithdrawPlan(amount)
  local feeRate = loadConfig().brokerFeeRate
  local maxW = withdrawableMax()
  local requested = r2(math.max(0, tonumber(amount) or 0))
  local payable = r2(math.min(requested, maxW))
  local cash = r2(state.broker.cash or 0)
  local fromCash = r2(math.min(cash, payable))
  local need = r2(payable - fromCash)

  local sharesToSell = {}
  local fromSales = 0
  local fee = 0
  local remainingNeed = need

  -- Simulate sells on a shadow copy of share counts
  local shadow = {}
  for _, h in ipairs(state.broker.holdings or {}) do
    shadow[h.ticker] = h.shares
  end
  local order = sortedBrokerHoldingsForSell()

  while remainingNeed > 0.009 do
    local picked = nil
    for _, row in ipairs(order) do
      local left = shadow[row.ticker] or 0
      if left >= 1 then
        picked = row
        break
      end
    end
    if not picked then break end

    local price = quotePrice(picked.ticker)
    if not price or price <= 0 then
      shadow[picked.ticker] = 0
    else
      local netPer = price * (1 - feeRate)
      if netPer <= 0 then break end
      local n = math.ceil((remainingNeed / netPer) - 1e-12)
      n = math.max(1, n)
      n = math.min(n, math.floor(shadow[picked.ticker]))
      local notional = price * n
      local sellFee = notional * feeRate
      local proceeds = notional - sellFee
      shadow[picked.ticker] = shadow[picked.ticker] - n
      fromSales = fromSales + proceeds
      fee = fee + sellFee
      remainingNeed = remainingNeed - proceeds
      local existing = nil
      for _, s in ipairs(sharesToSell) do
        if s.ticker == picked.ticker then existing = s break end
      end
      if existing then
        existing.shares = existing.shares + n
        existing.fee = r2(existing.fee + sellFee)
        existing.proceeds = r2(existing.proceeds + proceeds)
      else
        table.insert(sharesToSell, {
          ticker = picked.ticker,
          shares = n,
          price = price,
          fee = r2(sellFee),
          proceeds = r2(proceeds),
        })
      end
    end
  end

  fromSales = r2(fromSales)
  fee = r2(fee)
  local raised = r2(fromCash + fromSales)
  if raised + 0.0001 < payable then
    payable = raised
  end
  local excessToPool = r2(math.max(0, raised - payable))

  return {
    requested = requested,
    payable = payable,
    fromCash = fromCash,
    fromSales = fromSales,
    fee = fee,
    sharesToSell = sharesToSell,
    excessToPool = excessToPool,
    withdrawableMax = maxW,
    shortfall = r2(math.max(0, requested - payable)),
  }
end

function M.previewWithdraw(amount)
  return buildWithdrawPlan(amount)
end

function M.withdrawFromHoldings(amount)
  local plan = buildWithdrawPlan(amount)
  if plan.payable < 0.01 then
    return { ok = false, reason = "nothing_to_withdraw", overview = M.getOverview(), preview = plan }
  end

  local fromCash = plan.fromCash
  if fromCash > 0 then
    state.broker.cash = r2(state.broker.cash - fromCash)
  end

  local fromSales = 0
  local fee = 0
  for _, s in ipairs(plan.sharesToSell) do
    local proceeds, sellFee = brokerSell(s.ticker, s.shares)
    fromSales = fromSales + proceeds
    fee = fee + sellFee
  end
  fromSales = r2(fromSales)
  fee = r2(fee)

  -- brokerSell credited proceeds into cash; pay user from cash (fromCash already removed)
  local payable = plan.payable
  local needFromProceeds = r2(payable - fromCash)
  if needFromProceeds > state.broker.cash + 0.0001 then
    needFromProceeds = state.broker.cash
    payable = r2(fromCash + needFromProceeds)
  end
  if needFromProceeds > 0 then
    state.broker.cash = r2(state.broker.cash - needFromProceeds)
  end

  rewardMoney(payable, saleReason("Broker withdraw", "Withdrawn from managed holdings"))
  local excess = r2(state.broker.cash) -- remainder is pool
  recordBrokerLog(
    "Withdrew $" .. tostring(payable)
      .. (fee > 0 and (" · fee $" .. tostring(r2(fee))) or "")
      .. (excess > 0.009 and (" · $" .. tostring(excess) .. " left in pool") or "")
  )
  recordTx({
    side = "withdraw",
    source = "broker",
    total = payable,
    fee = r2(fee),
    fromCash = fromCash,
    fromSales = fromSales,
  })

  local result = {
    ok = true,
    requested = plan.requested,
    payable = payable,
    fromCash = fromCash,
    fromSales = fromSales,
    fee = r2(fee),
    sharesToSell = plan.sharesToSell,
    excessToPool = excess,
    withdrawableMax = withdrawableMax(),
    shortfall = r2(math.max(0, plan.requested - payable)),
    overview = M.getOverview(),
  }
  return result
end

function M.withdrawAll()
  return M.withdrawFromHoldings(withdrawableMax())
end

-- Compat: cash-only withdraw becomes holdings withdraw (cash-first).
function M.withdrawBroker(amount)
  return M.withdrawFromHoldings(amount)
end

-- Compat: liquidate everything then pause managed trading.
function M.closeBroker()
  local res = M.withdrawAll()
  state.broker.enabled = false
  recordBrokerLog("Managed trading paused after full withdraw")
  res.overview = M.getOverview()
  return res
end

local function scoreTickerBalanced(ticker, portfolioValue, targetWeight)
  local price = quotePrice(ticker.symbol)
  if not price or price <= 0 then return nil end
  local ret = shortReturn(ticker.symbol)
  if ret < -0.12 then return nil end -- avoid catching a falling knife

  local holding = findHolding(state.broker.holdings, ticker.symbol)
  local value = holding and (price * holding.shares) or 0
  local weight = portfolioValue > 0 and (value / portfolioValue) or 0
  local underweight = math.max(0, targetWeight - weight) * 10

  local avg = recentAverage(ticker.symbol, 8) or price
  local dip = 0
  if avg > 0 then
    dip = math.max(0, (avg - price) / avg) * 5
  end

  local idx = sectorIndex(ticker.sector)
  local sectorHealth = math.max(-1, math.min(1, (idx - 0.85) / 0.3)) * 1.5
  local yieldBoost = (ticker.dividendYield or DEFAULT_DIVIDEND_YIELD) * 20

  return underweight + dip + sectorHealth + yieldBoost
end

local function runBrokerTickBalanced()
  local cash = state.broker.cash or 0
  if cash < MIN_DEPLOY then
    state.broker.lastActionAt = os.time and os.time() or 0
    return
  end

  local cfg = loadConfig()
  local n = #cfg.tickers
  if n < 1 then return end

  local holdingsValue = brokerHoldingsNotional()
  local portfolioValue = math.max(cash + holdingsValue, 1)
  local targetWeight = 1 / n
  local maxWeight = math.max(targetWeight, cfg.maxBrokerCashPerTicker)

  local scored = {}
  for _, ticker in ipairs(cfg.tickers) do
    local score = scoreTickerBalanced(ticker, portfolioValue, targetWeight)
    if score then
      table.insert(scored, { ticker = ticker, score = score, symbol = ticker.symbol })
    end
  end
  table.sort(scored, function(a, b) return a.score > b.score end)

  local deployBudget = cash * DEPLOY_FRACTION
  local buys = 0
  for _, row in ipairs(scored) do
    if buys >= MAX_BUYS_PER_TICK or deployBudget < MIN_DEPLOY then break end
    local price = quotePrice(row.symbol)
    if price and price > 0 then
      local holding = findHolding(state.broker.holdings, row.symbol)
      local already = holding and price * holding.shares or 0
      local capValue = portfolioValue * maxWeight
      local room = capValue - already
      if room >= price then
        local spend = math.min(deployBudget, room, state.broker.cash)
        -- split remaining budget across remaining slots roughly
        local slotsLeft = math.max(1, MAX_BUYS_PER_TICK - buys)
        spend = math.min(spend, deployBudget / slotsLeft * 1.25)
        if spend >= MIN_DEPLOY and spend >= price then
          local spent = brokerBuy(row.symbol, spend)
          if spent > 0 then
            deployBudget = deployBudget - spent
            buys = buys + 1
            -- refresh portfolio value soft estimate
            portfolioValue = math.max((state.broker.cash or 0) + brokerHoldingsNotional(), 1)
          end
        end
      end
    end
  end
  state.broker.lastActionAt = os.time and os.time() or 0
end

-- Future: safe / risky profiles dispatch here. Only balanced is implemented.
function M.runBrokerTick()
  if not state.broker.enabled then return end
  if (state.broker.cash or 0) <= 0 and #(state.broker.holdings or {}) == 0 then return end
  local profile = state.broker.profile or "balanced"
  if profile == "safe" or profile == "risky" then
    -- Not implemented yet — fall through to balanced buy-only.
    profile = "balanced"
  end
  if profile == "balanced" then
    runBrokerTickBalanced()
  end
end

local function dripReinvest(holding, price)
  holding.pendingDividend = tonumber(holding.pendingDividend) or 0
  if not price or price <= 0 then return end
  while holding.pendingDividend + 0.0001 >= price do
    holding.pendingDividend = r2(holding.pendingDividend - price)
    applyBuy(state.portfolio, holding.ticker, 1, price)
    recordTx({
      side = "dividend",
      source = "reinvest",
      ticker = holding.ticker,
      shares = 1,
      price = price,
      fee = 0,
      total = price,
    })
  end
end

local function payDividends()
  local cfg = loadConfig()
  state.dividendTickCounter = (state.dividendTickCounter or 0) + 1
  if state.dividendTickCounter % cfg.dividendIntervalTicks ~= 0 then
    return
  end

  local fraction = (cfg.dividendIntervalTicks / cfg.simTicksPerYear)

  for _, holding in ipairs(state.portfolio) do
    local ticker = tickerBySymbol(holding.ticker)
    local price = quotePrice(holding.ticker)
    if ticker and price and (holding.shares or 0) > 0 then
      local gross = r2(holding.shares * price * (ticker.dividendYield or DEFAULT_DIVIDEND_YIELD) * fraction)
      if gross >= 0.01 then
        local pref = normalizeDividendPref(holding.dividendPref)
        if pref == "reinvest" then
          holding.pendingDividend = r2((holding.pendingDividend or 0) + gross)
          dripReinvest(holding, price)
          recordTx({
            side = "dividend",
            source = "manual",
            ticker = holding.ticker,
            total = gross,
            note = "accrued",
          })
        elseif pref == "checking" then
          local accountId = firstCheckingAccountId()
          rewardMoney(gross, dividendReason("Dividend " .. holding.ticker, "Portfolio dividend"), accountId)
          recordTx({
            side = "dividend",
            source = accountId and "checking" or "wallet",
            ticker = holding.ticker,
            total = gross,
          })
        else
          rewardMoney(gross, dividendReason("Dividend " .. holding.ticker, "Portfolio dividend"))
          recordTx({
            side = "dividend",
            source = "wallet",
            ticker = holding.ticker,
            total = gross,
          })
        end
      end
    end
  end

  local brokerDivTotal = 0
  for _, holding in ipairs(state.broker.holdings) do
    local ticker = tickerBySymbol(holding.ticker)
    local price = quotePrice(holding.ticker)
    if ticker and price and (holding.shares or 0) > 0 then
      local gross = r2(holding.shares * price * (ticker.dividendYield or DEFAULT_DIVIDEND_YIELD) * fraction)
      if gross >= 0.01 then
        state.broker.cash = r2(state.broker.cash + gross)
        brokerDivTotal = brokerDivTotal + gross
        recordTx({
          side = "dividend",
          source = "broker",
          ticker = holding.ticker,
          total = gross,
        })
      end
    end
  end
  if brokerDivTotal >= 0.01 then
    recordBrokerLog("Dividends $" .. tostring(r2(brokerDivTotal)) .. " → holding pool")
  end
end

function M.onEconomyUpdated()
  refreshQuotes()
  local okDiv, errDiv = pcall(payDividends)
  if not okDiv then
    log("E", "stockMarket", "dividends failed: " .. tostring(errDiv))
  end
  local ok, err = pcall(M.runBrokerTick)
  if not ok then
    log("E", "stockMarket", "broker tick failed: " .. tostring(err))
  end
end

local function onOverhaulSaveCurrentProfile(currentSavePath, _, writer)
  writer = writer or overhaul_career_saveSystem.getSaveWriter()
  saveState(currentSavePath, writer)
end

local function onExtensionLoaded()
  loadConfig()
end

local function onCareerActivated()
  loadState()
end

M.onOverhaulSaveCurrentProfile = onOverhaulSaveCurrentProfile
M.onExtensionLoaded = onExtensionLoaded
M.onCareerActivated = onCareerActivated

return M
