// css_rts/selftest_lobby.sp -- headless lobby/series selftest: sm_rts_selftest_lobby (~90 s)
// Uses the shared ST() reporter from selftest.sp. Step machine on a 1 s timer.

int g_iLT;          // current step
float g_fLTNext;    // earliest time for the next step
int g_iLTOldCountdown;
int g_iLTA = CS_TEAM_CT, g_iLTB = CS_TEAM_T;   // "mirror" arg swaps every team in the scenario
char g_sLTName[48];

// test name with the team suffix of the given team (attrition_win + CT -> attrition_win_ct)
void LTName(const char[] sBase, int t) {
	FormatEx(g_sLTName, sizeof(g_sLTName), "%s_%s", sBase, t == CS_TEAM_CT ? "ct" : "t");
}

void LobbyTest_Init() {
	RegConsoleCmd("sm_rts_selftest_lobby", cmdSelfTestLobby, "Headless lobby / win condition / series selftest (~90 s); arg mirror = swap T/CT");
}

public Action cmdSelfTestLobby(int iClient, int iArgs) {
	if (!HasRTSAccess(ResolveClient(iClient))) return Plugin_Handled;
	g_iSTPass = g_iSTFail = 0;
	char sArg[16]; GetCmdArg(1, sArg, sizeof(sArg));
	bool bMirror = StrEqual(sArg, "mirror", false);
	g_iLTA = bMirror ? CS_TEAM_T : CS_TEAM_CT;
	g_iLTB = bMirror ? CS_TEAM_CT : CS_TEAM_T;
	g_iLT = 0;
	g_fLTNext = 0.0;
	g_iLTOldCountdown = g_hCvarCountdown.IntValue;
	g_hCvarCountdown.IntValue = 2;
	PrintToServer("[RTS-SELFTEST] lobby scenario%s (~90s)", bMirror ? " MIRRORED (T/CT swapped)" : "");
	CreateTimer(1.0, Timer_LobbyTest, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	return Plugin_Handled;
}

int LT_CountBots() {
	int n;
	for (int i=1; i<=MaxClients; i++) if (IsClientInGame(i) && IsFakeClient(i) && !IsClientSourceTV(i)) n++;
	return n;
}

void LT_KillTeam(int t) {
	for (int i=1; i<=MaxClients; i++) {
		if (IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == t && GetTeamCommander(t) != i) ForcePlayerSuicide(i);
	}
}

void LT_After(bool bOver) {
	DataPack hP = new DataPack();
	hP.WriteCell(g_iEndGen);
	hP.WriteCell(bOver);
	Timer_AfterGame(null, hP);
	delete hP;
}

void LT_Wait(float f) { g_fLTNext = GetGameTime() + f; }

void LT_Finish() {
	g_hCvarCountdown.IntValue = g_iLTOldCountdown;
	g_iSetSeries = 1;
	g_eMode = Mode_Attrition;
	g_iSetPool = 200; g_iSetMinutes = 40; g_iSetBots = 5;
	PrintToServer("[RTS-SELFTEST] DONE: %d passed, %d failed", g_iSTPass, g_iSTFail);
	LogMessage("[SELFTEST-LOBBY] DONE: %d passed, %d failed", g_iSTPass, g_iSTFail);
}

public Action Timer_LobbyTest(Handle h) {
	float fNow = GetGameTime();
	if (fNow < g_fLTNext) return Plugin_Continue;
	switch (g_iLT) {
		case 0: {
			g_iSetSeries = 3; g_iSeriesGame = 0; g_iSeriesWins[2] = g_iSeriesWins[3] = 0;
			g_eMode = Mode_Attrition; g_iSetPool = 100; g_iSetMinutes = 30; g_iSetBots = 3;
			Lobby_Enter(false);
			LT_Wait(3.0);
		}
		case 1: {
			ST(g_eGame == GS_Lobby && InWarmup(), "lobby_state");
			ST(LT_CountBots() == 0, "lobby_no_bots", "%d bots", LT_CountBots());
			Lobby_StartCountdown(0);
			ST(g_eGame == GS_Countdown, "countdown_started");
			LT_Wait(3.5);
		}
		case 2: {
			ST(g_eGame == GS_Live && !InWarmup(), "match_live");
			ST(g_iUnitPool[g_iLTB] == 100 && g_iUnitPool[g_iLTA] == 100, "pool_setting_applied", "%d/%d", g_iUnitPool[g_iLTB], g_iUnitPool[g_iLTA]);
			ST(FloatAbs(g_fMatchEnd - g_fMatchStart - 1800.0) < 1.0, "time_limit_applied", "%.0f", g_fMatchEnd - g_fMatchStart);
			LT_Wait(11.0);
		}
		case 3: {
			ST(LT_CountBots() >= 4, "bots_spawned_after_start", "%d bots", LT_CountBots());
			g_iUnitPool[g_iLTB] = 0;
			LT_KillTeam(g_iLTB);
			LT_Wait(2.5);
		}
		case 4: {
			LTName("attrition_win", g_iLTA);
			ST(g_eGame == GS_Ended && g_iSeriesWins[g_iLTA] == 1 && g_iSeriesGame == 1, g_sLTName, "state %d wins %d:%d", g_eGame, g_iSeriesWins[g_iLTB], g_iSeriesWins[g_iLTA]);
			LT_After(false);
			ST(g_eGame == GS_Countdown, "series_next_game_countdown");
			LT_Wait(3.5);
		}
		case 5: {
			ST(g_eGame == GS_Live && g_iUnitPool[g_iLTB] == 100, "game2_live_pools_reset", "pool T %d", g_iUnitPool[g_iLTB]);
			g_iUnitPool[g_iLTB] = 10;
			g_fMatchEnd = fNow;
			LT_Wait(2.5);
		}
		case 6: {
			LTName("timeup_tiebreak_units", g_iLTA);
			ST(g_eGame == GS_Ended && g_iSeriesWins[g_iLTA] == 2, g_sLTName, "wins %d:%d", g_iSeriesWins[g_iLTB], g_iSeriesWins[g_iLTA]);
			LT_After(true);
			ST(g_eGame == GS_Lobby && g_iSeriesGame == 0 && g_iSeriesWins[g_iLTA] == 0, "series_over_back_to_lobby");
			g_iSetSeries = 1; g_eMode = Mode_IntelRace; g_iSetIntelTarget = 15000;
			Lobby_StartCountdown(0);
			LT_Wait(3.5);
		}
		case 7: {
			ST(g_eGame == GS_Live && g_iIntelEarned[g_iLTB] < 15000, "intel_race_live");
			g_iIntelEarned[g_iLTB] = 15000;
			LT_Wait(2.5);
		}
		case 8: {
			LTName("intel_race_win", g_iLTB);
			ST(g_eGame == GS_Ended && g_iSeriesWins[g_iLTB] == 1, g_sLTName, "state %d wins %d:%d", g_eGame, g_iSeriesWins[g_iLTB], g_iSeriesWins[g_iLTA]);
			LT_After(true);
			g_eMode = Mode_Workers;
			Lobby_StartCountdown(0);
			LT_Wait(7.0);
		}
		case 9: {
			ST(g_eGame == GS_Live && Npc_Count(Npc_Worker, g_iLTB) == g_hCvarWEWorkers.IntValue && Npc_Count(Npc_Worker, g_iLTA) == g_hCvarWEWorkers.IntValue,
				"we_start_workers", "T %d CT %d", Npc_Count(Npc_Worker, g_iLTB), Npc_Count(Npc_Worker, g_iLTA));
			for (int i=0; i<MAX_NPCS; i++) if (g_eNpc[i].bUsed && g_eNpc[i].iTeam == g_iLTB && g_eNpc[i].eState != NS_Dead) Npc_Kill(i, 0);
			LT_Wait(2.5);
		}
		case 10: {
			LTName("workers_elim_win", g_iLTA);
			ST(g_eGame == GS_Ended && g_iSeriesWins[g_iLTA] == 1, g_sLTName, "state %d wins %d:%d", g_eGame, g_iSeriesWins[g_iLTB], g_iSeriesWins[g_iLTA]);
			LT_After(true);
			ST(g_eGame == GS_Lobby, "back_to_lobby");
			LT_Finish();
			return Plugin_Stop;
		}
	}
	g_iLT++;
	return Plugin_Continue;
}
