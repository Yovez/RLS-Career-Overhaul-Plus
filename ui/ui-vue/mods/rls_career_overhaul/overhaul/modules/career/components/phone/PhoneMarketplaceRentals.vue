<!-- RLS Career Overhaul · https://github.com/RLS-Modding/rls_career_overhaul ; additional permission: licenses/RLS-BeamNG-Permission.txt
     Copyright (C) RLS Modding
     SPDX-License-Identifier: AGPL-3.0-only -->

<template>
  <div class="rentals-panel">
    <section class="block">
      <h3 class="block-title">Active rentals</h3>
      <p v-if="!active.length" class="empty">No vehicles currently rented out.</p>
      <article v-for="row in active" :key="'a-' + row.inventoryId" class="card">
        <div class="card-main">
          <div class="info">
            <strong>{{ row.niceName }}</strong>
            <span>${{ formatMoney(row.agreedDailyRate) }}/day · {{ row.termDays }} day term</span>
            <span>{{ formatRemaining(row.secondsRemaining) }} left</span>
          </div>
          <button type="button" class="btn danger" @click="endEarly(row)">End early</button>
        </div>
      </article>
    </section>

    <section class="block">
      <h3 class="block-title">Rent listings</h3>
      <p v-if="!listings.length" class="empty">No rental listings.</p>
      <article v-for="row in listings" :key="'l-' + row.inventoryId" class="card">
        <div class="card-main">
          <div class="info">
            <strong>{{ row.niceName }}</strong>
            <span>Ask ${{ formatMoney(row.askingDailyRate) }}/day · market ${{ formatMoney(row.marketDailyRate) }}/day</span>
            <span>{{ row.offerCount || 0 }} offer(s)</span>
          </div>
          <div class="actions">
            <button type="button" class="btn" @click="openOffers(row)">Offers</button>
            <button type="button" class="btn ghost" @click="removeListing(row)">Remove</button>
          </div>
        </div>
      </article>
      <button type="button" class="add-btn" @click="sheetOpen = true">+ Rent out a vehicle</button>
    </section>

    <PhoneLayer v-if="sheetOpen" class="sheet-overlay" @click.self="sheetOpen = false" label="Rent out vehicle" @close="sheetOpen = false">
      <div class="sheet">
        <div class="sheet-head">
          <h2>Rent out a vehicle</h2>
          <button type="button" class="sheet-close" @click="sheetOpen = false">×</button>
        </div>
        <p v-if="!rentableVehicles.length" class="empty">No eligible vehicles.</p>
        <template v-else>
          <label class="field-label">Vehicle</label>
          <select v-model="selectedId" class="select">
            <option v-for="v in rentableVehicles" :key="v.id" :value="v.id">{{ v.niceName }}</option>
          </select>
          <label class="field-label">Daily rate (market ${{ formatMoney(marketDaily) }}/day)</label>
          <input
            v-model.number="askingDaily"
            class="input"
            type="number"
            min="25"
            step="25"
            placeholder="Asking daily rate"
            v-bng-text-input
            v-phone-number="25"
          />
          <p v-if="guidance" class="hint" :class="guidance.tier">{{ guidance.label }}: {{ guidance.description }}</p>
          <p class="hint">Deposit at accept: ${{ formatMoney(guidance?.deposit || marketDaily * 2) }} · Term 1–7 sim days (NPC picks)</p>
          <button type="button" class="list-btn" :disabled="busy" @click="listSelected">List for rent</button>
        </template>
      </div>
    </PhoneLayer>

    <PhoneLayer v-if="offersTarget" class="sheet-overlay" @click.self="offersTarget = null" label="Rental offers" @close="offersTarget = null">
      <div class="sheet">
        <div class="sheet-head">
          <h2>Offers · {{ offersTarget.niceName }}</h2>
          <button type="button" class="sheet-close" @click="offersTarget = null">×</button>
        </div>
        <p v-if="!(offersTarget.offers || []).length" class="empty">No offers yet.</p>
        <article v-for="offer in offersTarget.offers || []" :key="offer.index" class="card">
          <div class="info">
            <strong>{{ offer.buyerName }}</strong>
            <span>${{ formatMoney(offer.negotiatedRate || offer.value) }}/day</span>
          </div>
          <div class="actions">
            <button type="button" class="btn" @click="accept(offer)">Accept</button>
            <button type="button" class="btn" :disabled="!offer.negotiationPossible" @click="negotiate(offer)">Negotiate</button>
            <button type="button" class="btn ghost" @click="decline(offer)">Decline</button>
          </div>
        </article>
      </div>
    </PhoneLayer>
  </div>
</template>

<script setup>
import { vPhoneNumber } from "../phone/phoneNumber.js"
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { lua, useBridge } from '@/bridge'
import { vBngTextInput } from '@/common/directives'
import PhoneLayer from './PhoneLayer.vue'
import { useVehicleInventoryStore } from '../../stores/vehicleInventoryStore'
import { openConfirmation } from '@/services/popup'

defineOptions({ directives: { BngTextInput: vBngTextInput, PhoneNumber: vPhoneNumber } })

const { events } = useBridge()
const inventoryStore = useVehicleInventoryStore()
const listings = ref([])
const active = ref([])
const sheetOpen = ref(false)
const offersTarget = ref(null)
const selectedId = ref(null)
const askingDaily = ref(50)
const guidance = ref(null)
const busy = ref(false)
const listedRentIds = computed(() => new Set(listings.value.map(l => String(l.inventoryId))))
const activeRentIds = computed(() => new Set(active.value.map(a => String(a.inventoryId))))

const rentableVehicles = computed(() => {
  const vehicles = inventoryStore.filteredVehicles || []
  return vehicles.filter(v =>
    v.owned !== false &&
    !v.listedForSale &&
    !v.rentedOut &&
    !v.timeToAccess &&
    !v.loanType &&
    !listedRentIds.value.has(String(v.id)) &&
    !activeRentIds.value.has(String(v.id))
  )
})

const marketDaily = computed(() => {
  const v = rentableVehicles.value.find(x => String(x.id) === String(selectedId.value))
  const sell = Number(v?.marketSellValue || v?.value || 0)
  return Math.max(25, Math.floor(sell * 0.01 + 0.5))
})

function formatMoney(n) {
  return new Intl.NumberFormat().format(Math.floor(Number(n) || 0))
}

function formatRemaining(seconds) {
  const s = Math.max(0, Number(seconds) || 0)
  const days = s / 1200
  if (days >= 1) return `${days.toFixed(1)} sim days`
  return `${Math.ceil(s)}s sim`
}

async function refresh() {
  const api = lua.overhaul_career_market_vehicleRentals
  if (!api) return
  const [list, act] = await Promise.all([
    api.getListings?.() || [],
    api.getActiveRentals?.() || [],
  ])
  listings.value = Array.isArray(list) ? list : []
  active.value = Array.isArray(act) ? act : []
}

watch([selectedId, askingDaily], async () => {
  const api = lua.overhaul_career_market_vehicleRentals
  if (!api?.getPriceGuidance || !selectedId.value) {
    guidance.value = null
    return
  }
  guidance.value = await api.getPriceGuidance(selectedId.value, Number(askingDaily.value) || 0)
})

watch(rentableVehicles, (vehicles) => {
  if (!vehicles.some(v => String(v.id) === String(selectedId.value))) {
    selectedId.value = vehicles[0]?.id ?? null
  }
}, { immediate: true })

watch(marketDaily, (m) => {
  if (!askingDaily.value || askingDaily.value === 50) askingDaily.value = m
}, { immediate: true })

async function listSelected() {
  if (busy.value || !selectedId.value) return
  busy.value = true
  try {
    const api = lua.overhaul_career_market_vehicleRentals
    await api.listForRent(selectedId.value, Number(askingDaily.value) || marketDaily.value)
    await refresh()
    sheetOpen.value = false
  } finally {
    busy.value = false
  }
}

async function removeListing(row) {
  const ok = await openConfirmation('Remove listing', `Remove rental listing for ${row.niceName}?`)
  if (!ok) return
  await lua.overhaul_career_market_vehicleRentals.removeListing(row.inventoryId)
  await refresh()
}

async function openOffers(row) {
  const data = await lua.overhaul_career_market_vehicleRentals.getListingOffersData(row.inventoryId)
  offersTarget.value = data || { ...row, offers: [] }
}

async function accept(offer) {
  await lua.overhaul_career_market_vehicleRentals.acceptOffer(offersTarget.value.inventoryId, offer.index)
  offersTarget.value = null
  await refresh()
}

async function negotiate(offer) {
  try { sessionStorage.setItem('phoneMarketplaceNegotiateMode', 'rent') } catch (_) {}
  await lua.overhaul_career_market_vehicleRentals.startNegotiateRentOffer(
    offersTarget.value.inventoryId,
    offer.index,
    true,
  )
  offersTarget.value = null
}

async function decline(offer) {
  await lua.overhaul_career_market_vehicleRentals.declineOffer(offersTarget.value.inventoryId, offer.index)
  await openOffers(offersTarget.value)
}

async function endEarly(row) {
  const ok = await openConfirmation(
    'End rental early',
    `End rental of ${row.niceName}?\n\nUnused prepaid time is refunded to the renter. Return damage may still apply.`
  )
  if (!ok) return
  await lua.overhaul_career_market_vehicleRentals.endRentalEarly(row.inventoryId)
  await refresh()
}

function onUpdated() { refresh() }

onMounted(async () => {
  await inventoryStore.requestInitialData()
  await refresh()
  events.on('vehicleRentals:updated', onUpdated)
})

onBeforeUnmount(() => {
  events.off('vehicleRentals:updated', onUpdated)
})
</script>

<style scoped lang="scss">
.rentals-panel { display: flex; flex-direction: column; gap: 18px; padding: 8px 0 24px; }
.block-title { margin: 0 0 8px; font-size: 13px; font-weight: 700; color: rgba(255,255,255,0.7); text-transform: uppercase; letter-spacing: 0.04em; }
.empty { color: rgba(255,255,255,0.45); font-size: 13px; margin: 0 0 8px; }
.card { background: #1a1a1a; border: 1px solid rgba(255,255,255,0.06); border-radius: 12px; padding: 12px; margin-bottom: 8px; }
.card-main, .actions { display: flex; gap: 8px; align-items: center; justify-content: space-between; }
.info { display: flex; flex-direction: column; gap: 2px; font-size: 12px; color: rgba(255,255,255,0.65); }
.info strong { color: #fff; font-size: 14px; }
.btn, .add-btn, .list-btn {
  border: 0; border-radius: 8px; padding: 8px 10px; background: #2563eb; color: #fff; font-weight: 600; font-size: 12px;
}
.btn.ghost, .sheet-close { background: rgba(255,255,255,0.08); }
.btn.danger { background: #b91c1c; }
.add-btn { width: 100%; margin-top: 8px; background: rgba(255,255,255,0.08); }
.sheet-overlay { position: absolute; inset: 0; background: rgba(0,0,0,0.55); display: flex; align-items: flex-end; z-index: 20; }
.sheet { width: 100%; background: #121212; border-radius: 16px 16px 0 0; padding: 16px; display: flex; flex-direction: column; gap: 10px; }
.sheet-head { display: flex; justify-content: space-between; align-items: center; }
.sheet-head h2 { margin: 0; font-size: 16px; }
.field-label { font-size: 12px; color: rgba(255,255,255,0.55); }
.select, .input { width: 100%; box-sizing: border-box; background: #1a1a1a; border: 1px solid rgba(255,255,255,0.1); border-radius: 8px; color: #fff; padding: 10px; }
.hint { font-size: 12px; color: rgba(255,255,255,0.55); margin: 0; }
.hint.low { color: #34d399; }
.hint.high { color: #f97316; }
.list-btn { width: 100%; }
</style>
