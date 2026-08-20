#if defined _KevAC_included
  #endinput
#endif
#define _KevAC_included

forward void KevAC_OnCheatDetected(const int client);
forward void KevAC_OnListenerUpdate(const int client);
forward void KevAC_OnListenerTelemetry(const int client, const int activeSubscriptions, const int blacklistedSubscriptions);
forward void KevAC_OnListenerProbe(const int client, const int rawCalls, const int humanCalls);

/**
 * Returns cumulative ListenEvents probe counters from the extension.
 * The first three counters belong to the legacy static detour. Vtable packets
 * and telemetry updates belong to the per-client ProcessListenEvents hook.
 */
native bool KevAC_GetListenerProbeStats(int &rawCalls, int &humanCalls, int &acceptedPackets, int &vtablePackets, int &telemetryUpdates);

/**
 * Returns whether the extension installed the static ProcessListenEvents
 * detour. This does not imply that a client has sent a listener packet.
 */
native bool KevAC_IsListenerStaticDetourEnabled();

/**
 * Returns a compact fingerprint of a client's last accepted server-visible
 * ListenEvents mask, or 0 when no mask has been observed.
 */
native int KevAC_GetListenerMaskFingerprint(int client);

/**
 * Copies the exact currently matched blacklist event names for a client. Empty
 * means no blacklist entry matched the last inspected listener table.
 */
native bool KevAC_GetListenerBlacklistedEvents(int client, char[] buffer, int maxlength);

/**
 * Checks a comma-separated list of event names against a client's latest
 * verified server-side listener table. It never changes detection state.
 * Returns the number of matched candidate names, or -1 when no listener table
 * has been observed for that client.
 */
native int KevAC_AuditListenerCandidates(int client, const char[] candidates, char[] matches, int maxlength);

/**
 * Copies every currently subscribed event name from KevAC's known CS:GO event
 * catalog for a client. It returns the number of catalog matches, or -1 when
 * no verified listener table has been observed for that client.
 */
native int KevAC_GetAllListenerAuditEvents(int client, char[] matches, int maxlength);

/**
 * Decodes a verified CCLCMsg_ListenEvents packet from the live client-message
 * handler and checks the server's listener table after the engine accepted it.
 */
native bool KevAC_InspectListenEvents(int client, Address messageHandler, Address message, int &activeSubscriptions, int &blacklistedSubscriptions, bool &changed);

public Extension __ext_KevAC =
{
	name = "KevAC",
	file = "KevAC.ext",
#if defined AUTOLOAD_EXTENSIONS
	autoload = 1,
#else
	autoload = 0,
#endif
#if defined REQUIRE_EXTENSIONS
	required = 1,
#else
	required = 0,
#endif
};
