// css_rts/lobbymatch.sp -- win conditions, time limit + tiebreak, end screen, series progression.
//
// Win conditions (checked every second while live):
//  * any mode: a team with an empty unit pool and nobody alive (FPS) loses
//  * Workers Elimination: a team that had workers and now has none alive loses
//  * Intel Race: first team whose EARNED Intel reaches the target wins
// Time limit tiebreak: Workers -> living workers, then units left; Attrition -> units left
// (pool + alive FPS); Intel Race -> Intel earned. Equal -> draw (no series point).

int Match_UnitsLeft(int t) {
	return g_iUnitPool[t] + CountFps(t, true);
}

int Match_TiebreakScore(int t) {
	switch (g_eMode) {
		case Mode_Workers: return Npc_Count(Npc_Worker, t) * 100000 + Match_UnitsLeft(t);
		case Mode_IntelRace: return g_iIntelEarned[t];
		case Mode_HQ: return g_iHQHealth[t] * 1000 + Match_UnitsLeft(t);
	}
	return Match_UnitsLeft(t);
}

void Match_CheckWin() {
	if (g_bMatchOver || g_bSelfTestRunning) return;
	for (int t=CS_TEAM_T; t<=CS_TEAM_CT; t++) {
		int e = t == CS_TEAM_T ? CS_TEAM_CT : CS_TEAM_T;
		if (HQ_Destroyed(t)) { Match_EndGame(e, "destroyed the enemy HQ"); return; }
	}
	if (g_fMatchEnd > 0.0 && GetGameTime() >= g_fMatchEnd) Match_TimeUp();
}

void Match_TimeUp() {
	int a = Match_TiebreakScore(CS_TEAM_T), b = Match_TiebreakScore(CS_TEAM_CT);
	if (a == b) Match_EndGame(0, "time limit - draw");
	else Match_EndGame(a > b ? CS_TEAM_T : CS_TEAM_CT, g_eMode == Mode_Workers ? "time limit - more workers / units left" :
		(g_eMode == Mode_Attrition ? "time limit - more units left" : (g_eMode == Mode_HQ ? "time limit - more HQ health left" : "time limit - more Intel earned")));
}

void Match_EndGame(int iWinner, const char[] sReason) {
	if (g_bMatchOver) return;
	g_bMatchOver = true;
	g_eGame = GS_Ended;
	g_iSeriesGame++;
	if (iWinner) g_iSeriesWins[iWinner]++;
	char sW[32];
	TeamName(iWinner, sW, sizeof(sW));
	int iMin = RoundToFloor((GetGameTime() - g_fMatchStart) / 60.0);
	bool bSeriesOver = g_iSetSeries <= 1 || g_iSeriesWins[CS_TEAM_T] >= Lobby_SeriesNeeded() || g_iSeriesWins[CS_TEAM_CT] >= Lobby_SeriesNeeded() || g_iSeriesGame >= g_iSetSeries;
	// v0.5.2: two lines (was five)
	char sSer[64] = "";
	if (g_iSetSeries > 1) FormatEx(sSer, sizeof(sSer), "  Series T %d : %d CT%s", g_iSeriesWins[CS_TEAM_T], g_iSeriesWins[CS_TEAM_CT], bSeriesOver ? " (over)" : " (next in 15 s)");
	PrintToChatAll("\x04[RTS] GAME OVER: %s%s\x01 - %s, %d min.%s", iWinner ? sW : "DRAW", iWinner ? " WIN" : "", sReason, iMin, sSer);
	PrintToChatAll("\x04[RTS]\x01 Units T %d / CT %d   Workers %d / %d   Intel earned %d / %d   Research %d / %d",
		Match_UnitsLeft(CS_TEAM_T), Match_UnitsLeft(CS_TEAM_CT), Npc_Count(Npc_Worker, CS_TEAM_T), Npc_Count(Npc_Worker, CS_TEAM_CT),
		g_iIntelEarned[CS_TEAM_T], g_iIntelEarned[CS_TEAM_CT], Unlocks_Count(CS_TEAM_T), Unlocks_Count(CS_TEAM_CT));
	PrintToServer("[RTS] game over: winner %d reason '%s' series T%d-CT%d game %d/%d over=%d", iWinner, sReason, g_iSeriesWins[CS_TEAM_T], g_iSeriesWins[CS_TEAM_CT], g_iSeriesGame, g_iSetSeries, bSeriesOver);
	PrintCenterTextAll("%s%s\n%s", iWinner ? sW : "DRAW", iWinner ? " WIN" : "", sReason);
	if (iWinner) {
		CS_SetTeamScore(iWinner, CS_GetTeamScore(iWinner) + 1);
		SetTeamScore(iWinner, CS_GetTeamScore(iWinner));
	}
	CS_TerminateRound(14.0, iWinner == CS_TEAM_T ? CSRoundEnd_TerroristWin : (iWinner == CS_TEAM_CT ? CSRoundEnd_CTWin : CSRoundEnd_Draw), true);
	g_iEndGen++;
	DataPack hPack;
	CreateDataTimer(15.0, Timer_AfterGame, hPack, TIMER_FLAG_NO_MAPCHANGE);
	hPack.WriteCell(g_iEndGen);
	hPack.WriteCell(bSeriesOver);
}

public Action Timer_AfterGame(Handle h, DataPack hPack) {
	hPack.Reset();
	int iGen = hPack.ReadCell();
	bool bSeriesOver = hPack.ReadCell() != 0;
	if (iGen != g_iEndGen || g_eGame != GS_Ended) return Plugin_Stop;
	if (bSeriesOver) {
		if (g_iSetSeries > 1) {
			int w = g_iSeriesWins[CS_TEAM_T] > g_iSeriesWins[CS_TEAM_CT] ? CS_TEAM_T : (g_iSeriesWins[CS_TEAM_CT] > g_iSeriesWins[CS_TEAM_T] ? CS_TEAM_CT : 0);
			char sW[32]; TeamName(w, sW, sizeof(sW));
			PrintToChatAll("\x04[RTS] SERIES WINNER: %s\x01 (T %d : %d CT)", w ? sW : "draw", g_iSeriesWins[CS_TEAM_T], g_iSeriesWins[CS_TEAM_CT]);
		}
		g_iSeriesGame = 0;
		g_iSeriesWins[2] = g_iSeriesWins[3] = 0;
		Lobby_Enter(true);
	} else {
		g_bMatchOver = false;
		g_eGame = GS_Countdown;
		g_fCountdownEnd = GetGameTime() + g_hCvarCountdown.FloatValue;
		PrintToChatAll("\x04[RTS]\x01 Next game of the series starts in %d s (same settings).", g_hCvarCountdown.IntValue);
	}
	return Plugin_Stop;
}

public Action cmdLobby(int iClient, int iArgs) {
	iClient = ResolveClient(iClient);
	if (!iClient) { ReplyToCommand(iClient, "[RTS] In-game only (server: sm_rts_debug_lobby)"); return Plugin_Handled; }
	if (!InLobby()) {
		if (IsHost(iClient) && g_eGame == GS_Live) { Lobby_ShowAbortMenu(iClient); return Plugin_Handled; }
		PrintToChat(iClient, "\x04[RTS]\x01 A game is running. The lobby opens after the game / series.");
		return Plugin_Handled;
	}
	Lobby_ShowMenu(iClient);
	return Plugin_Handled;
}

void Lobby_ShowAbortMenu(int iClient) {
	Menu hMenu = new Menu(MenuHandler_Abort);
	hMenu.SetTitle("Game running (%s). Abort and return to the lobby?\n ", g_sModeNames[g_eMode]);
	hMenu.AddItem("no", "No, keep playing");
	hMenu.AddItem("yes", "Yes: end the game (draw) and reset the series");
	hMenu.Display(iClient, 20);
}

public int MenuHandler_Abort(Menu hMenu, MenuAction eAction, int iClient, int iItem) {
	if (eAction == MenuAction_End) delete hMenu;
	else if (eAction == MenuAction_Select && iItem == 1 && g_eGame == GS_Live) {
		PrintToChatAll("\x04[RTS]\x01 %N aborted the game.", iClient);
		g_iSetSeries = 1;
		Match_EndGame(0, "aborted by the host");
	}
	return 0;
}

public Action cmdDebugLobby(int iClient, int iArgs) {
	iClient = ResolveClient(iClient);
	if (!HasRTSAccess(iClient)) return Plugin_Handled;
	char sCmd[16], sArg[32], sArg2[32];
	GetCmdArg(1, sCmd, sizeof(sCmd));
	GetCmdArg(2, sArg, sizeof(sArg));
	GetCmdArg(3, sArg2, sizeof(sArg2));
	if (StrEqual(sCmd, "start")) Lobby_StartCountdown(iClient);
	else if (StrEqual(sCmd, "forcestart")) { if (g_eGame != GS_Live) { LogMessage("[RTS] state: forcestart by %L", iClient); Lobby_BeginMatch(); } }
	else if (StrEqual(sCmd, "lobby")) { g_iSeriesGame = 0; g_iSeriesWins[2] = g_iSeriesWins[3] = 0; Lobby_Enter(true); }
	else if (StrEqual(sCmd, "win")) {
		int w = StrEqual(sArg, "draw") ? 0 : TeamFromName(sArg);
		if (g_eGame == GS_Live) Match_EndGame(w, sArg2[0] ? sArg2 : "forced (debug)");
	}
	else if (StrEqual(sCmd, "timeup")) { if (g_eGame == GS_Live) g_fMatchEnd = GetGameTime(); }
	else if (StrEqual(sCmd, "next")) {
		if (g_eGame == GS_Ended) {
			bool bOver = g_iSetSeries <= 1 || g_iSeriesWins[2] >= Lobby_SeriesNeeded() || g_iSeriesWins[3] >= Lobby_SeriesNeeded() || g_iSeriesGame >= g_iSetSeries;
			DataPack hP = new DataPack(); hP.WriteCell(g_iEndGen); hP.WriteCell(bOver); Timer_AfterGame(null, hP); delete hP;
		}
	}
	else if (StrEqual(sCmd, "set")) {
		if (StrEqual(sArg, "mode")) g_eMode = view_as<GameMode>(StringToInt(sArg2) % 4);
		else if (StrEqual(sArg, "pool")) g_iSetPool = StringToInt(sArg2);
		else if (StrEqual(sArg, "time")) g_iSetMinutes = StringToInt(sArg2);
		else if (StrEqual(sArg, "bots")) g_iSetBots = StringToInt(sArg2);
		else if (StrEqual(sArg, "diff")) g_iSetDifficulty = StringToInt(sArg2) % 4;
		else if (StrEqual(sArg, "series")) { g_iSetSeries = StringToInt(sArg2); g_iSeriesGame = 0; g_iSeriesWins[2] = g_iSeriesWins[3] = 0; }
		else if (StrEqual(sArg, "target")) g_iSetIntelTarget = StringToInt(sArg2);
		else if (StrEqual(sArg, "earned")) { g_iIntelEarned[CS_TEAM_T] = StringToInt(sArg2); }
		else if (StrEqual(sArg, "pool_t")) { g_iUnitPool[CS_TEAM_T] = StringToInt(sArg2); }
	}
	static const char sStates[][] = {"LOBBY", "COUNTDOWN", "LIVE", "ENDED"};
	ReplyToCommand(iClient, "[RTS] lobby state=%s mode=%s pool=%d time=%d bots=%d diff=%d series=%d (game %d, T %d : %d CT) target=%d earned T=%d CT=%d timeleft=%.0f",
		sStates[g_eGame], g_sModeNames[g_eMode], g_iSetPool, g_iSetMinutes, g_iSetBots, g_iSetDifficulty, g_iSetSeries, g_iSeriesGame,
		g_iSeriesWins[CS_TEAM_T], g_iSeriesWins[CS_TEAM_CT], g_iSetIntelTarget, g_iIntelEarned[CS_TEAM_T], g_iIntelEarned[CS_TEAM_CT],
		g_eGame == GS_Live && g_fMatchEnd > 0.0 ? g_fMatchEnd - GetGameTime() : 0.0);
	return Plugin_Handled;
}
