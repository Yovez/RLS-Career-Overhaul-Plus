<!-- RLS Career Overhaul · https://github.com/RLS-Modding/rls_career_overhaul ; additional permission: licenses/RLS-BeamNG-Permission.txt
     Copyright (C) RLS Modding
     SPDX-License-Identifier: AGPL-3.0-only -->

<template>
  <div class="phone-marketplace-home">
    <div class="search-bar-wrap">
      <div class="search-bar" data-focus-field>
        <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="rgba(255,255,255,.45)" stroke-width="2.4">
          <circle cx="11" cy="11" r="7" />
          <path d="M20 20l-4-4" />
        </svg>
        <input
          v-model="searchQuery"
          class="search-input"
          type="text"
          placeholder="Search private listings"
          v-bng-text-input
          @keydown.stop
          @keyup.stop
          @keypress.stop
        >
      </div>

      <div class="toolbar-row">
        <div class="dropdown-wrap">
          <button
            type="button"
            class="dropdown-btn"
            :class="{ active: filterOpen || filterCount > 0 }"
            @click="filterOpen = !filterOpen; sortOpen = false"
          >
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polygon points="22 3 2 3 10 12.46 10 19 14 21 14 12.46 22 3"/></svg>
            Filter
            <span v-if="filterCount" class="filter-count">{{ filterCount }}</span>
            <svg class="dropdown-chevron" :class="{ open: filterOpen }" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="6 9 12 15 18 9"/></svg>
          </button>
          <PhoneLayer
            v-if="filterOpen"
            class="dropdown-panel filter-panel"
            label="Listing filters"
            @close="filterOpen = false"
            @mousedown.stop
          >
            <label class="filter-opt" role="checkbox" tabindex="0" bng-nav-item :aria-checked="filterForm.affordable">
              <span class="custom-checkbox" :class="{ checked: filterForm.affordable }"><span class="custom-checkbox-dot"></span></span>
              <input type="checkbox" v-model="filterForm.affordable" class="sr-only" bng-no-nav="true" />
              Affordable only
            </label>
            <label class="filter-opt" role="checkbox" tabindex="0" bng-nav-item :aria-checked="filterForm.negotiable">
              <span class="custom-checkbox" :class="{ checked: filterForm.negotiable }"><span class="custom-checkbox-dot"></span></span>
              <input type="checkbox" v-model="filterForm.negotiable" class="sr-only" bng-no-nav="true" />
              Negotiable only
            </label>
            <label class="filter-opt" role="checkbox" tabindex="0" bng-nav-item :aria-checked="filterForm.underMarket">
              <span class="custom-checkbox" :class="{ checked: filterForm.underMarket }"><span class="custom-checkbox-dot"></span></span>
              <input type="checkbox" v-model="filterForm.underMarket" class="sr-only" bng-no-nav="true" />
              At or under market
            </label>
            <div class="filter-row">
              <label>Price</label>
              <div class="filter-inputs-stacked">
                <input type="number" v-model.number="filterForm.priceMin" placeholder="Min" min="0" inputmode="numeric" v-bng-text-input v-phone-number="1000" />
                <input type="number" v-model.number="filterForm.priceMax" placeholder="Max" min="0" inputmode="numeric" v-bng-text-input v-phone-number="1000" />
              </div>
            </div>
            <div class="filter-row">
              <label>Year</label>
              <div class="filter-inputs-stacked">
                <input type="number" v-model.number="filterForm.yearMin" placeholder="From" min="0" inputmode="numeric" v-bng-text-input v-phone-number="1" />
                <input type="number" v-model.number="filterForm.yearMax" placeholder="To" min="0" inputmode="numeric" v-bng-text-input v-phone-number="1" />
              </div>
            </div>
            <div class="filter-row">
              <label>Miles</label>
              <div class="filter-inputs-stacked">
                <input type="number" v-model.number="filterForm.mileageMaxMi" placeholder="Max" min="0" inputmode="numeric" v-bng-text-input v-phone-number="1000" />
              </div>
            </div>
            <div v-if="brandOptions.length" class="filter-brands">
              <span class="filter-brands-label">Make</span>
              <div class="brand-chips">
                <button
                  v-for="opt in brandOptions"
                  :key="opt.brand"
                  type="button"
                  class="brand-chip"
                  :class="{ active: filterForm.brands.includes(opt.brand) }"
                  @click="toggleBrand(opt.brand)"
                >
                  {{ opt.brand }}
                </button>
              </div>
            </div>
            <button type="button" class="filter-clear" @click="clearFilters">Clear</button>
          </PhoneLayer>
        </div>

        <div class="dropdown-wrap">
          <button
            type="button"
            class="dropdown-btn"
            :class="{ active: sortOpen }"
            @click="sortOpen = !sortOpen; filterOpen = false"
          >
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><line x1="4" y1="6" x2="20" y2="6"/><line x1="4" y1="12" x2="14" y2="12"/><line x1="4" y1="18" x2="9" y2="18"/></svg>
            Sort
            <svg class="dropdown-chevron" :class="{ open: sortOpen }" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="6 9 12 15 18 9"/></svg>
          </button>
          <PhoneLayer v-if="sortOpen" class="dropdown-panel sort-panel" label="Listing sorting" @close="sortOpen = false">
            <div class="sort-grid">
              <span class="sort-label">By</span>
              <div class="sort-options sort-fields">
                <button
                  v-for="f in sortFields"
                  :key="f.key"
                  type="button"
                  class="sort-opt"
                  :class="{ active: sortBy === f.key }"
                  @click="sortBy = f.key"
                >{{ f.label }}</button>
              </div>
              <span class="sort-label">Order</span>
              <div class="sort-options sort-order">
                <button type="button" class="sort-opt" :class="{ active: sortAsc }" @click="sortAsc = true">{{ sortAscLabel }}</button>
                <button type="button" class="sort-opt" :class="{ active: !sortAsc }" @click="sortAsc = false">{{ sortDescLabel }}</button>
              </div>
            </div>
          </PhoneLayer>
        </div>
      </div>
    </div>

    <div class="feed">
      <div class="feed-header">
        <div class="feed-title">Private listings</div>
        <div class="feed-count">{{ feedCountText }}</div>
      </div>

      <p v-if="!shopLoaded" class="feed-hint">Loading listings…</p>
      <p v-else-if="!feed.length" class="feed-hint">
        {{ emptyHint }}
      </p>

      <article v-for="row in feed" :key="row.shopId" class="listing-card">
        <button type="button" class="listing-photo" :style="row.photoStyle" @click="openVehicle(row)">
          <span v-if="!row.preview" class="photo-placeholder">Vehicle photo</span>
          <span class="seller-chip">
            <span class="avatar avatar--sm" :style="{ background: row.avatarBg }">{{ row.initials }}</span>
            <span class="seller-name">{{ row.sellerName }}</span>
          </span>
        </button>

        <div class="listing-body">
          <button type="button" class="listing-heading" @click="openVehicle(row)">
            <span class="listing-meta">{{ row.year }}, {{ row.mileageText }}</span>
            <span class="listing-name-row">
              <span class="listing-name">{{ row.name }}</span>
              <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="rgba(255,255,255,.4)" stroke-width="2.5">
                <path d="M9 6l6 6-6 6" />
              </svg>
            </span>
          </button>

          <div class="listing-footer">
            <div class="asking">
              <div class="asking-label">Asking</div>
              <div class="asking-value"><MoneyAmount>{{ row.askingText }}</MoneyAmount></div>
              <span v-if="row.delta" class="chip" :class="`chip--${row.delta.tone}`">{{ row.delta.text }}</span>
            </div>
            <button
              type="button"
              class="offer-btn"
              :disabled="(!row.canNegotiate && !row.pendingCheckout) || negotiateInProgress"
              :title="row.pendingCheckout ? '' : (row.canNegotiate ? '' : 'This seller will not haggle')"
              @click="makeOffer(row)"
            >
              {{ row.pendingCheckout ? 'Complete purchase' : 'Make an offer' }}
            </button>
          </div>
        </div>
      </article>
    </div>

    <PhoneMarketplaceNav active="buy" :unread-count="unreadCount" />
  </div>
</template>

<script setup>
import MoneyAmount from "../../components/MoneyAmount.vue"
import { reportUiFailure } from "../../utils/safeLua"

import { computed, onMounted, onUnmounted, ref } from 'vue'
import PhoneLayer from '../../components/phone/PhoneLayer.vue'
import PhoneMarketplaceNav from '../../components/phone/PhoneMarketplaceNav.vue'
import { vPhoneNumber } from '../../components/phone/phoneNumber.js'
import { lua, useBridge } from '@/bridge'
import { vBngTextInput } from '@/common/directives'
import { useVehicleShoppingStore } from '../../stores/vehicleShoppingStore'
import { usePhoneMarketplaceUi } from '../../composables/usePhoneMarketplaceUi'
import { usePhoneMarketplaceListings } from '../../composables/usePhoneMarketplaceListings'
import { usePhoneMarketplaceFilters } from '../../composables/usePhoneMarketplaceFilters'
import {
  avatarColour,
  avatarInitials,
  marketDelta,
  mileageText,
  usePhoneMarketplaceMoney,
} from '../../composables/usePhoneMarketplaceFormat'

usePhoneMarketplaceUi()

const { money } = usePhoneMarketplaceMoney()
const { unreadCount } = usePhoneMarketplaceListings()
const vehicleShoppingStore = useVehicleShoppingStore()
const { events } = useBridge()

/** Vehicles purchase reason — must match vehicleShopping/ui.lua vehicleSpendReason / payment pay. */
const MARKETPLACE_BUY_REASON = {
  category: 'purchase',
  tags: ['vehicleBought', 'buying'],
  label: 'Vehicle purchase',
}

const shopLoaded = ref(false)
const searchQuery = ref('')
const negotiateInProgress = ref(false)
const filterOpen = ref(false)
const sortOpen = ref(false)
/** Live Spendable from payment facade for marketplace buy affordability. */
const facadeSpendable = ref(null)

/** Raw shop stock — not filteredVehicles, which applies the computer's shared search/filters. */
const privateListings = computed(() => {
  const shop = vehicleShoppingStore.vehicleShoppingData?.vehiclesInShop
  if (!shop) return []
  const list = Array.isArray(shop) ? shop : Object.values(shop)
  return list.filter(v => String(v.sellerId) === 'private' && !v.__sold && !v.soldViewCounter)
})

/**
 * Buy-tab affordability gate: Spendable for the vehicles purchase reason when auto-pay applies;
 * equals Wallet when auto-pay is off. Prefer facade → shopping spendableMoney; never walletMoney
 * (cash-on-hand / deposit truth stays on walletMoney / playerAttributes.money).
 */
const playerBalance = computed(() => {
  if (Number.isFinite(facadeSpendable.value)) return facadeSpendable.value
  const d = vehicleShoppingStore.vehicleShoppingData
  const spendable = Number(d?.spendableMoney)
  if (Number.isFinite(spendable)) return spendable
  // Legacy payloads may still mirror Spendable into playerAttributes.money; do not use walletMoney.
  return Number(d?.playerAttributes?.money?.value ?? d?.playerAttributes?.money ?? 0) || 0
})

async function refreshBuySpendable() {
  try {
    const n = Number(await lua.overhaul_career_economy_payment.getSpendableMoney(MARKETPLACE_BUY_REASON))
    facadeSpendable.value = Number.isFinite(n) ? n : null
  } catch (_) {
    facadeSpendable.value = null
    reportUiFailure(_, 'optional action (PhoneMarketplace spendable)')
  }
}

const {
  filterForm,
  sortBy,
  sortAsc,
  sortFields,
  brandOptions,
  filterCount,
  filteredListings,
  toggleBrand,
  clearFilters,
  askingPrice,
} = usePhoneMarketplaceFilters({
  listings: privateListings,
  playerBalance,
  searchQuery,
})

const sortAscLabel = computed(() => {
  if (sortBy.value === 'year') return 'Oldest'
  if (sortBy.value === 'distance') return 'Nearest'
  if (sortBy.value === 'deal') return 'Best'
  if (sortBy.value === 'name') return 'A → Z'
  return 'Low → high'
})

const sortDescLabel = computed(() => {
  if (sortBy.value === 'year') return 'Newest'
  if (sortBy.value === 'distance') return 'Farthest'
  if (sortBy.value === 'deal') return 'Worst'
  if (sortBy.value === 'name') return 'Z → A'
  return 'High → low'
})

const feed = computed(() => filteredListings.value.map(v => {
  const asking = askingPrice(v)
  const sellerName = v.sellerName || 'Private seller'
  return {
    shopId: v.shopId || v.uid || v.id,
    name: [v.Brand, v.Name].filter(Boolean).join(' ') || v.Name || 'Vehicle',
    year: v.year || '—',
    preview: v.preview,
    photoStyle: v.preview ? { backgroundImage: `url('${v.preview}')` } : {},
    mileageText: mileageText(v.Mileage),
    sellerName,
    initials: avatarInitials(sellerName),
    avatarBg: avatarColour(sellerName),
    askingText: money(asking),
    // buying: paying under estimated market is the good outcome
    delta: marketDelta(asking, v.marketValue),
    canNegotiate: v.negotiationPossible !== false && !(Number(v.discountPercentage) > 0),
    pendingCheckout: !!v.pendingCheckout,
  }
}))

const feedCountText = computed(() => {
  const n = feed.value.length
  if (!shopLoaded.value) return ''
  const total = privateListings.value.length
  if (filterCount.value || searchQuery.value.trim()) {
    return `${n} of ${total}`
  }
  return n === 1 ? '1 listing' : `${n} listings`
})

const emptyHint = computed(() => {
  if (searchQuery.value.trim() || filterCount.value) {
    return 'No private listings match these filters.'
  }
  return 'No private listings right now. Check back later.'
})

function openVehicle(row) {
  if (!row.shopId) return
  lua.extensions.ui_router.navigate('phone-marketplace-vehicle', {
    kind: 'listing',
    vehicleId: String(row.shopId),
  })
}

async function makeOffer(row) {
  if (negotiateInProgress.value || !row.shopId) return
  if (!row.canNegotiate && !row.pendingCheckout) return
  negotiateInProgress.value = true
  try {
    if (row.pendingCheckout) {
      await lua.overhaul_career_market_vehicleShopping.openPurchaseMenu('instant', row.shopId)
      return
    }
    // Lua refuses some listings (discounted, non-negotiable, car meet rules) — it reports
    // back whether a negotiation actually opened.
    const started = await lua.overhaul_career_market_marketplace.startNegotiateSellingOffer(row.shopId, true)
    if (started) await lua.extensions.ui_router.navigate('phone-marketplace-negotiate')
  } finally {
    negotiateInProgress.value = false
  }
}

const onShopDelta = (delta) => {
  if (typeof vehicleShoppingStore.applyShopDelta === 'function') {
    vehicleShoppingStore.applyShopDelta(delta)
  }
  // Listing deltas do not refresh money; keep buy-tab Spendable aligned with the facade.
  refreshBuySpendable()
}

onMounted(async () => {
  events.on('vehicleShopDelta', onShopDelta)
  try {
    await lua.overhaul_career_market_vehicleShopping.setShoppingUiOpen(true)
  } catch (_) { reportUiFailure(_, "optional action (PhoneMarketplace)") }
  await vehicleShoppingStore.requestVehicleShoppingData()
  await refreshBuySpendable()
  shopLoaded.value = true
})

onUnmounted(() => {
  try {
    if (events && typeof events.off === 'function') events.off('vehicleShopDelta', onShopDelta)
  } catch (_) { reportUiFailure(_, "optional action (PhoneMarketplace)") }
  try { lua.overhaul_career_market_vehicleShopping.setShoppingUiOpen(false) } catch (_) { reportUiFailure(_, "optional action (PhoneMarketplace)") }
})
</script>

<style scoped lang="scss">
@use '@/styles/rls_career_overhaul/modules/career/styles/_phone-marketplace.scss' as *;

.phone-marketplace-home {
  display: flex;
  flex-direction: column;
  height: 100%;
  min-height: 0;
  box-sizing: border-box;
  color: #fff;
  overflow: hidden;
}

.search-bar-wrap {
  flex: none;
  padding: 42px 12px 10px;
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.search-bar {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 9px 11px;
  border-radius: 11px;
  background: rgba(255, 255, 255, 0.06);
  border: 1px solid rgba(255, 255, 255, 0.09);

  svg {
    flex: none;
  }
}

.search-input {
  flex: 1;
  min-width: 0;
  border: none;
  background: transparent;
  color: #fff;
  font: inherit;
  font-size: 12.5px;
  outline: none;

  &::placeholder {
    color: rgba(255, 255, 255, 0.4);
  }
}

.toolbar-row {
  display: flex;
  align-items: center;
  gap: 6px;
}

.dropdown-wrap {
  position: relative;
}

.dropdown-btn {
  display: flex;
  align-items: center;
  gap: 4px;
  padding: 5px 10px;
  border-radius: 8px;
  border: 1px solid rgba(255, 255, 255, 0.12);
  background: transparent;
  color: rgba(255, 255, 255, 0.7);
  font-size: 11px;
  font-weight: 600;
  font-family: inherit;
  cursor: pointer;

  &.active {
    background: $mkt-accent;
    border-color: $mkt-accent;
    color: #0f1116;
  }
}

.filter-count {
  min-width: 16px;
  height: 16px;
  padding: 0 4px;
  border-radius: 8px;
  background: rgba(15, 17, 22, 0.35);
  color: inherit;
  font-size: 10px;
  font-weight: 800;
  line-height: 16px;
  text-align: center;
}

.dropdown-chevron {
  transition: transform 0.15s ease;
  &.open { transform: rotate(180deg); }
}

.dropdown-panel {
  position: absolute;
  top: 100%;
  left: 0;
  margin-top: 4px;
  z-index: 100;
  min-width: 230px;
  max-width: min(280px, calc(100vw - 40px));
  max-height: 55vh;
  overflow-y: auto;
  border-radius: 12px;
  border: 1px solid rgba(255, 255, 255, 0.12);
  background: #1a1a1a;
  box-shadow: 0 8px 24px rgba(0, 0, 0, 0.45);
  outline: none;
}

.filter-panel {
  display: flex;
  flex-direction: column;
  gap: 8px;
  padding: 12px;
}

.sr-only {
  position: absolute;
  width: 1px;
  height: 1px;
  padding: 0;
  margin: -1px;
  overflow: hidden;
  clip: rect(0, 0, 0, 0);
  border: 0;
}

.custom-checkbox {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 18px;
  height: 18px;
  border-radius: 50%;
  border: 1.5px solid rgba(255, 255, 255, 0.35);
  flex-shrink: 0;

  .custom-checkbox-dot {
    width: 8px;
    height: 8px;
    border-radius: 50%;
    background: $mkt-accent;
    opacity: 0;
    transform: scale(0.5);
    transition: opacity 0.15s ease, transform 0.15s ease;
  }

  &.checked {
    border-color: rgba($mkt-accent, 0.55);

    .custom-checkbox-dot {
      opacity: 1;
      transform: scale(1);
    }
  }
}

.filter-opt {
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 12px;
  color: rgba(255, 255, 255, 0.8);
  cursor: pointer;
}

.filter-row {
  display: grid;
  grid-template-columns: 48px 1fr;
  gap: 6px;
  align-items: start;

  > label {
    font-size: 11px;
    color: rgba(255, 255, 255, 0.5);
    padding-top: 6px;
  }
}

.filter-inputs-stacked {
  display: flex;
  flex-direction: column;
  gap: 4px;

  input {
    width: 100%;
    padding: 6px 8px;
    border-radius: 6px;
    border: 1px solid rgba(255, 255, 255, 0.15);
    background: #0d0d0d;
    color: white;
    font-size: 12px;
    font-family: inherit;
    box-sizing: border-box;

    &::placeholder {
      color: rgba(255, 255, 255, 0.3);
    }

    &[type="number"] {
      -moz-appearance: textfield;
      appearance: textfield;

      &::-webkit-inner-spin-button,
      &::-webkit-outer-spin-button {
        -webkit-appearance: none;
        appearance: none;
        margin: 0;
      }
    }
  }
}

.filter-brands {
  display: flex;
  flex-direction: column;
  gap: 6px;
}

.filter-brands-label {
  font-size: 11px;
  color: rgba(255, 255, 255, 0.5);
}

.brand-chips {
  display: flex;
  flex-wrap: wrap;
  gap: 4px;
}

.brand-chip {
  padding: 4px 8px;
  border-radius: 8px;
  border: 1px solid rgba(255, 255, 255, 0.14);
  background: transparent;
  color: rgba(255, 255, 255, 0.75);
  font-size: 10.5px;
  font-weight: 600;
  font-family: inherit;
  cursor: pointer;

  &.active {
    background: rgba($mkt-accent, 0.22);
    border-color: $mkt-accent;
    color: $mkt-accent-soft;
  }
}

.filter-clear {
  padding: 6px 12px;
  border-radius: 8px;
  border: 1px solid rgba(255, 255, 255, 0.2);
  background: transparent;
  color: rgba(255, 255, 255, 0.6);
  font-size: 11px;
  font-weight: 600;
  font-family: inherit;
  cursor: pointer;
  align-self: flex-start;
}

.sort-panel {
  min-width: 210px;
  padding: 12px;
}

.sort-grid {
  display: grid;
  grid-template-columns: auto 1fr;
  gap: 8px 10px;
  align-items: start;
}

.sort-label {
  font-size: 11px;
  color: rgba(255, 255, 255, 0.5);
  padding-top: 6px;
}

.sort-options {
  display: grid;
  gap: 4px;
}

.sort-fields {
  grid-template-columns: repeat(3, 1fr);
}

.sort-order {
  grid-template-columns: repeat(2, 1fr);
}

.sort-opt {
  padding: 5px 8px;
  border-radius: 8px;
  border: 1px solid rgba(255, 255, 255, 0.12);
  background: transparent;
  color: rgba(255, 255, 255, 0.7);
  font-size: 10.5px;
  font-weight: 600;
  font-family: inherit;
  cursor: pointer;

  &.active {
    background: $mkt-accent;
    border-color: $mkt-accent;
    color: #0f1116;
  }
}

.feed {
  @include mkt-scrollbar;
  flex: 1;
  min-height: 0;
  overflow-y: auto;
  padding: 0 12px 12px;
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.feed-header {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
}

.feed-title {
  font-size: 13px;
  font-weight: 700;
  letter-spacing: 0.02em;
}

.feed-count {
  font-size: 10.5px;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: rgba(255, 255, 255, 0.4);
}

.feed-hint {
  margin: 4px 0;
  font-size: 12.5px;
  line-height: 1.5;
  color: rgba(255, 255, 255, 0.42);
}

.listing-card {
  flex: none;
  border-radius: 16px;
  background: rgba(23, 28, 37, 0.92);
  border: 1px solid rgba(255, 255, 255, 0.09);
  overflow: hidden;
}

.listing-photo {
  position: relative;
  display: flex;
  align-items: center;
  justify-content: center;
  width: 100%;
  aspect-ratio: 16 / 9;
  padding: 0;
  border: none;
  cursor: pointer;
  background: repeating-linear-gradient(135deg, #232a35 0, #232a35 12px, #1d232c 12px, #1d232c 24px) center / cover no-repeat;
}

.photo-placeholder {
  font-size: 10px;
  font-weight: 600;
  letter-spacing: 0.1em;
  text-transform: uppercase;
  color: rgba(255, 255, 255, 0.22);
}

.seller-chip {
  position: absolute;
  top: 9px;
  left: 9px;
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 4px 8px;
  border-radius: 9px;
  background: rgba(0, 0, 0, 0.62);
}

.seller-name {
  font-size: 10.5px;
  font-weight: 600;
  color: rgba(255, 255, 255, 0.8);
}

.listing-body {
  padding: 11px 12px 12px;
}

.listing-heading {
  display: block;
  width: 100%;
  padding: 0;
  border: none;
  background: transparent;
  color: inherit;
  font: inherit;
  text-align: left;
  cursor: pointer;
}

.listing-meta {
  display: block;
  font-size: 10.5px;
  font-weight: 600;
  color: rgba(255, 255, 255, 0.42);
}

.listing-name-row {
  display: flex;
  align-items: center;
  gap: 6px;
  margin-top: 2px;

  svg {
    flex: none;
  }
}

.listing-name {
  font-size: 15.5px;
  font-weight: 700;
  line-height: 1.25;
  overflow-wrap: break-word;
}

.listing-footer {
  display: flex;
  align-items: flex-end;
  justify-content: space-between;
  gap: 10px;
  margin-top: 11px;
}

.asking {
  min-width: 0;
}

.asking-label {
  font-size: 9.5px;
  font-weight: 600;
  letter-spacing: 0.08em;
  text-transform: uppercase;
  color: rgba(255, 255, 255, 0.4);
}

.asking-value {
  margin-top: 1px;
  font-size: 21px;
  font-weight: 800;
  line-height: 1.1;
  font-variant-numeric: tabular-nums;
}

.offer-btn {
  flex: none;
  min-height: 38px;
  padding: 9px 13px;
  border: none;
  border-radius: 10px;
  background: #7eb6ff;
  color: #0f1116;
  font: inherit;
  font-size: 12px;
  font-weight: 700;
  cursor: pointer;

  &:disabled {
    background: rgba(255, 255, 255, 0.07);
    color: rgba(255, 255, 255, 0.45);
    cursor: not-allowed;
  }
}
</style>
