// css_rts/build.sp -- Commander buildings. F2 > Build, then left click to place.

#define MAX_BUILDS 32

enum BuildKind {
	Build_None = 0,
	Build_Sandbag,
	Build_Wall,
	Build_Turret,
	Build_Mine,
	Build_Guard,
	Build_Fence
}

int g_iBuildKind[MAXPLAYERS+1];
int g_iBuildGhost[MAXPLAYERS+1] = {-1, ...};
int g_iBuildEnt[MAX_BUILDS] = {-1, ...};
int g_iBuildType[MAX_BUILDS];
int g_iBuildTeam[MAX_BUILDS];
int g_iBuildHp[MAX_BUILDS];
int g_iBuildMax[MAX_BUILDS];
int g_iBuildGun[MAX_BUILDS];
float g_fBuildArm[MAX_BUILDS];
float g_fBuildHit[MAX_BUILDS];
bool g_bBotTurretHeld[MAXPLAYERS+1];
float g_fBotTurretAim[MAXPLAYERS+1];
float g_fBuildYaw[MAXPLAYERS+1];
bool g_bBuildHold[MAXPLAYERS+1];
int g_iBuildMouseX[MAXPLAYERS+1];

#define MAX_GUARDS 32
float g_vecGuardPost[4][MAX_GUARDS][3];
float g_fGuardYaw[4][MAX_GUARDS];
int g_iGuardUser[4][MAX_GUARDS];
int g_iGuardN[4];
bool g_bIsGuard[MAXPLAYERS+1];
int g_iGuardSlot[MAXPLAYERS+1];

void Build_Init() {
	HookEvent("bullet_impact", Event_BuildBullet);
	HookEvent("weapon_fire", Event_BuildFire);
	HookEvent("hegrenade_detonate", Event_BuildGrenade);
	HookEvent("player_spawn", Event_GuardSpawn);
}

bool Guard_Is(int iClient) {
	return iClient >= 1 && iClient <= MaxClients && g_bIsGuard[iClient];
}

int Guard_Extra(int iTeam) {
	if (iTeam < CS_TEAM_T || iTeam > CS_TEAM_CT) return 0;
	return g_iGuardN[iTeam];
}

void Guard_Reset() {
	for (int t=0; t<4; t++) g_iGuardN[t] = 0;
	for (int i=1; i<=MaxClients; i++) g_bIsGuard[i] = false;
}

void Guard_ClearClient(int iClient) {
	if (!Guard_Is(iClient)) return;
	int iUser = GetClientUserId(iClient);
	g_bIsGuard[iClient] = false;
	for (int t=CS_TEAM_T; t<=CS_TEAM_CT; t++) {
		for (int s=0; s<g_iGuardN[t]; s++) if (g_iGuardUser[t][s] == iUser) g_iGuardUser[t][s] = 0;
	}
}

bool Guard_Hold(int iClient) {
	if (!Guard_Is(iClient)) return false;
	if (g_fOrderedUntil[iClient] > GetGameTime()) return true;
	int t = GetClientTeam(iClient);
	int s = g_iGuardSlot[iClient];
	if (t < CS_TEAM_T || t > CS_TEAM_CT || s < 0 || s >= g_iGuardN[t] || g_hSDKBotMoveTo == null) return true;
	float vecPos[3], vecGoal[3];
	GetClientAbsOrigin(iClient, vecPos);
	if (Match_EnemyAt(t, g_vecGuardPost[t][s], 800.0, vecGoal)) SDKCall(g_hSDKBotMoveTo, iClient, vecGoal, Route_Fastest);
	else if (GetVectorDistance(vecPos, g_vecGuardPost[t][s]) > 240.0) SDKCall(g_hSDKBotMoveTo, iClient, g_vecGuardPost[t][s], Route_Fastest);
	return true;
}

bool Guard_Buy(int iClient, const float vecPos[3], float fYaw) {
	int t = GetClientTeam(iClient);
	if (g_iGuardN[t] >= MAX_GUARDS) { PrintHintText(iClient, "Too many guards"); return false; }
	if (MaxClients - GetClientCount(false) <= 0) {
		PrintHintText(iClient, "No free player slot.\nRestart the game once.\nCS:S can hold 64 players.");
		return false;
	}
	int s = g_iGuardN[t];
	g_vecGuardPost[t][s] = vecPos;
	g_fGuardYaw[t][s] = fYaw;
	g_iGuardUser[t][s] = 0;
	g_iGuardN[t]++;
	g_iIntel[t] -= Build_Cost(view_as<int>(Build_Guard));
	ServerCommand(t == CS_TEAM_T ? "bot_add_t" : "bot_add_ct");
	PrintHintText(iClient, "Guard called in.\nThey hold this spot and fight anyone who comes close.");
	return true;
}

void Guard_Arm(int iClient) {
	int t = GetClientTeam(iClient);
	Client_RemoveAllWeapons(iClient);
	GivePlayerItem(iClient, "weapon_knife");
	GivePlayerItem(iClient, t == CS_TEAM_CT ? "weapon_m4a1" : "weapon_ak47");
	GivePlayerItem(iClient, t == CS_TEAM_CT ? "weapon_usp" : "weapon_glock");
	SetEntProp(iClient, Prop_Send, "m_ArmorValue", 100);
	if (HasEntProp(iClient, Prop_Send, "m_bHasHelmet")) SetEntProp(iClient, Prop_Send, "m_bHasHelmet", 1);
}

public void Event_GuardSpawn(Event hEvent, const char[] sName, bool bDontBroadcast) {
	int iClient = GetClientOfUserId(hEvent.GetInt("userid"));
	if (iClient && IsFakeClient(iClient)) CreateTimer(0.6, Timer_GuardAssign, GetClientUserId(iClient), TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_GuardAssign(Handle hTimer, int iUserId) {
	int iClient = GetClientOfUserId(iUserId);
	if (!iClient || !IsClientInGame(iClient) || !IsFakeClient(iClient) || !IsPlayerAlive(iClient)) return Plugin_Stop;
	int t = GetClientTeam(iClient);
	if (t < CS_TEAM_T || t > CS_TEAM_CT || GetTeamCommander(t) == iClient) return Plugin_Stop;
	if (Guard_Is(iClient)) {
		int s = g_iGuardSlot[iClient];
		if (s >= 0 && s < g_iGuardN[t]) {
			float vecAng[3], vecPos[3];
			vecPos = g_vecGuardPost[t][s];
			vecPos[2] += 4.0;
			vecAng[1] = g_fGuardYaw[t][s];
			TeleportEntity(iClient, vecPos, vecAng, view_as<float>({0.0, 0.0, 0.0}));
		}
		return Plugin_Stop;
	}
	for (int s=0; s<g_iGuardN[t]; s++) {
		int iOwner = GetClientOfUserId(g_iGuardUser[t][s]);
		if (iOwner && IsClientInGame(iOwner)) continue;
		g_iGuardUser[t][s] = GetClientUserId(iClient);
		g_bIsGuard[iClient] = true;
		g_iGuardSlot[iClient] = s;
		char sName[24];
		FormatEx(sName, sizeof(sName), "Guard %d", s + 1);
		SetClientName(iClient, sName);
		float vecAng[3], vecPos[3];
		vecPos = g_vecGuardPost[t][s];
		vecPos[2] += 4.0;
		vecAng[1] = g_fGuardYaw[t][s];
		TeleportEntity(iClient, vecPos, vecAng, view_as<float>({0.0, 0.0, 0.0}));
		Guard_Arm(iClient);
		break;
	}
	return Plugin_Stop;
}

void Build_MapStart() {
	Guard_Reset();
	for (int i=0; i<MAX_BUILDS; i++) g_iBuildEnt[i] = -1;
	PrecacheModel("models/props/de_prodigy/concretebags.mdl", true);
	PrecacheModel("models/props/cs_militia/fencewoodlog03_long.mdl", true);
	PrecacheModel("models/props/de_nuke/crate_extralarge.mdl", true);
	PrecacheModel("models/combine_turrets/floor_turret.mdl", true);
	PrecacheModel("models/weapons/w_smg_mp5.mdl", true);
	PrecacheSound("weapons/mp5navy/mp5-1.wav", true);
	PrecacheModel("models/weapons/w_mach_m249para.mdl", true);
	PrecacheModel("models/props/de_prodigy/turret.mdl", true);
	PrecacheModel("models/weapons/w_eq_fraggrenade.mdl", true);
	CreateTimer(0.15, Timer_TurretAim, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	PrecacheModel("models/player/ct_urban.mdl", true);
	PrecacheModel("models/player/t_phoenix.mdl", true);
	CreateTimer(0.5, Timer_Builds, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

bool Build_Active(int iClient) {
	return g_iBuildKind[iClient] != view_as<int>(Build_None);
}

void Build_Stop(int iClient) {
	if (g_iBuildGhost[iClient] > 0 && IsValidEntity(g_iBuildGhost[iClient])) RemoveEntity(g_iBuildGhost[iClient]);
	g_iBuildGhost[iClient] = -1;
	g_iBuildKind[iClient] = view_as<int>(Build_None);
}

int Build_Cost(int k) {
	if (k == view_as<int>(Build_Sandbag)) return 35;
	if (k == view_as<int>(Build_Wall)) return 80;
	if (k == view_as<int>(Build_Turret)) return 420;
	if (k == view_as<int>(Build_Mine)) return 45;
	if (k == view_as<int>(Build_Fence)) return 60;
	if (k == view_as<int>(Build_Guard)) return 180;
	return 0;
}

void Build_Name(int k, char[] s, int n) {
	if (k == view_as<int>(Build_Sandbag)) strcopy(s, n, "Sandbags");
	else if (k == view_as<int>(Build_Wall)) strcopy(s, n, "Wall");
	else if (k == view_as<int>(Build_Turret)) strcopy(s, n, "Turret");
	else if (k == view_as<int>(Build_Mine)) strcopy(s, n, "Mine");
	else if (k == view_as<int>(Build_Fence)) strcopy(s, n, "Fence");
	else if (k == view_as<int>(Build_Guard)) strcopy(s, n, "Guard");
	else strcopy(s, n, "Build");
}

void Build_Model(int k, int t, char[] s, int n) {
	if (k == view_as<int>(Build_Wall)) strcopy(s, n, "models/props/de_nuke/crate_extralarge.mdl");
	else if (k == view_as<int>(Build_Fence)) strcopy(s, n, "models/props/cs_militia/fencewoodlog03_long.mdl");
	else if (k == view_as<int>(Build_Turret)) strcopy(s, n, "models/combine_turrets/floor_turret.mdl");
	else if (k == view_as<int>(Build_Mine)) strcopy(s, n, "models/weapons/w_eq_fraggrenade.mdl");
	else if (k == view_as<int>(Build_Guard)) strcopy(s, n, t == CS_TEAM_T ? "models/player/t_phoenix.mdl" : "models/player/ct_urban.mdl");
	else strcopy(s, n, "models/props/de_prodigy/concretebags.mdl");
}

void Build_ShowMenu(int iClient) {
	if (Menu_Hold(iClient)) return;
	int t = GetClientTeam(iClient);
	Menu hMenu = new Menu(MenuHandler_Build);
	hMenu.SetTitle("BUILD    Intel %d\nLeft click places it. Right click cancels.\n ", g_iIntel[t]);
	char sItem[64];
	FormatEx(sItem, sizeof(sItem), "Sandbags     %d Intel", Build_Cost(view_as<int>(Build_Sandbag)));
	hMenu.AddItem("1", sItem, g_iIntel[t] >= Build_Cost(view_as<int>(Build_Sandbag)) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	FormatEx(sItem, sizeof(sItem), "Wall         %d Intel", Build_Cost(view_as<int>(Build_Wall)));
	hMenu.AddItem("2", sItem, g_iIntel[t] >= Build_Cost(view_as<int>(Build_Wall)) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	FormatEx(sItem, sizeof(sItem), "Turret       %d Intel", Build_Cost(view_as<int>(Build_Turret)));
	hMenu.AddItem("3", sItem, g_iIntel[t] >= Build_Cost(view_as<int>(Build_Turret)) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	FormatEx(sItem, sizeof(sItem), "Mine         %d Intel    visible", Build_Cost(view_as<int>(Build_Mine)));
	hMenu.AddItem("4", sItem, g_iIntel[t] >= Build_Cost(view_as<int>(Build_Mine)) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	FormatEx(sItem, sizeof(sItem), "Fence        %d Intel", Build_Cost(view_as<int>(Build_Fence)));
	hMenu.AddItem("6", sItem, g_iIntel[t] >= Build_Cost(view_as<int>(Build_Fence)) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	hMenu.ExitBackButton = true;
	hMenu.Display(iClient, MENU_TIME_FOREVER);
	Menu_Mark(iClient, 5);
}

public int MenuHandler_Build(Menu hMenu, MenuAction eAction, int iClient, int iItem) {
	if (eAction == MenuAction_End) delete hMenu;
	else if (eAction == MenuAction_Cancel && !Menu_Refreshing(iClient) && iItem == MenuCancel_ExitBack && GetCommanderTeam(iClient)) ShowCommanderMenu(iClient);
	else if (eAction == MenuAction_Select) {
		if (!g_eCommander[iClient].bEnabled) return 0;
		char s[8]; hMenu.GetItem(iItem, s, sizeof(s));
		Build_Begin(iClient, StringToInt(s));
	}
	return 0;
}

void Build_Begin(int iClient, int k) {
	Build_Stop(iClient);
	char sModel[80];
	Build_Model(k, GetClientTeam(iClient), sModel, sizeof(sModel));
	int e = CreateEntityByName("prop_dynamic_override");
	if (e == -1) return;
	DispatchKeyValue(e, "model", sModel);
	DispatchKeyValue(e, "solid", "0");
	DispatchSpawn(e);
	SetEntityRenderMode(e, RENDER_TRANSCOLOR);
	SetEntityRenderColor(e, 80, 220, 120, 140);
	g_iBuildGhost[iClient] = e;
	g_iBuildKind[iClient] = k;
	g_fBuildYaw[iClient] = g_fCamYaw[iClient];
	g_bBuildHold[iClient] = false;
	char sName[24];
	Build_Name(k, sName, sizeof(sName));
	PrintHintText(iClient, "%s   %d Intel\nHold left click and move the mouse to rotate. Release to place. Right click cancels.", sName, Build_Cost(k));
}

void Build_Update(int iClient, const float vecCursor[3], int iButtons, int iLastButtons) {
	int e = g_iBuildGhost[iClient];
	if (e <= 0 || !IsValidEntity(e)) { Build_Stop(iClient); return; }
	float vecFloor[3], vecAng[3];
	vecFloor = vecCursor;
	SnapToFloor(vecCursor, vecFloor);
	bool bHeld = (iButtons & IN_ATTACK) != 0;
	bool bRight = (iButtons & IN_ATTACK2) && !(iLastButtons & IN_ATTACK2);
	if (bRight) { g_bBuildHold[iClient] = false; Build_Stop(iClient); PrintHintText(iClient, "Build cancelled"); return; }
	if (bHeld && !g_bBuildHold[iClient]) g_bBuildHold[iClient] = true;
	else if (bHeld) g_fBuildYaw[iClient] += float(g_iBuildMouseX[iClient]) * 0.35;
	vecAng[0] = 0.0;
	vecAng[1] = g_fBuildYaw[iClient];
	vecAng[2] = 0.0;
	TeleportEntity(e, vecFloor, vecAng, NULL_VECTOR);
	if (bHeld) return;
	if (!g_bBuildHold[iClient]) return;
	g_bBuildHold[iClient] = false;
	int t = GetClientTeam(iClient);
	int iCost = Build_Cost(g_iBuildKind[iClient]);
	if (g_iIntel[t] < iCost) { PrintHintText(iClient, "Need %d Intel", iCost); return; }
	if (g_iBuildKind[iClient] == view_as<int>(Build_Guard)) {
		if (Guard_Buy(iClient, vecFloor, g_fBuildYaw[iClient])) Build_Stop(iClient);
		return;
	}
	int slot = -1;
	for (int i=0; i<MAX_BUILDS; i++) if (g_iBuildEnt[i] <= 0 || !IsValidEntity(g_iBuildEnt[i])) { slot = i; break; }
	if (slot == -1) { PrintHintText(iClient, "Too many buildings"); return; }
	char sModel[80];
	Build_Model(g_iBuildKind[iClient], t, sModel, sizeof(sModel));
	int b = CreateEntityByName("prop_dynamic_override");
	if (b == -1) return;
	DispatchKeyValue(b, "model", sModel);
	DispatchKeyValue(b, "solid", "6");
	if (g_iBuildKind[iClient] == view_as<int>(Build_Guard)) DispatchKeyValue(b, "DefaultAnim", "idle");
	DispatchSpawn(b);
	Build_Sit(b, vecFloor, g_fBuildYaw[iClient]);
	SDKHook(b, SDKHook_OnTakeDamage, SDKHookCB_BuildTakeDamage);
	SetEntProp(b, Prop_Data, "m_takedamage", 2);
	g_iIntel[t] -= iCost;
	g_iBuildEnt[slot] = b;
	g_iBuildGun[slot] = 0;
	g_iBuildType[slot] = g_iBuildKind[iClient];
	g_iBuildTeam[slot] = t;
	int iHp = 250;
	if (g_iBuildKind[iClient] == view_as<int>(Build_Turret)) iHp = 200;
	else if (g_iBuildKind[iClient] == view_as<int>(Build_Wall)) iHp = 150;
	else if (g_iBuildKind[iClient] == view_as<int>(Build_Fence)) iHp = 100;
	else if (g_iBuildKind[iClient] == view_as<int>(Build_Sandbag)) iHp = 250;
	g_iBuildHp[slot] = iHp;
	g_iBuildMax[slot] = iHp;
	g_fBuildArm[slot] = GetGameTime() + 2.0;
	if (g_iBuildKind[iClient] == view_as<int>(Build_Mine)) SetEntityRenderColor(b, 220, 50, 40, 255);
	if (g_iBuildKind[iClient] == view_as<int>(Build_Turret)) {
		SetVariantString("deploy");
		AcceptEntityInput(b, "SetAnimation");
		int g = CreateEntityByName("prop_dynamic_override");
		if (g != -1) {
			DispatchKeyValue(g, "model", "models/weapons/w_smg_mp5.mdl");
			DispatchKeyValue(g, "solid", "0");
			DispatchSpawn(g);
			float vecGun[3];
			GetEntPropVector(b, Prop_Data, "m_vecAbsOrigin", vecGun);
			vecGun[2] += 40.0;
			TeleportEntity(g, vecGun, NULL_VECTOR, NULL_VECTOR);
			SetVariantString("!activator");
			AcceptEntityInput(g, "SetParent", b);
			SetEntPropVector(g, Prop_Data, "m_vecOrigin", view_as<float>({10.0, 0.0, 40.0}));
			g_iBuildGun[slot] = g;
		}
	}
	SetEntProp(b, Prop_Data, "m_iHealth", slot + 1);
	Build_Stop(iClient);
	PrintHintText(iClient, "Placed");
}

void Build_Sit(int iEnt, float vecFloor[3], float fYaw) {
	float vecAng[3];
	vecAng[1] = fYaw;
	TeleportEntity(iEnt, vecFloor, vecAng, NULL_VECTOR);
	float vecMins[3];
	GetEntPropVector(iEnt, Prop_Send, "m_vecMins", vecMins);
	if (vecMins[2] < -1.0) {
		vecFloor[2] -= vecMins[2];
		TeleportEntity(iEnt, vecFloor, vecAng, NULL_VECTOR);
	}
}

public Action SDKHookCB_BuildTakeDamage(int iVictim, int &iAttacker, int &iInflictor, float &fDamage, int &iType) {
	int slot = Build_SlotOf(iVictim);
	if (slot != -1 && Build_IsEnemy(slot, iAttacker)) {
		int iDmg = 10;
		if (g_iBuildType[slot] == view_as<int>(Build_Turret)) {
			iDmg = RoundToCeil(fDamage);
			if (iDmg < 8) iDmg = 8;
		}
		Build_Hit(slot, iDmg);
	}
	return Plugin_Handled;
}

int Build_SlotOf(int iEnt) {
	for (int i = 0; i < MAX_BUILDS; i++) if (g_iBuildEnt[i] == iEnt) return i;
	return -1;
}

bool Build_IsEnemy(int slot, int iAttacker) {
	if (iAttacker < 1 || iAttacker > MaxClients || !IsClientInGame(iAttacker)) return false;
	int ta = GetClientTeam(iAttacker);
	return ta >= CS_TEAM_T && ta <= CS_TEAM_CT && ta != g_iBuildTeam[slot];
}

void Build_Hit(int slot, int iAmount) {
	if (slot < 0 || g_iBuildEnt[slot] <= 0) return;
	float fNow = GetGameTime();
	if (fNow - g_fBuildHit[slot] < 0.04) return;
	g_fBuildHit[slot] = fNow;
	Build_Hurt(slot, iAmount);
}

public Action Timer_Builds(Handle hTimer) {
	for (int i=0; i<MAX_BUILDS; i++) {
		int e = g_iBuildEnt[i];
		if (e <= 0 || !IsValidEntity(e)) { g_iBuildEnt[i] = -1; continue; }
		if (GetGameTime() < g_fBuildArm[i]) continue;
		if (g_iBuildType[i] == view_as<int>(Build_Mine)) Build_MineThink(i);
		else if (g_iBuildType[i] == view_as<int>(Build_Turret)) Build_HpBar(i);
		else if (g_iBuildType[i] == view_as<int>(Build_Guard)) Build_TurretThink(i, 480.0, 14.0);
	}
	Build_EnemyShootTurrets();
	return Plugin_Continue;
}

void Build_HpBar(int slot) {
	int e = g_iBuildEnt[slot];
	if (e <= 0 || !IsValidEntity(e)) return;
	int iMax = g_iBuildMax[slot] > 0 ? g_iBuildMax[slot] : 200;
	float fFrac = float(g_iBuildHp[slot]) / float(iMax);
	if (fFrac < 0.0) fFrac = 0.0;
	if (fFrac > 1.0) fFrac = 1.0;
	float o[3], a[3], b[3], c[3];
	GetEntPropVector(e, Prop_Data, "m_vecAbsOrigin", o);
	o[2] += 68.0;
	a = o; b = o; c = o;
	a[0] -= 24.0; b[0] += 24.0;
	c[0] = a[0] + 48.0 * fFrac;
	int iFg[4];
	if (fFrac > 0.6) iFg = {70, 220, 80, 255};
	else if (fFrac > 0.3) iFg = {240, 200, 40, 255};
	else iFg = {230, 50, 40, 255};
	int iSprite = g_iMarkerXray > 0 ? g_iMarkerXray : g_iMarkerBeam;
	if (iSprite <= 0) iSprite = PrecacheModel("sprites/laserbeam.vmt");
	if (fFrac > 0.02) {
		TE_SetupBeamPoints(a, c, iSprite, 0, 0, 0, 0.6, 4.0, 4.0, 0, 0.0, iFg, 0);
		TE_SendToAll();
	}
}

public bool Trace_BuildSkip(int iEnt, int iMask, any iData) {
	return iEnt != iData;
}

bool Build_ClearShot(int iBot, int iEnt, const float vecAim[3]) {
	float vecEye[3];
	GetClientEyePosition(iBot, vecEye);
	Handle h = TR_TraceRayFilterEx(vecEye, vecAim, MASK_SHOT, RayType_EndPoint, Trace_BuildSkip, iBot);
	bool bSee = !TR_DidHit(h) || TR_GetEntityIndex(h) == iEnt;
	if (!bSee) {
		float vecEnd[3];
		TR_GetEndPosition(vecEnd, h);
		bSee = GetVectorDistance(vecEnd, vecAim) < 56.0;
	}
	delete h;
	return bSee;
}

public Action Timer_TurretAim(Handle hTimer) {
	Build_EnemyShootTurrets();
	HQ_BotsShoot();
	for (int i = 0; i < MAX_BUILDS; i++) if (g_iBuildType[i] == view_as<int>(Build_Turret) && g_iBuildEnt[i] > 0 && IsValidEntity(g_iBuildEnt[i]) && GetGameTime() >= g_fBuildArm[i]) Build_TurretThink(i, 900.0, 3.0);
	return Plugin_Continue;
}

bool g_bBotHqHeld[MAXPLAYERS+1];
float g_fBotHqAim[MAXPLAYERS+1];

// A real shot at the enemy HQ: line of sight to a part, aim at the surface the bullet hits.
bool HQ_BotAimPoint(int c, int eTeam, float vecAim[3]) {
	float vecCore[3], vecEye[3];
	HQ_CorePoint(eTeam, vecCore);
	GetClientEyePosition(c, vecEye);
	Handle hTr = TR_TraceRayFilterEx(vecEye, vecCore, MASK_SHOT, RayType_EndPoint, Trace_BuildSkip, c);
	int iEnt = TR_GetEntityIndex(hTr);
	float vecEnd[3];
	TR_GetEndPosition(vecEnd, hTr);
	bool bHit = TR_DidHit(hTr);
	delete hTr;
	if (iEnt > MaxClients && iEnt < 2049 && g_iHQOwner[iEnt] == eTeam) {
		vecAim = vecEnd;
		return true;
	}
	if (!bHit || GetVectorDistance(vecEnd, vecCore) < 72.0) {
		vecAim = vecCore;
		return true;
	}
	return false;
}

void HQ_BotsShoot() {
	bool bWant[MAXPLAYERS+1];
	float fNow = GetGameTime();
	for (int c = 1; c <= MaxClients; c++) {
		if (!IsClientInGame(c) || !IsPlayerAlive(c) || !IsFakeClient(c) || g_bBodyHidden[c] || g_bBotTurretHeld[c]) continue;
		int t = GetClientTeam(c);
		if (t < CS_TEAM_T || t > CS_TEAM_CT || HQ_UnderFire(t)) continue;
		int eTeam = t == CS_TEAM_T ? CS_TEAM_CT : CS_TEAM_T;
		if (HQ_Destroyed(eTeam)) continue;
		float vecCore[3], p[3], vecAim[3];
		HQ_CorePoint(eTeam, vecCore);
		GetClientAbsOrigin(c, p);
		float dHq = GetVectorDistance(p, vecCore);
		if (dHq > 900.0 || dHq < 48.0) continue;
		bool bDuel;
		for (int h = 1; h <= MaxClients; h++) {
			if (h == c || !IsClientInGame(h) || !IsPlayerAlive(h) || GetClientTeam(h) == t || g_bBodyHidden[h]) continue;
			float hp[3];
			GetClientAbsOrigin(h, hp);
			if (GetVectorDistance(p, hp) < 220.0 && GetVectorDistance(p, hp) < dHq) { bDuel = true; break; }
		}
		if (bDuel || !HQ_BotAimPoint(c, eTeam, vecAim)) continue;
		// One short burst, then a pause. Re-sending +attack every tick is what made them twitch.
		float fAge = fNow - g_fBotHqAim[c];
		if (g_fBotHqAim[c] > 0.0 && fAge < 0.40) { bWant[c] = true; continue; }
		if (g_fBotHqAim[c] > 0.0 && fAge < 0.85) continue;
		float vecEye[3], vecCur[3], vecDir[3], vecAng[3];
		GetClientEyePosition(c, vecEye);
		GetClientEyeAngles(c, vecCur);
		MakeVectorFromPoints(vecEye, vecAim, vecDir);
		GetVectorAngles(vecDir, vecAng);
		vecAng[2] = 0.0;
		float fYaw = vecAng[1] - vecCur[1];
		while (fYaw > 180.0) fYaw -= 360.0;
		while (fYaw < -180.0) fYaw += 360.0;
		SetEntPropVector(c, Prop_Send, "m_angEyeAngles", vecAng);
		if (FloatAbs(fYaw) > 18.0 || FloatAbs(vecAng[0] - vecCur[0]) > 10.0) TeleportEntity(c, NULL_VECTOR, vecAng, NULL_VECTOR);
		FakeClientCommand(c, "+attack");
		g_fBotHqAim[c] = fNow;
		g_bBotHqHeld[c] = true;
		bWant[c] = true;
	}
	for (int c = 1; c <= MaxClients; c++) {
		if (!g_bBotHqHeld[c] || bWant[c] || g_bBotTurretHeld[c]) continue;
		if (IsClientInGame(c)) FakeClientCommand(c, "-attack");
		g_bBotHqHeld[c] = false;
	}
}

void Build_EnemyShootTurrets() {
	bool bWant[MAXPLAYERS+1];
	float fNow = GetGameTime();
	for (int slot = 0; slot < MAX_BUILDS; slot++) {
		if (g_iBuildType[slot] != view_as<int>(Build_Turret)) continue;
		int e = g_iBuildEnt[slot];
		if (e <= 0 || !IsValidEntity(e) || g_iBuildHp[slot] <= 0) continue;
		float o[3], vecAim[3];
		GetEntPropVector(e, Prop_Data, "m_vecAbsOrigin", o);
		vecAim = o; vecAim[2] += 40.0;
		int iEnemy = g_iBuildTeam[slot] == CS_TEAM_T ? CS_TEAM_CT : CS_TEAM_T;
		for (int c = 1; c <= MaxClients; c++) {
			if (!IsClientInGame(c) || !IsPlayerAlive(c) || !IsFakeClient(c) || GetClientTeam(c) != iEnemy || g_bBodyHidden[c]) continue;
			float p[3];
			GetClientAbsOrigin(c, p);
			float dTur = GetVectorDistance(p, o);
			if (dTur > 1100.0) continue;
			bool bDuel;
			for (int h = 1; h <= MaxClients; h++) {
				if (h == c || !IsClientInGame(h) || !IsPlayerAlive(h) || GetClientTeam(h) == iEnemy || g_bBodyHidden[h]) continue;
				float hp[3];
				GetClientAbsOrigin(h, hp);
				if (GetVectorDistance(p, hp) < 160.0 && GetVectorDistance(p, hp) < dTur) { bDuel = true; break; }
			}
			if (bDuel) continue;
			float fAge = fNow - g_fBotTurretAim[c];
			if (g_fBotTurretAim[c] > 0.0 && fAge < 0.4) { bWant[c] = true; continue; }
			if (g_fBotTurretAim[c] > 0.0 && fAge < 0.9) continue;
			if (dTur > 380.0 && g_hSDKBotMoveTo != null && fNow - g_fBotMoved[c] > 1.5) {
				SDKCall(g_hSDKBotMoveTo, c, o, Route_Fastest);
				g_fBotMoved[c] = fNow;
			}
			float vecEye[3], vecCur[3], vecDir[3], vecAng[3];
			GetClientEyePosition(c, vecEye);
			GetClientEyeAngles(c, vecCur);
			MakeVectorFromPoints(vecEye, vecAim, vecDir);
			GetVectorAngles(vecDir, vecAng);
			float fYaw = vecAng[1] - vecCur[1];
			while (fYaw > 180.0) fYaw -= 360.0;
			while (fYaw < -180.0) fYaw += 360.0;
			if (FloatAbs(fYaw) > 12.0) TeleportEntity(c, NULL_VECTOR, vecAng, NULL_VECTOR);
			FakeClientCommand(c, "+attack");
			g_fBotTurretAim[c] = fNow;
			g_bBotTurretHeld[c] = true;
			bWant[c] = true;
		}
	}
	for (int c = 1; c <= MaxClients; c++) {
		if (!g_bBotTurretHeld[c] || bWant[c]) continue;
		if (IsClientInGame(c)) FakeClientCommand(c, "-attack");
		g_bBotTurretHeld[c] = false;
	}
}

void Build_Hurt(int slot, int iAmount) {
	g_iBuildHp[slot] -= iAmount;
	if (g_iBuildHp[slot] > 0) return;
	int e = g_iBuildEnt[slot];
	if (e > 0 && IsValidEntity(e)) RemoveEntity(e);
	int g = g_iBuildGun[slot];
	if (g > 0 && IsValidEntity(g)) RemoveEntity(g);
	g_iBuildEnt[slot] = -1;
	g_iBuildGun[slot] = 0;
}

public void Event_BuildFire(Event hEvent, const char[] sName, bool bDontBroadcast) {
	int c = GetClientOfUserId(hEvent.GetInt("userid"));
	if (c < 1 || c > MaxClients || !IsClientInGame(c) || !IsPlayerAlive(c)) return;
	int ta = GetClientTeam(c);
	float vecEye[3], vecAng[3];
	GetClientEyePosition(c, vecEye);
	GetClientEyeAngles(c, vecAng);
	Handle hTr = TR_TraceRayFilterEx(vecEye, vecAng, MASK_SHOT, RayType_Infinite, Trace_BuildSkip, c);
	int iHit = TR_GetEntityIndex(hTr);
	float vecEnd[3];
	TR_GetEndPosition(vecEnd, hTr);
	delete hTr;
	for (int i = 0; i < MAX_BUILDS; i++) {
		int e = g_iBuildEnt[i];
		if (e <= 0 || !IsValidEntity(e) || g_iBuildTeam[i] == ta) continue;
		if (g_iBuildType[i] != view_as<int>(Build_Turret)) continue;
		if (iHit == e) { Build_Hit(i, 16); return; }
		float o[3];
		GetEntPropVector(e, Prop_Data, "m_vecAbsOrigin", o);
		if (GetVectorDistance(vecEnd, o) < 120.0) { Build_Hit(i, 16); return; }
	}
}

public void Event_BuildBullet(Event hEvent, const char[] sName, bool bDontBroadcast) {
	int c = GetClientOfUserId(hEvent.GetInt("userid"));
	if (c < 1 || c > MaxClients || !IsClientInGame(c)) return;
	float v[3];
	v[0] = hEvent.GetFloat("x"); v[1] = hEvent.GetFloat("y"); v[2] = hEvent.GetFloat("z");
	int ta = GetClientTeam(c);
	for (int i = 0; i < MAX_BUILDS; i++) {
		int e = g_iBuildEnt[i];
		if (e <= 0 || !IsValidEntity(e) || g_iBuildTeam[i] == ta) continue;
		float o[3];
		GetEntPropVector(e, Prop_Data, "m_vecAbsOrigin", o);
		float fReach = 110.0;
		if (g_iBuildType[i] == view_as<int>(Build_Fence)) fReach = 260.0;
		else if (g_iBuildType[i] == view_as<int>(Build_Wall)) fReach = 160.0;
		else if (g_iBuildType[i] == view_as<int>(Build_Turret)) fReach = 120.0;
		if (GetVectorDistance(v, o) < fReach) {
			Build_Hit(i, g_iBuildType[i] == view_as<int>(Build_Turret) ? 16 : 10);
			return;
		}
	}
}

bool Build_ClearLine(int iSkip, int iTarget, const float vecFrom[3], const float vecTo[3]) {
	Handle hTr = TR_TraceRayFilterEx(vecFrom, vecTo, MASK_SHOT, RayType_EndPoint, Trace_BuildSkip, iSkip);
	int iHit = TR_GetEntityIndex(hTr);
	float vecEnd[3];
	TR_GetEndPosition(vecEnd, hTr);
	delete hTr;
	if (iHit == iTarget) return true;
	return GetVectorDistance(vecEnd, vecTo) < 48.0;
}

void Build_TurretThink(int slot, float fRange, float fDamage) {
	int e = g_iBuildEnt[slot];
	float v[3], vecFrom[3], vecHit[3];
	GetEntPropVector(e, Prop_Data, "m_vecAbsOrigin", v);
	vecFrom = v; vecFrom[2] += 42.0;
	int iEnemy = g_iBuildTeam[slot] == CS_TEAM_T ? CS_TEAM_CT : CS_TEAM_T;
	float fBest = fRange;
	int iVictim, iProp;
	for (int i=1; i<=MaxClients; i++) {
		if (!IsClientInGame(i) || !IsPlayerAlive(i) || GetClientTeam(i) != iEnemy || g_bBodyHidden[i]) continue;
		float p[3], vecAim[3];
		GetClientAbsOrigin(i, p);
		float d = GetVectorDistance(v, p);
		if (d >= fBest) continue;
		vecAim = p; vecAim[2] += 40.0;
		if (!Build_ClearLine(e, i, vecFrom, vecAim)) continue;
		fBest = d; iVictim = i; iProp = 0; vecHit = vecAim;
	}
	for (int n = 0; n < MAX_NPCS; n++) {
		if (!g_eNpc[n].bUsed || g_eNpc[n].iTeam != iEnemy || g_eNpc[n].eState == NS_Dead) continue;
		int pe = Npc_GetEntity(n);
		if (pe == -1) continue;
		float p[3], vecAim[3];
		GetEntPropVector(pe, Prop_Data, "m_vecAbsOrigin", p);
		float d = GetVectorDistance(v, p);
		if (d >= fBest) continue;
		vecAim = p; vecAim[2] += 36.0;
		if (!Build_ClearLine(e, pe, vecFrom, vecAim)) continue;
		fBest = d; iVictim = 0; iProp = pe; vecHit = vecAim;
	}
	if (!iVictim && !iProp) {
		SetVariantString("idle");
		AcceptEntityInput(e, "SetAnimation");
		return;
	}
	float dx = vecHit[0] - v[0], dy = vecHit[1] - v[1];
	float vecAng[3];
	vecAng[1] = RadToDeg(ArcTangent2(dy, dx));
	float fOffYaw = GetRandomFloat(-8.0, 8.0);
	float fOffPitch = GetRandomFloat(-4.0, 4.0);
	vecAng[0] = fOffPitch;
	vecAng[1] += fOffYaw;
	TeleportEntity(e, NULL_VECTOR, vecAng, NULL_VECTOR);
	if (FloatAbs(fOffYaw) < 5.5) {
		int iDmg = GetRandomInt(3, 5);
		if (iVictim) {
			int iHp = GetClientHealth(iVictim) - iDmg;
			if (iHp > 0) SetEntityHealth(iVictim, iHp);
			else ForcePlayerSuicide(iVictim);
		} else if (iProp > 0) {
			int n = Npc_FromEntity(iProp);
			if (n != -1) {
				g_eNpc[n].iHealth -= iDmg;
				if (g_eNpc[n].iHealth <= 0) AcceptEntityInput(iProp, "Kill");
			}
		}
	}
	SetVariantString("fire");
	AcceptEntityInput(e, "SetAnimation");
	EmitSoundToAll("weapons/mp5navy/mp5-1.wav", e, SNDCHAN_WEAPON, 75, SND_NOFLAGS, 0.7);
}

public void Event_BuildGrenade(Event hEvent, const char[] sName, bool bDontBroadcast) {
	float v[3];
	v[0] = hEvent.GetFloat("x"); v[1] = hEvent.GetFloat("y"); v[2] = hEvent.GetFloat("z");
	for (int i = 0; i < MAX_BUILDS; i++) {
		int e = g_iBuildEnt[i];
		if (e <= 0 || !IsValidEntity(e) || g_iBuildType[i] != view_as<int>(Build_Wall)) continue;
		float o[3];
		GetEntPropVector(e, Prop_Data, "m_vecAbsOrigin", o);
		if (GetVectorDistance(v, o) < 240.0) Build_Hurt(i, 9999);
	}
}

void Build_MineThink(int slot) {
	int e = g_iBuildEnt[slot];
	float v[3]; GetEntPropVector(e, Prop_Data, "m_vecAbsOrigin", v);
	int iEnemy = g_iBuildTeam[slot] == CS_TEAM_T ? CS_TEAM_CT : CS_TEAM_T;
	bool bTrip;
	for (int i=1; i<=MaxClients; i++) {
		if (!IsClientInGame(i) || !IsPlayerAlive(i) || GetClientTeam(i) != iEnemy || g_bBodyHidden[i]) continue;
		float p[3]; GetClientAbsOrigin(i, p);
		if (GetVectorDistance(v, p) < 80.0) { bTrip = true; break; }
	}
	if (!bTrip) return;
	for (int i=1; i<=MaxClients; i++) {
		if (!IsClientInGame(i) || !IsPlayerAlive(i) || g_bBodyHidden[i]) continue;
		float p[3]; GetClientAbsOrigin(i, p);
		if (GetVectorDistance(v, p) < 180.0) SDKHooks_TakeDamage(i, e, e, GetClientTeam(i) == iEnemy ? 90.0 : 30.0, DMG_BLAST);
	}
	int boom = CreateEntityByName("env_explosion");
	if (boom != -1) {
		DispatchKeyValue(boom, "iMagnitude", "80");
		DispatchKeyValue(boom, "iRadiusOverride", "180");
		DispatchSpawn(boom);
		TeleportEntity(boom, v, NULL_VECTOR, NULL_VECTOR);
		AcceptEntityInput(boom, "Explode");
		AcceptEntityInput(boom, "Kill");
	}
	RemoveEntity(e);
	g_iBuildEnt[slot] = -1;
}
