<!-- RLS Career Overhaul · https://github.com/RLS-Modding/rls_career_overhaul ; additional permission: licenses/RLS-BeamNG-Permission.txt
     Copyright (C) RLS Modding
     SPDX-License-Identifier: AGPL-3.0-only -->

<template>
  <div class="sm-app" v-bng-ui-nav-scroll v-bng-on-ui-nav:tab_l="() => changeTab(-1)" v-bng-on-ui-nav:tab_r="() => changeTab(1)">
    <div v-if="!loaded" class="empty-state"><p>Loading markets…</p></div>

    <template v-else>
      <nav class="tabs" role="tablist" aria-label="Stock Market">
        <button
          v-for="id in TAB_IDS"
          :id="'sm-tab-' + id"
          :key="id"
          type="button"
          role="tab"
          :aria-selected="tab === id"
          :tabindex="tab === id ? 0 : -1"
          :class="{ active: tab === id }"
          @click="tab = id"
        >{{ TAB_LABELS[id] }}</button>
      </nav>

      <!-- Markets -->
      <section v-if="tab === 'markets'" class="tab-panel">
        <input
          v-model="search"
          v-bng-text-input
          class="search"
          type="search"
          placeholder="Search companies…"
          @keydown.stop
          @keyup.stop
          @keypress.stop
        />
        <div class="list">
          <button
            v-for="row in filteredMarkets"
            :key="row.symbol"
            type="button"
            class="row"
            @click="openTrade(row)"
          >
            <div class="row-main">
              <span class="sym">{{ row.symbol }}</span>
              <span class="name">{{ row.name }}</span>
              <span class="sector">{{ sectorLabel(row.sector) }} · ~{{ fmtYield(row.dividendYield) }} yr</span>
            </div>
            <div class="row-side">
              <span class="price">${{ fmt(row.price) }}</span>
              <span class="chg" :class="chgClass(row.changePct)">{{ fmtPct(row.changePct) }}</span>
            </div>
          </button>
          <p v-if="filteredMarkets.length === 0" class="hint">No matching tickers.</p>
        </div>
      </section>

      <!-- Portfolio -->
      <section v-else-if="tab === 'portfolio'" class="tab-panel">
        <div class="summary">
          <span>Holdings value</span>
          <strong>${{ fmt(overview.portfolioValue) }}</strong>
        </div>
        <div v-if="!overview.portfolio?.length" class="hint">No shares yet. Buy from Markets.</div>
        <div v-else class="list">
          <div v-for="h in overview.portfolio" :key="h.ticker" class="holding">
            <div class="row-main">
              <span class="sym">{{ h.ticker }}</span>
              <span class="name">{{ h.name }} · {{ h.shares }} sh · ~{{ fmtYield(h.dividendYield) }}</span>
              <span class="sector">Avg ${{ fmt(h.avgCost) }} · Now ${{ fmt(h.price) }}</span>
              <span v-if="h.pendingDividend > 0.009" class="sector">Div pending ${{ fmt(h.pendingDividend) }}</span>
              <label class="div-pref">
                Dividends
                <select
                  :value="h.dividendPref || 'reinvest'"
                  @change="setDividendPref(h.ticker, $event.target.value)"
                >
                  <option value="reinvest">Reinvest</option>
                  <option value="wallet">Wallet</option>
                  <option value="checking">Checking</option>
                </select>
              </label>
            </div>
            <div class="row-side">
              <span class="price">${{ fmt(h.value) }}</span>
              <span class="chg" :class="chgClass(h.unrealizedPct)">{{ fmtPct(h.unrealizedPct) }}</span>
              <button type="button" class="mini" @click="openSell(h)">Sell</button>
            </div>
          </div>
        </div>
        <div v-if="overview.transactions?.length" class="log">
          <h4>Recent trades</h4>
          <p v-for="tx in overview.transactions.slice(0, 8)" :key="tx.id" class="log-line">
            {{ tx.source }} {{ tx.side }} {{ tx.shares || '' }} {{ tx.ticker || '' }} · ${{ fmt(tx.total) }}
          </p>
        </div>
      </section>

      <!-- Broker -->
      <section v-else class="tab-panel">
        <p class="fee-note">
          Dump-and-forget balanced broker: buys automatically, never auto-sells.
          Dividends go to the holding pool and get reinvested. 5% fee only when selling to withdraw. Buys are free.
          Balanced strategy (more strategies later).
        </p>
        <div class="summary stack">
          <div><span>Broker cash</span><strong>${{ fmt(overview.broker?.cash) }}</strong></div>
          <div><span>Holdings</span><strong>${{ fmt(overview.broker?.holdingsValue) }}</strong></div>
          <div><span>Withdrawable</span><strong>${{ fmt(overview.broker?.withdrawableMax) }}</strong></div>
        </div>
        <label class="toggle">
          <span>Managed trading</span>
          <input type="checkbox" :checked="overview.broker?.enabled" @change="toggleBroker($event.target.checked)" />
        </label>
        <div class="actions deposit-row">
          <input v-model.number="brokerAmount" v-bng-text-input type="number" min="1" class="amt" placeholder="Deposit amount" inputmode="decimal" @keydown.stop @keyup.stop @keypress.stop />
          <button type="button" class="btn" @click="depositBroker">Deposit</button>
        </div>
        <div class="actions withdraw-row">
          <input v-model.number="withdrawAmount" v-bng-text-input type="number" min="1" class="amt" placeholder="Withdraw amount" inputmode="decimal" @keydown.stop @keyup.stop @keypress.stop />
          <button type="button" class="btn ghost" @click="withdrawBroker">Withdraw</button>
          <button type="button" class="btn ghost" @click="withdrawAll">All</button>
        </div>
        <p v-if="withdrawPreview" class="preview">
          ${{ fmt(withdrawPreview.payable) }} to wallet
          · ${{ fmt(withdrawPreview.fromCash) }} cash
          · ${{ fmt(withdrawPreview.fromSales) }} from sales
          · fee ${{ fmt(withdrawPreview.fee) }}
          <template v-if="withdrawPreview.excessToPool > 0.009">
            · ${{ fmt(withdrawPreview.excessToPool) }} stays in pool
          </template>
        </p>
        <div v-if="overview.broker?.holdings?.length" class="list">
          <div v-for="h in overview.broker.holdings" :key="'b-' + h.ticker" class="holding compact">
            <div class="row-main">
              <span class="sym">{{ h.ticker }}</span>
              <span class="name">{{ h.shares }} sh · ${{ fmt(h.value) }}</span>
            </div>
            <span class="chg" :class="chgClass(h.unrealizedPct)">{{ fmtPct(h.unrealizedPct) }}</span>
          </div>
        </div>
        <div v-if="overview.brokerLog?.length" class="log">
          <h4>Broker activity</h4>
          <p v-for="row in overview.brokerLog.slice(0, 10)" :key="row.id" class="log-line">{{ row.message }}</p>
        </div>
      </section>
    </template>

    <PhoneLayer v-if="trade" class="trade-overlay" label="Trade" @close="trade = null" @click.self="trade = null">
      <div class="trade-modal" @click.stop>
        <h3>{{ trade.mode === 'sell' ? 'Sell' : 'Buy' }} {{ trade.symbol }}</h3>
        <p class="sub">{{ trade.name }} · ${{ fmt(trade.price) }}</p>
        <label class="field">
          Shares
          <input v-model.number="tradeShares" v-bng-text-input type="number" min="1" :max="trade.maxShares || undefined" inputmode="numeric" @keydown.stop @keyup.stop @keypress.stop />
        </label>
        <p class="est">Est. {{ trade.mode === 'sell' ? 'proceeds' : 'cost' }}: ${{ fmt(tradeEstimate) }}</p>
        <div class="confirm-actions">
          <button type="button" class="btn" @click="confirmTrade">Confirm</button>
          <button type="button" class="btn ghost" @click="trade = null">Cancel</button>
        </div>
      </div>
    </PhoneLayer>
  </div>
</template>

<script setup>
import { computed, onMounted, onUnmounted, ref, watch } from 'vue'
import { vBngOnUiNav, vBngUiNavScroll } from '@/common/directives'
import { lua } from '@/bridge'
import { acquireScope } from '../../utils/luaScopes'
import { reportUiFailure } from '../../utils/safeLua'
import PhoneLayer from '../../components/phone/PhoneLayer.vue'
import { usePhoneScreen } from '../../composables/usePhoneScreen'

usePhoneScreen()

const TAB_IDS = ['markets', 'portfolio', 'broker']
const TAB_LABELS = { markets: 'Markets', portfolio: 'Portfolio', broker: 'Broker' }
const SECTORS = {
  global: 'Broad market',
  vehicleMarket: 'Vehicles',
  housingMarket: 'Housing',
  jobMarket: 'Jobs / logistics',
}

const loaded = ref(false)
const tab = ref('markets')
const search = ref('')
const overview = ref({
  markets: [],
  portfolio: [],
  portfolioValue: 0,
  broker: { cash: 0, holdings: [], enabled: false, withdrawableMax: 0 },
  transactions: [],
  brokerLog: [],
})
const trade = ref(null)
const tradeShares = ref(1)
const brokerAmount = ref(1000)
const withdrawAmount = ref(1000)
const withdrawPreview = ref(null)
let previewTimer = null

const filteredMarkets = computed(() => {
  const q = search.value.trim().toLowerCase()
  const rows = overview.value.markets || []
  if (!q) return rows
  return rows.filter(r =>
    r.symbol.toLowerCase().includes(q)
    || (r.name || '').toLowerCase().includes(q)
    || (r.sector || '').toLowerCase().includes(q)
  )
})

const tradeEstimate = computed(() => {
  if (!trade.value) return 0
  const n = Math.max(1, Math.floor(Number(tradeShares.value) || 0))
  return (Number(trade.value.price) || 0) * n
})

function fmt(n) {
  return (Number(n) || 0).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })
}
function fmtPct(n) {
  const v = Number(n) || 0
  const sign = v > 0 ? '+' : ''
  return `${sign}${v.toFixed(2)}%`
}
function fmtYield(y) {
  const v = (Number(y) || 0) * 100
  return `${v.toFixed(1)}%`
}
function chgClass(n) {
  const v = Number(n) || 0
  if (v > 0.05) return 'up'
  if (v < -0.05) return 'down'
  return ''
}
function sectorLabel(s) { return SECTORS[s] || s }

function changeTab(direction) {
  const idx = Math.max(0, TAB_IDS.indexOf(tab.value))
  const next = TAB_IDS[(idx + direction + TAB_IDS.length) % TAB_IDS.length]
  tab.value = next
  requestAnimationFrame(() => document.getElementById('sm-tab-' + next)?.focus())
}

async function refresh() {
  try {
    const data = await lua.overhaul_career_economy_stockMarket.getOverview()
    if (data) overview.value = data
  } catch (e) {
    reportUiFailure(e, 'stock market overview')
  } finally {
    loaded.value = true
  }
}

async function refreshPreview() {
  const amount = Number(withdrawAmount.value) || 0
  if (amount < 1) {
    withdrawPreview.value = null
    return
  }
  try {
    const preview = await lua.overhaul_career_economy_stockMarket.previewWithdraw(amount)
    withdrawPreview.value = preview || null
  } catch (_) {
    withdrawPreview.value = null
  }
}

watch(withdrawAmount, () => {
  if (previewTimer) clearTimeout(previewTimer)
  previewTimer = setTimeout(refreshPreview, 200)
})

watch(() => overview.value.broker?.withdrawableMax, () => {
  if (tab.value === 'broker') refreshPreview()
})

function openTrade(row) {
  trade.value = {
    mode: 'buy',
    symbol: row.symbol,
    name: row.name,
    price: row.price,
  }
  tradeShares.value = 1
}

function openSell(h) {
  trade.value = {
    mode: 'sell',
    symbol: h.ticker,
    name: h.name,
    price: h.price,
    maxShares: Math.floor(h.shares),
  }
  tradeShares.value = Math.min(1, Math.floor(h.shares))
}

async function confirmTrade() {
  const shares = Math.max(1, Math.floor(Number(tradeShares.value) || 0))
  try {
    let res
    if (trade.value.mode === 'sell') {
      res = await lua.overhaul_career_economy_stockMarket.sellShares(trade.value.symbol, shares)
    } else {
      res = await lua.overhaul_career_economy_stockMarket.buyShares(trade.value.symbol, shares)
    }
    if (res?.ok === false) {
      reportUiFailure(res.reason || 'trade failed', 'stock trade')
      return
    }
    if (res?.overview) overview.value = res.overview
    else await refresh()
    trade.value = null
  } catch (e) {
    reportUiFailure(e, 'stock trade')
  }
}

async function setDividendPref(ticker, mode) {
  try {
    const res = await lua.overhaul_career_economy_stockMarket.setDividendPreference(ticker, mode)
    if (res?.ok === false) {
      reportUiFailure(res.reason || 'preference failed', 'dividend preference')
      return
    }
    if (res?.overview) overview.value = res.overview
    else await refresh()
  } catch (e) {
    reportUiFailure(e, 'dividend preference')
  }
}

async function depositBroker() {
  try {
    const res = await lua.overhaul_career_economy_stockMarket.depositBroker(Number(brokerAmount.value) || 0)
    if (res?.ok === false) {
      reportUiFailure(res.reason || 'deposit failed', 'broker deposit')
      return
    }
    if (res?.overview) overview.value = res.overview
    else await refresh()
    await refreshPreview()
  } catch (e) { reportUiFailure(e, 'broker deposit') }
}

async function withdrawBroker() {
  try {
    const res = await lua.overhaul_career_economy_stockMarket.withdrawFromHoldings(Number(withdrawAmount.value) || 0)
    if (res?.ok === false) {
      reportUiFailure(res.reason || 'withdraw failed', 'broker withdraw')
      return
    }
    if (res?.overview) overview.value = res.overview
    else await refresh()
    await refreshPreview()
  } catch (e) { reportUiFailure(e, 'broker withdraw') }
}

async function withdrawAll() {
  try {
    const res = await lua.overhaul_career_economy_stockMarket.withdrawAll()
    if (res?.ok === false) {
      reportUiFailure(res.reason || 'withdraw failed', 'broker withdraw all')
      return
    }
    if (res?.overview) overview.value = res.overview
    else await refresh()
    withdrawAmount.value = Math.max(1, Math.floor(Number(overview.value.broker?.withdrawableMax) || 1))
    await refreshPreview()
  } catch (e) { reportUiFailure(e, 'broker withdraw all') }
}

async function toggleBroker(enabled) {
  try {
    const res = await lua.overhaul_career_economy_stockMarket.setBrokerEnabled(!!enabled)
    if (res?.overview) overview.value = res.overview
    else await refresh()
  } catch (e) { reportUiFailure(e, 'broker toggle') }
}

let poll = null
onMounted(async () => {
  try {
    await acquireScope(lua, 'career.stockMarket')
  } catch (e) {
    reportUiFailure(e, 'stock market scope')
  }
  await refresh()
  await refreshPreview()
  poll = setInterval(refresh, 8000)
})
onUnmounted(() => {
  if (poll) clearInterval(poll)
  if (previewTimer) clearTimeout(previewTimer)
})
</script>

<style scoped lang="scss">
.sm-app {
  height: 100%;
  position: relative;
  background: #111;
  color: #fff;
  overflow-y: auto;
  overflow-x: hidden;
  padding: 44px 12px 80px;
  box-sizing: border-box;
  border-radius: 0 0 16px 16px;
  font-size: 0.9em;
}

.empty-state, .hint {
  padding: 16px 4px;
  color: rgba(255, 255, 255, 0.45);
  font-size: 12.5px;
}

.tabs {
  display: flex;
  gap: 4px;
  margin-bottom: 12px;

  button {
    flex: 1;
    padding: 8px 6px;
    border: none;
    border-radius: 10px;
    background: transparent;
    color: rgba(255, 255, 255, 0.5);
    font: inherit;
    font-size: 12px;
    font-weight: 700;
    cursor: pointer;

    &.active {
      background: rgba(14, 165, 233, 0.22);
      color: #7dd3fc;
    }
  }
}

.search, .amt, .field input {
  width: 100%;
  box-sizing: border-box;
  padding: 8px 10px;
  border-radius: 10px;
  border: 1px solid rgba(255, 255, 255, 0.12);
  background: #0d0d0d;
  color: #fff;
  font: inherit;
  font-size: 13px;
  margin-bottom: 10px;
}

.list { display: flex; flex-direction: column; gap: 6px; }

.row, .holding {
  display: flex;
  justify-content: space-between;
  gap: 10px;
  width: 100%;
  text-align: left;
  padding: 10px;
  border-radius: 12px;
  border: 1px solid rgba(255, 255, 255, 0.08);
  background: rgba(255, 255, 255, 0.03);
  color: inherit;
  font: inherit;
  cursor: pointer;

  &.compact { cursor: default; align-items: center; }
}

.row-main {
  display: flex;
  flex-direction: column;
  gap: 2px;
  min-width: 0;
}

.sym { font-weight: 800; font-size: 13px; letter-spacing: 0.04em; }
.name { font-size: 12px; color: rgba(255, 255, 255, 0.75); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.sector { font-size: 10.5px; color: rgba(255, 255, 255, 0.4); }

.div-pref {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-top: 6px;
  font-size: 10.5px;
  color: rgba(255, 255, 255, 0.55);

  select {
    flex: 1;
    min-width: 0;
    padding: 4px 6px;
    border-radius: 6px;
    border: 1px solid rgba(255, 255, 255, 0.14);
    background: #0d0d0d;
    color: #fff;
    font: inherit;
    font-size: 11px;
  }
}

.row-side {
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  gap: 2px;
  flex-shrink: 0;
}

.price { font-weight: 700; font-size: 13px; }
.chg {
  font-size: 11px;
  font-weight: 700;
  color: rgba(255, 255, 255, 0.45);
  &.up { color: #6ee7b7; }
  &.down { color: #fca5a5; }
}

.summary {
  display: flex;
  justify-content: space-between;
  align-items: baseline;
  padding: 10px 12px;
  margin-bottom: 10px;
  border-radius: 12px;
  background: rgba(14, 165, 233, 0.12);
  font-size: 12px;

  strong { font-size: 16px; }

  &.stack {
    flex-direction: column;
    gap: 6px;
    div { display: flex; justify-content: space-between; width: 100%; }
  }
}

.toggle {
  display: flex;
  justify-content: space-between;
  align-items: center;
  font-size: 12.5px;
  font-weight: 600;
  margin-bottom: 10px;
}

.actions {
  display: grid;
  gap: 6px;
  margin-bottom: 8px;

  .amt { margin: 0; }

  &.deposit-row {
    grid-template-columns: 1fr auto;
  }

  &.withdraw-row {
    grid-template-columns: 1fr auto auto;
  }
}

.preview {
  margin: 0 0 12px;
  font-size: 11px;
  line-height: 1.45;
  color: rgba(255, 255, 255, 0.55);
}

.btn {
  padding: 8px 12px;
  border-radius: 10px;
  border: none;
  background: #0ea5e9;
  color: #fff;
  font: inherit;
  font-size: 12px;
  font-weight: 700;
  cursor: pointer;

  &.ghost {
    background: transparent;
    border: 1px solid rgba(255, 255, 255, 0.16);
    color: rgba(255, 255, 255, 0.75);
  }

  &.danger {
    background: transparent;
    border: 1px solid rgba(248, 113, 113, 0.4);
    color: #fca5a5;
  }

  &.full { width: 100%; margin-bottom: 12px; }
}

.mini {
  margin-top: 4px;
  padding: 3px 8px;
  border-radius: 6px;
  border: 1px solid rgba(255, 255, 255, 0.16);
  background: transparent;
  color: #7dd3fc;
  font: inherit;
  font-size: 10.5px;
  font-weight: 700;
  cursor: pointer;
}

.fee-note {
  font-size: 11px;
  color: rgba(255, 255, 255, 0.45);
  line-height: 1.4;
  margin: 0 0 10px;
}

.log {
  margin-top: 14px;
  h4 {
    margin: 0 0 6px;
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    color: rgba(255, 255, 255, 0.4);
  }
}

.log-line {
  margin: 0 0 4px;
  font-size: 11px;
  color: rgba(255, 255, 255, 0.55);
}

.trade-overlay {
  display: flex;
  align-items: center;
  justify-content: center;
  background: rgba(0, 0, 0, 0.55);
}

.trade-modal {
  width: min(300px, 90%);
  padding: 16px;
  border-radius: 14px;
  background: #141414;
  border: 1px solid rgba(255, 255, 255, 0.12);

  h3 { margin: 0 0 4px; font-size: 16px; }
  .sub { margin: 0 0 12px; font-size: 12px; color: rgba(255, 255, 255, 0.5); }
  .field {
    display: flex;
    flex-direction: column;
    gap: 4px;
    font-size: 11px;
    color: rgba(255, 255, 255, 0.55);
  }
  .est { font-size: 12.5px; font-weight: 600; margin: 8px 0 12px; }
}

.confirm-actions {
  display: flex;
  gap: 8px;
  .btn { flex: 1; }
}
</style>
