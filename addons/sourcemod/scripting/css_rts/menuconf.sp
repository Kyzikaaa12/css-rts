// css_rts/menuconf.sp -- v0.5.4: main-menu "Create RTS Game" settings.
// The native Create Server dialog shows our options (custom/css_rts/cfg/settings_default.scr) on its Game tab and,
// when the player presses Start, GameUI saves the chosen values to cfg/settings.scr. The css_rts_m_* names are NOT
// plugin cvars (SourceMod isn't running yet when the dialog applies them), so we read that file at map start and
// preset the lobby from it. LIST values are written as indices; our list values equal their index on purpose.

bool g_bMenuAutoStart;
float g_fMenuHostSeen;
int g_iMenuApplied;           // how many css_rts_m_* keys were applied at the last map start
char g_sMenuSource[64];

void MenuConf_Init() {
	RegConsoleCmd("sm_rts_debug_menuconf", cmdDebugMenuConf, "Re-read cfg/settings.scr (Create RTS Game dialog values) [path] and show what was applied");
}

// minimal tokenizer for the .scr format: quoted strings, {, }, bare words
int Scr_NextToken(const char[] sBuf, int iPos, char[] sTok, int iTokLen) {
	int n = strlen(sBuf);
	while (iPos < n) {
		if (sBuf[iPos] == '/' && iPos + 1 < n && sBuf[iPos + 1] == '/') { while (iPos < n && sBuf[iPos] != '\n') iPos++; continue; }
		if (sBuf[iPos] <= ' ') { iPos++; continue; }
		break;
	}
	if (iPos >= n) { sTok[0] = 0; return -1; }
	int k = 0;
	if (sBuf[iPos] == '"') {
		iPos++;
		while (iPos < n && sBuf[iPos] != '"') { if (k < iTokLen - 1) sTok[k++] = sBuf[iPos]; iPos++; }
		sTok[k] = 0;
		return iPos + 1;
	}
	if (sBuf[iPos] == '{' || sBuf[iPos] == '}') { sTok[0] = sBuf[iPos]; sTok[1] = 0; return iPos + 1; }
	while (iPos < n && sBuf[iPos] > ' ' && sBuf[iPos] != '{' && sBuf[iPos] != '}' && sBuf[iPos] != '"') { if (k < iTokLen - 1) sTok[k++] = sBuf[iPos]; iPos++; }
	sTok[k] = 0;
	return iPos;
}

// Reads every top-level "css_rts_m_*" { "prompt" { type } { "value" } }.
// LIST saves an index. NUMBER / BOOL / STRING save the value itself. hType gets LIST, NUMBER, BOOL, or STRING.
int MenuConf_Read(const char[] sPath, StringMap hOut, StringMap hType) {
	File f = OpenFile(sPath, "r", true, NULL_STRING);
	if (!f) return -1;
	static char sBuf[32768];
	int iLen = f.ReadString(sBuf, sizeof(sBuf), -1);
	delete f;
	if (iLen <= 0) return 0;
	sBuf[iLen < sizeof(sBuf) ? iLen : sizeof(sBuf) - 1] = 0;
	char sTok[128], sName[64], sLast[64], sType[16];
	int iPos = 0, iDepth = 0, n = 0;
	sName[0] = 0;
	sType[0] = 0;
	while ((iPos = Scr_NextToken(sBuf, iPos, sTok, sizeof(sTok))) != -1) {
		if (StrEqual(sTok, "{")) { iDepth++; continue; }
		if (StrEqual(sTok, "}")) {
			iDepth--;
			if (iDepth == 1 && sName[0]) {   // end of a cvar block: the last value token is the chosen setting
				hOut.SetString(sName, sLast);
				if (hType) hType.SetString(sName, sType);
				n++;
				sName[0] = 0;
				sType[0] = 0;
			}
			continue;
		}
		if (iDepth == 1) {
			if (StrContains(sTok, "css_rts_m_", false) == 0) {
				strcopy(sName, sizeof(sName), sTok);
				sType[0] = 0;
				sLast[0] = 0;
			}
			else sName[0] = 0;
		}
		else if (iDepth == 3) {
			if (StrEqual(sTok, "LIST") || StrEqual(sTok, "NUMBER") || StrEqual(sTok, "BOOL") || StrEqual(sTok, "STRING")) strcopy(sType, sizeof(sType), sTok);
			else strcopy(sLast, sizeof(sLast), sTok);
		}
	}
	return n;
}

int MenuConf_Int(StringMap h, const char[] sKey, int iDef) {
	char s[32];
	if (!h.GetString(sKey, s, sizeof(s)) || !s[0]) return iDef;
	g_iMenuApplied++;
	return StringToInt(s);
}

int MenuConf_Pick(int iIdx, const int[] iValues, int iCount, int iDef) {
	if (iIdx >= 0 && iIdx < iCount) return iValues[iIdx];
	return iDef;
}

// LIST still stores an index (older Create Server files). NUMBER stores the value.
// iMissing is returned when the key is absent. A present value is clamped to iMin..iMax.
int MenuConf_Value(StringMap h, StringMap hType, const char[] sKey, const int[] iList, int iCount, int iMin, int iMax, int iMissing) {
	char sType[16];
	int iRaw = MenuConf_Int(h, sKey, -99999);
	if (iRaw == -99999) return iMissing;
	if (hType) hType.GetString(sKey, sType, sizeof(sType));
	int v = StrEqual(sType, "LIST") ? MenuConf_Pick(iRaw, iList, iCount, iMissing) : iRaw;
	if (v < iMin) v = iMin;
	if (v > iMax) v = iMax;
	return v;
}

int VsAi_PlayerTeam() {
	char s[8];
	g_hCvarHostTeam.GetString(s, sizeof(s));
	if (StrEqual(s, "t", false)) return CS_TEAM_T;
	if (StrEqual(s, "ct", false)) return CS_TEAM_CT;
	for (int i = 1; i <= MaxClients; i++) {
		if (!IsClientInGame(i) || IsFakeClient(i)) continue;
		int t = GetClientTeam(i);
		if (t == CS_TEAM_T || t == CS_TEAM_CT) return t;
	}
	return 0;
}

int VsAi_Enemy() {
	int t = VsAi_PlayerTeam();
	if (t == CS_TEAM_T) return CS_TEAM_CT;
	if (t == CS_TEAM_CT) return CS_TEAM_T;
	return 0;
}

bool VsAi_FromPlayer(int iTeam) {
	return g_bVsAi && !g_bVsAiBusy && iTeam >= CS_TEAM_T && iTeam <= CS_TEAM_CT && iTeam == VsAi_PlayerTeam();
}

void MenuConf_Apply(const char[] sPath="cfg/settings.scr") {
	g_iMenuApplied = 0;
	g_bMenuAutoStart = false;
	g_bVsAi = false;
	strcopy(g_sMenuSource, sizeof(g_sMenuSource), sPath);
	StringMap h = new StringMap();
	StringMap hType = new StringMap();
	int n = MenuConf_Read(sPath, h, hType);
	if (n <= 0) { g_bUsedCreateSettings = false; delete hType; delete h; LogMessage("[RTS] menu settings: %s has no css_rts_m_* values (%d) -> lobby defaults", sPath, n); return; }
	g_bUsedCreateSettings = true;
	static int iPools[] = {100, 200, 300}, iTimes[] = {30, 40, 45}, iSeries[] = {1, 3, 5}, iTargets[] = {6000, 10000, 15000};
	static int iCaps[] = {4, 6, 8, 12}, iStart[] = {0, 200, 400, 800}, iIncome[] = {5, 10, 15};
	g_eMode = Mode_HQ;
	g_iSetPool = MenuConf_Value(h, hType, "css_rts_m_pool", iPools, 3, 0, 5000, g_iSetPool);
	g_iSetMinutes = MenuConf_Value(h, hType, "css_rts_m_time", iTimes, 3, 0, 180, g_iSetMinutes);
	int iPlayers = MenuConf_Int(h, "css_rts_m_players", -1);
	if (0 <= iPlayers <= 16) g_iSetBots = iPlayers;
	int iDiff = MenuConf_Int(h, "css_rts_m_difficulty", g_iSetDifficulty);
	if (0 <= iDiff <= 3) g_iSetDifficulty = iDiff;
	g_iSetSeries = MenuConf_Pick(MenuConf_Int(h, "css_rts_m_series", -1), iSeries, 3, g_iSetSeries);
	g_iSetIntelTarget = MenuConf_Pick(MenuConf_Int(h, "css_rts_m_target", -1), iTargets, 3, g_iSetIntelTarget);
	int iTeam = MenuConf_Int(h, "css_rts_m_hostteam", -1);
	if (iTeam >= 0) g_hCvarHostTeam.SetString(iTeam == 1 ? "t" : (iTeam == 2 ? "auto" : "ct"));
	g_bSetHQLoss = true;
	int iHQ = MenuConf_Int(h, "css_rts_m_hq", -1);
	if (iHQ >= 0) g_hCvarHQ.SetInt(iHQ != 0 ? 1 : 0);
	g_bMenuAutoStart = MenuConf_Int(h, "css_rts_m_autostart", 0) != 0;
	int iCap = MenuConf_Value(h, hType, "css_rts_m_workercap", iCaps, 4, 0, 32, -1);
	if (iCap >= 0) g_hCvarWorkerCap.SetInt(iCap);
	int iStartIntel = MenuConf_Value(h, hType, "css_rts_m_startintel", iStart, 4, 0, 20000, -1);
	if (iStartIntel >= 0) g_hCvarIntelStart.SetInt(iStartIntel);
	int iPerSec = MenuConf_Value(h, hType, "css_rts_m_income", iIncome, 3, 0, 100, -1);
	if (iPerSec >= 0) g_hCvarIntelBase.SetInt(iPerSec);
	g_hCvarUnitPool.IntValue = g_iSetPool;
	g_hCvarFpsPerTeam.IntValue = g_iSetBots;
	g_bVsAi = MenuConf_Int(h, "css_rts_m_play", 0) == 1;
	int iHand = MenuConf_Int(h, "css_rts_m_handicap", 0);
	if (iHand < 0 || iHand > 4) iHand = 0;
	g_iIncomeHandicap = iHand;
	g_iHandicapHost = iTeam == 1 ? CS_TEAM_T : (iTeam == 2 ? 0 : CS_TEAM_CT);
	char sWant[32], sCur[64];
	if (h.GetString("css_rts_m_map", sWant, sizeof(sWant))) {
		int iMap = StringToInt(sWant);
		strcopy(sWant, sizeof(sWant), iMap == 1 ? "de_dust2" : "cs_office");
		GetCurrentMap(sCur, sizeof(sCur));
		if (!StrEqual(sCur, sWant, false)) ServerCommand("changelevel %s", sWant);
	}
	delete hType;
	delete h;
	// css_rts.cfg is executed after OnMapStart and would put these cvars back to their file defaults.
	// Re-copy the banks while the match has not started. A live game keeps the Intel it already has.
	if (g_eGame != GS_Live) {
		for (int t = 0; t < 4; t++) g_iIntel[t] = g_hCvarIntelStart.IntValue;
		AutoJoin_ApplyHost();
	}
	char sTeam[8];
	g_hCvarHostTeam.GetString(sTeam, sizeof(sTeam));
	LogMessage("[RTS] menu settings from %s: %d values -> %s, pool %d, %d min, %d/team, %s bots, intel %d +%d/s, workers %d, host %s, autostart %d",
		sPath, g_iMenuApplied, g_bVsAi ? "Vs AI" : "Freeplay", g_iSetPool, g_iSetMinutes, g_iSetBots, g_sDiffNames[g_iSetDifficulty],
		g_hCvarIntelStart.IntValue, g_hCvarIntelBase.IntValue, g_hCvarWorkerCap.IntValue, sTeam, g_bMenuAutoStart);
}

// True while RTS Create is about to start the match, so the in-game setup menu stays closed.
bool MenuConf_HoldLobbyMenu() {
	return g_bMenuAutoStart || g_bUsedCreateSettings;
}

// called from Timer_Lobby every second while in the lobby
void MenuConf_LobbyTick() {
	if (!g_bMenuAutoStart || g_eGame != GS_Lobby) return;
	int iHost = Lobby_Host();
	if (!iHost || !IsPlayerAlive(iHost)) { g_fMenuHostSeen = 0.0; return; }
	if (g_fMenuHostSeen == 0.0) { g_fMenuHostSeen = GetGameTime(); return; }
	if (GetGameTime() - g_fMenuHostSeen < 3.0) return;
	g_bMenuAutoStart = false;
	LogMessage("[RTS] state: autostart (Create RTS Game: skip lobby)");
	Lobby_StartCountdown(iHost);
}

public Action cmdDebugMenuConf(int iClient, int iArgs) {
	iClient = ResolveClient(iClient);
	if (!HasRTSAccess(iClient)) return Plugin_Handled;
	char sPath[PLATFORM_MAX_PATH] = "cfg/settings.scr";
	if (iArgs >= 1) GetCmdArg(1, sPath, sizeof(sPath));
	MenuConf_Apply(sPath);
	char sTeam[8]; g_hCvarHostTeam.GetString(sTeam, sizeof(sTeam));
	ReplyToCommand(iClient, "[RTS] menuconf %s: %d values | mode %s pool %d time %d players %d diff %s series %d target %d hostteam %s hq %d hqloss %d autostart %d",
		sPath, g_iMenuApplied, g_sModeNames[view_as<int>(g_eMode)], g_iSetPool, g_iSetMinutes, g_iSetBots, g_sDiffNames[g_iSetDifficulty],
		g_iSetSeries, g_iSetIntelTarget, sTeam, g_hCvarHQ.IntValue, g_bSetHQLoss, g_bMenuAutoStart);
	return Plugin_Handled;
}
