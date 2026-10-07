// css_rts/cmdmenu.sp -- Commander menu drawn at the bottom middle (not the left text box).

bool g_bCtrl[MAXPLAYERS+1];
bool g_bMenuDismiss[MAXPLAYERS+1];
int g_iGroupN[MAXPLAYERS+1][10];
int g_iGroup[MAXPLAYERS+1][10][12];
float g_fGroupTap[MAXPLAYERS+1][10];
int g_iCmdPage[MAXPLAYERS+1];
Handle g_hHudMenu;
char g_sCmdLast[MAXPLAYERS+1][512];

void CmdMenu_Init() {
	g_hHudMenu = CreateHudSynchronizer();
	for (int i = 1; i <= 9; i++) {
		char sCmd[8];
		FormatEx(sCmd, sizeof(sCmd), "slot%d", i);
		AddCommandListener(Cmd_MenuSlot, sCmd);
	}
	AddCommandListener(Cmd_MenuSlot, "slot10");
	RegConsoleCmd("sm_rts_close", Cmd_MenuClose, "Close the RTS menu");
	RegConsoleCmd("+rtsctrl", Cmd_CtrlDown, "Hold Ctrl to save a control group");
	RegConsoleCmd("-rtsctrl", Cmd_CtrlUp);
}

bool Menu_Hold(int iClient) {
	return iClient > 0 && g_bMenuDismiss[iClient];
}

void Menu_Shut(int iClient) {
	if (iClient <= 0 || !IsClientInGame(iClient)) return;
	g_bMenuDismiss[iClient] = true;
	g_iLiveMenu[iClient] = 0;
	g_iCmdPage[iClient] = 0;
	g_sCmdLast[iClient][0] = 0;
	CancelClientMenu(iClient, true);
	RequestFrame(Frame_MenuClosed, GetClientUserId(iClient));
}

public Action Cmd_MenuClose(int iClient, int iArgs) {
	if (iClient <= 0 || !IsClientInGame(iClient) || IsFakeClient(iClient)) return Plugin_Handled;
	Menu_Shut(iClient);
	return Plugin_Handled;
}

void Frame_MenuClosed(int iUserId) {
	int iClient = GetClientOfUserId(iUserId);
	if (!iClient || !IsClientInGame(iClient)) return;
	g_bMenuDismiss[iClient] = true;
	g_iLiveMenu[iClient] = 0;
	g_iCmdPage[iClient] = 0;
	CancelClientMenu(iClient, true);
	g_bMenuDismiss[iClient] = false;
}

public Action Cmd_CtrlDown(int iClient, int iArgs) {
	if (iClient) g_bCtrl[iClient] = true;
	return Plugin_Handled;
}

public Action Cmd_CtrlUp(int iClient, int iArgs) {
	if (iClient) g_bCtrl[iClient] = false;
	return Plugin_Handled;
}

void Group_Save(int iClient, int key) {
	ArrayList h = g_eCommander[iClient].hSelectedUnits;
	int n;
	for (int i = 0; i < h.Length && n < 12; i++) g_iGroup[iClient][key][n++] = h.Get(i);
	g_iGroupN[iClient][key] = n;
	PrintHintText(iClient, "Group %d saved  (%d)", key, n);
}

void Group_Recall(int iClient, int key) {
	float fNow = GetGameTime();
	bool bCenter = fNow - g_fGroupTap[iClient][key] < 0.35;
	g_fGroupTap[iClient][key] = fNow;
	ClearUnitSelection(iClient);
	float vecSum[3];
	int n;
	for (int i = 0; i < g_iGroupN[iClient][key]; i++) {
		int e = EntRefToEntIndex(g_iGroup[iClient][key][i]);
		if (e <= 0 || !IsValidEntity(e)) continue;
		if (e <= MaxClients && !IsPlayerAlive(e)) continue;
		SelectUnit(iClient, e);
		float p[3];
		GetEntPropVector(e, Prop_Data, "m_vecAbsOrigin", p);
		AddVectors(vecSum, p, vecSum);
		n++;
	}
	if (bCenter && n) {
		ScaleVector(vecSum, 1.0 / float(n));
		Camera_GoTo(iClient, vecSum);
	}
	if (!n) PrintHintText(iClient, "Group %d is empty", key);
}

void CmdPanel_Close(int iClient) {
	if (iClient <= 0) return;
	g_iCmdPage[iClient] = 0;
	g_sCmdLast[iClient][0] = 0;
	if (IsClientInGame(iClient)) ClearSyncHud(iClient, g_hHudMenu);
}

void Ai_ShowMenu(int iClient) {
	if (Menu_Hold(iClient)) return;
	int t = GetClientTeam(iClient);
	char sMode[16];
	Ai_ModeName(t, sMode, sizeof(sMode));
	Menu hMenu = new Menu(MenuHandler_AI);
	hMenu.SetTitle("AI COMMANDS    now %s\nAttack pushes their HQ.\nDefend holds every intel seat.\nMix is half of each.\n ", sMode);
	hMenu.AddItem("atk", g_iAiMode[t] == AI_ATTACK ? "Attack    [on]" : "Attack");
	hMenu.AddItem("def", g_iAiMode[t] == AI_DEFEND ? "Defend    [on]" : "Defend");
	hMenu.AddItem("mix", g_iAiMode[t] == AI_MIX ? "Mix    [on]" : "Mix");
	hMenu.ExitBackButton = true;
	hMenu.Display(iClient, MENU_TIME_FOREVER);
	Menu_Mark(iClient, 8);
}

public int MenuHandler_AI(Menu hMenu, MenuAction eAction, int iClient, int iItem) {
	if (eAction == MenuAction_End) delete hMenu;
	else if (eAction == MenuAction_Cancel && !Menu_Refreshing(iClient) && iItem == MenuCancel_ExitBack) ShowCommanderMenu(iClient);
	else if (eAction == MenuAction_Select) {
		char sInfo[8];
		hMenu.GetItem(iItem, sInfo, sizeof(sInfo));
		int t = GetClientTeam(iClient);
		if (t >= CS_TEAM_T && t <= CS_TEAM_CT) {
			int iMode = AI_MIX;
			if (StrEqual(sInfo, "atk")) iMode = AI_ATTACK;
			else if (StrEqual(sInfo, "def")) iMode = AI_DEFEND;
			if (g_iAiMode[t] != iMode) {
				g_iAiMode[t] = iMode;
				Ai_Touch(t);
				LogMessage("AI team %d set to %s", t, sInfo);
			}
		}
		Ai_ShowMenu(iClient);
	}
	return 0;
}

void ShowCommanderMenu(int iClient) {
	if (Menu_Hold(iClient)) return;
	CmdPanel_Close(iClient);
	int t = GetClientTeam(iClient);
	Menu hMenu = new Menu(MenuHandler_Commander);
	hMenu.SetTitle("COMMAND   %s\nIntel %d     Workers %d/%d (%d at desks)\n ", t == CS_TEAM_CT ? "CT" : "T",
		g_iIntel[t], Npc_Count(Npc_Worker, t), g_hCvarWorkerCap.IntValue, CountSeatedWorkers(t));
	char sItem[96];
	FormatEx(sItem, sizeof(sItem), "Research    %d / %d", Unlocks_Count(t), g_iUnlocks);
	hMenu.AddItem("unl", sItem);
	FormatEx(sItem, sizeof(sItem), "Train    %d units", Train_Count(t));
	hMenu.AddItem("train", sItem);
	hMenu.AddItem("build", "Build    sandbags, wall, fence, turret, mine");
	hMenu.AddItem("sol", "Play as soldier");
	char sMode[16];
	Ai_ModeName(t, sMode, sizeof(sMode));
	FormatEx(sItem, sizeof(sItem), "AI Commands    %s", sMode);
	hMenu.AddItem("ai", sItem);
	hMenu.ExitButton = true;
	hMenu.Display(iClient, MENU_TIME_FOREVER);
	Menu_Mark(iClient, 1);
}

void Menu_Back(int iClient) {
	int k = g_iLiveMenu[iClient];
	g_iLiveMenu[iClient] = 0;
	if (k == 4) { Unlocks_ShowMenu(iClient); return; }
	if (k == 7) { Armory_ShowRestockMenu(iClient); return; }
	if (k == 8) { ShowCommanderMenu(iClient); return; }
	if (k <= 1) { CancelClientMenu(iClient); return; }
	ShowCommanderMenu(iClient);
}

void Menu_Tick(int iClient) {
	if (!g_iLiveMenu[iClient] || !g_eCommander[iClient].bEnabled) return;
	if (GetClientMenu(iClient) == MenuSource_None) { g_iLiveMenu[iClient] = 0; return; }
	if (GetGameTime() - g_fMenuRefresh[iClient] < 1.0) return;
	g_fMenuRefresh[iClient] = GetGameTime();
	g_bMenuRefreshing[iClient] = true;
	int t = GetClientTeam(iClient);
	if ((g_iLiveMenu[iClient] == 3 || g_iLiveMenu[iClient] == 4) && g_iResearchId[t] == g_iMenuSeenResearch[iClient]) {
		g_bMenuRefreshing[iClient] = false;
		return;
	}
	if (g_iLiveMenu[iClient] == 6 || g_iLiveMenu[iClient] == 7 || g_iLiveMenu[iClient] == 8) {
		g_bMenuRefreshing[iClient] = false;
		return;
	}
	g_iMenuSeenResearch[iClient] = (t >= CS_TEAM_T && t <= CS_TEAM_CT) ? g_iResearchId[t] : -2;
	if (g_iLiveMenu[iClient] == 1) ShowCommanderMenu(iClient);
	else if (g_iLiveMenu[iClient] == 2) Train_ShowMenu(iClient);
	else if (g_iLiveMenu[iClient] == 3) Unlocks_ShowMenu(iClient);
	else if (g_iLiveMenu[iClient] == 4) Unlocks_ShowCat(iClient, g_iLiveCat[iClient]);
	else if (g_iLiveMenu[iClient] == 5) Build_ShowMenu(iClient);
	else g_bMenuRefreshing[iClient] = false;
}

void CmdPanel_OpenStock(int iClient) {
	g_iCmdPage[iClient] = 3;
	g_sCmdLast[iClient][0] = 0;
}

bool Group_CtrlDown(int iClient) {
	if (g_bCtrl[iClient]) return true;
	return (GetClientButtons(iClient) & IN_DUCK) != 0;
}

public Action Cmd_MenuSlot(int iClient, const char[] sCmd, int iArgs) {
	if (!iClient || !g_eCommander[iClient].bEnabled) return Plugin_Continue;
	int key = sCmd[4] == '1' && sCmd[5] == '0' ? 0 : (view_as<int>(sCmd[4]) - view_as<int>('0'));
	if (key >= 1 && key <= 9 && Group_CtrlDown(iClient)) {
		Group_Save(iClient, key);
		return Plugin_Handled;
	}
	if (g_iCmdPage[iClient]) {
		CmdPanel_Pick(iClient, key);
		return Plugin_Handled;
	}
	if (GetClientMenu(iClient) != MenuSource_None) return Plugin_Continue;
	if (key < 1 || key > 9) return Plugin_Continue;
	Group_Recall(iClient, key);
	return Plugin_Handled;
}

void CmdPanel_Pick(int iClient, int key) {
	int page = g_iCmdPage[iClient];
	int t = GetClientTeam(iClient);
	if (page == 1) {
		if (key == 1) { g_iCmdPage[iClient] = 0; Unlocks_ShowMenu(iClient); }
		else if (key == 2) g_iCmdPage[iClient] = 5;
		else if (key == 3) g_iCmdPage[iClient] = 2;
		else if (key == 4) {
			g_iCmdPage[iClient] = 0;
			g_bWantsCommander[iClient] = false;
			g_bDeclinedCmdr[iClient] = true;
			if (g_hCvarBodyless.BoolValue) SchedulePending(iClient, Pending_LeaveRole);
			else ReleaseCommander(iClient);
		} else if (key == 5) g_iCmdPage[iClient] = 4;
		else if (key == 0) Menu_Shut(iClient);
	} else if (page == 4) {
		int iMode = -1;
		if (key == 1) iMode = AI_ATTACK;
		else if (key == 2) iMode = AI_DEFEND;
		else if (key == 3) iMode = AI_MIX;
		else if (key == 0) g_iCmdPage[iClient] = 1;
		if (iMode != -1 && t >= CS_TEAM_T && t <= CS_TEAM_CT && g_iAiMode[t] != iMode) {
			g_iAiMode[t] = iMode;
			Ai_Touch(t);
		}
	} else if (page == 5) {
		if (key == 1) {
			g_iCmdPage[iClient] = 0;
			if (g_eCommander[iClient].bEnabled && Worker_CanHire(iClient)) Ghost_Start(iClient, Ghost_Worker);
		} else if (key == 2) Train_Queue(iClient, 0);
		else if (key == 3) Train_Queue(iClient, 1);
		else if (key == 0) g_iCmdPage[iClient] = 1;
	} else if (page == 2) {
		if ((key >= 1 && key <= 4 || key == 6) && g_iIntel[t] >= Build_Cost(key)) { g_iCmdPage[iClient] = 0; Build_Begin(iClient, key); }
		else if (key == 0) g_iCmdPage[iClient] = 1;
	} else if (page == 3) {
		if (key == 0) g_iCmdPage[iClient] = 1;
	}
	g_sCmdLast[iClient][0] = 0;
}

void CmdPanel_Text(int iClient, char[] s, int n) {
	int t = GetClientTeam(iClient);
	int page = g_iCmdPage[iClient];
	if (page == 2) {
		FormatEx(s, n, "BUILD          Intel %d\n1  Sandbags     %d\n2  Wall         %d\n3  Turret       %d\n4  Mine         %d\n6  Fence        %d\n0  Back", g_iIntel[t], Build_Cost(1), Build_Cost(2), Build_Cost(3), Build_Cost(4), Build_Cost(6));
		return;
	}
	if (page == 3) {
		FormatEx(s, n, "ARMORY         Intel %d\n", g_iIntel[t]);
		int shown;
		for (int k = 0; k < g_iArmory && shown < 8; k++) {
			int u = Unlock_ForItem(g_eArmory[k].sKey);
			if (u != -1 && !g_bUnlocked[t][u]) continue;
			Format(s, n, "%s%s  x%d\n", s, g_eArmory[k].sName, g_iStock[t][k]);
			shown++;
		}
		if (!shown) StrCat(s, n, "Nothing stocked yet\n");
		StrCat(s, n, "0  Back");
		return;
	}
	if (page == 4) {
		char sMode[16];
		Ai_ModeName(t, sMode, sizeof(sMode));
		FormatEx(s, n, "AI COMMANDS    now %s\n1  Attack%s\n2  Defend%s\n3  Mix%s\n0  Back     F1  Close",
			sMode,
			g_iAiMode[t] == AI_ATTACK ? "    [on]" : "",
			g_iAiMode[t] == AI_DEFEND ? "    [on]" : "",
			g_iAiMode[t] == AI_MIX ? "    [on]" : "");
		return;
	}
	if (page == 5) {
		FormatEx(s, n, "TRAIN    Intel %d    Units %d\n1  Hire worker    %d\n2  Rifleman    %d\n3  Elite    %d\n0  Back     F1  Close",
			g_iIntel[t], Train_Count(t), Worker_NextCost(t), Train_Cost(0), Train_Cost(1));
		return;
	}
	char sMode[16];
	Ai_ModeName(t, sMode, sizeof(sMode));
	FormatEx(s, n, "COMMAND   %s\nIntel %d     Workers %d/%d (%d at desks)\n1  Research    %d / %d\n2  Train    %d units\n3  Build\n4  Play as soldier\n5  AI Commands    %s\n0 / F1  Close",
		t == CS_TEAM_CT ? "CT" : "T", g_iIntel[t], Npc_Count(Npc_Worker, t), g_hCvarWorkerCap.IntValue, CountSeatedWorkers(t),
		Unlocks_Count(t), g_iUnlocks, Train_Count(t), sMode);
}

public int MenuHandler_Commander(Menu hMenu, MenuAction eAction, int iClient, int iItem) {
	if (eAction == MenuAction_End) {
		delete hMenu;
	} else if (eAction == MenuAction_Cancel) {
		if (!Menu_Refreshing(iClient)) g_iLiveMenu[iClient] = 0;
	} else if (eAction == MenuAction_Select) {
		char sInfo[8];
		hMenu.GetItem(iItem, sInfo, sizeof(sInfo));
		if (GetCommanderTeam(iClient) == 0) return 0;
		if (StrEqual(sInfo, "unl")) {
			Unlocks_ShowMenu(iClient);
		} else if (StrEqual(sInfo, "train")) {
			Train_ShowMenu(iClient);
		} else if (StrEqual(sInfo, "build")) {
			Build_ShowMenu(iClient);
		} else if (strncmp(sInfo, "ab", 2) == 0) {
			Ability_Begin(iClient, view_as<AbilityId>(StringToInt(sInfo[2])));
		} else if (StrEqual(sInfo, "ai")) {
			Ai_ShowMenu(iClient);
		} else if (StrEqual(sInfo, "sol")) {
			g_bWantsCommander[iClient] = false;
			g_bDeclinedCmdr[iClient] = true;
			if (g_hCvarBodyless.BoolValue) SchedulePending(iClient, Pending_LeaveRole);
			else ReleaseCommander(iClient);
			PrintToChat(iClient, "\x04[RTS]\x01 Playing as Soldier. Type \x04!rts\x01 any time for the role menu.");
		}
	}
	return 0;
}
