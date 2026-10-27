-- Projects kind requirements into admission and progress without owning unlock rules.
local M = {}
-- Unlock flag definitions give labels as keys or {txt, context} translation objects.
local function labelText(label, translate)
  if type(label) == "table" then return translate(label.txt, label.context) end
  return translate(label)
end
-- Player Logistics XP lives on careerSkills-logistics (attribute logistics-delivery).
-- The domain path "logistics" is a short legacy card and reports the wrong level (often 1).
local DEFAULT_LOGISTICS_BRANCH = "careerSkills-logistics"

function M.evaluate(requirements, branchInfo, translate)
  local reasons = {}
  for _, requirement in ipairs(requirements or {}) do
    if requirement.unlocked == false then
      local definition = requirement.definition or {}
      local branch = requirement.branch or definition.branch or DEFAULT_LOGISTICS_BRANCH
      if branch == "logistics" then branch = DEFAULT_LOGISTICS_BRANCH end
      local info = branchInfo(branch) or {}
      local need = definition.level
      local have = tonumber(info.level) or 0
      if have < 0 then have = 0 end
      local label = definition.lockedReason and definition.lockedReason.label
        or definition.unlockInfo and definition.unlockInfo.longLabel
      local towardUnlock = (need and need > 0) and math.min(1, have / need) or nil
      reasons[#reasons + 1] = {
        kind = "level", flag = requirement.flag, branch = branch,
        label = label and labelText(label, translate) or (need and string.format("Logistics level %d required", need)
          or "Logistics level required"),
        need = need, have = have,
        progress = {level = have, current = info.curLvlProgress or 0,
          needed = info.neededForNext or 0,
          percent = towardUnlock or info.processPercent or 0},
      }
    end
  end
  table.sort(reasons, function(a, b)
    if (a.need or 0) ~= (b.need or 0) then return (a.need or 0) < (b.need or 0) end
    return tostring(a.flag or a.label) < tostring(b.flag or b.label)
  end)
  return {state = #reasons == 0 and "available" or "locked", reasons = reasons}
end
function M.apply(row, access)
  row.access = access
  row.unlocked = access.state == "available"
  local labels = {}
  for _, reason in ipairs(access.reasons) do labels[#labels + 1] = reason.label end
  row.lockedReason = #labels > 0 and table.concat(labels, "; ") or nil
  return row
end
return M
