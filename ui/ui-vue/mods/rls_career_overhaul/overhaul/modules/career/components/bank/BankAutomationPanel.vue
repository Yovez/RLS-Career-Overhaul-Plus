<!-- RLS Career Overhaul · https://github.com/RLS-Modding/rls_career_overhaul ; additional permission: licenses/RLS-BeamNG-Permission.txt
     Copyright (C) RLS Modding
     SPDX-License-Identifier: AGPL-3.0-only -->

<template>
  <div class="automation-panel">
    <h3 class="section-title">Automation</h3>
    <p class="intro">Set rules once and this account handles the rest. Changes save right away.</p>
    <p v-if="!loaded" class="hint">Loading…</p>
    <template v-else>
      <!-- Auto-pay (checking only) -->
      <section v-if="isChecking" class="block">
        <label class="row-toggle">
          <span>Auto-pay bills from checking</span>
          <input type="checkbox" v-model="autoPayEnabled" @change="saveAutoPay" />
        </label>
        <p class="hint">Spends from this checking first for the categories you pick. Wallet covers the rest.</p>
        <template v-if="autoPayEnabled">
          <p class="field-label">Categories to pay from here</p>
          <div class="chips">
            <button
              v-for="cat in spendCategories"
              :key="cat"
              type="button"
              class="chip"
              :class="{ on: autoPay[cat], claimed: claimOwner(cat) && claimOwner(cat) !== accountId }"
              :title="spendTitle(cat)"
              @click="togglePayCategory(cat)"
            >{{ labelSpend(cat) }}</button>
          </div>
          <p class="hint">Grey means another checking account already claimed that category.</p>
        </template>
      </section>

      <!-- Auto-deposit -->
      <section class="block">
        <label class="row-toggle">
          <span>Auto-deposit income here</span>
          <input type="checkbox" v-model="autoDeposit.enabled" @change="saveAutoDeposit" />
        </label>
        <p class="hint">When pay hits your wallet, scoop some of it into this account.</p>
        <template v-if="autoDeposit.enabled">
          <div class="field field-stack">
            <span>Wallet cushion ($)</span>
            <input type="number" min="0" v-model.number="autoDeposit.walletFloor" v-bng-text-input inputmode="decimal" @keydown.stop @keyup.stop @keypress.stop @change="saveAutoDeposit" />
            <p class="hint">Always leave yourself at least this much cash on hand.</p>
          </div>
          <div class="field field-stack">
            <span>Deposit share (%)</span>
            <input type="number" min="0" max="100" v-model.number="autoDeposit.percent" v-bng-text-input inputmode="numeric" @keydown.stop @keyup.stop @keypress.stop @change="saveAutoDeposit" />
            <p class="hint">How much of the leftover payout to bank (after the cushion).</p>
          </div>
          <p class="field-label">Income types to auto-deposit</p>
          <div class="chips">
            <button
              v-for="cat in incomeCategories"
              :key="cat"
              type="button"
              class="chip"
              :class="{ on: autoDeposit.income[cat] !== false }"
              :title="incomeTitle(cat)"
              @click="toggleIncomeCategory(cat)"
            >{{ labelIncome(cat) }}</button>
          </div>
        </template>
      </section>

      <!-- Auto-invest (checking only) -->
      <section v-if="isChecking" class="block">
        <label class="row-toggle">
          <span>Auto-invest surplus</span>
          <input
            type="checkbox"
            :checked="autoInvest.enabled"
            @change="onAutoInvestEnabled($event.target.checked)"
          />
        </label>
        <p v-if="investError" class="hint warn">{{ investError }}</p>
        <p class="hint">When checking climbs past your floor, put the extra into the stock market.</p>
        <template v-if="autoInvest.enabled">
          <div class="field field-stack">
            <span>Where should surplus go?</span>
            <div class="chips tight">
              <button
                type="button"
                class="chip"
                :class="{ on: autoInvest.mode === 'broker' }"
                @click="setInvestMode('broker')"
              >Broker cash</button>
              <button
                type="button"
                class="chip"
                :class="{ on: autoInvest.mode === 'stocks' }"
                @click="setInvestMode('stocks')"
              >My stock picks</button>
            </div>
            <p class="hint">
              <template v-if="autoInvest.mode === 'broker'">
                Sends the money to broker cash. Turn on managed trading in Stock Market if you want it traded for you.
              </template>
              <template v-else>
                Buys the companies you pick below, split evenly.
              </template>
            </p>
          </div>
          <div class="field field-stack">
            <span>Checking floor ($)</span>
            <input type="number" min="0" v-model.number="autoInvest.accountFloor" v-bng-text-input inputmode="decimal" @keydown.stop @keyup.stop @keypress.stop @change="saveAutoInvest" />
            <p class="hint">Keep this much in checking. Only the rest gets invested.</p>
          </div>
          <div class="field field-stack">
            <span>Minimum invest amount ($)</span>
            <input type="number" min="1" v-model.number="autoInvest.minAmount" v-bng-text-input inputmode="decimal" @keydown.stop @keyup.stop @keypress.stop @change="saveAutoInvest" />
            <p class="hint">Don't bother investing until the surplus is at least this big.</p>
          </div>
          <template v-if="autoInvest.mode === 'stocks'">
            <p class="field-label">Companies to buy</p>
            <p class="hint">Tap the ones you want. Each invest splits evenly between them.</p>
            <div class="chips">
              <button
                v-for="t in tickers"
                :key="t.symbol"
                type="button"
                class="chip"
                :class="{ on: !!autoInvest.tickers[t.symbol] }"
                :title="`${t.name} (${sectorLabel(t.sector)})`"
                @click="toggleInvestTicker(t.symbol)"
              >{{ t.symbol }}</button>
            </div>
            <p v-if="!hasInvestTickers" class="hint warn">Pick at least one company or nothing will buy.</p>
          </template>
        </template>
      </section>

      <!-- Balance rules -->
      <section class="block">
        <div class="row-head">
          <span>Balance rules</span>
          <button type="button" class="small-btn" @click="addRule">Add</button>
        </div>
        <p class="hint">Park overflow in savings, or top this account back up when it runs low.</p>
        <div v-for="(rule, index) in balanceRules" :key="rule.id" class="rule-card">
          <label class="row-toggle compact">
            <span>Rule {{ index + 1 }} enabled</span>
            <input type="checkbox" v-model="rule.enabled" @change="saveRules" />
          </label>
          <div class="field field-stack">
            <span>Trigger when this account’s balance is…</span>
            <div class="chips tight">
              <button
                v-for="op in operators"
                :key="op"
                type="button"
                class="chip"
                :class="{ on: rule.operator === op }"
                :title="operatorTitle(op)"
                @click="rule.operator = op; saveRules()"
              >{{ labelOperator(op) }}</button>
            </div>
          </div>
          <div class="field field-stack">
            <span>Threshold amount ($)</span>
            <input type="number" min="0" v-model.number="rule.amount" v-bng-text-input inputmode="decimal" @keydown.stop @keyup.stop @keypress.stop @change="saveRules" />
          </div>
          <div class="field field-stack">
            <span>What to do</span>
            <div class="chips tight">
              <button type="button" class="chip" :class="{ on: rule.action === 'sweepAbove' }" @click="rule.action = 'sweepAbove'; saveRules()">Send surplus there</button>
              <button type="button" class="chip" :class="{ on: rule.action === 'topUp' }" @click="rule.action = 'topUp'; saveRules()">Pull from there</button>
            </div>
            <p class="hint">
              <template v-if="rule.action === 'topUp'">
                Borrow from the other account until you hit this threshold.
              </template>
              <template v-else>
                Send whatever sits above the threshold over to the other account.
              </template>
            </p>
          </div>
          <div class="field field-stack">
            <span>Other account</span>
            <div class="chips tight">
              <button
                v-for="acc in otherAccounts"
                :key="acc.id"
                type="button"
                class="chip"
                :class="{ on: rule.linkedAccountId === acc.id }"
                @click="rule.linkedAccountId = acc.id; saveRules()"
              >{{ acc.name }}</button>
              <p v-if="otherAccounts.length === 0" class="hint warn">Open another Checking or Savings account first so you have somewhere to link.</p>
            </div>
          </div>
          <button type="button" class="small-btn danger" @click="removeRule(index)">Remove rule</button>
        </div>
      </section>
    </template>
  </div>
</template>

<script setup>
import { computed, onMounted, reactive, ref, watch } from 'vue'
import { lua } from '@/bridge'
import { reportUiFailure } from '../../utils/safeLua'

const props = defineProps({
  accountId: { type: String, required: true },
  accountType: { type: String, default: 'checking' },
  accounts: { type: Array, default: () => [] },
})

const loaded = ref(false)
const isChecking = computed(() => props.accountType === 'checking')
const spendCategories = ref([])
const incomeCategories = ref([])
const operators = ref(['lt', 'lte', 'eq', 'gte', 'gt'])
const autoPayEnabled = ref(false)
const autoPay = reactive({})
const payClaims = reactive({})
const autoDeposit = reactive({
  enabled: false,
  walletFloor: 0,
  percent: 100,
  income: {},
})
const autoInvest = reactive({
  enabled: false,
  mode: 'broker',
  accountFloor: 5000,
  minAmount: 100,
  tickers: {},
})
const tickers = ref([])
const balanceRules = ref([])
const investError = ref('')
const hasInvestTickers = computed(() => Object.values(autoInvest.tickers).some(Boolean))

const otherAccounts = computed(() =>
  (props.accounts || []).filter(a => a.type === 'personal' && a.id !== props.accountId)
)

const SPEND_LABELS = {
  shops: 'Shops', vehicles: 'Vehicles', stocks: 'Stocks', fines: 'Fines',
  insurance: 'Insurance', loans: 'Loans', repairs: 'Repairs', fuel: 'Fuel',
  services: 'Services', property: 'Property', other: 'Other',
}
const SPEND_HELP = {
  shops: 'Parts, shops, everyday buys',
  vehicles: 'Buying cars and trailers',
  stocks: 'Stock buys and broker deposits',
  fines: 'Tickets and traffic fines',
  insurance: 'Insurance bills',
  loans: 'Loan payments',
  repairs: 'Body and mechanic work',
  fuel: 'Filling up',
  services: 'Towing, recovery, that kind of thing',
  property: 'Garages and real estate',
  other: 'Anything else you spend on',
}
const INCOME_LABELS = {
  reward: 'Jobs / rewards', sale: 'Sales', interest: 'Interest', refund: 'Refunds', other: 'Other',
}
const INCOME_HELP = {
  reward: 'Job and activity pay',
  sale: 'Selling cars, parts, or property',
  interest: 'Savings interest',
  refund: 'Money coming back to you',
  other: 'Other cash hitting your wallet',
}
const OPERATOR_LABELS = {
  lt: 'Below',
  lte: 'At or below',
  eq: 'Exactly',
  gte: 'At or above',
  gt: 'Above',
}
const OPERATOR_HELP = {
  lt: 'Runs when your balance dips under this amount',
  lte: 'Runs when your balance is this amount or less',
  eq: 'Runs when your balance hits this amount exactly',
  gte: 'Runs when your balance is this amount or more',
  gt: 'Runs when your balance goes over this amount',
}
const SECTOR_LABELS = {
  global: 'Broad market',
  vehicleMarket: 'Vehicles',
  housingMarket: 'Housing',
  jobMarket: 'Jobs / logistics',
}

function labelSpend(cat) { return SPEND_LABELS[cat] || cat }
function labelIncome(cat) { return INCOME_LABELS[cat] || cat }
function labelOperator(op) { return OPERATOR_LABELS[op] || op }
function operatorTitle(op) { return OPERATOR_HELP[op] || '' }
function sectorLabel(sector) { return SECTOR_LABELS[sector] || sector }
function claimOwner(cat) { return payClaims[cat] || null }
function claimTitle(cat) {
  const owner = claimOwner(cat)
  if (!owner || owner === props.accountId) return ''
  const acc = (props.accounts || []).find(a => a.id === owner)
  return acc ? `Already on ${acc.name}` : 'Already on another account'
}
function spendTitle(cat) {
  const claimed = claimTitle(cat)
  const help = SPEND_HELP[cat] || ''
  return claimed ? `${help}. ${claimed}` : help
}
function incomeTitle(cat) { return INCOME_HELP[cat] || '' }

function applyPayload(data) {
  if (!data) return
  spendCategories.value = data.spendCategories || []
  incomeCategories.value = data.incomeCategories || []
  operators.value = data.operators || operators.value
  autoPayEnabled.value = !!data.autoPayEnabled
  Object.keys(autoPay).forEach(k => delete autoPay[k])
  Object.assign(autoPay, data.autoPay || {})
  Object.keys(payClaims).forEach(k => delete payClaims[k])
  Object.assign(payClaims, data.payClaims || {})
  autoDeposit.enabled = !!data.autoDeposit?.enabled
  autoDeposit.walletFloor = Number(data.autoDeposit?.walletFloor) || 0
  autoDeposit.percent = Number(data.autoDeposit?.percent) ?? 100
  autoDeposit.income = { ...(data.autoDeposit?.income || {}) }
  autoInvest.enabled = !!data.autoInvest?.enabled
  autoInvest.mode = data.autoInvest?.mode === 'stocks' ? 'stocks' : 'broker'
  autoInvest.accountFloor = Number(data.autoInvest?.accountFloor) || 0
  autoInvest.minAmount = Number(data.autoInvest?.minAmount) || 100
  autoInvest.tickers = { ...(data.autoInvest?.tickers || {}) }
  tickers.value = Array.isArray(data.tickers) ? data.tickers : []
  balanceRules.value = Array.isArray(data.balanceRules)
    ? data.balanceRules.map(r => ({ ...r }))
    : []
  investError.value = ''
  loaded.value = true
}

async function refresh() {
  if (!props.accountId) return
  try {
    const data = await lua.overhaul_career_economy_bank.getAccountAutomation(props.accountId)
    applyPayload(data)
  } catch (e) {
    reportUiFailure(e, 'bank automation load')
    loaded.value = true
  }
}

async function saveAutoPay() {
  try {
    const res = await lua.overhaul_career_economy_bank.setAutoPay(props.accountId, autoPayEnabled.value, { ...autoPay })
    if (res?.automation) applyPayload(res.automation)
  } catch (e) { reportUiFailure(e, 'bank setAutoPay') }
}

function togglePayCategory(cat) {
  if (claimOwner(cat) && claimOwner(cat) !== props.accountId) return
  autoPay[cat] = !autoPay[cat]
  saveAutoPay()
}

function toggleIncomeCategory(cat) {
  autoDeposit.income[cat] = autoDeposit.income[cat] === false
  saveAutoDeposit()
}

async function saveAutoDeposit() {
  try {
    const res = await lua.overhaul_career_economy_bank.setAutoDeposit(props.accountId, {
      enabled: autoDeposit.enabled,
      walletFloor: autoDeposit.walletFloor,
      percent: autoDeposit.percent,
      income: { ...autoDeposit.income },
    })
    if (res?.automation) applyPayload(res.automation)
  } catch (e) { reportUiFailure(e, 'bank setAutoDeposit') }
}

function onAutoInvestEnabled(enabled) {
  autoInvest.enabled = !!enabled
  saveAutoInvest()
}

function setInvestMode(mode) {
  autoInvest.mode = mode === 'stocks' ? 'stocks' : 'broker'
  saveAutoInvest()
}

function toggleInvestTicker(symbol) {
  autoInvest.tickers[symbol] = !autoInvest.tickers[symbol]
  saveAutoInvest()
}

async function saveAutoInvest() {
  investError.value = ''
  try {
    const res = await lua.overhaul_career_economy_bank.setAutoInvest(props.accountId, {
      enabled: !!autoInvest.enabled,
      mode: autoInvest.mode,
      accountFloor: Number(autoInvest.accountFloor) || 0,
      percent: 100, // always invest full surplus above the floor
      minAmount: Number(autoInvest.minAmount) || 1,
      tickers: { ...autoInvest.tickers },
    })
    if (res?.ok === false) {
      investError.value = res.reason === 'checking_only'
        ? 'Auto-invest only works on a personal Checking account.'
        : 'Couldn\'t save auto-invest. Try again.'
      return
    }
    if (res?.automation) applyPayload(res.automation)
  } catch (e) {
    investError.value = 'Couldn\'t save auto-invest. Try again.'
    reportUiFailure(e, 'bank setAutoInvest')
  }
}

async function saveRules() {
  try {
    const res = await lua.overhaul_career_economy_bank.setBalanceRules(props.accountId, balanceRules.value)
    if (res?.automation) applyPayload(res.automation)
  } catch (e) { reportUiFailure(e, 'bank setBalanceRules') }
}

function addRule() {
  const linked = otherAccounts.value[0]?.id || ''
  balanceRules.value.push({
    id: `rule-${Date.now()}`,
    linkedAccountId: linked,
    operator: 'gte',
    amount: 25000,
    action: 'sweepAbove',
    enabled: true,
  })
  saveRules()
}

function removeRule(index) {
  balanceRules.value.splice(index, 1)
  saveRules()
}

watch(() => props.accountId, refresh)
onMounted(refresh)
</script>

<style scoped lang="scss">
.automation-panel {
  margin: 0 0 16px;
  padding: 12px;
  border-radius: 12px;
  background: #ffffff;
  border: 1px solid #d4e2ff;
  box-shadow: 0 1px 2px rgba(16, 24, 40, 0.04), 0 4px 12px rgba(16, 24, 40, 0.05);
  color: #0f172a;
  flex: 0 0 auto;
}

.section-title {
  margin: 0 0 4px;
  font-size: 1.05rem;
  font-weight: 800;
  color: #0f172a;
}

.intro {
  margin: 0 0 12px;
  font-size: 11.5px;
  color: #64748b;
  line-height: 1.45;
}

.hint {
  margin: 0 0 8px;
  font-size: 11px;
  color: #64748b;
  line-height: 1.45;

  &.warn { color: #b45309; }
}

.field-label {
  display: block;
  margin: 8px 0 4px;
  font-size: 11.5px;
  font-weight: 700;
  color: #334155;
}

.block {
  margin-bottom: 14px;
  padding-bottom: 12px;
  border-bottom: 1px solid #e2e8f0;

  &:last-child {
    margin-bottom: 0;
    padding-bottom: 0;
    border-bottom: none;
  }
}

.row-toggle {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
  font-size: 12.5px;
  font-weight: 600;
  margin-bottom: 6px;
  color: #0f172a;

  &.compact { font-size: 11.5px; }
}

.row-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  font-size: 12.5px;
  font-weight: 600;
  margin-bottom: 4px;
  color: #0f172a;
}

.chips {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
  margin-top: 8px;

  &.tight { margin-top: 0; }
}

.field-stack {
  grid-template-columns: 1fr;
  gap: 6px;

  .hint { margin: 0; }
}

.chip {
  padding: 5px 9px;
  border-radius: 8px;
  border: 1px solid #cbd5e1;
  background: #f8fafc;
  color: #334155;
  font: inherit;
  font-size: 11px;
  font-weight: 600;
  cursor: pointer;

  &.on {
    background: rgba(16, 185, 129, 0.15);
    border-color: #10b981;
    color: #047857;
  }

  &.claimed:not(.on) {
    opacity: 0.4;
    cursor: not-allowed;
  }
}

.field {
  display: grid;
  grid-template-columns: 110px 1fr;
  gap: 8px;
  align-items: center;
  margin-top: 6px;
  font-size: 11.5px;
  color: #475569;

  input, select {
    width: 100%;
    box-sizing: border-box;
    padding: 6px 8px;
    border-radius: 8px;
    border: 1px solid #cbd5e1;
    background: #fff;
    color: #0f172a;
    font: inherit;
    font-size: 12px;
  }
}

.rule-card {
  margin-top: 8px;
  padding: 10px;
  border-radius: 10px;
  background: #f8fafc;
  border: 1px solid #e2e8f0;
}

.small-btn {
  padding: 4px 10px;
  border-radius: 8px;
  border: 1px solid #cbd5e1;
  background: #fff;
  color: #334155;
  font: inherit;
  font-size: 11px;
  font-weight: 600;
  cursor: pointer;

  &.danger {
    margin-top: 8px;
    color: #dc2626;
    border-color: #fecaca;
  }
}
</style>
