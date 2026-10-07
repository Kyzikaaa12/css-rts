// css_rts/role.sp -- commander role, listen-host resolution, join menu, post view enter/exit

int g_iCommanderUserId[4];
bool g_bPostView[MAXPLAYERS+1];      // in the commander view *at the post* (counts for Intel)
float g_fViewToggleTime[MAXPLAYERS+1];
int g_iLastButtons[MAXPLAYERS+1];
bool g_bMenuShown[MAXPLAYERS+1];
bool g_bWantsCommander[MAXPLAYERS+1];
char g_sLastExitReason[MAXPLAYERS+1][32];

// Listen server: commands typed/bound by the host arrive as client 0. Map them to the host.
int ResolveClient(int iClient) {
	if (iClient != 0 || IsDedicatedServer()) return iClient;
	for (int i=1; i<=MaxClients; i++) {
		if (IsClientInGame(i) && !IsFakeClient(i)) return i;
	}
	return 0;
}

int GetTeamCommander(int iTeam) {
	if (!(CS_TEAM_T <= iTeam <= CS_TEAM_CT)) return 0;
	int iClient = GetClientOfUserId(g_iCommanderUserId[iTeam]);
	if (iClient && IsClientInGame(iClient) && GetClientTeam(iClient) == iTeam) return iClient;
	g_iCommanderUserId[iTeam] = 0;
	return 0;
}

int GetCommanderTeam(int iClient) {
	for (int t=CS_TEAM_T; t<=CS_TEAM_CT; t++) {
		if (g_iCommanderUserId[t] && GetClientOfUserId(g_iCommanderUserId[t]) == iClient) return t;
	}
	return 0;
}

bool AssignCommander(int iClient, bool bAnnounce=true) {
	int iTeam = GetClientTeam(iClient);
	if (!(CS_TEAM_T <= iTeam <= CS_TEAM_CT)) return false;
	int iCur = GetTeamCommander(iTeam);
	if (iCur && iCur != iClient) return false;
	ReleaseCommander(iClient, false); // drop any other team's role
	g_iCommanderUserId[iTeam] = GetClientUserId(iClient);
	if (bAnnounce) {
		for (int i=1; i<=MaxClients; i++) {
			if (i != iClient && IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) == iTeam) PrintToChat(i, "\x04[RTS]\x01 %N is your \x04Commander\x01.", iClient);
		}
		if (!IsFakeClient(iClient)) PrintToChat(iClient, "\x04[RTS]\x01 You are the \x04Commander\x01.  F2 = menu");
	}
	return true;
}

void ReleaseCommander(int iClient, bool bAnnounce=true) {
	int iTeam = GetCommanderTeam(iClient);
	if (!iTeam) return;
	g_iCommanderUserId[iTeam] = 0;
	CancelPending(iClient);
	if (g_eCommander[iClient].bEnabled) ResetClient(iClient);
	RestoreCommanderBody(iClient);
	if (IsClientInGame(iClient) && !IsFakeClient(iClient)) {
		ClientCommand(iClient, "bind b buymenu");
	}
	if (bAnnounce && IsClientInGame(iClient)) {
		for (int i=1; i<=MaxClients; i++) {
			if (IsClientInGame(i) && GetClientTeam(i) == iTeam) PrintToChat(i, "\x04[RTS]\x01 %N left the Commander role (!commander to take it).", iClient);
		}
	}
}

// Enter the RTS camera at the post. bForce skips the "near terminal" requirement (F2 / !rts / menu).
bool EnterCommanderView(int iClient, bool bForce, char[] sWhy, int iWhyLen) {
	int iTeam = GetClientTeam(iClient);
	if (!IsPlayerAlive(iClient)) { strcopy(sWhy, iWhyLen, "you must be alive"); return false; }
	if (GetTeamCommander(iTeam) != iClient) { strcopy(sWhy, iWhyLen, "you are not the commander"); return false; }
	if (!bForce && GetAimedTerminal(iClient) != iTeam) { strcopy(sWhy, iWhyLen, "not at your terminal"); return false; }
	if (g_eCommander[iClient].bEnabled) ResetClient(iClient);

	float vecMins[3], vecMaxs[3], vecStart[3], vecBuy[3], vecBuyAng[3];
	GetCameraBounds(iTeam, vecMins, vecMaxs);
	float fYaw = 0.0;
	if (PickBuySpawn(iTeam, vecBuy, vecBuyAng)) {
		vecStart = vecBuy;
		fYaw = vecBuyAng[1];
	} else if (g_ePost[iTeam].bHasCamStart) {
		vecStart = g_ePost[iTeam].vecCamStart;
		if (g_ePost[iTeam].bValid) fYaw = g_ePost[iTeam].vecAngles[1];
	} else if (g_ePost[iTeam].bValid) {
		vecStart = g_ePost[iTeam].vecOrigin;
		fYaw = g_ePost[iTeam].vecAngles[1];
	} else GetClientAbsOrigin(iClient, vecStart);

	TeleportEntity(iClient, NULL_VECTOR, NULL_VECTOR, view_as<float>({0.0, 0.0, 0.0}));
	SetupClient(iClient, vecMins, vecMaxs, vecStart);
	g_fZoomTarget[iClient] = 700.0;
	Camera_Reset(iClient, vecStart, fYaw);
	if (!g_eCommander[iClient].bEnabled) { strcopy(sWhy, iWhyLen, "camera setup failed"); return false; }
	g_bPostView[iClient] = true;
	g_fViewToggleTime[iClient] = GetGameTime();
	if (g_hCvarBodyless.BoolValue) {
		HideCommanderBody(iClient);
	} else {
		// point_viewcontrol's Enable sets the player to DAMAGE_NO; legacy mode keeps the body exposed
		SetEntProp(iClient, Prop_Data, "m_takedamage", 2); // DAMAGE_YES
	}
	if (!IsFakeClient(iClient)) {
		Hud_OnEnterView(iClient);   // v0.5.2: controls help lives in the HUD panel (H toggles)
	}
	strcopy(sWhy, iWhyLen, "ok");
	return true;
}

void ExitCommanderView(int iClient, const char[] sReason) {
	if (!g_eCommander[iClient].bEnabled) return;
	bool bWasPost = g_bPostView[iClient];
	ResetClient(iClient);
	strcopy(g_sLastExitReason[iClient], sizeof(g_sLastExitReason[]), sReason);
	g_fViewToggleTime[iClient] = GetGameTime();
	if (bWasPost && IsClientInGame(iClient) && !IsFakeClient(iClient) && !StrEqual(sReason, "use")) {
		PrintHintText(iClient, "Left command view (%s)", sReason);
	}
}

// USE pressed (edge) while not in the camera.
void TryUseTerminal(int iClient) {
	if (GetGameTime() - g_fViewToggleTime[iClient] < 0.4) return;
	int iTeam = GetClientTeam(iClient);
	int iTermTeam = GetAimedTerminal(iClient);
	if (!iTermTeam) return;
	if (iTermTeam != iTeam) {
		PrintHintText(iClient, "Enemy command post");
		return;
	}
	int iCmdr = GetTeamCommander(iTeam);
	if (!iCmdr && g_hCvarAutoCommander.BoolValue && (!IsFakeClient(iClient) || g_bSelfTestRunning)) {
		AssignCommander(iClient);
		iCmdr = iClient;
	}
	if (iCmdr != iClient) {
		if (!IsFakeClient(iClient)) Armory_ShowAvailable(iClient);
		return;
	}
	if (g_hCvarBodyless.BoolValue) {
		CommanderStart(iClient);
		return;
	}
	char sWhy[64];
	if (!EnterCommanderView(iClient, false, sWhy, sizeof(sWhy))) PrintHintText(iClient, "Cannot command: %s", sWhy);
}

// F2 / !rts: toggle the view (commander only), or open the role menu.
void ToggleCommanderView(int iClient) {
	if (g_eCommander[iClient].bEnabled && g_bPostView[iClient] && g_hCvarBodyless.BoolValue) {
		ShowRoleMenu(iClient);
		return;
	}
	if (g_eCommander[iClient].bEnabled) {
		ExitCommanderView(iClient, "use");
		return;
	}
	if (GetTeamCommander(GetClientTeam(iClient)) != iClient) {
		ShowRoleMenu(iClient);
		return;
	}
	if (g_hCvarBodyless.BoolValue) {
		SchedulePending(iClient, Pending_EnterView);
		return;
	}
	char sWhy[64];
	bool bForce = !g_hCvarRequireTerminal.BoolValue;
	if (!EnterCommanderView(iClient, bForce, sWhy, sizeof(sWhy))) {
		PrintToChat(iClient, "\x04[RTS]\x01 Cannot enter command view: %s.", sWhy);
	}
}

void ShowRoleMenu(int iClient) {
	if (IsFakeClient(iClient)) return;
	if (GetClientMenu(iClient) != MenuSource_None) { Menu_Back(iClient); return; }
	int iTeam = GetClientTeam(iClient);
	if (InLobby() && IsHost(iClient) && iClient == Lobby_Host() && !g_bUsedCreateSettings) {
		Lobby_ShowMenu(iClient);
		return;
	}
	int iCmdr = GetTeamCommander(iTeam);
	if (iCmdr && iCmdr == iClient) {
		if (Wheel_Enabled(iClient)) { Wheel_Toggle(iClient); return; }
		ShowCommanderMenu(iClient);
		return;
	}
	Menu hMenu = new Menu(MenuHandler_Role);
	if (CS_TEAM_T <= iTeam <= CS_TEAM_CT) {
		if (iCmdr && iCmdr != iClient) hMenu.SetTitle("CSS RTS - %s\nCommander: %N\n ", iTeam == CS_TEAM_CT ? "Counter-Terrorists" : "Terrorists", iCmdr);
		else hMenu.SetTitle("CSS RTS - %s\nChoose your role:\n ", iTeam == CS_TEAM_CT ? "Counter-Terrorists" : "Terrorists");
	} else {
		hMenu.SetTitle("CSS RTS\nJoin T or CT first, then choose your role.\n ");
	}
	hMenu.AddItem("cmd", iCmdr == iClient ? "Stay Commander" : "Play as Commander (RTS view, no body)", (iCmdr && iCmdr != iClient) ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
	hMenu.AddItem("sol", "Play as Soldier (FPS)");
	if (CS_TEAM_T <= iTeam <= CS_TEAM_CT) hMenu.AddItem("team", iTeam == CS_TEAM_CT ? "Switch to Terrorists" : "Switch to Counter-Terrorists");
	hMenu.ExitButton = true;
	hMenu.Display(iClient, 30);
}

public int MenuHandler_Role(Menu hMenu, MenuAction eAction, int iClient, int iItem) {
	if (eAction == MenuAction_End) {
		delete hMenu;
	} else if (eAction == MenuAction_Select) {
		char sInfo[8];
		hMenu.GetItem(iItem, sInfo, sizeof(sInfo));
		if (StrEqual(sInfo, "team")) {
			AutoJoin_SwitchTeam(iClient, GetClientTeam(iClient) == CS_TEAM_CT ? CS_TEAM_T : CS_TEAM_CT);
		} else if (StrEqual(sInfo, "cmd")) {
			int iTeam = GetClientTeam(iClient);
			if (!(CS_TEAM_T <= iTeam <= CS_TEAM_CT)) {
				g_bWantsCommander[iClient] = true;
				PrintToChat(iClient, "\x04[RTS]\x01 Join T or CT: you will become Commander when you spawn.");
			} else if (AssignCommander(iClient)) {
				if (IsPlayerAlive(iClient) && !g_eCommander[iClient].bEnabled) CommanderStart(iClient);
			} else {
				PrintToChat(iClient, "\x04[RTS]\x01 Your team already has a Commander.");
			}
		} else {
			g_bWantsCommander[iClient] = false;
			g_bDeclinedCmdr[iClient] = true;
			if (GetCommanderTeam(iClient) && g_hCvarBodyless.BoolValue) SchedulePending(iClient, Pending_LeaveRole);
			else ReleaseCommander(iClient);
			PrintToChat(iClient, "\x04[RTS]\x01 Playing as Soldier. Type \x04!rts\x01 any time for the role menu.");
		}
	}
	return 0;
}

// Commander became active (role taken while alive, or spawned): bodyless mode hides the body now
// and enters the view after the countdown.
void CommanderStart(int iClient) {
	if (g_eCommander[iClient].bEnabled || g_ePending[iClient] == Pending_EnterView) return;
	if (g_hCvarBodyless.BoolValue) {
		HideCommanderBody(iClient);
		char sWhy[64];
		if (!EnterCommanderView(iClient, true, sWhy, sizeof(sWhy)) && !IsFakeClient(iClient)) PrintToChat(iClient, "\x04[RTS]\x01 Cannot enter command view: %s.", sWhy);
	} else if (!g_hCvarRequireTerminal.BoolValue) {
		char sWhy[64];
		EnterCommanderView(iClient, true, sWhy, sizeof(sWhy));
	}
}
