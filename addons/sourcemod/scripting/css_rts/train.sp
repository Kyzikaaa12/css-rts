// css_rts/train.sp -- Train combat units at the command post. They are NPCs, not player slots.
// F2 > Train. They hold the rally until ordered, and shoot anyone who walks into range.

#define TRAIN_QUEUE 6
#define TRAIN_CAP 8

int g_iTrainQ[4][TRAIN_QUEUE];
int g_iTrainN[4];
float g_fTrainDone[4];
float g_vecSoldierOrder[MAX_NPCS][3];
bool g_bSoldierOrder[MAX_NPCS];
float g_fSoldierShot[MAX_NPCS];
int g_iSoldierKind[MAX_NPCS];
bool g_bTrained[MAXPLAYERS+1];
int g_iTrainedKind[MAXPLAYERS+1];
int g_iEliteProp[MAXPLAYERS+1];
int g_iEliteGun[MAXPLAYERS+1];
char g_sEliteAnim[MAXPLAYERS+1][16];
float g_fTrainedFree[MAXPLAYERS+1];
float g_vecTrainHold[MAXPLAYERS+1][3];
bool g_bTrainHold[MAXPLAYERS+1];
int g_iTrainWaitKind[4][8];
int g_iTrainWaitN[4];
int g_iTrainIssued[4];
float g_fTrainIssueTime[4];

bool Train_Is(int iClient) {
	return iClient >= 1 && iClient <= MaxClients && g_bTrained[iClient];
}

int Train_Count(int iTeam) {
	int n;
	for (int i=1; i<=MaxClients; i++) if (Train_Is(i) && IsClientInGame(i) && GetClientTeam(i) == iTeam && IsPlayerAlive(i)) n++;
	return n;
}

int Train_Extra(int iTeam) {
	if (iTeam < CS_TEAM_T || iTeam > CS_TEAM_CT) return 0;
	return Train_Count(iTeam) + g_iTrainWaitN[iTeam];
}

void Train_ClearClient(int iClient) {
	if (g_iEliteGun[iClient] > 0 && IsValidEntity(g_iEliteGun[iClient])) RemoveEntity(g_iEliteGun[iClient]);
	if (g_iEliteProp[iClient] > 0 && IsValidEntity(g_iEliteProp[iClient])) RemoveEntity(g_iEliteProp[iClient]);
	g_iEliteGun[iClient] = 0;
	g_iEliteProp[iClient] = 0;
	g_bTrained[iClient] = false;
	g_bTrainHold[iClient] = false;
}

void Train_NoteOrder(int iClient, const float vecPos[3]) {
	if (!Train_Is(iClient)) return;
	g_vecTrainHold[iClient] = vecPos;
	g_bTrainHold[iClient] = true;
}

bool Train_Hold(int iClient) {
	if (!Train_Is(iClient)) return false;
	return g_fOrderedUntil[iClient] > GetGameTime();
}

void Train_MapStart() {
	Train_Reset();
	PrecacheModel("models/humans/group01/male_07.mdl", true);
	PrecacheModel("models/humans/group01/male_09.mdl", true);
	PrecacheModel("sprites/laserbeam.vmt", true);
	PrecacheModel("models/weapons/w_mach_m249para.mdl", true);
	PrecacheModel("models/player/ct_gsg9.mdl", true);
	PrecacheModel("models/player/t_arctic.mdl", true);
	CreateTimer(0.35, Timer_Train, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	static bool bHooked;
	if (!bHooked) {
		HookEvent("player_spawn", Event_TrainSpawn);
		HookEvent("player_death", Event_EliteDie, EventHookMode_Pre);
		bHooked = true;
	}
}

void Train_Reset() {
	for (int t=0; t<4; t++) { g_iTrainN[t] = 0; g_fTrainDone[t] = 0.0; g_iTrainWaitN[t] = 0; g_iTrainIssued[t] = 0; }
	for (int i=0; i<MAX_NPCS; i++) g_bSoldierOrder[i] = false;
	for (int i=1; i<=MaxClients; i++) Train_ClearClient(i);
}

int Train_Cost(int iKind) {
	return iKind == 1 ? 480 : 240;
}

float Train_Time(int iKind) {
	return iKind == 1 ? 10.0 : 8.0;
}

void Train_Name(int iKind, char[] s, int n) {
	strcopy(s, n, iKind == 1 ? "Elite" : "Rifleman");
}

void Train_AppendHud(int iTeam, char[] s, int n) {
	if (g_iTrainN[iTeam] <= 0) return;
	char sName[24];
	Train_Name(g_iTrainQ[iTeam][0], sName, sizeof(sName));
	int iLeft = RoundToCeil(g_fTrainDone[iTeam] - GetGameTime());
	if (iLeft < 0) iLeft = 0;
	Format(s, n, "%s\nTraining %s %ds", s, sName, iLeft);
	if (g_iTrainN[iTeam] > 1) Format(s, n, "%s   +%d", s, g_iTrainN[iTeam] - 1);
}

void Train_ShowMenu(int iClient) {
	if (Menu_Hold(iClient)) return;
	int t = GetClientTeam(iClient);
	Menu hMenu = new Menu(MenuHandler_Train);
	char sTitle[192], sName[24];
	FormatEx(sTitle, sizeof(sTitle), "TRAIN    Intel %d    Units %d\nA real soldier. Buys for 10s, then you command them.\n", g_iIntel[t], Train_Count(t));
	if (g_iTrainN[t] > 0) {
		Train_Name(g_iTrainQ[t][0], sName, sizeof(sName));
		Format(sTitle, sizeof(sTitle), "%sNow  %s  %ds    queue %d\n", sTitle, sName, RoundToCeil(g_fTrainDone[t] - GetGameTime()), g_iTrainN[t]);
	}
	hMenu.SetTitle(sTitle);
	char sItem[64];
	int iCost = Worker_NextCost(t);
	bool bWCap = Npc_Count(Npc_Worker, t) >= g_hCvarWorkerCap.IntValue;
	if (bWCap) FormatEx(sItem, sizeof(sItem), "Hire worker    cap reached");
	else FormatEx(sItem, sizeof(sItem), "Hire worker    %d Intel", iCost);
	hMenu.AddItem("hire", sItem, (bWCap || g_iIntel[t] < iCost) ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
	bool bCap = Train_Count(t) + g_iTrainN[t] + g_iTrainWaitN[t] >= TRAIN_CAP;
	bool bFull = g_iTrainN[t] >= TRAIN_QUEUE;
	FormatEx(sItem, sizeof(sItem), "Rifleman    %d Intel    8s", Train_Cost(0));
	hMenu.AddItem("0", sItem, (!bCap && !bFull && g_iIntel[t] >= Train_Cost(0)) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	FormatEx(sItem, sizeof(sItem), "Combine Elite    %d Intel    10s", Train_Cost(1));
	hMenu.AddItem("1", sItem, (!bCap && !bFull && g_iIntel[t] >= Train_Cost(1)) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	hMenu.ExitBackButton = true;
	hMenu.Display(iClient, MENU_TIME_FOREVER);
	Menu_Mark(iClient, 2);
}

public int MenuHandler_Train(Menu hMenu, MenuAction eAction, int iClient, int iItem) {
	if (eAction == MenuAction_End) delete hMenu;
	else if (eAction == MenuAction_Cancel && !Menu_Refreshing(iClient) && iItem == MenuCancel_ExitBack && GetCommanderTeam(iClient)) ShowCommanderMenu(iClient);
	else if (eAction == MenuAction_Select) {
		char s[8];
		hMenu.GetItem(iItem, s, sizeof(s));
		if (StrEqual(s, "hire")) {
			if (g_eCommander[iClient].bEnabled && Worker_CanHire(iClient)) Ghost_Start(iClient, Ghost_Worker);
			else Train_ShowMenu(iClient);
		} else {
			Train_Queue(iClient, StringToInt(s));
			Train_ShowMenu(iClient);
		}
	}
	return 0;
}

void Train_Queue(int iClient, int iKind) {
	int t = GetClientTeam(iClient);
	if (t < CS_TEAM_T || t > CS_TEAM_CT) return;
	if (Train_Count(t) + g_iTrainN[t] + g_iTrainWaitN[t] >= TRAIN_CAP) { PrintHintText(iClient, "Unit cap"); return; }
	if (g_iTrainN[t] >= TRAIN_QUEUE) { PrintHintText(iClient, "Queue is full"); return; }
	int iCost = Train_Cost(iKind);
	if (g_iIntel[t] < iCost) { PrintHintText(iClient, "Need %d Intel", iCost); return; }
	g_iIntel[t] -= iCost;
	g_iTrainQ[t][g_iTrainN[t]] = iKind;
	g_iTrainN[t]++;
	if (g_iTrainN[t] == 1) g_fTrainDone[t] = GetGameTime() + Train_Time(iKind);
	char sName[24];
	Train_Name(iKind, sName, sizeof(sName));
	PrintHintText(iClient, "%s training. %d in queue.", sName, g_iTrainN[t]);
	VsAi_MirrorTrain(t, iKind);
}

void VsAi_MirrorTrain(int iTeam, int iKind) {
	if (!VsAi_FromPlayer(iTeam)) return;
	int e = VsAi_Enemy();
	if (e < CS_TEAM_T || e > CS_TEAM_CT) return;
	if (Train_Count(e) + g_iTrainN[e] + g_iTrainWaitN[e] >= TRAIN_CAP) return;
	if (g_iTrainN[e] >= TRAIN_QUEUE) return;
	g_bVsAiBusy = true;
	int iCost = Train_Cost(iKind);
	int iHad = g_iIntel[e];
	if (iHad < iCost) g_iIntel[e] = iCost;
	g_iIntel[e] -= iCost;
	g_iTrainQ[e][g_iTrainN[e]] = iKind;
	g_iTrainN[e]++;
	if (g_iTrainN[e] == 1) g_fTrainDone[e] = GetGameTime() + Train_Time(iKind);
	if (iHad < iCost) g_iIntel[e] = 0;
	g_bVsAiBusy = false;
}

void Train_TryAdd(int iTeam) {
	if (g_iTrainIssued[iTeam] >= g_iTrainWaitN[iTeam]) return;
	if (MaxClients - GetClientCount(false) <= 0) return;
	g_iTrainIssued[iTeam]++;
	g_fTrainIssueTime[iTeam] = GetGameTime();
	ServerCommand(iTeam == CS_TEAM_T ? "bot_add_t" : "bot_add_ct");
}

void Train_Spawn(int iTeam, int iKind) {
	if (g_iTrainWaitN[iTeam] >= 8) {
		g_iIntel[iTeam] += Train_Cost(iKind);
		return;
	}
	g_iTrainWaitKind[iTeam][g_iTrainWaitN[iTeam]] = iKind;
	g_iTrainWaitN[iTeam]++;
	Train_TryAdd(iTeam);
}

public Action Timer_Train(Handle hTimer) {
	float fNow = GetGameTime();
	if (!InLobby() && !g_bMatchOver) {
		for (int t=CS_TEAM_T; t<=CS_TEAM_CT; t++) {
			if (g_iTrainN[t] <= 0 || fNow < g_fTrainDone[t]) continue;
			int iKind = g_iTrainQ[t][0];
			for (int k=1; k<g_iTrainN[t]; k++) g_iTrainQ[t][k - 1] = g_iTrainQ[t][k];
			g_iTrainN[t]--;
			Train_Spawn(t, iKind);
			if (g_iTrainN[t] > 0) g_fTrainDone[t] = fNow + Train_Time(g_iTrainQ[t][0]);
			else g_fTrainDone[t] = 0.0;
		}
		for (int t=CS_TEAM_T; t<=CS_TEAM_CT; t++) {
			if (g_iTrainIssued[t] > 0 && fNow - g_fTrainIssueTime[t] > 4.0) g_iTrainIssued[t] = 0;
			Train_TryAdd(t);
		}
	}
	return Plugin_Continue;
}

public void Event_TrainSpawn(Event hEvent, const char[] sName, bool bDontBroadcast) {
	int iClient = GetClientOfUserId(hEvent.GetInt("userid"));
	if (!iClient || !IsFakeClient(iClient)) return;
	Train_Claim(iClient);
	CreateTimer(0.05, Timer_TrainAssign, GetClientUserId(iClient), TIMER_FLAG_NO_MAPCHANGE);
	CreateTimer(0.2, Timer_TrainRename, GetClientUserId(iClient), TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_TrainRename(Handle hTimer, int iUserId) {
	int iClient = GetClientOfUserId(iUserId);
	if (iClient) Train_ApplyLook(iClient);
	return Plugin_Stop;
}

void Train_Claim(int iClient) {
	if (!iClient || !IsClientInGame(iClient) || !IsFakeClient(iClient) || Train_Is(iClient)) return;
	int t = GetClientTeam(iClient);
	if (t < CS_TEAM_T || t > CS_TEAM_CT || g_iTrainWaitN[t] <= 0 || GetTeamCommander(t) == iClient) return;
	int iKind = g_iTrainWaitKind[t][0];
	for (int k=1; k<g_iTrainWaitN[t]; k++) g_iTrainWaitKind[t][k-1] = g_iTrainWaitKind[t][k];
	g_iTrainWaitN[t]--;
	if (g_iTrainIssued[t] > 0) g_iTrainIssued[t]--;
	g_bTrained[iClient] = true;
	g_iTrainedKind[iClient] = iKind;
	g_fTrainedFree[iClient] = 0.0;
	g_bTrainHold[iClient] = false;
	g_fBotMoved[iClient] = 0.0;
	g_fCoverUntil[iClient] = 0.0;
	Train_ApplyLook(iClient);
}

public void Event_EliteDie(Event hEvent, const char[] sName, bool bDontBroadcast) {
	int iClient = GetClientOfUserId(hEvent.GetInt("userid"));
	if (iClient < 1 || !g_bTrained[iClient] || g_iTrainedKind[iClient] != 1) return;
	if (HasEntProp(iClient, Prop_Send, "m_flModelScale")) SetEntPropFloat(iClient, Prop_Send, "m_flModelScale", 1.25);
	DataPack hPack = new DataPack();
	hPack.WriteCell(GetClientUserId(iClient));
	float v[3];
	GetClientAbsOrigin(iClient, v);
	hPack.WriteFloat(v[0]); hPack.WriteFloat(v[1]); hPack.WriteFloat(v[2]);
	CreateTimer(0.15, Timer_EliteDoll, hPack);
}

public Action Timer_EliteDoll(Handle hTimer, DataPack hPack) {
	hPack.Reset();
	int iClient = GetClientOfUserId(hPack.ReadCell());
	float v[3];
	v[0] = hPack.ReadFloat(); v[1] = hPack.ReadFloat(); v[2] = hPack.ReadFloat();
	delete hPack;
	int e = -1;
	while ((e = FindEntityByClassname(e, "cs_ragdoll")) != -1) {
		bool bMine = false;
		if (iClient > 0 && HasEntProp(e, Prop_Send, "m_hPlayer") && GetEntPropEnt(e, Prop_Send, "m_hPlayer") == iClient) bMine = true;
		if (!bMine) {
			float o[3];
			GetEntPropVector(e, Prop_Data, "m_vecAbsOrigin", o);
			bMine = GetVectorDistance(o, v) < 96.0;
		}
		if (bMine && HasEntProp(e, Prop_Send, "m_flModelScale")) SetEntPropFloat(e, Prop_Send, "m_flModelScale", 1.25);
	}
	return Plugin_Stop;
}

void Elite_SetAnim(int iProp, const char[] sAnim) {
	SetVariantString(sAnim);
	AcceptEntityInput(iProp, "SetDefaultAnimation");
	SetVariantString(sAnim);
	AcceptEntityInput(iProp, "SetAnimation");
}

void Train_ApplyLook(int iClient) {
	if (!Train_Is(iClient) || !IsPlayerAlive(iClient)) return;
	SetEntProp(iClient, Prop_Send, "m_fEffects", GetEntProp(iClient, Prop_Send, "m_fEffects") & ~32);
	if (g_iEliteProp[iClient] > 0 && IsValidEntity(g_iEliteProp[iClient])) RemoveEntity(g_iEliteProp[iClient]);
	if (g_iEliteGun[iClient] > 0 && IsValidEntity(g_iEliteGun[iClient])) RemoveEntity(g_iEliteGun[iClient]);
	g_iEliteProp[iClient] = 0;
	g_iEliteGun[iClient] = 0;
	if (g_iTrainedKind[iClient] != 1) { SetClientName(iClient, "Rifleman"); return; }
	SetEntityModel(iClient, GetClientTeam(iClient) == CS_TEAM_CT ? "models/player/ct_gsg9.mdl" : "models/player/t_arctic.mdl");
	SetEntProp(iClient, Prop_Data, "m_iHealth", 135);
	SetEntProp(iClient, Prop_Data, "m_iMaxHealth", 135);
	if (HasEntProp(iClient, Prop_Send, "m_flLaggedMovementValue")) SetEntPropFloat(iClient, Prop_Send, "m_flLaggedMovementValue", 1.3);
	if (HasEntProp(iClient, Prop_Send, "m_flModelScale")) SetEntPropFloat(iClient, Prop_Send, "m_flModelScale", 1.25);
	SetClientName(iClient, "Elite");
}

void Elite_Update(int iClient) {
	if (!Train_Is(iClient) || g_iTrainedKind[iClient] != 1) return;
	int iProp = g_iEliteProp[iClient];
	if (iProp <= 0 || !IsValidEntity(iProp) || !IsPlayerAlive(iClient)) {
		if (!IsPlayerAlive(iClient)) {
			SetEntProp(iClient, Prop_Send, "m_fEffects", GetEntProp(iClient, Prop_Send, "m_fEffects") & ~32);
		}
		return;
	}
	SetEntProp(iClient, Prop_Send, "m_fEffects", GetEntProp(iClient, Prop_Send, "m_fEffects") | 32);
	int iWeap = GetEntPropEnt(iClient, Prop_Send, "m_hActiveWeapon");
	if (iWeap > 0) SetEntProp(iWeap, Prop_Send, "m_fEffects", GetEntProp(iWeap, Prop_Send, "m_fEffects") | 32);
	float vec[3], vecAng[3], vecVel[3];
	GetClientAbsOrigin(iClient, vec);
	GetClientEyeAngles(iClient, vecAng);
	vecAng[0] = 0.0;
	vecAng[2] = 0.0;
	TeleportEntity(iProp, vec, vecAng, NULL_VECTOR);
	GetEntPropVector(iClient, Prop_Data, "m_vecVelocity", vecVel);
	float fSpd = SquareRoot(vecVel[0] * vecVel[0] + vecVel[1] * vecVel[1]);
	char sAnim[16];
	if (fSpd > 160.0) strcopy(sAnim, sizeof(sAnim), "Run");
	else if (fSpd > 25.0) strcopy(sAnim, sizeof(sAnim), "Walk");
	else strcopy(sAnim, sizeof(sAnim), "Idle1");
	if (!StrEqual(g_sEliteAnim[iClient], sAnim)) {
		strcopy(g_sEliteAnim[iClient], 16, sAnim);
		Elite_SetAnim(iProp, sAnim);
	}
}

public Action Timer_TrainAssign(Handle hTimer, int iUserId) {
	int iClient = GetClientOfUserId(iUserId);
	if (!iClient || !IsClientInGame(iClient) || !IsFakeClient(iClient) || !IsPlayerAlive(iClient) || Train_Is(iClient)) return Plugin_Stop;
	int t = GetClientTeam(iClient);
	if (t < CS_TEAM_T || t > CS_TEAM_CT || g_iTrainWaitN[t] <= 0 || GetTeamCommander(t) == iClient) return Plugin_Stop;
	int iKind = g_iTrainWaitKind[t][0];
	for (int k=1; k<g_iTrainWaitN[t]; k++) g_iTrainWaitKind[t][k-1] = g_iTrainWaitKind[t][k];
	g_iTrainWaitN[t]--;
	if (g_iTrainIssued[t] > 0) g_iTrainIssued[t]--;
	g_bTrained[iClient] = true;
	g_iTrainedKind[iClient] = iKind;
	g_bTrainHold[iClient] = false;
	g_fTrainedFree[iClient] = GetGameTime() + 10.0;
	char sName[24];
	Train_Name(iKind, sName, sizeof(sName));
	SetClientName(iClient, sName);
	return Plugin_Stop;
}

bool Train_Enemy(int i, float vecFrom[3], float fRange, float vecOut[3], int &iVictim, int &iProp) {
	iVictim = 0;
	iProp = 0;
	int iEnemy = g_eNpc[i].iTeam == CS_TEAM_T ? CS_TEAM_CT : CS_TEAM_T;
	float fBest = fRange;
	bool bHit;
	for (int c=1; c<=MaxClients; c++) {
		if (!IsClientInGame(c) || !IsPlayerAlive(c) || GetClientTeam(c) != iEnemy || g_bBodyHidden[c]) continue;
		float p[3];
		GetClientAbsOrigin(c, p);
		float d = GetVectorDistance(vecFrom, p);
		if (d < fBest) { fBest = d; vecOut = p; iVictim = c; iProp = 0; bHit = true; }
	}
	for (int n=0; n<MAX_NPCS; n++) {
		if (!g_eNpc[n].bUsed || g_eNpc[n].iTeam != iEnemy || g_eNpc[n].eState == NS_Dead) continue;
		int e = Npc_GetEntity(n);
		if (e == -1) continue;
		float p[3];
		GetEntPropVector(e, Prop_Data, "m_vecAbsOrigin", p);
		float d = GetVectorDistance(vecFrom, p);
		if (d < fBest) { fBest = d; vecOut = p; iVictim = 0; iProp = e; bHit = true; }
	}
	return bHit;
}

bool Train_CanSee(const float vecFrom[3], const float vecTo[3]) {
	float a[3], b[3];
	a = vecFrom; b = vecTo;
	a[2] += 50.0; b[2] += 40.0;
	TR_TraceRayFilter(a, b, MASK_SOLID, RayType_EndPoint, TraceFilter_WorldOnlyNoPlayers);
	return !TR_DidHit();
}

void Train_Shoot(int i, int iVictim, int iProp, const float vecHit[3]) {
	int iEnt = Npc_GetEntity(i);
	if (iEnt == -1) return;
	float v[3];
	GetEntPropVector(iEnt, Prop_Data, "m_vecAbsOrigin", v);
	float dx = vecHit[0] - v[0], dy = vecHit[1] - v[1];
	float vecAng[3];
	vecAng[1] = RadToDeg(ArcTangent2(dy, dx));
	TeleportEntity(iEnt, v, vecAng, NULL_VECTOR);
	float fDmg = g_iSoldierKind[i] == 1 ? 14.0 : 8.0;
	int iRangeEnt = iVictim ? iVictim : iProp;
	if (iRangeEnt > 0) SDKHooks_TakeDamage(iRangeEnt, iEnt, iEnt, fDmg, DMG_BULLET);
	float a[3];
	a = v; a[2] += 48.0;
	float b[3];
	b = vecHit; b[2] += 36.0;
	int iCol[4] = {255, 220, 120, 220};
	TE_SetupBeamPoints(a, b, PrecacheModel("sprites/laserbeam.vmt"), 0, 0, 0, 0.08, 1.2, 1.2, 1, 0.0, iCol, 8);
	TE_SendToAll();
	Npc_SetAnim(i, "shoot_smg1");
}

void Train_ThinkOne(int i, float fNow) {
	int iEnt = Npc_GetEntity(i);
	if (iEnt == -1) return;
	float v[3], vecHit[3];
	GetEntPropVector(iEnt, Prop_Data, "m_vecAbsOrigin", v);
	int iKind = g_iSoldierKind[i];
	float fRange = iKind == 1 ? 520.0 : 700.0;
	int iVictim, iProp;
	bool bEnemy = Train_Enemy(i, v, fRange, vecHit, iVictim, iProp);
	if (bEnemy && Train_CanSee(v, vecHit)) {
		g_eNpc[i].eState = NS_Idle;
		if (g_eNpc[i].hPath != null) g_eNpc[i].iPathIdx = g_eNpc[i].hPath.Length;
		if (fNow >= g_fSoldierShot[i]) {
			g_fSoldierShot[i] = fNow + (iKind == 1 ? 0.7 : 0.4);
			Train_Shoot(i, iVictim, iProp, vecHit);
		}
		return;
	}
	float vecGoal[3];
	bool bGo = false;
	if (g_bSoldierOrder[i]) {
		vecGoal = g_vecSoldierOrder[i];
		if (GetVectorDistance(v, vecGoal) < 48.0) g_bSoldierOrder[i] = false;
		else bGo = g_eNpc[i].eState != NS_Walking;
	}
	if (!g_bSoldierOrder[i]) {
		int t = g_eNpc[i].iTeam;
		if (g_ePost[t].bValid) GetStandSpot(g_ePost[t].vecOrigin, g_ePost[t].vecAngles[1], vecGoal);
		else if (!GetBasePoint(t, vecGoal, false)) return;
		vecGoal[0] += float((i % 5) - 2) * 36.0;
		if (GetVectorDistance(v, vecGoal) > 160.0) bGo = g_eNpc[i].eState != NS_Walking;
	}
	if (bGo) {
		float fSpeed = iKind == 1 ? 110.0 : 155.0;
		Npc_MoveTo(i, vecGoal, fSpeed, NS_Walking);
	}
}

void Soldier_Order(int i, const float vecPos[3]) {
	if (i < 0 || i >= MAX_NPCS || !g_eNpc[i].bUsed || g_eNpc[i].eKind != Npc_Soldier) return;
	g_vecSoldierOrder[i] = vecPos;
	g_bSoldierOrder[i] = true;
	float fSpeed = g_iSoldierKind[i] == 1 ? 110.0 : 155.0;
	Npc_MoveTo(i, vecPos, fSpeed, NS_Walking);
}

void Train_Label(int i, char[] s, int n) {
	char sName[24];
	Train_Name(g_iSoldierKind[i], sName, sizeof(sName));
	FormatEx(s, n, "%s %d", sName, i + 1);
}
