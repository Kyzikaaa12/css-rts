// css_rts/countdown.sp -- per-client delayed actions with an on-screen countdown (view transitions)

enum PendingAction {
	Pending_None = 0,
	Pending_EnterView,
	Pending_LeaveRole
};

PendingAction g_ePending[MAXPLAYERS+1];
float g_fPendingAt[MAXPLAYERS+1];
ConVar g_hCvarViewDelay;

void Countdown_Init() {
	g_hCvarViewDelay = CreateConVar("css_rts_view_delay", "3", "Seconds of countdown when entering the command view / leaving the commander role", _, true, 0.0);
}

void Countdown_MapStart() {
	CreateTimer(0.25, Timer_Countdowns, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

void SchedulePending(int iClient, PendingAction eAction, float fDelay=-1.0) {
	if (fDelay < 0.0) fDelay = g_hCvarViewDelay.FloatValue;
	g_ePending[iClient] = eAction;
	g_fPendingAt[iClient] = GetGameTime() + fDelay;
	if (fDelay <= 0.0) RunPending(iClient);
}

void CancelPending(int iClient) {
	g_ePending[iClient] = Pending_None;
}

public Action Timer_Countdowns(Handle hTimer) {
	float fNow = GetGameTime();
	for (int i=1; i<=MaxClients; i++) {
		if (g_ePending[i] == Pending_None) continue;
		if (!IsClientInGame(i)) { g_ePending[i] = Pending_None; continue; }
		float fLeft = g_fPendingAt[i] - fNow;
		if (fLeft <= 0.0) {
			RunPending(i);
		} else if (!IsFakeClient(i)) {
			Hud_Action(i, "%s in %d...", g_ePending[i] == Pending_EnterView ? "Entering command view" : "Leaving command (becoming soldier)", RoundToCeil(fLeft));
		}
	}
	return Plugin_Continue;
}

void RunPending(int iClient) {
	PendingAction eAction = g_ePending[iClient];
	g_ePending[iClient] = Pending_None;
	char sWhy[64];
	switch (eAction) {
		case Pending_EnterView: {
			if (IsPlayerAlive(iClient) && GetTeamCommander(GetClientTeam(iClient)) == iClient && !g_eCommander[iClient].bEnabled) {
				if (!EnterCommanderView(iClient, true, sWhy, sizeof(sWhy)) && !IsFakeClient(iClient)) {
					PrintToChat(iClient, "\x04[RTS]\x01 Cannot enter command view: %s.", sWhy);
				}
			}
		}
		case Pending_LeaveRole: {
			ReleaseCommander(iClient, true);
		}
	}
}
