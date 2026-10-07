// css_rts/selftest_wheel.sp -- v0.5.4: radial wheel selftest (instant, both teams). Drives the wheel
// on a bot commander through the same code paths the mouse uses (Wheel_Update via Wheel_DebugTick):
// open -> sprites, hover -> tile, pick Research -> page 1, buy a research, locked tile refused,
// close -> sprites removed.

void SelfTestWheel_Init() {
	RegConsoleCmd("sm_rts_selftest_wheel", cmdSelfTestWheel, "Radial wheel selftest (instant, needs a live match with bots)");
}

int WT_Sprites(int c) {
	int n;
	for (int k=0; k<WHEEL_SLOTS; k++) if (EntRefToEntIndex(g_iWheelEnt[c][k]) > 0) n++;
	return n;
}

void WT_Hover(int c, int i) {
	float fS[2];
	Wheel_ScreenPos(c, g_iWheelPage[c], i, fS);
	g_eCommander[c].fMouse[0] = fS[0];
	g_eCommander[c].fMouse[1] = fS[1];
	Wheel_DebugTick(c);
}

public Action cmdSelfTestWheel(int iClient, int iArgs) {
	iClient = ResolveClient(iClient);
	if (!HasRTSAccess(iClient)) return Plugin_Handled;
	if (g_eGame != GS_Live) {
		if (InLobby()) Lobby_BeginMatch();
		PrintToServer("[RTS-SELFTEST] scenario skipped: not live (started the match) - run again in ~20 s");
		return Plugin_Handled;
	}
	g_iSTPass = g_iSTFail = 0;
	PrintToServer("[RTS-SELFTEST] scenario wheel (T + CT)");
	bool bOldWheel = g_hCvarWheel.BoolValue;
	g_hCvarWheel.BoolValue = true;
	Unlocks_Reset();
	for (int t=CS_TEAM_T; t<=CS_TEAM_CT; t++) {
		char sT[4], sWhy[64]; TeamShortName(t, sT, sizeof(sT));
		int iOld = GetTeamCommander(t);
		if (iOld) { if (g_eCommander[iOld].bEnabled) ResetClient(iOld); ReleaseCommander(iOld, false); }
		int c = SS_FindBot(t);
		ST(c > 0, "wheel_bot", "%s bot %d", sT, c);
		if (!c) continue;
		ST(AssignCommander(c, false) && EnterCommanderView(c, true, sWhy, sizeof(sWhy)) && Wheel_Enabled(c), "wheel_commander_view", "%s %s", sT, sWhy);
		g_iIntel[t] = 5000;
		// main page
		Wheel_Open(c, 0);
		Wheel_DebugTick(c);
		int iMain = WT_Sprites(c);
		ST(Wheel_IsOpen(c) && g_iWheelPage[c] == 0 && iMain >= Wheel_Count(0), "wheel_open_main", "%s sprites %d (tiles %d)", sT, iMain, Wheel_Count(0));
		ST(g_iWheelHover[c] == -1, "wheel_centre_no_hover", "%s hover %d", sT, g_iWheelHover[c]);
		WT_Hover(c, 1);
		ST(g_iWheelHover[c] == 1, "wheel_hover_research", "%s hover %d", sT, g_iWheelHover[c]);
		// pick Research -> page 1
		Wheel_Pick(c, 0, 1);
		Wheel_DebugTick(c);
		int iRes = WT_Sprites(c);
		ST(g_iWheelPage[c] == 1 && iRes >= Wheel_Count(1), "wheel_page_research", "%s page %d sprites %d (tiles %d)", sT, g_iWheelPage[c], iRes, Wheel_Count(1));
		// buyable + locked tiles
		int iBuy = -1, iLocked = -1;
		for (int i=0; i<Wheel_Count(1); i++) {
			int st = Wheel_State(c, 1, i);
			if (st == 'n' && iBuy == -1) iBuy = i;
			if (st == 'd' && iLocked == -1 && Wheel_Unlock(i) != -1) iLocked = i;
		}
		ST(iBuy != -1 && iLocked != -1, "wheel_states", "%s buy %d locked %d", sT, iBuy, iLocked);
		if (iBuy != -1) {
			int u = Wheel_Unlock(iBuy), iIntel = g_iIntel[t];
			WT_Hover(c, iBuy);
			ST(g_iWheelHover[c] == iBuy, "wheel_hover_tile", "%s hover %d want %d", sT, g_iWheelHover[c], iBuy);
			Wheel_Pick(c, 1, iBuy);
			ST(g_bUnlocked[t][u] && g_iIntel[t] == iIntel - Unlock_Cost(u) && Wheel_State(c, 1, iBuy) == 'o', "wheel_buy_research", "%s %s Intel %d -> %d", sT, g_sWheelResearch[iBuy], iIntel, g_iIntel[t]);
			ST(Wheel_IsOpen(c) && g_iWheelPage[c] == 1, "wheel_stays_open_after_buy", "%s", sT);
		}
		if (iLocked != -1) {
			int u = Wheel_Unlock(iLocked), iIntel = g_iIntel[t];
			Wheel_Pick(c, 1, iLocked);
			ST(!g_bUnlocked[t][u] && g_iIntel[t] == iIntel, "wheel_locked_refused", "%s %s Intel %d", sT, g_sWheelResearch[iLocked], g_iIntel[t]);
		}
		Wheel_Close(c);
		ST(!Wheel_IsOpen(c) && WT_Sprites(c) == 0, "wheel_close_removes_sprites", "%s sprites %d", sT, WT_Sprites(c));
		// cleanup
		if (g_eCommander[c].bEnabled) ResetClient(c);
		ReleaseCommander(c, false);
		g_iIntel[t] = 5000;
	}
	Unlocks_Reset();
	g_hCvarWheel.BoolValue = bOldWheel;
	PrintToServer("[RTS-SELFTEST] DONE: %d passed, %d failed", g_iSTPass, g_iSTFail);
	return Plugin_Handled;
}
