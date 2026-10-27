-- Stock market: quotes track globalEconomy sector indices; manual trading + managed broker (5% fee).
local M = {}

local saveStore = require("overhaul/lib/save/store")
local ensureDir = require("overhaul/lib/save/ensureDir")
local metadata = require("overhaul/lib/finance/metadata")

local CONFIG_PATH = "/gameplay/overhaul/economy/stocks.json"
local HISTORY_DEFAULT = 48
local MANUAL_FEE_DEFAULT = 0
local BROKER_FEE_DEFAULT = 0.05
local MAX_TX = 40
local MAX_BROKER_LOG = 30

local savePathFeature = nil
local config = nil
local state = {
  quotes = {}, -- symbol -> { price, previous, history = {}, noise }
  portfolio = {}, -- array { ticker, shares, avgCost }
  broker = {
    cash = 0,
    enabled = false,
    holdings = {}, -- array { ticker, shares, avgCost }
    lastActionAt = 0,
    depositTotal = 0,
  },
  transactions = {},
  brokerLog = {},
}

local function r2(amount)
  return math.floor((tonumber(amount) or 0) * 100 + 0.5) / 100
end

local function trim(value)
  return tostring(value or ""):match("^%s*(.-)%s*$") or ""
end

local function loadConfig()
  if config then return config end
  local data = jsonReadFile(CONFIG_PATH) or {}
  config = {
    historyLength = math.max(8, tonumber(data.historyLength) or HISTORY_DEFAULT),
    manualFeeRate = math.max(0, tonumber(data.manualFeeRate) or MANUAL_FEE_DEFAULT),
    brokerFeeRate = math.max(0, tonumber(data.brokerFeeRate) or BROKER_FEE_DEFAULT),
    maxBrokerCashPerTicker = math.max(0.05, math.min(1, tonumber(data.maxBrokerCashPerTicker) or 0.25)),
    brokerTakeProfit = tonumber(data.brokerTakeProfit) or 0.12,
    brokerCutLoss = tonumber(data.brokerCutLoss) or -0.08,
    tickers = {},
  }
  for _, row in ipairs(data.tickers or {}) do
    if type(row) == "table" and row.symbol and row.name then
      table.insert(config.tickers, {
        symbol = tostring(row.symbol):upper(),
        name = tostring(row.name),
        orgId = row.orgId and tostring(row.orgId) or nil,
        sector = tostring(row.sector or "global"),
        basePrice = math.max(1, tonumber(row.basePrice) or 25),
        beta = math.max(0.2, tonumber(row.beta) or 1),
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
  -- Slow random walk clipped to ±6%
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

local function payMoney(amount, reason, accountId)
  amount = r2(amount)
  if amount <= 0 then return true end
  local payment = overhaul_career_economy_payment
  if not payment or not payment.pay then return false end
  return payment.pay({ money = { amount = amount } }, reason, accountId) == true
end

local function rewardMoney(amount, reason)
  amount = r2(amount)
  if amount <= 0 then return true end
  local payment = overhaul_career_economy_payment
  if not payment or not payment.reward then return false end
  return payment.reward({ money = { amount = amount } }, reason) == true
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

local function applyBuy(list, symbol, shares, price)
  shares = tonumber(shares) or 0
  if shares <= 0 then return end
  local holding = findHolding(list, symbol)
  if holding then
    local totalShares = holding.shares + shares
    holding.avgCost = ((holding.avgCost * holding.shares) + (price * shares)) / totalShares
    holding.shares = totalShares
  else
    table.insert(list, { ticker = symbol, shares = shares, avgCost = price })
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
      holdings = {},
      lastActionAt = 0,
      depositTotal = 0,
    },
    transactions = {},
    brokerLog = {},
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
        })
      end
    end
  end
  if type(data.broker) == "table" then
    state.broker.cash = tonumber(data.broker.cash) or 0
    state.broker.enabled = data.broker.enabled == true
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
    })
  end
  table.sort(rows, function(a, b) return a.symbol < b.symbol end)
  return rows
end

local function enrichHoldings(list)
  local rows = {}
  for _, h in ipairs(list or {}) do
    local price = quotePrice(h.ticker) or h.avgCost
    local value = r2(price * h.shares)
    local cost = r2(h.avgCost * h.shares)
    table.insert(rows, {
      ticker = h.ticker,
      shares = h.shares,
      avgCost = r2(h.avgCost),
      price = price,
      value = value,
      cost = cost,
      unrealized = r2(value - cost),
      unrealizedPct = cost > 0 and ((value - cost) / cost) * 100 or 0,
      name = (tickerBySymbol(h.ticker) or {}).name or h.ticker,
    })
  end
  return rows
end

function M.getOverview()
  loadConfig()
  if not next(state.quotes) then refreshQuotes() end
  local portfolio = enrichHoldings(state.portfolio)
  local brokerHoldings = enrichHoldings(state.broker.holdings)
  local portfolioValue = 0
  for _, h in ipairs(portfolio) do portfolioValue = portfolioValue + h.value end
  local brokerHoldingsValue = 0
  for _, h in ipairs(brokerHoldings) do brokerHoldingsValue = brokerHoldingsValue + h.value end
  return {
    markets = marketRows(),
    portfolio = portfolio,
    portfolioValue = r2(portfolioValue),
    broker = {
      cash = r2(state.broker.cash),
      enabled = state.broker.enabled == true,
      holdings = brokerHoldings,
      holdingsValue = r2(brokerHoldingsValue),
      depositTotal = r2(state.broker.depositTotal),
      feeRate = loadConfig().brokerFeeRate,
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
    table.insert(rows, { symbol = ticker.symbol, name = ticker.name, sector = ticker.sector })
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
  applyBuy(state.portfolio, symbol, shares, price)
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

function M.withdrawBroker(amount)
  amount = r2(amount)
  if amount < 1 then return { ok = false, reason = "invalid_amount" } end
  if amount > state.broker.cash + 0.0001 then
    return { ok = false, reason = "insufficient_cash" }
  end
  state.broker.cash = r2(state.broker.cash - amount)
  rewardMoney(amount, saleReason("Broker withdraw", "Returned managed cash"))
  recordBrokerLog("Withdrew $" .. tostring(amount))
  recordTx({ side = "withdraw", source = "broker", total = amount })
  return { ok = true, overview = M.getOverview() }
end

function M.setBrokerEnabled(enabled)
  state.broker.enabled = enabled == true
  recordBrokerLog(state.broker.enabled and "Managed trading enabled" or "Managed trading paused")
  return { ok = true, overview = M.getOverview() }
end

local function brokerBuy(symbol, spendCash)
  local price = quotePrice(symbol)
  if not price or price <= 0 then return end
  local feeRate = loadConfig().brokerFeeRate
  -- spendCash covers notional + fee
  local shares = math.floor(spendCash / (price * (1 + feeRate)))
  if shares < 1 then return end
  local notional = r2(price * shares)
  local fee = r2(notional * feeRate)
  local cost = r2(notional + fee)
  if cost > state.broker.cash + 0.0001 then return end
  state.broker.cash = r2(state.broker.cash - cost)
  applyBuy(state.broker.holdings, symbol, shares, price)
  recordBrokerLog("Bought " .. shares .. " " .. symbol, { ticker = symbol, shares = shares, fee = fee })
  recordTx({ side = "buy", source = "broker", ticker = symbol, shares = shares, price = price, fee = fee, total = cost })
end

local function brokerSell(symbol, shares)
  local price = quotePrice(symbol)
  if not price then return end
  local sold = applySell(state.broker.holdings, symbol, shares)
  if sold <= 0 then return end
  local notional = r2(price * sold)
  local fee = r2(notional * loadConfig().brokerFeeRate)
  local proceeds = r2(notional - fee)
  state.broker.cash = r2(state.broker.cash + proceeds)
  recordBrokerLog("Sold " .. sold .. " " .. symbol, { ticker = symbol, shares = sold, fee = fee })
  recordTx({ side = "sell", source = "broker", ticker = symbol, shares = sold, price = price, fee = fee, total = proceeds })
end

function M.closeBroker()
  -- Liquidate holdings to broker cash, then cash to wallet.
  local symbols = {}
  for _, h in ipairs(state.broker.holdings) do
    table.insert(symbols, { ticker = h.ticker, shares = h.shares })
  end
  for _, h in ipairs(symbols) do
    brokerSell(h.ticker, h.shares)
  end
  state.broker.enabled = false
  local cash = r2(state.broker.cash)
  if cash > 0 then
    state.broker.cash = 0
    rewardMoney(cash, saleReason("Broker closed", "Liquidated managed account"))
    recordBrokerLog("Closed broker · returned $" .. tostring(cash))
    recordTx({ side = "withdraw", source = "broker", total = cash })
  else
    recordBrokerLog("Closed broker")
  end
  return { ok = true, overview = M.getOverview() }
end

function M.runBrokerTick()
  if not state.broker.enabled then return end
  if (state.broker.cash or 0) <= 0 and #(state.broker.holdings or {}) == 0 then return end
  local cfg = loadConfig()
  local ranked = {}
  for _, ticker in ipairs(cfg.tickers) do
    table.insert(ranked, {
      symbol = ticker.symbol,
      ret = shortReturn(ticker.symbol),
      sector = ticker.sector,
    })
  end
  table.sort(ranked, function(a, b) return a.ret < b.ret end)

  -- Sell: take profit / cut loss
  local toSell = {}
  for _, h in ipairs(state.broker.holdings) do
    local price = quotePrice(h.ticker) or h.avgCost
    local pnl = h.avgCost > 0 and ((price - h.avgCost) / h.avgCost) or 0
    local ret = shortReturn(h.ticker)
    if pnl >= cfg.brokerTakeProfit or pnl <= cfg.brokerCutLoss or ret < -0.05 then
      table.insert(toSell, { ticker = h.ticker, shares = h.shares })
    end
  end
  for _, s in ipairs(toSell) do
    brokerSell(s.ticker, s.shares)
  end

  -- Buy: prefer short-term laggards with recent positive sector / mild rebound candidates
  local cash = state.broker.cash or 0
  if cash < 25 then
    state.broker.lastActionAt = os.time and os.time() or 0
    return
  end
  local budgetPer = cash * cfg.maxBrokerCashPerTicker
  local buys = 0
  for _, row in ipairs(ranked) do
    if buys >= 3 then break end
    -- Buy laggards that aren't free-falling hard, or mild positive momentum
    if row.ret > -0.12 and row.ret < 0.04 then
      local holding = findHolding(state.broker.holdings, row.symbol)
      local already = holding and (quotePrice(row.symbol) or 0) * holding.shares or 0
      if already < budgetPer then
        local spend = math.min(budgetPer - already, state.broker.cash * 0.35)
        if spend >= 25 then
          brokerBuy(row.symbol, spend)
          buys = buys + 1
        end
      end
    end
  end
  state.broker.lastActionAt = os.time and os.time() or 0
end

function M.onEconomyUpdated()
  refreshQuotes()
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
