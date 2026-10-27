<!-- RLS Career Overhaul · https://github.com/RLS-Modding/rls_career_overhaul ; additional permission: licenses/RLS-BeamNG-Permission.txt
     Copyright (C) RLS Modding
     SPDX-License-Identifier: AGPL-3.0-only -->

<template>
  <div class="phone-marketplace-watches">
    <div class="page-head">
      <div>
        <h1 class="page-title">Alerts</h1>
        <p class="page-sub">Get notified when a type, brand, or model hits the Marketplace.</p>
      </div>
      <button type="button" class="add-btn" :disabled="atLimit" @click="openAdd">Add alert</button>
    </div>

    <div class="watch-list">
      <p v-if="!loaded" class="hint">Loading alerts…</p>
      <p v-else-if="!watches.length" class="hint">No alerts yet. Watch a body style, make, or model and the Marketplace app will ping you when one is listed.</p>

      <article v-for="watch in watches" :key="watch.id" class="watch-card">
        <div class="watch-info">
          <span class="watch-kind">{{ kindLabel(watch.kind) }}</span>
          <span class="watch-label">{{ watch.label }}</span>
        </div>
        <button type="button" class="remove-btn" @click="removeWatch(watch)">Remove</button>
      </article>

      <p v-if="loaded && atLimit" class="hint limit-hint">Alert limit reached ({{ limit }}). Remove one to add another.</p>
    </div>

    <PhoneMarketplaceNav active="watches" :unread-count="unreadCount" />

    <PhoneLayer v-if="addOpen" class="sheet-overlay" @click.self="closeAdd" label="Add listing alert" @close="closeAdd">
      <div class="sheet">
        <div class="sheet-head">
          <h2 class="sheet-title">Add alert</h2>
          <button type="button" class="sheet-close" @click="closeAdd">×</button>
        </div>

        <div class="kind-tabs" role="tablist" aria-label="Alert type">
          <button
            v-for="kind in kinds"
            :key="kind.id"
            type="button"
            role="tab"
            class="kind-tab"
            :class="{ active: addKind === kind.id }"
            :aria-selected="addKind === kind.id"
            @click="addKind = kind.id; optionQuery = ''"
          >{{ kind.label }}</button>
        </div>

        <input
          v-model="optionQuery"
          class="option-search"
          type="text"
          :placeholder="searchPlaceholder"
          v-bng-text-input
          @keydown.stop
          @keyup.stop
        >

        <div class="option-list">
          <p v-if="!filteredOptions.length" class="hint">{{ emptyOptionsHint }}</p>
          <button
            v-for="opt in filteredOptions"
            :key="opt.value"
            type="button"
            class="option-row"
            :class="{ selected: isWatched(addKind, opt.value) }"
            :disabled="busy || (atLimit && !isWatched(addKind, opt.value))"
            @click="toggleOption(opt)"
          >
            <span class="option-main">
              <span class="option-label">{{ opt.label }}</span>
              <span v-if="addKind === 'model' && opt.catalogType" class="option-type">{{ opt.catalogType }}</span>
            </span>
            <span class="option-state">{{ isWatched(addKind, opt.value) ? 'Watching' : 'Watch' }}</span>
          </button>
        </div>
      </div>
    </PhoneLayer>
  </div>
</template>

<script setup>
import { computed, onMounted, ref } from 'vue'
import { lua } from '@/bridge'
import { vBngTextInput } from '@/common/directives'
import PhoneLayer from '../../components/phone/PhoneLayer.vue'
import PhoneMarketplaceNav from '../../components/phone/PhoneMarketplaceNav.vue'
import { usePhoneMarketplaceUi } from '../../composables/usePhoneMarketplaceUi'
import { usePhoneMarketplaceListings } from '../../composables/usePhoneMarketplaceListings'
import { reportUiFailure } from '../../utils/safeLua'
import '../../utils/installLuaBridgeFallbacks'

usePhoneMarketplaceUi()
const { unreadCount } = usePhoneMarketplaceListings()

const kinds = [
  { id: 'type', label: 'Type' },
  { id: 'brand', label: 'Brand' },
  { id: 'model', label: 'Model' },
]

const loaded = ref(false)
const busy = ref(false)
const addOpen = ref(false)
const addKind = ref('brand')
const optionQuery = ref('')
const watches = ref([])
const options = ref({ types: [], brands: [], models: [], limit: 24 })

const limit = computed(() => Number(options.value.limit) || 24)
const atLimit = computed(() => watches.value.length >= limit.value)

const watchedKeys = computed(() => {
  const set = new Set()
  for (const watch of watches.value) set.add(`${watch.kind}:${watch.value}`)
  return set
})

const currentOptions = computed(() => {
  if (addKind.value === 'type') return options.value.types || []
  if (addKind.value === 'brand') return options.value.brands || []
  return options.value.models || []
})

const filteredOptions = computed(() => {
  const q = optionQuery.value.trim().toLowerCase()
  if (!q) return currentOptions.value
  return currentOptions.value.filter(opt =>
    String(opt.label || '').toLowerCase().includes(q)
    || String(opt.value || '').toLowerCase().includes(q)
    || String(opt.brand || '').toLowerCase().includes(q)
  )
})

const searchPlaceholder = computed(() => {
  if (addKind.value === 'type') return 'Search body styles'
  if (addKind.value === 'brand') return 'Search brands'
  return 'Search models'
})

const emptyOptionsHint = computed(() => {
  if (optionQuery.value.trim()) return 'No matches for that search.'
  if (addKind.value === 'type') return 'No body styles in current shop stock yet.'
  if (addKind.value === 'brand') return 'No brands in current shop stock yet.'
  return 'No models in current shop stock yet.'
})

function kindLabel(kind) {
  if (kind === 'type') return 'Type'
  if (kind === 'brand') return 'Brand'
  if (kind === 'model') return 'Model'
  return 'Alert'
}

function isWatched(kind, value) {
  return watchedKeys.value.has(`${kind}:${value}`)
}

async function refresh() {
  try {
    const [list, opts] = await Promise.all([
      lua.overhaul_career_market_marketplace.getListingWatches(),
      lua.overhaul_career_market_marketplace.getListingWatchOptions(),
    ])
    watches.value = Array.isArray(list) ? list : []
    options.value = opts && typeof opts === 'object'
      ? {
          types: Array.isArray(opts.types) ? opts.types : [],
          brands: Array.isArray(opts.brands) ? opts.brands : [],
          models: Array.isArray(opts.models) ? opts.models : [],
          limit: Number(opts.limit) || 24,
        }
      : { types: [], brands: [], models: [], limit: 24 }
  } catch (error) {
    reportUiFailure(error, 'marketplace listing watches')
  } finally {
    loaded.value = true
  }
}

function openAdd() {
  if (atLimit.value) return
  addKind.value = 'brand'
  optionQuery.value = ''
  addOpen.value = true
  refresh()
}

function closeAdd() {
  addOpen.value = false
}

async function toggleOption(opt) {
  if (busy.value || !opt?.value) return
  busy.value = true
  try {
    if (isWatched(addKind.value, opt.value)) {
      const existing = watches.value.find(w => w.kind === addKind.value && w.value === opt.value)
      if (existing) await lua.overhaul_career_market_marketplace.removeListingWatch(existing.id)
    } else {
      await lua.overhaul_career_market_marketplace.addListingWatch(addKind.value, opt.value, opt.label)
    }
    await refresh()
  } catch (error) {
    reportUiFailure(error, 'toggle marketplace listing watch')
  } finally {
    busy.value = false
  }
}

async function removeWatch(watch) {
  if (!watch?.id || busy.value) return
  busy.value = true
  try {
    await lua.overhaul_career_market_marketplace.removeListingWatch(watch.id)
    await refresh()
  } catch (error) {
    reportUiFailure(error, 'remove marketplace listing watch')
  } finally {
    busy.value = false
  }
}

onMounted(refresh)
</script>

<style scoped lang="scss">
@use '@/styles/rls_career_overhaul/modules/career/styles/_phone-marketplace.scss' as *;

.phone-marketplace-watches {
  display: flex;
  flex-direction: column;
  height: 100%;
  min-height: 0;
  color: #fff;
  overflow: hidden;
}

.page-head {
  flex: none;
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 10px;
  padding: 42px 12px 10px;
}

.page-title {
  margin: 0;
  font-size: 18px;
  font-weight: 800;
}

.page-sub {
  margin: 4px 0 0;
  font-size: 11.5px;
  line-height: 1.4;
  color: rgba(255, 255, 255, 0.45);
}

.add-btn {
  flex: none;
  min-height: 34px;
  padding: 7px 11px;
  border: none;
  border-radius: 9px;
  background: $mkt-accent;
  color: #0f1116;
  font: inherit;
  font-size: 11.5px;
  font-weight: 700;
  cursor: pointer;

  &:disabled {
    opacity: 0.45;
    cursor: not-allowed;
  }
}

.watch-list {
  @include mkt-scrollbar;
  flex: 1;
  min-height: 0;
  overflow-y: auto;
  padding: 0 12px 12px;
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.hint {
  margin: 4px 0;
  font-size: 12.5px;
  line-height: 1.5;
  color: rgba(255, 255, 255, 0.42);
}

.limit-hint {
  color: $mkt-warn;
}

.watch-card {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
  padding: 11px 12px;
  border-radius: 12px;
  background: $mkt-card-bg;
  border: 1px solid $mkt-card-border;
}

.watch-info {
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.watch-kind {
  font-size: 10px;
  font-weight: 700;
  letter-spacing: 0.06em;
  text-transform: uppercase;
  color: rgba(255, 255, 255, 0.4);
}

.watch-label {
  font-size: 13.5px;
  font-weight: 700;
  overflow-wrap: break-word;
}

.remove-btn {
  flex: none;
  padding: 6px 10px;
  border-radius: 8px;
  border: 1px solid rgba(255, 255, 255, 0.14);
  background: transparent;
  color: rgba(255, 255, 255, 0.65);
  font: inherit;
  font-size: 11px;
  font-weight: 600;
  cursor: pointer;
}

.sheet-overlay {
  position: absolute;
  inset: 0;
  z-index: 40;
  display: flex;
  align-items: flex-end;
  background: rgba(0, 0, 0, 0.55);
}

.sheet {
  width: 100%;
  max-height: 78%;
  display: flex;
  flex-direction: column;
  gap: 10px;
  padding: 14px 12px calc(14px + #{$mkt-bottom-inset});
  border-radius: 18px 18px 0 0;
  background: #151922;
  border: 1px solid rgba(255, 255, 255, 0.1);
  border-bottom: none;
}

.sheet-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
}

.sheet-title {
  margin: 0;
  font-size: 15px;
  font-weight: 800;
}

.sheet-close {
  width: 30px;
  height: 30px;
  border: none;
  border-radius: 8px;
  background: rgba(255, 255, 255, 0.08);
  color: #fff;
  font-size: 18px;
  line-height: 1;
  cursor: pointer;
}

.kind-tabs {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 4px;
}

.kind-tab {
  min-height: 34px;
  border: 1px solid rgba(255, 255, 255, 0.12);
  border-radius: 9px;
  background: transparent;
  color: rgba(255, 255, 255, 0.65);
  font: inherit;
  font-size: 11.5px;
  font-weight: 700;
  cursor: pointer;

  &.active {
    background: rgba($mkt-accent, 0.18);
    border-color: $mkt-accent;
    color: $mkt-accent-soft;
  }
}

.option-search {
  width: 100%;
  box-sizing: border-box;
  padding: 9px 11px;
  border-radius: 10px;
  border: 1px solid rgba(255, 255, 255, 0.12);
  background: rgba(255, 255, 255, 0.05);
  color: #fff;
  font: inherit;
  font-size: 12.5px;

  &::placeholder {
    color: rgba(255, 255, 255, 0.35);
  }
}

.option-list {
  @include mkt-scrollbar;
  flex: 1;
  min-height: 160px;
  max-height: 42vh;
  overflow-y: auto;
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.option-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  width: 100%;
  padding: 10px 11px;
  border-radius: 10px;
  border: 1px solid rgba(255, 255, 255, 0.08);
  background: rgba(255, 255, 255, 0.03);
  color: #fff;
  font: inherit;
  text-align: left;
  cursor: pointer;

  &.selected {
    border-color: rgba($mkt-accent, 0.55);
    background: rgba($mkt-accent, 0.12);
  }

  &:disabled {
    opacity: 0.45;
    cursor: not-allowed;
  }
}

.option-main {
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.option-label {
  font-size: 12.5px;
  font-weight: 650;
}

.option-type {
  font-size: 10px;
  font-weight: 600;
  color: rgba(255, 255, 255, 0.4);
}

.option-state {
  flex: none;
  font-size: 10.5px;
  font-weight: 700;
  color: rgba(255, 255, 255, 0.45);
}

.option-row.selected .option-state {
  color: $mkt-accent-soft;
}
</style>
