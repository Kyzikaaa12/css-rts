// css_rts/autojoin.sp -- v0.5.1: skip the stock MOTD ("You are playing Counter-Strike: Source"),
// the SELECT TEAM screen and the class picker. Humans are auto-assigned (host -> css_rts_host_team,
// everyone else balanced by human count), get a random class and spawn straight into the lobby.
// Team changes go through our own menu (!rts -> Switch team / sm_rts_team).

ConVar g_hCvarAutoJoin;
ConVar g_hCvarHostTeam;
bool g_bAutoJoinQueued[MAXPLAYERS+1];
int g_iAutoJoinBlocked;      // panels swallowed (selftest/debug)
int g_iAutoJoins;

ConVar g_hCvarQuietBots;

public Action Event_QuietCvar(Event hEvent, const char[] sName, bool bDontBroadcast) {
	if (!g_hCvarQuietBots.BoolValue) return Plugin_Continue;
	char sCvar[64];
	hEvent.GetString("cvarname", sCvar, sizeof(sCvar));
	if (StrContains(sCvar, "bot_") == 0 || StrContains(sCvar, "mp_") == 0 || StrContains(sCvar, "sv_") == 0 || StrContains(sCvar, "css_rts") == 0) hEvent.BroadcastDisabled = true;
	return Plugin_Continue;
}

public Action Event_QuietBot(Event hEvent, const char[] sName, bool bDontBroadcast) {
	if (!g_hCvarQuietBots.BoolValue) return Plugin_Continue;
	bool bBot;
	if (StrEqual(sName, "player_connect")) {
		char sId[32];
		hEvent.GetString("networkid", sId, sizeof(sId));
		bBot = StrEqual(sId, "BOT") || hEvent.GetInt("bot") != 0;
	} else {
		int c = GetClientOfUserId(hEvent.GetInt("userid"));
		bBot = c > 0 && IsClientInGame(c) && IsFakeClient(c);
		if (!bBot && StrEqual(sName, "player_disconnect")) {
			char sId[32];
			hEvent.GetString("networkid", sId, sizeof(sId));
			bBot = StrEqual(sId, "BOT");
		}
	}
	if (bBot) {
		if (StrEqual(sName, "player_team")) hEvent.SetBool("silent", true);
		hEvent.BroadcastDisabled = true;
	}
	return Plugin_Continue;
}

void AutoJoin_Init() {
	g_hCvarAutoJoin = CreateConVar("css_rts_autojoin", "1", "1 = skip the MOTD + team/class select screens; auto-assign teams", _, true, 0.0, true, 1.0);
	g_hCvarHostTeam = CreateConVar("css_rts_host_team", "ct", "Team the host (first human) is put on: ct, t or auto (balance)");
	UserMsg iMsg = GetUserMessageId("VGUIMenu");
	if (iMsg != INVALID_MESSAGE_ID) HookUserMessage(iMsg, UM_VGUIMenu, true);
	g_hCvarQuietBots = CreateConVar("css_rts_quiet_bots", "1", "1 = hide the bot join/leave/team chat and the 'Server cvar bot_quota changed' spam", _, true, 0.0, true, 1.0);
	HookEvent("server_cvar", Event_QuietCvar, EventHookMode_Pre);
	HookEvent("player_connect", Event_QuietBot, EventHookMode_Pre);
	HookEvent("player_disconnect", Event_QuietBot, EventHookMode_Pre);
	HookEvent("player_team", Event_QuietBot, EventHookMode_Pre);
	RegConsoleCmd("sm_rts_team", cmdTeam, "Switch team: sm_rts_team <t|ct> (no argument = the other team)");
	RegConsoleCmd("sm_rts_debug_autojoin", cmdDebugAutoJoin, "<#userid|name>: run the auto team assignment for a player (prints the pick)");
	// listen-server host / late load: players already connected before the plugin was ready
	for (int i=1; i<=MaxClients; i++) {
		if (IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) <= CS_TEAM_SPECTATOR) AutoJoin_Queue(i, 0.5);
	}
}

void AutoJoin_OnClientPutInServer(int iClient) {
	g_bAutoJoinQueued[iClient] = false;
	// Fallback in case no panel message arrives (or the client closed it first)
	if (!IsFakeClient(iClient)) AutoJoin_Queue(iClient, 3.0);
}

public Action UM_VGUIMenu(UserMsg iMsgId, BfRead hMsg, const int[] iPlayers, int iNum, bool bReliable, bool bInit) {
	if (!g_hCvarAutoJoin.BoolValue || iNum != 1) return Plugin_Continue;
	char sName[32];
	hMsg.ReadString(sName, sizeof(sName));
	bool bShow = hMsg.ReadByte() != 0;
	if (!bShow) return Plugin_Continue;
	int iClient = iPlayers[0];
	if (StrEqual(sName, "team") && IsClientInGame(iClient) && GetClientTeam(iClient) >= CS_TEAM_T) {
		// "M" / chooseteam while already playing: our role menu (has Switch team) instead
		g_iAutoJoinBlocked++;
		CreateTimer(0.1, Timer_AutoRoleMenu, GetClientUserId(iClient), TIMER_FLAG_NO_MAPCHANGE);
		return Plugin_Handled;
	}
	if (StrEqual(sName, "info") || StrEqual(sName, "team")) {
		g_iAutoJoinBlocked++;
		AutoJoin_Queue(iClient, 0.1);
		return Plugin_Handled;
	}
	if (StrEqual(sName, "class_ter") || StrEqual(sName, "class_ct")) {
		g_iAutoJoinBlocked++;
		CreateTimer(0.1, Timer_AutoClass, GetClientUserId(iClient), TIMER_FLAG_NO_MAPCHANGE);
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

void AutoJoin_Queue(int iClient, float fDelay) {
	if (g_bAutoJoinQueued[iClient]) return;
	g_bAutoJoinQueued[iClient] = true;
	CreateTimer(fDelay, Timer_AutoJoin, GetClientUserId(iClient), TIMER_FLAG_NO_MAPCHANGE);
}

// Team pick: host -> css_rts_host_team; others -> team with fewer humans (tie: fewer players, then CT)
int AutoJoin_PickTeam(int iClient) {
	char sHost[8];
	g_hCvarHostTeam.GetString(sHost, sizeof(sHost));
	int iHostTeam = TeamFromName(sHost);
	if (iHostTeam != CS_TEAM_NONE && Lobby_Host() == iClient) return iHostTeam;
	int iH[4], iP[4];
	for (int i=1; i<=MaxClients; i++) {
		if (i == iClient || !IsClientInGame(i)) continue;
		int t = GetClientTeam(i);
		if (t < CS_TEAM_T) continue;
		iP[t]++;
		if (!IsFakeClient(i)) iH[t]++;
	}
	if (iH[CS_TEAM_T] != iH[CS_TEAM_CT]) return iH[CS_TEAM_T] < iH[CS_TEAM_CT] ? CS_TEAM_T : CS_TEAM_CT;
	if (iP[CS_TEAM_T] != iP[CS_TEAM_CT]) return iP[CS_TEAM_T] < iP[CS_TEAM_CT] ? CS_TEAM_T : CS_TEAM_CT;
	if (iHostTeam != CS_TEAM_NONE) return iHostTeam == CS_TEAM_CT ? CS_TEAM_T : CS_TEAM_CT;  // host's team already chosen
	return CS_TEAM_CT;
}

public Action Timer_AutoJoin(Handle hTimer, int iUserId) {
	int iClient = GetClientOfUserId(iUserId);
	if (!iClient || !IsClientInGame(iClient)) return Plugin_Stop;
	g_bAutoJoinQueued[iClient] = false;
	if (!g_hCvarAutoJoin.BoolValue || IsFakeClient(iClient)) return Plugin_Stop;
	int t = AutoJoin_PickTeam(iClient);
	if (GetClientTeam(iClient) >= CS_TEAM_T) {
		if (GetClientTeam(iClient) != t && Lobby_Host() == iClient) {
			CS_SwitchTeam(iClient, t);
			if (!IsPlayerAlive(iClient)) CS_RespawnPlayer(iClient);
		}
		return Plugin_Stop;
	}
	g_iAutoJoins++;
	AutoJoin_ClosePanel(iClient, "info");
	AutoJoin_ClosePanel(iClient, "team");
	FakeClientCommandEx(iClient, "joingame");          // leaves the welcome (MOTD) state
	FakeClientCommandEx(iClient, "jointeam %d", t);    // class panel that follows is swallowed above
	CreateTimer(0.5, Timer_AutoClass, iUserId, TIMER_FLAG_NO_MAPCHANGE);
	CreateTimer(1.5, Timer_AutoJoinVerify, iUserId, TIMER_FLAG_NO_MAPCHANGE);
	return Plugin_Stop;
}

public Action Timer_AutoClass(Handle hTimer, int iUserId) {
	int iClient = GetClientOfUserId(iUserId);
	if (!iClient || !IsClientInGame(iClient) || IsPlayerAlive(iClient)) return Plugin_Stop;
	if (GetClientTeam(iClient) < CS_TEAM_T) return Plugin_Stop;
	if (!HasEntProp(iClient, Prop_Send, "m_iClass") || GetEntProp(iClient, Prop_Send, "m_iClass") == 0) FakeClientCommandEx(iClient, "joinclass 0");   // 0 = auto-select
	return Plugin_Stop;
}

// Last resort: still not on a team / not spawned -> force it server-side
public Action Timer_AutoJoinVerify(Handle hTimer, int iUserId) {
	int iClient = GetClientOfUserId(iUserId);
	if (!iClient || !IsClientInGame(iClient) || !g_hCvarAutoJoin.BoolValue) return Plugin_Stop;
	if (GetClientTeam(iClient) < CS_TEAM_T) {
		CS_SwitchTeam(iClient, AutoJoin_PickTeam(iClient));
		LogMessage("[autojoin] forced %N onto team %d", iClient, GetClientTeam(iClient));
	}
	if (!IsPlayerAlive(iClient) && (InLobby() || g_eGame == GS_Live)) CS_RespawnPlayer(iClient);
	return Plugin_Stop;
}

// Close a stock panel that was already open (e.g. the listen-server host saw the MOTD before the
// plugin loaded)
void AutoJoin_ClosePanel(int iClient, const char[] sPanel) {
	Handle hMsg = StartMessageOne("VGUIMenu", iClient);
	if (hMsg == null) return;
	BfWrite hBf = UserMessageToBfWrite(hMsg);
	hBf.WriteString(sPanel);
	hBf.WriteByte(0);   // hide
	hBf.WriteByte(0);   // no keys
	EndMessage();
}

// Create Server "Your team" is applied after css_rts.cfg, which would otherwise leave the host on CT.
// Auto is left to the balancer. CT and T are forced onto that side before the commander camera opens.
void AutoJoin_ApplyHost() {
	if (g_eGame == GS_Live) return;
	int iHost = Lobby_Host();
	if (!iHost || !IsClientInGame(iHost) || IsFakeClient(iHost)) return;
	char sHost[8];
	g_hCvarHostTeam.GetString(sHost, sizeof(sHost));
	int t = TeamFromName(sHost);
	if (t != CS_TEAM_T && t != CS_TEAM_CT) return;
	if (GetClientTeam(iHost) == t) return;
	if (GetClientTeam(iHost) >= CS_TEAM_T) AutoJoin_SwitchTeam(iHost, t);
}

void AutoJoin_SwitchTeam(int iClient, int t) {
	if (GetClientTeam(iClient) == t) return;
	if (GetCommanderTeam(iClient)) ReleaseCommander(iClient, true);
	CS_SwitchTeam(iClient, t);
	if (InLobby() || g_eGame == GS_Live) CS_RespawnPlayer(iClient);
	PrintToChatAll("\x04[RTS]\x01 %N switched to %s.", iClient, t == CS_TEAM_CT ? "Counter-Terrorists" : "Terrorists");
}

public Action cmdTeam(int iClient, int iArgs) {
	if (!iClient || !IsClientInGame(iClient)) return Plugin_Handled;
	int t = iArgs ? ArgTeam(1) : (GetClientTeam(iClient) == CS_TEAM_CT ? CS_TEAM_T : CS_TEAM_CT);
	if (!(CS_TEAM_T <= t <= CS_TEAM_CT)) { ReplyToCommand(iClient, "[RTS] usage: sm_rts_team <t|ct>"); return Plugin_Handled; }
	AutoJoin_SwitchTeam(iClient, t);
	return Plugin_Handled;
}

public Action cmdDebugAutoJoin(int iClient, int iArgs) {
	iClient = ResolveClient(iClient);
	if (!HasRTSAccess(iClient)) return Plugin_Handled;
	char sT[64]; GetCmdArg(1, sT, sizeof(sT));
	int iTarget = iArgs ? FindTarget(iClient, sT, false, false) : 0;
	if (iTarget > 0) ReplyToCommand(iClient, "[RTS] autojoin pick for %N: %d (host %d)", iTarget, AutoJoin_PickTeam(iTarget), Lobby_Host());
	ReplyToCommand(iClient, "[RTS] autojoin=%d host_team cvar, panels blocked %d, autojoins %d", g_hCvarAutoJoin.IntValue, g_iAutoJoinBlocked, g_iAutoJoins);
	return Plugin_Handled;
}

public Action Timer_AutoRoleMenu(Handle hTimer, int iUserId) {
	int iClient = GetClientOfUserId(iUserId);
	if (iClient && IsClientInGame(iClient)) ShowRoleMenu(iClient);
	return Plugin_Stop;
}
