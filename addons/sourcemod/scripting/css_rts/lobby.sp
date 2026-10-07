// css_rts/lobby.sp -- v0.5 pre-game LOBBY + series.
// Map load -> LOBBY (no bots, humans frozen, no Intel). The host (first human) picks the settings
// in the lobby menu, presses Start -> 10 s countdown -> bots spawn, match runs until a win condition
// or the time limit -> end screen -> next game of the series (countdown) or back to the lobby.

void Lobby_Init() {
	g_hCvarLobby = CreateConVar("css_rts_lobby", "1", "1 = pre-game lobby on map load (settings menu + Start); 0 = start a match immediately with the defaults", _, true, 0.0, true, 1.0);
	g_hCvarCountdown = CreateConVar("css_rts_start_countdown", "10", "Seconds of countdown after Start", _, true, 0.0, true, 60.0);
	g_hCvarWEWorkers = CreateConVar("css_rts_we_start_workers", "2", "Workers Elimination: free workers each team starts with", _, true, 1.0, true, 8.0);
	g_hHudLobby = CreateHudSynchronizer();
	RegConsoleCmd("sm_rts_lobby", cmdLobby, "Open the lobby / game setup menu (host)");
	RegConsoleCmd("sm_rts_debug_lobby", cmdDebugLobby, "state | start | forcestart | lobby | win <t|ct|draw> [reason] | timeup | set <key> <value>");
	HookEvent("player_spawn", Event_LobbySpawn);
}

bool InLobby() {
	return g_eGame == GS_Lobby || g_eGame == GS_Countdown;
}

bool IsHost(int iClient) {
	if (!iClient) return true;
	if (CheckCommandAccess(iClient, "sm_rts_lobby_admin", ADMFLAG_GENERIC, true)) return true;
	return GetClientOfUserId(g_iHostUserId) == iClient;
}

// first human in the server becomes host; re-pick if the host left
int Lobby_Host() {
	int iHost = GetClientOfUserId(g_iHostUserId);
	if (iHost && IsClientInGame(iHost)) return iHost;
	g_iHostUserId = 0;
	for (int i=1; i<=MaxClients; i++) {
		if (IsClientInGame(i) && !IsFakeClient(i)) { g_iHostUserId = GetClientUserId(i); return i; }
	}
	return 0;
}

int Lobby_SeriesNeeded() {
	return g_iSetSeries / 2 + 1;
}

void TeamName(int t, char[] s, int n) {
	strcopy(s, n, t == CS_TEAM_T ? "Terrorists" : (t == CS_TEAM_CT ? "Counter-Terrorists" : "Nobody"));
}

void CmdrSettingName(int t, char[] s, int n) {
	int iC = g_iSetCmdrUserId[t] ? GetClientOfUserId(g_iSetCmdrUserId[t]) : 0;
	if (iC && IsClientInGame(iC)) FormatEx(s, n, "%N", iC);
	else strcopy(s, n, "auto (first human)");
}

void Lobby_ShowMenu(int iClient) {
	if (!iClient || IsFakeClient(iClient)) return;
	if (!IsHost(iClient)) {
		PrintToChat(iClient, "\x04[RTS]\x01 Only the host (%N) can change the game setup. Settings are shown on your HUD.", Lobby_Host());
		return;
	}
	Menu hMenu = new Menu(MenuHandler_Lobby);
	hMenu.SetTitle("CSS RTS - GAME SETUP%s\n ", g_iSeriesGame > 0 ? " (series in progress)" : "");
	char s[96], sT[48], sCT[48];
	FormatEx(s, sizeof(s), "Win: destroy the enemy HQ"); hMenu.AddItem("mode", s, ITEMDRAW_DISABLED);
	FormatEx(s, sizeof(s), "Unit pool: %d per team", g_iSetPool); hMenu.AddItem("pool", s);
	FormatEx(s, sizeof(s), "Time limit: %d min", g_iSetMinutes); hMenu.AddItem("time", s);
	FormatEx(s, sizeof(s), "Players per team (bots fill): %d", g_iSetBots); hMenu.AddItem("bots", s);
	FormatEx(s, sizeof(s), "Bot difficulty: %s", g_sDiffNames[g_iSetDifficulty]); hMenu.AddItem("diff", s);
	CmdrSettingName(CS_TEAM_T, sT, sizeof(sT)); CmdrSettingName(CS_TEAM_CT, sCT, sizeof(sCT));
	FormatEx(s, sizeof(s), "T Commander: %s", sT); hMenu.AddItem("cmdt", s);
	FormatEx(s, sizeof(s), "CT Commander: %s", sCT); hMenu.AddItem("cmdct", s);
	FormatEx(s, sizeof(s), "Series: %s", g_iSetSeries == 1 ? "single game" : (g_iSetSeries == 3 ? "best of 3" : "best of 5")); hMenu.AddItem("series", s);
	FormatEx(s, sizeof(s), "My team: %s (switch)", GetClientTeam(iClient) == CS_TEAM_T ? "Terrorists" : "Counter-Terrorists"); hMenu.AddItem("myteam", s);
	hMenu.AddItem("start", g_eGame == GS_Countdown ? ">> Cancel countdown" : ">> START");
	hMenu.ExitButton = true;
	hMenu.Pagination = 6;
	hMenu.Display(iClient, MENU_TIME_FOREVER);
}

int CycleInt(int v, const int[] opts, int n) {
	for (int i=0; i<n; i++) if (opts[i] == v) return opts[(i + 1) % n];
	return opts[0];
}

// next human on team t after the current pick (0 = back to auto)
int NextCmdrPick(int t) {
	int iCur = g_iSetCmdrUserId[t] ? GetClientOfUserId(g_iSetCmdrUserId[t]) : 0;
	bool bPast = iCur == 0;
	for (int i=1; i<=MaxClients; i++) {
		if (!IsClientInGame(i) || IsFakeClient(i) || GetClientTeam(i) != t) continue;
		if (bPast) return GetClientUserId(i);
		if (i == iCur) bPast = true;
	}
	return 0;
}

public int MenuHandler_Lobby(Menu hMenu, MenuAction eAction, int iClient, int iItem) {
	if (eAction == MenuAction_End) { delete hMenu; return 0; }
	if (eAction != MenuAction_Select) return 0;
	char s[16];
	hMenu.GetItem(iItem, s, sizeof(s));
	if (!Lobby_ApplySetting(iClient, s)) return 0;
	if (InLobby()) Lobby_ShowMenu(iClient);
	return 0;
}

// returns false if the menu should not be reopened
bool Lobby_ApplySetting(int iClient, const char[] s) {
	static int iPools[] = {100, 200, 300}, iTimes[] = {30, 40, 45}, iSeries[] = {1, 3, 5}, iTargets[] = {6000, 10000, 15000};
	if (StrEqual(s, "mode")) g_eMode = view_as<GameMode>((view_as<int>(g_eMode) + 1) % 4);
	else if (StrEqual(s, "pool")) g_iSetPool = CycleInt(g_iSetPool, iPools, 3);
	else if (StrEqual(s, "time")) g_iSetMinutes = CycleInt(g_iSetMinutes, iTimes, 3);
	else if (StrEqual(s, "bots")) g_iSetBots = (g_iSetBots + 1) % 17;
	else if (StrEqual(s, "diff")) g_iSetDifficulty = (g_iSetDifficulty + 1) % 4;
	else if (StrEqual(s, "cmdt")) g_iSetCmdrUserId[CS_TEAM_T] = NextCmdrPick(CS_TEAM_T);
	else if (StrEqual(s, "cmdct")) g_iSetCmdrUserId[CS_TEAM_CT] = NextCmdrPick(CS_TEAM_CT);
	else if (StrEqual(s, "series")) { g_iSetSeries = CycleInt(g_iSetSeries, iSeries, 3); g_iSeriesGame = 0; g_iSeriesWins[2] = g_iSeriesWins[3] = 0; }
	else if (StrEqual(s, "target")) g_iSetIntelTarget = CycleInt(g_iSetIntelTarget, iTargets, 3);
	else if (StrEqual(s, "hqloss")) g_bSetHQLoss = !g_bSetHQLoss;
	else if (StrEqual(s, "myteam") && iClient) AutoJoin_SwitchTeam(iClient, GetClientTeam(iClient) == CS_TEAM_T ? CS_TEAM_CT : CS_TEAM_T);
	else if (StrEqual(s, "start")) {
		if (g_eGame == GS_Countdown) { Lobby_CancelCountdown(iClient); return true; }
		Lobby_StartCountdown(iClient);
		return false;
	}
	return true;
}

void Lobby_MapStart() {
	g_iSeriesGame = 0;
	g_iSeriesWins[2] = g_iSeriesWins[3] = 0;
	g_iSetCmdrUserId[2] = g_iSetCmdrUserId[3] = 0;
	CreateTimer(1.0, Timer_Lobby, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	MenuConf_Apply();     // v0.5.4: values chosen in the main menu's Create RTS Game dialog
	if (g_hCvarLobby.BoolValue) Lobby_Enter(false);
	else { LogMessage("[RTS] state: css_rts_lobby 0 -> auto start"); g_eGame = GS_Countdown; g_fCountdownEnd = GetGameTime() + 3.0; }
}

// back to the lobby: kick bots, freeze humans, no Intel
void Lobby_Enter(bool bAnnounce) {
	LogMessage("[RTS] state: lobby (announce %d)", bAnnounce);
	g_eGame = GS_Lobby;
	g_bMatchOver = false;
	ServerCommand("bot_quota 0");
	ServerCommand("bot_kick");
	ServerCommand("mp_timelimit 0");
	for (int t=0; t<4; t++) { g_iIntel[t] = g_hCvarIntelStart.IntValue; g_iIntelEarned[t] = 0; }
	Unlocks_Reset();
	Workers_ResetMatch();
	Guard_Reset();
	Train_Reset();
	HQ_Reset();
	for (int i=1; i<=MaxClients; i++) if (IsClientInGame(i) && IsPlayerAlive(i) && !IsFakeClient(i)) Lobby_Freeze(i, true);
	if (bAnnounce) PrintToChatAll("\x04[RTS]\x01 Back in the \x04lobby\x01. Host: type \x04!rts_lobby\x01 (or F2) to set up the next game.");
	int iHost = Lobby_Host();
	if (iHost && !MenuConf_HoldLobbyMenu()) Lobby_ShowMenu(iHost);
	else if (iHost) PrintToChat(iHost, "\x04[RTS]\x01 Using the RTS Create settings. The match starts in a moment.");
}

void Lobby_Freeze(int iClient, bool bFreeze) {
	if (g_bBodyHidden[iClient]) return;
	int f = GetEntityFlags(iClient);
	SetEntityFlags(iClient, bFreeze ? (f | FL_FROZEN) : (f & ~FL_FROZEN));
	SetEntProp(iClient, Prop_Data, "m_takedamage", bFreeze ? 0 : 2);
}

public void Event_LobbySpawn(Event hEvent, const char[] sName, bool bDontBroadcast) {
	int iClient = GetClientOfUserId(hEvent.GetInt("userid"));
	if (iClient && InLobby() && !IsFakeClient(iClient)) CreateTimer(0.3, Timer_LobbyFreeze, GetClientUserId(iClient), TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_LobbyFreeze(Handle h, int iUserId) {
	int iClient = GetClientOfUserId(iUserId);
	if (iClient && IsClientInGame(iClient) && IsPlayerAlive(iClient) && InLobby()) {
		Lobby_Freeze(iClient, true);
		if (iClient == Lobby_Host() && !MenuConf_HoldLobbyMenu()) Lobby_ShowMenu(iClient);
	}
	return Plugin_Stop;
}

void Lobby_StartCountdown(int iClient) {
	if (g_eGame != GS_Lobby) return;
	g_eGame = GS_Countdown;
	if (iClient) CancelClientMenu(iClient);
	LogMessage("[RTS] state: countdown started by %L", iClient);
	g_fCountdownEnd = GetGameTime() + g_hCvarCountdown.FloatValue;
	PrintToChatAll("\x04[RTS]\x01 Starting in %d s: \x04%s\x01, pool %d, %d min.", g_hCvarCountdown.IntValue, g_sModeNames[g_eMode], g_iSetPool, g_iSetMinutes);
}

void Lobby_CancelCountdown(int iClient) {
	if (g_eGame != GS_Countdown) return;
	g_eGame = GS_Lobby;
	LogMessage("[RTS] state: countdown cancelled by %L", iClient);
	PrintToChatAll("\x04[RTS]\x01 Countdown cancelled%s.", iClient ? " by the host" : "");
}

void Lobby_BeginMatch() {
	MenuConf_Apply();
	LogMessage("[RTS] state: match live (from state %d)", g_eGame);
	g_eGame = GS_Live;
	g_bMatchOver = false;
	g_fMatchStart = GetGameTime();
	g_fMatchEnd = g_iSetMinutes > 0 ? g_fMatchStart + g_iSetMinutes * 60.0 : 0.0;
	g_hCvarUnitPool.IntValue = g_iSetPool;
	g_hCvarFpsPerTeam.IntValue = g_iSetBots;
	ServerCommand("bot_difficulty %d", g_iSetDifficulty);
	ServerCommand("mp_timelimit 0");
	ResetPools();
	HQ_Reset();
	for (int t=0; t<4; t++) { g_iIntel[t] = g_hCvarIntelStart.IntValue; g_iIntelEarned[t] = 0; g_bHadWorkers[t] = false; }
	Unlocks_Reset();
	Workers_ResetMatch();
	Guard_Reset();
	Train_Reset();
	if (g_eMode == Mode_Workers) {
		for (int t=CS_TEAM_T; t<=CS_TEAM_CT; t++) g_iWorkersOwned[t] = g_hCvarWEWorkers.IntValue;
	}
	// Commander assignment: picked player, else the first human (auto)
	for (int t=CS_TEAM_T; t<=CS_TEAM_CT; t++) {
		int iPick = g_iSetCmdrUserId[t] ? GetClientOfUserId(g_iSetCmdrUserId[t]) : 0;
		if (iPick && IsClientInGame(iPick) && GetClientTeam(iPick) == t && GetTeamCommander(t) != iPick) {
			int iCur = GetTeamCommander(t);
			if (iCur) ReleaseCommander(iCur, false);
			AssignCommander(iPick);
		}
	}
	for (int i=1; i<=MaxClients; i++) if (IsClientInGame(i) && IsPlayerAlive(i) && !IsFakeClient(i)) Lobby_Freeze(i, false);
	g_fNextWave = GetGameTime() + g_hCvarWaveInterval.FloatValue;
	ServerCommand("mp_restartgame 1");
	char sSeries[48];
	if (g_iSetSeries > 1) FormatEx(sSeries, sizeof(sSeries), " - game %d of best-of-%d (T %d : %d CT)", g_iSeriesGame + 1, g_iSetSeries, g_iSeriesWins[CS_TEAM_T], g_iSeriesWins[CS_TEAM_CT]);
	Lobby_AnnounceGoal(sSeries);
}

// v0.5.2: one line per match start (was four)
void Lobby_AnnounceGoal(const char[] sSeries="") {
	char sGoal[96];
	switch (g_eMode) {
		case Mode_Workers: FormatEx(sGoal, sizeof(sGoal), "kill all enemy workers (you start with %d)", g_hCvarWEWorkers.IntValue);
		case Mode_Attrition: FormatEx(sGoal, sizeof(sGoal), "drain the enemy unit pool (%d each)", g_iSetPool);
		case Mode_IntelRace: FormatEx(sGoal, sizeof(sGoal), "first to earn %d Intel", g_iSetIntelTarget);
		case Mode_HQ: FormatEx(sGoal, sizeof(sGoal), "destroy the enemy HQ (%d HP)", g_hCvarHQHealth.IntValue);
	}
	PrintToChatAll("\x04[RTS] GO!\x01 %s%s: %s, %d min.", g_sModeNames[g_eMode], sSeries, sGoal, g_iSetMinutes);
	if (g_bVsAi) PrintToChatAll("\x04[RTS]\x01 Vs AI: the other team matches your research, soldiers, and workers.");
}

public Action Timer_Lobby(Handle hTimer) {
	float fNow = GetGameTime();
	if (g_eGame == GS_Lobby || g_eGame == GS_Countdown) {
		if (g_eGame == GS_Countdown) {
			int iLeft = RoundToCeil(g_fCountdownEnd - fNow);
			if (iLeft <= 0) { Lobby_BeginMatch(); return Plugin_Continue; }
			PrintCenterTextAll("Match starts in %d", iLeft);
		}
		MenuConf_LobbyTick();
		// keep the lobby empty of bots
		for (int i=1; i<=MaxClients; i++) {
			if (IsClientInGame(i) && IsFakeClient(i) && !IsClientSourceTV(i) && !g_bSelfTestRunning) { ServerCommand("bot_quota 0"); ServerCommand("bot_kick"); break; }
		}
	} else if (g_eGame == GS_Live) {
		Match_CheckWin();
	}
	return Plugin_Continue;
}

