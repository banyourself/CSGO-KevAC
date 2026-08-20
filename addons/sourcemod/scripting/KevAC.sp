#include <sourcemod>
#include <sdktools>
#include <sdktools_entoutput>
#include <sdkhooks>
#include <clientprefs>
#include <colors>
#include <kevac>
#tryinclude <movementapi>

#undef REQUIRE_PLUGIN
#tryinclude <sourcebanspp>
#tryinclude <shavit>

#undef REQUIRE_EXTENSIONS
#tryinclude <dhooks>
#tryinclude <PhysHooks>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo =
{
	name = "KevAC",
	author = "Kevin, JDW1337, Wend4r, Blacky, shavitush, J-Tanzanite, zwolof",
	version = "2.8.0",
	url = ""
};

enum
{
	NONE = 0,
	KICK,
	BAN,
	SBBAN
}

// The outcome profile is deliberately much larger than the short raw-input
// sequences that a physical mouse wheel can produce on a 128-tick server.
#define KEVAC_SCROLL_PROFILE_MAX 64

// ---- Core config ----
bool  status;
int   method, blocking_time, iNotification;
int   bd_listener_update_action, bd_listener_update_grace, bd_listener_update_threshold;
int   bd_preban_delay, bd_preban_preroll;
int   bd_listener_maxsubs, bd_listener_maxsubs_action;
int   bd_listener_consensus_min;
int   bd_listener_consensus_pct;
int   bd_fullupdate_action, bd_fullupdate_threshold;
float bd_fullupdate_window;
#define KEVAC_WL_LEN 192   // "STEAM_1:0:1234567890 Det1,Det2,Det3"
ArrayList hWhiteList;

// ---- Detection state (extension listener path) ----
bool  bDetect[MAXPLAYERS + 1];
float g_clientJoinTime[MAXPLAYERS + 1];
int   g_listenerUpdateCount[MAXPLAYERS + 1];
int   g_listenerActiveSubscriptions[MAXPLAYERS + 1];
int   g_listenerBlacklistedSubscriptions[MAXPLAYERS + 1];
char  g_listenerBlacklistedEventNames[MAXPLAYERS + 1][192];
int   g_listenerPeakSubscriptions[MAXPLAYERS + 1];
int   g_listenerMaskFingerprint[MAXPLAYERS + 1];
int   g_listenerMaskOutlierFingerprint[MAXPLAYERS + 1];
int   g_listenerAuditLoggedFingerprint[MAXPLAYERS + 1];
bool  g_listenerOversubFlagged[MAXPLAYERS + 1];
bool  g_listenerBlacklistFlagged[MAXPLAYERS + 1];
bool  g_punishmentDispatched[MAXPLAYERS + 1];
bool  g_listenerTelemetrySeen[MAXPLAYERS + 1];
bool  g_listenerHookEarly[MAXPLAYERS + 1]; // vhook attached during this client's signon
int   g_listenerRawCallbacks;
int   g_listenerHumanCallbacks;

// ---- Full-update telemetry (PTaH-verified CGameClient vtable index) ----
int   g_fullUpdateHookId[MAXPLAYERS + 1];
Address g_fullUpdateClientPtr[MAXPLAYERS + 1];
int   g_fullUpdateCalls[MAXPLAYERS + 1];
int   g_fullUpdateRequests[MAXPLAYERS + 1];
float g_fullUpdateWindowStart[MAXPLAYERS + 1];

// Raw client vtable hooks are deliberately held behind a build-validation
// gate. A previously inferred ProcessListenEvents slot crashed this server
// when a player joined, so it is not a valid route for this CS:GO build.
int   g_listenerMessageHookId[MAXPLAYERS + 1];
Address g_listenerMessageHandlerPtr[MAXPLAYERS + 1];

// ---- Behavioral config (cached from ConVars; detectors read these plain vars) ----
bool  bd_enable, bd_admin_immune;
bool  bd_vtable_hooks;   // user-requested vtable telemetry. It remains blocked until this exact build is validated.
bool  g_vtableHooksBlocked;
int   bd_bhop_ratio_action, bd_bhop_ratio_window, bd_bhop_ratio_pct;
int   bd_ghostjump_action;
int   bd_ghost_action, bd_ghost_tol, bd_ghost_streak;
int   bd_synthmove_action, bd_synthmove_min_ticks;
float bd_synthmove_tol;
int   bd_tick_action, bd_tick_regress, bd_tick_streak, bd_tick_tolerance, bd_tick_min_old;
bool  bd_tick_patch;
int   bd_bhop_action, bd_bhop_maxground, bd_bhop_streak;
int   bd_scroll_action, bd_scroll_sample, bd_scroll_maxjitter;
int   bd_scroll_pattern_action, bd_scroll_pattern_repeats, bd_scroll_pattern_jitter, bd_scroll_pattern_maxinterval;
int   bd_scroll_profile_window, bd_scroll_profile_perfect_pct, bd_scroll_profile_min_presses, bd_scroll_profile_press_pct, bd_scroll_profile_same_pairs, bd_scroll_profile_cadence_bursts;
float bd_scroll_profile_minspeed;
int   bd_duckmacro_action, bd_duckmacro_repeats, bd_duckmacro_jitter, bd_duckmacro_maxinterval, bd_duckmacro_outcomes, bd_duckmacro_window;
int   bd_duckmacro_input_action, bd_duckmacro_input_bursts;
// Shared by the +duck and +jump cadence paths: a free-spinning wheel is the
// same hardware whichever button it drives.
int   bd_hyperscroll_action;
float bd_duckmacro_input_minspeed;
int   bd_jumpbug_action, bd_jumpbug_streak, bd_jumpbug_chain, bd_jumpbug_maxgap;
float bd_jumpbug_minfall;
int   bd_jumpbug_timing_action, bd_jumpbug_timing_repeats, bd_jumpbug_timing_jitter, bd_jumpbug_timing_maxduck;
int   bd_groundjumpbug_action, bd_groundjumpbug_streak, bd_groundjumpbug_maxgap, bd_groundjumpbug_chain;
float bd_groundjumpbug_minspeed, bd_groundjumpbug_minside, bd_groundjumpbug_speedloss;
int   bd_groundjumpbug_timing_action;
int   bd_ahk_action, bd_ahk_streak;
float bd_ahk_maxnet;
int   bd_silent_action, bd_silent_streak;
int   bd_knife_action, bd_knife_reaction_ms, bd_knife_streak;
float bd_knife_range, bd_knife_cone;
int   bd_latency_action, bd_latency_cmdrate, bd_latency_observe;
int   bd_fakelag_action, bd_fakelag_burst, bd_fakelag_hits, bd_fakelag_seconds, bd_fakelag_observe;
int   bd_angle_action, bd_angle_roll_action, bd_angle_streak;
bool  bd_angle_patch;
float bd_angle_window;
int   bd_pattern_action, bd_pattern_minticks, bd_pattern_repeats, bd_pattern_minmouse;
int   bd_cheatvar_action, bd_cvarprobe_action;
int   bd_usercmd_action, bd_antiduck_action;
int   bd_future_ticks;
int   bd_lerp_action;
float bd_lerp_min_ms, bd_lerp_max_ms;
int   bd_mouseyaw_action, bd_mouseyaw_streak;
float bd_mouseyaw_tol;
int   bd_aimbot_action, bd_aimbot_delta, bd_aimbot_streak;
int   bd_trigger_action, bd_trigger_streak;
int   bd_psilent_action, bd_psilent_streak, bd_psilent_chain;
float bd_psilent_delta;

// ConVar handles (one per setting; all share OnAnyCvarChanged -> RefreshConfig)
ConVar gcv_enable, gcv_method, gcv_listener_update, gcv_listener_update_grace, gcv_listener_update_threshold, gcv_bantime, gcv_preban_delay, gcv_preban_preroll, gcv_notify, gcv_bd_enable, gcv_log, gcv_admin_immune;
ConVar gcv_banwave, gcv_banwave_exempt;
ConVar gcv_listener_maxsubs, gcv_listener_maxsubs_action, gcv_listener_consensus_min, gcv_listener_consensus_pct, gcv_listener_audit_log;
ConVar gcv_vtable_hooks;
ConVar gcv_bhop_ratio, gcv_bhop_ratio_window, gcv_bhop_ratio_pct;
ConVar gcv_fullupdate_action, gcv_fullupdate_threshold, gcv_fullupdate_window;
ConVar gcv_ghostjump, gcv_ghost, gcv_ghost_tol, gcv_ghost_streak;
ConVar gcv_synth, gcv_synth_ticks, gcv_synth_tol;
ConVar gcv_tick, gcv_tick_regress, gcv_tick_streak, gcv_tick_patch, gcv_tick_tolerance, gcv_tick_min_old;
ConVar gcv_bhop, gcv_bhop_ground, gcv_bhop_streak;
ConVar gcv_scroll, gcv_scroll_sample, gcv_scroll_jitter, gcv_scroll_pattern, gcv_scroll_pattern_repeats, gcv_scroll_pattern_jitter, gcv_scroll_pattern_maxinterval;
ConVar gcv_scroll_profile_window, gcv_scroll_profile_perfect_pct, gcv_scroll_profile_min_presses, gcv_scroll_profile_press_pct, gcv_scroll_profile_same_pairs, gcv_scroll_profile_cadence_bursts, gcv_scroll_profile_minspeed;
ConVar gcv_duckmacro, gcv_duckmacro_repeats, gcv_duckmacro_jitter, gcv_duckmacro_maxinterval, gcv_duckmacro_outcomes, gcv_duckmacro_window;
ConVar gcv_duckmacro_input, gcv_duckmacro_input_bursts, gcv_duckmacro_input_minspeed, gcv_hyperscroll;
ConVar gcv_jumpbug, gcv_jumpbug_streak, gcv_jumpbug_chain, gcv_jumpbug_maxgap, gcv_jumpbug_minfall, gcv_jumpbug_timing, gcv_jumpbug_timing_repeats, gcv_jumpbug_timing_jitter, gcv_jumpbug_timing_maxduck;
ConVar gcv_groundjumpbug, gcv_groundjumpbug_streak, gcv_groundjumpbug_maxgap, gcv_groundjumpbug_chain, gcv_groundjumpbug_minspeed, gcv_groundjumpbug_minside, gcv_groundjumpbug_speedloss, gcv_groundjumpbug_timing;
ConVar gcv_ahk, gcv_ahk_streak, gcv_ahk_maxnet;
ConVar gcv_silent, gcv_silent_streak;
ConVar gcv_knife, gcv_knife_range, gcv_knife_cone, gcv_knife_ms, gcv_knife_streak;
ConVar gcv_latency, gcv_latency_rate, gcv_latency_observe;
ConVar gcv_fakelag, gcv_fakelag_burst, gcv_fakelag_hits, gcv_fakelag_seconds, gcv_fakelag_observe;
ConVar gcv_angle, gcv_angle_roll, gcv_angle_streak, gcv_angle_window, gcv_angle_patch;
ConVar gcv_pattern, gcv_pattern_ticks, gcv_pattern_repeats, gcv_pattern_mouse;
ConVar gcv_cheatvar, gcv_cvarprobe;
ConVar gcv_usercmd, gcv_antiduck, gcv_futureticks, gcv_lerp, gcv_lerp_min, gcv_lerp_max;
ConVar gcv_mouseyaw, gcv_mouseyaw_streak, gcv_mouseyaw_tol;
ConVar gcv_aimbot, gcv_aimbot_delta, gcv_aimbot_streak;
ConVar gcv_trigger, gcv_trigger_streak;
ConVar gcv_psilent, gcv_psilent_delta, gcv_psilent_streak, gcv_psilent_chain;
ConVar gcv_strafe, gcv_strafe_devban, gcv_strafe_identical;
ConVar gcv_gain, gcv_gain_spjban;
ConVar gcv_illegalmove, gcv_illegalmove_zero;
ConVar gcv_cmdrate;


// Extended cheat-cvar probe list (name -> required value), loaded from a file.
ArrayList g_cheatCvarNames;
ArrayList g_cheatCvarValues;
ArrayList g_convarImmune;   // SteamIDs exempt from the sv_cheats / cheat-convar checks

// ---- Cached client cvars ----
int   g_fwdSpeed[MAXPLAYERS + 1];
int   g_sideSpeed[MAXPLAYERS + 1];
float g_mSide[MAXPLAYERS + 1];
float g_mForward[MAXPLAYERS + 1];
float g_mPitch[MAXPLAYERS + 1];
float g_sens[MAXPLAYERS + 1];
float g_myaw[MAXPLAYERS + 1];
int   g_mouseyawStreak[MAXPLAYERS + 1];
ConVar g_cvServerAutoBhop, g_cvAllowWait, g_cvMaxUsercmdFutureTicks, g_cvSvCheats;

// ---- Per-tick state ----
int   g_lastButtons[MAXPLAYERS + 1];
bool  g_wasOnGround[MAXPLAYERS + 1];
int   g_viewStillTicks[MAXPLAYERS + 1];     // consecutive ticks with frozen yaw+pitch
int   g_lastMouseActiveTick[MAXPLAYERS + 1]; // last tick with a nonzero usercmd mouse delta

// PhysHooks lets the ghost-jump check inspect the result after player physics,
// instead of inferring a launch from the next received usercmd.
bool  g_bPhysHooks;
bool  g_physicsPending[MAXPLAYERS + 1];
int   g_physicsSnapshotTick[MAXPLAYERS + 1];
int   g_physicsSnapshotButtons[MAXPLAYERS + 1];
bool  g_physicsSnapshotPrevJump[MAXPLAYERS + 1];

// ghost strafe / synthmove
int   g_ghostTicks[MAXPLAYERS + 1];
int   g_synthTicks[MAXPLAYERS + 1];

// Generic grace window after a spawn, teleport, or trigger movement. It does
// not modify client commands or participate in lag compensation.
float g_teleportGraceUntil[MAXPLAYERS + 1];
float g_usercmdLastFlag[MAXPLAYERS + 1];
float g_lerpLastFlag[MAXPLAYERS + 1];

// Backtrack command-tick state. This path is opt-in because packet recovery
// can legitimately create discontinuities on high-latency movement servers.
int   g_lastTick[MAXPLAYERS + 1];
int   g_tickStreak[MAXPLAYERS + 1];
int   g_tickLastServerTick[MAXPLAYERS + 1];
int   g_backtrackPrevTick[MAXPLAYERS + 1];
int   g_backtrackRawTick[MAXPLAYERS + 1];
int   g_backtrackPatchStreak[MAXPLAYERS + 1];
int   g_backtrackPatchLastServerTick[MAXPLAYERS + 1];

// bhop / scroll
int   g_groundTicks[MAXPLAYERS + 1];
int   g_perfectStreak[MAXPLAYERS + 1];
int   g_lastJumpTick[MAXPLAYERS + 1];
int   g_jumpDeltas[MAXPLAYERS + 1][32];
int   g_jumpDeltaCount[MAXPLAYERS + 1];
int   g_scrollPatternMin[MAXPLAYERS + 1];
int   g_scrollPatternMax[MAXPLAYERS + 1];
int   g_scrollPatternRepeats[MAXPLAYERS + 1];
int   g_scrollCadenceBursts[MAXPLAYERS + 1];
// Share of the above that needed the jitter tolerance. See AddScrollCadenceEvidence.
int   g_scrollJitteredBursts[MAXPLAYERS + 1];
int   g_scrollProfileCount[MAXPLAYERS + 1];
int   g_scrollProfilePresses[MAXPLAYERS + 1][KEVAC_SCROLL_PROFILE_MAX];
int   g_scrollProfilePerfect[MAXPLAYERS + 1][KEVAC_SCROLL_PROFILE_MAX];
int   g_lastDuckTick[MAXPLAYERS + 1];
int   g_duckPatternMin[MAXPLAYERS + 1];
int   g_duckPatternMax[MAXPLAYERS + 1];
int   g_duckPatternRepeats[MAXPLAYERS + 1];
int   g_duckCadenceBursts[MAXPLAYERS + 1];
int   g_duckCadenceLastTick[MAXPLAYERS + 1];
int   g_duckMouseStrafeBursts[MAXPLAYERS + 1];
// Bursts that only held together because of the jitter tolerance. A coasting
// wheel drifts; machine timing repeats the same interval exactly.
int   g_duckJitteredBursts[MAXPLAYERS + 1];
int   g_duckMacroOutcomes[MAXPLAYERS + 1];
int   g_duckMacroOutcomeLastTick[MAXPLAYERS + 1];
bool  g_jumpBugArmed[MAXPLAYERS + 1];
int   g_jumpBugArmTick[MAXPLAYERS + 1];
float g_jumpBugFallSpeed[MAXPLAYERS + 1];
int   g_jumpBugStreak[MAXPLAYERS + 1];
int   g_jumpBugLastTick[MAXPLAYERS + 1];
int   g_duckAirTicks[MAXPLAYERS + 1];
int   g_jumpBugDuckPressTick[MAXPLAYERS + 1];
int   g_jumpBugArmDuckToJump[MAXPLAYERS + 1];
int   g_jumpBugTimingLastDelay[MAXPLAYERS + 1];
int   g_jumpBugTimingStreak[MAXPLAYERS + 1];
bool  g_groundJumpBugArmed[MAXPLAYERS + 1];
int   g_groundJumpBugArmTick[MAXPLAYERS + 1];
float g_groundJumpBugArmSpeed[MAXPLAYERS + 1];
int   g_groundJumpBugStreak[MAXPLAYERS + 1];
int   g_groundJumpBugLastTick[MAXPLAYERS + 1];
int   g_groundJumpBugDuckPressTick[MAXPLAYERS + 1];
int   g_groundJumpBugArmDuckToJump[MAXPLAYERS + 1];
int   g_gjbTimingLastDelay[MAXPLAYERS + 1];
int   g_gjbTimingStreak[MAXPLAYERS + 1];

// Server plugins that deliberately alter a player's origin or velocity can ask
// KevAC to ignore only the resulting movement-state checks for a few ticks.
int   g_movementIgnoreUntil[MAXPLAYERS + 1];

bool  g_showAlerts[MAXPLAYERS + 1];

// ahk strafe (repeated identical mouse deltas mid-air)
int   g_lastMouseDx[MAXPLAYERS + 1];
int   g_ahkStreak[MAXPLAYERS + 1];
int   g_prevMouseDx2[MAXPLAYERS + 1];
int   g_ahkAltStreak[MAXPLAYERS + 1];

// scripted-bhop perfect-jump ratio window (catches humanized autobhop that
// deliberately misses hops to defeat the consecutive-streak detector)
int   g_bhopWindowJumps[MAXPLAYERS + 1];
int   g_bhopWindowPerfect[MAXPLAYERS + 1];

// cheat-cvar probe round accounting (selective query-block telemetry)
int   g_probeSentRound[MAXPLAYERS + 1];
int   g_probeAnsweredRound[MAXPLAYERS + 1];
int   g_probeSilentRounds[MAXPLAYERS + 1];
bool  g_probeBlockFlagged[MAXPLAYERS + 1];

// silent strafe (sidemove sign flips)
float g_lastSide[MAXPLAYERS + 1];
int   g_silentStreak[MAXPLAYERS + 1];

// knifebot
int   g_stabAvailSince[MAXPLAYERS + 1];
int   g_knifeStreak[MAXPLAYERS + 1];

// macro input-pattern (per air-phase signature)
bool  g_inAir[MAXPLAYERS + 1];
int   g_phaseTicks[MAXPLAYERS + 1];
int   g_phaseHash[MAXPLAYERS + 1];
int   g_phaseCheck[MAXPLAYERS + 1];
int   g_phaseMouse[MAXPLAYERS + 1];
int   g_prevPhaseHash[MAXPLAYERS + 1];
int   g_prevPhaseCheck[MAXPLAYERS + 1];
int   g_patternRepeat[MAXPLAYERS + 1];

// aimbot / triggerbot (from ofl)
float g_prevAngles[MAXPLAYERS + 1][3];
float g_cmdAngleHistory[MAXPLAYERS + 1][2][3];
int   g_cmdNumberHistory[MAXPLAYERS + 1][2];
int   g_cmdButtonHistory[MAXPLAYERS + 1][2];
int   g_aimbotStreak[MAXPLAYERS + 1];
int   g_lastHitGroup[MAXPLAYERS + 1];
int   g_onTargetTicks[MAXPLAYERS + 1];
int   g_prevOnTargetTicks[MAXPLAYERS + 1];
int   g_triggerStreak[MAXPLAYERS + 1];
int   g_psilentStreak[MAXPLAYERS + 1];
int   g_psilentLastTick[MAXPLAYERS + 1];

// knifebot spam guard / chain window
int   g_lastAttackEdgeTick[MAXPLAYERS + 1];
int   g_knifeLastFastTick[MAXPLAYERS + 1];

// scripted-bhop clean-press tracking (capture-validated: DLLs press +jump once on
// the landing tick; human scrollers spam airborne +jump edges between hops)
int   g_airJumpPresses[MAXPLAYERS + 1];

// Angle-clamp strike windows. Pitch and roll are intentionally separated: a
// movement plugin can author a roll during a spawn or view repair, while an
// out-of-range client pitch remains a protocol violation.
int   g_angleFlagCount[MAXPLAYERS + 1];
float g_angleFlagWindow[MAXPLAYERS + 1];
int   g_angleRollFlagCount[MAXPLAYERS + 1];
float g_angleRollFlagWindow[MAXPLAYERS + 1];

// mouse-yaw window counters + settings retest
int   g_mouseyawWindowTicks[MAXPLAYERS + 1];
int   g_mouseyawBadTicks[MAXPLAYERS + 1];
float g_mouseyawRetestUntil[MAXPLAYERS + 1];

// extended mouse pipeline cache (-1 = unknown until queried)
int   g_mRawInput[MAXPLAYERS + 1];
int   g_mFilter[MAXPLAYERS + 1];
int   g_mCustomAccel[MAXPLAYERS + 1];
int   g_mJoystick[MAXPLAYERS + 1];
int   g_mMouseLook[MAXPLAYERS + 1];
int   g_sensChanges[MAXPLAYERS + 1];

// ---- BASH2 ports (Blacky's Anti-Strafehack, shavit-bash2) ----
#define KEVAC_BASH_FRAMES 50
int   bd_strafe_action, bd_strafe_identical;
float bd_strafe_dev_ban;
int   bd_gain_action;
float bd_gain_spj_ban;
int   bd_illegalmove_action;
bool  bd_illegalmove_zero;
int   bd_cmdrate_action;

// strafe timing statistics (turn <-> keypress sync)
int   g_bashCmdNum[MAXPLAYERS + 1];
float g_bashYawDiff[MAXPLAYERS + 1];
int   g_bashPressTick[MAXPLAYERS + 1][4];      // 0 W, 1 S, 2 A, 3 D
int   g_bashReleaseTick[MAXPLAYERS + 1][4];
int   g_bashPressRecorded[MAXPLAYERS + 1][4];
int   g_bashReleaseRecorded[MAXPLAYERS + 1][4];
int   g_bashTurnDir[MAXPLAYERS + 1];           // 0 left, 1 right
int   g_bashTurnTick[MAXPLAYERS + 1];
int   g_bashStopTurnTick[MAXPLAYERS + 1];
bool  g_bashIsTurning[MAXPLAYERS + 1];
int   g_bashTurnRecStart[MAXPLAYERS + 1];
int   g_bashTurnRecEnd[MAXPLAYERS + 1];
int   g_bashStartDiff[MAXPLAYERS + 1][KEVAC_BASH_FRAMES];
int   g_bashStartFrame[MAXPLAYERS + 1];
int   g_bashStartFilled[MAXPLAYERS + 1];
int   g_bashStartLastDiff[MAXPLAYERS + 1];
int   g_bashStartIdentical[MAXPLAYERS + 1];
int   g_bashStartRecTick[MAXPLAYERS + 1];
int   g_bashEndDiff[MAXPLAYERS + 1][KEVAC_BASH_FRAMES];
int   g_bashEndFrame[MAXPLAYERS + 1];
int   g_bashEndFilled[MAXPLAYERS + 1];
int   g_bashEndLastDiff[MAXPLAYERS + 1];
int   g_bashEndIdentical[MAXPLAYERS + 1];
int   g_bashEndRecTick[MAXPLAYERS + 1];

// air-gain / strafes-per-jump statistics (bash2 gainlog)
int   g_gainJumps[MAXPLAYERS + 1];
float g_gainRaw[MAXPLAYERS + 1];
int   g_gainStrafeTicks[MAXPLAYERS + 1];
int   g_gainYawTicks[MAXPLAYERS + 1];
int   g_gainStrafes[MAXPLAYERS + 1];
int   g_gainGroundTicks[MAXPLAYERS + 1];
bool  g_gainFirstSix[MAXPLAYERS + 1];
bool  g_touchWall[MAXPLAYERS + 1];
bool  g_touchRotating[MAXPLAYERS + 1];
float g_lastGainPct[MAXPLAYERS + 1];
float g_lastSpj[MAXPLAYERS + 1];

// illegal sidemove / button-move mismatch (bash2)
int   g_invalidBtnMove[MAXPLAYERS + 1];
int   g_lastInvalidBtnMove[MAXPLAYERS + 1];
int   g_invalidReason[MAXPLAYERS + 1];
int   g_illegalSidemove[MAXPLAYERS + 1];
int   g_lastIllegalSidemove[MAXPLAYERS + 1];
int   g_illegalYawChanges[MAXPLAYERS + 1];

// usercmd rate monitor (speedhack / lag-switch, bash2)
int   g_cmdCount[MAXPLAYERS + 1];
int   g_cmdBadSeconds[MAXPLAYERS + 1];
float g_cmdWindowStart[MAXPLAYERS + 1];

// Fake-lag (withheld-then-bursted usercmds) state. See Detect_FakeLag.
int   g_flLastCmdnum[MAXPLAYERS + 1];   // previous cmdnum, for gap detection
int   g_flMissing[MAXPLAYERS + 1];      // usercmds that never arrived this window (real loss)
int   g_flLastTick[MAXPLAYERS + 1];     // server tick the previous cmd was processed on
int   g_flThisTickRun[MAXPLAYERS + 1];  // cmds processed on g_flLastTick so far
int   g_flBurstMax[MAXPLAYERS + 1];     // largest single-tick run this window
int   g_flBurstHits[MAXPLAYERS + 1];    // runs at/over the burst threshold this window
int   g_flBadSeconds[MAXPLAYERS + 1];   // consecutive qualifying windows
int   g_flServerBurstTick[MAXPLAYERS + 1]; // last tick this client burst, for the hitch guard
float g_flWindowStart[MAXPLAYERS + 1];  // start of the current one-second window
MoveType g_cmdSavedMoveType[MAXPLAYERS + 1];
bool  g_cmdFrozen[MAXPLAYERS + 1];

// extension health
bool  g_extMissing;

// optional integrations
bool  g_bStyleTimer;         // style timer plugin (shavit) present
bool  g_bDhooks;             // dhooks extension present
Handle g_hTeleportHook;       // CBaseEntity::Teleport DHook setup
GameData g_hKevACGameConf;    // KevAC PTaH-derived vtable/game addresses
Handle g_hGetClientCall;      // CBaseServer::GetClient raw SDKCall
Handle g_hFullUpdateHook;     // CGameClient::UpdateAcknowledgedFramecount vhook
Handle g_hListenerMessageHook; // CGameClient::ProcessListenEvents vhook
Address g_pBaseServer;
char  g_bypassTag[32];       // per-style special-string tag that disables behavioral checks
bool  g_styleBypass[MAXPLAYERS + 1];   // cached: this client's style is behavioral-exempt
bool  g_styleAutobhop[MAXPLAYERS + 1]; // cached: this client's style auto-bhops
ConVar gcv_bypass_tag, gcv_teleport_hook, gcv_cmd_public;

// alert scope + persistence (bash2_admin/bash2_personal port)
bool  g_alertsPersonal[MAXPLAYERS + 1]; // only show alerts about yourself
Cookie g_cookieAlerts;
Cookie g_cookiePersonal;

// KevAC's own plugin API (fired for other plugins: discord relays, stats, etc.)
Handle g_fwdDetection;
Handle g_fwdPunished;

// ---- TestACLog (diagnostic capture) ----
ConVar g_cvTestLog;
int    g_testTarget;                 // client being verbose-logged (0 = none)
int    g_testStartTick;
int    g_joinArm;                    // 0 none, 1 next join = DLL, 2 next join = Legit
int    g_probeClient;                // client under connection-probe
int    g_probeMode;                  // 1 DLL, 2 Legit (for the completion message)
int    g_probePending;               // outstanding convar queries for the probe
float  g_probeStart;                 // probe start time (for response-latency logging)
File   g_testFH;                     // open log handle for the active session/probe

// ---- Temporary knife-stab diagnosis ----
// This is deliberately target-scoped and disabled until an admin starts it.
// It observes command input and damage outcomes only. It never changes either.
int   g_stabTraceTargetUserId;
float g_stabTraceUntil;
int   g_stabTraceSessionId;
int   g_stabTraceInputCmd[MAXPLAYERS + 1];
int   g_stabTraceInputButtons[MAXPLAYERS + 1];
float g_stabTraceInputObservedAt[MAXPLAYERS + 1];
int   g_stabTraceLastFinalAttackButtons[MAXPLAYERS + 1];
int   g_stabTraceInputSerial[MAXPLAYERS + 1];
float g_stabTraceLastDamageTime[MAXPLAYERS + 1];
int   g_stabTraceDamageSerial;
int   g_stabTracePendingSerial[MAXPLAYERS + 1];
int   g_stabTracePendingAttackerUserId[MAXPLAYERS + 1];
bool  g_stabTracePendingPostDamage[MAXPLAYERS + 1];
bool  g_stabTracePendingPlayerHurt[MAXPLAYERS + 1];

// ---- Pre-ban audit capture ----
// Ban-grade detections wait briefly so the server retains the command stream and any
// corroborating detections from just before enforcement. Without the rolling pre-flag
// buffer the file holds the aftermath, not the episode. 256 ticks is two seconds at 128.
#define KEVAC_PREROLL_TICKS 256

enum
{
	PR_TICK = 0, PR_CMDNUM, PR_CMDTICK, PR_ONGROUND, PR_GROUNDTICK, PR_BUTTONS,
	PR_VEL0, PR_VEL1, PR_VEL2, PR_MOUSEX, PR_MOUSEY,
	PR_ANG0, PR_ANG1, PR_ANG2, PR_V0, PR_V1, PR_V2,
	PR_VELMOD, PR_MOVETYPE, PR_DUCKED, PR_WATER, PR_EYEZ,
	PR_CELLS
};

any   g_preroll[MAXPLAYERS + 1][KEVAC_PREROLL_TICKS][PR_CELLS];
int   g_prerollHead[MAXPLAYERS + 1];
int   g_prerollCount[MAXPLAYERS + 1];

bool   g_prebanPending[MAXPLAYERS + 1];
int    g_prebanUserId[MAXPLAYERS + 1];
int    g_prebanStartTick[MAXPLAYERS + 1];
int    g_prebanAction[MAXPLAYERS + 1];
int    g_prebanMinutes[MAXPLAYERS + 1];
char   g_prebanCategory[MAXPLAYERS + 1][64];
char   g_prebanEvidence[MAXPLAYERS + 1][256];
char   g_prebanReason[MAXPLAYERS + 1][192];
File   g_prebanFH[MAXPLAYERS + 1];

// probe cvar list
char g_probeCvars[][] =
{
	"sv_cheats", "cl_interp", "cl_interp_ratio", "cl_cmdrate", "cl_updaterate",
	"cl_forwardspeed", "cl_sidespeed", "sv_autobunnyhopping", "m_yaw", "sensitivity",
	"rate", "cl_interpolate", "cl_predict", "cl_lagcompensation", "cl_pitchspeed",
	"cl_pitchdown", "cl_pitchup", "developer", "host_timescale"
};

float g_tickrate;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	// A previous KevAC build, or a duplicated server plugin, can already provide this
	// compatibility native. Do not turn that deployment mistake into a failed load: consumers
	// feature-check before calling, so the existing provider stays safe until the duplicate goes.
	if(GetFeatureStatus(FeatureType_Native, "KevAC_IgnoreMovement") != FeatureStatus_Available) {
		CreateNative("KevAC_IgnoreMovement", Native_IgnoreMovement);
	}
	MarkNativeAsOptional("KevAC_GetListenerProbeStats");
	MarkNativeAsOptional("KevAC_IsListenerStaticDetourEnabled");
	MarkNativeAsOptional("KevAC_GetListenerMaskFingerprint");
	MarkNativeAsOptional("KevAC_AuditListenerCandidates");
	MarkNativeAsOptional("KevAC_GetAllListenerAuditEvents");
	MarkNativeAsOptional("KevAC_InspectListenEvents");
	return APLRes_Success;
}

public void OnPluginStart()
{
	LoadTranslations("kevac.phrases");
	LoadTranslations("common.phrases");

	RegAdminCmd("sm_kevac", CommandHelp, ADMFLAG_GENERIC, "Lists all KevAC commands");
	RegAdminCmd("sm_ad_config_reload", CommandReloadConfig, ADMFLAG_ROOT, "Reloads KevAC Config");
	RegAdminCmd("sm_ad_whitelist_reload", CommandReloadWhiteList, ADMFLAG_ROOT, "Reloads KevAC WhiteList");
	RegAdminCmd("sm_ad_whitelist_add", CommandAddWhiteList, ADMFLAG_ROOT, "Adds a SteamID to the KevAC WhiteList. Usage: sm_ad_whitelist_add <STEAM_1:0:...> [Detector[,Detector...]]");
	RegAdminCmd("sm_ad_whitelist_list", CommandPrintWhiteList, ADMFLAG_BAN, "List all SteamIDs in KevAC WhiteList and what each is exempt from");
	RegAdminCmd("sm_kevac_whitelist", CommandKevACWhitelist, ADMFLAG_ROOT, "Exempt a player from one detector (or all). Usage: sm_kevac_whitelist <#userid|name|steamid> [Detector[,Detector...]]");
	RegAdminCmd("sm_kevac_unwhitelist", CommandKevACUnwhitelist, ADMFLAG_ROOT, "Removes every whitelist entry for a SteamID. Usage: sm_kevac_unwhitelist <STEAM_1:0:X>");
	RegAdminCmd("sm_kevac_clearwhitelist", CommandClearWhiteList, ADMFLAG_ROOT, "Clears the ENTIRE KevAC whitelist. Usage: sm_kevac_clearwhitelist confirm");
	RegAdminCmd("sm_alerts", CommandAlerts, ADMFLAG_GENERIC, "Toggles KevAC detection alerts for yourself");
	RegAdminCmd("sm_kevac_stats", CommandStats, ADMFLAG_GENERIC, "Shows BASH strafe/gain stats for a player");
	RegAdminCmd("sm_kevac_ext", CommandExtStatus, ADMFLAG_GENERIC, "Shows KevAC extension status and per-client listener telemetry");
	RegAdminCmd("sm_kevac_listeneraudit", CommandListenerAudit, ADMFLAG_GENERIC, "Safely checks a player's active listener table for named events");
	RegAdminCmd("sm_kevac_listenerauditall", CommandListenerAuditAll, ADMFLAG_GENERIC, "Writes every connected player's full known listener catalog to the KevAC audit log");
	RegAdminCmd("sm_kevac_stabtrace", CommandStabTrace, ADMFLAG_GENERIC, "Toggles a temporary, target-scoped knife-stab diagnostic trace");
	// Queued bans persist across restarts, so the file is read back at start.
	LoadBanQueue();

	RegAdminCmd("sm_kevac_execban", Command_KevACExecBan, ADMFLAG_BAN, "Execute the queued ban wave. Usage: sm_kevac_execban confirm (bare form previews the queue)");
	RegAdminCmd("sm_kevac_banqueue", Command_KevACBanQueue, ADMFLAG_BAN, "List the players queued for the next ban wave");
	RegAdminCmd("sm_cancelban", CommandCancelPreBan, ADMFLAG_BAN, "Cancels a pending KevAC pre-ban before it is enforced. Usage: sm_cancelban <#userid|name>");
	RegAdminCmd("sm_kevac_cancelban", CommandCancelPreBan, ADMFLAG_BAN, "Cancels a pending KevAC pre-ban. (alias)");

	// bash2 command surface, rebranded (kevac_* are the canonical names; the old
	// bash names stay as aliases for muscle memory). Gated by kevac_cmd_public.
	RegConsoleCmd("kevac_menu", CommandKevACMenu, "Open the KevAC settings menu");
	RegConsoleCmd("sm_kevac_menu", CommandKevACMenu, "Open the KevAC settings menu");
	RegConsoleCmd("sm_bash", CommandKevACMenu, "Open the KevAC settings menu (bash2 alias)");
	RegConsoleCmd("sm_bash2", CommandKevACMenu, "Open the KevAC settings menu (bash2 alias)");
	RegConsoleCmd("kevac_stats", CommandStatsConsole, "Check a player's strafe stats");
	RegConsoleCmd("bash2_stats", CommandStatsConsole, "Check a player's strafe stats (bash2 alias)");
	RegConsoleCmd("kevac_admin", CommandAlertsConsole, "Toggle KevAC detection alerts in chat");
	RegConsoleCmd("bash2_admin", CommandAlertsConsole, "Toggle KevAC detection alerts in chat (bash2 alias)");
	RegConsoleCmd("kevac_personal", CommandPersonal, "Toggle personal mode (only alerts about yourself)");
	RegConsoleCmd("bash2_personal", CommandPersonal, "Toggle personal mode (bash2 alias)");

	g_cookieAlerts = new Cookie("kevac_alerts_enabled", "KevAC: detection alerts on/off", CookieAccess_Private);
	g_cookiePersonal = new Cookie("kevac_alerts_personal", "KevAC: only show alerts about yourself", CookieAccess_Private);

	g_fwdDetection = CreateGlobalForward("KevAC_OnDetection", ET_Ignore, Param_Cell, Param_String, Param_String, Param_Cell);
	g_fwdPunished = CreateGlobalForward("KevAC_OnClientPunished", ET_Ignore, Param_Cell, Param_Cell, Param_String);

	hWhiteList = new ArrayList(ByteCountToCells(KEVAC_WL_LEN));
	g_tickrate = 1.0 / GetTickInterval();
	g_cvServerAutoBhop = FindConVar("sv_autobunnyhopping");
	g_cvAllowWait = FindConVar("sv_allow_wait_command");
	g_cvMaxUsercmdFutureTicks = FindConVar("sv_max_usercmd_future_ticks");
	g_cvSvCheats = FindConVar("sv_cheats");

	g_cvTestLog = CreateConVar("sm_kevac_testlog", "0", "Enable KevAC diagnostic commands until manually set to 0; captures may start and stop independently.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	AddCommandListener(OnSayCommand, "say");
	AddCommandListener(OnSayCommand, "say_team");
	AddCommandListener(OnClientFullUpdateCommand, "cl_fullupdate");
	AddCommandListener(OnClientFullUpdateCommand, "fullupdate");
	HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
	HookEvent("player_jump", Event_PlayerJump, EventHookMode_Post);
	HookEvent("player_hurt", Event_PlayerHurt_StabTrace, EventHookMode_Post);
	HookEntityOutput("trigger_teleport", "OnEndTouch", OnTeleportTrigger);

	RegisterConVars();
	RefreshConfig();
	LoadCheatCvarList();
	LoadConvarImmune();
	LoadWhiteList();

	CreateTimer(15.0, Timer_CheatVarScan, _, TIMER_REPEAT);
	CreateTimer(10.0, Timer_LerpScan, _, TIMER_REPEAT);

	for (int i = 1; i <= MaxClients; i++)
	{
		g_fullUpdateHookId[i] = -1;
		g_listenerMessageHookId[i] = -1;
		if (IsClientInGame(i))
		{
			OnClientPutInServer(i);
		}
	}
	CreateTimer(1.0, Timer_StartupNotice);
}

public void OnMapStart()
{
	StopStabTrace("map change");
	LoadCheatCvarList();
	LoadConvarImmune();
	LoadWhiteList();
	// A map change can cause the retail client to refresh its listener mask.
	// Give that normal transition the same grace window as a fresh connection.
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client) || IsFakeClient(client))
			continue;

		ResetListenerPacketTelemetry(client);

	}
	CreateTimer(1.0, Timer_StartupNotice);
}

// Listener packet state is reset both at a new map and when a client occupies
// a slot again. Keep the shared portion together so their grace-window logic
// cannot drift apart.
void ResetListenerPacketTelemetry(int client)
{
	g_clientJoinTime[client] = GetGameTime();
	g_listenerUpdateCount[client] = 0;
	g_listenerActiveSubscriptions[client] = 0;
	g_listenerBlacklistedSubscriptions[client] = 0;
	g_listenerBlacklistedEventNames[client][0] = '\0';
	g_listenerPeakSubscriptions[client] = 0;
	g_listenerMaskFingerprint[client] = 0;
	g_listenerMaskOutlierFingerprint[client] = 0;
	g_listenerAuditLoggedFingerprint[client] = 0;
	g_listenerOversubFlagged[client] = false;
	g_listenerTelemetrySeen[client] = false;
}

// Keep the prefix formatting here so phrases remain plain, editable text.
// CPrintToChat handles the CS:GO color transport and never sends raw, malformed
// color control bytes to the client.
void KevACPrintToChat(int client, const char[] format, any ...)
{
	if (client < 1 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client))
		return;

	char message[256];
	char prefix[64];
	SetGlobalTransTarget(client);
	VFormat(message, sizeof(message), format, 3);
	FormatEx(prefix, sizeof(prefix), "%T", "Chat_Prefix", client);
	CPrintToChat(client, "{red}[%s] {default}%s", prefix, message);
}

public Action Timer_StartupNotice(Handle timer)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (CanReceiveKevACAlert(i))
		{
			KevACPrintToChat(i, "%T", "Startup_Active", i);
			if (g_extMissing)
				KevACPrintToChat(i, "%T", "Startup_ExtMissing", i);
		}
	}
	return Plugin_Stop;
}

public Action CommandAlerts(int client, int args)
{
	if (client == 0)
	{
		ReplyToCommand(client, "%T", "Alerts_Console", client);
		return Plugin_Handled;
	}

	g_showAlerts[client] = !g_showAlerts[client];
	if (AreClientCookiesCached(client))
		g_cookieAlerts.Set(client, g_showAlerts[client] ? "1" : "0");
	KevACPrintToChat(client, "%T", g_showAlerts[client] ? "Alerts_Enabled" : "Alerts_Disabled", client);
	return Plugin_Handled;
}

// Console-command surface for the bash2 ports. Everything here exposes detection
// evidence, so without kevac_cmd_public it stays behind the sm_alerts admin gate.
bool KevACCmdAllowed(int client)
{
	if (client == 0 || gcv_cmd_public.BoolValue)
		return true;
	return CheckCommandAccess(client, "sm_alerts", ADMFLAG_GENERIC, false);
}

public Action CommandAlertsConsole(int client, int args)
{
	if (!KevACCmdAllowed(client))
	{
		ReplyToCommand(client, "[KevAC] You do not have access to this command.");
		return Plugin_Handled;
	}
	return CommandAlerts(client, args);
}

public Action CommandPersonal(int client, int args)
{
	if (client == 0)
	{
		ReplyToCommand(client, "[KevAC] This command must be used in-game.");
		return Plugin_Handled;
	}
	if (!KevACCmdAllowed(client))
	{
		ReplyToCommand(client, "[KevAC] You do not have access to this command.");
		return Plugin_Handled;
	}

	g_alertsPersonal[client] = !g_alertsPersonal[client];
	if (AreClientCookiesCached(client))
		g_cookiePersonal.Set(client, g_alertsPersonal[client] ? "1" : "0");
	KevACPrintToChat(client, "%T", g_alertsPersonal[client] ? "Alerts_PersonalOnly" : "Alerts_PersonalAll", client);
	return Plugin_Handled;
}

public Action CommandStatsConsole(int client, int args)
{
	if (!KevACCmdAllowed(client))
	{
		ReplyToCommand(client, "[KevAC] You do not have access to this command.");
		return Plugin_Handled;
	}
	return CommandStats(client, args);
}

public Action CommandKevACMenu(int client, int args)
{
	if (client == 0)
	{
		ReplyToCommand(client, "[KevAC] This command must be used in-game.");
		return Plugin_Handled;
	}
	if (!KevACCmdAllowed(client))
	{
		ReplyToCommand(client, "[KevAC] You do not have access to this command.");
		return Plugin_Handled;
	}

	ShowKevACMenu(client);
	return Plugin_Handled;
}

void ShowKevACMenu(int client)
{
	Menu menu = new Menu(KevACMenu_Handler);
	menu.SetTitle("[KevAC] Settings");
	menu.AddItem("alerts", g_showAlerts[client] ? "[x] Detection alerts" : "[ ] Detection alerts");
	if (g_showAlerts[client])
		menu.AddItem("personal", g_alertsPersonal[client] ? "[You] Alert scope" : "[All] Alert scope");
	menu.AddItem("stats", "My strafe stats");
	menu.Display(client, MENU_TIME_FOREVER);
}

public int KevACMenu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		char info[32];
		menu.GetItem(param2, info, sizeof(info));

		if (StrEqual(info, "alerts"))
		{
			CommandAlerts(param1, 0);
			ShowKevACMenu(param1);
		}
		else if (StrEqual(info, "personal"))
		{
			CommandPersonal(param1, 0);
			ShowKevACMenu(param1);
		}
		else if (StrEqual(info, "stats"))
		{
			PrintStatsChat(param1, param1);
		}
	}
	if (action & MenuAction_End)
		delete menu;
	return 0;
}

public void OnClientCookiesCached(int client)
{
	ApplyAlertCookies(client);
}

void ApplyAlertCookies(int client)
{
	if (client < 1 || client > MaxClients || !IsClientConnected(client) || IsFakeClient(client) || !AreClientCookiesCached(client))
		return;

	char v[8];
	g_cookieAlerts.Get(client, v, sizeof(v));
	if (v[0] != '\0')
		g_showAlerts[client] = StrEqual(v, "1");
	g_cookiePersonal.Get(client, v, sizeof(v));
	g_alertsPersonal[client] = StrEqual(v, "1");
}

public void OnConfigsExecuted()
{
	RefreshConfig();
}

public void OnMapEnd()
{
	StopTest();
	for (int client = 1; client <= MaxClients; client++)
	{
		if (g_prebanPending[client] && IsClientInGame(client))
			DispatchPreBan(client, "map ended; enforcement dispatched early");
		else
			StopPreBanCapture(client, "map ended before enforcement");
	}
}

public void OnPluginEnd()
{
	for (int client = 1; client <= MaxClients; client++)
	{
		StopPreBanCapture(client, "plugin unloading");
		RemoveFullUpdateHook(client);
		RemoveListenerMessageHook(client);
	}
	delete g_hFullUpdateHook;
	delete g_hListenerMessageHook;
	delete g_hGetClientCall;
	delete g_hTeleportHook;
	g_hTeleportHook = null;
	g_bDhooks = false;
	delete g_hKevACGameConf;

	if (g_testFH != null)
	{
		g_testFH.Close();
		g_testFH = null;
	}
}

// Action convention for every gcv_*action below: -1 disable, 0 log-only, 1 kick,
// 2 SourceMod ban, 3 SourceBans++ ban with an automatic SourceMod fallback.
void RegisterConVars()
{
	gcv_enable       = CreateConVar("kevac_enable", "1", "Master enable for the whole anti-cheat.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	gcv_method       = CreateConVar("kevac_listener_action", "3", "Action for verified extension event-listener telemetry. -1 disables, 0 logs, 1 kicks, 2 SourceMod bans, 3 SourceBans++ bans with SourceMod fallback. Unverified callbacks are never punished.", _, true, -1.0, true, 3.0);
	gcv_listener_update = CreateConVar("kevac_listener_update_action", "0", "Action for verified post-join event-listener mask changes: -1 disable, 0 log, 1 kick, 2 SourceMod ban, 3 SourceBans++ ban with SourceMod fallback. A newly matched blacklisted event uses kevac_listener_action instead.", _, true, -1.0, true, 3.0);
	gcv_listener_update_grace = CreateConVar("kevac_listener_update_grace", "30", "Seconds after join before a new event-listener update is flagged.", _, true, 0.0, true, 300.0);
	gcv_listener_update_threshold = CreateConVar("kevac_listener_update_threshold", "1", "Actual post-join listener-mask changes required before the configured update action. The first verified change after grace is actionable.", _, true, 1.0, true, 10.0);
	// Count-ceiling detection, independent of the event-name blacklist. A retail client subscribes
	// to a stable number of game events; a DLL adding ANY extra events exceeds it. Set the ceiling
	// just above what sm_kevac_ext shows for known-clean players. 0 disables.
	gcv_listener_maxsubs = CreateConVar("kevac_listener_max_subs", "169", "Max network event subscriptions a client may hold before flagging (calibrated: known-clean peak is 166; 0 disables).", _, true, 0.0, true, 512.0);
	gcv_listener_maxsubs_action = CreateConVar("kevac_listener_max_subs_action", "3", "Action when a verified client exceeds kevac_listener_max_subs. -1 disable, 0 log, 1 kick, 2 SourceMod ban, 3 SourceBans++ ban with SourceMod fallback.", _, true, -1.0, true, 3.0);
	gcv_listener_consensus_min = CreateConVar("kevac_listener_consensus_min_clients", "3", "Minimum decoded human-client masks required for listener-mask peer comparison. Outliers are logged and shown only to opted-in admins. They are never punished from this signal alone.", _, true, 2.0, true, MAXPLAYERS + 1.0);
	gcv_listener_consensus_pct = CreateConVar("kevac_listener_consensus_pct", "75", "Percentage of decoded clients that must share one mask before the rest are called outliers. A bare majority is not a baseline: at 6/11 one disconnect flips which side is 'normal' and flags everybody else.", _, true, 51.0, true, 100.0);
	gcv_listener_audit_log = CreateConVar("kevac_listener_audit_log", "0", "Write known listener-catalog snapshots on a player's first decoded mask and each mask change to logs/KevAC-listeners.log. This is diagnostics only.", _, true, 0.0, true, 1.0);
	gcv_fullupdate_action = CreateConVar("kevac_fullupdate_action", "1", "Repeated client-issued cl_fullupdate or fullupdate commands: -1 disable reporting, 0 log, 1 kick, 2 SM ban, 3 SB ban. A single command is not proof of a skin changer.", _, true, -1.0, true, 3.0);
	gcv_fullupdate_threshold = CreateConVar("kevac_fullupdate_threshold", "3", "Client-issued cl_fullupdate or fullupdate commands in the window before action. Three protects legitimate manual use while catching repeated automated refreshes.", _, true, 1.0, true, 32.0);
	gcv_fullupdate_window = CreateConVar("kevac_fullupdate_window", "120.0", "Seconds used to group client-issued full-update commands.", _, true, 10.0, true, 900.0);
	gcv_bantime      = CreateConVar("kevac_bantime", "0", "Ban length in minutes (0 = permanent).", _, true, 0.0);
	gcv_preban_delay = CreateConVar("kevac_preban_delay", "30", "Seconds to capture a ban-grade player's command evidence before SourceMod or SourceBans++ enforcement. 0 bans immediately.", _, true, 0.0, true, 120.0);
	gcv_banwave = CreateConVar("kevac_banwave", "1", "Hold pre-ban enforcement in a queue instead of banning when the audit window closes. The capture still runs in full; an admin flushes the queue with sm_kevac_execban. The queue is written to disk, so it survives a restart. 0 bans immediately as before.", _, true, 0.0, true, 1.0);
	gcv_banwave_exempt = CreateConVar("kevac_banwave_exempt", "Ghost", "Comma-separated detector-name fragments that skip the ban wave and enforce immediately. Matched as case-insensitive substrings of the detector name, so \"Ghost\" covers GhostJump and GhostStrafe. Empty = every detector goes through the queue.");
	gcv_preban_preroll = CreateConVar("kevac_preban_preroll", "1", "Keep a rolling two-second command buffer per player and write it ahead of the pre-ban capture, so the file contains the episode that triggered the detection and not only its aftermath. Costs a few entity reads per player per tick.", _, true, 0.0, true, 1.0);
	gcv_notify       = CreateConVar("kevac_notify", "7", "Notify bitflags: add 1 log, 2 server, 4 admins. Chat notices are always admin-only.", _, true, 0.0, true, 7.0);
	gcv_bd_enable    = CreateConVar("kevac_behavioral", "1", "Enable behavioral (CUserCmd) detection.", _, true, 0.0, true, 1.0);
	gcv_log          = CreateConVar("kevac_log", "1", "Deprecated: KevAC always logs detection evidence before taking action.", _, true, 0.0, true, 1.0);
	gcv_admin_immune = CreateConVar("kevac_admin_immune", "1", "Exempt ROOT admins from the sv_cheats / cheat-convar checks (they may legitimately toggle cvars).", _, true, 0.0, true, 1.0);

	gcv_ghostjump    = CreateConVar("kevac_ghostjump_action", "0", "Ghost jump: left ground with jump impulse but no IN_JUMP (heuristic; log until calibrated).");
	gcv_ghost        = CreateConVar("kevac_ghost_action", "0", "Ghost strafe: move value with no matching WASD button (heuristic; log until calibrated).");
	gcv_ghost_tol    = CreateConVar("kevac_ghost_tol", "20", "Min |move| units to count as real movement.");
	gcv_ghost_streak = CreateConVar("kevac_ghost_streak", "10", "Ghost-strafe offending ticks before flagging.");

	gcv_synth        = CreateConVar("kevac_synth_action", "0", "Synthetic airborne move value from a keyboard (heuristic; log until calibrated).");
	gcv_synth_ticks  = CreateConVar("kevac_synth_ticks", "12", "Synthetic-move offending ticks before flagging.");
	gcv_synth_tol    = CreateConVar("kevac_synth_tol", "3.0", "Tolerance around legal cardinal move magnitudes.");

	// Disabled by default: packet recovery can resemble historical attack ticks, especially for
	// high-latency knife players. The PATCH defaults on since 2.3.17 - it punishes nobody, it
	// rewrites jittery attack ticks to now-minus-latency, which fixed high-ping ghoststabs and
	// neutered backtrack cheats in live testing (07-22). Live cfg (07-30): log-only, widest age gate.
	gcv_tick         = CreateConVar("kevac_backtrack_action", "0", "Historical attack-tick detector: -1 disabled, 0 log, 1 kick, 2 SourceMod ban, 3 SourceBans++ ban with fallback.", _, true, -1.0, true, 3.0);
	gcv_tick_regress = CreateConVar("kevac_backtrack_ticks", "2", "Minimum backward command-tick jump to count when the backtrack detector is enabled. Exact duplicate historical attack ticks also count.", _, true, 1.0, true, 300.0);
	gcv_tick_streak  = CreateConVar("kevac_backtrack_streak", "2", "Matching historical attacks within five seconds before flagging or patching.", _, true, 2.0, true, 8.0);
	gcv_tick_patch   = CreateConVar("kevac_backtrack_patch", "1", "Patch repeated anomalous attack tickcounts. Live-validated 07-22: normalizing jittery attack ticks to now-minus-latency fixed high-ping ghoststabs.", _, true, 0.0, true, 1.0);
	gcv_tick_tolerance = CreateConVar("kevac_backtrack_tolerance", "0", "Allowed deviation from the expected command tick before the opt-in patch counts an anomaly.", _, true, 0.0, true, 3.0);
	gcv_tick_min_old = CreateConVar("kevac_backtrack_min_old_ticks", "64", "Required age below the latency-adjusted server tick before an opt-in historical attack tick counts.", _, true, 3.0, true, 64.0);

	// Human scroll-bhop captures can sustain zero-ground-tick runs, so this stays evidence until
	// paired with an independent signal. Capture-validated: an auto-bhop DLL presses +jump once on
	// the landing tick; a human scroller shows airborne edges (435/508 legit vs 0/28 DLL).
	gcv_bhop         = CreateConVar("kevac_bhop_action", "3", "Scripted bhop: consecutive perfect jumps with zero airborne +jump input (0 log, 1 kick, 2 SourceMod ban, 3 SourceBans++ ban with fallback).");
	gcv_bhop_ground  = CreateConVar("kevac_bhop_maxground", "0", "Max ground ticks for a jump to count as perfect.");
	gcv_bhop_streak  = CreateConVar("kevac_bhop_streak", "8", "Consecutive clean perfect jumps before flagging.");
	// Ratio window: humanized autobhop inserts deliberate missed hops so the
	// consecutive streak never fills. Over a window of jump takeoffs, a clean-
	// perfect share no human scroller sustains is still visible.
	gcv_bhop_ratio   = CreateConVar("kevac_bhop_ratio_action", "0", "Humanized scripted bhop: perfect-jump share over a window of takeoffs. -1 disable, 0 log, 1 kick, 2 SM ban, 3 SB ban.", _, true, -1.0, true, 3.0);
	gcv_bhop_ratio_window = CreateConVar("kevac_bhop_ratio_window", "24", "Jump takeoffs per evaluation window.", _, true, 10.0, true, 64.0);
	gcv_bhop_ratio_pct = CreateConVar("kevac_bhop_ratio_pct", "90", "Clean perfect-jump percentage at or above which the window flags.", _, true, 50.0, true, 100.0);

	// Raw button edges do not identify a wheel, a bind or a macro. Keep them as evidence and act
	// only after a long run of high-speed, near-perfect hop outcomes also matches the cadence
	// profile. Oryx's useful idea without punishing a four-scroll burst from a legit HnS player.
	gcv_scroll       = CreateConVar("kevac_scroll_action", "1", "Exact-cadence evidence switch: -1 ignores exact cadence; any other value records it for the verified scroll outcome profile.", _, true, -1.0, true, 3.0);
	gcv_scroll_sample= CreateConVar("kevac_scroll_sample", "8", "Jump intervals sampled (max 32).", _, true, 1.0, true, 32.0);
	gcv_scroll_jitter= CreateConVar("kevac_scroll_jitter", "0", "Max tick jitter across an exact-cadence evidence run (0 = exact only).", _, true, 0.0, true, 4.0);
	gcv_scroll_pattern = CreateConVar("kevac_scroll_pattern_action", "3", "Verified scroll-macro outcome profile action: -1 disable, 0 log, 1 kick, 2 SM ban, 3 SB ban. Raw cadence never acts alone.", _, true, -1.0, true, 3.0);
	gcv_scroll_pattern_repeats = CreateConVar("kevac_scroll_pattern_repeats", "3", "Matching short jump intervals after the first required before recording one cadence-evidence burst (3 = four intervals).", _, true, 1.0);
	gcv_scroll_pattern_jitter = CreateConVar("kevac_scroll_pattern_jitter", "2", "Maximum spread in ticks across a near-periodic scroll sequence (0 = exact only).", _, true, 0.0, true, 4.0);
	gcv_scroll_pattern_maxinterval = CreateConVar("kevac_scroll_pattern_maxinterval", "4", "Largest interval in ticks considered a short scroll sequence.", _, true, 1.0, true, 12.0);
	gcv_scroll_profile_window = CreateConVar("kevac_scroll_profile_window", "48", "Completed high-speed hops sampled before evaluating the scroll outcome profile.", _, true, 24.0, true, float(KEVAC_SCROLL_PROFILE_MAX));
	gcv_scroll_profile_perfect_pct = CreateConVar("kevac_scroll_profile_perfect_pct", "94", "Required percentage of landing-tick hops in a scroll outcome profile.", _, true, 80.0, true, 100.0);
	gcv_scroll_profile_min_presses = CreateConVar("kevac_scroll_profile_min_presses", "3", "Minimum airborne +jump edges that make one hop a high-rate scroll candidate.", _, true, 2.0, true, 16.0);
	gcv_scroll_profile_press_pct = CreateConVar("kevac_scroll_profile_press_pct", "90", "Required percentage of profile hops with the minimum airborne +jump edge count.", _, true, 50.0, true, 100.0);
	gcv_scroll_profile_same_pairs = CreateConVar("kevac_scroll_profile_same_pairs", "32", "Required adjacent hop pairs whose airborne +jump edge counts differ by at most one.", _, true, 1.0, true, float(KEVAC_SCROLL_PROFILE_MAX - 1));
	gcv_scroll_profile_cadence_bursts = CreateConVar("kevac_scroll_profile_cadence_bursts", "8", "Raw exact or near-periodic cadence bursts required inside one outcome profile.", _, true, 1.0, true, 64.0);
	gcv_scroll_profile_minspeed = CreateConVar("kevac_scroll_profile_min_speed", "225.0", "Minimum horizontal speed for a hop to enter the scroll outcome profile.", _, true, 100.0, true, 1000.0);

	// A +duck wheel bind is normal on HnS. Treat periodic duck input as evidence
	// and require repeated verified ground jumpbug outcomes before taking action.
	gcv_duckmacro = CreateConVar("kevac_duckmacro_action", "3", "Verified +duck macro with repeated ground-jumpbug outcomes: -1 disable, 0 log, 1 kick, 2 SM ban, 3 SB ban. Periodic +duck input alone never acts through this cvar.", _, true, -1.0, true, 3.0);
	gcv_duckmacro_repeats = CreateConVar("kevac_duckmacro_repeats", "8", "Matching short +duck intervals after the first required before flagging (8 = nine intervals / ten presses).", _, true, 1.0);
	// Deliberately 1, not 0. Server policy (07-30): firmware-assisted input such as scroll-smoothing
	// counts as cheating even when the player did not set it up, so the wider band is wanted.
	// jitter 1 accepts a 2-3 tick OSCILLATION (~43-64 Hz) rather than a fixed period, so it fires
	// on variable input too: the 07-30 capture ran 3,3,2,3,2,2,2,2,4,3,2 and still reached 13
	// bursts, where jitter 0 scores 1 and the DLL captures sit at 42/65 against a threshold of 10.
	gcv_duckmacro_jitter = CreateConVar("kevac_duckmacro_jitter", "1", "Maximum spread in ticks across a rapid +duck sequence (0 = exact interval only). Above 0 matches a rate band rather than a fixed period, which also catches firmware-regularised scroll input.", _, true, 0.0, true, 4.0);
	gcv_duckmacro_maxinterval = CreateConVar("kevac_duckmacro_maxinterval", "4", "Largest interval in ticks considered a rapid +duck sequence.", _, true, 1.0, true, 12.0);
	gcv_duckmacro_outcomes = CreateConVar("kevac_duckmacro_outcomes", "4", "Verified ground jumpbug outcomes with fresh +duck cadence evidence required before the +duck macro action.", _, true, 2.0, true, 12.0);
	gcv_duckmacro_window = CreateConVar("kevac_duckmacro_window", "128", "Maximum ticks between a +duck cadence burst and a ground jumpbug outcome.", _, true, 16.0, true, 1024.0);
	// A duck-only macro has no +jump outcome to verify, so this companion signal stays part of
	// DuckMacro rather than a separate gstrafe detector. Actionable only after enough cadence
	// bursts to separate HiResScrollWheel-style macros from normal wheel +duck and legit gstrafe.
	gcv_duckmacro_input = CreateConVar("kevac_duckmacro_input_action", "3", "Exactly periodic +duck cadence while moving fast, which is a gstrafe macro such as HiResScrollWheel: -1 disable, 0 log, 1 kick, 2 SM ban, 3 SB ban. A cadence that drifts instead of repeating exactly is a physical wheel and goes to kevac_hyperscroll_action.", _, true, -1.0, true, 3.0);
	gcv_duckmacro_input_bursts = CreateConVar("kevac_duckmacro_input_bursts", "10", "Periodic +duck cadence bursts required before the input signal reports. 2026-07 HnS logs: legit gstrafe peaked near 5 bursts, DLL HiResScrollWheel exceeded 20.", _, true, 1.0, true, 32.0);
	gcv_duckmacro_input_minspeed = CreateConVar("kevac_duckmacro_input_min_speed", "140.0", "Minimum horizontal speed required for the periodic +duck input signal; excludes idle duck spam.", _, true, 0.0);
	gcv_hyperscroll = CreateConVar("kevac_hyperscroll_action", "1", "Action when a +duck or +jump cadence drifts inside the jitter band instead of repeating exactly. That is a free-spinning wheel coasting down (G502 hyper-scroll and friends), not machine timing. The wheel-mode button sits under the wheel and is easy to hit by accident, so this stays below the macro actions. -1 disable, 0 log, 1 kick, 2 SM ban, 3 SB ban.", _, true, -1.0, true, 3.0);

	// A jumpbug is a legitimate but extremely tight movement technique.  Record
	// repeated successful signatures for review; do not punish on a fresh install.
	gcv_jumpbug = CreateConVar("kevac_jumpbug_action", "0", "Repeated successful jumpbug signature: -1 disable, 0 log, 1 kick, 2 SM ban, 3 SB ban.");
	gcv_jumpbug_streak = CreateConVar("kevac_jumpbug_streak", "4", "Successful jumpbugs in a row before flagging.", _, true, 2.0);
	gcv_jumpbug_chain = CreateConVar("kevac_jumpbug_chain_ticks", "1024", "Maximum ticks between jumpbug successes in one streak.", _, true, 64.0);
	gcv_jumpbug_maxgap = CreateConVar("kevac_jumpbug_confirm_ticks", "2", "Ticks allowed to confirm upward motion after a jumpbug input.", _, true, 1.0, true, 4.0);
	gcv_jumpbug_minfall = CreateConVar("kevac_jumpbug_min_fall_speed", "350.0", "Minimum downward speed required to arm a jumpbug candidate.", _, true, 100.0);
	gcv_jumpbug_timing = CreateConVar("kevac_jumpbug_timing_action", "3", "Completed jumpbugs with identical duck-press-to-jump timing. 0 log, 1 kick, 2 SourceMod ban, 3 SourceBans++ ban with fallback.", _, true, -1.0, true, 3.0);
	gcv_jumpbug_timing_repeats = CreateConVar("kevac_jumpbug_timing_repeats", "3", "Matching successful jumpbugs required for the tick-perfect timing signature.", _, true, 3.0, true, 8.0);
	gcv_jumpbug_timing_jitter = CreateConVar("kevac_jumpbug_timing_jitter", "1", "Allowed tick spread in duck-press-to-jump timing. Capture analysis: real players spread 0-40 ticks, macros hold within +-1; 0 requires exact timing.", _, true, 0.0, true, 3.0);
	gcv_jumpbug_timing_maxduck = CreateConVar("kevac_jumpbug_timing_max_duck_ticks", "8", "Maximum duck-press-to-jump delay considered a timing signature.", _, true, 1.0, true, 32.0);

	gcv_groundjumpbug = CreateConVar("kevac_groundjumpbug_action", "0", "Ground jumpbug momentum signature: -1 disable, 0 log, 1 kick, 2 SM ban, 3 SB ban.");
	gcv_groundjumpbug_streak = CreateConVar("kevac_groundjumpbug_streak", "4", "Successful ground jumpbug signatures in a row before flagging.", _, true, 2.0);
	gcv_groundjumpbug_maxgap = CreateConVar("kevac_groundjumpbug_confirm_ticks", "2", "Ticks allowed to confirm a ground jumpbug takeoff.", _, true, 1.0, true, 4.0);
	gcv_groundjumpbug_chain = CreateConVar("kevac_groundjumpbug_chain_ticks", "128", "Maximum ticks between ground jumpbug successes in one streak.", _, true, 16.0);
	gcv_groundjumpbug_minspeed = CreateConVar("kevac_groundjumpbug_min_speed", "250.0", "Minimum horizontal speed required before a ground jumpbug candidate.", _, true, 0.0);
	gcv_groundjumpbug_minside = CreateConVar("kevac_groundjumpbug_min_sidemove", "200.0", "Minimum sidemove value required for a ground jumpbug/gstrafe candidate.", _, true, 0.0);
	gcv_groundjumpbug_speedloss = CreateConVar("kevac_groundjumpbug_max_speed_loss", "5.0", "Maximum horizontal speed loss permitted when confirming a ground jumpbug candidate.", _, true, 0.0);
	// Same fixed-latency logic as the airborne jumpbug: a macro presses +jump a
	// constant number of ticks after +duck. Reuses kevac_jumpbug_timing_* thresholds.
	gcv_groundjumpbug_timing = CreateConVar("kevac_groundjumpbug_timing_action", "3", "Completed ground jumpbugs with identical +duck-to-+jump timing (macro). -1 disable, 0 log, 1 kick, 2 SourceMod ban, 3 SourceBans++ ban with fallback.", _, true, -1.0, true, 3.0);

	gcv_ahk          = CreateConVar("kevac_ahk_action", "0", "AHK strafe: identical mouse-x deltas mid-air (heuristic; log until calibrated).");
	gcv_ahk_streak   = CreateConVar("kevac_ahk_streak", "25", "Identical mouse-x deltas before flagging.");
	gcv_ahk_maxnet   = CreateConVar("kevac_ahk_max_netloss", "1.0", "Incoming loss/choke percent above which AHKStrafe samples are discarded. A lagging client replays backup usercmds, producing identical mouse deltas with no macro involved. Commands arriving in a delivery burst are always discarded regardless of this value.", _, true, 0.0, true, 100.0);

	gcv_silent       = CreateConVar("kevac_silent_action", "0", "Silent strafe: per-tick sidemove sign flips (heuristic; log until calibrated).");
	gcv_silent_streak= CreateConVar("kevac_silent_streak", "12", "Consecutive sign flips before flagging.");

	gcv_knife        = CreateConVar("kevac_knife_action", "0", "Knifebot: stab faster than human reaction (heuristic; log until calibrated).");
	gcv_knife_range  = CreateConVar("kevac_knife_range", "64.0", "Knife range units.");
	gcv_knife_cone   = CreateConVar("kevac_knife_cone", "0.6", "Aim-cone dot product (higher = tighter).");
	gcv_knife_ms     = CreateConVar("kevac_knife_ms", "80", "Human reaction floor in ms.");
	gcv_knife_streak = CreateConVar("kevac_knife_streak", "6", "Sub-floor stabs before flagging.");

	// Disabled by default: this only tests cl_cmdrate == kevac_latency_cmdrate, which any old
	// low-bandwidth autoexec sets legitimately, so it has no discriminating power alone. -1 also
	// stops the client query in OnClientSettingsChanged, so it costs nothing when off.
	gcv_latency      = CreateConVar("kevac_latency_action", "-1", "Hide-latency: flags cl_cmdrate exactly equal to kevac_latency_cmdrate. Uncalibrated heuristic with a high false-positive rate (ordinary configs set a low cmdrate); -1 disable, 0 log.");
	gcv_latency_rate = CreateConVar("kevac_latency_cmdrate", "10", "The spoofed cl_cmdrate value to flag.");
	// The action check only recorded MATCHES, so there was no baseline to calibrate against. This
	// logs what every client reports - no flag, no alert, no action - so the value distribution
	// can be read off the log before deciding whether the check discriminates anything.
	gcv_latency_observe = CreateConVar("kevac_latency_observe", "0", "Log every client's reported cl_cmdrate to KevAC.log for calibration. Observation only: never flags, alerts or punishes. (1 = on, 0 = off)", _, true, 0.0, true, 1.0);

	// Server-measured fake lag. Unlike the cl_cmdrate check this cannot be spoofed, it counts what
	// the server received. Still NOT proof: a buffering router produces the same gapless bursts,
	// so 2/3 (ban) is deliberately not the default. Read the observe log first. See Detect_FakeLag.
	gcv_fakelag         = CreateConVar("kevac_fakelag_action", "-1", "Fake lag (usercmds withheld then burst-delivered with zero loss): -1 disable, 0 log, 1 kick, 2 SourceMod ban, 3 SourceBans++ ban. Strong evidence but not an impossibility - do not set 2/3 without calibrating.", _, true, -1.0, true, 3.0);
	gcv_fakelag_burst   = CreateConVar("kevac_fakelag_burst", "6", "Usercmds processed in a single server tick before that counts as a burst.", _, true, 3.0, true, 32.0);
	gcv_fakelag_hits    = CreateConVar("kevac_fakelag_hits", "4", "Bursts required within a one-second window for that window to qualify.", _, true, 1.0, true, 64.0);
	gcv_fakelag_seconds = CreateConVar("kevac_fakelag_seconds", "5", "Consecutive qualifying seconds before the action fires.", _, true, 2.0, true, 60.0);
	gcv_fakelag_observe = CreateConVar("kevac_fakelag_observe", "0", "Log per-second burst/loss/choke telemetry for every player to KevAC.log. Observation only: never flags, alerts or punishes. (1 = on, 0 = off)", _, true, 0.0, true, 1.0);

	gcv_angle        = CreateConVar("kevac_angle_action", "3", "Angle clamp action for usercmd pitch outside +-89.5. This is a protocol violation. -1 disable, 0 log, 1 kick, 2 SourceMod ban, 3 SourceBans++ ban with SourceMod fallback.", _, true, -1.0, true, 3.0);
	gcv_angle_roll   = CreateConVar("kevac_angle_roll_action", "0", "Action for repeated roll-only usercmd anomalies. Roll is always clamped, but this defaults to log-only because movement plugins can author it. -1 disable, 0 log, 1 kick, 2 SourceMod ban, 3 SourceBans++ ban with SourceMod fallback.", _, true, -1.0, true, 3.0);
	gcv_angle_streak = CreateConVar("kevac_angle_streak", "3", "Matching pitch or roll anomalies required inside kevac_angle_window before action.", _, true, 3.0, true, 10.0);
	gcv_angle_window = CreateConVar("kevac_angle_window", "2.0", "Seconds in which repeated angle anomalies must occur before action.", _, true, 0.5, true, 10.0);
	gcv_angle_patch  = CreateConVar("kevac_angle_patch", "1", "Clamp malformed usercmd pitch/roll before the engine consumes it.", _, true, 0.0, true, 1.0);

	gcv_pattern      = CreateConVar("kevac_pattern_action", "0", "Input pattern: identical air-strafe input signatures repeated (heuristic; log until calibrated).");
	gcv_pattern_ticks= CreateConVar("kevac_pattern_ticks", "5", "Min airborne ticks for a phase to count.");
	gcv_pattern_repeats=CreateConVar("kevac_pattern_repeats", "5", "Identical phases in a row before flagging.");
	gcv_pattern_mouse= CreateConVar("kevac_pattern_minmouse", "30", "Min total mouse-x movement for a phase to count.");

	gcv_cheatvar     = CreateConVar("kevac_cheatvar_action", "3", "sv_cheats reported above the server value (near-deterministic). 3 uses SourceBans++ with SourceMod fallback.");
	gcv_cvarprobe    = CreateConVar("kevac_cvarprobe_action", "3", "Extended FCVAR_CHEAT client-cvar probe from cheat_convars.ini (near-deterministic vs basic DLLs). 3 uses SourceBans++ with SourceMod fallback.");
	gcv_usercmd       = CreateConVar("kevac_usercmd_action", "3", "Malformed usercmd header/button bits (protocol impossibility). 3 uses SourceBans++ with SourceMod fallback.");
	gcv_antiduck      = CreateConVar("kevac_antiduck_action", "3", "CS:GO anti-duck-delay: IN_BULLRUSH in a usercmd (protocol cheat flag). 3 uses SourceBans++ with SourceMod fallback.");
	gcv_futureticks   = CreateConVar("kevac_future_ticks", "1", "Set sv_max_usercmd_future_ticks when the engine exposes it. -1 preserves the server setting.", _, true, -1.0, true, 64.0);
	gcv_lerp          = CreateConVar("kevac_lerp_action", "0", "NoLerp/interp anomaly from server-observed m_fLerpTime (log until calibrated).");
	gcv_lerp_min      = CreateConVar("kevac_lerp_min_ms", "-1", "Optional minimum valid m_fLerpTime in ms; -1 disables this bound.", _, true, -1.0);
	gcv_lerp_max      = CreateConVar("kevac_lerp_max_ms", "105", "Maximum valid m_fLerpTime in ms; detector is log-only by default.", _, true, -1.0);

	gcv_mouseyaw     = CreateConVar("kevac_mouseyaw_action", "0", "Mouse-angle desync: yaw or pitch differs from raw mouse in a verified linear mouselook path (heuristic; log until calibrated). Excludes +strafe, turn keys, attacks, filtering, acceleration, joystick, and pitch limits.");
	gcv_mouseyaw_streak=CreateConVar("kevac_mouseyaw_streak", "30", "Yaw/pitch desync ticks per 100-tick window before the window trips (first trip re-queries mouse settings; a second trip within 60s flags).");
	gcv_mouseyaw_tol = CreateConVar("kevac_mouseyaw_tol", "3.0", "Allowed yaw or pitch error in degrees before a tick counts.");

	gcv_aimbot       = CreateConVar("kevac_aimbot_action", "0", "Aimbot: view snap onto an enemy while firing (heuristic; log until calibrated).");
	gcv_aimbot_delta = CreateConVar("kevac_aimbot_delta", "15", "Min yaw snap degrees to count.");
	gcv_aimbot_streak= CreateConVar("kevac_aimbot_streak", "5", "Snap-shots before flagging.");

	gcv_trigger      = CreateConVar("kevac_trigger_action", "0", "Triggerbot: attack on the exact tick crosshair reaches an enemy (heuristic; log until calibrated).");
	gcv_trigger_streak=CreateConVar("kevac_trigger_streak", "5", "Tick-perfect shots before flagging.");
	gcv_psilent      = CreateConVar("kevac_psilent_action", "0", "Silent aim/no-recoil: returned viewangle around an attack (log until calibrated).");
	gcv_psilent_delta= CreateConVar("kevac_psilent_delta", "1.0", "Minimum middle-command angle delta for a silent-aim candidate.", _, true, 0.1);
	gcv_psilent_streak=CreateConVar("kevac_psilent_streak", "5", "Returned-angle attack sequences before flagging.", _, true, 2.0);
	gcv_psilent_chain= CreateConVar("kevac_psilent_chain_ticks", "384", "Maximum ticks between silent-aim candidates in one streak.", _, true, 32.0);

	// BASH2 (Blacky's Anti-Strafehack) ports. Strafe timing deviation is the core
	// strafehack signal: a bot syncs turn and keypress with near-zero variance.
	gcv_strafe       = CreateConVar("kevac_strafe_action", "3", "Strafe timing sync (BASH2): -1 disable, 0 log, 1 kick, 2 SourceMod ban, 3 SourceBans++ ban with fallback. Acts only below kevac_strafe_dev_ban; higher deviations always log.");
	gcv_strafe_devban= CreateConVar("kevac_strafe_dev_ban", "0.4", "Standard deviation (over 50 strafes) at or below which the configured action fires.", _, true, 0.0, true, 0.8);
	gcv_strafe_identical=CreateConVar("kevac_strafe_identical", "20", "Consecutive identical turn/keypress offsets before the configured action.", _, true, 15.0, true, 50.0);
	gcv_gain         = CreateConVar("kevac_gain_action", "3", "Air-gain / strafes-per-jump statistics (BASH2): -1 disable, 0 log, 1 kick, 2 SourceMod ban, 3 SourceBans++ ban with fallback. Acts only on the BASH ban-grade combinations.");
	gcv_gain_spjban  = CreateConVar("kevac_gain_spj_ban", "4.7", "Strafes-per-jump at or above which the gain action fires.", _, true, 3.5);
	gcv_illegalmove  = CreateConVar("kevac_illegalmove_action", "3", "Impossible sidemove values / button-move mismatch (BASH2): -1 disable, 0 log, 1 kick, 2 SourceMod ban, 3 SourceBans++ ban with fallback. Acts only on the ban-grade impossible-sidemove path.");
	gcv_illegalmove_zero=CreateConVar("kevac_illegalmove_zero", "1", "Zero out movement values while a client sends impossible sidemove sequences (neutralizes strafehacks without kicking).", _, true, 0.0, true, 1.0);
	gcv_cmdrate      = CreateConVar("kevac_cmdrate_action", "0", "Slow usercmd rate (speedhack/lag-switch, BASH2): -1 disable, 0 log, 1 log + freeze movement until the rate recovers.", _, true, -1.0, true, 1.0);

	// Optional shavit-timer integration. A movement style whose special string
	// contains this tag is fully exempt from behavioral movement checks (for TAS,
	// segmented, or scripted-practice styles that legitimately produce bot-like input).
	gcv_bypass_tag   = CreateConVar("kevac_style_bypass_tag", "kevac_bypass", "If shavit is loaded, a style whose special string contains this tag skips all behavioral movement detectors. Protocol/DLL checks still apply.");
	gcv_teleport_hook= CreateConVar("kevac_teleport_hook", "1", "If DHooks is available, hook CBaseEntity::Teleport so every plugin teleport (not just trigger_teleport) grants movement grace. Reduces movement false positives.", _, true, 0.0, true, 1.0);
	// This raw DHooks route previously crashed the server the moment a client joined. The cvar is
	// kept so configuration survives, but KevAC refuses to attach until per-build offsets are
	// independently verified. All non-vtable detectors remain active.
	gcv_vtable_hooks = CreateConVar("kevac_vtable_hooks", "0", "Request raw vtable telemetry. KevAC blocks this route on the current unverified CS:GO build because attaching it crashed on player join. All other detectors stay active.", _, true, 0.0, true, 1.0);
	gcv_cmd_public   = CreateConVar("kevac_cmd_public", "0", "Allow non-admins to use kevac_menu/kevac_stats/kevac_admin/kevac_personal. 0 keeps detection evidence admin-only (recommended).", _, true, 0.0, true, 1.0);

	// Any change re-caches into the plain vars the detectors read (live rcon tuning).
	gcv_enable.AddChangeHook(OnAnyCvarChanged);        gcv_method.AddChangeHook(OnAnyCvarChanged);
	gcv_listener_update.AddChangeHook(OnAnyCvarChanged); gcv_listener_update_grace.AddChangeHook(OnAnyCvarChanged); gcv_listener_update_threshold.AddChangeHook(OnAnyCvarChanged);
	gcv_listener_maxsubs.AddChangeHook(OnAnyCvarChanged); gcv_listener_maxsubs_action.AddChangeHook(OnAnyCvarChanged);
	gcv_listener_consensus_min.AddChangeHook(OnAnyCvarChanged);
	gcv_listener_consensus_pct.AddChangeHook(OnAnyCvarChanged);
	gcv_vtable_hooks.AddChangeHook(OnVtableHooksChanged);
	gcv_bhop_ratio.AddChangeHook(OnAnyCvarChanged); gcv_bhop_ratio_window.AddChangeHook(OnAnyCvarChanged); gcv_bhop_ratio_pct.AddChangeHook(OnAnyCvarChanged);
	gcv_fullupdate_action.AddChangeHook(OnAnyCvarChanged); gcv_fullupdate_threshold.AddChangeHook(OnAnyCvarChanged); gcv_fullupdate_window.AddChangeHook(OnAnyCvarChanged);
	gcv_bantime.AddChangeHook(OnAnyCvarChanged);       gcv_preban_delay.AddChangeHook(OnAnyCvarChanged); gcv_notify.AddChangeHook(OnAnyCvarChanged);
	gcv_preban_preroll.AddChangeHook(OnAnyCvarChanged);
	gcv_bd_enable.AddChangeHook(OnAnyCvarChanged);     gcv_log.AddChangeHook(OnAnyCvarChanged);
	gcv_admin_immune.AddChangeHook(OnAnyCvarChanged);  gcv_ghostjump.AddChangeHook(OnAnyCvarChanged);
	gcv_ghost.AddChangeHook(OnAnyCvarChanged);         gcv_ghost_tol.AddChangeHook(OnAnyCvarChanged);
	gcv_ghost_streak.AddChangeHook(OnAnyCvarChanged);  gcv_synth.AddChangeHook(OnAnyCvarChanged);
	gcv_synth_ticks.AddChangeHook(OnAnyCvarChanged);   gcv_synth_tol.AddChangeHook(OnAnyCvarChanged);
	gcv_tick.AddChangeHook(OnAnyCvarChanged);          gcv_tick_regress.AddChangeHook(OnAnyCvarChanged);
	gcv_tick_streak.AddChangeHook(OnAnyCvarChanged);   gcv_tick_patch.AddChangeHook(OnAnyCvarChanged);
	gcv_tick_tolerance.AddChangeHook(OnAnyCvarChanged); gcv_tick_min_old.AddChangeHook(OnAnyCvarChanged);
	gcv_bhop.AddChangeHook(OnAnyCvarChanged);
	gcv_bhop_ground.AddChangeHook(OnAnyCvarChanged);   gcv_bhop_streak.AddChangeHook(OnAnyCvarChanged);
	gcv_scroll.AddChangeHook(OnAnyCvarChanged);        gcv_scroll_sample.AddChangeHook(OnAnyCvarChanged);
	gcv_scroll_jitter.AddChangeHook(OnAnyCvarChanged); gcv_ahk.AddChangeHook(OnAnyCvarChanged);
	gcv_scroll_pattern.AddChangeHook(OnAnyCvarChanged); gcv_scroll_pattern_repeats.AddChangeHook(OnAnyCvarChanged);
	gcv_scroll_pattern_jitter.AddChangeHook(OnAnyCvarChanged); gcv_scroll_pattern_maxinterval.AddChangeHook(OnAnyCvarChanged);
	gcv_scroll_profile_window.AddChangeHook(OnAnyCvarChanged); gcv_scroll_profile_perfect_pct.AddChangeHook(OnAnyCvarChanged);
	gcv_scroll_profile_min_presses.AddChangeHook(OnAnyCvarChanged); gcv_scroll_profile_press_pct.AddChangeHook(OnAnyCvarChanged);
	gcv_scroll_profile_same_pairs.AddChangeHook(OnAnyCvarChanged); gcv_scroll_profile_cadence_bursts.AddChangeHook(OnAnyCvarChanged);
	gcv_scroll_profile_minspeed.AddChangeHook(OnAnyCvarChanged);
	gcv_duckmacro.AddChangeHook(OnAnyCvarChanged);      gcv_duckmacro_repeats.AddChangeHook(OnAnyCvarChanged);
	gcv_duckmacro_jitter.AddChangeHook(OnAnyCvarChanged); gcv_duckmacro_maxinterval.AddChangeHook(OnAnyCvarChanged);
	gcv_duckmacro_outcomes.AddChangeHook(OnAnyCvarChanged); gcv_duckmacro_window.AddChangeHook(OnAnyCvarChanged);
	gcv_duckmacro_input.AddChangeHook(OnAnyCvarChanged); gcv_duckmacro_input_bursts.AddChangeHook(OnAnyCvarChanged); gcv_duckmacro_input_minspeed.AddChangeHook(OnAnyCvarChanged);
	gcv_hyperscroll.AddChangeHook(OnAnyCvarChanged);
	gcv_jumpbug.AddChangeHook(OnAnyCvarChanged);        gcv_jumpbug_streak.AddChangeHook(OnAnyCvarChanged);
	gcv_jumpbug_chain.AddChangeHook(OnAnyCvarChanged);  gcv_jumpbug_maxgap.AddChangeHook(OnAnyCvarChanged);
	gcv_jumpbug_minfall.AddChangeHook(OnAnyCvarChanged); gcv_jumpbug_timing.AddChangeHook(OnAnyCvarChanged);
	gcv_jumpbug_timing_repeats.AddChangeHook(OnAnyCvarChanged); gcv_jumpbug_timing_jitter.AddChangeHook(OnAnyCvarChanged); gcv_jumpbug_timing_maxduck.AddChangeHook(OnAnyCvarChanged);
	gcv_groundjumpbug.AddChangeHook(OnAnyCvarChanged);  gcv_groundjumpbug_streak.AddChangeHook(OnAnyCvarChanged);
	gcv_groundjumpbug_maxgap.AddChangeHook(OnAnyCvarChanged); gcv_groundjumpbug_chain.AddChangeHook(OnAnyCvarChanged); gcv_groundjumpbug_minspeed.AddChangeHook(OnAnyCvarChanged);
	gcv_groundjumpbug_minside.AddChangeHook(OnAnyCvarChanged); gcv_groundjumpbug_speedloss.AddChangeHook(OnAnyCvarChanged);
	gcv_groundjumpbug_timing.AddChangeHook(OnAnyCvarChanged);
	gcv_ahk_streak.AddChangeHook(OnAnyCvarChanged);    gcv_silent.AddChangeHook(OnAnyCvarChanged);
	gcv_silent_streak.AddChangeHook(OnAnyCvarChanged); gcv_knife.AddChangeHook(OnAnyCvarChanged);
	gcv_knife_range.AddChangeHook(OnAnyCvarChanged);   gcv_knife_cone.AddChangeHook(OnAnyCvarChanged);
	gcv_knife_ms.AddChangeHook(OnAnyCvarChanged);      gcv_knife_streak.AddChangeHook(OnAnyCvarChanged);
	gcv_latency.AddChangeHook(OnAnyCvarChanged);       gcv_latency_rate.AddChangeHook(OnAnyCvarChanged);
	gcv_angle.AddChangeHook(OnAnyCvarChanged);         gcv_angle_roll.AddChangeHook(OnAnyCvarChanged); gcv_angle_streak.AddChangeHook(OnAnyCvarChanged); gcv_angle_window.AddChangeHook(OnAnyCvarChanged); gcv_angle_patch.AddChangeHook(OnAnyCvarChanged); gcv_pattern.AddChangeHook(OnAnyCvarChanged);
	gcv_pattern_ticks.AddChangeHook(OnAnyCvarChanged); gcv_pattern_repeats.AddChangeHook(OnAnyCvarChanged);
	gcv_pattern_mouse.AddChangeHook(OnAnyCvarChanged); gcv_cheatvar.AddChangeHook(OnAnyCvarChanged);
	gcv_cvarprobe.AddChangeHook(OnAnyCvarChanged);     gcv_usercmd.AddChangeHook(OnAnyCvarChanged); gcv_antiduck.AddChangeHook(OnAnyCvarChanged); gcv_futureticks.AddChangeHook(OnAnyCvarChanged); gcv_lerp.AddChangeHook(OnAnyCvarChanged); gcv_lerp_min.AddChangeHook(OnAnyCvarChanged); gcv_lerp_max.AddChangeHook(OnAnyCvarChanged); gcv_mouseyaw.AddChangeHook(OnAnyCvarChanged);
	gcv_mouseyaw_streak.AddChangeHook(OnAnyCvarChanged); gcv_mouseyaw_tol.AddChangeHook(OnAnyCvarChanged);
	gcv_aimbot.AddChangeHook(OnAnyCvarChanged);        gcv_aimbot_delta.AddChangeHook(OnAnyCvarChanged);
	gcv_aimbot_streak.AddChangeHook(OnAnyCvarChanged); gcv_trigger.AddChangeHook(OnAnyCvarChanged);
	gcv_trigger_streak.AddChangeHook(OnAnyCvarChanged); gcv_psilent.AddChangeHook(OnAnyCvarChanged); gcv_psilent_delta.AddChangeHook(OnAnyCvarChanged); gcv_psilent_streak.AddChangeHook(OnAnyCvarChanged); gcv_psilent_chain.AddChangeHook(OnAnyCvarChanged);
	gcv_strafe.AddChangeHook(OnAnyCvarChanged);        gcv_strafe_devban.AddChangeHook(OnAnyCvarChanged);
	gcv_strafe_identical.AddChangeHook(OnAnyCvarChanged); gcv_gain.AddChangeHook(OnAnyCvarChanged);
	gcv_gain_spjban.AddChangeHook(OnAnyCvarChanged);   gcv_illegalmove.AddChangeHook(OnAnyCvarChanged);
	gcv_illegalmove_zero.AddChangeHook(OnAnyCvarChanged); gcv_cmdrate.AddChangeHook(OnAnyCvarChanged);
	gcv_bypass_tag.AddChangeHook(OnAnyCvarChanged);    gcv_teleport_hook.AddChangeHook(OnAnyCvarChanged);


	AutoExecConfig(true, "KevAC");
}

public void OnAnyCvarChanged(ConVar cv, const char[] oldVal, const char[] newVal)
{
	RefreshConfig();
	if (cv == gcv_teleport_hook && gcv_teleport_hook.BoolValue)
	{
		SetupTeleportHook();
	}
}

// The vtable gate needs more than a cache refresh: turning it on must build the
// hooks (they were skipped at load), and turning it off must tear them down so
// the crash-prone path stops immediately without a map change.
public void OnVtableHooksChanged(ConVar cv, const char[] oldVal, const char[] newVal)
{
	bool wasOn = bd_vtable_hooks;
	RefreshConfig();
	if (bd_vtable_hooks == wasOn)
		return;

#if defined _dhooks_included
	if (bd_vtable_hooks)
	{
		LogMessage("[KevAC] kevac_vtable_hooks enabled - checking whether raw vtable telemetry is validated for this build.");
		SetupFullUpdateHooks();
	}
	else
	{
		LogMessage("[KevAC] kevac_vtable_hooks disabled - removing the vtable route.");
		g_vtableHooksBlocked = false;
		for (int i = 1; i <= MaxClients; i++)
		{
			RemoveFullUpdateHook(i);
			RemoveListenerMessageHook(i);
		}
		delete g_hFullUpdateHook;
		delete g_hListenerMessageHook;
		delete g_hGetClientCall;
		delete g_hKevACGameConf;
		g_pBaseServer = Address_Null;
	}
#endif
}

void RefreshConfig()
{
	status         = gcv_enable.BoolValue;
	method         = gcv_method.IntValue;
	bd_listener_update_action = gcv_listener_update.IntValue;
	bd_listener_update_grace = gcv_listener_update_grace.IntValue;
	bd_listener_update_threshold = gcv_listener_update_threshold.IntValue;
	bd_listener_maxsubs = gcv_listener_maxsubs.IntValue;
	bd_listener_maxsubs_action = gcv_listener_maxsubs_action.IntValue;
	bd_listener_consensus_min = gcv_listener_consensus_min.IntValue;
	bd_listener_consensus_pct = gcv_listener_consensus_pct.IntValue;
	bd_vtable_hooks = gcv_vtable_hooks.BoolValue;
	bd_fullupdate_action = gcv_fullupdate_action.IntValue;
	bd_fullupdate_threshold = gcv_fullupdate_threshold.IntValue;
	bd_fullupdate_window = gcv_fullupdate_window.FloatValue;
	blocking_time  = gcv_bantime.IntValue;
	bd_preban_delay = gcv_preban_delay.IntValue;
	bd_preban_preroll = gcv_preban_preroll.IntValue;
	// Bit 8 used to broadcast detections to every player. Ignore it even when
	// an old generated cfg still contains it; all chat evidence is admin-only.
	iNotification  = gcv_notify.IntValue & 7;
	bd_enable      = gcv_bd_enable.BoolValue;
	bd_admin_immune= gcv_admin_immune.BoolValue;

	bd_ghostjump_action = gcv_ghostjump.IntValue;
	bd_ghost_action = gcv_ghost.IntValue;
	bd_ghost_tol    = gcv_ghost_tol.IntValue;
	bd_ghost_streak = gcv_ghost_streak.IntValue;

	bd_synthmove_action    = gcv_synth.IntValue;
	bd_synthmove_min_ticks = gcv_synth_ticks.IntValue;
	bd_synthmove_tol       = gcv_synth_tol.FloatValue;

	bd_tick_action    = gcv_tick.IntValue;
	bd_tick_regress   = gcv_tick_regress.IntValue;
	bd_tick_streak    = gcv_tick_streak.IntValue;
	bd_tick_patch     = gcv_tick_patch.BoolValue;
	bd_tick_tolerance = gcv_tick_tolerance.IntValue;
	bd_tick_min_old   = gcv_tick_min_old.IntValue;

	bd_bhop_action    = gcv_bhop.IntValue;
	bd_bhop_maxground = gcv_bhop_ground.IntValue;
	bd_bhop_streak    = gcv_bhop_streak.IntValue;
	bd_bhop_ratio_action = gcv_bhop_ratio.IntValue;
	bd_bhop_ratio_window = gcv_bhop_ratio_window.IntValue;
	bd_bhop_ratio_pct = gcv_bhop_ratio_pct.IntValue;

	bd_scroll_action    = gcv_scroll.IntValue;
	bd_scroll_sample    = gcv_scroll_sample.IntValue;
	bd_scroll_maxjitter = gcv_scroll_jitter.IntValue;
	bd_scroll_pattern_action = gcv_scroll_pattern.IntValue;
	bd_scroll_pattern_repeats = gcv_scroll_pattern_repeats.IntValue;
	bd_scroll_pattern_jitter = gcv_scroll_pattern_jitter.IntValue;
	bd_scroll_pattern_maxinterval = gcv_scroll_pattern_maxinterval.IntValue;
	bd_scroll_profile_window = gcv_scroll_profile_window.IntValue;
	bd_scroll_profile_perfect_pct = gcv_scroll_profile_perfect_pct.IntValue;
	bd_scroll_profile_min_presses = gcv_scroll_profile_min_presses.IntValue;
	bd_scroll_profile_press_pct = gcv_scroll_profile_press_pct.IntValue;
	bd_scroll_profile_same_pairs = gcv_scroll_profile_same_pairs.IntValue;
	bd_scroll_profile_cadence_bursts = gcv_scroll_profile_cadence_bursts.IntValue;
	bd_scroll_profile_minspeed = gcv_scroll_profile_minspeed.FloatValue;
	bd_duckmacro_action = gcv_duckmacro.IntValue;
	bd_duckmacro_repeats = gcv_duckmacro_repeats.IntValue;
	bd_duckmacro_jitter = gcv_duckmacro_jitter.IntValue;
	bd_duckmacro_maxinterval = gcv_duckmacro_maxinterval.IntValue;
	bd_duckmacro_outcomes = gcv_duckmacro_outcomes.IntValue;
	bd_duckmacro_input_action = gcv_duckmacro_input.IntValue;
	bd_duckmacro_input_bursts = gcv_duckmacro_input_bursts.IntValue;
	bd_duckmacro_input_minspeed = gcv_duckmacro_input_minspeed.FloatValue;
	bd_hyperscroll_action = gcv_hyperscroll.IntValue;
	bd_duckmacro_window = gcv_duckmacro_window.IntValue;
	bd_jumpbug_action = gcv_jumpbug.IntValue;
	bd_jumpbug_streak = gcv_jumpbug_streak.IntValue;
	bd_jumpbug_chain = gcv_jumpbug_chain.IntValue;
	bd_jumpbug_maxgap = gcv_jumpbug_maxgap.IntValue;
	bd_jumpbug_minfall = gcv_jumpbug_minfall.FloatValue;
	bd_jumpbug_timing_action = gcv_jumpbug_timing.IntValue;
	bd_jumpbug_timing_repeats = gcv_jumpbug_timing_repeats.IntValue;
	bd_jumpbug_timing_jitter = gcv_jumpbug_timing_jitter.IntValue;
	bd_jumpbug_timing_maxduck = gcv_jumpbug_timing_maxduck.IntValue;
	bd_groundjumpbug_action = gcv_groundjumpbug.IntValue;
	bd_groundjumpbug_streak = gcv_groundjumpbug_streak.IntValue;
	bd_groundjumpbug_maxgap = gcv_groundjumpbug_maxgap.IntValue;
	bd_groundjumpbug_chain = gcv_groundjumpbug_chain.IntValue;
	bd_groundjumpbug_minspeed = gcv_groundjumpbug_minspeed.FloatValue;
	bd_groundjumpbug_minside = gcv_groundjumpbug_minside.FloatValue;
	bd_groundjumpbug_speedloss = gcv_groundjumpbug_speedloss.FloatValue;
	bd_groundjumpbug_timing_action = gcv_groundjumpbug_timing.IntValue;
	if (bd_scroll_sample < 1) bd_scroll_sample = 1;
	else if (bd_scroll_sample > 32) bd_scroll_sample = 32;
	if (bd_scroll_profile_window < 24) bd_scroll_profile_window = 24;
	else if (bd_scroll_profile_window > KEVAC_SCROLL_PROFILE_MAX) bd_scroll_profile_window = KEVAC_SCROLL_PROFILE_MAX;
	if (bd_scroll_profile_same_pairs >= bd_scroll_profile_window)
		bd_scroll_profile_same_pairs = bd_scroll_profile_window - 1;

	bd_ahk_action = gcv_ahk.IntValue;
	bd_ahk_streak = gcv_ahk_streak.IntValue;
	bd_ahk_maxnet = gcv_ahk_maxnet.FloatValue;

	bd_silent_action = gcv_silent.IntValue;
	bd_silent_streak = gcv_silent_streak.IntValue;

	bd_knife_action      = gcv_knife.IntValue;
	bd_knife_range       = gcv_knife_range.FloatValue;
	bd_knife_cone        = gcv_knife_cone.FloatValue;
	bd_knife_reaction_ms = gcv_knife_ms.IntValue;
	bd_knife_streak      = gcv_knife_streak.IntValue;

	bd_latency_action  = gcv_latency.IntValue;
	bd_latency_cmdrate = gcv_latency_rate.IntValue;
	bd_latency_observe = gcv_latency_observe.IntValue;

	bd_fakelag_action  = gcv_fakelag.IntValue;
	bd_fakelag_burst   = gcv_fakelag_burst.IntValue;
	bd_fakelag_hits    = gcv_fakelag_hits.IntValue;
	bd_fakelag_seconds = gcv_fakelag_seconds.IntValue;
	bd_fakelag_observe = gcv_fakelag_observe.IntValue;

	bd_angle_action      = gcv_angle.IntValue;
	bd_angle_roll_action = gcv_angle_roll.IntValue;
	bd_angle_streak      = gcv_angle_streak.IntValue;
	bd_angle_window      = gcv_angle_window.FloatValue;
	bd_angle_patch       = gcv_angle_patch.BoolValue;

	bd_pattern_action   = gcv_pattern.IntValue;
	bd_pattern_minticks = gcv_pattern_ticks.IntValue;
	bd_pattern_repeats  = gcv_pattern_repeats.IntValue;
	bd_pattern_minmouse = gcv_pattern_mouse.IntValue;

	bd_cheatvar_action  = gcv_cheatvar.IntValue;
	bd_cvarprobe_action = gcv_cvarprobe.IntValue;
	bd_usercmd_action   = gcv_usercmd.IntValue;
	bd_antiduck_action  = gcv_antiduck.IntValue;
	bd_future_ticks     = gcv_futureticks.IntValue;
	bd_lerp_action      = gcv_lerp.IntValue;
	bd_lerp_min_ms      = gcv_lerp_min.FloatValue;
	bd_lerp_max_ms      = gcv_lerp_max.FloatValue;

	bd_mouseyaw_action = gcv_mouseyaw.IntValue;
	bd_mouseyaw_streak = gcv_mouseyaw_streak.IntValue;
	bd_mouseyaw_tol    = gcv_mouseyaw_tol.FloatValue;

	bd_aimbot_action = gcv_aimbot.IntValue;
	bd_aimbot_delta  = gcv_aimbot_delta.IntValue;
	bd_aimbot_streak = gcv_aimbot_streak.IntValue;

	bd_trigger_action = gcv_trigger.IntValue;
	bd_trigger_streak = gcv_trigger_streak.IntValue;
	bd_psilent_action = gcv_psilent.IntValue;
	bd_psilent_delta  = gcv_psilent_delta.FloatValue;
	bd_psilent_streak = gcv_psilent_streak.IntValue;
	bd_psilent_chain  = gcv_psilent_chain.IntValue;

	bd_strafe_action    = gcv_strafe.IntValue;
	bd_strafe_dev_ban   = gcv_strafe_devban.FloatValue;
	bd_strafe_identical = gcv_strafe_identical.IntValue;
	bd_gain_action      = gcv_gain.IntValue;
	bd_gain_spj_ban     = gcv_gain_spjban.FloatValue;
	bd_illegalmove_action = gcv_illegalmove.IntValue;
	bd_illegalmove_zero = gcv_illegalmove_zero.BoolValue;
	bd_cmdrate_action   = gcv_cmdrate.IntValue;
	gcv_bypass_tag.GetString(g_bypassTag, sizeof(g_bypassTag));

	ApplyFutureTickLimit();
}

// Kigen-AC uses this engine limit to reject commands too far ahead of the
// server. It is a server policy, not behavioral evidence, and is skipped on
// builds where the cvar does not exist.
void ApplyFutureTickLimit()
{
	if (bd_future_ticks >= 0 && g_cvMaxUsercmdFutureTicks != null)
		g_cvMaxUsercmdFutureTicks.IntValue = bd_future_ticks;
}

// Extended cheat-cvar probe list: FCVAR_CHEAT client cvars + their enforced default value.
void LoadCheatCvarList()
{
	if (g_cheatCvarNames == null)  g_cheatCvarNames  = new ArrayList(ByteCountToCells(64));
	if (g_cheatCvarValues == null) g_cheatCvarValues = new ArrayList(ByteCountToCells(64));
	g_cheatCvarNames.Clear();
	g_cheatCvarValues.Clear();

	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/kevac/cheat_convars.ini");
	File hFile = OpenFile(sPath, "r");
	if (hFile == null)
	{
		LogError("[KevAC] cheat_convars.ini not found (%s) - extended cvar probe disabled", sPath);
		return;
	}

	char line[128], name[64], val[64];
	while (hFile.ReadLine(line, sizeof(line)))
	{
		TrimString(line);
		if (line[0] != '"' && line[0] != '_' && !IsCharNumeric(line[0]) && !IsCharAlpha(line[0]))
			continue;
		int r = BreakString(line, name, sizeof(name));
		if (r == -1)
			continue;
		BreakString(line[r], val, sizeof(val));
		StripQuotes(name);
		StripQuotes(val);
		g_cheatCvarNames.PushString(name);
		g_cheatCvarValues.PushString(val);
	}
	hFile.Close();
}

// Extension listener path (native DLLs that register event listeners)
public void KevAC_OnCheatDetected(const int iClient)
{
	if (iClient < 1 || iClient > MaxClients)
		return;
	// The extension dispatches telemetry before this forward. If it has not done
	// so, its static signature has not been proven to be the live CLC handler.
	// Never punish from an unverified listener probe.
	if (!g_listenerTelemetrySeen[iClient])
	{
		LogError("[KevAC] Ignored unverified event-listener detection for client %d: no ListenEvents telemetry was observed.", iClient);
		return;
	}
	if (g_listenerBlacklistFlagged[iClient])
		return;
	g_listenerBlacklistFlagged[iClient] = true;

	if (IsClientInGame(iClient))
	{
		char evidence[128];
		if (g_listenerBlacklistedSubscriptions[iClient] > 0)
		{
			if (g_listenerBlacklistedEventNames[iClient][0] != '\0')
				FormatEx(evidence, sizeof(evidence), "blacklisted event(s): %s (%d among %d active subscriptions)", g_listenerBlacklistedEventNames[iClient], g_listenerBlacklistedSubscriptions[iClient], g_listenerActiveSubscriptions[iClient]);
			else
				FormatEx(evidence, sizeof(evidence), "%d blacklisted listener(s) among %d active subscriptions", g_listenerBlacklistedSubscriptions[iClient], g_listenerActiveSubscriptions[iClient]);
		}
		else
			strcopy(evidence, sizeof(evidence), "native event-listener registration detected");
		FlagBehavioral(iClient, method, "EventListener", evidence);
	}
	else
		bDetect[iClient] = true;
}

// Extension telemetry is sent before either listener forward. This describes
// the accepted CCLCMsg_ListenEvents mask, not a fake or client-side-only event.
public void KevAC_OnListenerTelemetry(const int iClient, const int activeSubscriptions, const int blacklistedSubscriptions)
{
	if (iClient < 1 || iClient > MaxClients)
		return;

	g_listenerActiveSubscriptions[iClient] = activeSubscriptions;
	g_listenerBlacklistedSubscriptions[iClient] = blacklistedSubscriptions;
	g_listenerBlacklistedEventNames[iClient][0] = '\0';
	if (blacklistedSubscriptions > 0 && GetFeatureStatus(FeatureType_Native, "KevAC_GetListenerBlacklistedEvents") == FeatureStatus_Available)
		KevAC_GetListenerBlacklistedEvents(iClient, g_listenerBlacklistedEventNames[iClient], sizeof(g_listenerBlacklistedEventNames[]));
	g_listenerTelemetrySeen[iClient] = true;
	if (activeSubscriptions > g_listenerPeakSubscriptions[iClient])
		g_listenerPeakSubscriptions[iClient] = activeSubscriptions;

	// The extension retains a compact fingerprint of the exact accepted event
	// mask. A peer mismatch is telemetry only, never an automatic punishment.
	if (GetFeatureStatus(FeatureType_Native, "KevAC_GetListenerMaskFingerprint") == FeatureStatus_Available)
	{
		g_listenerMaskFingerprint[iClient] = KevAC_GetListenerMaskFingerprint(iClient);
		EvaluateListenerMaskConsensus(iClient);
	}
	LogListenerAuditSnapshot(iClient, "verified listener mask", false);

	// Count-ceiling detection, independent of the blacklist and of whether FindListener resolves on
	// this build. A DLL adding ANY extra event subscription pushes the raw bit count above a retail
	// client's. Honors the post-join grace window so a client ramping subscriptions is not flagged.
	if (bd_listener_maxsubs <= 0 || bd_listener_maxsubs_action < 0 || g_listenerOversubFlagged[iClient])
		return;
	if (!IsClientInGame(iClient) || IsFakeClient(iClient))
		return;
	if (GetGameTime() - g_clientJoinTime[iClient] < float(bd_listener_update_grace))
		return;
	if (activeSubscriptions > bd_listener_maxsubs)
	{
		g_listenerOversubFlagged[iClient] = true;
		char evidence[128];
		FormatEx(evidence, sizeof(evidence), "%d network event subscriptions exceed the retail ceiling of %d (%d blacklisted)", activeSubscriptions, bd_listener_maxsubs, blacklistedSubscriptions);
		FlagBehavioral(iClient, bd_listener_maxsubs_action, "EventListener(oversubscribed)", evidence);
	}
}

// Compare only fully decoded masks. This is deliberately an admin-only
// diagnostic: clients may legitimately differ, whereas a blacklisted event,
// oversubscription, or a post-grace mask change has its own enforcement path.
void EvaluateListenerMaskConsensus(int client)
{
	if (!IsClientInGame(client) || IsFakeClient(client) || g_listenerMaskFingerprint[client] == 0)
		return;

	int hashes[MAXPLAYERS + 1];
	int counts[MAXPLAYERS + 1];
	int uniqueMasks = 0;
	int decodedClients = 0;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i) || !g_listenerTelemetrySeen[i] || g_listenerMaskFingerprint[i] == 0)
			continue;

		decodedClients++;
		int maskIndex = -1;
		for (int j = 0; j < uniqueMasks; j++)
		{
			if (hashes[j] == g_listenerMaskFingerprint[i])
			{
				maskIndex = j;
				break;
			}
		}
		if (maskIndex == -1)
		{
			hashes[uniqueMasks] = g_listenerMaskFingerprint[i];
			counts[uniqueMasks] = 0;
			maskIndex = uniqueMasks++;
		}
		counts[maskIndex]++;
	}

	if (decodedClients < bd_listener_consensus_min)
		return;

	int majorityIndex = 0;
	for (int i = 1; i < uniqueMasks; i++)
		if (counts[i] > counts[majorityIndex])
			majorityIndex = i;

	// Do not report without a clear peer baseline. A bare >50% split is not one: at 6/11 a single
	// disconnect flips which group is the majority and everyone on the losing side becomes an
	// outlier, which is what produced flag bursts across half the server. Require a supermajority.
	if (counts[majorityIndex] < 2
		|| counts[majorityIndex] * 100 < decodedClients * bd_listener_consensus_pct)
		return;

	if (g_listenerMaskFingerprint[client] == hashes[majorityIndex])
		return;
	// Report each distinct fingerprint at most once per client per session. The
	// old code cleared this whenever the client matched the majority, so a mask
	// that kept drifting in and out of the majority re-reported every time.
	if (g_listenerMaskOutlierFingerprint[client] == g_listenerMaskFingerprint[client])
		return;

	g_listenerMaskOutlierFingerprint[client] = g_listenerMaskFingerprint[client];
	char evidence[192];
	FormatEx(evidence, sizeof(evidence), "listener mask fingerprint %08X differs from the %d/%d decoded-client majority (%08X); telemetry only, no action", g_listenerMaskFingerprint[client], counts[majorityIndex], decodedClients, hashes[majorityIndex]);
	LogToFile("addons/sourcemod/logs/KevAC.log", "[KevAC] %N | EventListener(mask outlier) | %s", client, evidence);
	AlertAdmins(client, "EventListener(mask outlier)", evidence, false);
}

// Raw callbacks arrive before the engine applies a ListenEvents packet. They
// never authorize a punishment, but they prove whether this build's detour is
// reached at all. sm_kevac_ext also reads the extension's cumulative counters.
public void KevAC_OnListenerProbe(const int iClient, const int rawCalls, const int humanCalls)
{
	if (iClient < 0 || iClient > MaxClients)
		return;

	g_listenerRawCallbacks = rawCalls;
	g_listenerHumanCallbacks = humanCalls;
}

// Raised only when the extension sees a real change to the accepted listener
// mask. The first connection mask is not an update and map transitions are
// covered by the join grace window above.
public void KevAC_OnListenerUpdate(const int iClient)
{
	if (bd_listener_update_action < 0 || !g_listenerTelemetrySeen[iClient] || !IsClientInGame(iClient))
		return;

	if (GetGameTime() - g_clientJoinTime[iClient] >= float(bd_listener_update_grace))
	{
		g_listenerUpdateCount[iClient]++;
		char evidence[160];
		FormatEx(evidence, sizeof(evidence), "listener mask changed %d time(s) after join grace; %d active subscriptions", g_listenerUpdateCount[iClient], g_listenerActiveSubscriptions[iClient]);

		// The threshold is configurable. HnS defaults to one verified post-grace
		// change so a feature enabled mid-round is actionable immediately.
		int action = g_listenerUpdateCount[iClient] >= bd_listener_update_threshold ? bd_listener_update_action : NONE;
		FlagBehavioral(iClient, action, "EventListener(post-join update)", evidence);
	}
}

public void OnClientAuthorized(int iClient)
{
	if (iClient >= 1 && iClient <= MaxClients && bDetect[iClient] && IsClientInGame(iClient))
	{
		bDetect[iClient] = false;
		FlagBehavioral(iClient, method, "EventListener", "native event-listener registration detected before authorization");
	}
}

void IgnoreServerAuthoredMovement(int client, int ticks)
{
	if (client < 1 || client > MaxClients || !IsClientInGame(client))
		return;

	if (ticks < 1)
		ticks = 1;
	if (ticks > 32)
		ticks = 32;

	int until = GetGameTickCount() + ticks;
	if (until > g_movementIgnoreUntil[client])
		g_movementIgnoreUntil[client] = until;

	// A server-authorized movement edit cannot be part of a client cheat streak.
	g_jumpBugArmed[client] = false;
	g_jumpBugStreak[client] = 0;
	g_groundJumpBugArmed[client] = false;
	g_groundJumpBugStreak[client] = 0;
	return;
}

public any Native_IgnoreMovement(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	int ticks = (numParams >= 2) ? GetNativeCell(2) : 2;
	IgnoreServerAuthoredMovement(client, ticks);
	return 0;
}

bool IsMovementSuppressed(int client)
{
	return GetGameTickCount() <= g_movementIgnoreUntil[client];
}

bool IsNormalWalkMovement(int client)
{
	return GetEntityMoveType(client) == MOVETYPE_WALK
		&& GetEntProp(client, Prop_Send, "m_nWaterLevel") == 0;
}

bool IsServerAutoBhopEnabled()
{
	return g_cvServerAutoBhop != null && g_cvServerAutoBhop.BoolValue;
}

bool IsWaitCommandAllowed()
{
	return g_cvAllowWait != null && g_cvAllowWait.BoolValue;
}

// Tickcount patching must stand down briefly after legitimate map/server teleports.
public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client >= 1 && client <= MaxClients)
	{
		g_teleportGraceUntil[client] = GetGameTime() + 2.0;
		RefreshStyleInfo(client);
	}
	return Plugin_Continue;
}

public void OnTeleportTrigger(const char[] output, int caller, int activator, float delay)
{
	if (activator >= 1 && activator <= MaxClients && IsClientInGame(activator))
		g_teleportGraceUntil[activator] = GetGameTime() + 2.0;
}

// MovementAPI uses DHooks to identify engine-level ladder exits, jumpbugs and non-jump takeoffs.
// When that optional plugin is installed those are stronger facts than guessing from the next
// usercmd, so skip only the affected movement heuristics for a few ticks.
public void Movement_OnStopTouchGround(int client, bool jumped, bool ladderJump, bool jumpbug)
{
	if (ladderJump || jumpbug || !jumped)
		IgnoreServerAuthoredMovement(client, 4);
}

public void Movement_OnChangeMovetype(int client, MoveType oldMovetype, MoveType newMovetype)
{
	if (oldMovetype == MOVETYPE_LADDER || newMovetype == MOVETYPE_LADDER)
		IgnoreServerAuthoredMovement(client, 6);
}

public Action Timer_LerpScan(Handle timer)
{
	if (!status || !bd_enable || bd_lerp_action < 0)
		return Plugin_Continue;

	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client) || IsFakeClient(client) || !HasEntProp(client, Prop_Data, "m_fLerpTime"))
			continue;

		float lerpMs = GetEntPropFloat(client, Prop_Data, "m_fLerpTime") * 1000.0;
		if (lerpMs < 0.0)
			continue;

		char evidence[96];
		bool invalidLerp = false;
		if (lerpMs <= 0.1)
		{
			FormatEx(evidence, sizeof(evidence), "server m_fLerpTime=%.3fms (NoLerp candidate)", lerpMs);
			invalidLerp = true;
		}
		else if ((bd_lerp_min_ms >= 0.0 && lerpMs < bd_lerp_min_ms) || (bd_lerp_max_ms >= 0.0 && lerpMs > bd_lerp_max_ms))
		{
			FormatEx(evidence, sizeof(evidence), "server m_fLerpTime=%.3fms outside %.1f..%.1fms", lerpMs, bd_lerp_min_ms, bd_lerp_max_ms);
			invalidLerp = true;
		}

		if (invalidLerp && GetGameTime() - g_lerpLastFlag[client] >= 30.0)
		{
			g_lerpLastFlag[client] = GetGameTime();
			FlagBehavioral(client, bd_lerp_action, lerpMs <= 0.1 ? "NoLerp" : "InterpolationRange", evidence);
		}
	}
	return Plugin_Continue;
}

// Behavioral path setup
public void OnClientConnected(int client)
{
#if defined _dhooks_included
	g_listenerBlacklistFlagged[client] = false;
	if (bd_vtable_hooks && !g_vtableHooksBlocked && !IsFakeClient(client))
	{
		// The retail client sends its first listener mask during signon, before
		// it is in game. Attaching only at PutInServer misses that first mask -
		// the exact packet a pre-injected DLL registers its listeners in.
		RequestFrame(Frame_AttachListenerMessageHook, GetClientUserId(client));
	}
#endif
}

public void OnClientPutInServer(int client)
{
	// Preserve listener telemetry that arrived during signon via the early hook;
	// ResetClientState would otherwise wipe the evidence of the first mask.
	bool preSeen = g_listenerTelemetrySeen[client];
	bool preEarly = g_listenerHookEarly[client];
	int preActive = g_listenerActiveSubscriptions[client];
	int preBlack = g_listenerBlacklistedSubscriptions[client];
	int prePeak = g_listenerPeakSubscriptions[client];
	int preFingerprint = g_listenerMaskFingerprint[client];

	ResetClientState(client);

	g_listenerHookEarly[client] = preEarly;
	if (preSeen)
	{
		g_listenerTelemetrySeen[client] = true;
		g_listenerActiveSubscriptions[client] = preActive;
		g_listenerBlacklistedSubscriptions[client] = preBlack;
		g_listenerPeakSubscriptions[client] = prePeak;
		g_listenerMaskFingerprint[client] = preFingerprint;
		LogListenerAuditSnapshot(client, "initial listener mask", false);
	}

	if (!IsFakeClient(client))
	{
		// Delayed so the client is settled enough to answer a cvar query.
		if (bd_latency_action >= 0 || bd_latency_observe)
			CreateTimer(15.0, Timer_QueryLatencyOnJoin, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);

		// Listener packets can arrive before SourceMod considers the player fully
		// in game. Preserve that extension signal until it is safe to log and act.
		if (bDetect[client])
		{
			bDetect[client] = false;
			FlagBehavioral(client, method, "EventListener", "native event-listener registration detected before authorization");
		}

		SDKHook(client, SDKHook_Touch, Hook_OnTouch);
		SDKHook(client, SDKHook_OnTakeDamage, StabTrace_OnTakeDamage);
		SDKHook(client, SDKHook_OnTakeDamagePost, StabTrace_OnTakeDamagePost);
#if defined _dhooks_included
		if (g_bDhooks && g_hTeleportHook != null)
			DHookEntity(g_hTeleportHook, false, client);
		if (bd_vtable_hooks && !g_vtableHooksBlocked)
		{
			RequestFrame(Frame_AttachFullUpdateHook, GetClientUserId(client));
			RequestFrame(Frame_AttachListenerMessageHook, GetClientUserId(client));
		}
#endif
		RefreshStyleInfo(client);

		QueryClientConVar(client, "cl_forwardspeed", OnConVarQueried);
		QueryClientConVar(client, "cl_sidespeed", OnConVarQueried);
		QueryClientConVar(client, "m_side", OnConVarQueried);
		QueryClientConVar(client, "m_forward", OnConVarQueried);
		QueryClientConVar(client, "m_pitch", OnConVarQueried);
		QueryClientConVar(client, "cl_mouselook", OnConVarQueried);
		QueryClientConVar(client, "sv_autobunnyhopping", OnConVarQueried);
		QueryClientConVar(client, "sensitivity", OnConVarQueried);
		QueryClientConVar(client, "m_yaw", OnConVarQueried);
		QueryClientConVar(client, "m_rawinput", OnConVarQueried);
		QueryClientConVar(client, "m_filter", OnConVarQueried);
		QueryClientConVar(client, "m_customaccel", OnConVarQueried);
		QueryClientConVar(client, "joystick", OnConVarQueried);
		if (bd_cheatvar_action >= 0)
			QueryClientConVar(client, "sv_cheats", OnCheatVarQueried);
		if (bd_cvarprobe_action >= 0)
			StartCheatCvarProbe(client);

		if (g_joinArm != 0)
			StartProbe(client);
	}
}

// True if the client should be exempt from the sv_cheats / cheat-convar checks.
// Exempt via: global whitelist.ini, the dedicated convar_immune.ini, a ROOT ('z') admin,
// or a custom "kevac_convar_immunity" override grantable to any admin group.
bool IsConvarImmune(int client)
{
	char sAuthID[32];
	if (GetClientAuthId(client, AuthId_Steam2, sAuthID, sizeof(sAuthID)))
	{
		if (hWhiteList.FindString(sAuthID) != -1)
			return true;
		if (g_convarImmune != null && g_convarImmune.FindString(sAuthID) != -1)
			return true;
	}
	if (bd_admin_immune && CheckCommandAccess(client, "kevac_convar_immunity", ADMFLAG_ROOT, false))
		return true;
	return false;
}

void LoadConvarImmune()
{
	if (g_convarImmune == null) g_convarImmune = new ArrayList(ByteCountToCells(32));
	g_convarImmune.Clear();

	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/kevac/convar_immune.ini");
	File hFile = OpenFile(sPath, "r");
	if (hFile == null)
		return; // optional file

	char line[64];
	while (hFile.ReadLine(line, sizeof(line)))
	{
		TrimString(line);
		if (!line[0] || line[0] == '/')
			continue;
		g_convarImmune.PushString(line);
	}
	hFile.Close();
}

// Query every FCVAR_CHEAT cvar in the list; mismatch vs its default (with sv_cheats 0) = patched protection.
void StartCheatCvarProbe(int client)
{
	if (g_cheatCvarNames == null || IsConvarImmune(client))
		return;

	g_probeSentRound[client] = g_cheatCvarNames.Length;
	g_probeAnsweredRound[client] = 0;

	char name[64];
	for (int i = 0; i < g_cheatCvarNames.Length; i++)
	{
		g_cheatCvarNames.GetString(i, name, sizeof(name));
		QueryClientConVar(client, name, OnCheatCvarProbed);
	}
}

public void OnCheatCvarProbed(QueryCookie cookie, int client, ConVarQueryResult result, const char[] cvarName, const char[] cvarValue)
{
	if (client <= 0 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client) || bd_cvarprobe_action < 0)
		return;

	// Any reply - even NotFound - proves the query channel is not filtered.
	g_probeAnsweredRound[client]++;

	if (result != ConVarQuery_Okay || g_cheatCvarNames == null)
		return;
	if (g_cvSvCheats.IntValue != 0 || IsConvarImmune(client))
		return;

	int idx = g_cheatCvarNames.FindString(cvarName);
	if (idx == -1)
		return;

	char expected[64];
	g_cheatCvarValues.GetString(idx, expected, sizeof(expected));

	// String and float compare (handles "0" vs "0.0"); mismatch on an FCVAR_CHEAT cvar = cheat.
	if (!StrEqual(cvarValue, expected) && StringToFloat(cvarValue) != StringToFloat(expected))
	{
		char ev[128];
		FormatEx(ev, sizeof(ev), "%s = %s (default %s) with sv_cheats 0", cvarName, cvarValue, expected);
		FlagBehavioral(client, bd_cvarprobe_action, "CheatConVar", ev);
	}
}

// A DLL hooking the netchannel to hide cheat cvars blocks the query replies. One blocked reply
// is noise; a client answering nothing across two full probe rounds while others answer is a
// strong evasion tell. Evidence only - a block is not deterministic.
void EvaluateCvarProbeRound(int client)
{
	if (bd_cvarprobe_action < 0 || g_probeSentRound[client] < 5)
		return;

	int sent = g_probeSentRound[client];
	g_probeSentRound[client] = 0; // consume the round; a skipped probe is not silence

	if (g_probeAnsweredRound[client] == 0)
	{
		g_probeSilentRounds[client]++;
		if (g_probeSilentRounds[client] >= 2 && !g_probeBlockFlagged[client])
		{
			g_probeBlockFlagged[client] = true;
			char ev[128];
			FormatEx(ev, sizeof(ev), "%d cheat-cvar queries unanswered across %d probe rounds (netchannel filter?)", sent * g_probeSilentRounds[client], g_probeSilentRounds[client]);
			FlagBehavioral(client, NONE, "CheatConVar(blocked queries)", ev);
		}
	}
	else
	{
		g_probeSilentRounds[client] = 0;
	}
}

// sv_cheats is FCVAR_REPLICATED: a legit client mirrors the server's value. A client
// reporting sv_cheats 1 while the server is 0 has patched cvar protection = cheat.
public Action Timer_CheatVarScan(Handle timer)
{
	if (!status)
		return Plugin_Continue;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i))
		{
			EvaluateCvarProbeRound(i);
			if (bd_cheatvar_action >= 0)
				QueryClientConVar(i, "sv_cheats", OnCheatVarQueried);
			if (bd_cvarprobe_action >= 0)
				StartCheatCvarProbe(i);

			// Sensitivity/m_yaw are not userinfo cvars, so the server is never told
			// when they change. Refresh the mouse-model cache to avoid stale-value
			// mouse-yaw false positives (streamable.com/yufnep class of kick).
			QueryClientConVar(i, "sensitivity", OnConVarQueried);
			QueryClientConVar(i, "m_yaw", OnConVarQueried);
			QueryClientConVar(i, "m_side", OnConVarQueried);
			QueryClientConVar(i, "m_forward", OnConVarQueried);
			QueryClientConVar(i, "m_pitch", OnConVarQueried);
			QueryClientConVar(i, "cl_mouselook", OnConVarQueried);
			QueryClientConVar(i, "m_rawinput", OnConVarQueried);
			QueryClientConVar(i, "m_filter", OnConVarQueried);
			QueryClientConVar(i, "m_customaccel", OnConVarQueried);
			QueryClientConVar(i, "joystick", OnConVarQueried);
		}
	}
	return Plugin_Continue;
}

public void OnCheatVarQueried(QueryCookie cookie, int client, ConVarQueryResult result, const char[] cvarName, const char[] cvarValue)
{
	if (client <= 0 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client) || bd_cheatvar_action < 0)
		return;
	if (IsConvarImmune(client))
		return;

	if (result != ConVarQuery_Okay)
	{
		// A blocked query is suspicious but not deterministic - log only, never action.
		LogToFile("addons/sourcemod/logs/KevAC.log", "[KevAC] %N - sv_cheats query blocked (result %d)", client, result);
		return;
	}

	// Value above the server's is impossible for a legit replicated cvar = unlocked cvars.
	int serverCheats = g_cvSvCheats.IntValue;
	if (StringToInt(cvarValue) > serverCheats)
	{
		char ev[64];
		FormatEx(ev, sizeof(ev), "sv_cheats client=%s server=%d", cvarValue, serverCheats);
		FlagBehavioral(client, bd_cheatvar_action, "CheatVarUnlock", ev);
	}
}

public void OnClientSettingsChanged(int client)
{
	if (!IsClientInGame(client) || IsFakeClient(client))
		return;

	// These values feed movement and mouse-yaw validation.  Refresh every cache
	// when the client changes settings so old sensitivity or movement limits do
	// not produce a false behavioral match.
	QueryClientConVar(client, "cl_forwardspeed", OnConVarQueried);
	QueryClientConVar(client, "cl_sidespeed", OnConVarQueried);
	QueryClientConVar(client, "m_side", OnConVarQueried);
	QueryClientConVar(client, "m_forward", OnConVarQueried);
	QueryClientConVar(client, "m_pitch", OnConVarQueried);
	QueryClientConVar(client, "cl_mouselook", OnConVarQueried);
	QueryClientConVar(client, "sensitivity", OnConVarQueried);
	QueryClientConVar(client, "m_yaw", OnConVarQueried);
	if (bd_latency_action >= 0 || bd_latency_observe)
		QueryClientConVar(client, "cl_cmdrate", OnLatencyQueried);
}

// OnClientSettingsChanged only fires when a player CHANGES a setting, so anyone
// who connects with their cvars already set was never asked. Ask once on join
// too, otherwise the check silently skips the exact case it is meant to catch.
public Action Timer_QueryLatencyOnJoin(Handle timer, any userid)
{
	int client = GetClientOfUserId(userid);
	if (client < 1 || !IsClientInGame(client) || IsFakeClient(client))
		return Plugin_Stop;
	if (bd_latency_action >= 0 || bd_latency_observe)
		QueryClientConVar(client, "cl_cmdrate", OnLatencyQueried);
	return Plugin_Stop;
}

void ResetClientState(int client)
{
	// A client can re-enter the server lifecycle without a process restart.
	// Remove old raw hooks before wiping their IDs, otherwise an early or prior
	// attachment becomes unreachable and a later frame stacks another hook.
	RemoveFullUpdateHook(client);
	RemoveListenerMessageHook(client);

	ResetListenerPacketTelemetry(client);
	g_listenerBlacklistFlagged[client] = false;
	g_punishmentDispatched[client] = false;
	g_listenerHookEarly[client] = false;
	g_probeSentRound[client] = 0;
	g_probeAnsweredRound[client] = 0;
	g_probeSilentRounds[client] = 0;
	g_probeBlockFlagged[client] = false;
	g_bhopWindowJumps[client] = 0;
	g_bhopWindowPerfect[client] = 0;
	g_prevMouseDx2[client] = 0;
	g_ahkAltStreak[client] = 0;
	g_fullUpdateHookId[client] = -1;
	g_fullUpdateClientPtr[client] = Address_Null;
	g_fullUpdateCalls[client] = 0;
	g_fullUpdateRequests[client] = 0;
	g_fullUpdateWindowStart[client] = 0.0;
	g_fwdSpeed[client]       = 450;
	g_sideSpeed[client]      = 450;
	g_mSide[client]          = 0.0;
	g_mForward[client]       = 0.0;
	g_mPitch[client]         = 0.0;
	g_sens[client]           = 0.0;
	g_myaw[client]           = 0.0;
	g_mouseyawStreak[client] = 0;
	g_lastButtons[client]    = 0;
	g_wasOnGround[client]    = false;
	g_viewStillTicks[client] = 0;
	g_lastMouseActiveTick[client] = 0;
	g_physicsPending[client] = false;
	g_physicsSnapshotTick[client] = 0;
	g_physicsSnapshotButtons[client] = 0;
	g_physicsSnapshotPrevJump[client] = false;
	g_ghostTicks[client]     = 0;
	g_synthTicks[client]     = 0;
	g_teleportGraceUntil[client] = GetGameTime() + 2.0;
	g_lastTick[client] = 0;
	g_tickStreak[client] = 0;
	g_tickLastServerTick[client] = 0;
	g_backtrackPrevTick[client] = 0;
	g_backtrackRawTick[client] = 0;
	g_backtrackPatchStreak[client] = 0;
	g_backtrackPatchLastServerTick[client] = 0;
	g_usercmdLastFlag[client] = 0.0;
	g_lerpLastFlag[client] = 0.0;
	g_groundTicks[client]    = 0;
	g_perfectStreak[client]  = 0;
	g_lastJumpTick[client]   = 0;
	g_jumpDeltaCount[client] = 0;
	g_scrollPatternMin[client] = 0;
	g_scrollPatternMax[client] = 0;
	g_scrollPatternRepeats[client] = 0;
	g_scrollCadenceBursts[client] = 0;
	g_scrollJitteredBursts[client] = 0;
	g_scrollProfileCount[client] = 0;
	for (int i = 0; i < KEVAC_SCROLL_PROFILE_MAX; i++)
	{
		g_scrollProfilePresses[client][i] = 0;
		g_scrollProfilePerfect[client][i] = 0;
	}
	g_lastDuckTick[client] = 0;
	g_duckPatternMin[client] = 0;
	g_duckPatternMax[client] = 0;
	g_duckPatternRepeats[client] = 0;
	g_duckCadenceBursts[client] = 0;
	g_duckCadenceLastTick[client] = 0;
	g_duckMouseStrafeBursts[client] = 0;
	g_duckJitteredBursts[client] = 0;
	g_prerollHead[client] = 0;
	g_prerollCount[client] = 0;
	g_duckMacroOutcomes[client] = 0;
	g_duckMacroOutcomeLastTick[client] = 0;
	g_jumpBugArmed[client] = false;
	g_jumpBugArmTick[client] = 0;
	g_jumpBugFallSpeed[client] = 0.0;
	g_jumpBugStreak[client] = 0;
	g_jumpBugLastTick[client] = 0;
	g_duckAirTicks[client] = 0;
	g_jumpBugDuckPressTick[client] = 0;
	g_jumpBugArmDuckToJump[client] = -1;
	g_jumpBugTimingLastDelay[client] = -1;
	g_jumpBugTimingStreak[client] = 0;
	g_groundJumpBugArmed[client] = false;
	g_groundJumpBugArmTick[client] = 0;
	g_groundJumpBugArmSpeed[client] = 0.0;
	g_groundJumpBugStreak[client] = 0;
	g_groundJumpBugLastTick[client] = 0;
	g_groundJumpBugDuckPressTick[client] = 0;
	g_groundJumpBugArmDuckToJump[client] = -1;
	g_gjbTimingLastDelay[client] = -1;
	g_gjbTimingStreak[client] = 0;
	g_movementIgnoreUntil[client] = 0;
	g_showAlerts[client] = true;
	g_lastMouseDx[client]    = 0;
	g_ahkStreak[client]      = 0;
	g_lastSide[client]       = 0.0;
	g_silentStreak[client]   = 0;
	g_stabAvailSince[client] = -1;
	g_knifeStreak[client]    = 0;
	g_inAir[client]          = false;
	g_phaseTicks[client]     = 0;
	g_phaseHash[client]      = 0;
	g_phaseCheck[client]     = 0;
	g_phaseMouse[client]     = 0;
	g_prevPhaseHash[client]  = 0;
	g_prevPhaseCheck[client] = 0;
	g_patternRepeat[client]  = 0;
	g_prevAngles[client]     = view_as<float>({ 0.0, 0.0, 0.0 });
	g_cmdAngleHistory[client][0] = view_as<float>({ 0.0, 0.0, 0.0 });
	g_cmdAngleHistory[client][1] = view_as<float>({ 0.0, 0.0, 0.0 });
	g_cmdNumberHistory[client][0] = 0;
	g_cmdNumberHistory[client][1] = 0;
	g_cmdButtonHistory[client][0] = 0;
	g_cmdButtonHistory[client][1] = 0;
	g_aimbotStreak[client]   = 0;
	g_lastHitGroup[client]   = 0;
	g_onTargetTicks[client]  = 0;
	g_prevOnTargetTicks[client] = 1;
	g_triggerStreak[client]  = 0;
	g_psilentStreak[client]  = 0;
	g_psilentLastTick[client] = 0;

	g_lastAttackEdgeTick[client] = 0;
	g_knifeLastFastTick[client] = 0;
	g_airJumpPresses[client] = 0;
	g_angleFlagCount[client] = 0;
	g_angleFlagWindow[client] = 0.0;
	g_angleRollFlagCount[client] = 0;
	g_angleRollFlagWindow[client] = 0.0;
	g_mouseyawWindowTicks[client] = 0;
	g_mouseyawBadTicks[client] = 0;
	g_mouseyawRetestUntil[client] = 0.0;
	g_mRawInput[client] = -1;
	g_mFilter[client] = -1;
	g_mCustomAccel[client] = -1;
	g_mJoystick[client] = -1;
	g_mMouseLook[client] = -1;
	g_sensChanges[client] = 0;
	g_stabTraceInputCmd[client] = 0;
	g_stabTraceInputButtons[client] = 0;
	g_stabTraceInputObservedAt[client] = 0.0;
	g_stabTraceLastFinalAttackButtons[client] = 0;
	g_stabTraceInputSerial[client] = 0;
	g_stabTraceLastDamageTime[client] = 0.0;
	g_stabTracePendingSerial[client] = 0;
	g_stabTracePendingAttackerUserId[client] = 0;
	g_stabTracePendingPostDamage[client] = false;
	g_stabTracePendingPlayerHurt[client] = false;

	g_bashCmdNum[client] = 0;
	g_bashYawDiff[client] = 0.0;
	for (int i = 0; i < 4; i++)
	{
		g_bashPressTick[client][i] = 0;
		g_bashReleaseTick[client][i] = 0;
		g_bashPressRecorded[client][i] = -1;
		g_bashReleaseRecorded[client][i] = -1;
	}
	g_bashTurnDir[client] = 0;
	g_bashTurnTick[client] = 0;
	g_bashStopTurnTick[client] = 0;
	g_bashIsTurning[client] = false;
	g_bashTurnRecStart[client] = -1;
	g_bashTurnRecEnd[client] = -1;
	g_bashStartFrame[client] = 0;
	g_bashStartFilled[client] = 0;
	g_bashStartLastDiff[client] = 0;
	g_bashStartIdentical[client] = 0;
	g_bashStartRecTick[client] = -1;
	g_bashEndFrame[client] = 0;
	g_bashEndFilled[client] = 0;
	g_bashEndLastDiff[client] = 0;
	g_bashEndIdentical[client] = 0;
	g_bashEndRecTick[client] = -1;

	g_gainJumps[client] = 0;
	g_gainRaw[client] = 0.0;
	g_gainStrafeTicks[client] = 0;
	g_gainYawTicks[client] = 0;
	g_gainStrafes[client] = 0;
	g_gainGroundTicks[client] = 0;
	g_gainFirstSix[client] = false;
	g_touchWall[client] = false;
	g_touchRotating[client] = false;
	g_lastGainPct[client] = 0.0;
	g_lastSpj[client] = 0.0;

	g_invalidBtnMove[client] = 0;
	g_lastInvalidBtnMove[client] = 0;
	g_invalidReason[client] = 0;
	g_illegalSidemove[client] = 0;
	g_lastIllegalSidemove[client] = 0;
	g_illegalYawChanges[client] = 0;

	g_cmdCount[client] = 0;
	g_cmdBadSeconds[client] = 0;
	g_cmdWindowStart[client] = 0.0;
	g_flLastCmdnum[client] = 0;
	g_flMissing[client] = 0;
	g_flLastTick[client] = 0;
	g_flThisTickRun[client] = 0;
	g_flBurstMax[client] = 0;
	g_flBurstHits[client] = 0;
	g_flBadSeconds[client] = 0;
	g_flServerBurstTick[client] = 0;
	g_flWindowStart[client] = 0.0;
	g_cmdSavedMoveType[client] = MOVETYPE_WALK;
	g_cmdFrozen[client] = false;

	g_styleBypass[client] = false;
	g_styleAutobhop[client] = false;
	g_alertsPersonal[client] = false;
	ApplyAlertCookies(client);
}

public void OnConVarQueried(QueryCookie cookie, int client, ConVarQueryResult result, const char[] cvarName, const char[] cvarValue)
{
	if (client <= 0 || result != ConVarQuery_Okay)
		return;

	int val = StringToInt(cvarValue);

	if (StrEqual(cvarName, "cl_forwardspeed", false) && val > 0)
		g_fwdSpeed[client] = val;
	else if (StrEqual(cvarName, "cl_sidespeed", false) && val > 0)
		g_sideSpeed[client] = val;
	else if (StrEqual(cvarName, "sensitivity", false))
	{
		float sens = StringToFloat(cvarValue);
		if (g_sens[client] > 0.0 && FloatAbs(sens - g_sens[client]) > 0.0001)
		{
			// BASH2 tell: repeated mid-game sensitivity swaps are a classic
			// anticheat-model evasion. Evidence only; the cache refresh is the fix.
			g_sensChanges[client]++;
			if (g_sensChanges[client] > 1 && IsClientInGame(client))
				LogToFile("addons/sourcemod/logs/KevAC.log", "[KevAC] %N changed sensitivity mid-game (%.4f -> %.4f, change #%d)", client, g_sens[client], sens, g_sensChanges[client]);
		}
		g_sens[client] = sens;
	}
	else if (StrEqual(cvarName, "m_yaw", false))
		g_myaw[client] = StringToFloat(cvarValue);
	else if (StrEqual(cvarName, "m_side", false))
		g_mSide[client] = StringToFloat(cvarValue);
	else if (StrEqual(cvarName, "m_forward", false))
		g_mForward[client] = StringToFloat(cvarValue);
	else if (StrEqual(cvarName, "m_pitch", false))
		g_mPitch[client] = StringToFloat(cvarValue);
	else if (StrEqual(cvarName, "m_rawinput", false))
		g_mRawInput[client] = (StringToFloat(cvarValue) != 0.0) ? 1 : 0;
	else if (StrEqual(cvarName, "m_filter", false))
		g_mFilter[client] = (StringToFloat(cvarValue) != 0.0) ? 1 : 0;
	else if (StrEqual(cvarName, "m_customaccel", false))
		g_mCustomAccel[client] = val;
	else if (StrEqual(cvarName, "joystick", false))
		g_mJoystick[client] = (StringToFloat(cvarValue) != 0.0) ? 1 : 0;
	else if (StrEqual(cvarName, "cl_mouselook", false))
		g_mMouseLook[client] = (StringToFloat(cvarValue) != 0.0) ? 1 : 0;
}

public void OnLatencyQueried(QueryCookie cookie, int client, ConVarQueryResult result, const char[] cvarName, const char[] cvarValue)
{
	if (client <= 0 || !IsClientInGame(client))
		return;

	// Calibration baseline. A non-Okay result is logged too: a client that
	// refuses or cannot answer a cvar query is itself worth seeing, and the
	// action path below silently discards those.
	if (bd_latency_observe)
	{
		char sAuthID[32];
		if (!GetClientAuthId(client, AuthId_Steam2, sAuthID, sizeof(sAuthID)))
			strcopy(sAuthID, sizeof(sAuthID), "UNKNOWN");
		LogToFile("addons/sourcemod/logs/KevAC.log",
			"[KevAC] [latency-observe] %N (%s) cl_cmdrate=%s result=%d",
			client, sAuthID, (result == ConVarQuery_Okay) ? cvarValue : "<no answer>", view_as<int>(result));
	}

	if (result != ConVarQuery_Okay || bd_latency_action < 0)
		return;

	// Exact-match heuristic. Whether a reported value this far from the server
	// tickrate is actually anomalous is the open question the observe log above
	// exists to answer - do not raise the action until that data says so.
	if (StringToInt(cvarValue) == bd_latency_cmdrate)
	{
		char ev[64];
		FormatEx(ev, sizeof(ev), "cl_cmdrate reported as %d", bd_latency_cmdrate);
		FlagBehavioral(client, bd_latency_action, "HideLatency", ev);
	}
}

// Reset only outcome/streak state during server-authored movement grace. A teleport launch must
// not count as a perfect hop, but periodic +duck / +scroll INPUT evidence is preserved: the
// server did not author the client's button edges, and wiping them blinded gstrafe detection.
void ResetMovementOutcomeStreaks(int client)
{
	g_groundTicks[client] = 0;
	g_perfectStreak[client] = 0;
	g_airJumpPresses[client] = 0;
	g_bhopWindowJumps[client] = 0;
	g_bhopWindowPerfect[client] = 0;
	g_scrollProfileCount[client] = 0;
	g_duckMacroOutcomes[client] = 0;
	g_duckMacroOutcomeLastTick[client] = 0;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if (client < 1 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client) || !IsPlayerAlive(client))
		return Plugin_Continue;

	int nowTick = GetGameTickCount();
	bool onGround = (GetEntityFlags(client) & FL_ONGROUND) != 0;
	bool walking = (GetEntityMoveType(client) == MOVETYPE_WALK);
	StabTraceCaptureInput(client, buttons, cmdnum, tickcount);

	bool modified = false;

	if (bd_enable && status)
	{
		// Protocol / DLL / engine-integrity checks always run: they are not movement
		// heuristics and a scripted-practice style is no excuse for a malformed cmd.
		Detect_UserCmdIntegrity(client, buttons, cmdnum, tickcount);
		Detect_AntiDuckDelay(client, buttons, modified);
		int rawTickcount = tickcount;
		if (bd_tick_action >= 0 || bd_tick_patch)
		{
			StoreBacktrackTick(client, rawTickcount);
			PatchBacktrackTick(client, buttons, tickcount, modified);
			if (bd_tick_action >= 0)
				Detect_CmdTick(client, buttons, rawTickcount);
		}
		Detect_AngleClamp(client, buttons, cmdnum, tickcount, mouse, angles, modified);
		Detect_FakeLag(client, cmdnum);
		Detect_CmdRate(client);

		// Behavioral movement/aim heuristics: skipped for shavit styles tagged with
		// the bypass string (TAS/segmented/scripted-practice legitimately look botted).
		if (!IsBehavioralBypassed(client))
		{
			bool ignoreServerMovement = IsMovementSuppressed(client);
			// +strafe is deliberately not a usercmd button; the client converts mouse deltas into
			// forward/sidemove instead. Retain that relationship so legitimate mouse strafing is never
			// classified as synthetic movement while injected movement still is.
			// The per-cmd move match alone misses +strafe when sidemove clamps at cl_sidespeed or a
			// movement key is held. +strafe also consumes the mouse, so both view axes stay frozen while
			// deltas keep arriving - which never happens under mouselook, so that combination counts too.
			if (FloatAbs(NormalizeAngle(angles[1] - g_prevAngles[client][1])) > 0.01
				|| FloatAbs(angles[0] - g_prevAngles[client][0]) > 0.01)
				g_viewStillTicks[client] = 0;
			else if (g_viewStillTicks[client] < 10000)
				g_viewStillTicks[client]++;
			if (mouse[0] != 0 || mouse[1] != 0)
				g_lastMouseActiveTick[client] = nowTick;
			bool plusStrafe = g_viewStillTicks[client] >= 4 && nowTick - g_lastMouseActiveTick[client] <= 4;
			bool mouseStrafe = IsMouseStrafeInput(client, buttons, vel, mouse) || plusStrafe;
			CapturePhysicsOutcomeInput(client, buttons, onGround, ignoreServerMovement);
			Detect_GhostStrafe(client, buttons, vel, mouseStrafe, angles, mouse);
			if (!ignoreServerMovement && !g_bPhysHooks)
				Detect_GhostJump(client, buttons, onGround);
			Detect_SynthMove(client, vel, walking, onGround, mouseStrafe, angles, mouse);

			// Input-cadence trackers read client button edges, not server-authored movement, so they run
			// even while outcome checks are suppressed. A plugin granting grace via KevAC_IgnoreMovement
			// must not erase periodic +duck / +scroll input evidence.
			Detect_Scroll(client, buttons, nowTick);
			Detect_DuckMacro(client, buttons, nowTick, mouseStrafe, angles, mouse);

			if (!ignoreServerMovement)
			{
				Detect_Bhop(client, buttons, onGround);
				Detect_JumpBug(client, buttons, onGround, nowTick);
				Detect_GroundJumpBug(client, buttons, vel, onGround, nowTick);
			}
			else
			{
				ResetMovementOutcomeStreaks(client);
			}
			Detect_AHKStrafe(client, mouse[0], onGround);
			Detect_MouseYaw(client, buttons, mouse, angles, mouseStrafe);
			Detect_SilentStrafe(client, vel[1], mouseStrafe);
			Detect_InputPattern(client, mouse, buttons, vel, onGround);
			Detect_Knife(client, buttons, angles, nowTick);
			Detect_AimTrigger(client, buttons, angles);
			Detect_PSilent(client, buttons, angles, cmdnum, nowTick);

			// BASH2 ports
			UpdateBashTracking(client, buttons, angles, onGround, walking);
			Detect_IllegalMove(client, buttons, vel, modified, mouseStrafe);
			Detect_Gain(client, vel, angles, buttons, onGround);
		}
	}

	if (client == g_testTarget)
		TestLogTick(client, buttons, vel, angles, mouse, cmdnum, tickcount, onGround);
	PreBanLogTick(client, buttons, vel, angles, mouse, cmdnum, tickcount, onGround);

	g_lastButtons[client] = buttons;
	g_wasOnGround[client] = onGround;
	g_prevAngles[client] = angles;
	StoreCmdHistory(client, buttons, angles, cmdnum);
	g_bashCmdNum[client]++;
	return modified ? Plugin_Changed : Plugin_Continue;
}

// This post forward observes the final command state after all RunCmd plugins
// have had their chance to modify it. Comparing it with the pre-forward sample
// above exposes a primary-to-secondary knife conversion without changing it.
public void OnPlayerRunCmdPost(int client, int buttons, int impulse, const float vel[3], const float angles[3], int weapon, int subtype, int cmdnum, int tickcount, int seed, const int mouse[2])
{
	if (client < 1 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client) || !IsPlayerAlive(client))
		return;

	StabTraceCaptureFinalInput(client, buttons, cmdnum, tickcount, angles);
}

// Temporary knife-stab trace
// A trace is intentionally limited to one admin-selected attacker. This keeps a
// normal server quiet and gives one ghost-stab report a compact, ordered record.
int GetStabTraceTarget()
{
	if (g_stabTraceTargetUserId == 0)
		return 0;

	if (GetGameTime() >= g_stabTraceUntil)
	{
		StopStabTrace("duration expired");
		return 0;
	}

	int target = GetClientOfUserId(g_stabTraceTargetUserId);
	if (target < 1 || !IsClientInGame(target) || IsFakeClient(target))
	{
		StopStabTrace("target unavailable");
		return 0;
	}
	return target;
}

void StopStabTrace(const char[] reason)
{
	if (g_stabTraceTargetUserId != 0)
		LogToFile("addons/sourcemod/logs/KevAC-stabtrace.log", "[KevAC-StabTrace] session=%d stopped (%s)", g_stabTraceSessionId, reason);

	g_stabTraceTargetUserId = 0;
	g_stabTraceUntil = 0.0;
	g_stabTraceSessionId++;
}

public Action Timer_StabTraceExpire(Handle timer, any sessionId)
{
	if (sessionId == g_stabTraceSessionId)
		StopStabTrace("duration expired");
	return Plugin_Stop;
}

bool GetStabTraceWeaponState(int client, char[] weaponName, int maxlen, float &nextPrimary, float &nextSecondary)
{
	weaponName[0] = '\0';
	nextPrimary = 0.0;
	nextSecondary = 0.0;

	int activeWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if (activeWeapon <= MaxClients || !IsValidEntity(activeWeapon))
		return false;

	GetEntityClassname(activeWeapon, weaponName, maxlen);
	if (HasEntProp(activeWeapon, Prop_Send, "m_flNextPrimaryAttack"))
		nextPrimary = GetEntPropFloat(activeWeapon, Prop_Send, "m_flNextPrimaryAttack");
	if (HasEntProp(activeWeapon, Prop_Send, "m_flNextSecondaryAttack"))
		nextSecondary = GetEntPropFloat(activeWeapon, Prop_Send, "m_flNextSecondaryAttack");

	return StrContains(weaponName, "knife", false) != -1;
}

bool IsStabTraceKnifeDamage(int attacker, char[] weaponName, int maxlen)
{
	weaponName[0] = '\0';
	if (attacker < 1 || attacker > MaxClients || !IsClientInGame(attacker))
		return false;
	GetClientWeapon(attacker, weaponName, maxlen);
	return StrContains(weaponName, "knife", false) != -1;
}

void StabTraceCaptureInput(int client, int buttons, int cmdnum, int tickcount)
{
	if (GetStabTraceTarget() != client)
		return;

	char weaponName[64];
	float nextPrimary, nextSecondary;
	if (!GetStabTraceWeaponState(client, weaponName, sizeof(weaponName), nextPrimary, nextSecondary))
	{
		g_stabTraceInputCmd[client] = 0;
		return;
	}

	g_stabTraceInputCmd[client] = cmdnum;
	g_stabTraceInputButtons[client] = buttons;
	g_stabTraceInputObservedAt[client] = GetGameTime();
	if ((buttons & (IN_ATTACK | IN_ATTACK2)) == 0)
		return;

	float now = GetGameTime();
	float primaryRemaining = nextPrimary - now;
	float secondaryRemaining = nextSecondary - now;
	if (primaryRemaining < 0.0)
		primaryRemaining = 0.0;
	if (secondaryRemaining < 0.0)
		secondaryRemaining = 0.0;
	LogToFile("addons/sourcemod/logs/KevAC-stabtrace.log", "[KevAC-StabTrace] session=%d INPUT attacker=%N cmd=%d tick=%d primary=%d secondary=%d buttons=0x%X weapon=%s next_primary=%.3f ready_primary=%.3f next_secondary=%.3f ready_secondary=%.3f",
		g_stabTraceSessionId, client, cmdnum, tickcount, (buttons & IN_ATTACK) != 0, (buttons & IN_ATTACK2) != 0, buttons, weaponName, nextPrimary, primaryRemaining, nextSecondary, secondaryRemaining);
}

void StabTraceCaptureFinalInput(int client, int buttons, int cmdnum, int tickcount, const float angles[3])
{
	if (GetStabTraceTarget() != client)
		return;

	char weaponName[64];
	float nextPrimary, nextSecondary;
	if (!GetStabTraceWeaponState(client, weaponName, sizeof(weaponName), nextPrimary, nextSecondary))
	{
		g_stabTraceLastFinalAttackButtons[client] = 0;
		return;
	}

	int rawButtons = 0;
	if (g_stabTraceInputCmd[client] == cmdnum)
		rawButtons = g_stabTraceInputButtons[client];
	if ((rawButtons & (IN_ATTACK | IN_ATTACK2)) == 0 && (buttons & (IN_ATTACK | IN_ATTACK2)) == 0)
	{
		g_stabTraceLastFinalAttackButtons[client] = 0;
		return;
	}

	float now = GetGameTime();
	float primaryRemaining = nextPrimary - now;
	float secondaryRemaining = nextSecondary - now;
	if (primaryRemaining < 0.0)
		primaryRemaining = 0.0;
	if (secondaryRemaining < 0.0)
		secondaryRemaining = 0.0;
	bool converted = (rawButtons & IN_ATTACK) != 0 && (rawButtons & IN_ATTACK2) == 0
		&& (buttons & IN_ATTACK) == 0 && (buttons & IN_ATTACK2) != 0;
	LogToFile("addons/sourcemod/logs/KevAC-stabtrace.log", "[KevAC-StabTrace] session=%d FINAL attacker=%N cmd=%d tick=%d raw_primary=%d raw_secondary=%d final_primary=%d final_secondary=%d converted_primary_to_secondary=%d raw_buttons=0x%X final_buttons=0x%X weapon=%s next_primary=%.3f ready_primary=%.3f next_secondary=%.3f ready_secondary=%.3f",
		g_stabTraceSessionId, client, cmdnum, tickcount, (rawButtons & IN_ATTACK) != 0, (rawButtons & IN_ATTACK2) != 0, (buttons & IN_ATTACK) != 0, (buttons & IN_ATTACK2) != 0, converted, rawButtons, buttons, weaponName, nextPrimary, primaryRemaining, nextSecondary, secondaryRemaining);
	int finalAttackButtons = buttons & (IN_ATTACK | IN_ATTACK2);
	bool attackEdge = finalAttackButtons != 0 && (g_stabTraceLastFinalAttackButtons[client] & (IN_ATTACK | IN_ATTACK2)) == 0;
	g_stabTraceLastFinalAttackButtons[client] = finalAttackButtons;
	if (attackEdge)
		StabTraceScheduleAttackOutcome(client, cmdnum, tickcount, angles);
	g_stabTraceInputCmd[client] = 0;
}

// A swing can fail before damage is applied, for example because the trace is
// out of range or the selected attack is still cooling down. Record that branch
// separately from a damage hook that later fails to emit player_hurt.
void StabTraceScheduleAttackOutcome(int client, int cmdnum, int tickcount, const float angles[3])
{
	int inputSerial = ++g_stabTraceInputSerial[client];
	float issuedAt = g_stabTraceInputObservedAt[client];
	if (issuedAt <= 0.0)
		issuedAt = GetGameTime();
	char reconciliation[1024];
	BuildStabTraceReconciliation(client, tickcount, angles, reconciliation, sizeof(reconciliation));
	DataPack pack;
	CreateDataTimer(0.50, Timer_StabTraceAttackOutcome, pack, TIMER_FLAG_NO_MAPCHANGE);
	pack.WriteCell(g_stabTraceSessionId);
	pack.WriteCell(GetClientUserId(client));
	pack.WriteCell(inputSerial);
	pack.WriteCell(cmdnum);
	pack.WriteCell(tickcount);
	pack.WriteFloat(issuedAt);
	pack.WriteString(reconciliation);
}

public Action Timer_StabTraceAttackOutcome(Handle timer, DataPack pack)
{
	pack.Reset();
	int sessionId = pack.ReadCell();
	int attackerUserId = pack.ReadCell();
	int inputSerial = pack.ReadCell();
	int cmdnum = pack.ReadCell();
	int tickcount = pack.ReadCell();
	float issuedAt = pack.ReadFloat();
	char reconciliation[1024];
	pack.ReadString(reconciliation, sizeof(reconciliation));
	if (sessionId != g_stabTraceSessionId || g_stabTraceTargetUserId != attackerUserId)
		return Plugin_Stop;

	int attacker = GetClientOfUserId(attackerUserId);
	if (attacker < 1 || g_stabTraceLastDamageTime[attacker] < issuedAt)
	{
		LogToFile("addons/sourcemod/logs/KevAC-stabtrace.log", "[KevAC-StabTrace] session=%d ATTACK_OUTCOME input_serial=%d attacker_userid=%d cmd=%d tick=%d damage_pre=no (the final attack did not reach KevAC's damage hook: inspect the recorded cooldowns, range, and any earlier hook/engine rejection)",
			sessionId, inputSerial, attackerUserId, cmdnum, tickcount);
		LogToFile("addons/sourcemod/logs/KevAC-stabtrace.log", "[KevAC-StabTrace] session=%d RECONCILIATION input_serial=%d server_snapshot=%s",
			sessionId, inputSerial, reconciliation);
	}
	return Plugin_Stop;
}

// This is diagnostics only. It records the server's immediate view of a missed
// swing without replaying or broadening the engine's knife trace, so it cannot
// create duplicate, through-wall, or out-of-range damage.
void BuildStabTraceReconciliation(int client, int commandTick, const float angles[3], char[] output, int maxlen)
{
	float eye[3], origin[3], viewForward[3], rayEnd[3], rayHitPosition[3];
	GetClientEyePosition(client, eye);
	GetClientAbsOrigin(client, origin);
	GetAngleVectors(angles, viewForward, NULL_VECTOR, NULL_VECTOR);
	rayEnd[0] = eye[0] + viewForward[0] * 96.0;
	rayEnd[1] = eye[1] + viewForward[1] * 96.0;
	rayEnd[2] = eye[2] + viewForward[2] * 96.0;

	Handle trace = TR_TraceRayFilterEx(eye, rayEnd, MASK_SHOT, RayType_EndPoint, StabTraceTraceFilter, client);
	int viewHit = TR_DidHit(trace) ? TR_GetEntityIndex(trace) : -1;
	TR_GetEndPosition(rayHitPosition, trace);
	delete trace;

	char viewHitName[64];
	StabTraceDescribeEntity(viewHit, viewHitName, sizeof(viewHitName));
	char groundName[64];
	int groundEntity = GetEntPropEnt(client, Prop_Send, "m_hGroundEntity");
	StabTraceDescribeEntity(groundEntity, groundName, sizeof(groundName));

	float maxUnlag = -1.0;
	ConVar maxUnlagCvar = FindConVar("sv_maxunlag");
	if (maxUnlagCvar != null)
		maxUnlag = maxUnlagCvar.FloatValue;
	float lerp = HasEntProp(client, Prop_Data, "m_fLerpTime") ? GetEntPropFloat(client, Prop_Data, "m_fLerpTime") : -1.0;
	float laggedMovement = HasEntProp(client, Prop_Send, "m_flLaggedMovementValue") ? GetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue") : -1.0;
	float teleportGrace = g_teleportGraceUntil[client] - GetGameTime();
	if (teleportGrace < 0.0)
		teleportGrace = 0.0;

	int nearest[3] = {-1, -1, -1};
	float nearestDistance[3] = {999999.0, 999999.0, 999999.0};
	for (int target = 1; target <= MaxClients; target++)
	{
		if (target == client || !IsClientInGame(target) || !IsPlayerAlive(target) || GetClientTeam(target) == GetClientTeam(client))
			continue;

		float targetOrigin[3];
		GetClientAbsOrigin(target, targetOrigin);
		float distance = GetVectorDistance(origin, targetOrigin);
		for (int slot = 0; slot < 3; slot++)
		{
			if (distance < nearestDistance[slot])
			{
				for (int move = 2; move > slot; move--)
				{
					nearest[move] = nearest[move - 1];
					nearestDistance[move] = nearestDistance[move - 1];
				}
				nearest[slot] = target;
				nearestDistance[slot] = distance;
				break;
			}
		}
	}

	char nearby[512];
	nearby[0] = '\0';
	for (int slot = 0; slot < 3; slot++)
	{
		int target = nearest[slot];
		if (target < 1)
			continue;

		float targetOrigin[3], targetPoint[3], toTarget[3];
		GetClientAbsOrigin(target, targetOrigin);
		targetPoint[0] = targetOrigin[0];
		targetPoint[1] = targetOrigin[1];
		targetPoint[2] = targetOrigin[2];
		targetPoint[2] += 36.0;
		MakeVectorFromPoints(eye, targetPoint, toTarget);
		NormalizeVector(toTarget, toTarget);
		float forwardDot = GetVectorDotProduct(viewForward, toTarget);
		bool lineOfSight = StabTraceHasLineOfSight(client, target, eye, targetPoint);

		char separator[3];
		if (nearby[0] == '\0')
			separator[0] = '\0';
		else
			strcopy(separator, sizeof(separator), "; ");
		char entry[160];
		FormatEx(entry, sizeof(entry), "%s%N d=%.1f dot=%.2f los=%d", separator, target, nearestDistance[slot], forwardDot, lineOfSight);
		StrCat(nearby, sizeof(nearby), entry);
	}
	if (nearby[0] == '\0')
		strcopy(nearby, sizeof(nearby), "none");

	MoveType moveType = GetEntityMoveType(client);
	FormatEx(output, maxlen, "cmd_age=%d maxunlag=%.3f lerp=%.3f net_ms(in=%.1f out=%.1f) loss_pct(in=%.1f out=%.1f) choke_pct(in=%.1f out=%.1f) rate=%d movement(type=%d ladder=%d lagged=%.2f ground=%s teleport_grace=%.3f) view_ray96(hit=%s dist=%.1f) attacker_origin=(%.1f,%.1f,%.1f) nearby=[%s]",
		GetGameTickCount() - commandTick, maxUnlag, lerp,
		GetClientAvgLatency(client, NetFlow_Incoming) * 1000.0, GetClientAvgLatency(client, NetFlow_Outgoing) * 1000.0,
		GetClientAvgLoss(client, NetFlow_Incoming) * 100.0, GetClientAvgLoss(client, NetFlow_Outgoing) * 100.0,
		GetClientAvgChoke(client, NetFlow_Incoming) * 100.0, GetClientAvgChoke(client, NetFlow_Outgoing) * 100.0,
		GetClientDataRate(client), view_as<int>(moveType), moveType == MOVETYPE_LADDER, laggedMovement, groundName, teleportGrace,
		viewHitName, GetVectorDistance(eye, rayHitPosition), origin[0], origin[1], origin[2], nearby);
}

bool StabTraceHasLineOfSight(int attacker, int target, const float start[3], const float end[3])
{
	Handle trace = TR_TraceRayFilterEx(start, end, MASK_SHOT, RayType_EndPoint, StabTraceTraceFilter, attacker);
	int hit = TR_DidHit(trace) ? TR_GetEntityIndex(trace) : -1;
	delete trace;
	return hit == target;
}

public bool StabTraceTraceFilter(int entity, int contentsMask, any data)
{
	return entity != data;
}

void StabTraceDescribeEntity(int entity, char[] description, int maxlen)
{
	if (entity >= 1 && entity <= MaxClients && IsClientInGame(entity))
	{
		FormatEx(description, maxlen, "player:%N", entity);
		return;
	}
	if (entity > MaxClients && IsValidEntity(entity) && GetEntityClassname(entity, description, maxlen))
		return;
	if (entity == 0)
		strcopy(description, maxlen, "world");
	else
		strcopy(description, maxlen, "none");
}

public Action StabTrace_OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damageType)
{
	if (GetStabTraceTarget() != attacker || victim < 1 || victim > MaxClients || !IsClientInGame(victim))
		return Plugin_Continue;

	char weaponName[64];
	if (!IsStabTraceKnifeDamage(attacker, weaponName, sizeof(weaponName)))
		return Plugin_Continue;

	int serial = ++g_stabTraceDamageSerial;
	g_stabTraceLastDamageTime[attacker] = GetGameTime();
	g_stabTracePendingSerial[victim] = serial;
	g_stabTracePendingAttackerUserId[victim] = GetClientUserId(attacker);
	g_stabTracePendingPostDamage[victim] = false;
	g_stabTracePendingPlayerHurt[victim] = false;
	LogToFile("addons/sourcemod/logs/KevAC-stabtrace.log", "[KevAC-StabTrace] session=%d DAMAGE_PRE serial=%d attacker=%N victim=%N weapon=%s requested_damage=%.2f type=0x%X KevAC_result=Plugin_Continue",
		g_stabTraceSessionId, serial, attacker, victim, weaponName, damage, damageType);

	DataPack pack;
	CreateDataTimer(0.35, Timer_StabTraceDamageOutcome, pack, TIMER_FLAG_NO_MAPCHANGE);
	pack.WriteCell(g_stabTraceSessionId);
	pack.WriteCell(serial);
	pack.WriteCell(GetClientUserId(attacker));
	pack.WriteCell(GetClientUserId(victim));
	return Plugin_Continue;
}

public void StabTrace_OnTakeDamagePost(int victim, int attacker, int inflictor, float damage, int damageType)
{
	if (GetStabTraceTarget() != attacker || victim < 1 || victim > MaxClients || !IsClientInGame(victim))
		return;

	char weaponName[64];
	if (!IsStabTraceKnifeDamage(attacker, weaponName, sizeof(weaponName)))
		return;

	g_stabTracePendingPostDamage[victim] = true;
	LogToFile("addons/sourcemod/logs/KevAC-stabtrace.log", "[KevAC-StabTrace] session=%d DAMAGE_POST serial=%d attacker=%N victim=%N weapon=%s final_damage=%.2f type=0x%X victim_health=%d",
		g_stabTraceSessionId, g_stabTracePendingSerial[victim], attacker, victim, weaponName, damage, damageType, GetClientHealth(victim));
}

public void Event_PlayerHurt_StabTrace(Event event, const char[] name, bool dontBroadcast)
{
	int victim = GetClientOfUserId(event.GetInt("userid"));
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	if (GetStabTraceTarget() != attacker || victim < 1 || victim > MaxClients || !IsClientInGame(victim))
		return;

	char weaponName[64];
	event.GetString("weapon", weaponName, sizeof(weaponName));
	if (StrContains(weaponName, "knife", false) == -1)
		return;

	g_stabTracePendingPlayerHurt[victim] = true;
	LogToFile("addons/sourcemod/logs/KevAC-stabtrace.log", "[KevAC-StabTrace] session=%d PLAYER_HURT serial=%d attacker=%N victim=%N weapon=%s damage_health=%d victim_health=%d victim_armor=%d hitgroup=%d",
		g_stabTraceSessionId, g_stabTracePendingSerial[victim], attacker, victim, weaponName, event.GetInt("dmg_health"), event.GetInt("health"), event.GetInt("armor"), event.GetInt("hitgroup"));
}

public Action Timer_StabTraceDamageOutcome(Handle timer, DataPack pack)
{
	pack.Reset();
	int sessionId = pack.ReadCell();
	int serial = pack.ReadCell();
	int attackerUserId = pack.ReadCell();
	int victimUserId = pack.ReadCell();
	if (sessionId != g_stabTraceSessionId || g_stabTraceTargetUserId != attackerUserId)
		return Plugin_Stop;

	int victim = GetClientOfUserId(victimUserId);
	if (victim < 1 || g_stabTracePendingSerial[victim] != serial || g_stabTracePendingAttackerUserId[victim] != attackerUserId)
		return Plugin_Stop;

	char postResult[8];
	char hurtResult[8];
	if (g_stabTracePendingPostDamage[victim])
		strcopy(postResult, sizeof(postResult), "yes");
	else
		strcopy(postResult, sizeof(postResult), "no");
	if (g_stabTracePendingPlayerHurt[victim])
		strcopy(hurtResult, sizeof(hurtResult), "yes");
	else
		strcopy(hurtResult, sizeof(hurtResult), "no");
	LogToFile("addons/sourcemod/logs/KevAC-stabtrace.log", "[KevAC-StabTrace] session=%d OUTCOME serial=%d victim=%N damage_post=%s player_hurt=%s%s",
		sessionId, serial, victim, postResult, hurtResult, (!g_stabTracePendingPostDamage[victim] || !g_stabTracePendingPlayerHurt[victim]) ? " (the damage was rejected or did not produce a health event after KevAC returned Plugin_Continue)" : "");
	g_stabTracePendingSerial[victim] = 0;
	g_stabTracePendingAttackerUserId[victim] = 0;
	g_stabTracePendingPostDamage[victim] = false;
	g_stabTracePendingPlayerHurt[victim] = false;
	return Plugin_Stop;
}

// PhysHooks runs OnPostPlayerThinkFunctions after every player has been simulated.
// Capturing the input here and checking the resulting origin/velocity there makes a
// normal jump outcome distinguishable from a slope, ladder, surf, or plugin launch.
void CapturePhysicsOutcomeInput(int client, int buttons, bool onGround, bool ignoreServerMovement)
{
	g_physicsPending[client] = false;
#if defined _physhooks_included
	if (!g_bPhysHooks || ignoreServerMovement || !onGround || !IsNormalWalkMovement(client))
		return;

	g_physicsPending[client] = true;
	g_physicsSnapshotTick[client] = GetGameTickCount();
	g_physicsSnapshotButtons[client] = buttons;
	g_physicsSnapshotPrevJump[client] = (g_lastButtons[client] & IN_JUMP) != 0;
#endif
}

#if defined _physhooks_included
public void OnPostPlayerThinkFunctions()
{
	if (!g_bPhysHooks || !bd_enable || !status || bd_ghostjump_action < 0)
		return;

	int nowTick = GetGameTickCount();
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!g_physicsPending[client])
			continue;

		// A skipped simulation frame is not evidence. Drop stale snapshots rather
		// than comparing a command with an unrelated later physics result.
		if (nowTick - g_physicsSnapshotTick[client] > 1)
		{
			g_physicsPending[client] = false;
			continue;
		}

		g_physicsPending[client] = false;
		if (!IsClientInGame(client) || !IsPlayerAlive(client) || IsMovementSuppressed(client) || !IsNormalWalkMovement(client))
			continue;

		bool onGround = (GetEntityFlags(client) & FL_ONGROUND) != 0;
		if (onGround)
			continue;

		float velocity[3];
		GetEntPropVector(client, Prop_Data, "m_vecVelocity", velocity);
		float hspeed = SquareRoot(velocity[0] * velocity[0] + velocity[1] * velocity[1]);
		bool hasJumpInput = (g_physicsSnapshotButtons[client] & IN_JUMP) != 0 || g_physicsSnapshotPrevJump[client];

		// This narrow CS:GO launch envelope intentionally excludes fast surf/ramp
		// exits and ladders. It is an outcome check, not a cadence heuristic.
		if (!hasJumpInput && hspeed <= 300.0 && velocity[2] >= 285.0 && velocity[2] <= 310.0)
		{
			char evidence[112];
			FormatEx(evidence, sizeof(evidence), "post-physics takeoff vz=%.1f with no IN_JUMP in the simulated command", velocity[2]);
			FlagBehavioral(client, bd_ghostjump_action, "GhostJump(post-physics input mismatch)", evidence);
		}
	}
}
#endif

// The Source client does not expose +strafe in CUserCmd::buttons. It applies m_side * mousedx to
// sidemove, and while held, -m_forward * mousedy to forwardmove. Treat that exact reported
// relationship as legitimate. A DLL is still caught if it writes movement with no raw mouse.
bool IsMouseStrafeInput(int client, int buttons, const float wishvel[3], const int mouse[2])
{
	// This helper covers the reported no-key +strafe mode only. Normal movement
	// buttons already explain their own move values in the affected detectors.
	int moveMask = IN_FORWARD | IN_BACK | IN_MOVELEFT | IN_MOVERIGHT | IN_LEFT | IN_RIGHT;
	if (buttons & moveMask)
		return false;

	bool hasSide = mouse[0] != 0 && g_mSide[client] != 0.0;
	bool hasForward = mouse[1] != 0 && g_mForward[client] != 0.0;
	if (!hasSide && !hasForward)
		return false;

	float sideTolerance = hasSide ? FloatAbs(g_mSide[client]) * 2.0 : 3.0;
	if (sideTolerance < 3.0)
		sideTolerance = 3.0;
	float forwardTolerance = hasForward ? FloatAbs(g_mForward[client]) * 2.0 : 3.0;
	if (forwardTolerance < 3.0)
		forwardTolerance = 3.0;

	bool sideMatches = !hasSide || FloatAbs(wishvel[1] - g_mSide[client] * float(mouse[0])) <= sideTolerance;
	bool forwardMatches = !hasForward || FloatAbs(wishvel[0] + g_mForward[client] * float(mouse[1])) <= forwardTolerance;
	if (!sideMatches || !forwardMatches)
		return false;

	if (!hasSide && FloatAbs(wishvel[1]) > forwardTolerance)
		return false;
	if (!hasForward && FloatAbs(wishvel[0]) > sideTolerance)
		return false;
	return true;
}

// ---- Ghost strafe: move value with no matching source input (near-deterministic) ----
// Keyboard movement supplies a matching button; +strafe has the verified mouse-to-move
// relationship above. A significant move with neither source is injected movement.
void Detect_GhostStrafe(int client, int buttons, const float vel[3], bool mouseStrafe, const float angles[3], const int mouse[2])
{
	if (bd_ghost_action < 0)
		return;

	// Any button that can legitimately produce move values, including +strafe/+left/+right
	// (turn keys become sidemove under +strafe) so movement-server players never false-flag.
	int moveMask = IN_FORWARD | IN_BACK | IN_MOVELEFT | IN_MOVERIGHT | IN_LEFT | IN_RIGHT;
	float tol = float(bd_ghost_tol);
	bool moving = FloatAbs(vel[0]) > tol || FloatAbs(vel[1]) > tol;

	if (!moving || (buttons & moveMask) || mouseStrafe)
	{
		g_ghostTicks[client] = 0;
		return;
	}

	g_ghostTicks[client]++;
	if (g_ghostTicks[client] >= bd_ghost_streak)
	{
		char ev[192];
		FormatEx(ev, sizeof(ev), "move fwd=%.0f side=%.0f with no direction key for %d ticks (dyaw=%.2f dpitch=%.2f dx=%d dy=%d viewstill=%dt)",
			vel[0], vel[1], g_ghostTicks[client],
			NormalizeAngle(angles[1] - g_prevAngles[client][1]), angles[0] - g_prevAngles[client][0],
			mouse[0], mouse[1], g_viewStillTicks[client]);
		g_ghostTicks[client] = 0;
		FlagBehavioral(client, bd_ghost_action, "GhostStrafe(injected movement)", ev);
	}
}

// ---- Ghost jump: left the ground with jump velocity but no IN_JUMP ----
// The KZJumpStats keys-panel-never-updates tell: a DLL jumping by velocity write leaves the
// button bit unset. Restricted to normal walk-speed launches so ladder and surf ramps skip it.
void Detect_GhostJump(int client, int buttons, bool onGround)
{
	if (bd_ghostjump_action < 0 || IsServerAutoBhopEnabled() || !IsNormalWalkMovement(client))
		return;

	// Rising edge into the air.
	if (onGround || !g_wasOnGround[client])
		return;

	float velocity[3];
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", velocity);
	float vz = velocity[2];
	float hspeed = SquareRoot(velocity[0] * velocity[0] + velocity[1] * velocity[1]);
	bool jumpedThisCmd = (buttons & IN_JUMP) || (g_lastButtons[client] & IN_JUMP);

	// A normal CS:GO jump is ~302 ups, or slightly less after the first gravity tick.
	if (hspeed <= 300.0 && vz >= 285.0 && vz <= 310.0 && !jumpedThisCmd)
	{
		char ev[96];
		FormatEx(ev, sizeof(ev), "takeoff vz=%.1f with no IN_JUMP in usercmd", vz);
		FlagBehavioral(client, bd_ghostjump_action, "GhostJump(input not registered)", ev);
	}
}

// ---- Synthetic move magnitude: unexplained airborne analog movement ----
void Detect_SynthMove(int client, const float vel[3], bool walking, bool onGround, bool mouseStrafe, const float angles[3], const int mouse[2])
{
	if (bd_synthmove_action < 0)
		return;

	if (!walking || GetEntProp(client, Prop_Send, "m_nWaterLevel") > 0 || onGround)
	{
		g_synthTicks[client] = 0;
		return;
	}

	if (mouseStrafe || (IsLegalMoveAxis(vel[0], g_fwdSpeed[client]) && IsLegalMoveAxis(vel[1], g_sideSpeed[client])))
	{
		g_synthTicks[client] = 0;
		return;
	}

	g_synthTicks[client]++;
	if (g_synthTicks[client] >= bd_synthmove_min_ticks)
	{
		char ev[192];
		FormatEx(ev, sizeof(ev), "fwd=%.1f side=%.1f (legal +-%d / +-%d) for %d ticks (dyaw=%.2f dpitch=%.2f dx=%d dy=%d viewstill=%dt)",
			vel[0], vel[1], g_fwdSpeed[client], g_sideSpeed[client], g_synthTicks[client],
			NormalizeAngle(angles[1] - g_prevAngles[client][1]), angles[0] - g_prevAngles[client][0],
			mouse[0], mouse[1], g_viewStillTicks[client]);
		g_synthTicks[client] = 0;
		FlagBehavioral(client, bd_synthmove_action, "SyntheticMovement(autostrafe)", ev);
	}
}

// Legal keyboard axis values sit near {0, +-speed, +-walkspeed}.
bool IsLegalMoveAxis(float v, int speed)
{
	float m = FloatAbs(v);
	float s = float(speed);
	if (m <= bd_synthmove_tol)                    return true;
	if (FloatAbs(m - s) <= bd_synthmove_tol)      return true;
	if (FloatAbs(m - s * 0.52) <= bd_synthmove_tol) return true;
	return false;
}

// ---- Usercmd integrity: malformed command headers/unknown input bits ----
#define KEVAC_VALID_BUTTON_MASK ((1 << 26) - 1)

void Detect_UserCmdIntegrity(int client, int buttons, int cmdnum, int tickcount)
{
	if (bd_usercmd_action < 0)
		return;

	char evidence[96];
	bool invalid = false;
	if (cmdnum < 0)
	{
		FormatEx(evidence, sizeof(evidence), "negative command number %d", cmdnum);
		invalid = true;
	}
	else if (tickcount < 0)
	{
		FormatEx(evidence, sizeof(evidence), "negative command tickcount %d", tickcount);
		invalid = true;
	}
	else
	{
		int unknown = buttons & ~KEVAC_VALID_BUTTON_MASK;
		if (unknown != 0)
		{
			FormatEx(evidence, sizeof(evidence), "unknown usercmd button bits 0x%X", unknown);
			invalid = true;
		}
	}

	if (invalid && GetGameTime() - g_usercmdLastFlag[client] >= 5.0)
	{
		g_usercmdLastFlag[client] = GetGameTime();
		FlagBehavioral(client, bd_usercmd_action, "MalformedUserCmd", evidence);
	}
}

// CS:GO reserves IN_BULLRUSH for its anti-duck-delay bypass. Normal clients never
// need it; strip it before movement consumes the command and act according to config.
void Detect_AntiDuckDelay(int client, int &buttons, bool &modified)
{
	if (bd_antiduck_action < 0 || !(buttons & IN_BULLRUSH))
		return;

	buttons &= ~IN_BULLRUSH;
	modified = true;
	FlagBehavioral(client, bd_antiduck_action, "AntiDuckDelay", "IN_BULLRUSH set in usercmd");
}

// ---- Angle clamp: usercmd pitch/roll out of engine range ----
// Pitch beyond the client range is a command-integrity failure. Roll differs: a plugin
// repairing a view or teleporting can feed nonzero roll into the next commands. Sanitize both,
// but never let a roll-only sequence inherit the pitch-ban action.
void Detect_AngleClamp(int client, int buttons, int cmdnum, int tickcount, const int mouse[2], float angles[3], bool &modified)
{
	if (bd_angle_action < 0 && bd_angle_roll_action < 0)
		return;

	float rawPitch = angles[0];
	float rawYaw = angles[1];
	float rawRoll = angles[2];
	bool badPitch = FloatAbs(rawPitch) > 89.5;
	bool badRoll = FloatAbs(rawRoll) > 0.5;
	if (!badPitch && !badRoll)
		return;

	if (bd_angle_patch)
	{
		if (angles[0] > 89.0)
			angles[0] = 89.0;
		else if (angles[0] < -89.0)
			angles[0] = -89.0;
		angles[2] = 0.0;
		modified = true;
	}

	if (GetGameTime() < g_teleportGraceUntil[client])
		return;

	if (badPitch)
	{
		if (bd_angle_action < 0)
			return;

		int strike = AdvanceAngleStrike(g_angleFlagCount[client], g_angleFlagWindow[client]);
		LogAngleSample(client, "pitch", rawPitch, rawYaw, rawRoll, buttons, cmdnum, tickcount, mouse, strike);
		if (strike < bd_angle_streak)
			return;

		char ev[128];
		FormatEx(ev, sizeof(ev), "pitch=%.2f out of legal range (x%d in %.1fs; roll=%.2f)", rawPitch, strike, bd_angle_window, rawRoll);
		g_angleFlagCount[client] = 0;
		FlagBehavioral(client, bd_angle_action, "AngleClamp(injected pitch)", ev);
		return;
	}

	// A small nonzero roll is cleaned silently. A larger roll is still recorded
	// in full, but it follows its own log-only-by-default action.
	if (bd_angle_roll_action < 0 || FloatAbs(rawRoll) <= 5.0)
		return;

	int strike = AdvanceAngleStrike(g_angleRollFlagCount[client], g_angleRollFlagWindow[client]);
	LogAngleSample(client, "roll", rawPitch, rawYaw, rawRoll, buttons, cmdnum, tickcount, mouse, strike);
	if (strike < bd_angle_streak)
		return;

	char ev[128];
	FormatEx(ev, sizeof(ev), "roll=%.2f with legal pitch=%.2f (x%d in %.1fs; review KevAC-angle.log)", rawRoll, rawPitch, strike, bd_angle_window);
	g_angleRollFlagCount[client] = 0;
	FlagBehavioral(client, bd_angle_roll_action, "AngleClamp(roll anomaly)", ev);
}

int AdvanceAngleStrike(int &count, float &windowStart)
{
	float now = GetGameTime();
	if (now - windowStart > bd_angle_window)
	{
		count = 0;
		windowStart = now;
	}

	count++;
	return count;
}

void LogAngleSample(int client, const char[] kind, float pitch, float yaw, float roll, int buttons, int cmdnum, int tickcount, const int mouse[2], int strike)
{
	float velocity[3];
	float origin[3];
	GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", velocity);
	GetClientAbsOrigin(client, origin);
	float speed = SquareRoot(velocity[0] * velocity[0] + velocity[1] * velocity[1]);

	LogToFile("addons/sourcemod/logs/KevAC-angle.log", "[KevAC] %L | %s anomaly | p=%.2f y=%.2f r=%.2f | cmd=%d tick=%d buttons=0x%X mouse=(%d,%d) | strike=%d/%d window=%.1fs | speed=%.1f origin=(%.1f,%.1f,%.1f) | spawn/teleport grace ended %.2fs ago",
		client, kind, pitch, yaw, roll, cmdnum, tickcount, buttons, mouse[0], mouse[1], strike, bd_angle_streak, bd_angle_window, speed, origin[0], origin[1], origin[2], GetGameTime() - g_teleportGraceUntil[client]);
}

// ---- Opt-in backtrack mitigation: command tick manipulation ----
void StoreBacktrackTick(int client, int tickcount)
{
	g_backtrackPrevTick[client] = g_backtrackRawTick[client];
	g_backtrackRawTick[client] = tickcount;
}

void PatchBacktrackTick(int client, int buttons, int &tickcount, bool &modified)
{
	if (!bd_tick_patch || tickcount <= 0 || g_backtrackPrevTick[client] <= 0)
		return;
	if (GetGameTime() < g_teleportGraceUntil[client])
		return;
	bool attackEdge = (buttons & (IN_ATTACK | IN_ATTACK2)) != 0
		&& (g_lastButtons[client] & (IN_ATTACK | IN_ATTACK2)) == 0;
	if (!attackEdge)
		return;

	int expected = g_backtrackPrevTick[client] + 1;
	int deviation = tickcount - expected;
	if (deviation < 0)
		deviation = -deviation;
	bool duplicateTick = tickcount == g_backtrackPrevTick[client];

	if (deviation <= bd_tick_tolerance && !duplicateTick)
	{
		g_backtrackPatchStreak[client] = 0;
		return;
	}

	int nowTick = GetGameTickCount();
	int chainTicks = RoundToNearest(5.0 / GetTickInterval());
	if (g_backtrackPatchLastServerTick[client] <= 0 || nowTick - g_backtrackPatchLastServerTick[client] > chainTicks)
		g_backtrackPatchStreak[client] = 0;

	g_backtrackPatchLastServerTick[client] = nowTick;
	g_backtrackPatchStreak[client]++;

	if (g_backtrackPatchStreak[client] < bd_tick_streak)
		return;

	int pingTicks = RoundToNearest(GetClientAvgLatency(client, NetFlow_Outgoing) / GetTickInterval());
	int patched = nowTick - pingTicks;
	if (patched < 0)
		patched = 0;
	else if (patched > nowTick)
		patched = nowTick;

	tickcount = patched;
	modified = true;

	if (bd_tick_action >= 0)
	{
		char evidence[128];
		FormatEx(evidence, sizeof(evidence), "%d anomalous attack tickcounts; raw=%d expected=%d", g_backtrackPatchStreak[client], g_backtrackRawTick[client], expected);
		FlagBehavioral(client, bd_tick_action, "BacktrackPatch(repeated attack ticks)", evidence);
	}

	g_backtrackPatchStreak[client] = 0;
	g_backtrackPatchLastServerTick[client] = 0;
}

void Detect_CmdTick(int client, int buttons, int tickcount)
{
	if (bd_tick_action < 0)
		return;

	int previousTick = g_lastTick[client];
	g_lastTick[client] = tickcount;
	if (previousTick <= 0 || tickcount <= 0)
		return;

	int drop = previousTick - tickcount;
	bool attackEdge = (buttons & (IN_ATTACK | IN_ATTACK2)) != 0
		&& (g_lastButtons[client] & (IN_ATTACK | IN_ATTACK2)) == 0;
	if (!attackEdge)
		return;

	int nowTick = GetGameTickCount();
	int pingTicks = RoundToNearest(GetClientAvgLatency(client, NetFlow_Outgoing) / GetTickInterval());
	int expectedTick = nowTick - pingTicks;
	int historicalAge = expectedTick - tickcount;
	bool duplicateTick = tickcount == previousTick;
	bool historicalAttack = (duplicateTick || (drop >= bd_tick_regress && drop < 300))
		&& historicalAge >= bd_tick_min_old;

	if (!historicalAttack)
	{
		g_tickStreak[client] = 0;
		g_tickLastServerTick[client] = 0;
		return;
	}

	int chainTicks = RoundToNearest(5.0 / GetTickInterval());
	if (g_tickLastServerTick[client] <= 0 || nowTick - g_tickLastServerTick[client] > chainTicks)
		g_tickStreak[client] = 0;

	g_tickLastServerTick[client] = nowTick;
	g_tickStreak[client]++;
	if (g_tickStreak[client] < bd_tick_streak)
		return;

	char evidence[160];
	FormatEx(evidence, sizeof(evidence), "%d historical attacks: prev=%d raw=%d drop=%d duplicate=%d expected=%d age=%d ping=%d", g_tickStreak[client], previousTick, tickcount, drop, duplicateTick, expectedTick, historicalAge, pingTicks);
	g_tickStreak[client] = 0;
	g_tickLastServerTick[client] = 0;
	FlagBehavioral(client, bd_tick_action, "Backtrack(historical attack tick)", evidence);
}

// ---- Scripted bhop (capture-validated) ----
// A human scroller spams +jump edges while airborne; the DLL capture showed exactly one press,
// on the landing tick. Requiring both a perfect takeoff AND zero airborne +jump separates them.
void Detect_Bhop(int client, int buttons, bool onGround)
{
	if ((bd_bhop_action < 0 && bd_bhop_ratio_action < 0 && bd_scroll_pattern_action < 0) || IsServerAutoBhopEnabled() || g_styleAutobhop[client])
		return;
	if (!IsNormalWalkMovement(client))
	{
		g_groundTicks[client] = 0;
		g_perfectStreak[client] = 0;
		g_airJumpPresses[client] = 0;
		ResetScrollOutcomeProfile(client);
		return;
	}

	if (onGround)
	{
		g_groundTicks[client] = g_wasOnGround[client] ? g_groundTicks[client] + 1 : 0;
		// A profile represents one continuous bhop attempt. Walking or standing for
		// a moment ends it, rather than allowing unrelated jumps to be combined.
		if (g_groundTicks[client] > 7)
			ResetScrollOutcomeProfile(client);
		return;
	}

	bool jumpEdge = (buttons & IN_JUMP) && !(g_lastButtons[client] & IN_JUMP);
	if (!g_wasOnGround[client])
	{
		if (jumpEdge)
			g_airJumpPresses[client]++;
		return;
	}

	// Takeoff tick.
	if ((buttons & IN_JUMP) || (g_lastButtons[client] & IN_JUMP))
	{
		int airbornePresses = g_airJumpPresses[client];
		bool landingTickPerfect = g_groundTicks[client] <= bd_bhop_maxground;
		bool cleanPerfect = (landingTickPerfect && airbornePresses == 0);
		Track_BhopRatio(client, cleanPerfect);
		TrackScrollOutcomeProfile(client, landingTickPerfect, airbornePresses);
		if (cleanPerfect)
		{
			g_perfectStreak[client]++;
			if (bd_bhop_action >= 0 && g_perfectStreak[client] >= bd_bhop_streak)
			{
				char ev[128];
				FormatEx(ev, sizeof(ev), "%d consecutive perfect jumps (<=%d ground ticks) with zero airborne +jump input", g_perfectStreak[client], bd_bhop_maxground);
				g_perfectStreak[client] = 0;
				FlagBehavioral(client, bd_bhop_action, "ScriptedBhop(landing-tick auto jump)", ev);
			}
		}
		else
		{
			g_perfectStreak[client] = 0;
		}
	}
	else
	{
		// Leaving the ground without a qualifying jump breaks the perfect-hop run.
		g_perfectStreak[client] = 0;
	}
	g_airJumpPresses[client] = 0;
}

// Rolling perfect-jump share. A human scroller spams airborne +jump (so almost
// none of their hops are "clean"), while a humanized autobhop that inserts
// missed hops to defeat the streak still lands most takeoffs clean+perfect.
void Track_BhopRatio(int client, bool cleanPerfect)
{
	if (bd_bhop_ratio_action < 0)
		return;

	g_bhopWindowJumps[client]++;
	if (cleanPerfect)
		g_bhopWindowPerfect[client]++;
	if (g_bhopWindowJumps[client] < bd_bhop_ratio_window)
		return;

	int pct = (g_bhopWindowPerfect[client] * 100) / g_bhopWindowJumps[client];
	if (pct >= bd_bhop_ratio_pct)
	{
		char ev[128];
		FormatEx(ev, sizeof(ev), "%d/%d takeoffs perfect (<=%d ground ticks, no airborne +jump) = %d%%", g_bhopWindowPerfect[client], g_bhopWindowJumps[client], bd_bhop_maxground, pct);
		FlagBehavioral(client, bd_bhop_ratio_action, "ScriptedBhop(humanized ratio)", ev);
	}
	g_bhopWindowJumps[client] = 0;
	g_bhopWindowPerfect[client] = 0;
}

// ---- Scroll cadence and outcome profile ----
// The server cannot identify physical wheel movement, so raw cadence is evidence only. An action
// requires corroboration by a long run of near-perfect high-speed hop outcomes below.
void Detect_Scroll(int client, int buttons, int nowTick)
{
	if (bd_scroll_action < 0 && bd_scroll_pattern_action < 0)
		return;

	bool jumpEdge = (buttons & IN_JUMP) && !(g_lastButtons[client] & IN_JUMP);
	if (!jumpEdge)
		return;

	if (g_lastJumpTick[client] > 0)
	{
		int delta = nowTick - g_lastJumpTick[client];
		if (delta > 0 && delta <= 40)
		{
			Detect_ScrollPattern(client, delta);
			if (bd_scroll_action >= 0)
			{
				g_jumpDeltas[client][g_jumpDeltaCount[client] % bd_scroll_sample] = delta;
				g_jumpDeltaCount[client]++;

				if (g_jumpDeltaCount[client] >= bd_scroll_sample)
				{
					int mn = g_jumpDeltas[client][0], mx = g_jumpDeltas[client][0];
					for (int i = 1; i < bd_scroll_sample; i++)
					{
						int d = g_jumpDeltas[client][i];
						if (d < mn) mn = d;
						if (d > mx) mx = d;
					}
					if ((mx - mn) <= bd_scroll_maxjitter)
					{
						g_jumpDeltaCount[client] = 0;
						AddScrollCadenceEvidence(client, 2, mx > mn);
					}
				}
			}
		}
		else
		{
			g_jumpDeltaCount[client] = 0;
			g_scrollPatternMin[client] = 0;
			g_scrollPatternMax[client] = 0;
			g_scrollPatternRepeats[client] = 0;
		}
	}
	g_lastJumpTick[client] = nowTick;
}

// A short sequence is retained as one evidence point. It is deliberately not a
// punishment on its own because normal wheel bindings can produce it.
void Detect_ScrollPattern(int client, int delta)
{
	if (bd_scroll_pattern_action < 0)
		return;

	if (delta > bd_scroll_pattern_maxinterval)
	{
		g_scrollPatternMin[client] = 0;
		g_scrollPatternMax[client] = 0;
		g_scrollPatternRepeats[client] = 0;
		return;
	}

	if (g_scrollPatternMin[client] == 0)
	{
		g_scrollPatternMin[client] = delta;
		g_scrollPatternMax[client] = delta;
		return;
	}

	int mn = (delta < g_scrollPatternMin[client]) ? delta : g_scrollPatternMin[client];
	int mx = (delta > g_scrollPatternMax[client]) ? delta : g_scrollPatternMax[client];
	if ((mx - mn) > bd_scroll_pattern_jitter)
	{
		g_scrollPatternMin[client] = delta;
		g_scrollPatternMax[client] = delta;
		g_scrollPatternRepeats[client] = 0;
		return;
	}

	g_scrollPatternMin[client] = mn;
	g_scrollPatternMax[client] = mx;
	g_scrollPatternRepeats[client]++;
	if (g_scrollPatternRepeats[client] >= bd_scroll_pattern_repeats)
	{
		g_scrollPatternRepeats[client] = 0;
		g_scrollPatternMin[client] = 0;
		g_scrollPatternMax[client] = 0;
		AddScrollCadenceEvidence(client, 1, mx > mn);
	}
}

// drifted means the sequence only held together because of the jitter
// tolerance. A coasting wheel slows as it spins down and always drifts;
// machine timing lands on the same interval every time.
void AddScrollCadenceEvidence(int client, int weight, bool drifted)
{
	if (weight <= 0)
		return;
	g_scrollCadenceBursts[client] += weight;
	if (g_scrollCadenceBursts[client] > 128)
		g_scrollCadenceBursts[client] = 128;

	if (drifted)
		g_scrollJitteredBursts[client] += weight;
	if (g_scrollJitteredBursts[client] > g_scrollCadenceBursts[client])
		g_scrollJitteredBursts[client] = g_scrollCadenceBursts[client];
}

void ResetScrollOutcomeProfile(int client)
{
	g_scrollCadenceBursts[client] = 0;
	g_scrollJitteredBursts[client] = 0;
	g_scrollProfileCount[client] = 0;
}

// Oryx's useful lesson is to compare many complete hops, not a few raw button intervals. This
// profile keeps that conservative for HnS: a high-speed chain, near-perfect takeoffs, repeated
// high-rate input, close press counts between adjacent hops, and repeated cadence evidence.
void TrackScrollOutcomeProfile(int client, bool landingTickPerfect, int airbornePresses)
{
	if (bd_scroll_pattern_action < 0)
		return;

	float velocity[3];
	GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", velocity);
	float hspeed = SquareRoot(velocity[0] * velocity[0] + velocity[1] * velocity[1]);
	if (hspeed < bd_scroll_profile_minspeed)
	{
		ResetScrollOutcomeProfile(client);
		return;
	}

	int index = g_scrollProfileCount[client];
	if (index >= bd_scroll_profile_window)
	{
		ResetScrollOutcomeProfile(client);
		index = 0;
	}

	g_scrollProfilePresses[client][index] = airbornePresses;
	g_scrollProfilePerfect[client][index] = landingTickPerfect ? 1 : 0;
	g_scrollProfileCount[client]++;
	if (g_scrollProfileCount[client] < bd_scroll_profile_window)
		return;

	int perfect = 0;
	int highRate = 0;
	int samePairs = 0;
	for (int i = 0; i < bd_scroll_profile_window; i++)
	{
		if (g_scrollProfilePerfect[client][i] != 0)
			perfect++;
		if (g_scrollProfilePresses[client][i] >= bd_scroll_profile_min_presses)
			highRate++;
		if (i > 0)
		{
			int pressDifference = g_scrollProfilePresses[client][i] - g_scrollProfilePresses[client][i - 1];
			if (pressDifference < 0)
				pressDifference = -pressDifference;
			if (pressDifference <= 1)
				samePairs++;
		}
	}

	int perfectPct = (perfect * 100) / bd_scroll_profile_window;
	int highRatePct = (highRate * 100) / bd_scroll_profile_window;
	bool verified = perfectPct >= bd_scroll_profile_perfect_pct
		&& highRatePct >= bd_scroll_profile_press_pct
		&& samePairs >= bd_scroll_profile_same_pairs
		&& g_scrollCadenceBursts[client] >= bd_scroll_profile_cadence_bursts;

	if (verified)
	{
		// Same split as the +duck path: a drifting cadence is a coasting wheel,
		// an exact one is machine timing. Only the exact case is a macro.
		int drifted = g_scrollJitteredBursts[client];
		int total = g_scrollCadenceBursts[client];
		bool coasting = (drifted * 2 >= total);
		int action = coasting ? bd_hyperscroll_action : bd_scroll_pattern_action;

		char ev[224];
		FormatEx(ev, sizeof(ev), "%d-hop outcome profile: %d%% landing-tick, %d%% with >=%d airborne +jump edges, %d adjacent edge-count pairs within one input, %d cadence bursts (%d drifted)",
			bd_scroll_profile_window, perfectPct, highRatePct, bd_scroll_profile_min_presses, samePairs, total, drifted);
		if (action >= 0)
			FlagBehavioral(client, action, coasting ? "HyperScroll(+jump free-spin cadence)" : "ScrollMacro(verified hop outcome profile)", ev);
	}

	ResetScrollOutcomeProfile(client);
}

// The server sees usercmd edges, not physical wheel movement. A long, near-periodic +duck train
// accumulates cadence bursts. Duck gstrafe and duck macros are the same input family, so both
// report as DuckMacro. Mouse-strafe context adds evidence only; it never excuses periodic input.
void Detect_DuckMacro(int client, int buttons, int nowTick, bool mouseStrafe, const float angles[3], const int mouse[2])
{
	if ((bd_duckmacro_action < 0 && bd_duckmacro_input_action < 0) || !(buttons & IN_DUCK) || (g_lastButtons[client] & IN_DUCK))
		return;

	if (mouseStrafe)
		g_duckMouseStrafeBursts[client]++;

	if (g_lastDuckTick[client] > 0)
	{
		int delta = nowTick - g_lastDuckTick[client];
		if (delta <= 0 || delta > bd_duckmacro_maxinterval)
		{
			g_duckPatternMin[client] = 0;
			g_duckPatternMax[client] = 0;
			g_duckPatternRepeats[client] = 0;
			g_duckMouseStrafeBursts[client] = 0;
		}
		else if (g_duckPatternMin[client] == 0)
		{
			g_duckPatternMin[client] = delta;
			g_duckPatternMax[client] = delta;
		}
		else
		{
			int mn = (delta < g_duckPatternMin[client]) ? delta : g_duckPatternMin[client];
			int mx = (delta > g_duckPatternMax[client]) ? delta : g_duckPatternMax[client];
			if ((mx - mn) > bd_duckmacro_jitter)
			{
				g_duckPatternMin[client] = delta;
				g_duckPatternMax[client] = delta;
				g_duckPatternRepeats[client] = 0;
				g_duckMouseStrafeBursts[client] = 0;
			}
			else if (++g_duckPatternRepeats[client] >= bd_duckmacro_repeats)
			{
				int burstMin = g_duckPatternMin[client];
				int burstMax = g_duckPatternMax[client];
				g_duckPatternMin[client] = 0;
				g_duckPatternMax[client] = 0;
				g_duckPatternRepeats[client] = 0;
				// Bursts separated by more than 4x the outcome window are separate
				// episodes. Without this, a whole map of occasional legit duck spam
				// accumulates into the input-signal threshold.
				if (g_duckCadenceLastTick[client] > 0 && nowTick - g_duckCadenceLastTick[client] > bd_duckmacro_window * 4)
				{
					g_duckCadenceBursts[client] = 0;
					g_duckJitteredBursts[client] = 0;
				}
				float dmv[3];
				GetEntPropVector(client, Prop_Data, "m_vecVelocity", dmv);
				float dmSpeed = SquareRoot(dmv[0] * dmv[0] + dmv[1] * dmv[1]);
				if (dmSpeed < bd_duckmacro_input_minspeed)
				{
					// Idle ducking is neither useful movement automation nor evidence for a
					// later moving sequence. Do not carry it into the actionable counter.
					g_duckCadenceBursts[client] = 0;
					g_duckCadenceLastTick[client] = 0;
					g_duckMouseStrafeBursts[client] = 0;
					g_duckJitteredBursts[client] = 0;
					g_duckMacroOutcomes[client] = 0;
					g_duckMacroOutcomeLastTick[client] = 0;
				}
				else
				{
					g_duckCadenceBursts[client]++;
					if (burstMax > burstMin)
						g_duckJitteredBursts[client]++;
					if (g_duckCadenceBursts[client] > 64)
						g_duckCadenceBursts[client] = 64;
					g_duckCadenceLastTick[client] = nowTick;

					// A duck-only movement macro has no +jump outcome to verify. Report its
					// periodic +duck input only while moving fast enough to be meaningful.
					if (bd_duckmacro_input_action >= 0 && g_duckCadenceBursts[client] >= bd_duckmacro_input_bursts)
					{
						// A free-spinning wheel coasts, so its detents drift across the jitter band as it slows. Machine
						// timing does not drift: a macro or firmware repeat rate lands on the same interval every time.
						// The wheel-mode button is easy to hit by accident, so the drifting case is capped below the action.
						int total = g_duckCadenceBursts[client];
						// Verified outcomes consume bursts without consuming the drift
						// tally, so clamp rather than letting the ratio exceed 1.
						int drifted = g_duckJitteredBursts[client];
						if (drifted > total)
							drifted = total;
						bool coasting = (drifted * 2 >= total);
						int action = coasting ? bd_hyperscroll_action : bd_duckmacro_input_action;

						char ev[256];
						FormatEx(ev, sizeof(ev), "%d periodic +duck bursts (interval %d-%d ticks, >=%d repeats each; %d/%d drifted) at %.0f ups; mouse-strafe context on %d duck edges (dyaw=%.2f dpitch=%.2f dx=%d dy=%d)",
							total, burstMin, burstMax, bd_duckmacro_repeats + 1, drifted, total, dmSpeed, g_duckMouseStrafeBursts[client],
							NormalizeAngle(angles[1] - g_prevAngles[client][1]), angles[0] - g_prevAngles[client][0], mouse[0], mouse[1]);
						g_duckCadenceBursts[client] = 0;
						g_duckMouseStrafeBursts[client] = 0;
						g_duckJitteredBursts[client] = 0;
						if (action >= 0)
							FlagBehavioral(client, action, coasting ? "HyperScroll(+duck free-spin cadence)" : "DuckMacro(+duck cadence)", ev);
					}
				}
			}
			else
			{
				g_duckPatternMin[client] = mn;
				g_duckPatternMax[client] = mx;
			}
		}
	}
	g_lastDuckTick[client] = nowTick;
}

void TrackDuckMacroOutcome(int client, int nowTick, float beforeSpeed, float afterSpeed)
{
	if (bd_duckmacro_action < 0)
		return;

	if (g_duckCadenceBursts[client] <= 0 || g_duckCadenceLastTick[client] <= 0
		|| nowTick - g_duckCadenceLastTick[client] > bd_duckmacro_window)
	{
		g_duckMacroOutcomes[client] = 0;
		g_duckMacroOutcomeLastTick[client] = 0;
		g_duckMouseStrafeBursts[client] = 0;
		return;
	}

	if (g_duckMacroOutcomeLastTick[client] <= 0
		|| nowTick - g_duckMacroOutcomeLastTick[client] > bd_groundjumpbug_chain)
		g_duckMacroOutcomes[client] = 0;

	// Consume one independently observed cadence burst for each verified outcome.
	// A single wheel burst cannot be reused to turn an unrelated sequence of
	// successful ground jumps into a macro detection.
	g_duckCadenceBursts[client]--;
	g_duckMacroOutcomeLastTick[client] = nowTick;
	g_duckMacroOutcomes[client]++;
	if (g_duckMacroOutcomes[client] < bd_duckmacro_outcomes)
		return;

	char ev[160];
	FormatEx(ev, sizeof(ev), "%d ground duck-release jumps preserved speed (%.0f -> %.0f ups), each preceded by periodic +duck cadence", g_duckMacroOutcomes[client], beforeSpeed, afterSpeed);
	g_duckMacroOutcomes[client] = 0;
	g_duckMacroOutcomeLastTick[client] = 0;
	g_duckCadenceBursts[client] = 0;
	g_duckCadenceLastTick[client] = 0;
	g_duckMouseStrafeBursts[client] = 0;
	FlagBehavioral(client, bd_duckmacro_action, "DuckMacro(verified +duck outcome)", ev);
}

// A successful jumpbug starts and ends a frame airborne: falling while ducked, releasing duck and
// pressing jump together near ground, then rising the next frame without a stable ground state.
// Besides the outcome streak, track the duck-press-to-jump offset across successes.
void Detect_JumpBug(int client, int buttons, bool onGround, int nowTick)
{
	if (bd_jumpbug_action < 0 && bd_jumpbug_timing_action < 0)
		return;
	if (!IsNormalWalkMovement(client))
	{
		g_jumpBugArmed[client] = false;
		g_jumpBugStreak[client] = 0;
		g_duckAirTicks[client] = 0;
		g_jumpBugTimingStreak[client] = 0;
		g_jumpBugTimingLastDelay[client] = -1;
		return;
	}

	float velocity[3];
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", velocity);

	if (g_jumpBugLastTick[client] > 0 && nowTick - g_jumpBugLastTick[client] > bd_jumpbug_chain)
	{
		g_jumpBugStreak[client] = 0;
		g_jumpBugTimingStreak[client] = 0;
		g_jumpBugTimingLastDelay[client] = -1;
	}

	if (g_jumpBugArmed[client])
	{
		int elapsed = nowTick - g_jumpBugArmTick[client];
		if (elapsed > bd_jumpbug_maxgap || onGround)
		{
			g_jumpBugArmed[client] = false;
			g_jumpBugStreak[client] = 0;
			g_jumpBugTimingStreak[client] = 0;
			g_jumpBugTimingLastDelay[client] = -1;
		}
		else if (velocity[2] >= 200.0)
		{
			g_jumpBugArmed[client] = false;
			if (g_jumpBugLastTick[client] == 0 || nowTick - g_jumpBugLastTick[client] > bd_jumpbug_chain)
				g_jumpBugStreak[client] = 0;

			g_jumpBugStreak[client]++;
			g_jumpBugLastTick[client] = nowTick;

			if (bd_jumpbug_timing_action >= 0 && g_jumpBugArmDuckToJump[client] >= 0 && g_jumpBugArmDuckToJump[client] <= bd_jumpbug_timing_maxduck)
			{
				int delay = g_jumpBugArmDuckToJump[client];
				int timingDifference = delay - g_jumpBugTimingLastDelay[client];
				if (timingDifference < 0)
					timingDifference = -timingDifference;
				if (g_jumpBugTimingLastDelay[client] < 0 || timingDifference > bd_jumpbug_timing_jitter)
					g_jumpBugTimingStreak[client] = 1;
				else
					g_jumpBugTimingStreak[client]++;

				g_jumpBugTimingLastDelay[client] = delay;
				if (g_jumpBugTimingStreak[client] >= bd_jumpbug_timing_repeats)
				{
					char timingEvidence[128];
					FormatEx(timingEvidence, sizeof(timingEvidence), "%d successful jumpbugs with +jump exactly %d ticks after +duck", g_jumpBugTimingStreak[client], delay);
					g_jumpBugTimingStreak[client] = 0;
					g_jumpBugTimingLastDelay[client] = -1;
					FlagBehavioral(client, bd_jumpbug_timing_action, "JumpBug(tick-perfect duck-to-jump)", timingEvidence);
				}
			}
			else
			{
				g_jumpBugTimingStreak[client] = 0;
				g_jumpBugTimingLastDelay[client] = -1;
			}

			if (g_jumpBugStreak[client] >= bd_jumpbug_streak)
			{
				if (bd_jumpbug_action >= 0)
				{
					char ev[128];
					FormatEx(ev, sizeof(ev), "%d successful late-fall duck-release + jump sequences (last fall %.0f ups)", g_jumpBugStreak[client], -g_jumpBugFallSpeed[client]);
					FlagBehavioral(client, bd_jumpbug_action, "JumpBug(repeated successful signature)", ev);
				}
				g_jumpBugStreak[client] = 0;
			}
		}
	}

	bool duckPressed = (buttons & IN_DUCK) && !(g_lastButtons[client] & IN_DUCK);
	if (duckPressed)
		g_jumpBugDuckPressTick[client] = nowTick;

	bool jumpEdge = (buttons & IN_JUMP) && !(g_lastButtons[client] & IN_JUMP);
	bool duckReleased = !(buttons & IN_DUCK) && (g_lastButtons[client] & IN_DUCK);
	if (!onGround && duckReleased && jumpEdge && g_duckAirTicks[client] > 0 && velocity[2] <= -bd_jumpbug_minfall)
	{
		g_jumpBugArmed[client] = true;
		g_jumpBugArmTick[client] = nowTick;
		g_jumpBugFallSpeed[client] = velocity[2];
		g_jumpBugArmDuckToJump[client] = g_jumpBugDuckPressTick[client] > 0 ? nowTick - g_jumpBugDuckPressTick[client] : -1;
	}

	if (!onGround && (buttons & IN_DUCK))
		g_duckAirTicks[client]++;
	else
		g_duckAirTicks[client] = 0;
}

// Some jumpbug macros run during high-speed ground strafes instead of a large fall. Record the
// narrow duck-release + jump input and verify the player leaves the ground keeping nearly all
// that momentum. Deliberately separate from the fall-damage signature above.
void Detect_GroundJumpBug(int client, int buttons, const float wishvel[3], bool onGround, int nowTick)
{
	if (bd_groundjumpbug_action < 0 && bd_groundjumpbug_timing_action < 0 && bd_duckmacro_action < 0)
		return;
	if (!IsNormalWalkMovement(client))
	{
		g_groundJumpBugArmed[client] = false;
		g_groundJumpBugStreak[client] = 0;
		g_groundJumpBugLastTick[client] = 0;
		g_gjbTimingStreak[client] = 0;
		g_gjbTimingLastDelay[client] = -1;
		return;
	}

	bool duckPressed = (buttons & IN_DUCK) && !(g_lastButtons[client] & IN_DUCK);
	if (duckPressed)
		g_groundJumpBugDuckPressTick[client] = nowTick;

	float velocity[3];
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", velocity);
	float hspeed = SquareRoot(velocity[0] * velocity[0] + velocity[1] * velocity[1]);

	if (g_groundJumpBugLastTick[client] > 0 && nowTick - g_groundJumpBugLastTick[client] > bd_groundjumpbug_chain)
		g_groundJumpBugStreak[client] = 0;

	if (g_groundJumpBugArmed[client])
	{
		int elapsed = nowTick - g_groundJumpBugArmTick[client];
		if (elapsed > bd_groundjumpbug_maxgap || onGround)
		{
			g_groundJumpBugArmed[client] = false;
			g_groundJumpBugStreak[client] = 0;
		}
		else if (velocity[2] >= 200.0)
		{
			g_groundJumpBugArmed[client] = false;
			if (hspeed >= g_groundJumpBugArmSpeed[client] - bd_groundjumpbug_speedloss)
			{
				g_groundJumpBugLastTick[client] = nowTick;
				g_groundJumpBugStreak[client]++;
				TrackDuckMacroOutcome(client, nowTick, g_groundJumpBugArmSpeed[client], hspeed);

				// Fixed-latency macro tell: +jump a constant tick count after +duck
				// across consecutive successful ground jumpbugs. Reuses the airborne
				// jumpbug timing thresholds (repeats/jitter/max-duck).
				if (bd_groundjumpbug_timing_action >= 0 && g_groundJumpBugArmDuckToJump[client] >= 0 && g_groundJumpBugArmDuckToJump[client] <= bd_jumpbug_timing_maxduck)
				{
					int delay = g_groundJumpBugArmDuckToJump[client];
					int d = delay - g_gjbTimingLastDelay[client];
					if (d < 0)
						d = -d;
					if (g_gjbTimingLastDelay[client] < 0 || d > bd_jumpbug_timing_jitter)
						g_gjbTimingStreak[client] = 1;
					else
						g_gjbTimingStreak[client]++;
					g_gjbTimingLastDelay[client] = delay;
					if (g_gjbTimingStreak[client] >= bd_jumpbug_timing_repeats)
					{
						char tev[128];
						FormatEx(tev, sizeof(tev), "%d ground jumpbugs with +jump exactly %d ticks after +duck (macro latency)", g_gjbTimingStreak[client], delay);
						g_gjbTimingStreak[client] = 0;
						g_gjbTimingLastDelay[client] = -1;
						FlagBehavioral(client, bd_groundjumpbug_timing_action, "GroundJumpBug(tick-perfect duck-to-jump)", tev);
					}
				}
				else
				{
					g_gjbTimingStreak[client] = 0;
					g_gjbTimingLastDelay[client] = -1;
				}

				if (bd_groundjumpbug_action >= 0 && g_groundJumpBugStreak[client] >= bd_groundjumpbug_streak)
				{
					char ev[128];
					FormatEx(ev, sizeof(ev), "%d ground duck-release jumps preserved speed (%.0f -> %.0f ups)", g_groundJumpBugStreak[client], g_groundJumpBugArmSpeed[client], hspeed);
					g_groundJumpBugStreak[client] = 0;
					FlagBehavioral(client, bd_groundjumpbug_action, "DuckMacro(ground +duck momentum)", ev);
				}
			}
			else
			{
				g_groundJumpBugStreak[client] = 0;
				g_groundJumpBugLastTick[client] = 0;
				g_gjbTimingStreak[client] = 0;
				g_gjbTimingLastDelay[client] = -1;
			}
		}
	}

	bool jumpEdge = (buttons & IN_JUMP) && !(g_lastButtons[client] & IN_JUMP);
	bool duckReleased = !(buttons & IN_DUCK) && (g_lastButtons[client] & IN_DUCK);
	if (onGround && duckReleased && jumpEdge && hspeed >= bd_groundjumpbug_minspeed && FloatAbs(wishvel[1]) >= bd_groundjumpbug_minside)
	{
		g_groundJumpBugArmed[client] = true;
		g_groundJumpBugArmTick[client] = nowTick;
		g_groundJumpBugArmSpeed[client] = hspeed;
		g_groundJumpBugArmDuckToJump[client] = g_groundJumpBugDuckPressTick[client] > 0 ? nowTick - g_groundJumpBugDuckPressTick[client] : -1;
	}
}

// ---- AHK strafe (from ofl): identical mouse-x deltas repeated mid-air ----
// Also matches period-2 replay curves (a,b,a,b,...): a scripted strafe alternating two exact
// deltas defeats the identical-delta check, but no human reproduces a two-value cycle exactly.
void Detect_AHKStrafe(int client, int mousedx, bool onGround)
{
	if (bd_ahk_action < 0)
		return;

	if (onGround || (mousedx < 10 && mousedx > -10))
	{
		g_ahkStreak[client] = 0;
		g_ahkAltStreak[client] = 0;
		g_lastMouseDx[client] = 0;
		g_prevMouseDx2[client] = 0;
		return;
	}

	// Drop the whole streak rather than just skipping the sample: a streak that
	// spans a lag burst has already been contaminated by replayed commands.
	if (AhkNetworkUnreliable(client))
	{
		g_ahkStreak[client] = 0;
		g_ahkAltStreak[client] = 0;
		g_lastMouseDx[client] = 0;
		g_prevMouseDx2[client] = 0;
		return;
	}

	if (mousedx == g_lastMouseDx[client] || mousedx == -g_lastMouseDx[client])
	{
		g_ahkStreak[client]++;
		if (g_ahkStreak[client] >= bd_ahk_streak)
		{
			char ev[96];
			FormatEx(ev, sizeof(ev), "%d identical mouse-x deltas (%d) mid-air", g_ahkStreak[client], mousedx);
			g_ahkStreak[client] = 0;
			FlagBehavioral(client, bd_ahk_action, "AHKStrafe(macro mouse)", ev);
		}
	}
	else
	{
		g_ahkStreak[client] = 0;
	}

	if (mousedx == g_prevMouseDx2[client] && mousedx != g_lastMouseDx[client])
	{
		g_ahkAltStreak[client]++;
		if (g_ahkAltStreak[client] >= bd_ahk_streak)
		{
			char ev[96];
			FormatEx(ev, sizeof(ev), "%d-tick period-2 mouse-x cycle (%d/%d) mid-air", g_ahkAltStreak[client], g_prevMouseDx2[client], g_lastMouseDx[client]);
			g_ahkAltStreak[client] = 0;
			FlagBehavioral(client, bd_ahk_action, "AHKStrafe(period-2 macro mouse)", ev);
		}
	}
	else if (mousedx != g_lastMouseDx[client] && mousedx != -g_lastMouseDx[client])
	{
		g_ahkAltStreak[client] = 0;
	}

	g_prevMouseDx2[client] = g_lastMouseDx[client];
	g_lastMouseDx[client] = mousedx;
}

// ---- Mouse-angle desync (Oryx idea, BASH2-hardened) ----
// A legit linear mouselook changes yaw by -mousedx * m_yaw and pitch by mousedy * m_pitch, and
// CUserCmd mouse fields are already sensitivity-scaled. Runs only when every client setting
// needed to verify it is known and linear. +strafe is excluded: it consumes raw mouse for movement.
void Detect_MouseYaw(int client, int buttons, const int mouse[2], const float angles[3], bool mouseStrafe)
{
	if (bd_mouseyaw_action < 0)
		return;
	if (g_myaw[client] <= 0.0 || g_mPitch[client] == 0.0 || g_mMouseLook[client] != 1)
		return; // mouse model is unknown or mouselook is disabled
	if (g_mRawInput[client] != 1 || g_mFilter[client] != 0 || g_mCustomAccel[client] != 0 || g_mJoystick[client] != 0)
		return; // unknown or non-linear mouse pipeline - cannot be modeled server-side
	if ((buttons & (IN_LEFT | IN_RIGHT | IN_ATTACK | IN_ATTACK2)) || mouseStrafe)
	{
		g_mouseyawWindowTicks[client] = 0;
		g_mouseyawBadTicks[client] = 0;
		return; // turn keys, weapon recoil, or +strafe invalidate the angle model
	}
	if (GetGameTime() < g_teleportGraceUntil[client])
		return; // spawn/teleport view snaps are server-authored

	float expectedYaw = -float(mouse[0]) * g_myaw[client];
	float actualYaw = NormalizeAngle(angles[1] - g_prevAngles[client][1]);
	float expectedPitch = float(mouse[1]) * g_mPitch[client];
	float actualPitch = angles[0] - g_prevAngles[client][0];
	if (FloatAbs(actualYaw) > 20.0 || FloatAbs(actualPitch) > 20.0
		|| FloatAbs(angles[0]) >= 87.0 || FloatAbs(g_prevAngles[client][0]) >= 87.0)
		return; // large snaps are handled by the aim detectors, not the linear model

	float unit = g_myaw[client];
	float counts = actualYaw / unit;
	bool yawMismatch = mouse[0] != 0
		&& FloatAbs(expectedYaw) > bd_mouseyaw_tol
		&& FloatAbs(actualYaw - expectedYaw) > bd_mouseyaw_tol;
	bool nonInteger = FloatAbs(counts - float(RoundToNearest(counts))) > 0.1;
	bool pitchMismatch = mouse[1] != 0
		&& FloatAbs(expectedPitch) > bd_mouseyaw_tol
		&& FloatAbs(actualPitch - expectedPitch) > bd_mouseyaw_tol;
	if ((yawMismatch && nonInteger) || pitchMismatch)
		g_mouseyawBadTicks[client]++;

	if (++g_mouseyawWindowTicks[client] < 100)
		return;

	int bad = g_mouseyawBadTicks[client];
	g_mouseyawWindowTicks[client] = 0;
	g_mouseyawBadTicks[client] = 0;
	if (bad < bd_mouseyaw_streak)
		return;

	if (g_mouseyawRetestUntil[client] < GetGameTime())
	{
		// First trip: refresh the cached mouse model and demand a repeat.
		g_mouseyawRetestUntil[client] = GetGameTime() + 60.0;
		QueryClientConVar(client, "sensitivity", OnConVarQueried);
		QueryClientConVar(client, "m_yaw", OnConVarQueried);
		QueryClientConVar(client, "m_pitch", OnConVarQueried);
		QueryClientConVar(client, "cl_mouselook", OnConVarQueried);
		QueryClientConVar(client, "m_rawinput", OnConVarQueried);
		QueryClientConVar(client, "m_filter", OnConVarQueried);
		QueryClientConVar(client, "m_customaccel", OnConVarQueried);
		QueryClientConVar(client, "joystick", OnConVarQueried);
		return;
	}

	g_mouseyawRetestUntil[client] = 0.0;
	char ev[160];
	int duckAge = (g_duckCadenceLastTick[client] > 0) ? GetGameTickCount() - g_duckCadenceLastTick[client] : -1;
	FormatEx(ev, sizeof(ev), "%d/100 raw mouse angle mismatches (yaw %.2f vs %.2f, pitch %.2f vs %.2f; dx=%d dy=%d; duck age=%dt)", bad, actualYaw, expectedYaw, actualPitch, expectedPitch, mouse[0], mouse[1], duckAge);
	bool duckContext = duckAge >= 0 && duckAge <= bd_duckmacro_window;
	FlagBehavioral(client, bd_mouseyaw_action, duckContext ? "DuckMacro(mouse-angle desync)" : "MouseAngleDesync(silent aim/anglehack)", ev);
}

// ---- Silent strafe (from ofl): sidemove sign flips every tick ----
void Detect_SilentStrafe(int client, float sidemove, bool mouseStrafe)
{
	if (bd_silent_action < 0)
		return;
	if (mouseStrafe)
	{
		g_silentStreak[client] = 0;
		g_lastSide[client] = 0.0;
		return;
	}
	if (sidemove == 0.0)
	{
		g_silentStreak[client] = 0;
		g_lastSide[client] = 0.0;
		return;
	}

	if ((sidemove > 0.0 && g_lastSide[client] < 0.0) || (sidemove < 0.0 && g_lastSide[client] > 0.0))
	{
		g_silentStreak[client]++;
		if (g_silentStreak[client] >= bd_silent_streak)
		{
			char ev[64];
			FormatEx(ev, sizeof(ev), "%d consecutive sidemove sign flips", g_silentStreak[client]);
			g_silentStreak[client] = 0;
			FlagBehavioral(client, bd_silent_action, "SilentStrafe", ev);
		}
	}
	else
	{
		g_silentStreak[client] = 0;
	}
	g_lastSide[client] = sidemove;
}

// ---- Knifebot (heuristic): stab faster than a human can react ----
// FP fixes: a slow stab now RESETS the streak (six coincidences over a match used to accumulate),
// M1-spam rhythm is excluded (a fast stab counts only if the previous edge was >=24 ticks
// earlier), and fast stabs must chain within 120 seconds.
void Detect_Knife(int client, int buttons, const float angles[3], int nowTick)
{
	if (bd_knife_action < 0)
		return;

	int wep = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if (wep == -1 || !IsValidEntity(wep))
	{
		g_stabAvailSince[client] = -1;
		return;
	}

	char cls[64];
	GetEntityClassname(wep, cls, sizeof(cls));
	if (StrContains(cls, "knife", false) == -1 && StrContains(cls, "bayonet", false) == -1)
	{
		g_stabAvailSince[client] = -1;
		return;
	}

	bool stabAvail = StabAvailable(client, angles);

	if (stabAvail && g_stabAvailSince[client] == -1)
		g_stabAvailSince[client] = nowTick;
	else if (!stabAvail)
		g_stabAvailSince[client] = -1;

	bool attackEdge = (buttons & (IN_ATTACK | IN_ATTACK2)) && !(g_lastButtons[client] & (IN_ATTACK | IN_ATTACK2));
	if (!attackEdge)
		return;

	int prevEdge = g_lastAttackEdgeTick[client];
	g_lastAttackEdgeTick[client] = nowTick;

	if (!stabAvail || g_stabAvailSince[client] == -1)
		return;

	bool spamming = prevEdge > 0 && nowTick - prevEdge < 24;
	float reactionMs = float(nowTick - g_stabAvailSince[client]) * (1000.0 / g_tickrate);
	g_stabAvailSince[client] = -1;

	if (spamming)
		return; // rhythm-fire alignment with cone entry is chance, not reaction

	int chainTicks = RoundToNearest(120.0 * g_tickrate);
	if (g_knifeLastFastTick[client] > 0 && nowTick - g_knifeLastFastTick[client] > chainTicks)
		g_knifeStreak[client] = 0;

	if (reactionMs < float(bd_knife_reaction_ms))
	{
		g_knifeLastFastTick[client] = nowTick;
		g_knifeStreak[client]++;
		if (g_knifeStreak[client] >= bd_knife_streak)
		{
			char ev[96];
			FormatEx(ev, sizeof(ev), "%d consecutive stabs at %.0fms reaction (floor %dms)", g_knifeStreak[client], reactionMs, bd_knife_reaction_ms);
			g_knifeStreak[client] = 0;
			FlagBehavioral(client, bd_knife_action, "Knifebot", ev);
		}
	}
	else
	{
		g_knifeStreak[client] = 0;
	}
}

bool StabAvailable(int client, const float angles[3])
{
	float eye[3], fwd[3];
	GetClientEyePosition(client, eye);
	GetAngleVectors(angles, fwd, NULL_VECTOR, NULL_VECTOR);

	int team = GetClientTeam(client);
	for (int t = 1; t <= MaxClients; t++)
	{
		if (t == client || !IsClientInGame(t) || !IsPlayerAlive(t) || GetClientTeam(t) == team)
			continue;

		float tpos[3], to[3];
		GetClientAbsOrigin(t, tpos);
		tpos[2] += 40.0;
		SubtractVectors(tpos, eye, to);

		float dist = GetVectorLength(to);
		if (dist > bd_knife_range || dist <= 0.0)
			continue;

		NormalizeVector(to, to);
		if (GetVectorDotProduct(fwd, to) >= bd_knife_cone)
			return true;
	}
	return false;
}

// ---- Input pattern: repeated full air-phase signatures (research telemetry) ----
// A phase covers both mouse axes, movement buttons and desired movement axes. More useful than
// scroll cadence, but still cannot identify a macro source, so the default is log-only.
void Detect_InputPattern(int client, const int mouse[2], int buttons, const float wishvel[3], bool onGround)
{
	if (bd_pattern_action < 0)
		return;

	if (!onGround)
	{
		// Accumulate this airborne tick into the phase signature.
		g_inAir[client] = true;
		g_phaseTicks[client]++;
		int mousedx = mouse[0];
		int mousedy = mouse[1];
		g_phaseMouse[client] += (mousedx < 0 ? -mousedx : mousedx);
		int strafeBits = buttons & (IN_JUMP | IN_DUCK | IN_MOVELEFT | IN_MOVERIGHT | IN_FORWARD | IN_BACK);
		g_phaseHash[client] = g_phaseHash[client] * 31 + mousedx;
		g_phaseHash[client] = g_phaseHash[client] * 31 + strafeBits;
		g_phaseHash[client] = g_phaseHash[client] * 31 + RoundToNearest(wishvel[0]);
		g_phaseCheck[client] = g_phaseCheck[client] * 131 + mousedy;
		g_phaseCheck[client] = g_phaseCheck[client] * 131 + strafeBits;
		g_phaseCheck[client] = g_phaseCheck[client] * 131 + RoundToNearest(wishvel[1]);
		return;
	}

	// Landed: finalise the phase and compare to the previous one.
	if (g_inAir[client])
	{
		g_inAir[client] = false;

		if (g_phaseTicks[client] >= bd_pattern_minticks && g_phaseMouse[client] >= bd_pattern_minmouse)
		{
			int sig = g_phaseHash[client] * 31 + g_phaseTicks[client];
			int check = g_phaseCheck[client] * 131 + g_phaseTicks[client];
			if (sig == g_prevPhaseHash[client] && check == g_prevPhaseCheck[client])
			{
				g_patternRepeat[client]++;
				if (g_patternRepeat[client] >= bd_pattern_repeats)
				{
					char ev[96];
					FormatEx(ev, sizeof(ev), "%d identical %d-tick air-strafe input patterns in a row", g_patternRepeat[client] + 1, g_phaseTicks[client]);
					g_patternRepeat[client] = 0;
					FlagBehavioral(client, bd_pattern_action, "InputPattern(macro)", ev);
				}
			}
			else
			{
				g_patternRepeat[client] = 0;
			}
			g_prevPhaseHash[client] = sig;
			g_prevPhaseCheck[client] = check;
		}
		else
		{
			// A short or inactive air phase ends the run; do not join patterns
			// across unrelated movement attempts.
			g_patternRepeat[client] = 0;
			g_prevPhaseHash[client] = 0;
			g_prevPhaseCheck[client] = 0;
		}

		g_phaseTicks[client] = 0;
		g_phaseHash[client]  = 0;
		g_phaseCheck[client] = 0;
		g_phaseMouse[client] = 0;
	}
}

// ---- Silent aim / no-recoil telemetry: A-B-A viewangle sequence around a shot ----
// StAC's useful insight is the returned-angle shape rather than a single aimbot snap.
// This remains log-only by default because precise manual corrections can resemble it.
void Detect_PSilent(int client, int buttons, const float angles[3], int cmdnum, int nowTick)
{
	if (bd_psilent_action < 0)
		return;

	int prevCmd = g_cmdNumberHistory[client][0];
	int beforeCmd = g_cmdNumberHistory[client][1];
	if (cmdnum <= 0 || prevCmd <= 0 || beforeCmd <= 0 || cmdnum != prevCmd + 1 || prevCmd != beforeCmd + 1)
	{
		g_psilentStreak[client] = 0;
		return;
	}

	bool attacked = (buttons & IN_ATTACK) || (g_cmdButtonHistory[client][0] & IN_ATTACK);
	if (!attacked)
	{
		g_psilentStreak[client] = 0;
		return;
	}

	float pitchReturn = FloatAbs(angles[0] - g_cmdAngleHistory[client][1][0]);
	float yawReturn = FloatAbs(NormalizeAngle(angles[1] - g_cmdAngleHistory[client][1][1]));
	float pitchSnap = FloatAbs(g_cmdAngleHistory[client][0][0] - angles[0]);
	float yawSnap = FloatAbs(NormalizeAngle(g_cmdAngleHistory[client][0][1] - angles[1]));
	if (pitchReturn > bd_psilent_delta || yawReturn > bd_psilent_delta || (pitchSnap < bd_psilent_delta && yawSnap < bd_psilent_delta))
	{
		g_psilentStreak[client] = 0;
		return;
	}

	if (g_psilentLastTick[client] > 0 && nowTick - g_psilentLastTick[client] > bd_psilent_chain)
		g_psilentStreak[client] = 0;
	g_psilentLastTick[client] = nowTick;
	g_psilentStreak[client]++;

	if (g_psilentStreak[client] >= bd_psilent_streak)
	{
		char ev[112];
		FormatEx(ev, sizeof(ev), "%d returned-angle attack sequences (middle snap p=%.2f y=%.2f)", g_psilentStreak[client], pitchSnap, yawSnap);
		g_psilentStreak[client] = 0;
		FlagBehavioral(client, bd_psilent_action, "SilentAim(returned viewangle)", ev);
	}
}

void StoreCmdHistory(int client, int buttons, const float angles[3], int cmdnum)
{
	g_cmdAngleHistory[client][1] = g_cmdAngleHistory[client][0];
	g_cmdAngleHistory[client][0] = angles;
	g_cmdNumberHistory[client][1] = g_cmdNumberHistory[client][0];
	g_cmdNumberHistory[client][0] = cmdnum;
	g_cmdButtonHistory[client][1] = g_cmdButtonHistory[client][0];
	g_cmdButtonHistory[client][0] = buttons;
}

// ---- Aimbot + triggerbot (ported from ofl, heuristic): one trace per tick ----
void Detect_AimTrigger(int client, int buttons, const float angles[3])
{
	bool checkAimbot = bd_aimbot_action >= 0;
	bool checkTrigger = bd_trigger_action >= 0 && !IsWaitCommandAllowed();
	if (!checkAimbot && !checkTrigger)
		return;

	float eye[3], fwd[3], end[3];
	GetClientEyePosition(client, eye);
	GetAngleVectors(angles, fwd, NULL_VECTOR, NULL_VECTOR);
	end[0] = eye[0] + fwd[0] * 999999.0;
	end[1] = eye[1] + fwd[1] * 999999.0;
	end[2] = eye[2] + fwd[2] * 999999.0;

	Handle tr = TR_TraceRayFilterEx(eye, end, MASK_SHOT, RayType_EndPoint, TraceFilterNotSelf, client);
	int target = TR_DidHit(tr) ? TR_GetEntityIndex(tr) : -1;
	int hitgroup = (target > 0) ? TR_GetHitGroup(tr) : 0;
	delete tr;

	bool onEnemy = (target > 0 && target <= MaxClients && IsClientInGame(target) && IsPlayerAlive(target) && GetClientTeam(target) != GetClientTeam(client));

	// Aimbot: a large view snap that lands exactly on an enemy, same hitgroup, while firing.
	if (checkAimbot)
	{
		float delta = NormalizeAngle(angles[1] - g_prevAngles[client][1]);
		if (onEnemy && (delta > float(bd_aimbot_delta) || delta < -float(bd_aimbot_delta)) && (buttons & IN_ATTACK) && hitgroup == g_lastHitGroup[client])
			g_aimbotStreak[client]++;
		else if (buttons & IN_ATTACK)
			g_aimbotStreak[client] = 0;

		if (onEnemy)
			g_lastHitGroup[client] = hitgroup;

		if (g_aimbotStreak[client] >= bd_aimbot_streak)
		{
			char ev[64];
			FormatEx(ev, sizeof(ev), "%d snap-to-enemy shots", g_aimbotStreak[client]);
			g_aimbotStreak[client] = 0;
			FlagBehavioral(client, bd_aimbot_action, "Aimbot", ev);
		}
	}

	// Triggerbot: attack fired on the exact tick the crosshair reaches an enemy, repeatedly.
	if (checkTrigger)
	{
		if (onEnemy)
		{
			g_onTargetTicks[client]++;
			if ((buttons & IN_ATTACK) && !(g_lastButtons[client] & IN_ATTACK) && g_onTargetTicks[client] == g_prevOnTargetTicks[client])
			{
				g_triggerStreak[client]++;
				if (g_triggerStreak[client] >= bd_trigger_streak)
				{
					char ev[64];
					FormatEx(ev, sizeof(ev), "%d tick-perfect shots on target", g_triggerStreak[client]);
					g_triggerStreak[client] = 0;
					FlagBehavioral(client, bd_trigger_action, "Triggerbot", ev);
				}
			}
		}
		else
		{
			if (g_onTargetTicks[client] > 0)
				g_prevOnTargetTicks[client] = g_onTargetTicks[client];
			g_onTargetTicks[client] = 0;
		}
	}
}

public bool TraceFilterNotSelf(int entity, int mask, any data)
{
	return entity != data;
}

float NormalizeAngle(float angle)
{
	// Client-supplied yaw is never sanitized upstream: Detect_AngleClamp only bounds pitch and roll,
	// and is skipped when disabled. An unbounded subtract loop hangs the server on a hostile value
	// - infinity never converges (inf - 360.0 == inf) and a large finite angle costs millions of
	// iterations - and this runs per client per tick. The range test is written so NaN and both infinities fail.
	if (!(angle > -3600.0 && angle < 3600.0))
		return 0.0;
	while (angle > 180.0) angle -= 360.0;
	while (angle < -180.0) angle += 360.0;
	return angle;
}

// BASH2 ports (Blacky's Anti-Strafehack / shavit-bash2)
float BashMean(const int[] arr, int count)
{
	if (count <= 0)
		return 0.0;
	int total = 0;
	for (int i = 0; i < count; i++)
		total += arr[i];
	return float(total) / float(count);
}

float BashDev(const int[] arr, int count, float mean)
{
	if (count <= 0)
		return 0.0;
	float sd = 0.0;
	for (int i = 0; i < count; i++)
		sd += Pow(float(arr[i]) - mean, 2.0);
	return SquareRoot(sd / count);
}

// Turn/keypress sync statistics. A strafehack turns the view in lockstep with A/D input, so the
// tick offset between turn-direction change and key press shows near-zero variance over 50
// strafes. Humans jitter. Turnbind (+left/+right) users are skipped: their turns pair by design.
void UpdateBashTracking(int client, int buttons, const float angles[3], bool onGround, bool walking)
{
	int n = g_bashCmdNum[client];

	// Turn state from the yaw delta (uses g_prevAngles, updated after all detectors).
	float diff = NormalizeAngle(angles[1] - g_prevAngles[client][1]);
	g_bashYawDiff[client] = diff;
	if (diff == 0.0 && g_bashIsTurning[client])
	{
		g_bashStopTurnTick[client] = n;
		g_bashIsTurning[client] = false;
	}
	else if (diff > 0.0 && g_bashTurnDir[client] == 1)
	{
		g_bashTurnTick[client] = n;
		g_bashTurnDir[client] = 0;
		g_bashIsTurning[client] = true;
	}
	else if (diff < 0.0 && g_bashTurnDir[client] == 0)
	{
		g_bashTurnTick[client] = n;
		g_bashTurnDir[client] = 1;
		g_bashIsTurning[client] = true;
	}

	// Key press/release edges: 0 W, 1 S, 2 A, 3 D.
	static const int btnBits[4] = { IN_FORWARD, IN_BACK, IN_MOVELEFT, IN_MOVERIGHT };
	for (int i = 0; i < 4; i++)
	{
		bool held = (buttons & btnBits[i]) != 0;
		bool was = (g_lastButtons[client] & btnBits[i]) != 0;
		if (held && !was)
		{
			g_bashPressTick[client][i] = n;
			g_gainStrafes[client]++;
		}
		else if (!held && was)
			g_bashReleaseTick[client][i] = n;
	}

	if (bd_strafe_action < 0)
		return;
	if (onGround || !walking || GetEntProp(client, Prop_Send, "m_nWaterLevel") > 0)
		return;
	if (IsMovementSuppressed(client) || (buttons & (IN_LEFT | IN_RIGHT)))
		return;
	if ((buttons & IN_BACK))
		return; // backward strafing inverts the key/turn mapping; skip for simplicity

	// Start strafe: A pairs with a left turn, D with a right turn, within +-15 ticks.
	static const int keyForDir[2] = { 2, 3 };
	int dir = g_bashTurnDir[client];
	int key = keyForDir[dir];
	bool pressedNow = g_bashPressTick[client][key] == n;
	bool turnedNow = g_bashIsTurning[client] && g_bashTurnTick[client] == n;
	if ((pressedNow || turnedNow) && g_bashIsTurning[client]
		&& (buttons & btnBits[key])
		&& g_bashStartRecTick[client] != n
		&& g_bashPressRecorded[client][key] != g_bashPressTick[client][key]
		&& g_bashTurnRecStart[client] != g_bashTurnTick[client])
	{
		int d = g_bashPressTick[client][key] - g_bashTurnTick[client];
		if (d >= -15 && d <= 15)
			RecordBashStrafe(client, key, d, true);
	}

	// End strafe: release of the strafe key pairs with the turn stopping/flipping.
	for (int i = 2; i <= 3; i++)
	{
		if (g_bashReleaseTick[client][i] != n)
			continue;
		int endRef = (g_bashTurnTick[client] > g_bashStopTurnTick[client]) ? g_bashTurnTick[client] : g_bashStopTurnTick[client];
		if (g_bashEndRecTick[client] == n || g_bashReleaseRecorded[client][i] == g_bashReleaseTick[client][i] || g_bashTurnRecEnd[client] == endRef)
			continue;
		int d = g_bashReleaseTick[client][i] - endRef;
		if (d >= -15 && d <= 15)
		{
			g_bashTurnRecEnd[client] = endRef;
			RecordBashStrafe(client, i, d, false);
		}
	}
}

void RecordBashStrafe(int client, int key, int diff, bool start)
{
	int n = g_bashCmdNum[client];
	if (start)
	{
		g_bashPressRecorded[client][key] = g_bashPressTick[client][key];
		g_bashTurnRecStart[client] = g_bashTurnTick[client];
		g_bashStartRecTick[client] = n;

		g_bashStartDiff[client][g_bashStartFrame[client]] = diff;
		g_bashStartFrame[client] = (g_bashStartFrame[client] + 1) % KEVAC_BASH_FRAMES;
		if (g_bashStartFilled[client] < KEVAC_BASH_FRAMES)
			g_bashStartFilled[client]++;

		if (diff == g_bashStartLastDiff[client])
		{
			if (++g_bashStartIdentical[client] >= bd_strafe_identical)
			{
				char ev[96];
				FormatEx(ev, sizeof(ev), "%d consecutive identical start-strafe offsets (%d ticks)", g_bashStartIdentical[client], diff);
				g_bashStartIdentical[client] = 0;
				FlagBehavioral(client, bd_strafe_action, "StrafeSync(identical offsets)", ev);
			}
		}
		else
		{
			g_bashStartLastDiff[client] = diff;
			g_bashStartIdentical[client] = 0;
		}

		if (g_bashStartFrame[client] == 0 && g_bashStartFilled[client] >= KEVAC_BASH_FRAMES)
			EvaluateBashWindow(client, g_bashStartDiff[client], true);
	}
	else
	{
		g_bashReleaseRecorded[client][key] = g_bashReleaseTick[client][key];
		g_bashEndRecTick[client] = n;

		g_bashEndDiff[client][g_bashEndFrame[client]] = diff;
		g_bashEndFrame[client] = (g_bashEndFrame[client] + 1) % KEVAC_BASH_FRAMES;
		if (g_bashEndFilled[client] < KEVAC_BASH_FRAMES)
			g_bashEndFilled[client]++;

		if (diff == g_bashEndLastDiff[client])
		{
			if (++g_bashEndIdentical[client] >= bd_strafe_identical)
			{
				char ev[96];
				FormatEx(ev, sizeof(ev), "%d consecutive identical end-strafe offsets (%d ticks)", g_bashEndIdentical[client], diff);
				g_bashEndIdentical[client] = 0;
				FlagBehavioral(client, bd_strafe_action, "StrafeSync(identical offsets)", ev);
			}
		}
		else
		{
			g_bashEndLastDiff[client] = diff;
			g_bashEndIdentical[client] = 0;
		}

		if (g_bashEndFrame[client] == 0 && g_bashEndFilled[client] >= KEVAC_BASH_FRAMES)
			EvaluateBashWindow(client, g_bashEndDiff[client], false);
	}
}

void EvaluateBashWindow(int client, const int[] arr, bool start)
{
	float mean = BashMean(arr, KEVAC_BASH_FRAMES);
	float sd = BashDev(arr, KEVAC_BASH_FRAMES, mean);
	if (sd >= 0.7)
		return;

	char ev[112];
	FormatEx(ev, sizeof(ev), "%s-strafe deviation %.2f (avg %.2f) over %d strafes", start ? "start" : "end", sd, mean, KEVAC_BASH_FRAMES);
	// Below the ban line the configured action fires; above it this is evidence.
	FlagBehavioral(client, sd <= bd_strafe_dev_ban ? bd_strafe_action : NONE, start ? "StrafeSync(start strafe timing)" : "StrafeSync(end strafe timing)", ev);
}

// ---- Air-gain / strafes-per-jump (bash2 gainlog) ----
public Action Event_PlayerJump(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client < 1 || client > MaxClients || bd_gain_action < 0 || !bd_enable || !status || IsBehavioralBypassed(client))
		return Plugin_Continue;

	if (++g_gainJumps[client] >= 6)
	{
		float gain = GetGainPercent(client);
		if (g_gainStrafeTicks[client] > 300 && gain >= 85.0)
		{
			float yawPct = (float(g_gainYawTicks[client]) / float(g_gainStrafeTicks[client])) * 100.0;
			float jumps = g_gainFirstSix[client] ? 5.0 : 6.0;
			float spj = (jumps * (0.75 * g_tickrate) / g_gainStrafeTicks[client]) * (g_gainStrafes[client] / jumps);
			ProcessGainLog(client, gain, spj, yawPct);
		}
		g_gainJumps[client] = 0;
		g_gainRaw[client] = 0.0;
		g_gainStrafeTicks[client] = 0;
		g_gainYawTicks[client] = 0;
		g_gainStrafes[client] = 0;
		g_gainFirstSix[client] = false;
	}
	return Plugin_Continue;
}

void ProcessGainLog(int client, float gain, float spj, float yawPct)
{
	g_lastGainPct[client] = gain;
	g_lastSpj[client] = spj;

	bool ban = spj >= bd_gain_spj_ban
		|| (gain >= 94.0 && yawPct == 0.0 && spj >= 0.4)
		|| (gain >= 91.0 && spj >= 3.0);
	bool sus = ban
		|| (yawPct <= 30.0 && gain >= 93.0 && spj >= 1.0)
		|| (gain >= 88.0 && spj >= 3.4)
		|| (gain >= 87.0 && spj >= 4.0);

	if (!sus && !(gain >= 90.0 && spj >= 2.0) && spj < 3.5)
		return; // unremarkable window

	char ev[128];
	FormatEx(ev, sizeof(ev), "gain %.2f%% spj %.1f turnbind %.1f%% over %d ticks", gain, spj, yawPct, g_gainStrafeTicks[client]);
	FlagBehavioral(client, ban ? bd_gain_action : NONE, sus ? "GainStats(SUSPICIOUS)" : "GainStats(high)", ev);
}

void Detect_Gain(int client, const float vel[3], const float angles[3], int buttons, bool onGround)
{
	if (bd_gain_action < 0)
		return;

	if (onGround)
	{
		if (g_gainGroundTicks[client] > 15)
		{
			g_gainJumps[client] = 0;
			g_gainStrafeTicks[client] = 0;
			g_gainRaw[client] = 0.0;
			g_gainYawTicks[client] = 0;
			g_gainStrafes[client] = 0;
			g_gainFirstSix[client] = true;
		}
		g_gainGroundTicks[client]++;
		g_touchWall[client] = false;
		g_touchRotating[client] = false;
		return;
	}
	g_gainGroundTicks[client] = 0;

	if (!IsNormalWalkMovement(client) || IsMovementSuppressed(client))
		return;

	bool yawing = ((buttons & IN_LEFT) != 0) != ((buttons & IN_RIGHT) != 0);
	if (yawing)
		g_gainYawTicks[client]++;

	g_gainStrafeTicks[client]++;
	if (g_gainStrafeTicks[client] >= 1000)
	{
		g_gainRaw[client] *= 998.0 / 999.0;
		g_gainStrafeTicks[client]--;
	}

	float velocity[3];
	GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", velocity);
	if (velocity[0] == 0.0 && velocity[1] == 0.0)
		return;

	float fore[3], side[3], wishvel[3], wishdir[3];
	GetAngleVectors(angles, fore, side, NULL_VECTOR);
	fore[2] = 0.0;
	side[2] = 0.0;
	NormalizeVector(fore, fore);
	NormalizeVector(side, side);
	for (int i = 0; i < 2; i++)
		wishvel[i] = fore[i] * vel[0] + side[i] * vel[1];
	wishvel[2] = 0.0;

	float wishspeed = NormalizeVector(wishvel, wishdir);
	float maxspeed = GetEntPropFloat(client, Prop_Send, "m_flMaxspeed");
	if (wishspeed > maxspeed)
		wishspeed = maxspeed;
	if (wishspeed <= 0.0)
		return;

	float wishspd = (wishspeed > 30.0) ? 30.0 : wishspeed;
	float currentgain = GetVectorDotProduct(velocity, wishdir);
	float gaincoeff = 0.0;
	if (currentgain < 30.0)
		gaincoeff = (wishspd - FloatAbs(currentgain)) / wishspd;
	if (g_touchWall[client] && gaincoeff > 0.5)
		gaincoeff = FloatAbs(gaincoeff - 1.0);
	if (!g_touchRotating[client])
		g_gainRaw[client] += gaincoeff;

	g_touchWall[client] = false;
	g_touchRotating[client] = false;
}

float GetGainPercent(int client)
{
	if (g_gainStrafeTicks[client] == 0)
		return 0.0;
	float pct = (g_gainRaw[client] / g_gainStrafeTicks[client]) * 100.0;
	return RoundToFloor(pct * 100.0 + 0.5) / 100.0;
}

public Action Hook_OnTouch(int client, int entity)
{
	if (entity == 0)
		g_touchWall[client] = true;
	else if (IsValidEntity(entity))
	{
		char cls[64];
		GetEntityClassname(entity, cls, sizeof(cls));
		if (StrEqual(cls, "func_rotating"))
			g_touchRotating[client] = true;
	}
	return Plugin_Continue;
}

// ---- Impossible sidemove / button-move mismatch (bash2) ----
// CS:GO keyboard move values quantize to multiples of 6.25 with defaults, and full inputs sit at
// {0, +-225, +-450}. A strafehack writing arbitrary sidemove fails both. Optionally neutralized.
void Detect_IllegalMove(int client, int buttons, float vel[3], bool &modified, bool mouseStrafe)
{
	if (bd_illegalmove_action < 0)
		return;
	if (!IsNormalWalkMovement(client) || IsMovementSuppressed(client) || g_mJoystick[client] != 0
		|| (buttons & (IN_LEFT | IN_RIGHT)) || mouseStrafe)
	{
		// Turn keys can be converted into sidemove without IN_MOVELEFT/RIGHT.
		g_invalidBtnMove[client] = 0;
		g_illegalSidemove[client] = 0;
		return;
	}
	if (GetGameTime() < g_teleportGraceUntil[client])
		return;

	// Button/sidemove combination mismatch (bash2 reasons 1-6). Note vel[1] > 0 is
	// moveright in Source.
	g_lastInvalidBtnMove[client] = g_invalidBtnMove[client];
	bool invalid = false;
	bool left = (buttons & IN_MOVELEFT) != 0;
	bool right = (buttons & IN_MOVERIGHT) != 0;
	if (vel[1] > 0.0 && left && !right)       { invalid = true; g_invalidReason[client] = 1; }
	else if (vel[1] < 0.0 && right && !left)  { invalid = true; g_invalidReason[client] = 3; }
	else if (vel[1] != 0.0 && left && right)  { invalid = true; g_invalidReason[client] = 2; }
	else if (vel[1] != 0.0 && !left && !right){ invalid = true; g_invalidReason[client] = 6; }
	else if (vel[1] == 0.0 && (left != right)){ invalid = true; g_invalidReason[client] = 5; }

	if (invalid)
	{
		g_invalidBtnMove[client]++;
		if (g_invalidBtnMove[client] >= 4 && bd_illegalmove_zero)
		{
			vel[0] = 0.0; vel[1] = 0.0; vel[2] = 0.0;
			modified = true;
		}
	}
	else
	{
		if (g_invalidBtnMove[client] == 0 && g_lastInvalidBtnMove[client] >= 10)
		{
			char ev[96];
			FormatEx(ev, sizeof(ev), "buttons/sidemove mismatch x%d (reason %d)", g_lastInvalidBtnMove[client], g_invalidReason[client]);
			FlagBehavioral(client, NONE, "IllegalMove(button/sidemove mismatch)", ev);
		}
		g_invalidBtnMove[client] = 0;
	}

	// Quantization check only applies to default 450 move speeds.
	if (g_fwdSpeed[client] != 450 || g_sideSpeed[client] != 450)
		return;

	bool illegal = false;
	if (RoundToFloor(vel[0] * 100.0) % 625 != 0 || RoundToFloor(vel[1] * 100.0) % 625 != 0)
		illegal = true;
	else
	{
		float f = FloatAbs(vel[0]);
		float s = FloatAbs(vel[1]);
		bool fOk = f < 0.01 || FloatAbs(f - 450.0) < 0.01 || FloatAbs(f - 225.0) < 0.01;
		bool sOk = s < 0.01 || FloatAbs(s - 450.0) < 0.01 || FloatAbs(s - 225.0) < 0.01;
		if (!fOk || !sOk)
			illegal = true;
	}

	if (illegal)
	{
		g_illegalSidemove[client]++;
		if (FloatAbs(g_bashYawDiff[client]) > 0.0)
			g_illegalYawChanges[client]++;
		if (g_illegalSidemove[client] >= 4 && bd_illegalmove_zero)
		{
			vel[0] = 0.0; vel[1] = 0.0; vel[2] = 0.0;
			modified = true;
		}
	}
	else
	{
		if (g_lastIllegalSidemove[client] >= 10 && g_illegalSidemove[client] == 0)
		{
			// Turning through the illegal-value run means the values steer the view
			// (strafehack), not a macro artifact - that is the ban-grade path.
			bool banGrade = (float(g_illegalYawChanges[client]) / float(g_lastIllegalSidemove[client])) > 0.3;
			char ev[112];
			FormatEx(ev, sizeof(ev), "impossible sidemove values x%d (yaw changes %d)", g_lastIllegalSidemove[client], g_illegalYawChanges[client]);
			FlagBehavioral(client, banGrade ? bd_illegalmove_action : NONE, "IllegalMove(impossible sidemove)", ev);
			g_illegalYawChanges[client] = 0;
		}
		g_illegalSidemove[client] = 0;
	}
	g_lastIllegalSidemove[client] = g_illegalSidemove[client];
}

// ---- Slow usercmd rate (speedhack / lag-switch, bash2) ----
// Fake lag = the client withholds usercmds for several ticks then releases the backlog at once,
// so its model updates in jerks and lag compensation works against whoever is shooting at it.
// The discriminator against a bad connection is LOSS, not rate:
//   real packet loss -> usercmds destroyed -> cmdnum GAPS, low total
//   real jitter      -> irregular bunching -> variable burst sizes, gaps
//   fake lag         -> usercmds DELAYED   -> zero gaps, regular bursts
// A withholding client must eventually deliver every command or desync itself, so a gapless
// stream arriving in fat periodic clumps is the signature. Strong evidence, NOT proof: a
// buffering router does the same, which is why this ships log-only.
void Detect_FakeLag(int client, int cmdnum)
{
	// Tracking always runs even with the detector off: Detect_AHKStrafe needs
	// g_flThisTickRun to know whether this usercmd arrived one-per-tick or as
	// part of a delivery burst. Only the ACTION is gated by the cvars below.
	int nowTick = GetGameTickCount();

	// Gap tracking. cmdnum increments by exactly 1 per command on a healthy
	// stream; anything larger is commands that never arrived, i.e. real loss.
	if (g_flLastCmdnum[client] != 0 && cmdnum > g_flLastCmdnum[client])
	{
		int step = cmdnum - g_flLastCmdnum[client];
		if (step > 1)
			g_flMissing[client] += step - 1;
	}
	g_flLastCmdnum[client] = cmdnum;

	// Burst tracking: how many usercmds the server processes for this client
	// inside one server tick.
	if (nowTick == g_flLastTick[client])
	{
		g_flThisTickRun[client]++;
	}
	else
	{
		g_flLastTick[client] = nowTick;
		g_flThisTickRun[client] = 1;
	}

	if (g_flThisTickRun[client] > g_flBurstMax[client])
		g_flBurstMax[client] = g_flThisTickRun[client];

	if (g_flThisTickRun[client] == bd_fakelag_burst)
	{
		g_flBurstHits[client]++;
		g_flServerBurstTick[client] = nowTick;
	}

	if (bd_fakelag_action < 0 && !bd_fakelag_observe)
		return;

	// Own one-second window: Detect_CmdRate's window stops rolling whenever
	// kevac_cmdrate_action is disabled, so this cannot piggyback on it.
	float now = GetEngineTime();
	if (g_flWindowStart[client] == 0.0)
	{
		g_flWindowStart[client] = now;
		return;
	}
	if (now - g_flWindowStart[client] < 1.0)
		return;

	g_flWindowStart[client] = now;
	EvaluateFakeLagWindow(client);
}

// A lagging client is not a macro. When packets bunch, the server processes several usercmds in
// one tick and replays backup commands, so consecutive commands legitimately carry the SAME
// mouse delta - exactly what Detect_AHKStrafe matches on. Samples taken then are untrustworthy.
bool AhkNetworkUnreliable(int client)
{
	// This usercmd did not arrive one-per-tick: it came in a delivery burst.
	if (g_flThisTickRun[client] > 1)
		return true;

	if (GetClientAvgLoss(client, NetFlow_Incoming) * 100.0 > bd_ahk_maxnet)
		return true;

	if (GetClientAvgChoke(client, NetFlow_Incoming) * 100.0 > bd_ahk_maxnet)
		return true;

	return false;
}

// Did anyone ELSE burst on the same server tick? A server frame hitch delivers
// every client's backlog at once, which looks identical to fake lag on a single
// client. Only a client bursting alone is anomalous.
bool FakeLagBurstWasIsolated(int client)
{
	int tick = g_flServerBurstTick[client];
	if (tick == 0)
		return false;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (i == client || !IsClientInGame(i) || IsFakeClient(i))
			continue;
		// Same tick, and they burst too - that is the server stalling, not them.
		if (g_flServerBurstTick[i] == tick)
			return false;
	}
	return true;
}

void EvaluateFakeLagWindow(int client)
{
	if (bd_fakelag_action < 0 && !bd_fakelag_observe)
	{
		g_flMissing[client] = 0;
		g_flBurstMax[client] = 0;
		g_flBurstHits[client] = 0;
		return;
	}

	int missing = g_flMissing[client];
	int burstMax = g_flBurstMax[client];
	int hits = g_flBurstHits[client];
	bool isolated = FakeLagBurstWasIsolated(client);

	g_flMissing[client] = 0;
	g_flBurstMax[client] = 0;
	g_flBurstHits[client] = 0;

	if (bd_fakelag_observe)
	{
		char sAuthID[32];
		if (!GetClientAuthId(client, AuthId_Steam2, sAuthID, sizeof(sAuthID)))
			strcopy(sAuthID, sizeof(sAuthID), "UNKNOWN");
		LogToFile("addons/sourcemod/logs/KevAC.log",
			"[KevAC] [fakelag-observe] %N (%s) burstmax=%d hits=%d missing=%d isolated=%s loss=%.1f%% choke=%.1f%% ping=%.0fms",
			client, sAuthID, burstMax, hits, missing, isolated ? "yes" : "no",
			GetClientAvgLoss(client, NetFlow_Incoming) * 100.0,
			GetClientAvgChoke(client, NetFlow_Incoming) * 100.0,
			GetClientAvgLatency(client, NetFlow_Outgoing) * 1000.0);
	}

	if (bd_fakelag_action < 0)
		return;

	// All four must hold: fat bursts, repeatedly, with nothing actually lost,
	// and not shared with the rest of the server.
	bool qualifies = (burstMax >= bd_fakelag_burst)
		&& (hits >= bd_fakelag_hits)
		&& (missing == 0)
		&& isolated;

	if (!qualifies)
	{
		g_flBadSeconds[client] = 0;
		return;
	}

	if (++g_flBadSeconds[client] < bd_fakelag_seconds)
		return;

	g_flBadSeconds[client] = 0;

	char ev[192];
	FormatEx(ev, sizeof(ev), "usercmds delivered in bursts of %d (%d/s) for %ds with 0 lost commands and %.1f%% measured loss",
		burstMax, hits, bd_fakelag_seconds, GetClientAvgLoss(client, NetFlow_Incoming) * 100.0);
	FlagBehavioral(client, bd_fakelag_action, "FakeLag", ev);
}

void Detect_CmdRate(int client)
{
	if (bd_cmdrate_action < 0)
	{
		if (g_cmdFrozen[client])
		{
			SetEntityMoveType(client, g_cmdSavedMoveType[client]);
			g_cmdFrozen[client] = false;
		}
		return;
	}

	if (!g_cmdFrozen[client] && GetEntityMoveType(client) != MOVETYPE_NONE)
		g_cmdSavedMoveType[client] = GetEntityMoveType(client);

	g_cmdCount[client]++;
	if (g_cmdWindowStart[client] == 0.0)
		g_cmdWindowStart[client] = GetEngineTime();
	if (GetEngineTime() - g_cmdWindowStart[client] < 1.0)
		return;

	float ratio = float(g_cmdCount[client]) / g_tickrate;
	g_cmdCount[client] = 0;
	g_cmdWindowStart[client] = GetEngineTime();

	if (ratio <= 0.95)
	{
		if (++g_cmdBadSeconds[client] == 3)
		{
			char ev[96];
			FormatEx(ev, sizeof(ev), "usercmd rate at %.0f%% of tickrate for 3s", ratio * 100.0);
			FlagBehavioral(client, NONE, "CmdRate(slow usercmd rate)", ev);
			if (bd_cmdrate_action >= 1 && !g_cmdFrozen[client])
			{
				g_cmdFrozen[client] = true;
				SetEntityMoveType(client, MOVETYPE_NONE);
			}
		}
	}
	else
	{
		g_cmdBadSeconds[client] = 0;
		if (g_cmdFrozen[client])
		{
			SetEntityMoveType(client, g_cmdSavedMoveType[client]);
			g_cmdFrozen[client] = false;
		}
	}
}

// ---- Admin commands (bash2_stats equivalent + extension health) ----
public Action CommandStats(int client, int args)
{
	int target = client;
	if (args >= 1)
	{
		char arg[65];
		GetCmdArg(1, arg, sizeof(arg));
		target = FindTarget(client, arg, true, false);
		if (target < 1)
			return Plugin_Handled;
	}
	else if (client == 0)
	{
		ReplyToCommand(client, "[KevAC] Usage: sm_kevac_stats <player>");
		return Plugin_Handled;
	}

	float sMean = BashMean(g_bashStartDiff[target], g_bashStartFilled[target]);
	float sDev = BashDev(g_bashStartDiff[target], g_bashStartFilled[target], sMean);
	float eMean = BashMean(g_bashEndDiff[target], g_bashEndFilled[target]);
	float eDev = BashDev(g_bashEndDiff[target], g_bashEndFilled[target], eMean);

	ReplyToCommand(client, "[KevAC] BASH stats for %N:", target);
	ReplyToCommand(client, "  start strafes: %d/%d sampled | dev %.2f avg %.2f | identical run %d", g_bashStartFilled[target], KEVAC_BASH_FRAMES, sDev, sMean, g_bashStartIdentical[target]);
	ReplyToCommand(client, "  end strafes:   %d/%d sampled | dev %.2f avg %.2f | identical run %d", g_bashEndFilled[target], KEVAC_BASH_FRAMES, eDev, eMean, g_bashEndIdentical[target]);
	ReplyToCommand(client, "  last gain window: gain %.2f%% spj %.1f | live gain %.2f%%", g_lastGainPct[target], g_lastSpj[target], GetGainPercent(target));
	ReplyToCommand(client, "  mouse model: sens %.3f m_yaw %.4f rawinput %d filter %d accel %d joystick %d (-1 = not answered)", g_sens[target], g_myaw[target], g_mRawInput[target], g_mFilter[target], g_mCustomAccel[target], g_mJoystick[target]);
	ReplyToCommand(client, "  listeners: %d active subscriptions, %d blacklisted", g_listenerActiveSubscriptions[target], g_listenerBlacklistedSubscriptions[target]);
	return Plugin_Handled;
}

int LogListenerAuditSnapshot(int client, const char[] reason, bool force)
{
	if ((!force && !gcv_listener_audit_log.BoolValue) ||
		GetFeatureStatus(FeatureType_Native, "KevAC_GetAllListenerAuditEvents") != FeatureStatus_Available ||
		!IsClientInGame(client) || IsFakeClient(client))
	{
		return -2;
	}

	if (!force && (g_listenerMaskFingerprint[client] == 0 || g_listenerAuditLoggedFingerprint[client] == g_listenerMaskFingerprint[client]))
		return -2;

	char events[4096];
	int eventCount = KevAC_GetAllListenerAuditEvents(client, events, sizeof(events));
	if (eventCount < 0)
		return eventCount;

	char steamId[32];
	if (!GetClientAuthId(client, AuthId_Steam2, steamId, sizeof(steamId), true))
		strcopy(steamId, sizeof(steamId), "unavailable");
	LogToFile("addons/sourcemod/logs/KevAC-listeners.log", "[KevAC] %N (%s) | %s | %d/%d catalog listener(s): %s", client, steamId, reason, eventCount, g_listenerActiveSubscriptions[client], events);
	g_listenerAuditLoggedFingerprint[client] = g_listenerMaskFingerprint[client];
	return eventCount;
}

public Action CommandStabTrace(int client, int args)
{
	if (args < 1 || args > 2)
	{
		ReplyToCommand(client, "%T", "StabTrace_Usage", client);
		return Plugin_Handled;
	}

	char targetArg[65];
	GetCmdArg(1, targetArg, sizeof(targetArg));
	int target = FindTarget(client, targetArg, true, false);
	if (target < 1 || IsFakeClient(target))
		return Plugin_Handled;

	if (GetClientUserId(target) == g_stabTraceTargetUserId)
	{
		StopStabTrace("stopped by admin");
		ReplyToCommand(client, "%T", "StabTrace_Stopped", client, target);
		return Plugin_Handled;
	}

	float duration = 45.0;
	if (args == 2)
	{
		char durationArg[16];
		GetCmdArg(2, durationArg, sizeof(durationArg));
		duration = StringToFloat(durationArg);
	}
	if (duration < 5.0)
		duration = 5.0;
	else if (duration > 120.0)
		duration = 120.0;

	StopStabTrace("replaced by a new admin trace");
	g_stabTraceTargetUserId = GetClientUserId(target);
	g_stabTraceUntil = GetGameTime() + duration;
	char initiator[64];
	if (client > 0 && IsClientInGame(client))
		GetClientName(client, initiator, sizeof(initiator));
	else
		strcopy(initiator, sizeof(initiator), "Console");
	LogToFile("addons/sourcemod/logs/KevAC-stabtrace.log", "[KevAC-StabTrace] session=%d started by %s for %N (%.0f seconds)", g_stabTraceSessionId, initiator, target, duration);
	CreateTimer(duration, Timer_StabTraceExpire, g_stabTraceSessionId, TIMER_FLAG_NO_MAPCHANGE);
	ReplyToCommand(client, "%T", "StabTrace_Started", client, target, RoundToNearest(duration));
	return Plugin_Handled;
}

// Full cohort snapshot for calibration and later comparison. It writes only
// server-decoded listener tables, never invents client subscriptions, and does
// not flag or punish anyone.
public Action CommandListenerAuditAll(int client, int args)
{
	if (args != 0)
	{
		ReplyToCommand(client, "%T", "ListenerAuditAll_Usage", client);
		return Plugin_Handled;
	}

	if (GetFeatureStatus(FeatureType_Native, "KevAC_GetAllListenerAuditEvents") != FeatureStatus_Available)
	{
		ReplyToCommand(client, "%T", "ListenerAudit_NativeMissing", client);
		return Plugin_Handled;
	}

	int connected = 0;
	int logged = 0;
	int unavailable = 0;
	for (int target = 1; target <= MaxClients; target++)
	{
		if (!IsClientInGame(target) || IsFakeClient(target))
			continue;

		connected++;
		int eventCount = LogListenerAuditSnapshot(target, "manual all-player listener audit", true);
		if (eventCount < 0)
			unavailable++;
		else
			logged++;
	}

	ReplyToCommand(client, "%T", "ListenerAuditAll_Logged", client, logged, connected, unavailable);
	return Plugin_Handled;
}

public Action CommandListenerAudit(int client, int args)
{
	if (args < 1)
	{
		ReplyToCommand(client, "%T", "ListenerAudit_Usage", client);
		return Plugin_Handled;
	}

	char targetArg[65];
	GetCmdArg(1, targetArg, sizeof(targetArg));
	int target = FindTarget(client, targetArg, true, false);
	if (target < 1)
		return Plugin_Handled;

	if (GetFeatureStatus(FeatureType_Native, "KevAC_AuditListenerCandidates") != FeatureStatus_Available)
	{
		ReplyToCommand(client, "%T", "ListenerAudit_NativeMissing", client);
		return Plugin_Handled;
	}

	char candidates[256];
	if (args >= 2)
		GetCmdArg(2, candidates, sizeof(candidates));
	else
		strcopy(candidates, sizeof(candidates), "item_purchase,bullet_impact,player_hurt,player_blind");

	if (StrEqual(candidates, "all", false))
	{
		if (GetFeatureStatus(FeatureType_Native, "KevAC_GetAllListenerAuditEvents") != FeatureStatus_Available)
		{
			ReplyToCommand(client, "%T", "ListenerAudit_NativeMissing", client);
			return Plugin_Handled;
		}
		int eventCount = LogListenerAuditSnapshot(target, "manual full listener audit", true);
		if (eventCount < 0)
			ReplyToCommand(client, "%T", "ListenerAudit_NoTelemetry", client, target);
		else
			ReplyToCommand(client, "%T", "ListenerAudit_AllLogged", client, target, eventCount, g_listenerActiveSubscriptions[target]);
		return Plugin_Handled;
	}

	char matches[256];
	int matchCount = KevAC_AuditListenerCandidates(target, candidates, matches, sizeof(matches));
	if (matchCount < 0)
	{
		ReplyToCommand(client, "%T", "ListenerAudit_NoTelemetry", client, target);
		return Plugin_Handled;
	}

	if (matchCount == 0)
		ReplyToCommand(client, "%T", "ListenerAudit_None", client, target, candidates);
	else
		ReplyToCommand(client, "%T", "ListenerAudit_Result", client, target, matchCount, matches);

	return Plugin_Handled;
}

// Chat variant for menu selections (ReplyToCommand needs a command context).
void PrintStatsChat(int viewer, int target)
{
	float sMean = BashMean(g_bashStartDiff[target], g_bashStartFilled[target]);
	float sDev = BashDev(g_bashStartDiff[target], g_bashStartFilled[target], sMean);
	float eMean = BashMean(g_bashEndDiff[target], g_bashEndFilled[target]);
	float eDev = BashDev(g_bashEndDiff[target], g_bashEndFilled[target], eMean);

	KevACPrintToChat(viewer, "%T", "Stats_Title", viewer, target);
	KevACPrintToChat(viewer, "%T", "Stats_Strafe", viewer,
		g_bashStartFilled[target], KEVAC_BASH_FRAMES, sDev, sMean, g_bashStartIdentical[target],
		g_bashEndFilled[target], KEVAC_BASH_FRAMES, eDev, eMean, g_bashEndIdentical[target]);
	KevACPrintToChat(viewer, "%T", "Stats_Gain", viewer, g_lastGainPct[target], g_lastSpj[target], GetGainPercent(target));
}

public Action CommandExtStatus(int client, int args)
{
	// GetExtensionFileStatus: -2 no file, -1 load error, 0 not running, 1 running.
	char err[256];
	int st = GetExtensionFileStatus("KevAC.ext", err, sizeof(err));
	if (st == 1)
		ReplyToCommand(client, "%T", "Ext_Running", client);
	else
		ReplyToCommand(client, "%T", "Ext_NotRunning", client, st, err);

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i))
		{
			ReplyToCommand(client, "%T", "Ext_ClientTelemetry", client, i, g_listenerActiveSubscriptions[i], g_listenerPeakSubscriptions[i], g_listenerBlacklistedSubscriptions[i], bDetect[i] ? " [PRE-AUTH DETECT PENDING]" : "", g_listenerTelemetrySeen[i] ? "" : " [NO LISTENEVENTS PACKET YET]");
			if (g_listenerTelemetrySeen[i] && g_listenerMaskFingerprint[i] != 0)
				ReplyToCommand(client, "%T", "Ext_ClientFingerprint", client, i, g_listenerMaskFingerprint[i]);
		}
	}
	int rawCalls = g_listenerRawCallbacks;
	int humanCalls = g_listenerHumanCallbacks;
	int acceptedPackets = 0;
	int vtablePackets = 0;
	int telemetryUpdates = 0;
	if (GetFeatureStatus(FeatureType_Native, "KevAC_GetListenerProbeStats") == FeatureStatus_Available)
		KevAC_GetListenerProbeStats(rawCalls, humanCalls, acceptedPackets, vtablePackets, telemetryUpdates);
	if (GetFeatureStatus(FeatureType_Native, "KevAC_IsListenerStaticDetourEnabled") == FeatureStatus_Available)
	{
		if (KevAC_IsListenerStaticDetourEnabled())
			ReplyToCommand(client, "%T", "Ext_StaticRouteEnabled", client);
		else
			ReplyToCommand(client, "%T", "Ext_StaticRouteOff", client);
	}
	else
	{
		ReplyToCommand(client, "%T", "Ext_StaticRouteUnknown", client);
	}
	ReplyToCommand(client, "%T", "Ext_ListenerProbe", client, rawCalls, humanCalls, acceptedPackets, vtablePackets, telemetryUpdates);
	if (telemetryUpdates > 0)
		ReplyToCommand(client, "%T", "Ext_ListenerVerified", client, telemetryUpdates);
	else if (rawCalls > 0 || vtablePackets > 0)
		ReplyToCommand(client, "%T", "Ext_ListenerRawOnly", client);
	else
		ReplyToCommand(client, "%T", "Ext_ListenerUnavailable", client);
	// Two independent listener routes, reported separately so a dormant one is never mistaken for a
	// broken one:
	//   Route A (extension detour): the .so's own ProcessListenEvents hook. Where that symbol is
	//     not found it stays dormant BY DESIGN; telemetry shows if it ever decoded a packet.
	//   Route B (in-plugin vtable hook): blocked on this build, the inferred slot crashed on join.
	int listenerHooks = 0;
	for (int i = 1; i <= MaxClients; i++)
		if (g_listenerMessageHookId[i] != -1)
			listenerHooks++;
	if (!bd_vtable_hooks)
		ReplyToCommand(client, "%T", "Ext_VtableOff", client);
	else if (g_vtableHooksBlocked)
		ReplyToCommand(client, "%T", "Ext_VtableBlocked", client);
	else if (g_hListenerMessageHook != null)
		ReplyToCommand(client, "%T", "Ext_VtableOnOk", client, listenerHooks);
	else
		ReplyToCommand(client, "%T", "Ext_VtableOnFailed", client);
	int hooked = 0;
	int calls = 0;
	int requests = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_fullUpdateHookId[i] != -1)
			hooked++;
		calls += g_fullUpdateCalls[i];
		requests += g_fullUpdateRequests[i];
	}
	ReplyToCommand(client, "%T", "Ext_FullUpdate", client, hooked, calls, requests, bd_fullupdate_action);
	ReplyToCommand(client, "%T", "Ext_ListenerCeiling", client, bd_listener_maxsubs, bd_listener_maxsubs_action);
	if (bd_listener_maxsubs <= 0)
	{
		int maxPeak = 0;
		for (int i = 1; i <= MaxClients; i++)
			if (IsClientInGame(i) && !IsFakeClient(i) && g_listenerPeakSubscriptions[i] > maxPeak)
				maxPeak = g_listenerPeakSubscriptions[i];
		if (maxPeak > 0)
			ReplyToCommand(client, "[KevAC] Ceiling disabled. Highest peak among current clients: %d - with only known-clean players connected, set kevac_listener_max_subs %d.", maxPeak, maxPeak + 2);
	}
	return Plugin_Handled;
}

public void OnAllPluginsLoaded()
{
	char err[256];
	int st = GetExtensionFileStatus("KevAC.ext", err, sizeof(err));
	g_extMissing = (st != 1);
	if (g_extMissing)
		LogError("[KevAC] KevAC.ext is not running (%d: %s) - event-listener DLL detection is DISABLED. Behavioral checks continue.", st, err);

	g_bStyleTimer = LibraryExists("shavit");
	g_bPhysHooks = LibraryExists("PhysHooks");
	SetupTeleportHook();
	SetupFullUpdateHooks();
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "shavit"))
		g_bStyleTimer = true;
	else if (StrEqual(name, "dhooks"))
	{
		SetupTeleportHook();
		SetupFullUpdateHooks();
	}
	else if (StrEqual(name, "PhysHooks"))
		g_bPhysHooks = true;
}

public void OnLibraryRemoved(const char[] name)
{
	if (StrEqual(name, "shavit"))
		g_bStyleTimer = false;
	else if (StrEqual(name, "dhooks"))
		ResetDHookIntegrations();
	else if (StrEqual(name, "PhysHooks"))
		g_bPhysHooks = false;
}

// DHook CBaseEntity::Teleport (offset from sdktools.games) so every plugin teleport, including
// SetOrigin resets that never touch a trigger_teleport, grants the same grace as a spawn. This
// is what shavit-bash2 used dhooks for, and it removes a class of FPs on teleport-heavy maps.
void SetupTeleportHook()
{
	if (g_bDhooks || g_hTeleportHook != null)
		return;
	if (gcv_teleport_hook != null && !gcv_teleport_hook.BoolValue)
		return;
#if defined _dhooks_included
	if (!LibraryExists("dhooks"))
		return;

	Handle conf = LoadGameConfigFile("sdktools.games");
	if (conf == null)
		return;

	int offset = GameConfGetOffset(conf, "Teleport");
	delete conf;
	if (offset == -1)
	{
		LogError("[KevAC] dhooks present but sdktools.games has no Teleport offset - teleport hook disabled.");
		return;
	}

	g_hTeleportHook = DHookCreate(offset, HookType_Entity, ReturnType_Void, ThisPointer_CBaseEntity, Hook_Teleport);
	if (g_hTeleportHook == null)
		return;

	DHookAddParam(g_hTeleportHook, HookParamType_VectorPtr);
	DHookAddParam(g_hTeleportHook, HookParamType_ObjectPtr);
	DHookAddParam(g_hTeleportHook, HookParamType_VectorPtr);
	if (GetEngineVersion() == Engine_CSGO)
		DHookAddParam(g_hTeleportHook, HookParamType_Bool);

	g_bDhooks = true;
	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i) && !IsFakeClient(i))
			DHookEntity(g_hTeleportHook, false, i);
#endif
}

// DHooks can be unloaded and reloaded while KevAC stays loaded. Its raw-hook
// handles become invalid in that case, so discard them and rebuild only after
// the library announces itself again.
void ResetDHookIntegrations()
{
	g_bDhooks = false;
	g_hTeleportHook = null;
	g_hFullUpdateHook = null;
	g_hListenerMessageHook = null;
	g_hGetClientCall = null;
	g_pBaseServer = Address_Null;
	delete g_hKevACGameConf;
	for (int client = 1; client <= MaxClients; client++)
	{
		g_fullUpdateHookId[client] = -1;
		g_fullUpdateClientPtr[client] = Address_Null;
		g_listenerMessageHookId[client] = -1;
		g_listenerMessageHandlerPtr[client] = Address_Null;
	}
}

// The supplied gamedata's vtable values were inferred, not verified against this server, and
// ProcessListenEvents at that slot crashes as soon as a client joins. Keep a positive validation
// gate rather than risking a crash because a config value was set to 1.
bool IsVtableRouteValidatedForThisBuild()
{
	return false;
}

void SetupFullUpdateHooks()
{
#if defined _dhooks_included
	if (!bd_vtable_hooks)
		return;
	if (!IsVtableRouteValidatedForThisBuild())
	{
		g_vtableHooksBlocked = true;
		LogError("[KevAC] Raw vtable telemetry was requested but is BLOCKED: the current CGameClient offsets crashed this server on player join. Route A is unaffected, and all non-vtable detectors remain active.");
		return;
	}
	g_vtableHooksBlocked = false;
	if (g_hKevACGameConf != null || !LibraryExists("dhooks") || GetEngineVersion() != Engine_CSGO)
		return;

	g_hKevACGameConf = LoadGameConfigFile("kevac.games");
	if (g_hKevACGameConf == null)
	{
		LogError("[KevAC] kevac.games is unavailable - full-update AND listener vtable telemetry are disabled.");
		return;
	}

	// Shared prerequisites: both vtable hooks resolve their per-client pointer
	// through CBaseServer::GetClient. Resolve these first so a missing
	// full-update key can never take the listener hook down with it.
	g_pBaseServer = GameConfGetAddress(g_hKevACGameConf, "CBaseServer");
	if (g_pBaseServer == Address_Null)
	{
		LogError("[KevAC] kevac.games could not resolve CBaseServer (stale/stub gamedata?) - full-update AND listener vtable telemetry are disabled. Deploy the current gamedata/kevac.games/engine.csgo.txt.");
		delete g_hKevACGameConf;
		return;
	}

	StartPrepSDKCall(SDKCall_Raw);
	if (!PrepSDKCall_SetFromConf(g_hKevACGameConf, SDKConf_Virtual, "CBaseServer::GetClient"))
	{
		LogError("[KevAC] kevac.games lacks CBaseServer::GetClient - full-update AND listener vtable telemetry are disabled.");
		delete g_hKevACGameConf;
		return;
	}
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	g_hGetClientCall = EndPrepSDKCall();
	if (g_hGetClientCall == null)
	{
		LogError("[KevAC] could not prepare CBaseServer::GetClient - full-update AND listener vtable telemetry are disabled.");
		delete g_hKevACGameConf;
		return;
	}

	// Full-update (skin changer) hook - failure here no longer disables the
	// listener hook below.
	int offset = GameConfGetOffset(g_hKevACGameConf, "CGameClient::UpdateAcknowledgedFramecount");
	if (offset == -1)
	{
		LogError("[KevAC] kevac.games lacks CGameClient::UpdateAcknowledgedFramecount. Full-update telemetry is disabled; the listener hook is unaffected.");
	}
	else
	{
		g_hFullUpdateHook = DHookCreate(offset, HookType_Raw, ReturnType_Void, ThisPointer_Address, Hook_UpdateAcknowledgedFramecount);
		if (g_hFullUpdateHook == null)
			LogError("[KevAC] could not create the PTaH full-update vtable hook.");
		else
			DHookAddParam(g_hFullUpdateHook, HookParamType_Int);
	}

	// VoiceAnnounceEx verifies CGameClient::ProcessVoiceData at vtable index 9 on this branch. The SDK
	// declares ListenEvents two slots later, so index 11 reaches the real handler without a brittle
	// byte pattern. Hooked post-call so the engine has accepted the packet before reading the table.
	int listenerOffset = GameConfGetOffset(g_hKevACGameConf, "CGameClient::ProcessListenEvents");
	if (listenerOffset == -1)
	{
		LogError("[KevAC] kevac.games lacks CGameClient::ProcessListenEvents. Listener vtable telemetry is disabled.");
	}
	else
	{
		g_hListenerMessageHook = DHookCreate(listenerOffset, HookType_Raw, ReturnType_Bool, ThisPointer_Address, Hook_ListenEventsMessage);
		if (g_hListenerMessageHook == null)
		{
			LogError("[KevAC] could not create the ListenEvents vtable hook.");
		}
		else
		{
			DHookAddParam(g_hListenerMessageHook, HookParamType_ObjectPtr);
		}
	}

	// Connected (not just in-game) so late hook setup still covers clients that
	// are mid-signon; Frame_AttachFullUpdateHook applies its own in-game gate.
	for (int client = 1; client <= MaxClients; client++)
		if (IsClientConnected(client) && !IsFakeClient(client))
		{
			RequestFrame(Frame_AttachFullUpdateHook, GetClientUserId(client));
			RequestFrame(Frame_AttachListenerMessageHook, GetClientUserId(client));
		}
#endif
}

public void Frame_AttachFullUpdateHook(any userid)
{
#if defined _dhooks_included
	if (!bd_vtable_hooks || g_vtableHooksBlocked)
		return;
	int client = GetClientOfUserId(userid);
	if (client < 1 || !IsClientInGame(client) || IsFakeClient(client) || g_hFullUpdateHook == null || g_hGetClientCall == null || g_pBaseServer == Address_Null)
		return;

	RemoveFullUpdateHook(client);
	Address iClient = view_as<Address>(SDKCall(g_hGetClientCall, g_pBaseServer, client - 1));
	if (iClient == Address_Null)
		return;

	// CBaseServer::GetClient returns IClient. The CBaseClient vtable object used
	// by UpdateAcknowledgedFramecount begins four bytes before that interface.
	Address baseClient = iClient - view_as<Address>(4);
	int hookId = DHookRaw(g_hFullUpdateHook, false, baseClient, _, Hook_UpdateAcknowledgedFramecount);
	if (hookId == -1)
	{
		LogError("[KevAC] could not attach full-update telemetry for client %d.", client);
		return;
	}

	g_fullUpdateHookId[client] = hookId;
	g_fullUpdateClientPtr[client] = baseClient;
#endif
}

void RemoveFullUpdateHook(int client)
{
#if defined _dhooks_included
	if (client < 1 || client > MaxClients)
		return;
	if (g_fullUpdateHookId[client] != -1 && LibraryExists("dhooks"))
		DHookRemoveHookID(g_fullUpdateHookId[client]);
	g_fullUpdateHookId[client] = -1;
	g_fullUpdateClientPtr[client] = Address_Null;
#endif
}

// This legacy attachment path remains for a future independently validated
// vtable layout. It is unreachable on the current build, whose inferred
// ProcessListenEvents slot crashed during player join.
public void Frame_AttachListenerMessageHook(any userid)
{
#if defined _dhooks_included
	if (!bd_vtable_hooks || g_vtableHooksBlocked)
		return;
	int client = GetClientOfUserId(userid);
	// IsClientConnected, not InGame: the hook must exist during signon to see
	// the client's first listener mask.
	if (client < 1 || !IsClientConnected(client) || IsFakeClient(client) || g_hListenerMessageHook == null || g_hGetClientCall == null || g_pBaseServer == Address_Null)
		return;

	RemoveListenerMessageHook(client);
	Address iClient = view_as<Address>(SDKCall(g_hGetClientCall, g_pBaseServer, client - 1));
	if (iClient == Address_Null)
		return;

	Address messageHandler = iClient + view_as<Address>(4);
	int hookId = DHookRaw(g_hListenerMessageHook, true, messageHandler);
	if (hookId == -1)
	{
		LogError("[KevAC] could not attach ListenEvents vtable telemetry for client %d.", client);
		return;
	}

	g_listenerMessageHookId[client] = hookId;
	g_listenerMessageHandlerPtr[client] = messageHandler;
	// Only a hook that existed during signon can judge ListenEvents silence;
	// a hook attached mid-game (plugin reload) missed the legit first mask.
	if (!IsClientInGame(client))
		g_listenerHookEarly[client] = true;
#endif
}

void RemoveListenerMessageHook(int client)
{
#if defined _dhooks_included
	if (client < 1 || client > MaxClients)
		return;
	if (g_listenerMessageHookId[client] != -1 && LibraryExists("dhooks"))
		DHookRemoveHookID(g_listenerMessageHookId[client]);
	g_listenerMessageHookId[client] = -1;
	g_listenerMessageHandlerPtr[client] = Address_Null;
#endif
}

#if defined _dhooks_included
public MRESReturn Hook_ListenEventsMessage(Address pThis, DHookReturn hReturn, DHookParam hParams)
{
	int client = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_listenerMessageHandlerPtr[i] == pThis)
		{
			client = i;
			break;
		}
	}
	if (client == 0 || !IsClientConnected(client) || IsFakeClient(client) || !hReturn.Value)
		return MRES_Ignored;
	if (GetFeatureStatus(FeatureType_Native, "KevAC_InspectListenEvents") != FeatureStatus_Available)
		return MRES_Ignored;

	Address message = view_as<Address>(hParams.Get(1));
	int activeSubscriptions = 0;
	int blacklistedSubscriptions = 0;
	bool changed = false;
	if (!KevAC_InspectListenEvents(client, pThis, message, activeSubscriptions, blacklistedSubscriptions, changed))
		return MRES_Ignored;

	KevAC_OnListenerTelemetry(client, activeSubscriptions, blacklistedSubscriptions);
	if (blacklistedSubscriptions > 0)
	{
		if (g_listenerBlacklistFlagged[client])
			return MRES_Ignored;

		g_listenerBlacklistFlagged[client] = true;
		if (IsClientInGame(client))
		{
			char evidence[160];
			FormatEx(evidence, sizeof(evidence), "%d blacklisted listener(s) among %d active subscriptions (ProcessListenEvents vtable)", blacklistedSubscriptions, activeSubscriptions);
			FlagBehavioral(client, method, "EventListener(vtable)", evidence);
		}
		else
		{
			bDetect[client] = true;
		}
	}
	else if (changed)
	{
		KevAC_OnListenerUpdate(client);
	}

	return MRES_Ignored;
}
#endif

public Action OnClientFullUpdateCommand(int client, const char[] command, int args)
{
	if (client < 1 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client) || bd_fullupdate_action < 0)
		return Plugin_Continue;

	float now = GetGameTime();
	if (g_fullUpdateWindowStart[client] == 0.0 || now - g_fullUpdateWindowStart[client] > bd_fullupdate_window)
	{
		g_fullUpdateWindowStart[client] = now;
		g_fullUpdateRequests[client] = 0;
	}

	g_fullUpdateRequests[client]++;
	if (g_fullUpdateRequests[client] >= bd_fullupdate_threshold)
	{
		char evidence[160];
		FormatEx(evidence, sizeof(evidence), "%d client-issued %s command(s) in %.0fs (latest arguments: %d)", g_fullUpdateRequests[client], command, now - g_fullUpdateWindowStart[client], args);
		g_fullUpdateRequests[client] = 0;
		g_fullUpdateWindowStart[client] = now;
		FlagBehavioral(client, bd_fullupdate_action, "FullUpdate(repeated client command)", evidence);
	}

	return Plugin_Continue;
}

#if defined _dhooks_included
public MRESReturn Hook_UpdateAcknowledgedFramecount(Address pThis, DHookParam hParams)
{
	int client = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_fullUpdateClientPtr[i] == pThis)
		{
			client = i;
			break;
		}
	}
	if (client == 0 || !IsClientInGame(client))
		return MRES_Ignored;

	g_fullUpdateCalls[client]++;
	// UpdateAcknowledgedFramecount is an engine acknowledgement path reachable by legitimate server
	// refreshes, so keep it telemetry only. The punitive vector is the explicitly client-issued
	// cl_fullupdate recorded above.
	int acknowledgedTick = hParams.Get(1);
	if (acknowledgedTick == -1)
	{
		// -1 is an engine sentinel, not a client-cheat verdict.
	}
	return MRES_Ignored;
}
#endif

#if defined _dhooks_included
public MRESReturn Hook_Teleport(int client, Handle hParams)
{
	if (gcv_teleport_hook != null && gcv_teleport_hook.BoolValue
		&& client >= 1 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client))
	{
		g_teleportGraceUntil[client] = GetGameTime() + 2.0;
		IgnoreServerAuthoredMovement(client, 6);
	}
	return MRES_Ignored;
}
#endif

// Cache the client's shavit style properties (behavioral bypass + autobhop) so the
// per-tick path never calls into shavit. Refreshed on spawn and style change.
void RefreshStyleInfo(int client)
{
	g_styleBypass[client] = false;
	g_styleAutobhop[client] = false;
	if (!g_bStyleTimer || client < 1 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client))
		return;

#if defined _shavit_included
	int style = Shavit_GetBhopStyle(client);
	if (style < 0 || style >= STYLE_LIMIT)
		return;

	if (g_bypassTag[0] != '\0')
	{
		char special[128];
		Shavit_GetStyleStrings(style, sSpecialString, special, sizeof(special));
		if (special[0] != '\0' && StrContains(special, g_bypassTag, false) != -1)
			g_styleBypass[client] = true;
	}

	stylesettings_t settings;
	Shavit_GetStyleSettings(style, settings);
	g_styleAutobhop[client] = settings.bAutobhop;
#endif
}

// These two receivers MUST keep the Shavit_ names: they are forwards fired BY the shavit plugin,
// matched by function name. Thin shims only, all logic lives in RefreshStyleInfo. Everything
// KevAC exposes itself uses the KevAC_ prefix.
public void Shavit_OnStyleConfigLoaded(int styles)
{
	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i) && !IsFakeClient(i))
			RefreshStyleInfo(i);
}

public void Shavit_OnStyleChanged(int client, int oldstyle, int newstyle, int track, bool manual)
{
	RefreshStyleInfo(client);
}

bool IsBehavioralBypassed(int client)
{
	return g_styleBypass[client];
}

// TestACLog - diagnostic capture (sm_kevac_testlog 1)
// Chat (admin/root): "cheat <detector> <name>", "legit <detector> <name>", "stop",
// "dllplayer join", "nodllplayer join". Prefix is fixed [KevAC].
public Action OnSayCommand(int client, const char[] command, int argc)
{
	if (client < 1 || client > MaxClients)
		return Plugin_Continue;

	// StAC's chat guard is portable: normal player chat has no legitimate newline
	// or carriage-return bytes. Block them before another plugin/log parser sees them.
	char msg[192];
	GetCmdArgString(msg, sizeof(msg));
	if (StrContains(msg, "\n") != -1 || StrContains(msg, "\r") != -1)
	{
		LogToFile("addons/sourcemod/logs/KevAC.log", "[KevAC] blocked control-character chat input from client %d", client);
		return Plugin_Handled;
	}

	StripQuotes(msg);
	TrimString(msg);
	if (msg[0] == '\0')
		return Plugin_Continue;

	char kw[32];
	int p = BreakString(msg, kw, sizeof(kw));
	bool diagnosticCommand = StrEqual(kw, "stop", false)
		|| StrEqual(kw, "dllplayer", false)
		|| StrEqual(kw, "nodllplayer", false)
		|| StrEqual(kw, "cheat", false)
		|| StrEqual(kw, "legit", false);

	if (!g_cvTestLog.BoolValue)
	{
		if (diagnosticCommand && CanReceiveKevACAlert(client))
			KevACPrintToChat(client, "%T", "Capture_Disabled", client);
		return Plugin_Continue;
	}
	if (!CheckCommandAccess(client, "sm_kevac_testlog", ADMFLAG_ROOT))
	{
		if (diagnosticCommand && CanReceiveKevACAlert(client))
			KevACPrintToChat(client, "%T", "Capture_AccessDenied", client);
		return Plugin_Continue;
	}

	if (StrEqual(kw, "stop", false))
	{
		StopTest();
		KevACPrintToChat(client, "%T", "Capture_Stopped", client);
		return Plugin_Handled;
	}

	if (StrEqual(kw, "dllplayer", false) || StrEqual(kw, "nodllplayer", false))
	{
		char rest[32];
		if (p != -1) { strcopy(rest, sizeof(rest), msg[p]); TrimString(rest); }
		if (StrEqual(rest, "join", false))
		{
			g_joinArm = StrEqual(kw, "dllplayer", false) ? 1 : 2;
			KevACPrintToChat(client, "%T", "Probe_Armed", client, g_joinArm == 1 ? "DLL" : "Legit");
			return Plugin_Handled;
		}
		return Plugin_Continue;
	}

	bool cheat = StrEqual(kw, "cheat", false);
	bool legit = StrEqual(kw, "legit", false);
	if ((cheat || legit) && p != -1)
	{
		char det[32], name[65];
		char rest[160];
		strcopy(rest, sizeof(rest), msg[p]);
		int p2 = BreakString(rest, det, sizeof(det));
		if (p2 == -1)
		{
			KevACPrintToChat(client, "%T", "Capture_Usage", client);
			return Plugin_Handled;
		}
		strcopy(name, sizeof(name), rest[p2]);
		StripQuotes(name);
		TrimString(name);

		int target = FindTarget(client, name, true, false);
		if (target < 1)
			return Plugin_Handled;

		if (StartTestSession(cheat ? 1 : 2, det, target))
			KevACPrintToChat(client, "%T", "Capture_Started", client, det, target, cheat ? "DLL" : "Legit");
		else
			KevACPrintToChat(client, "%T", "Capture_Failed", client, target);
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

bool StartTestSession(int mode, const char[] detector, int target)
{
	StopTest();

	g_testTarget = target;
	g_testStartTick = GetGameTickCount();

	char name[64], safe[64], date[32];
	GetClientName(target, name, sizeof(name));
	strcopy(safe, sizeof(safe), name);
	SanitizeFileName(safe);
	FormatTime(date, sizeof(date), "%Y%m%d_%H%M%S", GetTime());

	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "logs/KevAC_%s_%s_%s_%s.log", mode == 1 ? "DLL" : "LEGIT", detector, safe, date);
	g_testFH = OpenFile(path, "w");
	if (g_testFH == null)
	{
		LogError("[KevAC] Could not create diagnostic capture for %N.", target);
		g_testTarget = 0;
		return false;
	}

	WriteMovementCaptureHeader(g_testFH, mode == 1 ? "DLL/cheat" : "Legit", detector, target);
	return true;
}

void TestLogTick(int client, int buttons, const float vel[3], const float angles[3], const int mouse[2], int cmdnum, int tickcount, bool onGround)
{
	if (g_testFH == null)
		return;
	WriteMovementCaptureTick(g_testFH, client, g_testStartTick, buttons, vel, angles, mouse, cmdnum, tickcount, onGround);
}

void WriteMovementCaptureHeader(File capture, const char[] type, const char[] detector, int client)
{
	char name[64], steam[32], map[64], date[32];
	GetClientName(client, name, sizeof(name));
	if (!GetClientAuthId(client, AuthId_Steam2, steam, sizeof(steam)))
		strcopy(steam, sizeof(steam), "UNKNOWN");
	GetCurrentMap(map, sizeof(map));
	FormatTime(date, sizeof(date), "%Y%m%d_%H%M%S", GetTime());

	capture.WriteLine("# KevAC per-tick capture");
	capture.WriteLine("# type=%s detector=%s player=%s steam=%s map=%s date=%s tickrate=%.0f", type, detector, name, steam, map, date, g_tickrate);
	capture.WriteLine("# sv_airaccelerate=%.0f sv_autobunnyhopping=%d sv_gravity=%.0f sv_maxvelocity=%.0f sv_staminamax=%.1f",
		GetConVarFloat(FindConVar("sv_airaccelerate")),
		FindConVar("sv_autobunnyhopping") != null ? GetConVarInt(FindConVar("sv_autobunnyhopping")) : -1,
		GetConVarFloat(FindConVar("sv_gravity")),
		GetConVarFloat(FindConVar("sv_maxvelocity")),
		FindConVar("sv_staminamax") != null ? GetConVarFloat(FindConVar("sv_staminamax")) : -1.0);
	capture.WriteLine("dtick,cmdnum,cmdtick,onground,groundticks,W,A,S,D,turnleft,turnright,jump,duck,attack,attack2,speed_fwd,side_side,up,mousedx,mousedy,pitch,yaw,roll,velx,vely,velz,hspeed,vspeed,velmod,movetype,ducked,water,eyez");
}

// Snapshot one command into a flat record. Split out from the writer so the
// rolling pre-flag buffer and the live capture emit byte-identical rows.
void BuildMovementCaptureRecord(int client, any rec[PR_CELLS], int buttons, const float vel[3], const float angles[3], const int mouse[2], int cmdnum, int tickcount, bool onGround)
{
	float v[3];
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", v);

	rec[PR_TICK]       = GetGameTickCount();
	rec[PR_CMDNUM]     = cmdnum;
	rec[PR_CMDTICK]    = tickcount;
	rec[PR_ONGROUND]   = onGround ? 1 : 0;
	rec[PR_GROUNDTICK] = g_groundTicks[client];
	rec[PR_BUTTONS]    = buttons;
	rec[PR_VEL0]       = vel[0];
	rec[PR_VEL1]       = vel[1];
	rec[PR_VEL2]       = vel[2];
	rec[PR_MOUSEX]     = mouse[0];
	rec[PR_MOUSEY]     = mouse[1];
	rec[PR_ANG0]       = angles[0];
	rec[PR_ANG1]       = angles[1];
	rec[PR_ANG2]       = angles[2];
	rec[PR_V0]         = v[0];
	rec[PR_V1]         = v[1];
	rec[PR_V2]         = v[2];
	rec[PR_VELMOD]     = GetEntPropFloat(client, Prop_Send, "m_flVelocityModifier");
	rec[PR_MOVETYPE]   = view_as<int>(GetEntityMoveType(client));
	rec[PR_DUCKED]     = GetEntProp(client, Prop_Send, "m_bDucked");
	rec[PR_WATER]      = GetEntProp(client, Prop_Data, "m_nWaterLevel");
	rec[PR_EYEZ]       = GetClientEyePositionZ(client);
}

void WriteMovementCaptureRecord(File capture, int startTick, const any rec[PR_CELLS])
{
	int buttons = rec[PR_BUTTONS];
	float v0 = view_as<float>(rec[PR_V0]);
	float v1 = view_as<float>(rec[PR_V1]);
	float v2 = view_as<float>(rec[PR_V2]);
	float hspeed = SquareRoot(v0 * v0 + v1 * v1);

	capture.WriteLine("%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%.2f,%.2f,%.2f,%d,%d,%.3f,%.3f,%.3f,%.2f,%.2f,%.2f,%.2f,%.2f,%.3f,%d,%d,%d,%.2f",
		rec[PR_TICK] - startTick, rec[PR_CMDNUM], rec[PR_CMDTICK],
		rec[PR_ONGROUND], rec[PR_GROUNDTICK],
		(buttons & IN_FORWARD) ? 1 : 0, (buttons & IN_MOVELEFT) ? 1 : 0, (buttons & IN_BACK) ? 1 : 0, (buttons & IN_MOVERIGHT) ? 1 : 0,
		(buttons & IN_LEFT) ? 1 : 0, (buttons & IN_RIGHT) ? 1 : 0,
		(buttons & IN_JUMP) ? 1 : 0, (buttons & IN_DUCK) ? 1 : 0, (buttons & IN_ATTACK) ? 1 : 0, (buttons & IN_ATTACK2) ? 1 : 0,
		view_as<float>(rec[PR_VEL0]), view_as<float>(rec[PR_VEL1]), view_as<float>(rec[PR_VEL2]),
		rec[PR_MOUSEX], rec[PR_MOUSEY],
		view_as<float>(rec[PR_ANG0]), view_as<float>(rec[PR_ANG1]), view_as<float>(rec[PR_ANG2]),
		v0, v1, v2, hspeed, v2,
		view_as<float>(rec[PR_VELMOD]),
		rec[PR_MOVETYPE], rec[PR_DUCKED], rec[PR_WATER],
		view_as<float>(rec[PR_EYEZ]));
}

void WriteMovementCaptureTick(File capture, int client, int startTick, int buttons, const float vel[3], const float angles[3], const int mouse[2], int cmdnum, int tickcount, bool onGround)
{
	any rec[PR_CELLS];
	BuildMovementCaptureRecord(client, rec, buttons, vel, angles, mouse, cmdnum, tickcount, onGround);
	WriteMovementCaptureRecord(capture, startTick, rec);
}

bool StartPreBanCapture(int client, int actionMethod, const char[] category, const char[] evidence, const char[] customReason, int banMinutes, bool writeAudit = true)
{
	if (bd_preban_delay <= 0)
		return false;

	int userid = GetClientUserId(client);
	File capture = null;
	if (writeAudit)
	{
		char name[64], safe[64], date[32], path[PLATFORM_MAX_PATH];
		GetClientName(client, name, sizeof(name));
		strcopy(safe, sizeof(safe), name);
		SanitizeFileName(safe);
		FormatTime(date, sizeof(date), "%Y%m%d_%H%M%S", GetTime());
		BuildPath(Path_SM, path, sizeof(path), "logs/KevAC_preban_%s_%d_%s.log", safe, userid, date);
		capture = OpenFile(path, "w");
		if (capture == null)
		{
			LogError("[KevAC] Could not create pre-ban audit log: %s", path);
			return false;
		}
	}

	g_prebanPending[client] = true;
	g_prebanUserId[client] = userid;
	g_prebanStartTick[client] = GetGameTickCount();
	g_prebanAction[client] = actionMethod;
	g_prebanMinutes[client] = banMinutes;
	strcopy(g_prebanCategory[client], sizeof(g_prebanCategory[]), category);
	strcopy(g_prebanEvidence[client], sizeof(g_prebanEvidence[]), evidence);
	strcopy(g_prebanReason[client], sizeof(g_prebanReason[]), customReason);
	g_prebanFH[client] = capture;

	if (capture != null)
	{
		WriteMovementCaptureHeader(capture, "pre-ban", category, client);
		capture.WriteLine("# initial_action=%s duration_minutes=%d delay_seconds=%d", actionMethod == SBBAN ? "SourceBans++" : "SourceMod", banMinutes, bd_preban_delay);
		capture.WriteLine("# initial_evidence=%s", evidence);
		if (customReason[0] != '\0')
			capture.WriteLine("# initial_reason=%s", customReason);

		PreRollFlush(client, capture, g_prebanStartTick[client]);

		char message[256];
		FormatEx(message, sizeof(message), "%T", "PreBan_Started", LANG_SERVER, client, category, bd_preban_delay);
		LogMessage("[KevAC] %s", message);
		AlertPreBanStarted(client, category, bd_preban_delay);
	}
	else
	{
		LogMessage("[KevAC] Delaying %s enforcement for %N by %d seconds without a movement audit capture.", actionMethod == SBBAN ? "SourceBans++" : "SourceMod", client, bd_preban_delay);
	}
	CreateTimer(float(bd_preban_delay), Timer_PreBanBan, g_prebanUserId[client], TIMER_FLAG_NO_MAPCHANGE);
	return true;
}

void PreBanLogTick(int client, int buttons, const float vel[3], const float angles[3], const int mouse[2], int cmdnum, int tickcount, bool onGround)
{
	bool live = (g_prebanPending[client] && g_prebanFH[client] != null);

	// Building a record costs a handful of entity lookups, and this runs for
	// every alive player every tick. Skip it entirely when nothing wants one.
	if (!live && bd_preban_preroll == 0)
		return;

	any rec[PR_CELLS];
	BuildMovementCaptureRecord(client, rec, buttons, vel, angles, mouse, cmdnum, tickcount, onGround);

	if (bd_preban_preroll != 0)
	{
		int idx = g_prerollHead[client];
		g_preroll[client][idx] = rec;
		g_prerollHead[client] = (idx + 1) % KEVAC_PREROLL_TICKS;
		if (g_prerollCount[client] < KEVAC_PREROLL_TICKS)
			g_prerollCount[client]++;
	}

	if (live)
		WriteMovementCaptureRecord(g_prebanFH[client], g_prebanStartTick[client], rec);
}

// Oldest first. dtick is negative for everything that preceded the detection,
// so the flag point is unambiguous when the file is read back.
void PreRollFlush(int client, File capture, int startTick)
{
	int count = g_prerollCount[client];
	if (count <= 0)
		return;

	int idx = (g_prerollHead[client] - count + KEVAC_PREROLL_TICKS) % KEVAC_PREROLL_TICKS;
	capture.WriteLine("# preroll_ticks=%d (negative dtick precedes the detection)", count);

	for (int i = 0; i < count; i++)
	{
		WriteMovementCaptureRecord(capture, startTick, g_preroll[client][idx]);
		idx = (idx + 1) % KEVAC_PREROLL_TICKS;
	}

	capture.WriteLine("# --- detection fired here ---");
}

void AppendPreBanDetection(int client, int actionMethod, const char[] category, const char[] evidence)
{
	if (!g_prebanPending[client])
		return;

	if (g_prebanFH[client] != null)
		g_prebanFH[client].WriteLine("# DETECTION dtick=%d requested_action=%d detector=%s evidence=%s", GetGameTickCount() - g_prebanStartTick[client], actionMethod, category, evidence);
}

void StopPreBanCapture(int client, const char[] reason)
{
	if (client < 1 || client > MaxClients || !g_prebanPending[client])
		return;

	if (g_prebanFH[client] != null)
	{
		g_prebanFH[client].WriteLine("# AUDIT END - %s", reason);
		g_prebanFH[client].Close();
		g_prebanFH[client] = null;
	}

	g_prebanPending[client] = false;
	g_prebanUserId[client] = 0;
	g_prebanStartTick[client] = 0;
	g_prebanAction[client] = NONE;
	g_prebanMinutes[client] = 0;
	g_prebanCategory[client][0] = '\0';
	g_prebanEvidence[client][0] = '\0';
	g_prebanReason[client][0] = '\0';
}

// ---------------------------------------------------------------- ban wave
// A pre-ban still audits for its full window, but enforcement parks in a queue an admin flushes
// with sm_kevac_execban. Detectors named in kevac_banwave_exempt skip the queue and ban on the
// spot, which keeps protocol-impossibility catches immediate.
// The queue is written to disk on every change: an in-memory queue would be lost to the same
// SIGKILL that already loses a pending pre-ban.

enum struct BanQueueEntry_t
{
	char sAuth[32];
	char sName[64];
	char sCategory[64];
	char sEvidence[256];
	char sReason[192];
	int  iAction;
	int  iMinutes;
	int  iQueuedAt;
}

ArrayList g_alBanQueue = null;

#define KEVAC_BANQUEUE_FILE "data/kevac_banwave.txt"

bool BanWaveExempt(const char[] category)
{
	char exempt[256];
	gcv_banwave_exempt.GetString(exempt, sizeof(exempt));
	if (!exempt[0])
		return false;

	char parts[16][64];
	int count = ExplodeString(exempt, ",", parts, sizeof(parts), sizeof(parts[]));
	for (int i = 0; i < count; i++)
	{
		TrimString(parts[i]);
		if (parts[i][0] != '\0' && StrContains(category, parts[i], false) != -1)
			return true;
	}
	return false;
}

int BanQueueFind(const char[] auth)
{
	if (g_alBanQueue == null)
		return -1;

	BanQueueEntry_t entry;
	for (int i = 0; i < g_alBanQueue.Length; i++)
	{
		g_alBanQueue.GetArray(i, entry, sizeof(entry));
		if (StrEqual(entry.sAuth, auth, false))
			return i;
	}
	return -1;
}

bool IsQueuedForBanWave(const char[] auth)
{
	return BanQueueFind(auth) != -1;
}

void SaveBanQueue()
{
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), KEVAC_BANQUEUE_FILE);

	File hFile = OpenFile(path, "w");
	if (hFile == null)
	{
		LogError("[KevAC] Could not write the ban-wave queue to %s", path);
		return;
	}

	hFile.WriteLine("// KevAC ban wave. One queued ban per line, flushed by sm_kevac_execban.");
	hFile.WriteLine("// steamid|name|action|minutes|queued_at|category|evidence|reason");

	BanQueueEntry_t entry;
	for (int i = 0; i < g_alBanQueue.Length; i++)
	{
		g_alBanQueue.GetArray(i, entry, sizeof(entry));
		hFile.WriteLine("%s|%s|%d|%d|%d|%s|%s|%s", entry.sAuth, entry.sName, entry.iAction,
			entry.iMinutes, entry.iQueuedAt, entry.sCategory, entry.sEvidence, entry.sReason);
	}

	delete hFile;
}

void LoadBanQueue()
{
	if (g_alBanQueue == null)
		g_alBanQueue = new ArrayList(sizeof(BanQueueEntry_t));
	g_alBanQueue.Clear();

	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), KEVAC_BANQUEUE_FILE);
	if (!FileExists(path))
		return;

	File hFile = OpenFile(path, "r");
	if (hFile == null)
		return;

	char line[1024];
	while (hFile.ReadLine(line, sizeof(line)))
	{
		TrimString(line);
		if (line[0] == '\0' || (line[0] == '/' && line[1] == '/'))
			continue;

		char parts[8][256];
		if (ExplodeString(line, "|", parts, sizeof(parts), sizeof(parts[])) < 8)
			continue;

		BanQueueEntry_t entry;
		strcopy(entry.sAuth, sizeof(entry.sAuth), parts[0]);
		strcopy(entry.sName, sizeof(entry.sName), parts[1]);
		entry.iAction = StringToInt(parts[2]);
		entry.iMinutes = StringToInt(parts[3]);
		entry.iQueuedAt = StringToInt(parts[4]);
		strcopy(entry.sCategory, sizeof(entry.sCategory), parts[5]);
		strcopy(entry.sEvidence, sizeof(entry.sEvidence), parts[6]);
		strcopy(entry.sReason, sizeof(entry.sReason), parts[7]);

		g_alBanQueue.PushArray(entry, sizeof(entry));
	}

	delete hFile;
	if (g_alBanQueue.Length > 0)
		LogMessage("[KevAC] Ban wave: %d queued ban(s) loaded, awaiting sm_kevac_execban.", g_alBanQueue.Length);
}

void QueueForBanWave(int client, const char[] auth, int actionMethod, const char[] category, const char[] evidence, const char[] customReason, int banMinutes)
{
	if (g_alBanQueue == null)
		g_alBanQueue = new ArrayList(sizeof(BanQueueEntry_t));
	if (IsQueuedForBanWave(auth))
		return;

	BanQueueEntry_t entry;
	strcopy(entry.sAuth, sizeof(entry.sAuth), auth);
	if (client > 0 && IsClientInGame(client))
		GetClientName(client, entry.sName, sizeof(entry.sName));
	else
		strcopy(entry.sName, sizeof(entry.sName), "unknown");
	strcopy(entry.sCategory, sizeof(entry.sCategory), category);
	strcopy(entry.sEvidence, sizeof(entry.sEvidence), evidence);
	strcopy(entry.sReason, sizeof(entry.sReason), customReason);
	entry.iAction = actionMethod;
	entry.iMinutes = banMinutes;
	entry.iQueuedAt = GetTime();

	g_alBanQueue.PushArray(entry, sizeof(entry));
	SaveBanQueue();

	LogToFile("addons/sourcemod/logs/KevAC_ban.log", "[KevAC] QUEUED %s (%s) | detector=%s | evidence=%s | awaiting sm_kevac_execban",
		entry.sName, auth, category, evidence);
	LogMessage("[KevAC] Ban wave: queued %s (%s) for %s. %d pending.", entry.sName, auth, category, g_alBanQueue.Length);
	AlertAdmins(client, category, "queued for the next ban wave (sm_kevac_execban)", false);
}

public Action Command_KevACBanQueue(int client, int args)
{
	if (g_alBanQueue == null || g_alBanQueue.Length < 1)
	{
		ReplyToCommand(client, "[KevAC] The ban wave queue is empty.");
		return Plugin_Handled;
	}

	ReplyToCommand(client, "[KevAC] %d queued ban(s). sm_kevac_execban to run the wave:", g_alBanQueue.Length);

	BanQueueEntry_t entry;
	for (int i = 0; i < g_alBanQueue.Length; i++)
	{
		g_alBanQueue.GetArray(i, entry, sizeof(entry));
		ReplyToCommand(client, "  %d. %s (%s) | %s | %s", i + 1, entry.sName, entry.sAuth, entry.sCategory, entry.sEvidence);
	}
	return Plugin_Handled;
}

public Action Command_KevACExecBan(int client, int args)
{
	if (g_alBanQueue == null || g_alBanQueue.Length < 1)
	{
		ReplyToCommand(client, "[KevAC] The ban wave queue is empty.");
		return Plugin_Handled;
	}

	// A wave is irreversible and hits everyone at once, so it never runs off a
	// bare command. Reviewing before enforcing is the entire point of the
	// queue; executing it by accident throws that away.
	char confirm[16];
	if (args >= 1)
		GetCmdArg(1, confirm, sizeof(confirm));

	if (!StrEqual(confirm, "confirm", false))
	{
		ReplyToCommand(client, "[KevAC] This will ban %d player(s) permanently and cannot be undone:", g_alBanQueue.Length);

		// Evidence, not just the detector name. Every player here is banned with the same public text, so
		// this preview is the only place an admin can tell a solid catch from a false positive before
		// the wave becomes irreversible.
		BanQueueEntry_t preview;
		for (int i = 0; i < g_alBanQueue.Length; i++)
		{
			g_alBanQueue.GetArray(i, preview, sizeof(preview));
			ReplyToCommand(client, "  %d. %s (%s) | %s | %s", i + 1, preview.sName, preview.sAuth, preview.sCategory, preview.sEvidence);
		}

		ReplyToCommand(client, "[KevAC] Review with sm_kevac_banqueue, or type: sm_kevac_execban confirm");
		return Plugin_Handled;
	}

	int total = g_alBanQueue.Length;
	int online = 0;

	BanQueueEntry_t entry;
	for (int i = 0; i < total; i++)
	{
		g_alBanQueue.GetArray(i, entry, sizeof(entry));

		// A whitelist added after queueing still gets the last word.
		if (IsWhitelistedFor(entry.sAuth, entry.sCategory))
		{
			LogMessage("[KevAC] Ban wave: skipped %s (%s) - whitelisted since queueing.", entry.sName, entry.sAuth);
			continue;
		}

		int target = FindClientByAuthId(entry.sAuth);
		if (target > 0)
		{
			online++;
			PlayerAction(target, entry.iAction, entry.sCategory, entry.sEvidence, entry.sReason, entry.iMinutes, true);
		}
		else
		{
			BanOfflineAuth(entry.sAuth, entry.sName, entry.iAction, entry.sCategory, entry.sEvidence, entry.sReason, entry.iMinutes);
		}
	}

	g_alBanQueue.Clear();
	SaveBanQueue();

	ReplyToCommand(client, "[KevAC] Ban wave executed: %d ban(s), %d of them online.", total, online);
	LogAction(client, -1, "[KevAC] executed a ban wave of %d player(s).", total);
	return Plugin_Handled;
}

int FindClientByAuthId(const char[] auth)
{
	char current[32];
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
			continue;
		if (GetClientAuthId(i, AuthId_Steam2, current, sizeof(current)) && StrEqual(current, auth, false))
			return i;
	}
	return -1;
}

bool DispatchPreBan(int client, const char[] endReason)
{
	if (client < 1 || client > MaxClients || !IsClientInGame(client) || !g_prebanPending[client])
		return false;

	char auth[32], category[64], evidence[256], customReason[192];
	if (!GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth)))
		strcopy(auth, sizeof(auth), "UNKNOWN");
	// Scope-aware for the same reason as PlayerAction: the list holds whole
	// lines, so an exact-match lookup never sees a scoped entry. An admin who
	// whitelists a player mid-capture must have that honored at dispatch.
	if (!status || IsWhitelistedFor(auth, g_prebanCategory[client]))
	{
		StopPreBanCapture(client, "ban cancelled before dispatch");
		return false;
	}

	int actionMethod = g_prebanAction[client];
	int banMinutes = g_prebanMinutes[client];
	strcopy(category, sizeof(category), g_prebanCategory[client]);
	strcopy(evidence, sizeof(evidence), g_prebanEvidence[client]);
	strcopy(customReason, sizeof(customReason), g_prebanReason[client]);
	StopPreBanCapture(client, endReason);

	// The audit ran in full either way; only the enforcement is deferred.
	if (gcv_banwave.BoolValue && !BanWaveExempt(category))
	{
		QueueForBanWave(client, auth, actionMethod, category, evidence, customReason, banMinutes);
		return true;
	}

	PlayerAction(client, actionMethod, category, evidence, customReason, banMinutes, true);
	return true;
}

// Queued bans outlive the session that flagged them, so the wave must be able to ban someone who
// has disconnected. One place decides what a banned player is told, because two paths reach a
// ban (immediate in PlayerAction, deferred from the wave) and they must agree.
// Detector hits stay vague: naming the vector just tells a cheater what to fix.
void ResolveBanReason(char[] buffer, int maxlen)
{
	FormatEx(buffer, maxlen, "%T", "Ban_PublicReason", LANG_SERVER);
}

void BanOfflineAuth(const char[] auth, const char[] name, int actionMethod, const char[] category, const char[] evidence, const char[] customReason, int banMinutes)
{
	// The wave used to write the detector name into the ban, so a queued ban told the cheater which
	// vector caught them while an immediate ban did not. The vector stays admin-side: queue file,
	// sm_kevac_banqueue, the execban preview and KevAC_ban.log.
	char reason[256];
	ResolveBanReason(reason, sizeof(reason));

	// Same fallback PlayerAction uses: SourceBans++ is optional, so an action
	// configured as 3 still lands through SourceMod when it is not loaded.
	if (actionMethod == SBBAN && GetFeatureStatus(FeatureType_Native, "SBPP_BanPlayer") == FeatureStatus_Available)
	{
		ServerCommand("sm_addban %d \"%s\" \"%s\"", banMinutes, auth, reason);
	}
	else
	{
		BanIdentity(auth, banMinutes, BANFLAG_AUTHID, reason, "kevac_banwave");
	}

	LogToFile("addons/sourcemod/logs/KevAC_ban.log", "[KevAC] WAVE %s (%s) | action=%s | duration_minutes=%d | detector=%s | evidence=%s | note=%s",
		name, auth, actionMethod == SBBAN ? "SourceBans++" : "SourceMod", banMinutes, category, evidence,
		customReason[0] != '\0' ? customReason : "-");
}

public Action Timer_PreBanBan(Handle timer, any userid)
{
	int client = GetClientOfUserId(userid);
	if (client < 1 || client > MaxClients || !IsClientInGame(client) || !g_prebanPending[client] || g_prebanUserId[client] != userid)
		return Plugin_Stop;

	DispatchPreBan(client, "audit window complete; ban dispatch begins");
	return Plugin_Stop;
}

// Cancels a pending pre-ban. No timer handle to kill: Timer_PreBanBan re-checks g_prebanPending
// and stops once StopPreBanCapture clears it. The capture closes with the cancelling admin
// recorded, so a cancelled ban still leaves the evidence behind.
public Action CommandCancelPreBan(int iClient, int iArgs)
{
	if (iArgs < 1)
	{
		ReplyToCommand(iClient, "%T", "PreBan_CancelUsage", iClient);

		int iPending = 0;
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i) && g_prebanPending[i])
			{
				ReplyToCommand(iClient, "[KevAC] Pending: %N (%s)", i, g_prebanCategory[i]);
				iPending++;
			}
		}
		if (iPending == 0)
			ReplyToCommand(iClient, "[KevAC] No pre-bans are pending.");
		return Plugin_Handled;
	}

	char sTarget[64];
	GetCmdArg(1, sTarget, sizeof(sTarget));

	int iTarget = FindTarget(iClient, sTarget, true, false);
	if (iTarget < 1)
		return Plugin_Handled; // FindTarget already replied

	if (!g_prebanPending[iTarget])
	{
		ReplyToCommand(iClient, "%T", "PreBan_NonePending", iClient, iTarget);
		return Plugin_Handled;
	}

	// Snapshot before StopPreBanCapture wipes it.
	char sCategory[64];
	strcopy(sCategory, sizeof(sCategory), g_prebanCategory[iTarget]);

	char sAdmin[MAX_NAME_LENGTH];
	if (iClient > 0)
		GetClientName(iClient, sAdmin, sizeof(sAdmin));
	else
		strcopy(sAdmin, sizeof(sAdmin), "Console");

	char sEnd[192];
	FormatEx(sEnd, sizeof(sEnd), "cancelled by %s", sAdmin);
	StopPreBanCapture(iTarget, sEnd);

	LogToFile("addons/sourcemod/logs/KevAC.log",
		"[KevAC] Pre-ban for %N (%s) cancelled by %s", iTarget, sCategory, sAdmin);
	LogAction(iClient, iTarget, "\"%L\" cancelled the pending KevAC ban for \"%L\" (%s)", iClient, iTarget, sCategory);

	for (int i = 1; i <= MaxClients; i++)
	{
		if (CanReceiveKevACAlert(i) && g_showAlerts[i])
			KevACPrintToChat(i, "%T", "PreBan_Cancelled", i, iTarget, sCategory);
	}
	if (iClient == 0)
		ReplyToCommand(iClient, "[KevAC] Pending ban cancelled for %N (%s).", iTarget, sCategory);

	return Plugin_Handled;
}

void StopTest()
{
	if (g_testTarget != 0)
	{
		LogTest("SESSION END - stopped");
		g_testTarget = 0;
	}
	if (g_probeClient != 0)
		FinishProbe("stopped");

	if (g_testFH != null)
	{
		g_testFH.Close();
		g_testFH = null;
	}
	g_joinArm = 0;
}

void LogTest(const char[] fmt, any ...)
{
	if (g_testFH == null)
		return;
	char buf[512];
	VFormat(buf, sizeof(buf), fmt, 2);
	g_testFH.WriteLine("# %s", buf);
}

// ---- Connection probe (dllplayer join / nodllplayer join) ----
void StartProbe(int client)
{
	g_probeMode = g_joinArm;
	g_joinArm = 0;
	g_probeClient = client;
	g_probeStart = GetGameTime();
	g_probePending = 0;

	if (g_testFH != null)
	{
		g_testFH.Close();
		g_testFH = null;
	}

	char name[64], safe[64], steam[32], date[32];
	GetClientName(client, name, sizeof(name));
	strcopy(safe, sizeof(safe), name);
	SanitizeFileName(safe);
	if (!GetClientAuthId(client, AuthId_Steam2, steam, sizeof(steam)))
		strcopy(steam, sizeof(steam), "PENDING");
	FormatTime(date, sizeof(date), "%Y%m%d_%H%M%S", GetTime());

	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "logs/KevAC_PROBE_%s_%s_%s.log", g_probeMode == 1 ? "DLL" : "LEGIT", safe, date);
	g_testFH = OpenFile(path, "w");
	if (g_testFH == null)
	{
		LogError("[KevAC] Could not create probe log: %s", path);
		g_probeClient = 0;
		return;
	}
	AnnounceProbeStarted(client, g_probeMode == 1 ? "DLL" : "Legit");

	g_testFH.WriteLine("# KevAC connection probe");
	g_testFH.WriteLine("# type=%s player=%s steam=%s date=%s", g_probeMode == 1 ? "DLL" : "Legit", name, steam, date);
	g_testFH.WriteLine("# listener_detection(extension)=%s", bDetect[client] ? "TRIPPED" : "clean-so-far");
	g_testFH.WriteLine("# NOTE: honeypot/fake-packet injection is not performed; this probe records convar values + response latency + listener status.");
	g_testFH.WriteLine("cvar,result,value,latency_ms");

	for (int i = 0; i < sizeof(g_probeCvars); i++)
	{
		QueryClientConVar(client, g_probeCvars[i], OnProbeQueried);
		g_probePending++;
	}

	CreateTimer(6.0, Timer_ProbeTimeout, GetClientUserId(client));
}

public void OnProbeQueried(QueryCookie cookie, int client, ConVarQueryResult result, const char[] cvarName, const char[] cvarValue)
{
	if (client != g_probeClient || g_testFH == null)
		return;

	char rs[24];
	switch (result)
	{
		case ConVarQuery_Okay:            strcopy(rs, sizeof(rs), "Okay");
		case ConVarQuery_NotFound:        strcopy(rs, sizeof(rs), "NotFound");
		case ConVarQuery_NotValid:        strcopy(rs, sizeof(rs), "NotValid");
		case ConVarQuery_Protected:       strcopy(rs, sizeof(rs), "Protected");
		default:                          strcopy(rs, sizeof(rs), "Unknown");
	}

	g_testFH.WriteLine("%s,%s,%s,%.1f", cvarName, rs, (result == ConVarQuery_Okay) ? cvarValue : "-", (GetGameTime() - g_probeStart) * 1000.0);

	if (--g_probePending <= 0)
		FinishProbe("all convars processed");
}

public Action Timer_ProbeTimeout(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);
	if (client != 0 && client == g_probeClient && g_probePending > 0)
		FinishProbe("timeout - some convar queries never answered (hooked netchannel?)");
	return Plugin_Stop;
}

void FinishProbe(const char[] reason)
{
	if (g_probeClient == 0)
		return;

	if (g_testFH != null)
	{
		g_testFH.WriteLine("# PROBE END (%d unanswered) - %s", g_probePending, reason);
		g_testFH.Close();
		g_testFH = null;
	}

	AnnounceProbeFinished(g_probeMode == 1 ? "DLL" : "Legit");
	g_probeClient = 0;
	g_probePending = 0;
}

// ---- helpers ----
void AnnounceProbeStarted(int target, const char[] type)
{
	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i) && !IsFakeClient(i) && CheckCommandAccess(i, "sm_kevac_testlog", ADMFLAG_ROOT))
			KevACPrintToChat(i, "%T", "Probe_Started", i, target, type);
}

void AnnounceProbeFinished(const char[] type)
{
	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i) && !IsFakeClient(i) && CheckCommandAccess(i, "sm_kevac_testlog", ADMFLAG_ROOT))
			KevACPrintToChat(i, "%T", "Probe_Finished", i, type);
}

void SanitizeFileName(char[] s)
{
	int len = strlen(s);
	for (int i = 0; i < len; i++)
	{
		int c = s[i];
		bool ok = (c >= '0' && c <= '9') || (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c == '_' || c == '-';
		if (!ok)
			s[i] = '_';
	}
	if (len == 0)
		strcopy(s, 64, "player");
}

float GetClientEyePositionZ(int client)
{
	float eye[3];
	GetClientEyePosition(client, eye);
	return eye[2];
}

// Action dispatch
void FlagBehavioral(int client, int action, const char[] category, const char[] evidence, const char[] actionReason = "", int banMinutes = -1, bool capturePreBanAudit = true)
{
	if (action == -1)
		return;
	if (client < 1 || client > MaxClients || !IsClientInGame(client))
		return;

	char sAuthID[32];
	if (!GetClientAuthId(client, AuthId_Steam2, sAuthID, sizeof(sAuthID)))
		strcopy(sAuthID, sizeof(sAuthID), "UNKNOWN");

	// Per-detector: a scoped entry exempts only its own categories, so a player
	// cleared for DuckMacro is still fully bannable by everything else.
	bool whitelisted = IsWhitelistedFor(sAuthID, category);

	float vel[3];
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", vel);
	float origin[3];
	GetClientAbsOrigin(client, origin);
	LogToFile("addons/sourcemod/logs/KevAC.log",
		"[KevAC] %N (%s) | %s | %s | speed=%.1f pos_z=%.1f%s",
		client, sAuthID, category, evidence,
		SquareRoot(vel[0] * vel[0] + vel[1] * vel[1]),
		origin[2],
		whitelisted ? " [WHITELISTED - no action]" : "");
	AlertAdmins(client, category, evidence, whitelisted);

	// KevAC's own API: other plugins (discord relays, stat trackers) hook this.
	Call_StartForward(g_fwdDetection);
	Call_PushCell(client);
	Call_PushString(category);
	Call_PushString(evidence);
	Call_PushCell(whitelisted ? NONE : action);
	Call_Finish();

	if (!whitelisted)
		PlayerAction(client, action, category, evidence, actionReason, banMinutes, false, capturePreBanAudit);
}

void AlertAdmins(int target, const char[] category, const char[] evidence, bool whitelisted)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (CanReceiveKevACAlert(i) && g_showAlerts[i])
		{
			if (g_alertsPersonal[i] && i != target)
				continue;
			char whitelistSuffix[64];
			whitelistSuffix[0] = '\0';
			if (whitelisted)
				FormatEx(whitelistSuffix, sizeof(whitelistSuffix), "%T", "Alert_Whitelisted", i);
			KevACPrintToChat(i, "%T", "Alert_Detection", i, target, category, evidence, whitelistSuffix);
		}
	}
}

void AlertPreBanStarted(int target, const char[] category, int seconds)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (CanReceiveKevACAlert(i) && g_showAlerts[i])
			KevACPrintToChat(i, "%T", "PreBan_Started", i, target, category, seconds);
	}
}

void PlayerAction(int client, int actionMethod = -1, const char[] category = "DLL", const char[] evidence = "", const char[] customReason = "", int banMinutes = -1, bool bypassPreBan = false, bool capturePreBanAudit = true)
{
	static char message[256];
	if (client < 1 || client > MaxClients || !IsClientInGame(client))
		return;

	if (actionMethod == -1)
		actionMethod = method;
	if (banMinutes < 0)
		banMinutes = blocking_time;

	char sAuthID[32];
	if (!GetClientAuthId(client, AuthId_Steam2, sAuthID, sizeof(sAuthID)))
		strcopy(sAuthID, sizeof(sAuthID), "UNKNOWN");

	// Scope-aware, NOT hWhiteList.FindString(sAuthID). The list stores whole lines, so a scoped entry
	// (STEAM_1:0:1 DuckMacro) never equals the bare SteamID and exact-match silently missed it.
	// FlagBehavioral gates correctly, but the deferred pre-ban path calls this directly - so an
	// admin who whitelisted a player DURING their capture window still had the ban land.
	if (IsWhitelistedFor(sAuthID, category) || !status)
		return;

	// Already in the wave queue: their ban is decided and an admin owns the trigger. Checked HERE, not
	// only in StartPreBanCapture - that returning false means 'I did not take ownership' and the
	// fall-through is an immediate ban. So the second time any detector fired on a queued player
	// they were banned on the spot, which is exactly what EventListener does on every mask change.
	if ((actionMethod == BAN || actionMethod == SBBAN) && IsQueuedForBanWave(sAuthID))
		return;

	if (g_prebanPending[client])
	{
		AppendPreBanDetection(client, actionMethod, category, evidence);
		return;
	}

	if (!bypassPreBan && (actionMethod == BAN || actionMethod == SBBAN)
		&& StartPreBanCapture(client, actionMethod, category, evidence, customReason, banMinutes, capturePreBanAudit))
		return;

	// SourceBans++ submits its ban before the client is necessarily disconnected.
	// A second detector callback in that short window must not create another
	// database ban or duplicate kick. ResetClientState clears this on reconnect.
	if (actionMethod != NONE && g_punishmentDispatched[client])
	{
		LogMessage("[KevAC] Suppressed duplicate action %d for %N (%s).", actionMethod, client, category);
		return;
	}
	if (actionMethod != NONE)
		g_punishmentDispatched[client] = true;

	if (actionMethod == BAN || actionMethod == SBBAN)
	{
		// Deliberately the only reason provided to SourceBans++ or the SourceMod-ban
		// fallback. Detector details stay server-side.
		ResolveBanReason(message, sizeof(message));
		LogKevACBan(client, actionMethod, banMinutes, category, evidence);
	}
	else if (customReason[0] != '\0')
	{
		FormatEx(message, sizeof(message), "%T %s", "PREFIX", client, customReason);
	}
	else
	{
		FormatEx(message, sizeof(message), "%T %T", "PREFIX", client, "REASON", client);
	}

	int appliedAction = actionMethod;
	switch (actionMethod)
	{
		case NONE: { }
		case KICK:  KickClient(client, message);
		case BAN:   BanClient(client, banMinutes, BANFLAG_AUTO, message);
		case SBBAN:
		{
			// SourceBans++ is optional. A deterministic action configured as 3
			// remains enforceable when it is not loaded instead of throwing a
			// missing-native runtime error and leaving the cheater connected.
			if (GetFeatureStatus(FeatureType_Native, "SBPP_BanPlayer") == FeatureStatus_Available)
			{
				SBPP_BanPlayer(0, client, banMinutes, message);
			}
			else
			{
				appliedAction = BAN;
				LogMessage("[KevAC] SourceBans++ is unavailable. Falling back to the SourceMod ban for %N (%s).", client, category);
				BanClient(client, banMinutes, BANFLAG_AUTO, message);
			}
		}
		default:    LogError("Method not found");
	}

	if (appliedAction != NONE)
	{
		Call_StartForward(g_fwdPunished);
		Call_PushCell(client);
		Call_PushCell(appliedAction);
		Call_PushString(category);
		Call_Finish();
	}

	// AlertAdmins() already delivered the colored detection evidence to opted-in
	// admins. Never echo the action to public chat.
	char plainMsg[256];
	FormatEx(plainMsg, sizeof(plainMsg), "%t", "Detected_Server", client, client, category);

	if (iNotification & 2)  PrintToServer("[KevAC] %s", plainMsg);
	if (iNotification & 1)  LogToFile("addons/sourcemod/logs/KevAC.log", "[KevAC] %s", plainMsg);
}

bool CanReceiveKevACAlert(int client)
{
	return client >= 1 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client)
		&& GetUserAdmin(client) != INVALID_ADMIN_ID
		&& CheckCommandAccess(client, "sm_alerts", ADMFLAG_GENERIC, false);
}

public void OnClientDisconnect(int iClient)
{
	SDKUnhook(iClient, SDKHook_OnTakeDamage, StabTrace_OnTakeDamage);
	SDKUnhook(iClient, SDKHook_OnTakeDamagePost, StabTrace_OnTakeDamagePost);
	if (GetClientUserId(iClient) == g_stabTraceTargetUserId)
		StopStabTrace("target disconnected");
	bDetect[iClient] = false;
	g_listenerBlacklistFlagged[iClient] = false;
	StopPreBanCapture(iClient, "target disconnected");
	RemoveFullUpdateHook(iClient);
	RemoveListenerMessageHook(iClient);

	if (iClient == g_testTarget)
	{
		LogTest("SESSION END - target disconnected");
		g_testTarget = 0;
	}
	if (iClient == g_probeClient)
		FinishProbe("target disconnected");

	ResetClientState(iClient);
}

// whitelist.ini format. A bare SteamID is a blanket exemption; anything after it scopes the
// exemption to those detectors only:
//   STEAM_1:0:111                     ; every detector (legacy line)
//   STEAM_1:0:222 DuckMacro           ; DuckMacro only, still bannable elsewhere
//   STEAM_1:0:333 DuckMacro,AHKStrafe ; two detectors
// Names match the detector CATEGORY as a prefix, so DuckMacro covers both DuckMacro variants.
void LoadWhiteList()
{
	char sPath[PLATFORM_MAX_PATH];
	if (hWhiteList.Length != 0)
		hWhiteList.Clear();
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/kevac/whitelist.ini");

	File hFile;
	if (!FileExists(sPath) || (hFile = OpenFile(sPath, "r")) == null)
	{
		LogError("[KevAC] Couldn't load SteamIDs from %s", sPath);
		return;
	}
	char sBuffer[KEVAC_WL_LEN];
	while (!hFile.EndOfFile())
	{
		hFile.ReadLine(sBuffer, sizeof(sBuffer));
		// Strip trailing comments so "STEAM_1:0:1 DuckMacro ; note" parses.
		int iComment = FindCharInString(sBuffer, ';');
		if (iComment != -1)
			sBuffer[iComment] = '\0';
		TrimString(sBuffer);
		if (!sBuffer[0] || sBuffer[0] == '/' || sBuffer[0] == '#')
			continue;

		// Reject anything that is not a real SteamID2. A malformed row can never
		// match a live client, so keeping it would be a whitelist that LOOKS
		// present and protects nobody - including a SteamID64 typed by hand.
		char sAuth[32], sScope[KEVAC_WL_LEN];
		ParseWhiteListEntry(sBuffer, sAuth, sizeof(sAuth), sScope, sizeof(sScope));
		if (!IsValidSteamId2(sAuth))
		{
			LogError("[KevAC] Ignoring malformed whitelist entry '%s' (expected STEAM_1:0:12345678).", sBuffer);
			continue;
		}

		hWhiteList.PushString(sBuffer);
	}
	hFile.Close();
}

// The engine tokenizer breaks an unquoted STEAM_1:0:123 on its colons, so GetCmdArg(1) returned
// STEAM_1 and (2) returned ':', writing junk rows into the whitelist. Parse the raw argument
// string instead. A quoted first token is still honored, keeping names with spaces working.
void SplitRawArgs(char[] sFirst, int iFirstLen, char[] sRest, int iRestLen)
{
	char sRaw[256];
	GetCmdArgString(sRaw, sizeof(sRaw));
	TrimString(sRaw);

	sFirst[0] = '\0';
	sRest[0] = '\0';
	if (!sRaw[0])
		return;

	if (sRaw[0] == '"')
	{
		int iClose = FindCharInString(sRaw[1], '"');
		if (iClose != -1)
		{
			sRaw[iClose + 1] = '\0';
			strcopy(sFirst, iFirstLen, sRaw[1]);
			strcopy(sRest, iRestLen, sRaw[iClose + 2]);
			TrimString(sRest);
			return;
		}
	}

	int iCut = FindCharInString(sRaw, ' ');
	if (iCut == -1)
	{
		strcopy(sFirst, iFirstLen, sRaw);
		return;
	}
	sRaw[iCut] = '\0';
	strcopy(sFirst, iFirstLen, sRaw);
	strcopy(sRest, iRestLen, sRaw[iCut + 1]);
	TrimString(sRest);
}

// STEAM_x:y:z with y in {0,1} and a numeric z. Anything else is a typo or a
// mangled argument, and must never reach the whitelist file - a bogus row is
// dead weight that makes the list unreadable and hides real entries.
bool IsValidSteamId2(const char[] sId)
{
	if (StrContains(sId, "STEAM_", false) != 0)
		return false;

	char sParts[4][24];
	if (ExplodeString(sId, ":", sParts, sizeof(sParts), sizeof(sParts[])) != 3)
		return false;
	if (!StrEqual(sParts[1], "0") && !StrEqual(sParts[1], "1"))
		return false;
	if (!sParts[2][0])
		return false;
	for (int i = 0; sParts[2][i] != '\0'; i++)
	{
		if (!IsCharNumeric(sParts[2][i]))
			return false;
	}
	return true;
}

// True when this exact exemption already exists. An existing blanket entry
// counts as covering any scoped add, since it already exempts everything.
bool WhiteListHasEntry(const char[] sAuthID, const char[] sScope)
{
	char sEntry[KEVAC_WL_LEN], sAuth[32], sExisting[KEVAC_WL_LEN];
	for (int i = 0; i < hWhiteList.Length; i++)
	{
		hWhiteList.GetString(i, sEntry, sizeof(sEntry));
		ParseWhiteListEntry(sEntry, sAuth, sizeof(sAuth), sExisting, sizeof(sExisting));
		if (!StrEqual(sAuth, sAuthID, false))
			continue;
		if (!sExisting[0])
			return true;
		if (StrEqual(sExisting, sScope, false))
			return true;
	}
	return false;
}

// Splits one whitelist entry into its SteamID and its (possibly empty) scope.
void ParseWhiteListEntry(const char[] sEntry, char[] sAuth, int iAuthLen, char[] sScope, int iScopeLen)
{
	sScope[0] = '\0';
	strcopy(sAuth, iAuthLen, sEntry);

	int iSpace = FindCharInString(sAuth, ' ');
	if (iSpace == -1)
		iSpace = FindCharInString(sAuth, '\t');
	if (iSpace == -1)
		return;

	sAuth[iSpace] = '\0';
	strcopy(sScope, iScopeLen, sEntry[iSpace + 1]);
	TrimString(sScope);
}

// True when this SteamID is exempt from THIS detector. An entry with no scope
// exempts everything, which is the pre-existing behavior.
bool IsWhitelistedFor(const char[] sAuthID, const char[] sCategory)
{
	char sEntry[KEVAC_WL_LEN], sAuth[32], sScope[KEVAC_WL_LEN];

	for (int i = 0; i < hWhiteList.Length; i++)
	{
		hWhiteList.GetString(i, sEntry, sizeof(sEntry));
		ParseWhiteListEntry(sEntry, sAuth, sizeof(sAuth), sScope, sizeof(sScope));

		if (!StrEqual(sAuth, sAuthID, false))
			continue;
		if (!sScope[0])
			return true; // blanket exemption

		// Comma-separated detector prefixes, sized past the current detector count so a long scope cannot
		// silently drop its tail - an entry that quietly stops covering a detector is a false ban waiting.
		char sNames[24][40];
		int iCount = ExplodeString(sScope, ",", sNames, sizeof(sNames), sizeof(sNames[]));
		for (int n = 0; n < iCount; n++)
		{
			TrimString(sNames[n]);
			if (sNames[n][0] && StrContains(sCategory, sNames[n], false) == 0)
				return true;
		}
	}
	return false;
}

public Action CommandAddWhiteList(int iClient, int iArgs)
{
	if (iArgs < 1)
	{
		ReplyToCommand(iClient, "%T", "Whitelist_Usage", iClient);
		return Plugin_Handled;
	}
	// Raw parsing: an unquoted SteamID is split by the engine tokenizer.
	char sSteamID[32], sScope[KEVAC_WL_LEN];
	SplitRawArgs(sSteamID, sizeof(sSteamID), sScope, sizeof(sScope));
	ReplaceString(sScope, sizeof(sScope), " ", ",");

	if (!IsValidSteamId2(sSteamID))
	{
		ReplyToCommand(iClient, "[KevAC] '%s' is not a valid SteamID2. Expected STEAM_1:0:12345678.", sSteamID);
		return Plugin_Handled;
	}
	if (WhiteListHasEntry(sSteamID, sScope))
	{
		ReplyToCommand(iClient, "[KevAC] %s is already whitelisted from %s - nothing added.",
			sSteamID, sScope[0] ? sScope : "ALL detectors");
		return Plugin_Handled;
	}

	char sLine[KEVAC_WL_LEN];
	if (sScope[0])
		FormatEx(sLine, sizeof(sLine), "%s %s", sSteamID, sScope);
	else
		strcopy(sLine, sizeof(sLine), sSteamID);

	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/kevac/whitelist.ini");
	File hFile = OpenFile(sPath, "a");
	if (hFile != null)
	{
		hFile.WriteLine(sLine);
		hFile.Close();
		ReplyToCommand(iClient, "%T", "Whitelist_Added", iClient, sLine);
		LogAction(iClient, -1, "\"%L\" whitelisted %s from %s", iClient, sSteamID, sScope[0] ? sScope : "ALL detectors");
		LoadWhiteList();
	}
	else
	{
		ReplyToCommand(iClient, "%T", "Whitelist_WriteFailed", iClient, sPath);
	}
	return Plugin_Handled;
}

public Action CommandReloadWhiteList(int iClient, int iArgs)
{
	LoadWhiteList();
	ReplyToCommand(iClient, "%T", "Whitelist_Loaded", iClient, hWhiteList.Length);
	return Plugin_Handled;
}

public Action CommandPrintWhiteList(int iClient, int iArgs)
{
	ReplyToCommand(iClient, "%T", "Whitelist_List", iClient, hWhiteList.Length);
	char sBuffer[KEVAC_WL_LEN], sAuth[32], sScope[KEVAC_WL_LEN];
	for (int i = 0; i < hWhiteList.Length; i++)
	{
		hWhiteList.GetString(i, sBuffer, sizeof(sBuffer));
		ParseWhiteListEntry(sBuffer, sAuth, sizeof(sAuth), sScope, sizeof(sScope));
		ReplyToCommand(iClient, "%s -> %s", sAuth, sScope[0] ? sScope : "ALL detectors");
	}
	return Plugin_Handled;
}

// Friendlier front end: accepts a live player as well as a raw SteamID, so an
// admin can clear someone without looking their ID up first.
public Action CommandKevACWhitelist(int iClient, int iArgs)
{
	if (iArgs < 1)
	{
		ReplyToCommand(iClient, "[KevAC] Usage: sm_kevac_whitelist <#userid|name|STEAM_1:0:X> <detector|all>");
		ReplyToCommand(iClient, "[KevAC] 'all' exempts them from EVERY detector; otherwise name the detector.");
		ReplyToCommand(iClient, "[KevAC] Several detectors: separate them with spaces or commas.");
		ReplyToCommand(iClient, "[KevAC] Example: sm_kevac_whitelist STEAM_1:0:711984383 DuckMacro");
		return Plugin_Handled;
	}

	char sTarget[64], sScope[KEVAC_WL_LEN];
	SplitRawArgs(sTarget, sizeof(sTarget), sScope, sizeof(sScope));
	if (!sTarget[0])
	{
		ReplyToCommand(iClient, "[KevAC] Usage: sm_kevac_whitelist <#userid|name|STEAM_1:0:X> <detector|all>");
		return Plugin_Handled;
	}

	// A blanket exemption must be asked for by name. Omitting the detector used
	// to grant it silently, which is a lot of authority for a typo.
	if (!sScope[0])
	{
		ReplyToCommand(iClient, "[KevAC] Name a detector, or 'all' to exempt them from everything.");
		return Plugin_Handled;
	}
	if (StrEqual(sScope, "all", false))
		sScope[0] = '\0'; // stored as a scopeless line, which is the blanket form
	else
		ReplaceString(sScope, sizeof(sScope), " ", ","); // "DuckMacro Scroll" == "DuckMacro,Scroll"

	char sSteamID[32];
	if (StrContains(sTarget, "STEAM_", false) == 0)
	{
		if (!IsValidSteamId2(sTarget))
		{
			ReplyToCommand(iClient, "[KevAC] '%s' is not a valid SteamID2. Expected STEAM_1:0:12345678.", sTarget);
			return Plugin_Handled;
		}
		strcopy(sSteamID, sizeof(sSteamID), sTarget);
	}
	else
	{
		int iTarget = FindTarget(iClient, sTarget, true, false);
		if (iTarget < 1)
			return Plugin_Handled; // FindTarget already replied
		if (!GetClientAuthId(iTarget, AuthId_Steam2, sSteamID, sizeof(sSteamID)))
		{
			ReplyToCommand(iClient, "[KevAC] Could not read that player's SteamID.");
			return Plugin_Handled;
		}
	}

	if (WhiteListHasEntry(sSteamID, sScope))
	{
		ReplyToCommand(iClient, "[KevAC] %s is already whitelisted from %s - nothing added.",
			sSteamID, sScope[0] ? sScope : "ALL detectors");
		return Plugin_Handled;
	}

	char sLine[KEVAC_WL_LEN];
	if (sScope[0])
		FormatEx(sLine, sizeof(sLine), "%s %s", sSteamID, sScope);
	else
		strcopy(sLine, sizeof(sLine), sSteamID);

	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/kevac/whitelist.ini");
	File hFile = OpenFile(sPath, "a");
	if (hFile == null)
	{
		ReplyToCommand(iClient, "[KevAC] Could not write %s", sPath);
		return Plugin_Handled;
	}
	hFile.WriteLine(sLine);
	hFile.Close();
	LoadWhiteList();

	ReplyToCommand(iClient, "[KevAC] Whitelisted %s from %s.", sSteamID, sScope[0] ? sScope : "ALL detectors");
	LogAction(iClient, -1, "\"%L\" whitelisted %s from %s", iClient, sSteamID, sScope[0] ? sScope : "ALL detectors");
	return Plugin_Handled;
}

// Removes whitelist lines for a SteamID by rewriting the file without them.
// A detector removes only that scope; 'all' removes every entry they have.
public Action CommandKevACUnwhitelist(int iClient, int iArgs)
{
	if (iArgs < 1)
	{
		ReplyToCommand(iClient, "[KevAC] Usage: sm_kevac_unwhitelist <#userid|name|STEAM_1:0:X> <detector|all>");
		ReplyToCommand(iClient, "[KevAC] 'all' removes every entry they have; otherwise only that detector's entry goes.");
		return Plugin_Handled;
	}

	// Raw parsing for the same reason as the add path: an unquoted SteamID gets
	// split on its colons, and "STEAM_1" would then remove the wrong rows.
	char sTarget[64], sScope[KEVAC_WL_LEN];
	SplitRawArgs(sTarget, sizeof(sTarget), sScope, sizeof(sScope));

	if (!sScope[0])
	{
		ReplyToCommand(iClient, "[KevAC] Name a detector, or 'all' to remove every entry for them.");
		return Plugin_Handled;
	}
	bool bAll = StrEqual(sScope, "all", false);
	if (!bAll)
		ReplaceString(sScope, sizeof(sScope), " ", ",");

	// Accept a live player as well as a raw SteamID, matching the add command.
	char sSteamID[32];
	if (StrContains(sTarget, "STEAM_", false) == 0)
	{
		if (!IsValidSteamId2(sTarget))
		{
			ReplyToCommand(iClient, "[KevAC] '%s' is not a valid SteamID2. Expected STEAM_1:0:12345678.", sTarget);
			return Plugin_Handled;
		}
		strcopy(sSteamID, sizeof(sSteamID), sTarget);
	}
	else
	{
		int iFound = FindTarget(iClient, sTarget, true, false);
		if (iFound < 1)
			return Plugin_Handled; // FindTarget already replied
		if (!GetClientAuthId(iFound, AuthId_Steam2, sSteamID, sizeof(sSteamID)))
		{
			ReplyToCommand(iClient, "[KevAC] Could not read that player's SteamID.");
			return Plugin_Handled;
		}
	}

	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/kevac/whitelist.ini");

	// Rebuild from the in-memory list, which already has comments stripped.
	int iRemoved = 0;
	File hFile = OpenFile(sPath, "w");
	if (hFile == null)
	{
		ReplyToCommand(iClient, "[KevAC] Could not write %s", sPath);
		return Plugin_Handled;
	}

	char sEntry[KEVAC_WL_LEN], sAuth[32], sExistingScope[KEVAC_WL_LEN];
	for (int i = 0; i < hWhiteList.Length; i++)
	{
		hWhiteList.GetString(i, sEntry, sizeof(sEntry));
		ParseWhiteListEntry(sEntry, sAuth, sizeof(sAuth), sExistingScope, sizeof(sExistingScope));
		// 'all' drops every line for them; a named detector drops only the line
		// carrying that exact scope, so their other exemptions survive.
		if (StrEqual(sAuth, sSteamID, false)
			&& (bAll || StrEqual(sExistingScope, sScope, false)))
		{
			iRemoved++;
			continue;
		}
		hFile.WriteLine(sEntry);
	}
	hFile.Close();
	LoadWhiteList();

	ReplyToCommand(iClient, "[KevAC] Removed %d whitelist entr%s for %s (%s).",
		iRemoved, iRemoved == 1 ? "y" : "ies", sSteamID, bAll ? "all detectors" : sScope);
	if (iRemoved > 0)
		LogAction(iClient, -1, "\"%L\" removed %s from the KevAC whitelist", iClient, sSteamID);
	return Plugin_Handled;
}

// Wipes the whole whitelist. Requires the literal word 'confirm' so it cannot
// be fat-fingered - there is no undo, and losing the list silently re-exposes
// every whitelisted player to a ban.
public Action CommandClearWhiteList(int iClient, int iArgs)
{
	char sConfirm[16];
	if (iArgs >= 1)
		GetCmdArg(1, sConfirm, sizeof(sConfirm));

	if (!StrEqual(sConfirm, "confirm", false))
	{
		ReplyToCommand(iClient, "[KevAC] This removes ALL %d whitelist entries.", hWhiteList.Length);
		ReplyToCommand(iClient, "[KevAC] Run: sm_kevac_clearwhitelist confirm");
		return Plugin_Handled;
	}

	int iRemoved = hWhiteList.Length;

	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/kevac/whitelist.ini");
	File hFile = OpenFile(sPath, "w");
	if (hFile == null)
	{
		ReplyToCommand(iClient, "[KevAC] Could not write %s", sPath);
		return Plugin_Handled;
	}
	hFile.WriteLine("// KevAC whitelist. One entry per line:");
	hFile.WriteLine("//   STEAM_1:0:12345678 DuckMacro    ; exempt from that detector only");
	hFile.WriteLine("//   STEAM_1:0:12345678              ; exempt from EVERY detector");
	hFile.Close();
	LoadWhiteList();

	ReplyToCommand(iClient, "[KevAC] Cleared the whitelist (%d entr%s removed).", iRemoved, iRemoved == 1 ? "y" : "ies");
	LogAction(iClient, -1, "\"%L\" cleared the entire KevAC whitelist (%d entries)", iClient, iRemoved);
	return Plugin_Handled;
}

public Action CommandReloadConfig(int iClient, int iArgs)
{
	ServerCommand("exec sourcemod/KevAC.cfg");
	LoadCheatCvarList();
	ReplyToCommand(iClient, "%T", "Config_Reloaded", iClient);
	return Plugin_Handled;
}

public Action CommandHelp(int iClient, int iArgs)
{
	bool root = CheckCommandAccess(iClient, "sm_kevac_root", ADMFLAG_ROOT);

	ReplyToCommand(iClient, "%T", "Help_Title", iClient);
	ReplyToCommand(iClient, "%T", "Help_Kevac", iClient);
	ReplyToCommand(iClient, "%T", "Help_Alerts", iClient);
	ReplyToCommand(iClient, "%T", "Help_Stats", iClient);
	ReplyToCommand(iClient, "%T", "Help_Ext", iClient);
	ReplyToCommand(iClient, "%T", "Help_ListenerAudit", iClient);
	ReplyToCommand(iClient, "%T", "Help_ListenerAuditAll", iClient);
	ReplyToCommand(iClient, "%T", "Help_StabTrace", iClient);
	ReplyToCommand(iClient, "%T", "Help_WhitelistList", iClient);
	if (root)
	{
		ReplyToCommand(iClient, "%T", "Help_ConfigReload", iClient);
		ReplyToCommand(iClient, "%T", "Help_WhitelistReload", iClient);
		ReplyToCommand(iClient, "%T", "Help_WhitelistAdd", iClient);
		// Literals rather than %T: these are newer than the phrase file, and a
		// missing phrase prints as an error instead of the line.
		ReplyToCommand(iClient, "sm_kevac_whitelist <#userid|name|steamid> [Detector[,Detector...]] - exempt a player from one detector, or all if omitted");
		ReplyToCommand(iClient, "sm_kevac_unwhitelist <STEAM_1:0:...> - remove every whitelist entry for a SteamID");
		ReplyToCommand(iClient, "  Detector names: DuckMacro, AHKStrafe, StrafeSync, HideLatency, FakeLag, EventListener, AngleClamp, CmdRate");
	}
	ReplyToCommand(iClient, "%T", "Help_HnsPolicy", iClient);
	ReplyToCommand(iClient, "%T", "Help_BacktrackPolicy", iClient);
	ReplyToCommand(iClient, "%T", "Help_CadencePolicy", iClient);
	ReplyToCommand(iClient, "%T", "Help_DiagnosticTitle", iClient);
	ReplyToCommand(iClient, "%T", "Help_Cheat", iClient);
	ReplyToCommand(iClient, "%T", "Help_Legit", iClient);
	ReplyToCommand(iClient, "%T", "Help_Probe", iClient);
	ReplyToCommand(iClient, "%T", "Help_Stop", iClient);
	ReplyToCommand(iClient, "%T", "Help_Detectors", iClient);
	return Plugin_Handled;
}

// Evidence for a ban belongs in a dedicated server-side log, never in the
// public SourceBans++ reason. This preserves an audit trail without teaching
// players which detector acted.
void LogKevACBan(int client, int actionMethod, int banMinutes, const char[] category, const char[] evidence)
{
	char auth[32];
	if (!GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth)))
		strcopy(auth, sizeof(auth), "UNKNOWN");

	LogToFile("addons/sourcemod/logs/KevAC_ban.log",
		"[KevAC] %N (%s) | action=%s | duration_minutes=%d | detector=%s | evidence=%s",
		client, auth, actionMethod == SBBAN ? "SourceBans++" : "SourceMod", banMinutes, category, evidence);
}
