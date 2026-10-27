// RLS Career Overhaul · https://github.com/RLS-Modding/rls_career_overhaul ; additional permission: licenses/RLS-BeamNG-Permission.txt
// Copyright (C) RLS Modding
// SPDX-License-Identifier: AGPL-3.0-only

import { computed, reactive, ref } from 'vue'

const MILES_TO_METERS = 1609.344

export function askingPrice(vehicle) {
  return Number(vehicle?.valueAdjusted || vehicle?.Value || 0) || 0
}

function numOrEmpty(value) {
  if (value == null || value === '') return null
  const n = Number(value)
  return Number.isFinite(n) ? n : null
}

function isNegotiable(vehicle) {
  return vehicle?.negotiationPossible !== false && !(Number(vehicle?.discountPercentage) > 0)
}

/**
 * Filter + sort for the phone Marketplace buy feed (private listings only).
 * Caller owns the raw listing list and player balance.
 */
export function usePhoneMarketplaceFilters({ listings, playerBalance, searchQuery }) {
  const filterForm = reactive({
    affordable: false,
    negotiable: false,
    underMarket: false,
    priceMin: null,
    priceMax: null,
    yearMin: null,
    yearMax: null,
    mileageMaxMi: null,
    brands: [],
  })
  const sortBy = ref('price')
  const sortAsc = ref(true)
  const sortFields = [
    { key: 'price', label: 'Price' },
    { key: 'year', label: 'Year' },
    { key: 'mileage', label: 'Mileage' },
    { key: 'deal', label: 'Deal' },
    { key: 'name', label: 'Name' },
    { key: 'distance', label: 'Distance' },
  ]

  const brandOptions = computed(() => {
    const counts = new Map()
    for (const v of listings.value || []) {
      const brand = String(v.Brand || '').trim()
      if (!brand) continue
      counts.set(brand, (counts.get(brand) || 0) + 1)
    }
    return [...counts.entries()]
      .sort((a, b) => a[0].localeCompare(b[0]))
      .map(([brand, count]) => ({ brand, count }))
  })

  const filterCount = computed(() => {
    const f = filterForm
    let n = 0
    if (f.affordable) n++
    if (f.negotiable) n++
    if (f.underMarket) n++
    if (numOrEmpty(f.priceMin) != null) n++
    if (numOrEmpty(f.priceMax) != null) n++
    if (numOrEmpty(f.yearMin) != null) n++
    if (numOrEmpty(f.yearMax) != null) n++
    if (numOrEmpty(f.mileageMaxMi) != null) n++
    if (f.brands.length) n++
    return n
  })

  const filteredListings = computed(() => {
    const balance = Number(playerBalance.value) || 0
    const query = String(searchQuery.value || '').trim().toLowerCase()
    const f = filterForm
    const priceMin = numOrEmpty(f.priceMin)
    const priceMax = numOrEmpty(f.priceMax)
    const yearMin = numOrEmpty(f.yearMin)
    const yearMax = numOrEmpty(f.yearMax)
    const mileageMaxM = numOrEmpty(f.mileageMaxMi) != null ? numOrEmpty(f.mileageMaxMi) * MILES_TO_METERS : null
    const brandSet = f.brands.length ? new Set(f.brands.map(String)) : null

    let list = (listings.value || []).filter(v => {
      const asking = askingPrice(v)
      if (f.affordable && asking > balance) return false
      if (f.negotiable && !isNegotiable(v)) return false
      if (f.underMarket) {
        const market = Number(v.marketValue)
        if (!(Number.isFinite(market) && market > 0 && asking <= market)) return false
      }
      if (priceMin != null && asking < priceMin) return false
      if (priceMax != null && asking > priceMax) return false
      const year = Number(v.year)
      if (yearMin != null && !(Number.isFinite(year) && year >= yearMin)) return false
      if (yearMax != null && !(Number.isFinite(year) && year <= yearMax)) return false
      if (mileageMaxM != null) {
        const miles = Number(v.Mileage)
        if (!(Number.isFinite(miles) && miles <= mileageMaxM)) return false
      }
      if (brandSet && !brandSet.has(String(v.Brand || '').trim())) return false
      if (query) {
        const hay = [v.Name, v.Brand, v.sellerName, v.year, v.niceName]
        if (!hay.some(field => field != null && String(field).toLowerCase().includes(query))) return false
      }
      return true
    })

    const key = sortBy.value
    const asc = sortAsc.value
    const dir = asc ? 1 : -1
    list = [...list].sort((a, b) => {
      let va
      let vb
      if (key === 'price') {
        va = askingPrice(a)
        vb = askingPrice(b)
      } else if (key === 'year') {
        va = Number(a.year)
        vb = Number(b.year)
      } else if (key === 'mileage') {
        va = Number(a.Mileage)
        vb = Number(b.Mileage)
      } else if (key === 'deal') {
        // Asking / market; lower is a better buy. Missing market sorts last.
        const ma = Number(a.marketValue)
        const mb = Number(b.marketValue)
        va = Number.isFinite(ma) && ma > 0 ? askingPrice(a) / ma : Number.POSITIVE_INFINITY
        vb = Number.isFinite(mb) && mb > 0 ? askingPrice(b) / mb : Number.POSITIVE_INFINITY
      } else if (key === 'name') {
        const na = [a.Brand, a.Name].filter(Boolean).join(' ').toLowerCase()
        const nb = [b.Brand, b.Name].filter(Boolean).join(' ').toLowerCase()
        if (na < nb) return -1 * dir
        if (na > nb) return 1 * dir
        return 0
      } else if (key === 'distance') {
        const da = Number(a.distance)
        const db = Number(b.distance)
        va = Number.isFinite(da) && da >= 0 ? da : Number.POSITIVE_INFINITY
        vb = Number.isFinite(db) && db >= 0 ? db : Number.POSITIVE_INFINITY
      } else {
        va = askingPrice(a)
        vb = askingPrice(b)
      }
      if (!Number.isFinite(va)) va = asc ? Number.POSITIVE_INFINITY : Number.NEGATIVE_INFINITY
      if (!Number.isFinite(vb)) vb = asc ? Number.POSITIVE_INFINITY : Number.NEGATIVE_INFINITY
      if (va < vb) return -1 * dir
      if (va > vb) return 1 * dir
      return 0
    })
    return list
  })

  function toggleBrand(brand) {
    const name = String(brand || '').trim()
    if (!name) return
    const i = filterForm.brands.indexOf(name)
    if (i >= 0) filterForm.brands.splice(i, 1)
    else filterForm.brands.push(name)
  }

  function clearFilters() {
    filterForm.affordable = false
    filterForm.negotiable = false
    filterForm.underMarket = false
    filterForm.priceMin = null
    filterForm.priceMax = null
    filterForm.yearMin = null
    filterForm.yearMax = null
    filterForm.mileageMaxMi = null
    filterForm.brands = []
  }

  return {
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
    isNegotiable,
  }
}
