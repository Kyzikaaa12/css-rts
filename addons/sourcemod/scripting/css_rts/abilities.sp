// css_rts/abilities.sp -- v0.6 Commander abilities (Intel cost + cooldown), F2 menu:
//   Radar sweep: enemies revealed to the whole team for a few seconds (through-wall markers + radar).
//   Smoke drop:  a smoke screen at the cursor point.
//   Supply drop: a crate's worth of grenades on the floor at the cursor point.
// Targeted abilities enter a cursor mode in the Commander view (LMB = drop, RMB = cancel).

enum AbilityId {
	Ability_Sweep = 0,
	Ability_Smoke,
	Ability_Supply,
	Ability_Count
}

char g_sAbilityName[][] = {"Radar sweep", "Smoke drop", "Supply drop"};
char g_sAbilityKey[][] = {"sweep", "smoke", "supply"};
int g_iAbilityBaseCost[] = {240, 150, 200};
float g_fAbilityCooldown[] = {60.0, 30.0, 45.0};

ConVar g_hCvarAbilityScale;
ConVar g_hCvarSweepTime;
ConVar g_hCvarAbilities;
float g_fAbilityReadyAt[4][3];
float g_fSweepUntil[4];
int g_iAbilityUses[4][3];
int g_iAbilityTarget[MAXPLAYERS+1] = {-1, ...};

void Abilities_Init() {
	g_hCvarAbilities = CreateConVar("css_rts_abilities", "0", "1 = Commander abilities (radar sweep, smoke drop, supply drop) in the F2 menu", _, true, 0.0, true, 1.0);
	g_hCvarAbilityScale = CreateConVar("css_rts_ability_cost_scale", "1.0", "Multiplier for Commander ability Intel costs", FCVAR_NOTIFY, true, 0.0);
	g_hCvarSweepTime = CreateConVar("css_rts_sweep_time", "6.0", "Seconds a radar sweep reveals the enemy", FCVAR_NOTIFY, true, 1.0, true, 30.0);
}

void Abilities_MapStart() {
	Abilities_Reset();
	CreateTimer(0.2, Timer_Sweep, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

void Abilities_Reset() {
	for (int t=0; t<4; t++) {
		g_fSweepUntil[t] = 0.0;
		for (int a=0; a<3; a++) { g_fAbilityReadyAt[t][a] = 0.0; g_iAbilityUses[t][a] = 0; }
	}
	for (int i=1; i<=MaxClients; i++) g_iAbilityTarget[i] = -1;
}

int Ability_Cost(AbilityId a) {
	return RoundToCeil(g_iAbilityBaseCost[a] * g_hCvarAbilityScale.FloatValue);
}

float Ability_CooldownLeft(int t, AbilityId a) {
	float f = g_fAbilityReadyAt[t][a] - GetGameTime();
	return f > 0.0 ? f : 0.0;
}

bool Ability_Ready(int t, AbilityId a) {
	return Ability_CooldownLeft(t, a) <= 0.0 && g_iIntel[t] >= Ability_Cost(a);
}

void Ability_MenuLabel(int t, AbilityId a, char[] sBuf, int iLen) {
	float fCd = Ability_CooldownLeft(t, a);
	if (fCd > 0.0) FormatEx(sBuf, iLen, "%s  -  %d  (ready in %ds)", g_sAbilityName[a], Ability_Cost(a), RoundToCeil(fCd));
	else FormatEx(sBuf, iLen, "%s  -  %d  (%ds cd)", g_sAbilityName[a], Ability_Cost(a), RoundToFloor(g_fAbilityCooldown[a]));
}

int Ability_FromName(const char[] s) {
	for (int a=0; a<3; a++) if (StrEqual(s, g_sAbilityKey[a], false)) return a;
	return -1;
}

// Menu entry point
void Ability_Begin(int iClient, AbilityId a) {
	int t = GetCommanderTeam(iClient);
	if (!t) return;
	if (!Ability_Check(iClient, t, a)) return;
	if (a == Ability_Sweep) { Ability_Fire(iClient, t, a, NULL_VECTOR); return; }
	if (g_eCommander[iClient].bEnabled) {
		Ghost_Stop(iClient);
		g_iAbilityTarget[iClient] = view_as<int>(a);
		PrintHintText(iClient, "%s: move the cursor to the target point\nLeft click = drop, right click = cancel", g_sAbilityName[a]);
		return;
	}
	// Not in the overhead view: target where the Commander is looking
	float vecEye[3], vecAng[3], vecEnd[3];
	GetClientEyePosition(iClient, vecEye);
	GetClientEyeAngles(iClient, vecAng);
	TR_TraceRayFilter(vecEye, vecAng, MASK_SOLID, RayType_Infinite, TraceFilter_NoPlayers);
	TR_GetEndPosition(vecEnd);
	Ability_Fire(iClient, t, a, vecEnd);
}

public bool TraceFilter_NoPlayers(int iEnt, int iMask) {
	return iEnt > MaxClients;
}

bool Ability_Check(int iClient, int t, AbilityId a) {
	float fCd = Ability_CooldownLeft(t, a);
	if (fCd > 0.0) {
		if (iClient) PrintToChat(iClient, "\x04[RTS]\x01 %s is recharging (%ds).", g_sAbilityName[a], RoundToCeil(fCd));
		return false;
	}
	if (g_iIntel[t] < Ability_Cost(a)) {
		if (iClient) PrintToChat(iClient, "\x04[RTS]\x01 %s needs %d Intel (have %d).", g_sAbilityName[a], Ability_Cost(a), g_iIntel[t]);
		return false;
	}
	return true;
}

// Spends Intel, starts the cooldown and runs the effect. iClient 0 = debug/selftest.
bool Ability_Fire(int iClient, int t, AbilityId a, const float vecPos[3]) {
	if (!Ability_Check(iClient, t, a)) return false;
	g_iIntel[t] -= Ability_Cost(a);
	g_fAbilityReadyAt[t][a] = GetGameTime() + g_fAbilityCooldown[a];
	g_iAbilityUses[t][a]++;
	switch (a) {
		case Ability_Sweep: {
			g_fSweepUntil[t] = GetGameTime() + g_hCvarSweepTime.FloatValue;
			TeamChat(t, "\x04[RTS] RADAR SWEEP:\x01 enemy positions revealed for %d seconds (red markers).", RoundToFloor(g_hCvarSweepTime.FloatValue));
			for (int i=1; i<=MaxClients; i++) {
				if (IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) == t) PrintHintText(i, "RADAR SWEEP\nEnemies marked through walls");
			}
		}
		case Ability_Smoke: {
			Ability_SpawnSmoke(iClient, vecPos);
			TeamChat(t, "\x04[RTS]\x01 Commander dropped a \x03smoke screen\x01.");
		}
		case Ability_Supply: {
			Ability_SpawnSupply(vecPos);
			TeamChat(t, "\x04[RTS]\x01 Commander dropped \x03supplies\x01 (2 HE, 2 flash, 1 smoke) - pick them up!");
		}
	}
	return true;
}

int g_iSmokesSpawned;

void Ability_SpawnSmoke(int iClient, const float vecPos[3]) {
	float vecAt[3];
	vecAt = vecPos; vecAt[2] += 16.0;
	int iEnt = CreateEntityByName("env_particlesmokegrenade");
	if (iEnt == -1) return;
	DispatchKeyValue(iEnt, "targetname", "css_rts_smoke");
	TeleportEntity(iEnt, vecAt, NULL_VECTOR, NULL_VECTOR);
	DispatchSpawn(iEnt);
	SetEntPropFloat(iEnt, Prop_Send, "m_flSpawnTime", GetGameTime());
	SetEntPropFloat(iEnt, Prop_Send, "m_FadeStartTime", 15.0);
	SetEntPropFloat(iEnt, Prop_Send, "m_FadeEndTime", 20.0);
	SetEntProp(iEnt, Prop_Send, "m_CurrentStage", 1);
	CreateTimer(22.0, Timer_RemoveEnt, EntIndexToEntRef(iEnt), TIMER_FLAG_NO_MAPCHANGE);
	g_iSmokesSpawned++;
	EmitGameSoundToAll("BaseSmokeEffect.Sound", SOUND_FROM_WORLD, _, _, vecAt);
	// Let the bots know a smoke cloud exists (they avoid shooting/looking through it)
	Event hEv = CreateEvent("smokegrenade_detonate", true);
	if (hEv != null) {
		hEv.SetInt("userid", iClient ? GetClientUserId(iClient) : 0);
		hEv.SetFloat("x", vecAt[0]); hEv.SetFloat("y", vecAt[1]); hEv.SetFloat("z", vecAt[2]);
		hEv.Fire();
	}
}

public Action Timer_RemoveEnt(Handle hTimer, int iRef) {
	int iEnt = EntRefToEntIndex(iRef);
	if (iEnt != INVALID_ENT_REFERENCE) RemoveEntity(iEnt);
	return Plugin_Stop;
}

char g_sSupplyItems[][] = {"weapon_hegrenade", "weapon_hegrenade", "weapon_flashbang", "weapon_flashbang", "weapon_smokegrenade"};

void Ability_SpawnSupply(const float vecPos[3]) {
	for (int k=0; k<sizeof(g_sSupplyItems); k++) {
		int iEnt = CreateEntityByName(g_sSupplyItems[k]);
		if (iEnt == -1) continue;
		DispatchKeyValue(iEnt, "targetname", "css_rts_supply");
		float fA = 6.2832 * k / sizeof(g_sSupplyItems);
		float vecAt[3];
		vecAt[0] = vecPos[0] + Cosine(fA) * 20.0;
		vecAt[1] = vecPos[1] + Sine(fA) * 20.0;
		vecAt[2] = vecPos[2] + 24.0;
		DispatchSpawn(iEnt);
		TeleportEntity(iEnt, vecAt, NULL_VECTOR, NULL_VECTOR);
	}
}

// Called each tick from the commander cursor code while an ability is being targeted
bool Ability_Targeting(int iClient) {
	return g_iAbilityTarget[iClient] != -1;
}

void Ability_UpdateTarget(int iClient, const float vecCursor[3], int iButtons, int iLastButtons) {
	AbilityId a = view_as<AbilityId>(g_iAbilityTarget[iClient]);
	int t = GetCommanderTeam(iClient);
	if (!t) { g_iAbilityTarget[iClient] = -1; return; }
	int iCol[4] = {255, 255, 255, 255};
	if (a == Ability_Smoke) iCol = {200, 200, 200, 255}; else iCol = {80, 255, 80, 255};
	DrawRing(iClient, vecCursor, a == Ability_Smoke ? 220.0 : 60.0, iCol, 4.0);
	Hud_Action(iClient, "%s: %d Intel (have %d)  -  LMB drop here, RMB cancel", g_sAbilityName[a], Ability_Cost(a), g_iIntel[t]);
	bool bLeft = (iButtons & IN_ATTACK) && !(iLastButtons & IN_ATTACK);
	bool bRight = (iButtons & IN_ATTACK2) && !(iLastButtons & IN_ATTACK2);
	if (bRight) { g_iAbilityTarget[iClient] = -1; PrintHintText(iClient, "%s cancelled", g_sAbilityName[a]); return; }
	if (!bLeft) return;
	g_iAbilityTarget[iClient] = -1;
	Ability_Fire(iClient, t, a, vecCursor);
}

// Radar sweep: red through-wall rings + chevrons over every living enemy, sent to the sweeping team
public Action Timer_Sweep(Handle hTimer) {
	float fNow = GetGameTime();
	for (int t=CS_TEAM_T; t<=CS_TEAM_CT; t++) {
		if (g_fSweepUntil[t] <= fNow) continue;
		int iEnemy = t == CS_TEAM_T ? CS_TEAM_CT : CS_TEAM_T;
		int iCol[4] = {255, 40, 40, 255};
		for (int e=1; e<=MaxClients; e++) {
			if (!IsClientInGame(e) || !IsPlayerAlive(e) || GetClientTeam(e) != iEnemy || g_bBodyHidden[e]) continue;
			float vecFeet[3];
			GetClientAbsOrigin(e, vecFeet);
			for (int v=1; v<=MaxClients; v++) {
				if (!IsClientInGame(v) || IsFakeClient(v) || GetClientTeam(v) != t) continue;
				DrawRing(v, vecFeet, 36.0, iCol, 5.0);
				DrawChevron(v, vecFeet, iCol, 1.3, 4.0);
			}
		}
	}
	return Plugin_Continue;
}

bool Ability_SweepActive(int t) {
	return g_fSweepUntil[t] > GetGameTime();
}
