// RLS Career Overhaul · https://github.com/RLS-Modding/rls_career_overhaul ; additional permission: licenses/RLS-BeamNG-Permission.txt
// Copyright (C) RLS Modding
// SPDX-License-Identifier: AGPL-3.0-only

import { onBeforeUnmount, watch } from "vue"
import { lua } from "@/bridge"
import { openOverhaulPopup } from "../../utils/openOverhaulPopup.js"
import { safeLua } from "../../utils/safeLua.js"

// Bank amount popups mount outside the phone shell, so shell focus listeners never see them.
// Hold CEF typing for the whole popup so number keys go into the form, not camera binds.
function setTyping(on) {
  safeLua(() => lua.setCEFTyping(!!on), on ? "bank popup typing on" : "bank popup typing off")
}

// Keep the bank's public show/event API while stock popups own maps and focus.
export function useBankPopup(view, props, emit, successEvent) {
  let current = null
  const stop = watch(() => props.show, show => {
    if (!show) {
      const closing = current
      current = null
      closing?.return(false)
      setTyping(false)
      return
    }
    if (current) return
    const host = document.activeElement?.closest?.('.phone-bank-root, .phone-bank-account-root')
    const rect = host?.getBoundingClientRect()
    const appearance = host ? getComputedStyle(host) : null
    setTyping(true)
    const popup = openOverhaulPopup(view, { ...props }, {
      localBackdrop: true,
      ...(rect ? {
        style: {
          fontFamily: appearance.fontFamily, fontSize: appearance.fontSize, lineHeight: appearance.lineHeight,
          position: 'fixed', left: `${rect.left}px`, top: `${rect.top}px`,
          width: `${rect.width}px`, height: `${rect.height}px`,
        },
      } : {}),
    })
    current = popup
    popup.promise.then(result => {
      if (current !== popup) return
      current = null
      setTyping(false)
      if (result === true) emit(successEvent)
      emit("close")
    })
  }, { immediate: true })
  onBeforeUnmount(() => {
    stop()
    const closing = current
    current = null
    closing?.return(false)
    setTyping(false)
  })
}
