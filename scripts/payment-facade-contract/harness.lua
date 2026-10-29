-- Offline Payment Domain facade contract (#2).
-- Loads real payment.lua against stubbed bank / wallet / sponsor deps.
-- Run via: node scripts/payment-facade-contract/run.mjs

local ROOT = assert(_G.__PAYMENT_CONTRACT_ROOT, "missing __PAYMENT_CONTRACT_ROOT")
local PAYMENT_PATH = ROOT .. "/lua/ge/extensions/overhaul/career/economy/payment.lua"

local failures = 0
local passed = 0

local function fail(msg)
  failures = failures + 1
  io.stderr:write("FAIL: " .. msg .. "\n")
end

local function ok(msg)
  passed = passed + 1
  io.write("ok: " .. msg .. "\n")
end

local function expect(cond, msg)
  if cond then ok(msg) else fail(msg) end
end

local function nearly(a, b)
  return math.abs((tonumber(a) or 0) - (tonumber(b) or 0)) < 0.011
end

-- Minimal spend-bucket map mirroring bank/automation.spendBucket for purchase reasons.
local function spendBucket(reason)
  reason = type(reason) == "table" and reason or {}
  local category = reason.category
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
  if finance.kind == "stocks" or tagSet.stocks or tagSet.stockMarket then return "stocks" end
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
    return nil
  end
  return "other"
end

local function makeWorld(opts)
  opts = opts or {}
  local wallet = { money = tonumber(opts.wallet) or 0 }
  local accounts = {}
  local payClaims = {}
  local autoPay = {}
  local persistedKeys = { money = true } -- only wallet money is a stored player attribute here

  if opts.checking then
    accounts.chk1 = {
      id = "chk1",
      type = "personal",
      accountType = "checking",
      balance = tonumber(opts.checking) or 0,
    }
  end
  if opts.claimBucket and accounts.chk1 then
    payClaims[opts.claimBucket] = "chk1"
    autoPay[opts.claimBucket] = true
  end

  local function walletBalance()
    return tonumber(wallet.money) or 0
  end

  local function resolvePayAccountId(reason)
    local bucket = spendBucket(reason)
    if not bucket then return nil, nil end
    local accountId = payClaims[bucket]
    if not accountId then return nil, bucket end
    if not autoPay[bucket] then return nil, bucket end
    local account = accounts[accountId]
    if not account or account.accountType ~= "checking" then return nil, bucket end
    return accountId, bucket
  end

  local bank = {}

  function bank.getAccountBalance(accountId)
    local a = accounts[accountId]
    return a and (tonumber(a.balance) or 0) or 0
  end

  function bank.resolvePayAccount(reason, amount)
    amount = tonumber(amount) or 0
    local accountId = resolvePayAccountId(reason)
    if not accountId then return nil end
    local account = accounts[accountId]
    if amount > 0 and (account.balance or 0) + 0.0001 < amount then
      return nil
    end
    return accountId
  end

  function bank.getAutoPayBalance(reason)
    local accountId = resolvePayAccountId(reason)
    if not accountId then return 0 end
    return math.max(0, tonumber(accounts[accountId].balance) or 0)
  end

  function bank.getSpendableMoney(reason)
    return walletBalance() + bank.getAutoPayBalance(reason)
  end

  function bank.payFromAccount(price, accountId, label, description, meta)
    local account = accounts[accountId]
    if not account then return false end
    local amount = tonumber(price and price.money and price.money.amount) or 0
    if amount <= 0 then return true end
    if (account.balance or 0) + 0.0001 < amount then return false end
    account.balance = (account.balance or 0) - amount
    return true
  end

  function bank.rewardToAccount(price, accountId)
    local account = accounts[accountId]
    if not account then return false end
    local amount = tonumber(price and price.money and price.money.amount) or 0
    account.balance = (account.balance or 0) + amount
    return true
  end

  function bank.maybeAutoDeposit()
    -- no-op for facade contract
  end

  local playerAttributes = {}
  function playerAttributes.getAttributeValue(currency)
    currency = currency or "money"
    return tonumber(wallet[currency]) or 0
  end

  function playerAttributes.addAttributes(change)
    for currency, delta in pairs(change or {}) do
      wallet[currency] = (tonumber(wallet[currency]) or 0) + (tonumber(delta) or 0)
      persistedKeys[currency] = true
    end
    -- Intentionally never create a persisted "spendable" attribute.
  end

  function playerAttributes._wallet()
    return walletBalance()
  end

  function playerAttributes._persistedKeys()
    return persistedKeys
  end

  function playerAttributes._failNextWalletDebit(flag)
    playerAttributes.__failWallet = flag and true or false
  end

  -- Wrap addAttributes so tests can force a wallet debit failure after checking already moved.
  local realAdd = playerAttributes.addAttributes
  function playerAttributes.addAttributes(change, reason, fullReward, onRecorded)
    local moneyDelta = change and change.money
    if playerAttributes.__failWallet and moneyDelta and moneyDelta < 0 then
      return false
    end
    realAdd(change)
    if onRecorded then onRecorded({ attributeChange = change }) end
    return true
  end

  return {
    bank = bank,
    playerAttributes = playerAttributes,
    accounts = accounts,
    payClaims = payClaims,
    wallet = wallet,
  }
end

-- Stub payment.lua requires before loadfile.
package.preload["overhaul/lib/ledger/sponsors"] = function()
  return {
    tryCover = function() return false end,
    registerService = function() return true, function() end end,
  }
end

package.preload["overhaul/career/economy/payment/wageHolders"] = function()
  return {
    register = function() end,
    hold = function() return false, "unused" end,
  }
end

package.preload["overhaul/lib/platform/manifests"] = function()
  return {
    isNonEmptyString = function(s) return type(s) == "string" and s ~= "" end,
    scan = function() return {} end,
  }
end

package.preload["overhaul/lib/lifecycle/host"] = function()
  return {
    epochs = function() return { career = 1, map = 1, profile = 1 } end,
  }
end

local function loadPayment()
  local chunk, err = loadfile(PAYMENT_PATH)
  if not chunk then error("load payment.lua: " .. tostring(err)) end
  return chunk()
end

local payment = loadPayment()

local vehicleReason = { category = "purchase", tags = { "vehicleBought", "buying" } }
local shopsReason = { category = "purchase", tags = { "part" } }
-- Mirrors stockMarket stocksReason / metadata.tag(..., "purchase", { kind = "stocks" }).
local stocksReason = { category = "purchase", finance = { kind = "stocks" }, label = "Bought TEST" }

local function installWorld(world)
  _G.overhaul_career_economy_bank = world.bank
  _G.overhaul_career_economy_playerAttributes = world.playerAttributes
  _G.overhaul_career_economy_cheats = { isCheatsMode = function() return false end }
  -- silence BeamNG log if referenced
  _G.log = _G.log or function() end
end

---------------------------------------------------------------------------
-- Contract cases
---------------------------------------------------------------------------

do
  local world = makeWorld({ wallet = 200, checking = 800, claimBucket = "vehicles" })
  installWorld(world)
  local spendable = payment.getSpendableMoney(vehicleReason)
  expect(nearly(spendable, 1000), "Spendable = Wallet + claimed checking (derived)")
  expect(world.playerAttributes._persistedKeys().spendable == nil, "Spendable is not a persisted attribute key")
  expect(nearly(world.playerAttributes._wallet(), 200), "Wallet stored separately from Spendable")
  expect(nearly(world.bank.getAccountBalance("chk1"), 800), "Account balance stored separately")
end

do
  local world = makeWorld({ wallet = 50, checking = 500, claimBucket = "vehicles" })
  installWorld(world)
  local price = { money = { amount = 400 } }
  expect(payment.canPay(price, nil, vehicleReason) == true, "Auto-pay on: enough checking alone → canPay true")
  expect(payment.pay(price, vehicleReason) == true, "Auto-pay on: pay succeeds from checking")
  expect(nearly(world.bank.getAccountBalance("chk1"), 100), "pay debits checking first (full cover)")
  expect(nearly(world.playerAttributes._wallet(), 50), "Wallet untouched when checking covers full amount")
end

do
  local world = makeWorld({ wallet = 200, checking = 150, claimBucket = "vehicles" })
  installWorld(world)
  local price = { money = { amount = 300 } }
  expect(payment.canPay(price, nil, vehicleReason) == true, "Auto-pay on: partial checking → canPay true")
  expect(payment.pay(price, vehicleReason) == true, "Auto-pay on: split pay succeeds")
  expect(nearly(world.bank.getAccountBalance("chk1"), 0), "split: checking drained first")
  expect(nearly(world.playerAttributes._wallet(), 50), "split: Wallet covers remainder (200-150)")
end

do
  local world = makeWorld({ wallet = 400, checking = 900, claimBucket = nil })
  -- claimBucket nil = auto-pay off (no payClaims)
  installWorld(world)
  expect(nearly(payment.getSpendableMoney(vehicleReason), 400), "Auto-pay off: Spendable equals Wallet")
  local price = { money = { amount = 100 } }
  expect(payment.canPay(price, nil, vehicleReason) == true, "Auto-pay off: canPay from Wallet")
  expect(payment.pay(price, vehicleReason) == true, "Auto-pay off: pay from Wallet")
  expect(nearly(world.bank.getAccountBalance("chk1"), 900), "Auto-pay off: checking untouched")
  expect(nearly(world.playerAttributes._wallet(), 300), "Auto-pay off: Wallet debited")
end

do
  -- Vehicles claim only; shops reason must not use vehicles checking.
  local world = makeWorld({ wallet = 40, checking = 5000, claimBucket = "vehicles" })
  installWorld(world)
  expect(nearly(payment.getSpendableMoney(shopsReason), 40), "Wrong bucket: shops Spendable ignores vehicles claim")
  expect(payment.canPay({ money = { amount = 100 } }, nil, shopsReason) == false,
    "Wrong bucket: shops cannotPay using vehicles checking")
  expect(payment.canPay({ money = { amount = 100 } }, nil, vehicleReason) == true,
    "Wrong bucket: vehicles reason still uses vehicles claim")
end

do
  local world = makeWorld({ wallet = 100, checking = 250, claimBucket = "vehicles" })
  installWorld(world)
  local spendable = payment.getSpendableMoney(vehicleReason)
  expect(nearly(spendable, 350), "Spendable equals Wallet + claimed checking")
  expect(spendable <= 100 + 250 + 0.001, "Spendable never exceeds Wallet + claimed checking")
  -- Unclaimed second account must not inflate Spendable
  world.accounts.chk2 = { id = "chk2", type = "personal", accountType = "checking", balance = 9999 }
  expect(nearly(payment.getSpendableMoney(vehicleReason), 350),
    "Spendable ignores unclaimed checking balances")
end

do
  local world = makeWorld({ wallet = 20, checking = 100, claimBucket = "vehicles" })
  installWorld(world)
  local price = { money = { amount = 80 } }
  expect(payment.canPay(price, nil, vehicleReason) == true, "Reject path setup: canPay true before forced wallet failure")
  world.playerAttributes._failNextWalletDebit(true)
  -- Force a split: checking 100 covers none of remainder need... amount 80, checking 100 covers full.
  -- Use amount that requires split:
  local splitPrice = { money = { amount = 110 } }
  expect(payment.canPay(splitPrice, nil, vehicleReason) == true, "Reject path: canPay for split amount")
  local beforeChk = world.bank.getAccountBalance("chk1")
  local beforeWallet = world.playerAttributes._wallet()
  local accepted = payment.pay(splitPrice, vehicleReason)
  expect(accepted == false, "Failed pay returns false when Wallet leg cannot complete")
  expect(nearly(world.bank.getAccountBalance("chk1"), beforeChk),
    "Failed/rejected pay does not leave partial checking debit")
  expect(nearly(world.playerAttributes._wallet(), beforeWallet),
    "Failed/rejected pay leaves Wallet unchanged")
end

do
  local world = makeWorld({ wallet = 10, checking = 0, claimBucket = "vehicles" })
  installWorld(world)
  expect(payment.canPay({ money = { amount = 50 } }, nil, vehicleReason) == false,
    "Insufficient funds: canPay false")
  expect(payment.pay({ money = { amount = 50 } }, vehicleReason) == false,
    "Insufficient funds: pay rejected without mutation")
  expect(nearly(world.playerAttributes._wallet(), 10), "Rejected pay: Wallet unchanged")
end

do
  local world = makeWorld({ wallet = 0, checking = 0 })
  installWorld(world)
  expect(payment.reward({ money = { amount = 75 } }, { category = "reward", label = "test" }) == true,
    "Reward path credits Wallet")
  expect(nearly(world.playerAttributes._wallet(), 75), "Reward lands in Wallet")
  expect(world.playerAttributes._persistedKeys().spendable == nil,
    "Reward does not persist Spendable")
end

---------------------------------------------------------------------------
-- #8 Stocks spend bucket / auto-pay via payment facade
---------------------------------------------------------------------------

do
  local world = makeWorld({ wallet = 40, checking = 600, claimBucket = "stocks" })
  installWorld(world)
  expect(nearly(payment.getSpendableMoney(stocksReason), 640),
    "Stocks auto-pay on: Spendable = Wallet + stocks checking")
  expect(payment.canPay({ money = { amount = 500 } }, nil, stocksReason) == true,
    "Stocks auto-pay on: canPay with stocks-mapped reason")
  expect(payment.pay({ money = { amount = 500 } }, stocksReason) == true,
    "Stocks auto-pay on: pay with stocks-mapped reason")
  expect(nearly(world.bank.getAccountBalance("chk1"), 100),
    "Stocks auto-pay on: checking then Wallet (full checking cover)")
  expect(nearly(world.playerAttributes._wallet(), 40),
    "Stocks auto-pay on: Wallet untouched when checking covers")
end

do
  local world = makeWorld({ wallet = 120, checking = 80, claimBucket = "stocks" })
  installWorld(world)
  local price = { money = { amount = 150 } }
  expect(payment.canPay(price, nil, stocksReason) == true,
    "Stocks auto-pay on: split canPay (checking + Wallet)")
  expect(payment.pay(price, stocksReason) == true,
    "Stocks auto-pay on: split pay succeeds")
  expect(nearly(world.bank.getAccountBalance("chk1"), 0),
    "Stocks split: checking drained first")
  expect(nearly(world.playerAttributes._wallet(), 50),
    "Stocks split: Wallet covers remainder (120-80)")
end

do
  local world = makeWorld({ wallet = 300, checking = 900, claimBucket = nil })
  installWorld(world)
  expect(nearly(payment.getSpendableMoney(stocksReason), 300),
    "Stocks auto-pay off: Spendable equals Wallet")
  expect(payment.canPay({ money = { amount = 100 } }, nil, stocksReason) == true,
    "Stocks auto-pay off: canPay from Wallet")
  expect(payment.pay({ money = { amount = 100 } }, stocksReason) == true,
    "Stocks auto-pay off: pay from Wallet")
  expect(nearly(world.bank.getAccountBalance("chk1"), 900),
    "Stocks auto-pay off: checking untouched")
  expect(nearly(world.playerAttributes._wallet(), 200),
    "Stocks auto-pay off: Wallet debited")
end

do
  -- Vehicles claim must not fund stock buys (and vice versa).
  local world = makeWorld({ wallet = 30, checking = 5000, claimBucket = "vehicles" })
  installWorld(world)
  expect(nearly(payment.getSpendableMoney(stocksReason), 30),
    "Stocks wrong bucket: Spendable ignores vehicles claim")
  expect(payment.canPay({ money = { amount = 100 } }, nil, stocksReason) == false,
    "Stocks wrong bucket: cannotPay using vehicles checking")
  expect(payment.pay({ money = { amount = 100 } }, stocksReason) == false,
    "Stocks wrong bucket: pay rejected without debit")
  expect(nearly(world.bank.getAccountBalance("chk1"), 5000),
    "Stocks wrong bucket: checking untouched after reject")
  expect(nearly(world.playerAttributes._wallet(), 30),
    "Stocks wrong bucket: Wallet untouched after reject")
end

do
  -- Plain purchase without finance.kind=stocks must not steal the stocks claim.
  local world = makeWorld({ wallet = 25, checking = 4000, claimBucket = "stocks" })
  installWorld(world)
  expect(nearly(payment.getSpendableMoney(shopsReason), 25),
    "Shops reason ignores stocks auto-pay claim")
  expect(payment.canPay({ money = { amount = 100 } }, nil, shopsReason) == false,
    "Shops cannotPay via stocks checking")
  expect(payment.canPay({ money = { amount = 100 } }, nil, stocksReason) == true,
    "Stocks reason still uses stocks claim")
end

io.write(string.format("\n%d passed, %d failed\n", passed, failures))
if failures > 0 then
  os.exit(1)
end
os.exit(0)
