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
    -- Vehicle purchases only: vehicleBought / vehicle tags. Generic "buying" and
    -- finance.vehicleId are used by parts/paint/tune ledger reasons and must map to shops.
    if tagSet.vehicleBought or tagSet.vehicle then
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
-- #3 Vehicle dealership — same facade reason list / checkout / pay must agree
---------------------------------------------------------------------------

-- Dealership listing affordability reason (matches vehicleShopping/ui.lua vehicleSpendReason).
local dealershipListReason = {
  category = "purchase",
  tags = { "vehicleBought", "buying" },
  label = "Vehicle purchase",
}

-- Dealership checkout/pay reason (matches purchase.lua vehiclePurchaseReason finance shape).
local dealershipPayReason = {
  category = "purchase",
  finance = { vehicleName = "Test Coupe", locationId = "dealer_a", locationName = "Test Motors" },
  tags = { "vehicleBought", "buying" },
  label = "Bought a vehicle: Test Coupe",
}

do
  -- AC: auto-pay on + low Wallet + enough checking → Spendable covers listing price
  local world = makeWorld({ wallet = 50, checking = 9500, claimBucket = "vehicles" })
  installWorld(world)
  local price = 4000
  local spendable = payment.getSpendableMoney(dealershipListReason)
  expect(nearly(spendable, 9550), "#3 list: Spendable = low Wallet + vehicles checking")
  expect(payment.canPay({ money = { amount = price } }, nil, dealershipListReason) == true,
    "#3 list: canPay true when Spendable covers vehicle")
  expect(nearly(world.playerAttributes._wallet(), 50),
    "#3 list: Wallet (deposit capacity) stays 50, not Spendable")
  expect(world.playerAttributes._wallet() < spendable,
    "#3 list: Wallet display must not equal inflated Spendable")
end

do
  -- AC: same setup → checkout canPay + pay: checking then Wallet
  local world = makeWorld({ wallet = 50, checking = 9500, claimBucket = "vehicles" })
  installWorld(world)
  local price = { money = { amount = 4000 } }
  expect(payment.canPay(price, nil, dealershipPayReason) == true,
    "#3 checkout: canPay agrees with list Spendable for pay reason")
  expect(payment.pay(price, dealershipPayReason) == true, "#3 purchase: pay succeeds")
  expect(nearly(world.bank.getAccountBalance("chk1"), 5500),
    "#3 purchase: checking debited first (9500-4000)")
  expect(nearly(world.playerAttributes._wallet(), 50),
    "#3 purchase: Wallet untouched when checking covers full price")
end

do
  -- AC: split debit when checking alone is short
  local world = makeWorld({ wallet = 800, checking = 1200, claimBucket = "vehicles" })
  installWorld(world)
  local price = { money = { amount = 1500 } }
  expect(nearly(payment.getSpendableMoney(dealershipListReason), 2000),
    "#3 split: list Spendable covers package")
  expect(payment.canPay(price, nil, dealershipPayReason) == true, "#3 split: checkout canPay")
  expect(payment.pay(price, dealershipPayReason) == true, "#3 split: pay succeeds")
  expect(nearly(world.bank.getAccountBalance("chk1"), 0), "#3 split: checking drained first")
  expect(nearly(world.playerAttributes._wallet(), 500), "#3 split: Wallet covers remainder")
end

do
  -- AC: insufficient Spendable → UI and purchase both refuse
  local world = makeWorld({ wallet = 40, checking = 100, claimBucket = "vehicles" })
  installWorld(world)
  local price = { money = { amount = 500 } }
  expect(nearly(payment.getSpendableMoney(dealershipListReason), 140),
    "#3 refuse: Spendable below vehicle price")
  expect(payment.canPay(price, nil, dealershipListReason) == false,
    "#3 refuse: list/UI canPay false")
  expect(payment.canPay(price, nil, dealershipPayReason) == false,
    "#3 refuse: checkout canPay false")
  expect(payment.pay(price, dealershipPayReason) == false, "#3 refuse: pay rejected")
  expect(nearly(world.bank.getAccountBalance("chk1"), 100), "#3 refuse: checking unchanged")
  expect(nearly(world.playerAttributes._wallet(), 40), "#3 refuse: Wallet unchanged")
end

do
  -- AC: vehicles auto-pay off → affordability and pay use Wallet only
  local world = makeWorld({ wallet = 600, checking = 8000, claimBucket = nil })
  installWorld(world)
  expect(nearly(payment.getSpendableMoney(dealershipListReason), 600),
    "#3 auto-pay off: Spendable equals Wallet")
  expect(payment.canPay({ money = { amount = 500 } }, nil, dealershipPayReason) == true,
    "#3 auto-pay off: canPay from Wallet")
  expect(payment.canPay({ money = { amount = 700 } }, nil, dealershipPayReason) == false,
    "#3 auto-pay off: cannot use checking")
  expect(payment.pay({ money = { amount = 200 } }, dealershipPayReason) == true,
    "#3 auto-pay off: pay from Wallet")
  expect(nearly(world.bank.getAccountBalance("chk1"), 8000),
    "#3 auto-pay off: checking untouched")
  expect(nearly(world.playerAttributes._wallet(), 400),
    "#3 auto-pay off: Wallet debited")
end

---------------------------------------------------------------------------
-- #4 Parts/shops Spendable — shop reasons must use shops bucket, not vehicles
---------------------------------------------------------------------------

local partsShopReason = {
  category = "purchase",
  finance = { vehicleId = "inv-1" },
  tags = { "partsBought", "buying" },
  label = "Bought parts",
}
local paintingShopReason = {
  category = "purchase",
  finance = { vehicleId = "inv-1" },
  tags = { "vehiclePainting", "buying" },
  label = "Repainted vehicle",
}
local tuningShopReason = {
  category = "purchase",
  finance = { vehicleId = "inv-1" },
  tags = { "tuning", "buying" },
  label = "Tuned vehicle",
}

do
  -- Vehicles claim must not cover non-vehicle shop goods (parts/paint/tune).
  local world = makeWorld({ wallet = 30, checking = 5000, claimBucket = "vehicles" })
  installWorld(world)
  expect(nearly(payment.getSpendableMoney(partsShopReason), 30),
    "#4 shops≠vehicles: parts Spendable ignores vehicles claim")
  expect(payment.canPay({ money = { amount = 100 } }, nil, partsShopReason) == false,
    "#4 shops≠vehicles: parts cannotPay via vehicles checking")
  expect(nearly(payment.getSpendableMoney(paintingShopReason), 30),
    "#4 shops≠vehicles: painting Spendable ignores vehicles claim")
  expect(nearly(payment.getSpendableMoney(tuningShopReason), 30),
    "#4 shops≠vehicles: tuning Spendable ignores vehicles claim")
  expect(payment.canPay({ money = { amount = 100 } }, nil, vehicleReason) == true,
    "#4 shops≠vehicles: vehicleBought reason still uses vehicles claim")
end

do
  local world = makeWorld({ wallet = 40, checking = 600, claimBucket = "shops" })
  installWorld(world)
  expect(nearly(payment.getSpendableMoney(partsShopReason), 640),
    "#4 shops auto-pay on: Spendable = Wallet + shops checking")
  expect(payment.canPay({ money = { amount = 500 } }, nil, partsShopReason) == true,
    "#4 shops auto-pay on: canPay when checking covers")
  expect(payment.pay({ money = { amount = 500 } }, partsShopReason) == true,
    "#4 shops auto-pay on: pay succeeds from checking")
  expect(nearly(world.bank.getAccountBalance("chk1"), 100),
    "#4 shops auto-pay on: checking debited first (full cover)")
  expect(nearly(world.playerAttributes._wallet(), 40),
    "#4 shops auto-pay on: Wallet untouched when checking covers")
end

do
  local world = makeWorld({ wallet = 120, checking = 80, claimBucket = "shops" })
  installWorld(world)
  local price = { money = { amount = 150 } }
  expect(payment.canPay(price, nil, paintingShopReason) == true,
    "#4 shops split: canPay with partial checking")
  expect(payment.pay(price, paintingShopReason) == true,
    "#4 shops split: pay succeeds checking then Wallet")
  expect(nearly(world.bank.getAccountBalance("chk1"), 0),
    "#4 shops split: checking drained first")
  expect(nearly(world.playerAttributes._wallet(), 50),
    "#4 shops split: Wallet covers remainder (120-80)")
end

do
  local world = makeWorld({ wallet = 250, checking = 900, claimBucket = nil })
  installWorld(world)
  expect(nearly(payment.getSpendableMoney(tuningShopReason), 250),
    "#4 shops auto-pay off: Spendable equals Wallet")
  expect(payment.canPay({ money = { amount = 100 } }, nil, tuningShopReason) == true,
    "#4 shops auto-pay off: canPay from Wallet")
  expect(payment.pay({ money = { amount = 100 } }, tuningShopReason) == true,
    "#4 shops auto-pay off: pay from Wallet")
  expect(nearly(world.bank.getAccountBalance("chk1"), 900),
    "#4 shops auto-pay off: checking untouched")
  expect(nearly(world.playerAttributes._wallet(), 150),
    "#4 shops auto-pay off: Wallet debited")
end


-- #5 Phone Marketplace buy-tab — affordability reason matches vehicle pay
---------------------------------------------------------------------------

-- Same reason Phone Marketplace / vehicle shopping list gates must pass to
-- getSpendableMoney / canPay (vehicleShopping/ui.lua vehicleSpendReason).
local marketplaceBuyReason = {
  category = "purchase",
  tags = { "vehicleBought", "buying" },
  label = "Vehicle purchase",
}

do
  -- AC: buy-tab gates use Spendable when vehicles auto-pay is on
  local world = makeWorld({ wallet = 80, checking = 4200, claimBucket = "vehicles" })
  installWorld(world)
  local listingPrice = 2500
  local spendable = payment.getSpendableMoney(marketplaceBuyReason)
  expect(nearly(spendable, 4280), "#5 auto-pay on: Spendable = Wallet + vehicles checking")
  expect(payment.canPay({ money = { amount = listingPrice } }, nil, marketplaceBuyReason) == true,
    "#5 auto-pay on: canPay true when Spendable covers listing")
  expect(nearly(world.playerAttributes._wallet(), 80),
    "#5 auto-pay on: Wallet (cash-on-hand / deposit) stays 80, not Spendable")
  expect(world.playerAttributes._wallet() < spendable,
    "#5 auto-pay on: Wallet display must not equal inflated Spendable")
end

do
  -- AC: auto-pay off → buy-tab Spendable / canPay use Wallet only
  local world = makeWorld({ wallet = 900, checking = 7000, claimBucket = nil })
  installWorld(world)
  expect(nearly(payment.getSpendableMoney(marketplaceBuyReason), 900),
    "#5 auto-pay off: Spendable equals Wallet")
  expect(payment.canPay({ money = { amount = 500 } }, nil, marketplaceBuyReason) == true,
    "#5 auto-pay off: canPay from Wallet")
  expect(payment.canPay({ money = { amount = 1200 } }, nil, marketplaceBuyReason) == false,
    "#5 auto-pay off: cannot use checking for marketplace buy")
  expect(nearly(world.playerAttributes._wallet(), 900),
    "#5 auto-pay off: Wallet unchanged by affordability check")
  expect(nearly(world.bank.getAccountBalance("chk1"), 7000),
    "#5 auto-pay off: checking untouched by affordability check")
end

do
  -- AC: marketplace vehicle buy must not read shops-only Spendable / Wallet while vehicles auto-pay covers
  local world = makeWorld({ wallet = 60, checking = 3000, claimBucket = "vehicles" })
  installWorld(world)
  local listingPrice = 1000
  expect(nearly(payment.getSpendableMoney(shopsReason), 60),
    "#5 no wallet-only path: shops Spendable ignores vehicles claim")
  expect(payment.canPay({ money = { amount = listingPrice } }, nil, shopsReason) == false,
    "#5 no wallet-only path: shops canPay false (would grey listing wrongly)")
  expect(nearly(payment.getSpendableMoney(marketplaceBuyReason), 3060),
    "#5 no wallet-only path: marketplace vehicle reason uses vehicles Spendable")
  expect(payment.canPay({ money = { amount = listingPrice } }, nil, marketplaceBuyReason) == true,
    "#5 no wallet-only path: marketplace buy canPay true under vehicles auto-pay")
end



-- #6 maintenance / garage / travel reasons (must match production pay tags)
local repairReason = { category = "repair", tags = { "maintenance", "buying" } }
local propertyReason = { category = "property", finance = { vehicleRelated = false } }
local serviceReason = { category = "service", tags = { "quickTravel", "buying" } }

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
-- #6 Maintenance / garage / travel bucket alignment at the payment facade
---------------------------------------------------------------------------

do
  local world = makeWorld({ wallet = 30, checking = 400, claimBucket = "repairs" })
  installWorld(world)
  expect(nearly(payment.getSpendableMoney(repairReason), 430),
    "#6 repairs auto-pay on: Spendable = Wallet + repairs checking")
  expect(payment.canPay({ money = { amount = 350 } }, nil, repairReason) == true,
    "#6 repairs auto-pay on: canPay with checking cover")
  expect(payment.canPay({ money = { amount = 350 } }, nil, propertyReason) == false,
    "#6 repairs claim does not cover property reason")
  expect(nearly(payment.getSpendableMoney(propertyReason), 30),
    "#6 property Spendable ignores repairs claim (Wallet only)")
end

do
  local world = makeWorld({ wallet = 30, checking = 400, claimBucket = "repairs" })
  installWorld(world)
  expect(payment.pay({ money = { amount = 200 } }, repairReason) == true,
    "#6 repairs auto-pay on: pay succeeds")
  expect(nearly(world.bank.getAccountBalance("chk1"), 200), "#6 repairs pay debits checking")
  expect(nearly(world.playerAttributes._wallet(), 30), "#6 repairs pay leaves Wallet when checking covers")
end

do
  local world = makeWorld({ wallet = 50, checking = 500, claimBucket = nil })
  installWorld(world)
  expect(nearly(payment.getSpendableMoney(repairReason), 50),
    "#6 repairs auto-pay off: Spendable equals Wallet")
  expect(payment.canPay({ money = { amount = 100 } }, nil, repairReason) == false,
    "#6 repairs auto-pay off: cannotPay beyond Wallet")
  expect(payment.canPay({ money = { amount = 40 } }, nil, repairReason) == true,
    "#6 repairs auto-pay off: canPay from Wallet")
end

do
  local world = makeWorld({ wallet = 25, checking = 900, claimBucket = "property" })
  installWorld(world)
  expect(nearly(payment.getSpendableMoney(propertyReason), 925),
    "#6 property auto-pay on: garage Spendable includes property checking")
  expect(payment.canPay({ money = { amount = 800 } }, nil, propertyReason) == true,
    "#6 property auto-pay on: garage canPay")
  expect(nearly(payment.getSpendableMoney(shopsReason), 25),
    "#6 garage must not invent shops Spendable from property claim")
  expect(payment.canPay({ money = { amount = 800 } }, nil, shopsReason) == false,
    "#6 property claim does not cover shops/purchase-without-property reason")
end

do
  local world = makeWorld({ wallet = 25, checking = 900, claimBucket = nil })
  installWorld(world)
  expect(nearly(payment.getSpendableMoney(propertyReason), 25),
    "#6 property auto-pay off: Spendable equals Wallet")
  expect(payment.canPay({ money = { amount = 100 } }, nil, propertyReason) == false,
    "#6 property auto-pay off: cannotPay beyond Wallet")
end

do
  local world = makeWorld({ wallet = 10, checking = 200, claimBucket = "services" })
  installWorld(world)
  expect(nearly(payment.getSpendableMoney(serviceReason), 210),
    "#6 services auto-pay on: travel Spendable includes services checking")
  expect(payment.canPay({ money = { amount = 150 } }, nil, serviceReason) == true,
    "#6 services auto-pay on: travel canPay")
  expect(payment.pay({ money = { amount = 150 } }, serviceReason) == true,
    "#6 services auto-pay on: travel pay")
  expect(nearly(world.bank.getAccountBalance("chk1"), 50), "#6 services pay debits checking")
end

do
  -- Cash-only gate: no reason / Wallet attribute — must not invent Spendable from checking
  local world = makeWorld({ wallet = 40, checking = 2000, claimBucket = "property" })
  installWorld(world)
  local walletOnly = world.playerAttributes.getAttributeValue("money")
  expect(nearly(walletOnly, 40), "#6 cash-only Wallet read is Wallet, not Spendable")
  expect(walletOnly + 0.001 < payment.getSpendableMoney(propertyReason),
    "#6 cash-only Wallet is strictly less than property Spendable when claim is large")
end



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



-- #9 Wallet-truth: deposit capacity / Account displays / Wallet ledger
---------------------------------------------------------------------------

local transferReason = { category = "transfer", label = "Bank deposit" }

do
  -- Deposit-facing cash must stay Wallet even when vehicles auto-pay checking is large.
  local world = makeWorld({ wallet = 120, checking = 880, claimBucket = "vehicles" })
  installWorld(world)
  expect(type(payment.getWalletMoney) == "function",
    "#9 facade exposes getWalletMoney for deposit/cash-on-hand")
  local wallet = payment.getWalletMoney and payment.getWalletMoney() or nil
  local spendable = payment.getSpendableMoney(vehicleReason)
  expect(nearly(wallet, 120), "#9 deposit capacity / Wallet display uses Wallet only")
  expect(nearly(spendable, 1000), "#9 Spendable still reflects vehicles auto-pay")
  expect(nearly(wallet, spendable) == false,
    "#9 auto-pay on must not inflate deposit/Wallet display via Spendable")
  expect(nearly(world.bank.getAccountBalance("chk1"), 880),
    "#9 Account balance stays real ledger (not Spendable)")
end

do
  -- Bank deposit reason is transfer: never debit auto-pay checking, even for "other".
  local world = makeWorld({ wallet = 40, checking = 900, claimBucket = "other" })
  installWorld(world)
  local price = { money = { amount = 100 } }
  expect(payment.canPay(price, nil, transferReason) == false,
    "#9 deposit canPay is Wallet-only (checking cannot top up transfer)")
  expect(nearly(payment.getSpendableMoney(vehicleReason), 40),
    "#9 vehicles Spendable ignores other-bucket claim")
  expect(payment.pay(price, transferReason) == false,
    "#9 deposit pay rejects when Wallet alone is short")
  expect(nearly(world.bank.getAccountBalance("chk1"), 900),
    "#9 rejected deposit leaves Account untouched")
  expect(nearly(world.playerAttributes._wallet(), 40),
    "#9 rejected deposit leaves Wallet untouched")
end

do
  -- Successful deposit-shaped transfer: Wallet ledger truth, Account claim untouched.
  local world = makeWorld({ wallet = 200, checking = 700, claimBucket = "vehicles" })
  installWorld(world)
  local recorded
  local price = { money = { amount = 75 } }
  expect(payment.canPay(price, nil, transferReason) == true,
    "#9 deposit canPay true from Wallet alone")
  expect(payment.pay(price, transferReason, nil, function(info)
    recorded = info
  end) == true, "#9 deposit pay debits Wallet")
  expect(nearly(world.playerAttributes._wallet(), 125),
    "#9 deposit pay reduces Wallet only")
  expect(nearly(world.bank.getAccountBalance("chk1"), 700),
    "#9 deposit pay does not consume auto-pay checking")
  expect(recorded and recorded.attributeChange and nearly(recorded.attributeChange.money, -75),
    "#9 financial history / onRecorded stays Wallet ledger truth (not Spendable)")
  expect(world.playerAttributes._persistedKeys().spendable == nil,
    "#9 deposit path never persists Spendable")
end

do
  -- Deriving Spendable must not rewrite stored Wallet or Account balances.
  local world = makeWorld({ wallet = 55, checking = 445, claimBucket = "vehicles" })
  installWorld(world)
  local beforeWallet = world.playerAttributes._wallet()
  local beforeChk = world.bank.getAccountBalance("chk1")
  local _ = payment.getSpendableMoney(vehicleReason)
  local walletNow = payment.getWalletMoney and payment.getWalletMoney() or beforeWallet
  expect(nearly(walletNow, beforeWallet), "#9 getSpendableMoney does not mutate Wallet")
  expect(nearly(world.bank.getAccountBalance("chk1"), beforeChk),
    "#9 getSpendableMoney does not mutate Account")
  expect(nearly(walletNow, beforeChk) == false or nearly(beforeWallet, beforeChk),
    "#9 Wallet display stays distinct from Account when balances differ")
end


io.write(string.format("\n%d passed, %d failed\n", passed, failures))
if failures > 0 then
  os.exit(1)
end
os.exit(0)
