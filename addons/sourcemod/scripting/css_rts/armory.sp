// css_rts/armory.sp -- v0.6 STOCKPILE ARMORY.
// The Commander buys stock with Intel in bundles (only for unlocked item types). Soldiers and bots
// can only buy stocked items; every successful buy takes one from the team stock (money still
// applies). Default pistols (glock/usp) and ammo are never stocked. Stock resets every game.

#define MAX_ARMORY 32

enum struct ArmoryItem {
	char sKey[16];       // CS buy name
	char sName[24];
	int iBundle;         // units per restock
	int iCost;           // Intel per bundle
	int iCat;            // 0 grenades, 1 gear, 2 pistols, 3 smg/shotgun, 4 rifles, 5 heavy
}

ArmoryItem g_eArmory[MAX_ARMORY];
int g_iArmory;
int g_iStock[4][MAX_ARMORY];
int g_iStockRestocks[4];
int g_iArmoryBought[4];
ConVar g_hCvarStockpile;
ConVar g_hCvarStockScale;
Handle g_hHudArmory;

char g_sArmoryCats[][] = {"Grenades", "Armour + gear", "Pistols", "SMGs", "Shotguns", "Rifles", "Heavy + snipers"};

void AddArmory(const char[] sKey, const char[] sName, int iBundle, int iCost, int iCat) {
	ArmoryItem e;
	strcopy(e.sKey, sizeof(e.sKey), sKey);
	strcopy(e.sName, sizeof(e.sName), sName);
	e.iBundle = iBundle; e.iCost = iCost; e.iCat = iCat;
	g_eArmory[g_iArmory++] = e;
}

void Armory_Init() {
	g_hCvarStockpile = CreateConVar("css_rts_stockpile", "1", "1 = soldiers can only buy items the Commander stocked in the team armory. Each buy takes 1 from stock", _, true, 0.0, true, 1.0);
	AddCommandListener(Cmd_OpenArmory, "buymenu");
	g_hCvarStockScale = CreateConVar("css_rts_stock_cost_scale", "1.0", "Multiplier for armory restock Intel costs", _, true, 0.0);
	g_hHudArmory = CreateHudSynchronizer();
	RegConsoleCmd("sm_armory", Cmd_Armory, "Team armory: what's in stock (Commander: restock)");
	HookEvent("player_spawn", Event_ArmorySpawn);
	g_iArmory = 0;
	AddArmory("hegrenade", "HE grenade", 4, 180, 0);
	AddArmory("flashbang", "Flashbang", 2, 90, 0);
	AddArmory("smokegrenade", "Smoke", 2, 90, 0);
	AddArmory("vest", "Kevlar", 3, 120, 1);
	AddArmory("vesthelm", "Kevlar+helmet", 3, 240, 1);
	AddArmory("defuser", "Defuse kit", 2, 60, 1);
	AddArmory("nvgs", "Nightvision", 2, 60, 1);
	AddArmory("glock", "Glock (T)", 3, 60, 2);
	AddArmory("usp", "USP (CT)", 3, 60, 2);
	AddArmory("p228", "P228", 3, 90, 2);
	AddArmory("deagle", "Desert Eagle", 3, 150, 2);
	AddArmory("elite", "Dual Elites", 3, 120, 2);
	AddArmory("fiveseven", "Five-SeveN", 3, 120, 2);
	AddArmory("mac10", "MAC-10", 3, 180, 3);
	AddArmory("tmp", "TMP", 3, 180, 3);
	AddArmory("mp5navy", "MP5", 3, 210, 3);
	AddArmory("ump45", "UMP45", 3, 210, 3);
	AddArmory("p90", "P90", 3, 270, 3);
	AddArmory("m3", "M3 shotgun", 3, 180, 4);
	AddArmory("xm1014", "XM1014", 3, 270, 4);
	AddArmory("galil", "Galil", 3, 300, 5);
	AddArmory("famas", "FAMAS", 3, 300, 5);
	AddArmory("scout", "Scout", 3, 270, 5);
	AddArmory("ak47", "AK-47", 3, 480, 5);
	AddArmory("m4a1", "M4A1", 3, 480, 5);
	AddArmory("sg552", "SG 552 Bullpup (T)", 3, 510, 5);
	AddArmory("aug", "AUG Bullpup (CT)", 3, 510, 5);
	AddArmory("awp", "AWP", 2, 720, 6);
	AddArmory("g3sg1", "G3SG1", 2, 720, 6);
	AddArmory("sg550", "SG550", 2, 720, 6);
	AddArmory("m249", "M249", 2, 600, 6);
}

void Armory_Reset() {
	for (int t=0; t<4; t++) { g_iStockRestocks[t] = 0; for (int k=0; k<MAX_ARMORY; k++) g_iStock[t][k] = 0; }
}

int Armory_Find(const char[] sKey) {
	for (int k=0; k<g_iArmory; k++) if (StrEqual(g_eArmory[k].sKey, sKey, false)) return k;
	return -1;
}

int Armory_Cost(int k) {
	return RoundToCeil(g_eArmory[k].iCost * g_hCvarStockScale.FloatValue * 1.25);
}

// item type unlocked in the tech tree (or economy off)?
int Armory_Index(const char[] sKey) {
	for (int k = 0; k < g_iArmory; k++) if (StrEqual(g_eArmory[k].sKey, sKey)) return k;
	return -1;
}

bool BuyMenu_Open(int t, const char[] sKey) {
	int k = Armory_Index(sKey);
	if (k < 0) return true;
	if (!Armory_ForTeam(t, sKey)) return false;
	return Armory_Unlocked(t, k);
}

void BuyMenu_Replace(const char[] sRel, const char[] sFrom, const char[] sTo) {
	char sPath[256], sBuf[16384];
	BuildPath(Path_SM, sPath, sizeof(sPath), "../../custom/css_rts/%s", sRel);
	File h = OpenFile(sPath, "r");
	if (h == null) return;
	sBuf[0] = 0;
	char sLine[384];
	while (!h.EndOfFile() && h.ReadLine(sLine, sizeof(sLine))) StrCat(sBuf, sizeof(sBuf), sLine);
	delete h;
	if (ReplaceString(sBuf, sizeof(sBuf), sFrom, sTo) <= 0) return;
	h = OpenFile(sPath, "w");
	if (h != null) { h.WriteString(sBuf, false); delete h; }
}

void BuyMenu_Class(const char[] sFile, const char[] sKey, int t) {
	char sRel[128];
	Format(sRel, sizeof(sRel), "classes/%s", sFile);
	bool bOpen = BuyMenu_Open(t, sKey);
	if (bOpen) {
		BuyMenu_Replace(sRel, "TECH: LOCKED", "TECH: UNLOCKED");
		BuyMenu_Replace(sRel, "170 170 170 255", "255 196 64 255");
	} else {
		BuyMenu_Replace(sRel, "TECH: UNLOCKED", "TECH: LOCKED");
		BuyMenu_Replace(sRel, "255 196 64 255", "170 170 170 255");
	}
	int iStock = 0;
	int k = Armory_Index(sKey);
	if (k >= 0) iStock = g_iStock[t][k];
	BuyMenu_Qty(sRel, iStock);
}

void BuyMenu_Qty(const char[] sRel, int n) {
	char sPath[256], sBuf[8192];
	BuildPath(Path_SM, sPath, sizeof(sPath), "../../custom/css_rts/%s", sRel);
	File h = OpenFile(sPath, "r");
	if (h == null) return;
	sBuf[0] = 0;
	char sLine[256];
	while (!h.EndOfFile() && h.ReadLine(sLine, sizeof(sLine))) {
		if (StrContains(sLine, "//qty") != -1) Format(sLine, sizeof(sLine), "\"labelText\" \"x%d\" //qty\n", n);
		StrCat(sBuf, sizeof(sBuf), sLine);
	}
	delete h;
	h = OpenFile(sPath, "w");
	if (h != null) { h.WriteString(sBuf, false); delete h; }
}

void BuyMenu_Dull(const char[] sRel, int t) {
	char sPath[256], sBuf[16384];
	BuildPath(Path_SM, sPath, sizeof(sPath), "../../custom/css_rts/%s", sRel);
	File h = OpenFile(sPath, "r");
	if (h == null) return;
	sBuf[0] = 0;
	char sLine[384];
	while (!h.EndOfFile() && h.ReadLine(sLine, sizeof(sLine))) {
		int p = StrContains(sLine, "//rtslock ");
		if (p != -1) {
			char sKey[24];
			strcopy(sKey, sizeof(sKey), sLine[p + 10]);
			TrimString(sKey);
			bool bOpen = BuyMenu_Open(t, sKey);
			Format(sLine, sizeof(sLine), "\t\t\"dulltext\"\t\t\"%d\" //rtslock %s\n", bOpen ? 0 : 1, sKey);
		}
		StrCat(sBuf, sizeof(sBuf), sLine);
	}
	delete h;
	h = OpenFile(sPath, "w");
	if (h != null) { h.WriteString(sBuf, false); delete h; }
}

void BuyMenu_Sync() {
	int tShow = CS_TEAM_CT;
	for (int i = 1; i <= MaxClients; i++) {
		if (!IsClientInGame(i) || IsFakeClient(i)) continue;
		int t = GetClientTeam(i);
		if (t == CS_TEAM_T || t == CS_TEAM_CT) tShow = t;
	}
	BuyMenu_Class("glock18.res", "glock", tShow);
	BuyMenu_Class("usp45.res", "usp", tShow);
	BuyMenu_Class("p228.res", "p228", tShow);
	BuyMenu_Class("deserteagle.res", "deagle", tShow);
	BuyMenu_Class("fiveseven.res", "fiveseven", tShow);
	BuyMenu_Class("elites.res", "elite", tShow);
	BuyMenu_Class("mac10.res", "mac10", tShow);
	BuyMenu_Class("tmp.res", "tmp", tShow);
	BuyMenu_Class("mp5.res", "mp5navy", tShow);
	BuyMenu_Class("ump45.res", "ump45", tShow);
	BuyMenu_Class("p90.res", "p90", tShow);
	BuyMenu_Class("famas.res", "famas", tShow);
	BuyMenu_Class("galil.res", "galil", tShow);
	BuyMenu_Class("ak47.res", "ak47", tShow);
	BuyMenu_Class("m4a1.res", "m4a1", tShow);
	BuyMenu_Class("sg552.res", "sg552", tShow);
	BuyMenu_Class("aug.res", "aug", tShow);
	BuyMenu_Class("scout.res", "scout", tShow);
	BuyMenu_Class("awp.res", "awp", tShow);
	BuyMenu_Class("sg550.res", "sg550", tShow);
	BuyMenu_Class("g3sg1.res", "g3sg1", tShow);
	BuyMenu_Class("m249.res", "m249", tShow);
	BuyMenu_Class("m3.res", "m3", tShow);
	BuyMenu_Class("xm1014.res", "xm1014", tShow);
	BuyMenu_Class("flashbang.res", "flashbang", tShow);
	BuyMenu_Class("hegrenade.res", "hegrenade", tShow);
	BuyMenu_Class("smokegrenade.res", "smokegrenade", tShow);
	BuyMenu_Class("kevlar.res", "vest", tShow);
	BuyMenu_Class("kevlar_helmet.res", "vesthelm", tShow);
	BuyMenu_Class("defuser.res", "defuser", tShow);
	BuyMenu_Class("nightvision.res", "nvgs", tShow);
	BuyMenu_Dull("resource/ui/buypistols_ct.res", CS_TEAM_CT);
	BuyMenu_Dull("resource/ui/buypistols_ter.res", CS_TEAM_T);
	BuyMenu_Dull("resource/ui/buyrifles_ct.res", CS_TEAM_CT);
	BuyMenu_Dull("resource/ui/buyrifles_ter.res", CS_TEAM_T);
	BuyMenu_Dull("resource/ui/buysubmachineguns_ct.res", CS_TEAM_CT);
	BuyMenu_Dull("resource/ui/buysubmachineguns_ter.res", CS_TEAM_T);
	BuyMenu_Dull("resource/ui/buyequipment_ct.res", CS_TEAM_CT);
	BuyMenu_Dull("resource/ui/buyequipment_ter.res", CS_TEAM_T);
	BuyMenu_Dull("resource/ui/buyshotguns.res", tShow);
	BuyMenu_Dull("resource/ui/buymachineguns.res", tShow);
}

bool Armory_Unlocked(int t, int k) {
	int u = Unlock_ForItem(g_eArmory[k].sKey);
	return u == -1 || !g_hCvarUnlocks.BoolValue || g_bUnlocked[t][u];
}

// Commander restock: spends Intel, adds one bundle. iClient 0 = debug/selftest.
bool Armory_Restock(int iClient, int t, int k, bool bFree=false) {
	if (k < 0 || k >= g_iArmory) return false;
	if (!Armory_Unlocked(t, k)) {
		int u = Unlock_ForItem(g_eArmory[k].sKey);
		if (iClient) PrintToChat(iClient, "\x04[RTS]\x01 %s is not researched yet (tech tree: %s).", g_eArmory[k].sName, u != -1 ? g_eUnlock[u].sName : "?");
		return false;
	}
	int iCost = Armory_Cost(k);
	if (!bFree && g_iIntel[t] < iCost) {
		if (iClient) PrintToChat(iClient, "\x04[RTS]\x01 Need %d Intel (have %d).", iCost, g_iIntel[t]);
		return false;
	}
	if (!bFree) g_iIntel[t] -= iCost;
	g_iStock[t][k] += g_eArmory[k].iBundle;
	g_iStockRestocks[t]++;
	TeamChat(t, "\x04[RTS] ARMORY:\x01 +%d \x03%s\x01 in stock (now %d). Type \x04!armory\x01 to buy.", g_eArmory[k].iBundle, g_eArmory[k].sName, g_iStock[t][k]);
	return true;
}

// From CS_OnBuyCommand (after the unlock check). true = block. Reserves one unit; refunded next
// frame if the purchase didn't go through (no money spent).
bool Armory_OnBuy(int iClient, const char[] sWeapon) {
	if (!g_hCvarStockpile.BoolValue) return false;
	int t = GetClientTeam(iClient);
	if (!(CS_TEAM_T <= t <= CS_TEAM_CT)) return false;
	int k = Armory_Find(sWeapon);
	if (k == -1) return false;   // default pistols, ammo, unknown aliases
	if (!Armory_ForTeam(t, g_eArmory[k].sKey)) {
		if (!IsFakeClient(iClient)) PrintHintText(iClient, "That is the other side's gear");
		return true;
	}
	if (Armory_Give(iClient, t, k)) {
		if (!IsFakeClient(iClient)) PrintToChat(iClient, "\x04[RTS]\x01 Bought \x03%s\x01.", g_eArmory[k].sName);
		return true;
	}
	if (!IsFakeClient(iClient)) PrintHintText(iClient, "Cannot buy %s", g_eArmory[k].sName);
	return true;
}

public void Frame_ArmoryBuyCheck(DataPack hPack) {
	hPack.Reset();
	int iClient = GetClientOfUserId(hPack.ReadCell());
	int t = hPack.ReadCell(), k = hPack.ReadCell(), iMoney = hPack.ReadCell();
	delete hPack;
	bool bBought = iClient && IsClientInGame(iClient) && GetEntProp(iClient, Prop_Send, "m_iAccount") < iMoney;
	if (!bBought) g_iStock[t][k]++;   // refund the reserved unit
	else g_iArmoryBought[t]++;
}


int Armory_TotalStock(int t) {
	int n;
	for (int k=0; k<g_iArmory; k++) n += g_iStock[t][k];
	return n;
}

// Flat list for a click on the HQ: every item, locked or not, and the stock count.
int Armory_ViewTeam(int iClient) {
	int t = GetCommanderTeam(iClient);
	if (t >= CS_TEAM_T && t <= CS_TEAM_CT) return t;
	return GetClientTeam(iClient);
}

void Armory_ShowHQMenu(int iClient, int iStart = 0) {
	if (Menu_Hold(iClient)) return;
	int t = Armory_ViewTeam(iClient);
	if (t < CS_TEAM_T || t > CS_TEAM_CT) return;
	Menu hMenu = new Menu(MenuHandler_HQBuy);
	hMenu.SetTitle("%s ARMOURY    Intel %d\nOnly your side's gear.  xN is stocked.\n ", t == CS_TEAM_CT ? "CT" : "T", g_iIntel[t]);
	char sInfo[8], sItem[96];
	for (int k = 0; k < g_iArmory; k++) {
		if (!Armory_ForTeam(t, g_eArmory[k].sKey)) continue;
		bool bOpen = Armory_Unlocked(t, k);
		IntToString(k, sInfo, sizeof(sInfo));
		if (!bOpen) {
			char sReq[40];
			int u = Unlock_ForItem(g_eArmory[k].sKey);
			if (u != -1) Unlock_ShortName(u, sReq, sizeof(sReq));
			else strcopy(sReq, sizeof(sReq), "research");
			FormatEx(sItem, sizeof(sItem), "LOCKED   %s    x%d    needs %s", g_eArmory[k].sName, g_iStock[t][k], sReq);
			hMenu.AddItem(sInfo, sItem, ITEMDRAW_DISABLED);
		} else {
			FormatEx(sItem, sizeof(sItem), "%s    x%d    +%d for %d Intel", g_eArmory[k].sName, g_iStock[t][k], g_eArmory[k].iBundle, Armory_Cost(k));
			hMenu.AddItem(sInfo, sItem, g_iIntel[t] >= Armory_Cost(k) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
		}
	}
	hMenu.ExitBackButton = true;
	if (iStart > 0) hMenu.DisplayAt(iClient, iStart, MENU_TIME_FOREVER);
	else hMenu.Display(iClient, MENU_TIME_FOREVER);
	Menu_Mark(iClient, 6);
}

public int MenuHandler_HQBuy(Menu hMenu, MenuAction eAction, int iClient, int iItem) {
	if (eAction == MenuAction_End) delete hMenu;
	else if (eAction == MenuAction_Cancel && !Menu_Refreshing(iClient) && iItem == MenuCancel_ExitBack && GetCommanderTeam(iClient)) ShowCommanderMenu(iClient);
	else if (eAction == MenuAction_Select) {
		int t = Armory_ViewTeam(iClient);
		if (t < CS_TEAM_T || t > CS_TEAM_CT) return 0;
		char sInfo[8];
		hMenu.GetItem(iItem, sInfo, sizeof(sInfo));
		Armory_Restock(iClient, t, StringToInt(sInfo));
		int iPer = hMenu.Pagination > 0 ? hMenu.Pagination : 7;
		Armory_ShowHQMenu(iClient, (iItem / iPer) * iPer);
	}
	return 0;
}

// ---- Commander: restock menu (categories -> items) ----
void Armory_ShowAvailable(int iClient) {
	if (Menu_Hold(iClient)) return;
	int t = GetClientTeam(iClient);
	if (t < CS_TEAM_T || t > CS_TEAM_CT) return;
	Menu hMenu = new Menu(MenuHandler_Available);
	int n;
	char sInfo[8], sItem[96];
	hMenu.SetTitle("%s HQ\nIn stock, ready to take.\n ", t == CS_TEAM_CT ? "CT" : "T");
	for (int k = 0; k < g_iArmory; k++) {
		if (!Armory_ForTeam(t, g_eArmory[k].sKey) || !Armory_Unlocked(t, k) || g_iStock[t][k] <= 0) continue;
		IntToString(k, sInfo, sizeof(sInfo));
		FormatEx(sItem, sizeof(sItem), "%s    x%d", g_eArmory[k].sName, g_iStock[t][k]);
		hMenu.AddItem(sInfo, sItem);
		n++;
	}
	if (!n) hMenu.AddItem("", "Nothing in stock yet", ITEMDRAW_DISABLED);
	hMenu.ExitButton = true;
	hMenu.Display(iClient, 20);
}

public int MenuHandler_Available(Menu hMenu, MenuAction eAction, int iClient, int iItem) {
	if (eAction == MenuAction_End) delete hMenu;
	else if (eAction == MenuAction_Select) {
		char sInfo[8];
		hMenu.GetItem(iItem, sInfo, sizeof(sInfo));
		if (!sInfo[0]) return 0;
		int t = GetClientTeam(iClient);
		int k = StringToInt(sInfo);
		if (Armory_Give(iClient, t, k)) PrintHintText(iClient, "Took %s", g_eArmory[k].sName);
		Armory_ShowAvailable(iClient);
	}
	return 0;
}

void Armory_ShowRestockMenu(int iClient) {
	if (Menu_Hold(iClient)) return;
	Armory_ShowHQMenu(iClient);
}

void Armory_ShowRestockMenu_Old(int iClient) {
	int t = GetClientTeam(iClient);
	Menu hMenu = new Menu(MenuHandler_RestockCat);
	hMenu.SetTitle("ARMORY - restock (Intel %d)\nTeam stock: %d items\n ", g_iIntel[t], Armory_TotalStock(t));
	char sInfo[8], sItem[64];
	for (int c=0; c<sizeof(g_sArmoryCats); c++) {
		int iStock, iOpen;
		for (int k=0; k<g_iArmory; k++) if (g_eArmory[k].iCat == c) { iStock += g_iStock[t][k]; if (Armory_Unlocked(t, k)) iOpen++; }
		FormatEx(sItem, sizeof(sItem), "%s  (stock %d)%s", g_sArmoryCats[c], iStock, iOpen ? "" : "  [locked]");
		IntToString(c, sInfo, sizeof(sInfo));
		hMenu.AddItem(sInfo, sItem);
	}
	hMenu.ExitBackButton = true;
	hMenu.Display(iClient, MENU_TIME_FOREVER);
	Menu_Mark(iClient, 6);
}

public int MenuHandler_RestockCat(Menu hMenu, MenuAction eAction, int iClient, int iItem) {
	if (eAction == MenuAction_End) delete hMenu;
	else if (eAction == MenuAction_Cancel && !Menu_Refreshing(iClient) && iItem == MenuCancel_ExitBack && GetCommanderTeam(iClient)) ShowCommanderMenu(iClient);
	else if (eAction == MenuAction_Select) {
		char sInfo[8]; hMenu.GetItem(iItem, sInfo, sizeof(sInfo));
		Armory_ShowRestockItems(iClient, StringToInt(sInfo));
	}
	return 0;
}

int g_iRestockCat[MAXPLAYERS+1];

void Armory_ShowRestockItems(int iClient, int c) {
	int t = GetClientTeam(iClient);
	g_iRestockCat[iClient] = c;
	Menu hMenu = new Menu(MenuHandler_RestockItem);
	hMenu.SetTitle("RESTOCK %s (Intel %d)\n ", g_sArmoryCats[c], g_iIntel[t]);
	char sInfo[8], sItem[80];
	for (int k=0; k<g_iArmory; k++) {
		if (g_eArmory[k].iCat != c) continue;
		bool bOpen = Armory_Unlocked(t, k);
		if (bOpen) FormatEx(sItem, sizeof(sItem), "+%d %s  (%d Intel)  stock %d", g_eArmory[k].iBundle, g_eArmory[k].sName, Armory_Cost(k), g_iStock[t][k]);
		else FormatEx(sItem, sizeof(sItem), "%s  [research first]", g_eArmory[k].sName);
		IntToString(k, sInfo, sizeof(sInfo));
		hMenu.AddItem(sInfo, sItem, (bOpen && g_iIntel[t] >= Armory_Cost(k)) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	}
	hMenu.ExitBackButton = true;
	hMenu.Display(iClient, MENU_TIME_FOREVER);
	Menu_Mark(iClient, 7);
}

public int MenuHandler_RestockItem(Menu hMenu, MenuAction eAction, int iClient, int iItem) {
	if (eAction == MenuAction_End) delete hMenu;
	else if (eAction == MenuAction_Cancel && !Menu_Refreshing(iClient) && iItem == MenuCancel_ExitBack && GetCommanderTeam(iClient)) Armory_ShowRestockMenu(iClient);
	else if (eAction == MenuAction_Select) {
		int t = GetCommanderTeam(iClient);
		if (!t) return 0;
		char sInfo[8]; hMenu.GetItem(iItem, sInfo, sizeof(sInfo));
		Armory_Restock(iClient, t, StringToInt(sInfo));
		Armory_ShowRestockItems(iClient, g_iRestockCat[iClient]);
	}
	return 0;
}

// ---- Soldiers: !armory menu (what's in stock) + buyzone HUD line ----
void Armory_MapStart() {
	Armory_Reset();
	CreateTimer(10.0, Timer_ArmoryBots, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_ArmoryBots(Handle hTimer) {
	Armory_BotShop();
	Armory_BotTrade();
	return Plugin_Continue;
}

public void Event_ArmorySpawn(Event hEvent, const char[] sName, bool bDontBroadcast) {
	int iClient = GetClientOfUserId(hEvent.GetInt("userid"));
	if (iClient > 0 && IsClientInGame(iClient) && !IsFakeClient(iClient)) {
		ClientCommand(iClient, "bind b buymenu");
		ClientCommand(iClient, "bind F1 bunny_on");
	}
}

public Action Cmd_Armory(int iClient, int iArgs) {
	if (!iClient || !IsClientInGame(iClient)) return Plugin_Handled;
	int t = GetClientTeam(iClient);
	if (!(CS_TEAM_T <= t <= CS_TEAM_CT)) { ReplyToCommand(iClient, "[RTS] Join a team first."); return Plugin_Handled; }
	if (GetCommanderTeam(iClient)) { Armory_ShowRestockMenu(iClient); return Plugin_Handled; }
	Armory_ShowBuyMenu(iClient);
	return Plugin_Handled;
}

public Action Cmd_OpenArmory(int iClient, const char[] sCmd, int iArgs) {
	if (!iClient || !IsClientInGame(iClient) || IsFakeClient(iClient)) return Plugin_Continue;
	return Plugin_Continue;
}

bool g_bBuyOther[MAXPLAYERS+1];

int Armory_Side(const char[] sKey) {
	if (StrEqual(sKey, "glock") || StrEqual(sKey, "elite") || StrEqual(sKey, "mac10") || StrEqual(sKey, "galil") || StrEqual(sKey, "ak47") || StrEqual(sKey, "sg552") || StrEqual(sKey, "g3sg1")) return CS_TEAM_T;
	if (StrEqual(sKey, "usp") || StrEqual(sKey, "fiveseven") || StrEqual(sKey, "tmp") || StrEqual(sKey, "famas") || StrEqual(sKey, "m4a1") || StrEqual(sKey, "aug") || StrEqual(sKey, "sg550") || StrEqual(sKey, "defuser")) return CS_TEAM_CT;
	return 0;
}

bool Armory_ForTeam(int t, const char[] sKey) {
	int iSide = Armory_Side(sKey);
	return iSide == 0 || iSide == t;
}

int Armory_Cash(const char[] sKey) {
	if (StrEqual(sKey, "vest")) return 650;
	if (StrEqual(sKey, "vesthelm")) return 1000;
	if (StrEqual(sKey, "defuser")) return 200;
	if (StrEqual(sKey, "nvgs")) return 1250;
	if (StrEqual(sKey, "hegrenade")) return 300;
	if (StrEqual(sKey, "flashbang") || StrEqual(sKey, "smokegrenade")) return 200;
	if (StrEqual(sKey, "glock")) return 400;
	if (StrEqual(sKey, "usp")) return 500;
	if (StrEqual(sKey, "p228")) return 600;
	if (StrEqual(sKey, "deagle")) return 650;
	if (StrEqual(sKey, "elite")) return 800;
	if (StrEqual(sKey, "fiveseven")) return 750;
	if (StrEqual(sKey, "mac10")) return 1400;
	if (StrEqual(sKey, "tmp")) return 1250;
	if (StrEqual(sKey, "mp5navy")) return 1500;
	if (StrEqual(sKey, "ump45")) return 1700;
	if (StrEqual(sKey, "p90")) return 2350;
	if (StrEqual(sKey, "m3")) return 1700;
	if (StrEqual(sKey, "xm1014")) return 3000;
	if (StrEqual(sKey, "galil")) return 2000;
	if (StrEqual(sKey, "famas")) return 2250;
	if (StrEqual(sKey, "ak47")) return 2500;
	if (StrEqual(sKey, "scout")) return 2750;
	if (StrEqual(sKey, "m4a1")) return 3100;
	if (StrEqual(sKey, "sg552") || StrEqual(sKey, "aug")) return 3500;
	if (StrEqual(sKey, "sg550")) return 4200;
	if (StrEqual(sKey, "awp")) return 4750;
	if (StrEqual(sKey, "g3sg1")) return 5000;
	if (StrEqual(sKey, "m249")) return 5750;
	return 1000;
}

int Armory_Tier(const char[] sKey) {
	int side = Armory_Side(sKey);
	if (StrEqual(sKey, "vest") || StrEqual(sKey, "vesthelm") || StrEqual(sKey, "defuser") || StrEqual(sKey, "nvgs")) return 0;
	if (StrEqual(sKey, "hegrenade") || StrEqual(sKey, "flashbang") || StrEqual(sKey, "smokegrenade")) return 0;
	if (StrEqual(sKey, "m3") || StrEqual(sKey, "xm1014")) return 3;
	if (StrEqual(sKey, "galil") || StrEqual(sKey, "famas") || StrEqual(sKey, "ak47") || StrEqual(sKey, "m4a1") || StrEqual(sKey, "sg552") || StrEqual(sKey, "aug") || StrEqual(sKey, "scout")) return 4;
	if (StrEqual(sKey, "awp") || StrEqual(sKey, "g3sg1") || StrEqual(sKey, "sg550") || StrEqual(sKey, "m249")) return 5;
	if (StrEqual(sKey, "mac10") || StrEqual(sKey, "tmp") || StrEqual(sKey, "mp5navy") || StrEqual(sKey, "ump45") || StrEqual(sKey, "p90")) return 2;
	return 1;
}

int Armory_GrantResearch(int t, const char[] sItems) {
	int k = Armory_Find(sItems);
	if (k < 0 || t < 0 || t > 3) return 0;
	g_iStock[t][k] += g_eArmory[k].iBundle;
	return g_iStock[t][k];
}

bool Armory_Give(int iClient, int t, int k) {
	if (k < 0 || k >= g_iArmory || iClient < 1 || !IsClientInGame(iClient) || !IsPlayerAlive(iClient)) return false;
	if (!Armory_ForTeam(t, g_eArmory[k].sKey) || !Armory_Unlocked(t, k)) return false;
	bool bFree = Unlock_ForItem(g_eArmory[k].sKey) == -1;
	bool bPay = !bFree && g_hCvarStockpile.BoolValue && g_iStock[t][k] <= 0;
	int iCash = Armory_Cash(g_eArmory[k].sKey);
	if (bPay && GetEntProp(iClient, Prop_Send, "m_iAccount") < iCash) return false;
	char sKey[16];
	strcopy(sKey, sizeof(sKey), g_eArmory[k].sKey);
	if (StrEqual(sKey, "vest")) SetEntProp(iClient, Prop_Send, "m_ArmorValue", 100);
	else if (StrEqual(sKey, "vesthelm")) {
		SetEntProp(iClient, Prop_Send, "m_ArmorValue", 100);
		if (HasEntProp(iClient, Prop_Send, "m_bHasHelmet")) SetEntProp(iClient, Prop_Send, "m_bHasHelmet", 1);
	} else if (StrEqual(sKey, "nvgs")) {
		if (HasEntProp(iClient, Prop_Send, "m_bHasNightVision")) SetEntProp(iClient, Prop_Send, "m_bHasNightVision", 1);
	} else if (StrEqual(sKey, "defuser")) {
		if (HasEntProp(iClient, Prop_Send, "m_bHasDefuser")) SetEntProp(iClient, Prop_Send, "m_bHasDefuser", 1);
	} else {
		char sClass[32];
		FormatEx(sClass, sizeof(sClass), "weapon_%s", sKey);
		GivePlayerItem(iClient, sClass);
	}
	if (bPay) SetEntProp(iClient, Prop_Send, "m_iAccount", GetEntProp(iClient, Prop_Send, "m_iAccount") - iCash);
	else if (!bFree && g_hCvarStockpile.BoolValue && g_iStock[t][k] > 0) g_iStock[t][k]--;
	return true;
}

int Bot_HeldTier(int iClient) {
	int iBest = 0;
	for (int s = 0; s < 4; s++) {
		int w = GetPlayerWeaponSlot(iClient, s);
		if (w <= 0) continue;
		char sClass[32];
		GetEntityClassname(w, sClass, sizeof(sClass));
		ReplaceString(sClass, sizeof(sClass), "weapon_", "");
		int iTier = Armory_Tier(sClass);
		if (iTier > iBest) iBest = iTier;
	}
	return iBest;
}

void Armory_BotShop() {
	if (g_eGame != GS_Live) return;
	for (int t = CS_TEAM_T; t <= CS_TEAM_CT; t++) {
		int iBestK = -1, iBestTier = 0;
		for (int k = 0; k < g_iArmory; k++) {
			if (g_iStock[t][k] <= 0 || !Armory_Unlocked(t, k) || !Armory_ForTeam(t, g_eArmory[k].sKey)) continue;
			int iTier = Armory_Tier(g_eArmory[k].sKey);
			if (iTier > iBestTier) { iBestTier = iTier; iBestK = k; }
		}
		int iNeed = 0;
		for (int i = 1; i <= MaxClients; i++) {
			if (!IsClientInGame(i) || !IsFakeClient(i) || !IsPlayerAlive(i) || GetClientTeam(i) != t || g_bBodyHidden[i]) continue;
			if (GetEntProp(i, Prop_Send, "m_ArmorValue") < 50) {
				for (int k = 0; k < g_iArmory; k++) {
					if (g_iStock[t][k] <= 0) continue;
					if (StrEqual(g_eArmory[k].sKey, "vesthelm") || StrEqual(g_eArmory[k].sKey, "vest")) {
						Armory_Give(i, t, k);
						break;
					}
				}
			}
			if (iBestK != -1 && Bot_HeldTier(i) < iBestTier && iNeed < 2) {
				if (Armory_Give(i, t, iBestK)) iNeed++;
			}
		}
	}
}

void Armory_BotTrade() {
	for (int t = CS_TEAM_T; t <= CS_TEAM_CT; t++) {
		float vecBase[3];
		if (!GetBasePoint(t, vecBase, false)) continue;
		int iPoor = 0, iRich = 0;
		float fPoor = 0.0, fRich = 99999.0;
		for (int i = 1; i <= MaxClients; i++) {
			if (!IsClientInGame(i) || !IsFakeClient(i) || !IsPlayerAlive(i) || GetClientTeam(i) != t || g_bBodyHidden[i]) continue;
			if (Train_Hold(i) || Guard_Hold(i)) continue;
			float p[3];
			GetClientAbsOrigin(i, p);
			float d = GetVectorDistance(p, vecBase);
			int iTier = Bot_HeldTier(i);
			if (iTier <= 1 && d > fPoor) { fPoor = d; iPoor = i; }
			if (iTier >= 4 && d < fRich) { fRich = d; iRich = i; }
		}
		if (!iPoor || !iRich || iPoor == iRich || fRich > 700.0) continue;
		int w = GetPlayerWeaponSlot(iRich, 0);
		if (w <= 0) continue;
		char sClass[32];
		GetEntityClassname(w, sClass, sizeof(sClass));
		RemovePlayerItem(iRich, w);
		AcceptEntityInput(w, "Kill");
		GivePlayerItem(iPoor, sClass);
	}
}

void Armory_ShowBuyMenu(int iClient, int iStart = 0) {
	if (Menu_Hold(iClient)) return;
	int t = GetClientTeam(iClient);
	Menu hMenu = new Menu(MenuHandler_ArmoryBuy);
	hMenu.SetTitle("BUY  %s    $%d\nYour side only.  xN is free from the armoury, otherwise you pay.\n ", t == CS_TEAM_CT ? "CT" : "T", GetEntProp(iClient, Prop_Send, "m_iAccount"));
	hMenu.Pagination = 8;
	char sInfo[8], sItem[96];
	for (int pass = 0; pass < 2; pass++) {
	for (int k=0; k<g_iArmory; k++) {
		if (!Armory_ForTeam(t, g_eArmory[k].sKey)) continue;
		bool bGear = g_eArmory[k].iCat == 1;
		if (pass == 0 && !bGear) continue;
		if (pass == 1 && bGear) continue;
		int u = Unlock_ForItem(g_eArmory[k].sKey);
		bool bLocked = u != -1 && !g_bUnlocked[t][u];
		int iCash = Armory_Cash(g_eArmory[k].sKey);
		IntToString(k, sInfo, sizeof(sInfo));
		if (bLocked) {
			FormatEx(sItem, sizeof(sItem), "LOCKED  %s", g_eArmory[k].sName);
			hMenu.AddItem(sInfo, sItem, ITEMDRAW_DISABLED);
		} else if (g_iStock[t][k] > 0) {
			FormatEx(sItem, sizeof(sItem), "%s   x%d", g_eArmory[k].sName, g_iStock[t][k]);
			hMenu.AddItem(sInfo, sItem);
		} else if (GetEntProp(iClient, Prop_Send, "m_iAccount") >= iCash) {
			FormatEx(sItem, sizeof(sItem), "%s   $%d", g_eArmory[k].sName, iCash);
			hMenu.AddItem(sInfo, sItem);
		} else {
			FormatEx(sItem, sizeof(sItem), "%s   $%d", g_eArmory[k].sName, iCash);
			hMenu.AddItem(sInfo, sItem, ITEMDRAW_DISABLED);
		}
	}
	}
	hMenu.ExitBackButton = true;
	if (iStart > 0) hMenu.DisplayAt(iClient, iStart, MENU_TIME_FOREVER);
	else hMenu.Display(iClient, MENU_TIME_FOREVER);
}

public int MenuHandler_ArmoryBuy(Menu hMenu, MenuAction eAction, int iClient, int iItem) {
	if (eAction == MenuAction_End) delete hMenu;
	else if (eAction == MenuAction_Select) {
		char sInfo[8]; hMenu.GetItem(iItem, sInfo, sizeof(sInfo));
		if (!sInfo[0]) return 0;
		if (sInfo[0]) {
			int t = GetClientTeam(iClient);
			int k = StringToInt(sInfo);
			if (Armory_Give(iClient, t, k)) PrintHintText(iClient, "Bought %s", g_eArmory[k].sName);
			else PrintHintText(iClient, "Cannot buy that");
		}
		if (IsClientInGame(iClient) && IsPlayerAlive(iClient) && !g_eCommander[iClient].bEnabled) {
			int iPer = hMenu.Pagination > 0 ? hMenu.Pagination : 7;
			Armory_ShowBuyMenu(iClient, (iItem / iPer) * iPer);
		}
	}
	return 0;
}

public Action Timer_ArmoryReopen(Handle hTimer, int iUserId) {
	int iClient = GetClientOfUserId(iUserId);
	if (iClient && IsClientInGame(iClient) && IsPlayerAlive(iClient)) Armory_ShowBuyMenu(iClient);
	return Plugin_Stop;
}

// "ARMORY: HE x4  Flash x2  AK-47 x3 ..." while standing in a buy zone
void Armory_StockLine(int t, char[] sBuf, int iLen) {
	sBuf[0] = '\0';
	int n;
	for (int k=0; k<g_iArmory; k++) {
		if (g_iStock[t][k] <= 0) continue;
		if (n && n % 5 == 0) StrCat(sBuf, iLen, "\n");
		Format(sBuf, iLen, "%s%s x%d   ", sBuf, g_eArmory[k].sName, g_iStock[t][k]);
		n++;
	}
	if (!n) strcopy(sBuf, iLen, "empty - Commander restocks with Intel");
}

// compact stock lines for the HUD panel (soldier in a buy zone)
void Armory_HudText(int t, char[] s, int n) {
	StrCat(s, n, " \nARMORY (!armory)\n");
	int m;
	for (int k=0; k<g_iArmory; k++) {
		if (g_iStock[t][k] <= 0) continue;
		Format(s, n, "%s%s x%d%s", s, g_eArmory[k].sName, g_iStock[t][k], (++m % 2) ? "   " : "\n");
	}
	if (!m) StrCat(s, n, "empty - ask your Commander\n");
	else if (m % 2) StrCat(s, n, "\n");
}
