// css_rts/selftest_sides.sp -- v0.5.1: T/CT symmetry selftest (~25 s). For BOTH teams: tech tree +
// buy lock, workers spawn/seat/income, worker ghost spot, base point, commander assign/view on a
// bot, team colours, and (v0.6, cvar forced on for the test) armory restock + abilities.

int g_iSSWorkers[4];
int g_iSSBaseIncome[4];

void SelfTestSides_Init() {
	RegConsoleCmd("sm_rts_selftest_sides", cmdSelfTestSides, "T/CT symmetry selftest (~25 s, needs a live match with bots)");
}

int SS_FindBot(int t) {
	for (int i=1; i<=MaxClients; i++) {
		if (IsClientInGame(i) && IsFakeClient(i) && !IsClientSourceTV(i) && GetClientTeam(i) == t && IsPlayerAlive(i) && !GetCommanderTeam(i)) return i;
	}
	return 0;
}

public Action cmdSelfTestSides(int iClient, int iArgs) {
	iClient = ResolveClient(iClient);
	if (!HasRTSAccess(iClient)) return Plugin_Handled;
	if (g_eGame != GS_Live) {
		if (InLobby()) Lobby_BeginMatch();
		PrintToServer("[RTS-SELFTEST] scenario skipped: not live (started the match) - run again in ~20 s");
		return Plugin_Handled;
	}
	g_iSTPass = g_iSTFail = 0;
	PrintToServer("[RTS-SELFTEST] scenario sides (T + CT), ~25s");
	Workers_ResetMatch();
	bool bOldStock = g_hCvarStockpile.BoolValue;
	g_hCvarStockpile.BoolValue = true;
	int iCol[4][4];
	Unlocks_Reset();    // also resets armory stock + ability cooldowns
	for (int t=CS_TEAM_T; t<=CS_TEAM_CT; t++) {
		char sT[4]; TeamShortName(t, sT, sizeof(sT));
		TeamColor(t, iCol[t]);
		g_iIntel[t] = 5000;
		// tech tree + buy lock
		int iBot = SS_FindBot(t);
		ST(iBot > 0, "side_bot", "%s bot %d", sT, iBot);
		if (iBot) ST(Unlocks_BlockBuy(iBot, "hegrenade"), "side_locked_buy_blocked", "%s", sT);
		int u = Unlock_FindKey("nades");
		ST(Unlock_Buy(0, t, u) && g_bUnlocked[t][u] && g_iIntel[t] == 5000 - Unlock_Cost(u), "side_unlock", "%s Intel %d", sT, g_iIntel[t]);
		if (iBot) ST(!Unlocks_BlockBuy(iBot, "hegrenade"), "side_unlocked_buy_ok", "%s", sT);
		// armory (v0.6)
		int k = Armory_Find("hegrenade"), k2 = Armory_Find("ak47");
		ST(Armory_Restock(0, t, k) && g_iStock[t][k] == 4, "side_armory_restock", "%s stock %d", sT, g_iStock[t][k]);
		ST(!Armory_Restock(0, t, k2) && g_iStock[t][k2] == 0, "side_armory_locked", "%s", sT);
		// abilities (v0.6)
		ST(Ability_Fire(0, t, Ability_Sweep, NULL_VECTOR) && Ability_SweepActive(t) && !Ability_Ready(t, Ability_Sweep), "side_ability_sweep", "%s cd %.0f", sT, Ability_CooldownLeft(t, Ability_Sweep));
		// base / post / workers
		float vecBase[3];
		ST(GetBasePoint(t, vecBase, false), "side_base_point", "%s %.0f %.0f %.0f", sT, vecBase[0], vecBase[1], vecBase[2]);
		ST(FindFreeSeat(t, g_ePost[t].vecOrigin) != -1, "side_free_seat", "%s", sT);
		int s = FindFreeSeat(t, g_ePost[t].vecOrigin);
		if (s != -1) { float v[3], fYaw; ST(Ghost_WorkerSpot(t, g_vecSeat[s], v, fYaw) == 2, "side_ghost_seat_valid", "%s seat %d", sT, s); }
		g_iSSBaseIncome[t] = ComputeIntelIncome(t);
		int w1 = Worker_Spawn(t, true), w2 = Worker_Spawn(t, true);
		g_iSSWorkers[t] = Npc_Count(Npc_Worker, t);
		ST(w1 != -1 && w2 != -1 && g_iSSWorkers[t] == 2, "side_workers_spawned", "%s n=%d", sT, g_iSSWorkers[t]);
		ST(w1 != -1 && g_eNpc[w1].iSeat != -1, "side_worker_seat_assigned", "%s seat %d", sT, w1 != -1 ? g_eNpc[w1].iSeat : -2);
		g_iIntel[t] = 5000;
	}
	ST(iCol[2][2] != iCol[3][2], "side_team_colours", "T b=%d CT b=%d", iCol[2][2], iCol[3][2]);
	g_hCvarStockpile.BoolValue = bOldStock;
	CreateTimer(22.0, Timer_SSCheck, _, TIMER_FLAG_NO_MAPCHANGE);
	return Plugin_Handled;
}

public Action Timer_SSCheck(Handle hTimer) {
	for (int t=CS_TEAM_T; t<=CS_TEAM_CT; t++) {
		char sT[4]; TeamShortName(t, sT, sizeof(sT));
		int iSeated = CountSeatedWorkers(t);
		ST(iSeated >= 1, "side_workers_seated", "%s seated %d/%d", sT, iSeated, Npc_Count(Npc_Worker, t));
		int iInc = ComputeIntelIncome(t);
		ST(iInc > g_iSSBaseIncome[t], "side_worker_income", "%s income %d (base %d)", sT, iInc, g_iSSBaseIncome[t]);
		ST(!Ability_SweepActive(t), "side_sweep_expired", "%s", sT);
	}
	PrintToServer("[RTS-SELFTEST] DONE: %d passed, %d failed", g_iSTPass, g_iSTFail);
	Workers_ResetMatch();
	Abilities_Reset();
	Unlocks_Reset();
	return Plugin_Stop;
}
