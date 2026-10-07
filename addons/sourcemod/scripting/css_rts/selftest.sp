// css_rts/selftest.sp -- sm_rts_selftest [t|ct]: headless checks of M1 (config, terminals, role, view, Intel, blocking)
int g_iSTOldWorkers[4];

int g_iSTPass, g_iSTFail, g_iSTBot, g_iSTTeam, g_iSTIntel, g_iSTBlocked, g_iSTMoney, g_iSTHealth;
int g_iSTOldCmdrUserId;
int g_iSTOldZombie;
float g_fSTOldViewDelay;

void SelfTest_Register() {
	RegConsoleCmd("sm_rts_selftest", cmdSelfTest, "Headless M1 self test: [t|ct] (uses a bot on that team)");
}

void ST(bool bOk, const char[] sName, const char[] sFmt="", any ...) {
	char sDetail[192];
	VFormat(sDetail, sizeof(sDetail), sFmt, 4);
	if (bOk) g_iSTPass++; else g_iSTFail++;
	PrintToServer("[RTS-SELFTEST] %s %s %s", bOk ? "PASS" : "FAIL", sName, sDetail);
	LogMessage("[SELFTEST] %s %s %s", bOk ? "PASS" : "FAIL", sName, sDetail);
}

public Action cmdSelfTest(int iClient, int iArgs) {
	iClient = ResolveClient(iClient);
	if (!HasRTSAccess(iClient)) return Plugin_Handled;
	if (g_bSelfTestRunning) { ReplyToCommand(iClient, "[RTS] selftest already running"); return Plugin_Handled; }
	if (g_eGame != GS_Live) {
		if (InLobby()) Lobby_BeginMatch();
		ReplyToCommand(iClient, "[RTS] selftest needs a live match with bots: match started, run sm_rts_selftest again in ~20 s");
		PrintToServer("[RTS-SELFTEST] scenario skipped: not live (started the match)");
		return Plugin_Handled;
	}
	g_iSTPass = g_iSTFail = 0;
	g_iSTTeam = CS_TEAM_CT;
	if (iArgs >= 1) { char s[8]; GetCmdArg(1, s, sizeof(s)); if (TeamFromName(s)) g_iSTTeam = TeamFromName(s); }

	// --- static checks ---
	char sMap[64];
	GetMapConfigName(sMap, sizeof(sMap));
	ST(g_hSDKBotMoveTo != null, "gamedata", "CCSBot::MoveTo SDKCall");
	ST(g_bMapConfigLoaded, "map_config", "%s", g_sMapConfigPath);
	ST(g_vecCamMins[0] < g_vecCamMaxs[0] && g_vecCamMins[1] < g_vecCamMaxs[1] && g_vecCamMins[2] < g_vecCamMaxs[2], "camera_bounds");
	for (int t=CS_TEAM_T; t<=CS_TEAM_CT; t++) {
		char sT[4]; TeamShortName(t, sT, sizeof(sT));
		ST(g_ePost[t].bValid, "post_defined", "%s (%s)", sT, g_ePost[t].bFromConfig ? "config" : "auto");
		ST(FileExists(g_ePost[t].sModel, true), "terminal_model_file", "%s", g_ePost[t].sModel);
		char sWhy[64]; float f[3];
		ST(ValidatePostSpot(t, g_ePost[t].vecOrigin, g_ePost[t].vecAngles[1], f, sWhy, sizeof(sWhy)), "post_spot_valid", "%s: %s", sT, sWhy);
		int iEnt = GetTerminal(t);
		ST(iEnt != -1, "terminal_spawned", "%s ent=%d", sT, iEnt);
		if (iEnt != -1) {
			char sModel[PLATFORM_MAX_PATH], sCls[64];
			GetEntPropString(iEnt, Prop_Data, "m_ModelName", sModel, sizeof(sModel));
			GetEntityClassname(iEnt, sCls, sizeof(sCls));
			float v[3]; GetEntPropVector(iEnt, Prop_Data, "m_vecAbsOrigin", v);
			ST(StrEqual(sModel, g_ePost[t].sModel) && StrContains(sCls, "prop_dynamic") == 0, "terminal_entity", "%s %s at %.0f", sCls, sModel, GetVectorDistance(v, g_ePost[t].vecOrigin));
		}
	}

	// --- scenario with a bot ---
	g_iSTBot = 0;
	for (int i=1; i<=MaxClients; i++) {
		if (IsClientInGame(i) && IsFakeClient(i) && !IsClientSourceTV(i) && IsPlayerAlive(i) && GetClientTeam(i) == g_iSTTeam) { g_iSTBot = i; break; }
	}
	if (!g_iSTBot) {
		ST(false, "scenario", "no live bot on team %d (add bots / wait for spawn)", g_iSTTeam);
		SelfTestSummary();
		return Plugin_Handled;
	}
	g_bSelfTestRunning = true;
	// commander income checks run without workers (worker tests: sm_rts_selftest_workers)
	for (int t=0; t<4; t++) { g_iSTOldWorkers[t] = g_iWorkersOwned[t]; g_iWorkersOwned[t] = 0; }
	Npc_RemoveAll();
	// keep other bots from killing the test bot mid-scenario
	ConVar hZombie = FindConVar("bot_zombie");
	if (hZombie != null) { g_iSTOldZombie = hZombie.IntValue; hZombie.IntValue = 1; }
	g_fSTOldViewDelay = g_hCvarViewDelay.FloatValue;
	g_hCvarViewDelay.FloatValue = 0.0;
	g_iSTOldCmdrUserId = g_iCommanderUserId[g_iSTTeam];
	int iCur = GetTeamCommander(g_iSTTeam);
	if (iCur) ReleaseCommander(iCur, false);

	// Stand the bot in front of its terminal, facing it, then press USE (auto-assign + enter view)
	float vecStand[3], vecAng[3];
	GetStandSpot(g_ePost[g_iSTTeam].vecOrigin, g_ePost[g_iSTTeam].vecAngles[1], vecStand);
	vecStand[2] += 4.0;
	vecAng[0] = 30.0; vecAng[1] = g_ePost[g_iSTTeam].vecAngles[1] + 180.0;
	TeleportEntity(g_iSTBot, vecStand, vecAng, view_as<float>({0.0, 0.0, 0.0}));
	g_fViewToggleTime[g_iSTBot] = 0.0;
	CreateTimer(0.3, Timer_ST1, _, TIMER_FLAG_NO_MAPCHANGE);
	PrintToServer("[RTS-SELFTEST] scenario with bot %N (team %d), ~%.0fs", g_iSTBot, g_iSTTeam, g_hCvarIntelTick.FloatValue*4.0 + 3.0);
	return Plugin_Handled;
}

bool STBotOk() {
	if (IsClientInGame(g_iSTBot) && IsPlayerAlive(g_iSTBot)) return true;
	ST(false, "scenario", "bot died / left mid-test");
	SelfTestEnd();
	return false;
}

public Action Timer_ST1(Handle h) {
	if (!STBotOk()) return Plugin_Stop;
	float vecAng[3]; vecAng[0] = 30.0; vecAng[1] = g_ePost[g_iSTTeam].vecAngles[1] + 180.0;
	TeleportEntity(g_iSTBot, NULL_VECTOR, vecAng, NULL_VECTOR);
	int iAimed = GetAimedTerminal(g_iSTBot);
	ST(iAimed == g_iSTTeam, "use_detects_terminal", "aimed team %d", iAimed);
	SimulateUse(g_iSTBot);
	ST(GetTeamCommander(g_iSTTeam) == g_iSTBot, "auto_assign_on_use", "commander=%d", GetTeamCommander(g_iSTTeam));
	ST(g_bPostView[g_iSTBot] && g_eCommander[g_iSTBot].bEnabled, "enter_view_on_use");
	ST((GetEntityFlags(g_iSTBot) & FL_FROZEN) != 0, "body_frozen");
	ST(GetCommanderState(g_iSTTeam) == CmdState_InView && ComputeIntelIncome(g_iSTTeam) - g_hCvarIntelBase.IntValue == g_hCvarIntelPerTick.IntValue, "income_in_view", "%d", ComputeIntelIncome(g_iSTTeam));

	// buy/drop blocking
	g_iSTBlocked = g_iBlockedCmds;
	g_iSTMoney = 16000;
	SetEntProp(g_iSTBot, Prop_Send, "m_iAccount", g_iSTMoney);
	FakeClientCommand(g_iSTBot, "buy hegrenade");
	FakeClientCommand(g_iSTBot, "buymenu");
	FakeClientCommand(g_iSTBot, "drop");
	ST(g_iBlockedCmds - g_iSTBlocked >= 3, "buy_drop_blocked", "%d blocked", g_iBlockedCmds - g_iSTBlocked);
	ST(GetEntProp(g_iSTBot, Prop_Send, "m_iAccount") == g_iSTMoney, "money_unchanged");

	g_iSTIntel = g_iIntel[g_iSTTeam];
	CreateTimer(g_hCvarIntelTick.FloatValue * 2.0 + 0.2, Timer_ST2, _, TIMER_FLAG_NO_MAPCHANGE);
	return Plugin_Stop;
}

public Action Timer_ST2(Handle h) {
	if (!STBotOk()) return Plugin_Stop;
	int iDelta = g_iIntel[g_iSTTeam] - g_iSTIntel;
	int iPer = g_hCvarIntelPerTick.IntValue + g_hCvarIntelBase.IntValue;
	ST(g_bPostView[g_iSTBot], "still_in_view", "last exit reason: %s", g_sLastExitReason[g_iSTBot]);
	ST(iDelta >= iPer && iPer > 0 && iDelta % iPer == 0, "intel_ticks_in_view", "+%d over 2 ticks (per tick %d)", iDelta, iPer);

	// damage exits the view
	g_iSTHealth = GetClientHealth(g_iSTBot);
	SDKHooks_TakeDamage(g_iSTBot, 0, 0, 1.0, DMG_GENERIC);
	CreateTimer(0.3, Timer_ST3, _, TIMER_FLAG_NO_MAPCHANGE);
	return Plugin_Stop;
}

public Action Timer_ST3(Handle h) {
	if (!STBotOk()) return Plugin_Stop;
	if (g_hCvarBodyless.BoolValue) {
		// Bodyless commander: untouchable, hidden, stays in view; leaving the role restores the body
		ST(GetClientHealth(g_iSTBot) == g_iSTHealth, "bodyless_godmode", "hp %d -> %d", g_iSTHealth, GetClientHealth(g_iSTBot));
		ST(g_bPostView[g_iSTBot] && g_eCommander[g_iSTBot].bEnabled, "bodyless_stays_in_view");
		ST(g_bBodyHidden[g_iSTBot] && GetEntityRenderMode(g_iSTBot) == RENDER_NONE && GetEntProp(g_iSTBot, Prop_Data, "m_takedamage") == 0, "body_hidden");
		float vecPos[3]; GetClientAbsOrigin(g_iSTBot, vecPos);
		ST(vecPos[2] < g_ePost[g_iSTTeam].vecOrigin[2] - 1000.0, "body_parked", "z %.0f", vecPos[2]);
		ST(GetPlayerWeaponSlot(g_iSTBot, 0) == -1 && GetPlayerWeaponSlot(g_iSTBot, 1) == -1 && GetPlayerWeaponSlot(g_iSTBot, 2) == -1, "no_weapons");
		ReleaseCommander(g_iSTBot, false);
		ST(!g_bBodyHidden[g_iSTBot] && GetEntityRenderMode(g_iSTBot) == RENDER_NORMAL && GetEntProp(g_iSTBot, Prop_Data, "m_takedamage") == 2 && !g_eCommander[g_iSTBot].bEnabled, "release_restores_body");
		ST(GetPlayerWeaponSlot(g_iSTBot, 1) != -1, "release_gives_pistol");
		ST(ComputeIntelIncome(g_iSTTeam) == g_hCvarIntelBase.IntValue, "no_income_out_of_view", "%d", ComputeIntelIncome(g_iSTTeam));
		AssignCommander(g_iSTBot, false);
		ST(ComputeIntelIncome(g_iSTTeam) == g_hCvarIntelBase.IntValue, "no_income_alive_not_in_view", "%d", ComputeIntelIncome(g_iSTTeam));
		g_iSTIntel = g_iIntel[g_iSTTeam];
		CreateTimer(g_hCvarIntelTick.FloatValue * 1.5, Timer_ST4, _, TIMER_FLAG_NO_MAPCHANGE);
		return Plugin_Stop;
	}
	ST(GetClientHealth(g_iSTBot) < g_iSTHealth, "commander_body_damageable", "hp %d -> %d", g_iSTHealth, GetClientHealth(g_iSTBot));
	ST(!g_bPostView[g_iSTBot] && !g_eCommander[g_iSTBot].bEnabled, "damage_exits_view");
	ST((GetEntityFlags(g_iSTBot) & FL_FROZEN) == 0, "body_unfrozen");
	ST(ComputeIntelIncome(g_iSTTeam) == g_hCvarIntelBase.IntValue, "no_income_out_of_view", "%d", ComputeIntelIncome(g_iSTTeam));
	g_iSTIntel = g_iIntel[g_iSTTeam];
	CreateTimer(g_hCvarIntelTick.FloatValue * 1.5, Timer_ST4, _, TIMER_FLAG_NO_MAPCHANGE);
	return Plugin_Stop;
}

public Action Timer_ST4(Handle h) {
	if (!STBotOk()) return Plugin_Stop;
	int iB = g_hCvarIntelBase.IntValue;
	int iD = g_iIntel[g_iSTTeam] - g_iSTIntel;
	ST(iB > 0 ? (iD % iB == 0) : iD == 0, "intel_only_base_out_of_view", "delta %d (base %d)", iD, iB);
	// USE toggles in and out (re-aim at the terminal first; idle bots look around)
	if (!g_hCvarBodyless.BoolValue) {
		float vecAng[3]; vecAng[0] = 30.0; vecAng[1] = g_ePost[g_iSTTeam].vecAngles[1] + 180.0;
		TeleportEntity(g_iSTBot, NULL_VECTOR, vecAng, NULL_VECTOR);
		g_fViewToggleTime[g_iSTBot] = 0.0;
		SimulateUse(g_iSTBot);
		bool bIn = g_bPostView[g_iSTBot];
		g_fViewToggleTime[g_iSTBot] = 0.0;
		SimulateUse(g_iSTBot);
		ST(bIn && !g_bPostView[g_iSTBot], "use_toggles_view");
	}
	// buy allowed again outside the view
	g_iSTBlocked = g_iBlockedCmds;
	FakeClientCommand(g_iSTBot, "buymenu");
	ST(g_iBlockedCmds == g_iSTBlocked, "buy_allowed_outside_view");
	// death exits the view
	char sWhy[64];
	EnterCommanderView(g_iSTBot, true, sWhy, sizeof(sWhy));
	ForcePlayerSuicide(g_iSTBot);
	CreateTimer(0.3, Timer_ST5, _, TIMER_FLAG_NO_MAPCHANGE);
	return Plugin_Stop;
}

public Action Timer_ST5(Handle h) {
	if (!IsClientInGame(g_iSTBot)) { SelfTestEnd(); return Plugin_Stop; }
	ST(!g_bPostView[g_iSTBot] && !g_eCommander[g_iSTBot].bEnabled, "death_exits_view");
	ST(GetTeamCommander(g_iSTTeam) == g_iSTBot && GetCommanderState(g_iSTTeam) == CmdState_Dead, "dead_commander_keeps_role");
	ReleaseCommander(g_iSTBot, false);
	ST(GetTeamCommander(g_iSTTeam) == 0, "uncommander_releases");
	// team change releases the role
	AssignCommander(g_iSTBot, false);
	ChangeClientTeam(g_iSTBot, g_iSTTeam == CS_TEAM_CT ? CS_TEAM_T : CS_TEAM_CT);
	ST(GetTeamCommander(g_iSTTeam) == 0 && GetCommanderTeam(g_iSTBot) == 0, "team_change_releases");
	ChangeClientTeam(g_iSTBot, g_iSTTeam);
	SelfTestEnd();
	return Plugin_Stop;
}

void SelfTestEnd() {
	g_bSelfTestRunning = false;
	for (int t=0; t<4; t++) g_iWorkersOwned[t] = g_iSTOldWorkers[t];
	ConVar hZombie = FindConVar("bot_zombie");
	if (hZombie != null) hZombie.IntValue = g_iSTOldZombie;
	g_hCvarViewDelay.FloatValue = g_fSTOldViewDelay;
	int iBot = g_iSTBot;
	if (iBot && IsClientInGame(iBot)) {
		if (g_eCommander[iBot].bEnabled) ResetClient(iBot);
		ReleaseCommander(iBot, false);
	}
	int iOld = GetClientOfUserId(g_iSTOldCmdrUserId);
	if (iOld && GetClientTeam(iOld) == g_iSTTeam) AssignCommander(iOld, false);
	SelfTestSummary();
}

void SelfTestSummary() {
	PrintToServer("[RTS-SELFTEST] DONE: %d passed, %d failed", g_iSTPass, g_iSTFail);
	LogMessage("[SELFTEST] DONE: %d passed, %d failed", g_iSTPass, g_iSTFail);
}
