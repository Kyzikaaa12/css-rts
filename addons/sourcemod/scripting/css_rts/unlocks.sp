// css_rts/unlocks.sp -- Commander unlock economy (v0.4).
// At match start only the default pistols (glock / usp) and ammo are buyable. The Commander spends
// Intel in the Unlocks menu to open grenades, weapon tiers, armour tiers and team upgrades.

#define MAX_UNLOCKS 40

enum struct UnlockDef {
	char sKey[16];
	char sName[48];
	int iCost;
	int iRequires;      // index of a prerequisite unlock, -1 = none
	char sItems[32];
	int iCat;
}

UnlockDef g_eUnlock[MAX_UNLOCKS];
int g_iUnlocks;
bool g_bUnlocked[4][MAX_UNLOCKS];
ConVar g_hCvarUnlocks;
ConVar g_hCvarUnlockScale;
ConVar g_hCvarStimsHP;

int AddUnlock(const char[] sKey, const char[] sName, int iCost, int iRequires, const char[] sItems, int iCat) {
	UnlockDef e;
	strcopy(e.sKey, sizeof(e.sKey), sKey);
	strcopy(e.sName, sizeof(e.sName), sName);
	e.iCost = iCost;
	e.iRequires = iRequires;
	strcopy(e.sItems, sizeof(e.sItems), sItems);
	e.iCat = iCat;
	g_eUnlock[g_iUnlocks] = e;
	return g_iUnlocks++;
}

int g_iUnlockStims = -1;
int g_iUnlockTraining = -1;
int g_iResearchId[4] = {-1, ...};
float g_fResearchEnd[4];
int g_iQueue[4][6];
int g_iQueueN[4];
float g_fResearchDoneUntil[4];
char g_sResearchDone[4][48];

void Unlocks_Init() {
	g_hCvarUnlocks = CreateConVar("css_rts_unlocks", "1", "1 = Commander unlock economy (only default pistols at start); 0 = everything buyable", _, true, 0.0, true, 1.0);
	g_hCvarUnlockScale = CreateConVar("css_rts_unlock_cost_scale", "1.0", "Multiplier for all unlock Intel costs", _, true, 0.0);
	g_hCvarStimsHP = CreateConVar("css_rts_stims_hp", "15", "Extra spawn health granted by the Combat stims upgrade", _, true, 0.0, true, 100.0);
	g_iUnlocks = 0;
	AddUnlock("p228", "P228", 80, -1, "p228", 0);
	AddUnlock("deagle", "Desert Eagle", 120, -1, "deagle", 0);
	AddUnlock("elite", "Dual Elites", 100, -1, "elite", 0);
	AddUnlock("fiveseven", "Five-SeveN", 80, -1, "fiveseven", 0);
	AddUnlock("mac10", "MAC-10", 140, -1, "mac10", 1);
	AddUnlock("tmp", "TMP", 140, -1, "tmp", 1);
	AddUnlock("mp5", "MP5", 180, -1, "mp5navy", 1);
	AddUnlock("ump", "UMP-45", 180, -1, "ump45", 1);
	AddUnlock("p90", "P90", 220, -1, "p90", 1);
	AddUnlock("m3", "M3", 160, -1, "m3", 2);
	AddUnlock("xm1014", "XM1014", 200, -1, "xm1014", 2);
	AddUnlock("galil", "Galil", 280, -1, "galil", 3);
	AddUnlock("famas", "FAMAS", 280, -1, "famas", 3);
	AddUnlock("scout", "Scout", 320, -1, "scout", 3);
	AddUnlock("ak47", "AK-47", 420, -1, "ak47", 3);
	AddUnlock("m4a1", "M4A1", 420, -1, "m4a1", 3);
	AddUnlock("sg552", "SG 552 Bullpup (T)", 480, -1, "sg552", 3);
	AddUnlock("aug", "AUG Bullpup (CT)", 480, -1, "aug", 3);
	AddUnlock("awp", "AWP", 700, -1, "awp", 4);
	AddUnlock("g3sg1", "G3SG1", 650, -1, "g3sg1", 4);
	AddUnlock("sg550", "SG 550", 650, -1, "sg550", 4);
	AddUnlock("m249", "M249", 600, -1, "m249", 4);
	AddUnlock("he", "HE grenade", 100, -1, "hegrenade", 5);
	AddUnlock("flash", "Flashbang", 80, -1, "flashbang", 5);
	AddUnlock("smoke", "Smoke", 80, -1, "smokegrenade", 5);
	int iKev = AddUnlock("kevlar", "Kevlar vest", 240, -1, "vest", 6);
	AddUnlock("helmet", "Kevlar + helmet", 240, iKev, "vesthelm", 6);
	AddUnlock("kit", "Defuse kit", 80, -1, "defuser", 7);
	AddUnlock("nvg", "Nightvision", 60, -1, "nvgs", 7);
	g_iUnlockStims = AddUnlock("stims", "Combat stims", 1200, -1, "", 8);
	g_iUnlockTraining = AddUnlock("training", "Worker training", 1200, -1, "", 8);
	HookEvent("player_spawn", Event_UnlocksSpawn);
}

void Unlocks_Reset() {
	Armory_Reset();     // v0.6: stock + ability cooldowns reset with the tech tree (every game)
	Abilities_Reset();
	for (int t=0; t<4; t++) {
		for (int u=0; u<MAX_UNLOCKS; u++) g_bUnlocked[t][u] = false;
		g_iResearchId[t] = -1;
		g_fResearchEnd[t] = 0.0;
		g_iQueueN[t] = 0;
		g_fResearchDoneUntil[t] = 0.0;
		g_sResearchDone[t][0] = 0;
	}
}

void Unlocks_MapStart() {
	PrecacheSound("buttons/button9.wav", true);
	BuyMenu_Sync();
}

void Unlocks_Tick() {
	float fNow = GetGameTime();
	for (int t=CS_TEAM_T; t<=CS_TEAM_CT; t++) {
		int u = g_iResearchId[t];
		if (u < 0 || fNow < g_fResearchEnd[t]) continue;
		g_bUnlocked[t][u] = true;
		g_iResearchId[t] = -1;
		strcopy(g_sResearchDone[t], sizeof(g_sResearchDone[]), g_eUnlock[u].sName);
		for (int i = 1; i <= MaxClients; i++) if (IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) == t) EmitSoundToClient(i, "buttons/button9.wav");
		int iGot = Armory_GrantResearch(t, g_eUnlock[u].sItems);
		if (iGot > 0) TeamChat(t, "\x04[RTS] RESEARCHED:\x01 \x03%s\x01 - x%d now in the buy shop.", g_eUnlock[u].sName, iGot);
		else TeamChat(t, "\x04[RTS] RESEARCHED:\x01 \x03%s\x01.", g_eUnlock[u].sName);
		if (g_iQueueN[t] > 0) {
			int iNext = g_iQueue[t][0];
			for (int q = 1; q < g_iQueueN[t]; q++) g_iQueue[t][q - 1] = g_iQueue[t][q];
			g_iQueueN[t]--;
			g_iResearchId[t] = iNext;
			g_fResearchEnd[t] = fNow + float(Unlock_Seconds(iNext));
			TeamChat(t, "\x04[RTS]\x01 Next: \x03%s\x01 (%d seconds, %d still queued).", g_eUnlock[iNext].sName, Unlock_Seconds(iNext), g_iQueueN[t]);
		} else g_fResearchDoneUntil[t] = fNow + 5.0;
		BuyMenu_Sync();
	}
}

int Unlock_Seconds(int u) {
	int s = RoundToNearest(Unlock_Cost(u) / 20.0);
	if (s < 16) s = 16;
	if (s > 48) s = 48;
	return s;
}

int Unlock_Cost(int u) {
	return RoundToCeil(g_eUnlock[u].iCost * g_hCvarUnlockScale.FloatValue * 1.4);
}

bool Unlock_Has(int iTeam, int u) {
	return u >= 0 && (!g_hCvarUnlocks.BoolValue || g_bUnlocked[iTeam][u]);
}

// Which unlock opens this buy item? -1 = always allowed (default pistols, ammo, unknown aliases).
int Unlock_ForItem(const char[] sItem) {
	char sNeedle[40];
	FormatEx(sNeedle, sizeof(sNeedle), " %s ", sItem);
	char sHay[168];
	for (int u=0; u<g_iUnlocks; u++) {
		if (!g_eUnlock[u].sItems[0]) continue;
		FormatEx(sHay, sizeof(sHay), " %s ", g_eUnlock[u].sItems);
		if (StrContains(sHay, sNeedle, false) != -1) return u;
	}
	return -1;
}

// Called from CS_OnBuyCommand (after the command-view block). true = block the purchase.
bool Unlocks_BlockBuy(int iClient, const char[] sWeapon) {
	if (!g_hCvarUnlocks.BoolValue) return false;
	int t = GetClientTeam(iClient);
	if (!(CS_TEAM_T <= t <= CS_TEAM_CT)) return false;
	int u = Unlock_ForItem(sWeapon);
	if (u == -1 || g_bUnlocked[t][u]) return false;
	if (!IsFakeClient(iClient)) {
		PrintHintText(iClient, "LOCKED: %s\nYour Commander must unlock\n%s (%d Intel)", sWeapon, g_eUnlock[u].sName, Unlock_Cost(u));
		PrintToChat(iClient, "\x04[RTS]\x01 \x03%s\x01 is locked. Commander unlock needed: \x04%s\x01 (%d Intel).", sWeapon, g_eUnlock[u].sName, Unlock_Cost(u));
	}
	return true;
}

// Spend team Intel on an unlock. iClient may be 0 (debug/selftest).
bool Unlock_Buy(int iClient, int iTeam, int u, bool bFree=false) {
	if (u < 0 || u >= g_iUnlocks || g_bUnlocked[iTeam][u]) return false;
	int r = g_eUnlock[u].iRequires;
	if (r != -1 && !g_bUnlocked[iTeam][r]) {
		if (iClient) PrintToChat(iClient, "\x04[RTS]\x01 Requires \x04%s\x01 first.", g_eUnlock[r].sName);
		return false;
	}
	int iCost = Unlock_Cost(u);
	if (!bFree && g_iIntel[iTeam] < iCost) {
		if (iClient) PrintToChat(iClient, "\x04[RTS]\x01 Need %d Intel (have %d).", iCost, g_iIntel[iTeam]);
		return false;
	}
	for (int q = 0; q < g_iQueueN[iTeam]; q++) if (g_iQueue[iTeam][q] == u) return false;
	if (g_iResearchId[iTeam] != -1) {
		if (g_iQueueN[iTeam] >= 6) {
			if (iClient) PrintToChat(iClient, "\x04[RTS]\x01 Research queue is full.");
			return false;
		}
		if (!bFree && g_iIntel[iTeam] < iCost) {
			if (iClient) PrintToChat(iClient, "\x04[RTS]\x01 Need %d Intel (have %d).", iCost, g_iIntel[iTeam]);
			return false;
		}
		if (!bFree) g_iIntel[iTeam] -= iCost;
		g_iQueue[iTeam][g_iQueueN[iTeam]++] = u;
		if (iClient) PrintHintText(iClient, "Queued %s\n%d in line", g_eUnlock[u].sName, g_iQueueN[iTeam]);
		VsAi_MirrorUnlock(iTeam, u);
		return true;
	}
	if (!bFree) g_iIntel[iTeam] -= iCost;
	if (bFree) {
		g_bUnlocked[iTeam][u] = true;
		VsAi_MirrorUnlock(iTeam, u);
		return true;
	}
	g_iResearchId[iTeam] = u;
	g_fResearchEnd[iTeam] = GetGameTime() + float(Unlock_Seconds(u));
	if (iClient) PrintHintText(iClient, "%s\n%d seconds", g_eUnlock[u].sName, Unlock_Seconds(u));
	VsAi_MirrorUnlock(iTeam, u);
	return true;
}

void VsAi_MirrorUnlock(int iTeam, int u) {
	if (!VsAi_FromPlayer(iTeam)) return;
	int e = VsAi_Enemy();
	if (e < CS_TEAM_T || e > CS_TEAM_CT || u < 0 || u >= g_iUnlocks) return;
	if (g_bUnlocked[e][u] || g_iResearchId[e] == u) return;
	for (int q = 0; q < g_iQueueN[e]; q++) if (g_iQueue[e][q] == u) return;
	g_bVsAiBusy = true;
	int iCost = Unlock_Cost(u);
	int iHad = g_iIntel[e];
	if (iHad < iCost) g_iIntel[e] = iCost;
	bool bOk = Unlock_Buy(0, e, u, false);
	if (!bOk) g_iIntel[e] = iHad;
	else if (iHad < iCost) g_iIntel[e] = 0;
	g_bVsAiBusy = false;
}

int g_iMenuSeenResearch[MAXPLAYERS+1];
int g_iLiveMenu[MAXPLAYERS+1];
int g_iLiveCat[MAXPLAYERS+1];
bool g_bMenuRefreshing[MAXPLAYERS+1];

void Research_Bar(int iFilled, char[] s, int n) {
	if (iFilled < 0) iFilled = 0;
	if (iFilled > 16) iFilled = 16;
	s[0] = 0;
	for (int i = 0; i < iFilled; i++) StrCat(s, n, "#");
	for (int i = iFilled; i < 16; i++) StrCat(s, n, "-");
}

void Research_FillHud(int t, char[] s, int n) {
	s[0] = 0;
	if (t < CS_TEAM_T || t > CS_TEAM_CT) return;
	float fNow = GetGameTime();
	bool bWork = g_iResearchId[t] >= 0;
	bool bLinger = !bWork && g_iQueueN[t] <= 0 && g_fResearchDoneUntil[t] > fNow;
	if (!bWork && !bLinger) return;
	char sBar[20], sName[48];
	if (bLinger) {
		Research_Bar(16, sBar, sizeof(sBar));
		FormatEx(s, n, "RESEARCH\ntick done\n%s\n%s", g_sResearchDone[t], sBar);
		return;
	}
	int u = g_iResearchId[t];
	Unlock_ShortName(u, sName, sizeof(sName));
	int iTotal = Unlock_Seconds(u);
	int iLeft = RoundToCeil(g_fResearchEnd[t] - fNow);
	if (iLeft < 0) iLeft = 0;
	if (iLeft > iTotal) iLeft = iTotal;
	int iFilled = iTotal > 0 ? (iTotal - iLeft) * 16 / iTotal : 16;
	Research_Bar(iFilled, sBar, sizeof(sBar));
	FormatEx(s, n, "RESEARCH\n%s\n%s\n%ds left", sName, sBar, iLeft);
	if (g_iQueueN[t] > 0) {
		StrCat(s, n, "\nQueue");
		for (int q = 0; q < g_iQueueN[t] && q < 4; q++) {
			Unlock_ShortName(g_iQueue[t][q], sName, sizeof(sName));
			Format(s, n, "%s\n%s", s, sName);
		}
	}
}

void Research_ShowStatus(int iClient) {
	if (iClient > 0 && g_iLiveMenu[iClient] == 9) {
		g_iLiveMenu[iClient] = 0;
		CancelClientMenu(iClient, true);
	}
}

public int MenuHandler_ResearchBox(Menu hMenu, MenuAction eAction, int iClient, int iItem) {
	if (eAction == MenuAction_End) delete hMenu;
	else if (eAction == MenuAction_Cancel && !Menu_Refreshing(iClient)) g_iLiveMenu[iClient] = 0;
	return 0;
}
float g_fMenuRefresh[MAXPLAYERS+1];

void Menu_Mark(int iClient, int iKind) {
	g_iLiveMenu[iClient] = iKind;
}

bool Menu_Refreshing(int iClient) {
	if (!g_bMenuRefreshing[iClient]) return false;
	g_bMenuRefreshing[iClient] = false;
	return true;
}

void Unlock_CatName(int iCat, char[] s, int n) {
	static const char sCats[][] = {"Pistols", "SMGs", "Shotguns", "Rifles", "Heavy", "Grenades", "Armour", "Gear", "Upgrades"};
	if (iCat < 0 || iCat >= sizeof(sCats)) strcopy(s, n, "Research");
	else strcopy(s, n, sCats[iCat]);
}

void Unlocks_ShowMenu(int iClient) {
	if (Menu_Hold(iClient)) return;
	int t = GetClientTeam(iClient);
	Menu hMenu = new Menu(MenuHandler_Unlocks);
	char sTitle[180];
	FormatEx(sTitle, sizeof(sTitle), "RESEARCH    Intel %d\nOne at a time. Open a group.\n", g_iIntel[t]);
	if (g_iResearchId[t] != -1) {
		char sNow[40];
		Unlock_ShortName(g_iResearchId[t], sNow, sizeof(sNow));
		int iSec = Unlock_Seconds(g_iResearchId[t]);
		int iLeft = RoundToCeil(g_fResearchEnd[t] - GetGameTime());
		if (iLeft < 0) iLeft = 0;
		int iPct = iSec > 0 ? (100 * (iSec - iLeft)) / iSec : 100;
		Format(sTitle, sizeof(sTitle), "%s%s   %d%%   %ds\n", sTitle, sNow, iPct, iLeft);
	}
	hMenu.SetTitle(sTitle);
	hMenu.Pagination = MENU_NO_PAGINATION;
	hMenu.ExitButton = true;
	for (int c = 0; c < 9; c++) {
		int iOwn, iAll;
		for (int u = 0; u < g_iUnlocks; u++) {
			if (g_eUnlock[u].iCat != c) continue;
			int iSide = g_eUnlock[u].sItems[0] ? Armory_Side(g_eUnlock[u].sItems) : 0;
			if (iSide != 0 && iSide != t) continue;
			iAll++;
			if (g_bUnlocked[t][u]) iOwn++;
		}
		if (!iAll) continue;
		char sName[24], sItem[48], sInfo[8];
		Unlock_CatName(c, sName, sizeof(sName));
		FormatEx(sItem, sizeof(sItem), "%s    %d/%d", sName, iOwn, iAll);
		FormatEx(sInfo, sizeof(sInfo), "c%d", c);
		hMenu.AddItem(sInfo, sItem);
	}
	hMenu.ExitBackButton = false;
	hMenu.Display(iClient, MENU_TIME_FOREVER);
	g_iMenuSeenResearch[iClient] = g_iResearchId[t];
	Menu_Mark(iClient, 3);
}

void Unlocks_ShowCat(int iClient, int iCat) {
	if (Menu_Hold(iClient)) return;
	int t = GetClientTeam(iClient);
	Menu hMenu = new Menu(MenuHandler_Unlocks);
	char sCat[24], sTitle[180];
	Unlock_CatName(iCat, sCat, sizeof(sCat));
	FormatEx(sTitle, sizeof(sTitle), "%s    Intel %d\n", sCat, g_iIntel[t]);
	if (g_iResearchId[t] != -1) {
		char sNow[40];
		Unlock_ShortName(g_iResearchId[t], sNow, sizeof(sNow));
		Format(sTitle, sizeof(sTitle), "%sWorking  %s  %ds\n", sTitle, sNow, RoundToCeil(g_fResearchEnd[t] - GetGameTime()));
	}
	hMenu.SetTitle(sTitle);
	for (int u = 0; u < g_iUnlocks; u++) {
		if (g_eUnlock[u].iCat != iCat) continue;
		int iSide = g_eUnlock[u].sItems[0] ? Armory_Side(g_eUnlock[u].sItems) : 0;
		if (iSide != 0 && iSide != t) continue;
		char sItem[72], sInfo[8], sShort[40];
		Unlock_ShortName(u, sShort, sizeof(sShort));
		int iDraw = ITEMDRAW_DEFAULT;
		int r = g_eUnlock[u].iRequires;
		if (g_bUnlocked[t][u]) { FormatEx(sItem, sizeof(sItem), "Done    %s", sShort); iDraw = ITEMDRAW_DISABLED; }
		else if (u == g_iResearchId[t]) { FormatEx(sItem, sizeof(sItem), "%s    %ds", sShort, RoundToCeil(g_fResearchEnd[t] - GetGameTime())); iDraw = ITEMDRAW_DISABLED; }
		else if (r != -1 && !g_bUnlocked[t][r]) {
			char sReq[40]; Unlock_ShortName(r, sReq, sizeof(sReq));
			FormatEx(sItem, sizeof(sItem), "Needs %s    %s", sReq, sShort);
			iDraw = ITEMDRAW_DISABLED;
		} else {
			FormatEx(sItem, sizeof(sItem), "%s    %d Intel    %ds", sShort, Unlock_Cost(u), Unlock_Seconds(u));
			if (g_iIntel[t] < Unlock_Cost(u)) iDraw = ITEMDRAW_DISABLED;
		}
		IntToString(u, sInfo, sizeof(sInfo));
		hMenu.AddItem(sInfo, sItem, iDraw);
	}
	hMenu.ExitBackButton = true;
	hMenu.Display(iClient, MENU_TIME_FOREVER);
	g_iLiveCat[iClient] = iCat;
	g_iMenuSeenResearch[iClient] = g_iResearchId[t];
	Menu_Mark(iClient, 4);
}

// "Tier 3: AK-47, M4A1, SG552, AUG" -> "Tier 3: AK-47, M4A1, SG552, AUG" is too long for a menu
// line; use the part before " (" and cap the length
void Unlock_ShortName(int u, char[] s, int n) {
	strcopy(s, n, g_eUnlock[u].sName);
	int p = StrContains(s, " (");
	if (p > 0) s[p] = '\0';
	if (strlen(s) > 30) { s[28] = '.'; s[29] = '.'; s[30] = '\0'; }
}

public int MenuHandler_Unlocks(Menu hMenu, MenuAction eAction, int iClient, int iItem) {
	if (eAction == MenuAction_End) {
		delete hMenu;
	} else if (eAction == MenuAction_Cancel) {
		if (Menu_Refreshing(iClient)) return 0;
		if (iItem == MenuCancel_ExitBack && GetCommanderTeam(iClient)) {
			if (g_iLiveMenu[iClient] == 4) Unlocks_ShowMenu(iClient);
			else ShowCommanderMenu(iClient);
		}
	} else if (eAction == MenuAction_Select) {
		int t = GetCommanderTeam(iClient);
		if (!t) return 0;
		char sInfo[8];
		hMenu.GetItem(iItem, sInfo, sizeof(sInfo));
		if (sInfo[0] == 'c') Unlocks_ShowCat(iClient, StringToInt(sInfo[1]));
		else {
			int iCat = g_iLiveCat[iClient];
			Unlock_Buy(iClient, t, StringToInt(sInfo));
			Unlocks_ShowCat(iClient, iCat);
		}
	}
	return 0;
}

public void Event_UnlocksSpawn(Event hEvent, const char[] sName, bool bDontBroadcast) {
	int iClient = GetClientOfUserId(hEvent.GetInt("userid"));
	if (!iClient || !IsClientInGame(iClient)) return;
	int t = GetClientTeam(iClient);
	if (CS_TEAM_T <= t <= CS_TEAM_CT && g_iUnlockStims != -1 && g_bUnlocked[t][g_iUnlockStims]) {
		CreateTimer(0.2, Timer_ApplyStims, GetClientUserId(iClient), TIMER_FLAG_NO_MAPCHANGE);
	}
	if (!IsFakeClient(iClient)) BuyMenu_Sync();
}

public Action Timer_ApplyStims(Handle hTimer, int iUserId) {
	int iClient = GetClientOfUserId(iUserId);
	if (iClient && IsClientInGame(iClient) && IsPlayerAlive(iClient) && !g_bBodyHidden[iClient]) {
		int iHP = 100 + g_hCvarStimsHP.IntValue;
		SetEntProp(iClient, Prop_Data, "m_iMaxHealth", iHP);
		SetEntityHealth(iClient, iHP);
	}
	return Plugin_Stop;
}

int Unlocks_WorkerBonus(int iTeam) {
	return (g_iUnlockTraining != -1 && g_bUnlocked[iTeam][g_iUnlockTraining]) ? 1 : 0;
}

int Unlocks_Count(int iTeam) {
	int n;
	for (int u=0; u<g_iUnlocks; u++) if (g_bUnlocked[iTeam][u]) n++;
	return n;
}

int Unlock_FindKey(const char[] sKey) {
	for (int u=0; u<g_iUnlocks; u++) if (StrEqual(g_eUnlock[u].sKey, sKey, false)) return u;
	return -1;
}
