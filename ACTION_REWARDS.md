# ServerShopFramework — direct action rewards

This patch adds actual configurable Credit grants to ServerShopFramework. It does not install an evidence-capture mod. Source review and syntax checks are complete; Palworld execution has not been tested here. Rates default to zero and the feature defaults to disabled until configured.

## What is exposed

Palladium's inspected bridge publishes player lifecycle/chat/item-use events and npc.spawn, but not the requested completed-action reward events. Its sandbox exposes UE4SS globals, so ServerShopFramework can register native callbacks itself. PalSchema supplies data/asset changes, not the required Lua action-event API. The useful entry points here are Palworld reflected UFunctions, accessed through UE4SS.

The public SDK is evidence of reflected declarations, **not proof that the installed server invokes them through UE4SS**. RegisterHook also requires each function to exist in memory. Registered callbacks and callbacks actually seen are reported separately.

| Action setting | Native callback / evidence | Grant behavior and limits |
| --- | --- | --- |
| `alpha.credits` | `PalEventNotify_Character:OnCharacterDead_ServerInternal`; `FPalDeadInfo.SelfActor/LastAttacker`; `PalStaticCharacterParameterComponent` classifiers | Credit the last attacker player, or the owning player of an attacking Pal. Require wild ownership, the database boss classification excluding rare-only Pals, and negative tower/raid/predator classification. Exact WorldBossFramework member IDs are excluded. |
| `predator.credits` | Same death callback; `IsPredatorBossPal` | Same attribution and World Boss exclusion. Predator takes precedence over Alpha, preventing two grants. |
| `tower.credits` | `PalBossBattleInstanceModel:GiftSuccessItem_OnePlayer` | Post-callback credit to the native reward recipient. `OnUpdateBossBattleState` identifies successive battles within a stage for duplicate protection. If that state hook is unavailable, conservatively pay once per player/stage instance; repeated clears of a reused stage may then be withheld. A spawned tower-species World Boss does not itself execute the native tower success distribution. |
| `raid.credits` | `PalRaidBossComponent:CallOnEnd_ToAll`, finish type `Success` | Credit players returned by native `FindInRangePlayers(..., false)` at successful completion. This is the chosen proximity policy, not a claim about damage participation. Requires dead raid individual IDs for deduplication and World Boss exclusion. Native out-array marshalling and multicast hook visibility require live validation. Empty/unreadable recipients or identities withhold the grant and log a failure. |
| `new_pal.credits` | `PalUtility:PalCaptureSuccess`; reflected `PalPlayerRecordData.PalCaptureCount.Items` (`Key`, integer `Value`) | Require count 0 before, 1 after a successful native capture. A matching `RegisterForPalDex_ToClient` first-capture receipt can also confirm it within 10 seconds. One grant per player/species. Callback timing and exact record keys need live verification; no overall capture-counter delta is substituted. |
| `capture_five.credits` | `PalNetworkPlayerComponent:ShowCaptureCompletionRelicReward_ToClient` | Credit the recipient of the game's capture-completion relic notification, once per player/species. It follows the actual notification, not modulo-five arithmetic, an item pickup, or an assumed new five-capture threshold. This is a **client RPC**: server hook registration can succeed without it firing on the dedicated server. No grant is invented if it is not observed. |
| `main_quest.credits` | `PalQuestManager:OnCompletedQuest_ServerInternal`; quest owner UID, ID, completed state and `EPalQuestType.Main` | Post-callback credit to the quest owner once per quest ID. |
| `side_quest.credits` | Same completion callback; `EPalQuestType.Sub` | Same policy. Hidden/invalid quests are excluded. Repeatable quests do not earn another payment for the same quest ID in this patch. |
| Dungeon completion | No verified reflected completion callback found | Not implemented. `PalDungeonExit.OnTriggerInteract` is an interaction request; dungeon boss death/capture is not proof of dungeon completion. Clear counters use `FThreadSafeInt32`, whose inspected declaration exposes no readable value property. No offsets or guessed replacements are used. The generator rejects nonzero dungeon rates. |

All action keys above are prefixed with `action_rewards.`. No dependency updates or inferred engine offsets are included.

## Installation and configuration

The archive contains `Mods/ServerShopFramework` (the complete preserved v1.0.0 source with the new module) and `WorldBossFramework_compat/mod.lua` plus its narrow diff. Install the Shop files in the existing ServerShopFramework mod directory. Apply the WorldBossFramework diff, or replace its mod.lua only if the baseline matches the supplied SOURCE_BASELINES.json. The compatibility change only exposes membership lookup and retains captured individual IDs after terminal cleanup. Existing spawn behavior and configuration are unchanged. No Core or shared-module replacement is necessary.

The usual live settings path for this package is `ue4ss/Mods/Palladium/mods/ServerShopFramework/settings.config`. Retain existing offers and permissions. The updated example does not overwrite this live file. In its settings portion **before any permission section**, merge settings generated on the Server Shop page, or use the following initial one-Credit trial values:

```ini
action_rewards.enabled = true
action_rewards.announce = true
action_rewards.worldboss_installed = true
action_rewards.alpha.credits = 1
action_rewards.predator.credits = 1
action_rewards.tower.credits = 1
action_rewards.raid.credits = 1
action_rewards.new_pal.credits = 1
action_rewards.capture_five.credits = 1
action_rewards.main_quest.credits = 1
action_rewards.side_quest.credits = 1
```

Use your preferred amounts, or 0 to disable an action. Only enabled nonzero actions register their hooks. Missing hooks retry registration once per minute. Set `worldboss_installed=false` only on installations without WorldBossFramework; an installed but outdated/unready membership service still blocks affected grants instead of assuming a Pal is vanilla. The old ActionRewardEvidence mod is not needed and should be removed if installed.

## Credit delivery and performance

Confirmed actions enqueue only primitive IDs, action names and amounts. A single persistent one-second game-thread timer drains up to eight grants per wake. It performs no player, Pal, or spawner scans. The persistent timer follows the existing host-compatible WorldBossFramework pattern, avoiding short-lived ExecuteInGameThread submissions. If unavailable, normal Palladium events and clock.minute drain the queue with a logged warning.

Credits are applied through ServerShopFramework's existing locked `adjust_balance` ledger. Persistent idempotency keys prevent repeated callback/receipt/retry payments for the same player/action identity. Each new successful action grant privately announces its amount and balance unless announcements are disabled. Duplicate ledger results are not announced again.

Failed balance writes retry once a minute while the process runs. The queue is bounded to 256 entries and is held in memory; unsuccessful queued grants are not durable across a restart. Queue overflow or grant failure is logged, never reported as paid. Successful ledger payments survive restarts. This patch does not change Core's `!claimrewards` summaries or reminders, player transfers, or other deferred shop-command changes.

WorldBossFramework membership history retains primitive captured IDs for the running process, including IDs reconstructed by existing encounter restoration. It deliberately survives encounter cleanup so later callbacks cannot reclassify a just-finished World Boss as a vanilla boss. It does not reconstruct arbitrary historical corpses from prior server runs.

## Live validation

There is no manual capture/probe command. An administrator can use `!shop actions` to report and log actual registration state, callback counts, eligible actions, successful grants, errors and pending grants. A registered hook with `seen=0` is not a validated route. The normal ledger also logs `source=ServerShopFramework.action` on payments.

Use one-Credit rates initially. Compare actual action receipts with balances, confirm World Boss kills do not also receive Alpha/Predator grants, repeat a tower battle to validate run separation, and confirm repeat callbacks/quests cannot pay twice. For capture completion, check that the native reward occurs and `capture_relic` actually increments on the dedicated server. If it does not, this route remains unsupported by this Lua integration until a server-executed equivalent is identified. No mocked runtime tests or live server execution were performed for this package.

## Sources

SDK inspected at commit `e6632458b97af0083eb81715775651b08104ef6a` of [localcc/PalworldModdingKit](https://github.com/localcc/PalworldModdingKit/tree/e6632458b97af0083eb81715775651b08104ef6a/Source/Pal/Public). See the accompanying source manifest for each downloaded header's SHA-256 and pinned URL. The SDK's game-version equivalence to the host build has not been established; startup hook logs and live behavior are the compatibility check.

- [Death callback declaration](https://github.com/localcc/PalworldModdingKit/blob/e6632458b97af0083eb81715775651b08104ef6a/Source/Pal/Public/PalEventNotify_Character.h)
- [Native boss classifiers](https://github.com/localcc/PalworldModdingKit/blob/e6632458b97af0083eb81715775651b08104ef6a/Source/Pal/Public/PalStaticCharacterParameterComponent.h)
- [Quest completion and type functions](https://github.com/localcc/PalworldModdingKit/blob/e6632458b97af0083eb81715775651b08104ef6a/Source/Pal/Public/PalQuestManager.h)
- [Capture-completion relic notification](https://github.com/localcc/PalworldModdingKit/blob/e6632458b97af0083eb81715775651b08104ef6a/Source/Pal/Public/PalNetworkPlayerComponent.h)
- [UE4SS RegisterHook: native pre/post parameters, loaded-function requirement, no delegate support](https://docs.ue4ss.com/dev/lua-api/global-functions/registerhook.html)
- [PalSchema data and asset loader](https://github.com/Okaetsu/PalSchema)

Only signatures and behavior inferred from their declarations are described here; no native implementation bodies were available. Installed Palladium framework.lua/main.lua, ServerShopFramework's balance ledger and WorldBossFramework's membership lifecycle were inspected directly.
