// css_rts/commands.sp -- M1 player + debug commands

void M1_RegisterCommands() {
	RegConsoleCmd("sm_commander", cmdCommander, "Claim the Commander role for your team");
	RegConsoleCmd("sm_rts_soldier", cmdSoldier, "Leave the Commander role and play as a soldier (FPS)");
	RegConsoleCmd("sm_uncommander", cmdUncommander, "Give up the Commander role");
	RegConsoleCmd("sm_rtsmenu", cmdRoleMenu, "Open the CSS RTS role menu");
	RegConsoleCmd("sm_rts_toggle", cmdToggle, "Commander: toggle the command view (bind F2)");

	RegConsoleCmd("sm_rts_debug_config", cmdDebugConfig, "Print the loaded per-map config");
	RegConsoleCmd("sm_rts_debug_ents", cmdDebugEnts, "Dump css_rts entities (terminals etc.)");
	RegConsoleCmd("sm_rts_debug_findpost", cmdDebugFindPost, "Search a valid command post spot near a team's spawns: [t|ct]");
	RegConsoleCmd("sm_rts_debug_setcommander", cmdDebugSetCommander, "Force <#userid|name> to be commander (bots allowed)");
	RegConsoleCmd("sm_rts_debug_view", cmdDebugView, "Force <#userid|name> into (1) / out of (0) the post command view");
	RegConsoleCmd("sm_rts_debug_use", cmdDebugUse, "Simulate <#userid|name> pressing USE");
	RegConsoleCmd("sm_rts_debug_intel", cmdDebugIntel, "Print Intel, or set: <t|ct> <value>");
	RegConsoleCmd("sm_rts_debug_hurt", cmdDebugHurt, "Deal <dmg> generic damage to <#userid|name> (tests damage-exit)");
	RegConsoleCmd("sm_rts_debug_match", cmdDebugMatch, "Print match state (warm-up, unit pools, waves, FPS counts)");
	RegConsoleCmd("sm_rts_reloadcfg", cmdReloadCfg, "Reload the map config and respawn terminals");
}

public Action cmdCommander(int iClient, int iArgs) {
	iClient = ResolveClient(iClient);
	if (!iClient) { ReplyToCommand(iClient, "[RTS] In-game players only"); return Plugin_Handled; }
	int iTeam = GetClientTeam(iClient);
	if (!(CS_TEAM_T <= iTeam <= CS_TEAM_CT)) { g_bWantsCommander[iClient] = true; PrintToChat(iClient, "\x04[RTS]\x01 Join T or CT first; you will become Commander when you spawn."); return Plugin_Handled; }
	int iCur = GetTeamCommander(iTeam);
	if (iCur == iClient) { ToggleCommanderView(iClient); return Plugin_Handled; }
	if (iCur) { PrintToChat(iClient, "\x04[RTS]\x01 %N is already your Commander.", iCur); return Plugin_Handled; }
	AssignCommander(iClient);
	if (IsPlayerAlive(iClient)) CommanderStart(iClient);
	return Plugin_Handled;
}

public Action cmdUncommander(int iClient, int iArgs) {
	iClient = ResolveClient(iClient);
	if (!iClient) return Plugin_Handled;
	if (!GetCommanderTeam(iClient)) { PrintToChat(iClient, "\x04[RTS]\x01 You are not a Commander."); return Plugin_Handled; }
	g_bDeclinedCmdr[iClient] = true;
	if (g_hCvarBodyless.BoolValue) SchedulePending(iClient, Pending_LeaveRole);
	else ReleaseCommander(iClient);
	return Plugin_Handled;
}

public Action cmdRoleMenu(int iClient, int iArgs) {
	iClient = ResolveClient(iClient);
	if (iClient) ShowRoleMenu(iClient);
	return Plugin_Handled;
}

public Action cmdToggle(int iClient, int iArgs) {
	iClient = ResolveClient(iClient);
	if (iClient) ToggleCommanderView(iClient);
	return Plugin_Handled;
}

int GetTargetArg(int iClient, int iArg) {
	char sArg[64];
	GetCmdArg(iArg, sArg, sizeof(sArg));
	int iTarget = FindTarget(iClient, sArg, false, false);
	return iTarget > 0 ? iTarget : 0;
}

public Action cmdDebugConfig(int iClient, int iArgs) {
	iClient = ResolveClient(iClient);
	if (!HasRTSAccess(iClient)) return Plugin_Handled;
	ReplyToCommand(iClient, "[RTS] config %s loaded=%d", g_sMapConfigPath, g_bMapConfigLoaded);
	ReplyToCommand(iClient, "[RTS] camera mins %.0f %.0f %.0f maxs %.0f %.0f %.0f", g_vecCamMins[0], g_vecCamMins[1], g_vecCamMins[2], g_vecCamMaxs[0], g_vecCamMaxs[1], g_vecCamMaxs[2]);
	for (int t=CS_TEAM_T; t<=CS_TEAM_CT; t++) {
		TeamPost p;
		p = g_ePost[t];
		ReplyToCommand(iClient, "[RTS] %s post valid=%d src=%s origin %.0f %.0f %.0f yaw %.0f model %s hq %.0f %.0f %.0f terminal=%d cmdr=%d intel=%d",
			t == CS_TEAM_CT ? "CT" : "T", p.bValid, p.bFromConfig ? "config" : "auto", p.vecOrigin[0], p.vecOrigin[1], p.vecOrigin[2], p.vecAngles[1], p.sModel,
			p.vecHQOrigin[0], p.vecHQOrigin[1], p.vecHQOrigin[2], GetTerminal(t), GetTeamCommander(t), g_iIntel[t]);
	}
	return Plugin_Handled;
}

public Action cmdDebugEnts(int iClient, int iArgs) {
	iClient = ResolveClient(iClient);
	if (!HasRTSAccess(iClient)) return Plugin_Handled;
	int iCount, iEdicts;
	char sName[64], sClass[64], sModel[PLATFORM_MAX_PATH];
	for (int i=MaxClients+1; i<GetMaxEntities(); i++) {
		if (!IsValidEntity(i)) continue;
		iEdicts++;
		GetEntPropString(i, Prop_Data, "m_iName", sName, sizeof(sName));
		if (StrContains(sName, "css_rts_") != 0) continue;
		GetEntityClassname(i, sClass, sizeof(sClass));
		GetEntPropString(i, Prop_Data, "m_ModelName", sModel, sizeof(sModel));
		float v[3];
		GetEntPropVector(i, Prop_Data, "m_vecAbsOrigin", v);
		ReplyToCommand(iClient, "[RTS] ent %d %s name=%s model=%s pos=%.0f %.0f %.0f solid=%d", i, sClass, sName, sModel, v[0], v[1], v[2], GetEntProp(i, Prop_Send, "m_nSolidType"));
		iCount++;
	}
	ReplyToCommand(iClient, "[RTS] %d css_rts entities, %d valid entities total", iCount, iEdicts);
	return Plugin_Handled;
}

public Action cmdDebugFindPost(int iClient, int iArgs) {
	iClient = ResolveClient(iClient);
	if (!HasRTSAccess(iClient)) return Plugin_Handled;
	for (int t=CS_TEAM_T; t<=CS_TEAM_CT; t++) {
		if (iArgs >= 1) { char s[8]; GetCmdArg(1, s, sizeof(s)); if (TeamFromName(s) != t) continue; }
		float v[3], fYaw;
		if (FindPostSpot(t, v, fYaw, true)) {
			ReplyToCommand(iClient, "[RTS] \"%s\" { \"post_origin\" \"%.0f %.0f %.0f\" \"post_angles\" \"0 %.0f 0\" }", t == CS_TEAM_CT ? "CT" : "T", v[0], v[1], v[2], fYaw);
		} else {
			ReplyToCommand(iClient, "[RTS] team %d: no valid spot found", t);
		}
		if (g_ePost[t].bValid) {
			char sWhy[64];
			float f[3];
			bool bOk = ValidatePostSpot(t, g_ePost[t].vecOrigin, g_ePost[t].vecAngles[1], f, sWhy, sizeof(sWhy));
			ReplyToCommand(iClient, "[RTS] team %d current post validation: %s (%s)", t, bOk ? "PASS" : "FAIL", sWhy);
		}
	}
	return Plugin_Handled;
}

public Action cmdDebugSetCommander(int iClient, int iArgs) {
	iClient = ResolveClient(iClient);
	if (!HasRTSAccess(iClient)) return Plugin_Handled;
	if (iArgs < 1) { ReplyToCommand(iClient, "Usage: sm_rts_debug_setcommander <#userid|name>"); return Plugin_Handled; }
	int iTarget = GetTargetArg(iClient, 1);
	if (!iTarget) return Plugin_Handled;
	int iTeam = GetClientTeam(iTarget);
	int iCur = GetTeamCommander(iTeam);
	if (iCur && iCur != iTarget) ReleaseCommander(iCur, false);
	ReplyToCommand(iClient, "[RTS] setcommander %N: %s", iTarget, AssignCommander(iTarget) ? "ok" : "failed (not on T/CT?)");
	return Plugin_Handled;
}

public Action cmdDebugView(int iClient, int iArgs) {
	iClient = ResolveClient(iClient);
	if (!HasRTSAccess(iClient)) return Plugin_Handled;
	if (iArgs < 1) { ReplyToCommand(iClient, "Usage: sm_rts_debug_view <#userid|name> [1|0]"); return Plugin_Handled; }
	int iTarget = GetTargetArg(iClient, 1);
	if (!iTarget) return Plugin_Handled;
	bool bOn = iArgs < 2 || GetCmdArgInt(2) != 0;
	if (!bOn) { ExitCommanderView(iTarget, "debug"); ReplyToCommand(iClient, "[RTS] %N left the view", iTarget); return Plugin_Handled; }
	char sWhy[64];
	bool bOk = EnterCommanderView(iTarget, true, sWhy, sizeof(sWhy));
	ReplyToCommand(iClient, "[RTS] %N enter view: %s", iTarget, sWhy);
	#pragma unused bOk
	return Plugin_Handled;
}

public Action cmdDebugUse(int iClient, int iArgs) {
	iClient = ResolveClient(iClient);
	if (!HasRTSAccess(iClient)) return Plugin_Handled;
	if (iArgs < 1) { ReplyToCommand(iClient, "Usage: sm_rts_debug_use <#userid|name>"); return Plugin_Handled; }
	int iTarget = GetTargetArg(iClient, 1);
	if (!iTarget) return Plugin_Handled;
	SimulateUse(iTarget);
	ReplyToCommand(iClient, "[RTS] %N USE -> aimed terminal team %d, in view=%d", iTarget, GetAimedTerminal(iTarget), g_bPostView[iTarget]);
	return Plugin_Handled;
}

void SimulateUse(int iClient) {
	if (g_eCommander[iClient].bEnabled) {
		if (GetGameTime() - g_fViewToggleTime[iClient] >= 0.4) ExitCommanderView(iClient, "use");
	} else {
		TryUseTerminal(iClient);
	}
}

public Action cmdDebugIntel(int iClient, int iArgs) {
	iClient = ResolveClient(iClient);
	if (!HasRTSAccess(iClient)) return Plugin_Handled;
	if (iArgs >= 2) {
		char s[8]; GetCmdArg(1, s, sizeof(s));
		int t = TeamFromName(s);
		if (t) g_iIntel[t] = GetCmdArgInt(2);
	}
	ReplyToCommand(iClient, "[RTS] Intel T=%d (+%d) CT=%d (+%d) tick=%.1fs blocked_cmds=%d", g_iIntel[CS_TEAM_T], ComputeIntelIncome(CS_TEAM_T),
		g_iIntel[CS_TEAM_CT], ComputeIntelIncome(CS_TEAM_CT), g_hCvarIntelTick.FloatValue, g_iBlockedCmds);
	return Plugin_Handled;
}

public Action cmdReloadCfg(int iClient, int iArgs) {
	iClient = ResolveClient(iClient);
	if (!HasRTSAccess(iClient)) return Plugin_Handled;
	RemoveTerminals();
	LoadMapConfig();
	PrecacheTerminals();
	EnsureTerminals();
	ReplyToCommand(iClient, "[RTS] reloaded %s (loaded=%d)", g_sMapConfigPath, g_bMapConfigLoaded);
	return Plugin_Handled;
}

public Action cmdDebugHurt(int iClient, int iArgs) {
	iClient = ResolveClient(iClient);
	if (!HasRTSAccess(iClient)) return Plugin_Handled;
	if (iArgs < 1) { ReplyToCommand(iClient, "Usage: sm_rts_debug_hurt <#userid|name> [dmg=5]"); return Plugin_Handled; }
	int iTarget = GetTargetArg(iClient, 1);
	if (!iTarget) return Plugin_Handled;
	float fDmg = iArgs >= 2 ? GetCmdArgFloat(2) : 5.0;
	int iHp = GetClientHealth(iTarget);
	SDKHooks_TakeDamage(iTarget, 0, 0, fDmg, DMG_BULLET);
	ReplyToCommand(iClient, "[RTS] hurt %N: hp %d -> %d, obsmode=%d takedamage=%d inview=%d", iTarget, iHp, GetClientHealth(iTarget),
		GetEntProp(iTarget, Prop_Send, "m_iObserverMode"), GetEntProp(iTarget, Prop_Data, "m_takedamage"), g_bPostView[iTarget]);
	return Plugin_Handled;
}

public Action cmdDebugMatch(int iClient, int iArgs) {
	iClient = ResolveClient(iClient);
	if (!HasRTSAccess(iClient)) return Plugin_Handled;
	int iBotsT, iBotsCT;
	int iFpsT = CountFps(CS_TEAM_T, false, iBotsT), iFpsCT = CountFps(CS_TEAM_CT, false, iBotsCT);
	ReplyToCommand(iClient, "[RTS] match: continuous=%d warmup_left=%.0f over=%d next_wave=%.0f pool T=%d CT=%d | FPS T=%d (bots %d, alive %d) CT=%d (bots %d, alive %d) | cmdr T=%d CT=%d",
		g_hCvarContinuous.BoolValue, InWarmup() ? (g_eGame == GS_Countdown ? g_fCountdownEnd - GetGameTime() : -1.0) : 0.0, g_bMatchOver, g_fNextWave - GetGameTime(),
		g_iUnitPool[CS_TEAM_T], g_iUnitPool[CS_TEAM_CT], iFpsT, iBotsT, CountFps(CS_TEAM_T, true), iFpsCT, iBotsCT, CountFps(CS_TEAM_CT, true),
		GetTeamCommander(CS_TEAM_T), GetTeamCommander(CS_TEAM_CT));
	return Plugin_Handled;
}

public Action cmdSoldier(int iClient, int iArgs) {
	iClient = ResolveClient(iClient);
	if (!iClient) return Plugin_Handled;
	g_bWantsCommander[iClient] = false;
	g_bDeclinedCmdr[iClient] = true;
	if (GetCommanderTeam(iClient)) {
		if (g_hCvarBodyless.BoolValue) SchedulePending(iClient, Pending_LeaveRole);
		else ReleaseCommander(iClient);
	}
	ReplyToCommand(iClient, "[RTS] Playing as Soldier. sm_commander (or !rts) to command again.");
	return Plugin_Handled;
}
