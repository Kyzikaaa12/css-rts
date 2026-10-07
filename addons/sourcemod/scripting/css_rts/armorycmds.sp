// css_rts/armorycmds.sp -- v0.6 armory / ability console + debug commands

void ArmoryCmds_Init() {
	RegConsoleCmd("sm_rts_stock", cmdStock, "List the team armory stock [t|ct]");
	RegConsoleCmd("sm_rts_restock", cmdRestock, "Commander: restock <item> (costs Intel; server: <t|ct> <item>)");
	RegConsoleCmd("sm_rts_ability", cmdAbility, "Commander: use ability <sweep|smoke|supply> (server: <t|ct> <name> [x y z])");
	RegConsoleCmd("sm_rts_debug_stock", cmdDebugStock, "<t|ct> <item|all|clear> [n]: set stock for free");
	RegConsoleCmd("sm_rts_debug_buy", cmdDebugBuy, "<#userid|name> <item>: make a player/bot run 'buy <item>'");
	RegConsoleCmd("sm_rts_debug_ability", cmdDebugAbility, "<t|ct> <sweep|smoke|supply|reset> [x y z]: fire an ability (pays Intel, ignores nothing)");
}

public Action cmdStock(int iClient, int iArgs) {
	iClient = ResolveClient(iClient);
	int t = iClient ? GetClientTeam(iClient) : ArgTeam(1);
	if (iArgs >= 1) t = ArgTeam(1);
	if (!(CS_TEAM_T <= t <= CS_TEAM_CT)) { ReplyToCommand(iClient, "[RTS] sm_rts_stock t|ct"); return Plugin_Handled; }
	ReplyToCommand(iClient, "[RTS] Armory %s (stockpile %s), Intel %d, restocks %d, bought %d, total %d:", t == CS_TEAM_CT ? "CT" : "T",
		g_hCvarStockpile.BoolValue ? "on" : "off", g_iIntel[t], g_iStockRestocks[t], g_iArmoryBought[t], Armory_TotalStock(t));
	for (int k=0; k<g_iArmory; k++) {
		ReplyToCommand(iClient, "  %-12s %-6s stock %2d  bundle %d for %4d Intel", g_eArmory[k].sKey, Armory_Unlocked(t, k) ? "open" : "locked", g_iStock[t][k], g_eArmory[k].iBundle, Armory_Cost(k));
	}
	return Plugin_Handled;
}

public Action cmdRestock(int iClient, int iArgs) {
	iClient = ResolveClient(iClient);
	int t; char sItem[16];
	if (iClient) { t = GetCommanderTeam(iClient); GetCmdArg(1, sItem, sizeof(sItem)); }
	else { t = ArgTeam(1); GetCmdArg(2, sItem, sizeof(sItem)); }
	if (!t) { ReplyToCommand(iClient, "[RTS] Commanders only"); return Plugin_Handled; }
	int k = Armory_Find(sItem);
	if (k == -1) { ReplyToCommand(iClient, "[RTS] Unknown armory item '%s' (sm_rts_stock lists them)", sItem); return Plugin_Handled; }
	bool bOk = Armory_Restock(iClient, t, k);
	ReplyToCommand(iClient, "[RTS] restock %s -> %s (stock %d, Intel %d)", sItem, bOk ? "OK" : "refused", g_iStock[t][k], g_iIntel[t]);
	return Plugin_Handled;
}

bool ArgPos(int iFirst, float vecPos[3]) {
	if (GetCmdArgs() < iFirst + 2) return false;
	char s[16];
	for (int i=0; i<3; i++) { GetCmdArg(iFirst + i, s, sizeof(s)); vecPos[i] = StringToFloat(s); }
	return true;
}

public Action cmdAbility(int iClient, int iArgs) {
	iClient = ResolveClient(iClient);
	char sName[16];
	if (iClient) {
		GetCmdArg(1, sName, sizeof(sName));
		int a = Ability_FromName(sName);
		if (!GetCommanderTeam(iClient) || a == -1) { ReplyToCommand(iClient, "[RTS] Commanders only: sm_rts_ability sweep|smoke|supply"); return Plugin_Handled; }
		Ability_Begin(iClient, view_as<AbilityId>(a));
		return Plugin_Handled;
	}
	return cmdDebugAbility(0, iArgs);
}

public Action cmdDebugStock(int iClient, int iArgs) {
	iClient = ResolveClient(iClient);
	if (!HasRTSAccess(iClient)) return Plugin_Handled;
	int t = ArgTeam(1);
	char sItem[16], sN[8];
	GetCmdArg(2, sItem, sizeof(sItem));
	GetCmdArg(3, sN, sizeof(sN));
	int n = sN[0] ? StringToInt(sN) : 5;
	if (!(CS_TEAM_T <= t <= CS_TEAM_CT)) { ReplyToCommand(iClient, "[RTS] usage: sm_rts_debug_stock <t|ct> <item|all|clear> [n]"); return Plugin_Handled; }
	if (StrEqual(sItem, "clear")) { for (int k=0; k<g_iArmory; k++) g_iStock[t][k] = 0; }
	else if (StrEqual(sItem, "all")) { for (int k=0; k<g_iArmory; k++) g_iStock[t][k] = n; }
	else {
		int k = Armory_Find(sItem);
		if (k == -1) { ReplyToCommand(iClient, "[RTS] Unknown item '%s'", sItem); return Plugin_Handled; }
		g_iStock[t][k] = n;
	}
	ReplyToCommand(iClient, "[RTS] %s stock %s = %d (total %d)", t == CS_TEAM_CT ? "CT" : "T", sItem, n, Armory_TotalStock(t));
	return Plugin_Handled;
}

public Action cmdDebugAbility(int iClient, int iArgs) {
	iClient = ResolveClient(iClient);
	if (!HasRTSAccess(iClient)) return Plugin_Handled;
	int t = ArgTeam(1);
	char sName[16]; GetCmdArg(2, sName, sizeof(sName));
	if (!(CS_TEAM_T <= t <= CS_TEAM_CT)) { ReplyToCommand(iClient, "[RTS] usage: sm_rts_debug_ability <t|ct> <sweep|smoke|supply|reset> [x y z]"); return Plugin_Handled; }
	if (StrEqual(sName, "reset")) { Abilities_Reset(); ReplyToCommand(iClient, "[RTS] ability cooldowns reset"); return Plugin_Handled; }
	int a = Ability_FromName(sName);
	if (a == -1) { ReplyToCommand(iClient, "[RTS] unknown ability '%s'", sName); return Plugin_Handled; }
	float vecPos[3];
	if (!ArgPos(3, vecPos)) {
		int c = GetTeamCommander(t);
		if (c > 0) GetClientAbsOrigin(c, vecPos);
	}
	bool bOk = Ability_Fire(0, t, view_as<AbilityId>(a), vecPos);
	ReplyToCommand(iClient, "[RTS] ability %s for %s -> %s (Intel %d, cooldown %.0fs) at %.0f %.0f %.0f", sName, t == CS_TEAM_CT ? "CT" : "T",
		bOk ? "FIRED" : "refused", g_iIntel[t], Ability_CooldownLeft(t, view_as<AbilityId>(a)), vecPos[0], vecPos[1], vecPos[2]);
	return Plugin_Handled;
}

public Action cmdDebugBuy(int iClient, int iArgs) {
	iClient = ResolveClient(iClient);
	if (!HasRTSAccess(iClient)) return Plugin_Handled;
	char sTarget[64], sItem[16];
	GetCmdArg(1, sTarget, sizeof(sTarget));
	GetCmdArg(2, sItem, sizeof(sItem));
	int iTarget = FindTarget(iClient, sTarget, false, false);
	if (iTarget <= 0) return Plugin_Handled;
	if (StrEqual(sItem, "spawn")) {   // teleport to the team spawn (into the buy zone) first
		int iSpawn = FindEntityByClassname(-1, GetClientTeam(iTarget) == CS_TEAM_CT ? "info_player_counterterrorist" : "info_player_terrorist");
		float vecPos[3];
		if (iSpawn != -1) { Entity_GetAbsOrigin(iSpawn, vecPos); TeleportEntity(iTarget, vecPos, NULL_VECTOR, view_as<float>({0.0, 0.0, 0.0})); }
		ReplyToCommand(iClient, "[RTS] %N teleported to spawn", iTarget);
		return Plugin_Handled;
	}
	int iMoney = GetEntProp(iTarget, Prop_Send, "m_iAccount");
	FakeClientCommand(iTarget, "buy %s", sItem);
	ReplyToCommand(iClient, "[RTS] %N: buy %s (money before $%d, now $%d, inbuyzone %d)", iTarget, sItem, iMoney, GetEntProp(iTarget, Prop_Send, "m_iAccount"), GetEntProp(iTarget, Prop_Send, "m_bInBuyZone"));
	return Plugin_Handled;
}
