// css_rts/hud.sp -- RTS readout. Resources sit on a top bar (AoE2 / WC3). The unit list sits
// along the bottom. The right-hand column is gone so the map stays clear.

ConVar g_hCvarHudX, g_hCvarHudY;
float g_fHelpUntil[MAXPLAYERS+1];
bool g_bHelpPinned[MAXPLAYERS+1];
bool g_bHudMini;
bool g_bHelpSeen[MAXPLAYERS+1];
char g_sJoinLine[96];
char g_sJoinHold[96];
float g_fJoinUntil;
int g_iCursorCol[MAXPLAYERS+1][3];
char g_sAction[MAXPLAYERS+1][256];
float g_fActionUntil[MAXPLAYERS+1];

void Hud_Init() {
	UserMsg iJoin = GetUserMessageId("TextMsg");
	if (iJoin != INVALID_MESSAGE_ID) HookUserMessage(iJoin, UM_JoinLine, true);
	g_hCvarHudX = CreateConVar("css_rts_hud_x", "0.74", "HUD panel left edge (0..1 of screen width)", _, true, 0.0, true, 0.95);
	g_hCvarHudY = CreateConVar("css_rts_hud_y", "0.20", "HUD panel top (0..1 of screen height)", _, true, 0.0, true, 0.9);
	RegConsoleCmd("sm_rts_help", cmdRtsHelp, "Toggle the controls help in the HUD panel");
	RegConsoleCmd("sm_rts_hud", cmdRtsHud, "Show or shrink the RTS bars (F9)");
	RegConsoleCmd("sm_rts_debug_hud", cmdDebugHud, "<#userid|name> [view]: print a player's HUD panel text + size");
}

void Hud_MapStart() {
	CreateTimer(0.5, Timer_HudPanel, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

void Hud_OnClientPutInServer(int iClient) {
	g_fHelpUntil[iClient] = 0.0;
	g_bHelpPinned[iClient] = false;
	g_bHelpSeen[iClient] = false;
}

// Called when a player enters the command view: help for 10 s the first time only
void Hud_OnEnterView(int iClient) {
	g_bHelpSeen[iClient] = true;
	g_fHelpUntil[iClient] = 0.0;
	g_bHelpPinned[iClient] = false;
}

public Action cmdRtsHud(int iClient, int iArgs) {
	g_bHudMini = !g_bHudMini;
	if (iClient) PrintHintText(iClient, g_bHudMini ? "RTS UI mini" : "RTS UI full");
	return Plugin_Handled;
}

public Action cmdRtsHelp(int iClient, int iArgs) {
	if (iClient) Hud_ToggleHelp(iClient);
	return Plugin_Handled;
}

public Action UM_JoinLine(UserMsg iMsg, BfRead hMsg, const int[] iPlayers, int iNum, bool bReliable, bool bInit) {
	hMsg.ReadByte();
	char sMsg[160], sWho[64];
	hMsg.ReadString(sMsg, sizeof(sMsg));
	hMsg.ReadString(sWho, sizeof(sWho));
	bool bJoin = StrContains(sMsg, "Game_connected", false) != -1 || StrContains(sMsg, "joined the game", false) != -1;
	bool bLeft = StrContains(sMsg, "Game_disconnected", false) != -1 || StrContains(sMsg, "left the game", false) != -1;
	if (!bJoin && !bLeft) return Plugin_Continue;
	// ShowSyncHudText starts a usermessage. Doing that inside this TextMsg hook
	// makes StartMessage return a null buffer and the game dies on connect.
	if (sWho[0]) FormatEx(g_sJoinLine, sizeof(g_sJoinLine), "%s %s", sWho, bLeft ? "left" : "joined");
	else strcopy(g_sJoinLine, sizeof(g_sJoinLine), sMsg);
	RequestFrame(Frame_JoinLine);
	return Plugin_Handled;
}

public void Frame_JoinLine() {
	if (!g_sJoinLine[0]) return;
	strcopy(g_sJoinHold, sizeof(g_sJoinHold), g_sJoinLine);
	g_sJoinLine[0] = 0;
	g_fJoinUntil = GetGameTime() + 3.5;
}

void Hud_ToggleHelp(int iClient) {
	g_bHelpPinned[iClient] = !(g_bHelpPinned[iClient] || g_fHelpUntil[iClient] > GetGameTime());
	g_fHelpUntil[iClient] = 0.0;
}

bool Hud_HelpVisible(int iClient) {
	return g_bHelpPinned[iClient] || g_fHelpUntil[iClient] > GetGameTime();
}

// Bottom-centre action line (placement / ability targeting). Short, one or two lines.
// CS:S keeps 6 HUD channels. Sync objects stole the least-used one, so CT, T, and the
// clock dropped out. These six are fixed channels, repainted every frame.
#define HUD_CH_INTEL 0
#define HUD_CH_CT 1
#define HUD_CH_T 2
#define HUD_CH_CLOCK 3
#define HUD_CH_HQ 4
#define HUD_CH_EXTRA 5

void Hud_CursorColor(int i, int r, int g, int b) {
	if (i < 1 || i > MaxClients) return;
	g_iCursorCol[i][0] = r;
	g_iCursorCol[i][1] = g;
	g_iCursorCol[i][2] = b;
}

void Hud_Chan(int i, int ch, float x, float y, int r, int g, int b, const char[] s) {
	if (!s[0]) return;
	SetHudTextParams(x, y, 999.0, r, g, b, 255, 0, 0.0, 0.0, 0.0);
	ShowHudText(i, ch, "%s", s);
}

void Hud_ClearChan(int i, int ch) {
	SetHudTextParams(0.0, 0.0, 0.05, 0, 0, 0, 0, 0, 0.0, 0.0, 0.0);
	ShowHudText(i, ch, " ");
}

void Hud_GameFrame() {
	for (int i = 1; i <= MaxClients; i++) {
		if (!IsClientInGame(i) || IsFakeClient(i)) continue;
		for (int slot = 0; slot < 6; slot++) Hud_PaintSlot(i, slot);
	}
}

void Hud_PaintSlot(int i, int slot) {
	int t = GetClientTeam(i);
	bool bMenu = InLobby() && GetClientMenu(i) != MenuSource_None && g_eGame != GS_Countdown;
	bool bBar = !g_bHudMini && !InLobby() && !bMenu && CS_TEAM_T <= t <= CS_TEAM_CT;
	if (!bBar) {
		if (slot == HUD_CH_INTEL && InLobby() && !bMenu) {
			char sLobby[768];
			Hud_LobbyText(i, sLobby, sizeof(sLobby));
			Hud_Chan(i, HUD_CH_INTEL, 0.02, 0.02, 255, 244, 210, sLobby);
		} else Hud_ClearChan(i, slot);
		return;
	}
	if (slot == HUD_CH_INTEL) {
		char sTop[768];
		Hud_LiveText(i, t, sTop, sizeof(sTop));
		int r = 255, g = 244, b = 210;
		if (t == CS_TEAM_CT) { r = 186; g = 214; b = 255; }
		else if (t == CS_TEAM_T) { r = 255; g = 214; b = 150; }
		Hud_Chan(i, HUD_CH_INTEL, 0.02, 0.012, r, g, b, sTop);
		return;
	}
	if (slot == HUD_CH_CT || slot == HUD_CH_T) {
		int iCt = g_iUnitPool[CS_TEAM_CT], iTm = g_iUnitPool[CS_TEAM_T];
		char sCt[32], sTm[32];
		FormatEx(sCt, sizeof(sCt), "CT %d left", iCt);
		FormatEx(sTm, sizeof(sTm), "T %d left", iTm);
		float xCt = 0.44, xT = 0.28;
		if (t == CS_TEAM_CT) { xCt = 0.28; xT = 0.44; }
		if (slot == HUD_CH_CT) Hud_Chan(i, HUD_CH_CT, xCt, 0.012, 80, 160, 255, sCt);
		else Hud_Chan(i, HUD_CH_T, xT, 0.012, 255, 60, 40, sTm);
		return;
	}
	char sRes[384];
	sRes[0] = 0;
	Research_FillHud(t, sRes, sizeof(sRes));
	bool bHq = g_hCvarHQ.BoolValue;
	int iEnemy = t == CS_TEAM_T ? CS_TEAM_CT : CS_TEAM_T;
	if (slot == HUD_CH_CLOCK) {
		int iClock = Hud_Clock();
		char sClock[64];
		if (bHq && sRes[0]) FormatEx(sClock, sizeof(sClock), "%d:%02d    HQ %d%%    Enemy %d%%", iClock / 60, iClock % 60, HQ_Percent(t), HQ_Percent(iEnemy));
		else FormatEx(sClock, sizeof(sClock), "%d:%02d", iClock / 60, iClock % 60);
		Hud_Chan(i, HUD_CH_CLOCK, 0.58, 0.012, 255, 220, 40, sClock);
		return;
	}
	if (slot == HUD_CH_HQ) {
		if (sRes[0]) Hud_Chan(i, HUD_CH_HQ, 0.62, 0.55, 255, 220, 140, sRes);
		else if (bHq) {
			char sHq[48];
			FormatEx(sHq, sizeof(sHq), "HQ %d%%    Enemy %d%%", HQ_Percent(t), HQ_Percent(iEnemy));
			Hud_Chan(i, HUD_CH_HQ, 0.72, 0.012, 255, 244, 210, sHq);
		} else Hud_ClearChan(i, HUD_CH_HQ);
		return;
	}
	if (g_iCmdPage[i]) {
		char s[512];
		CmdPanel_Text(i, s, sizeof(s));
		Hud_Chan(i, HUD_CH_EXTRA, 0.02, 0.28, 255, 220, 150, s);
		return;
	}
	if (g_fActionUntil[i] > GetGameTime() && g_sAction[i][0]) {
		Hud_Chan(i, HUD_CH_EXTRA, -1.0, 0.72, 255, 230, 170, g_sAction[i]);
		return;
	}
	if (g_fJoinUntil > GetGameTime() && g_sJoinHold[0]) {
		Hud_Chan(i, HUD_CH_EXTRA, 0.68, 0.88, 255, 214, 120, g_sJoinHold);
		return;
	}
	if (g_eCommander[i].bEnabled) {
		if (!g_eCommander[i].sCursor[0]) g_eCommander[i].sCursor = "+";
		int r = g_iCursorCol[i][0], g = g_iCursorCol[i][1], b = g_iCursorCol[i][2];
		if (r + g + b == 0) { r = 255; g = 255; b = 255; }
		Hud_Chan(i, HUD_CH_EXTRA, g_eCommander[i].fMouse[0] - 0.01, g_eCommander[i].fMouse[1] - 0.02, r, g, b, g_eCommander[i].sCursor);
		return;
	}
	Hud_ClearChan(i, HUD_CH_EXTRA);
}

void Hud_Action(int iClient, const char[] sFmt, any ...) {
	char sBuf[256];
	VFormat(sBuf, sizeof(sBuf), sFmt, 3);
	if (iClient < 1 || iClient > MaxClients) return;
	strcopy(g_sAction[iClient], sizeof(g_sAction[]), sBuf);
	g_fActionUntil[iClient] = GetGameTime() + 2.0;
}

void Hud_LobbyText(int iClient, char[] s, int n) {
	char sT[48], sCT[48], sHost[48] = "-";
	CmdrSettingName(CS_TEAM_T, sT, sizeof(sT)); CmdrSettingName(CS_TEAM_CT, sCT, sizeof(sCT));
	int iHost = Lobby_Host();
	if (iHost) FormatEx(sHost, sizeof(sHost), "%N", iHost);
	FormatEx(s, n, "CSS RTS  -  LOBBY\nHost: %s\n \nMode: %s\nPool %d  |  %d min\n%d per team, bots %s\n",
		sHost, g_sModeNames[g_eMode], g_iSetPool, g_iSetMinutes, g_iSetBots, g_sDiffNames[g_iSetDifficulty]);
	if (g_eMode == Mode_IntelRace) Format(s, n, "%sTarget: %d Intel\n", s, g_iSetIntelTarget);
	if (g_iSetSeries > 1) Format(s, n, "%sBest of %d  (T %d : %d CT)\n", s, g_iSetSeries, g_iSeriesWins[CS_TEAM_T], g_iSeriesWins[CS_TEAM_CT]);
	Format(s, n, "%sT Cmdr: %s\nCT Cmdr: %s\n \n", s, sT, sCT);
	if (g_eGame == GS_Countdown) Format(s, n, "%sSTARTING IN %d", s, RoundToCeil(g_fCountdownEnd - GetGameTime()));
	else if (iClient == iHost) StrCat(s, n, "F2 = setup menu");
	else StrCat(s, n, "Waiting for the host");
}

void Hud_ResearchLine(int t, char[] s, int n, bool bOneLine) {
	s[0] = 0;
	int u = g_iResearchId[t];
	if (u < 0) return;
	float fTotal = float(Unlock_Seconds(u));
	float fLeft = g_fResearchEnd[t] - GetGameTime();
	if (fLeft < 0.0) fLeft = 0.0;
	float fFrac = fTotal > 0.0 ? (fTotal - fLeft) / fTotal : 1.0;
	int iFill = RoundToFloor(fFrac * 10.0);
	if (iFill < 0) iFill = 0;
	if (iFill > 10) iFill = 10;
	char sBar[12], sName[40];
	for (int i=0; i<10; i++) sBar[i] = i < iFill ? '#' : '.';
	sBar[10] = 0;
	Unlock_ShortName(u, sName, sizeof(sName));
	int iPct = RoundToFloor(fFrac * 100.0);
	FormatEx(s, n, "%s\n%d%%    %ds left", sName, iPct, RoundToCeil(fLeft));
}

int Hud_Income(int t) {
	return g_iLastIncome[t] > 0 ? g_iLastIncome[t] : ComputeIntelIncome(t);
}

int Hud_Clock() {
	int iLeft = g_fMatchEnd > 0.0 ? RoundToCeil(g_fMatchEnd - GetGameTime()) : 0;
	return iLeft < 0 ? 0 : iLeft;
}

// Commander: short block at the top, left of the scoreboard.
void Hud_LiveText(int iClient, int t, char[] s, int n) {
	int iEnemy = t == CS_TEAM_T ? CS_TEAM_CT : CS_TEAM_T;
	if (g_eGame == GS_Ended) { FormatEx(s, n, "GAME OVER"); return; }
	FormatEx(s, n, "INTEL %d    +%d/s", g_iIntel[t], Hud_Income(t));
	if (g_eMode == Mode_IntelRace) Format(s, n, "%s\nRace %d/%d", s, g_iIntelEarned[t], g_iSetIntelTarget);
	else if (g_eMode == Mode_Workers) Format(s, n, "%s\nWorkers %d / %d", s, Npc_Count(Npc_Worker, t), Npc_Count(Npc_Worker, iEnemy));
	Train_AppendHud(t, s, n);
	if (!IsPlayerAlive(iClient) && g_iUnitPool[t] <= 0 && !GetCommanderTeam(iClient)) StrCat(s, n, "\nNO REINFORCEMENTS");
}

// Boots on the ground: one fact per line, mid-right, clear of the radar and the weapon.
void Hud_SoldierText(int iClient, int t, char[] s, int n) {
	int iEnemy = t == CS_TEAM_T ? CS_TEAM_CT : CS_TEAM_T;
	if (g_eGame == GS_Ended) { FormatEx(s, n, "GAME OVER"); return; }
	int iClock = Hud_Clock();
	int iMine = t == CS_TEAM_T ? g_iUnitPool[CS_TEAM_T] : g_iUnitPool[CS_TEAM_CT];
	int iOther = t == CS_TEAM_T ? g_iUnitPool[CS_TEAM_CT] : g_iUnitPool[CS_TEAM_T];
	FormatEx(s, n, "Intel %d\n+%d/s total\n \n%s %d left\n%s %d left\n%d:%02d", g_iIntel[t], Hud_Income(t), t == CS_TEAM_T ? "T" : "CT", iMine, t == CS_TEAM_T ? "CT" : "T", iOther, iClock / 60, iClock % 60);
	if (g_hCvarHQ.BoolValue && g_ePost[t].bValid) Format(s, n, "%s\nHQ %d%%", s, HQ_Percent(t));
	if (g_eMode == Mode_HQ) Format(s, n, "%s\nEnemy HQ %d%%", s, HQ_Percent(iEnemy));
	char sRes[96];
	Hud_ResearchLine(t, sRes, sizeof(sRes), false);
	if (sRes[0]) Format(s, n, "%s\n \n%s", s, sRes);
	Train_AppendHud(t, s, n);
	if (!IsPlayerAlive(iClient) && g_iUnitPool[t] <= 0) StrCat(s, n, "\nNO REINFORCEMENTS");
}

void Hud_Frames(int c, int t, char[] s, int n) {
	int iUnits[96];
	int m = Markers_CollectUnits(t, iUnits, sizeof(iUnits));
	s[0] = 0;
	int iShown;
	for (int k = 0; k < m && iShown < 8; k++) {
		int iHp, iMax = 100;
		char sName[24];
		if (iUnits[k] <= MaxClients) {
			iHp = GetClientHealth(iUnits[k]);
			FormatEx(sName, sizeof(sName), "%N", iUnits[k]);
		} else {
			int slot = Npc_FromEntity(iUnits[k]);
			if (slot == -1) continue;
			iHp = g_eNpc[slot].iHealth;
			iMax = g_eNpc[slot].iMaxHealth > 0 ? g_eNpc[slot].iMaxHealth : 60;
			if (g_eNpc[slot].eKind == Npc_Soldier) Train_Label(slot, sName, sizeof(sName));
			else FormatEx(sName, sizeof(sName), "Worker %d", slot + 1);
		}
		bool bSel = IsUnitSelected(c, iUnits[k]);
		Format(s, n, "%s%s%s - %d HP\n", s, bSel ? "> " : "", sName, iHp);
		iShown++;
	}
}

void Hud_CommanderText(int c, int t, char[] s, int n) {
	int iUnits[96];
	int m = Markers_CollectUnits(t, iUnits, sizeof(iUnits));
	int iSel, iBots, iWorkers;
	char sList[320], sLine[48];
	int iShown;
	for (int k = 0; k < m; k++) {
		if (iUnits[k] <= MaxClients) iBots++; else iWorkers++;
		bool bSel = IsUnitSelected(c, iUnits[k]);
		if (bSel) iSel++;
		if (iShown < 6) {
			UnitLabel(iUnits[k], sLine, sizeof(sLine));
			Format(sList, sizeof(sList), "%s%s%s   ", sList, bSel ? "* " : "", sLine);
			iShown++;
		}
	}
	FormatEx(s, n, "WORKERS %d/%d      BOTS %d      SELECTED %d", iWorkers, g_hCvarWorkerCap.IntValue, iBots, iSel);
	int iOff = g_iOffscreen[c][0] + g_iOffscreen[c][1] + g_iOffscreen[c][2] + g_iOffscreen[c][3];
	if (iOff) Format(s, n, "%s      off  L%d U%d R%d D%d", s, g_iOffscreen[c][0], g_iOffscreen[c][1], g_iOffscreen[c][2], g_iOffscreen[c][3]);
	if (m > iShown) Format(sList, sizeof(sList), "%s+%d", sList, m - iShown);
	if (Hud_HelpVisible(c)) StrCat(s, n, "\nWASD pan    Wheel height    Q/E rotate    LMB select    RMB move    F2 menu    H hide");
	else if (sList[0]) Format(s, n, "%s\n%s", s, sList);
	else StrCat(s, n, "\nF2 menu     H controls");
}

public Action Timer_HudPanel(Handle hTimer) {
	if (g_eGame == GS_Live) {
		CS_SetTeamScore(CS_TEAM_CT, g_iUnitPool[CS_TEAM_CT]);
		CS_SetTeamScore(CS_TEAM_T, g_iUnitPool[CS_TEAM_T]);
	}
	for (int i=1; i<=MaxClients; i++) {
		if (!IsClientInGame(i) || IsFakeClient(i)) continue;
		int t = GetClientTeam(i);
		if (InLobby() && GetClientMenu(i) != MenuSource_None && g_eGame != GS_Countdown) continue;
		if (!g_bHudMini && t >= CS_TEAM_T && t <= CS_TEAM_CT) {
			if (g_iLiveMenu[i] == 9) Research_ShowStatus(i);
			Menu_Tick(i);
		}
	}
	return Plugin_Continue;
}

// Build the panel text exactly like the timer does (for selftest / console checks)
void Hud_Build(int i, char[] s, int n, bool bForceView=false) {
	s[0] = '\0';
	int t = GetClientTeam(i);
	if (InLobby()) { Hud_LobbyText(i, s, n); return; }
	if (!(CS_TEAM_T <= t <= CS_TEAM_CT)) return;
	Hud_LiveText(i, t, s, n);
	bool bView = bForceView || g_eCommander[i].bEnabled;
	if (bView) {
		char sBot[512];
		Hud_CommanderText(i, t, sBot, sizeof(sBot));
		Format(s, n, "%s\n%s", s, sBot);
	} else {
		int iCmdr = GetTeamCommander(t);
		if (iCmdr && iCmdr != i) Format(s, n, "%s\nCommander: %N", s, iCmdr);
		else if (!iCmdr) StrCat(s, n, "\nNo Commander (!commander)");
		else StrCat(s, n, "\nYou command  (F2)");
	}
	if (!bView && g_hCvarStockpile.BoolValue && IsPlayerAlive(i) && GetEntProp(i, Prop_Send, "m_bInBuyZone")) Armory_HudText(t, s, n);
}

// lines / longest line (characters, UTF-8 aware)
void Hud_Measure(const char[] s, int &iLines, int &iLongest) {
	iLines = 1; iLongest = 0;
	int iCur;
	for (int k=0; s[k]; k++) {
		if (s[k] == '\n') { iLines++; if (iCur > iLongest) iLongest = iCur; iCur = 0; continue; }
		if ((s[k] & 0xC0) != 0x80) iCur++;
	}
	if (iCur > iLongest) iLongest = iCur;
}

public Action cmdDebugHud(int iClient, int iArgs) {
	iClient = ResolveClient(iClient);
	if (!HasRTSAccess(iClient)) return Plugin_Handled;
	char sT[64], sV[8]; GetCmdArg(1, sT, sizeof(sT)); GetCmdArg(2, sV, sizeof(sV));
	int iTarget = FindTarget(iClient, sT, false, false);
	if (iTarget <= 0) return Plugin_Handled;
	char s[1024];
	Hud_Build(iTarget, s, sizeof(s), StrEqual(sV, "view"));
	int iLines, iLong;
	Hud_Measure(s, iLines, iLong);
	ReplyToCommand(iClient, "[RTS] HUD panel for %N (%d lines, longest %d chars):\n%s", iTarget, iLines, iLong, s);
	return Plugin_Handled;
}
