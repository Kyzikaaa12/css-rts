// css_rts/post.sp -- command post terminals: auto placement, spawning, USE detection

int g_iTerminalRef[4] = {INVALID_ENT_REFERENCE, ...};

float TERMINAL_MINS[3] = {-14.0, -14.0, 14.0};   // v0.5.3.1: posts stand flush against walls now
float TERMINAL_MAXS[3] = {14.0, 14.0, 56.0};
float PLAYER_MINS[3] = {-16.0, -16.0, 0.0};
float PLAYER_MAXS[3] = {16.0, 16.0, 72.0};

// Ignores players and our own terminals
int g_iHQOwner[2049];   // HQ part -> team (hq.sp)
public bool TraceFilter_WorldOnlyNoPlayers(int iEntity, int iMask) {
	if (1 <= iEntity <= MaxClients) return false;
	for (int t=CS_TEAM_T; t<=CS_TEAM_CT; t++) {
		if (iEntity > 0 && iEntity == EntRefToEntIndex(g_iTerminalRef[t])) return false;
	}
	if (iEntity > MaxClients && iEntity < 2049 && g_iHQOwner[iEntity]) return false;   // our own HQ parts stand right beside the terminal
	return true;
}

// Drop a point to the floor. Returns false if it starts in solid or no floor within 256u.
bool SnapToFloor(const float vecIn[3], float vecOut[3]) {
	float vecStart[3], vecEnd[3];
	vecStart = vecIn; vecStart[2] += 40.0;
	TR_TraceHullFilter(vecStart, vecStart, view_as<float>({-1.0, -1.0, -1.0}), view_as<float>({1.0, 1.0, 1.0}), MASK_PLAYERSOLID, TraceFilter_WorldOnlyNoPlayers);
	if (TR_StartSolid() || TR_DidHit()) return false;
	vecEnd = vecStart; vecEnd[2] -= 296.0;
	TR_TraceRayFilter(vecStart, vecEnd, MASK_PLAYERSOLID, RayType_EndPoint, TraceFilter_WorldOnlyNoPlayers);
	if (!TR_DidHit() || TR_StartSolid()) return false;
	TR_GetEndPosition(vecOut);
	return true;
}

bool HullClear(const float vecPos[3], const float vecMins[3], const float vecMaxs[3]) {
	float vecP[3];
	vecP = vecPos; vecP[2] += 2.0;
	TR_TraceHullFilter(vecP, vecP, vecMins, vecMaxs, MASK_PLAYERSOLID, TraceFilter_WorldOnlyNoPlayers);
	return !TR_DidHit();
}

bool LineClear(const float vecA[3], const float vecB[3]) {
	float a[3], b[3];
	a = vecA; b = vecB; a[2] += 40.0; b[2] += 40.0;
	TR_TraceRayFilter(a, b, MASK_PLAYERSOLID, RayType_EndPoint, TraceFilter_WorldOnlyNoPlayers);
	return !TR_DidHit();
}

int CollectSpawns(int iTeam, float vecSpawns[64][3]) {
	int n, iEnt = -1;
	char sClass[40];
	strcopy(sClass, sizeof(sClass), iTeam == CS_TEAM_CT ? "info_player_counterterrorist" : "info_player_terrorist");
	while ((iEnt = FindEntityByClassname(iEnt, sClass)) != -1 && n < 64) {
		GetEntPropVector(iEnt, Prop_Data, "m_vecAbsOrigin", vecSpawns[n++]);
	}
	return n;
}

bool PointInBuyZone(int iTeam, const float vec[3]) {
	int e = -1;
	while ((e = FindEntityByClassname(e, "func_buyzone")) != -1) {
		int iZoneTeam = GetEntProp(e, Prop_Data, "m_iTeamNum");
		if (iZoneTeam != 0 && iZoneTeam != iTeam) continue;
		float vecOrg[3], vecMins[3], vecMaxs[3];
		GetEntPropVector(e, Prop_Data, "m_vecAbsOrigin", vecOrg);
		GetEntPropVector(e, Prop_Send, "m_vecMins", vecMins);
		GetEntPropVector(e, Prop_Send, "m_vecMaxs", vecMaxs);
		AddVectors(vecMins, vecOrg, vecMins);
		AddVectors(vecMaxs, vecOrg, vecMaxs);
		if (vec[0] < vecMins[0] || vec[0] > vecMaxs[0] || vec[1] < vecMins[1] || vec[1] > vecMaxs[1]) continue;
		if (vec[2] < vecMins[2] - 80.0 || vec[2] > vecMaxs[2] + 32.0) continue;
		return true;
	}
	return false;
}

// A team info_player inside that team's buy zone. Rank: zone+clear, then zone, then any clear, then the first spawn.
bool PickBuySpawn(int iTeam, float vecOut[3], float vecAng[3]) {
	char sClass[40];
	strcopy(sClass, sizeof(sClass), iTeam == CS_TEAM_CT ? "info_player_counterterrorist" : "info_player_terrorist");
	float vecBest[3], vecBestAng[3];
	int iRank = -1;
	bool bAny;
	int e = -1;
	while ((e = FindEntityByClassname(e, sClass)) != -1) {
		float v[3], a[3];
		GetEntPropVector(e, Prop_Data, "m_vecAbsOrigin", v);
		GetEntPropVector(e, Prop_Data, "m_angAbsRotation", a);
		if (!bAny) { vecBest = v; vecBestAng = a; bAny = true; }
		bool bZone = PointInBuyZone(iTeam, v);
		bool bClear = HullClear(v, PLAYER_MINS, PLAYER_MAXS);
		int rank = (bZone && bClear) ? 2 : (bZone ? 1 : (bClear ? 0 : -1));
		if (rank > iRank) { iRank = rank; vecBest = v; vecBestAng = a; if (rank == 2) break; }
	}
	if (!bAny) return false;
	vecOut = vecBest;
	vecAng[0] = 0.0;
	vecAng[1] = vecBestAng[1];
	vecAng[2] = 0.0;
	return true;
}

bool Soldier_DropAtBuy(int iClient) {
	int iTeam = GetClientTeam(iClient);
	float vec[3], vecAng[3];
	if (!(CS_TEAM_T <= iTeam <= CS_TEAM_CT) || !PickBuySpawn(iTeam, vec, vecAng)) return false;
	vec[2] += 4.0;
	TeleportEntity(iClient, vec, vecAng, view_as<float>({0.0, 0.0, 0.0}));
	SetEntityMoveType(iClient, MOVETYPE_WALK);
	SetEntityFlags(iClient, GetEntityFlags(iClient) & ~(FL_FROZEN | FL_ATCONTROLS));
	SetClientViewEntity(iClient, iClient);
	Client_SetObserverMode(iClient, OBS_MODE_NONE, false);
	if (PointInBuyZone(iTeam, vec)) SetEntProp(iClient, Prop_Send, "m_bInBuyZone", 1);
	RequestFrame(Frame_BuyZone, GetClientUserId(iClient));
	return true;
}

public void Frame_BuyZone(int iUserId) {
	int iClient = GetClientOfUserId(iUserId);
	if (!iClient || !IsClientInGame(iClient) || !IsPlayerAlive(iClient) || g_bBodyHidden[iClient]) return;
	float v[3];
	GetClientAbsOrigin(iClient, v);
	if (PointInBuyZone(GetClientTeam(iClient), v)) SetEntProp(iClient, Prop_Send, "m_bInBuyZone", 1);
}

// Validates a terminal spot: floor found, terminal hull clear, a clear standing spot
// 48-64u in front, >=72u from every team spawn (spawned players must not get stuck).
bool ValidatePostSpot(int iTeam, const float vecPos[3], float fYaw, float vecFloor[3], char[] sWhy, int iWhyLen) {
	if (!SnapToFloor(vecPos, vecFloor)) { strcopy(sWhy, iWhyLen, "no floor / in solid"); return false; }
	if (!HullClear(vecFloor, TERMINAL_MINS, TERMINAL_MAXS)) {
		int e = TR_GetEntityIndex(); float h[3]; TR_GetEndPosition(h); char c[32] = "world";
		if (e > 0) GetEntityClassname(e, c, sizeof(c));
		FormatEx(sWhy, iWhyLen, "terminal hull blocked (%s, at %.0f %.0f %.0f, floor %.0f %.0f %.0f)", c, h[0], h[1], h[2], vecFloor[0], vecFloor[1], vecFloor[2]);
		return false;
	}
	float vecStand[3];
	GetStandSpot(vecFloor, fYaw, vecStand);
	if (!HullClear(vecStand, PLAYER_MINS, PLAYER_MAXS)) { strcopy(sWhy, iWhyLen, "no standing room in front"); return false; }
	float vecSpawns[64][3];
	int n = CollectSpawns(iTeam, vecSpawns);
	for (int i=0; i<n; i++) {
		if (GetVectorDistance(vecSpawns[i], vecFloor) < 72.0) { strcopy(sWhy, iWhyLen, "too close to a spawn point"); return false; }
	}
	strcopy(sWhy, iWhyLen, "ok");
	return true;
}

void GetStandSpot(const float vecFloor[3], float fYaw, float vecStand[3]) {
	vecStand[0] = vecFloor[0] + 56.0*Cosine(DegToRad(fYaw));
	vecStand[1] = vecFloor[1] + 56.0*Sine(DegToRad(fYaw));
	vecStand[2] = vecFloor[2];
}

// Search rings around the team's spawn centroid for the closest valid spot. Terminal faces the centroid.
bool FindPostSpot(int iTeam, float vecOut[3], float &fYaw, bool bVerbose) {
	float vecSpawns[64][3];
	int n = CollectSpawns(iTeam, vecSpawns);
	if (!n) return false;
	float vecC[3];
	for (int i=0; i<n; i++) AddVectors(vecC, vecSpawns[i], vecC);
	ScaleVector(vecC, 1.0/n);
	// centroid z: use the most common floor (lowest spawn z is fine for flat spawns)
	char sWhy[64];
	for (float r=64.0; r<=768.0; r+=32.0) {
		for (int a=0; a<24; a++) {
			float fAng = a * 15.0;
			float vecP[3];
			vecP[0] = vecC[0] + r*Cosine(DegToRad(fAng));
			vecP[1] = vecC[1] + r*Sine(DegToRad(fAng));
			vecP[2] = vecC[2];
			float fFace = fAng + 180.0; // face back toward the spawn centroid
			if (fFace >= 360.0) fFace -= 360.0;
			float vecFloor[3];
			if (!ValidatePostSpot(iTeam, vecP, fFace, vecFloor, sWhy, sizeof(sWhy))) continue;
			if (FloatAbs(vecFloor[2] - vecC[2]) > 48.0) continue;
			if (!LineClear(vecC, vecFloor)) continue;
			vecOut = vecFloor;
			fYaw = fFace;
			if (bVerbose) PrintToServer("[RTS] findpost team %d: r=%.0f -> %.0f %.0f %.0f yaw %.0f", iTeam, r, vecOut[0], vecOut[1], vecOut[2], fYaw);
			return true;
		}
	}
	return false;
}

int GetTerminal(int iTeam) {
	if (!(CS_TEAM_T <= iTeam <= CS_TEAM_CT)) return -1;
	int iEnt = EntRefToEntIndex(g_iTerminalRef[iTeam]);
	return (iEnt > 0 && IsValidEntity(iEnt)) ? iEnt : -1;
}

void PrecacheTerminals() {
	PrecacheModel(DEFAULT_TERMINAL_MODEL, true);
	PrecacheModel(FALLBACK_TERMINAL_MODEL, true);
	for (int t=CS_TEAM_T; t<=CS_TEAM_CT; t++) {
		if (g_ePost[t].sModel[0]) PrecacheModel(g_ePost[t].sModel, true);
	}
}

// Called every second and on round_start: (re)spawns terminals removed by round cleanup.
void EnsureTerminals() {
	for (int t=CS_TEAM_T; t<=CS_TEAM_CT; t++) {
		if (!g_ePost[t].bValid || GetTerminal(t) != -1) continue;
		SpawnTerminal(t);
	}
}

// Removes our terminals, including leftovers from a previous plugin instance (reload)
void RemoveTerminals() {
	for (int t=CS_TEAM_T; t<=CS_TEAM_CT; t++) g_iTerminalRef[t] = INVALID_ENT_REFERENCE;
	char sName[64];
	int iEnt = -1;
	while ((iEnt = FindEntityByClassname(iEnt, "prop_dynamic")) != -1) {
		GetEntPropString(iEnt, Prop_Data, "m_iName", sName, sizeof(sName));
		if (StrContains(sName, "css_rts_terminal_") == 0) RemoveEntity(iEnt);
	}
}

int SpawnTerminal(int iTeam) {
	int iEnt = CreateEntityByName("prop_dynamic_override");
	if (iEnt == -1) return -1;
	char sName[32];
	FormatEx(sName, sizeof(sName), "css_rts_terminal_%s", iTeam == CS_TEAM_CT ? "ct" : "t");
	DispatchKeyValue(iEnt, "targetname", sName);
	DispatchKeyValue(iEnt, "model", g_ePost[iTeam].sModel);
	DispatchKeyValue(iEnt, "solid", "6");
	DispatchKeyValue(iEnt, "disableshadows", "1");
	float vecPos[3];
	if (!SnapToFloor(g_ePost[iTeam].vecOrigin, vecPos)) vecPos = g_ePost[iTeam].vecOrigin;
	DispatchKeyValueVector(iEnt, "origin", vecPos);
	DispatchKeyValueVector(iEnt, "angles", g_ePost[iTeam].vecAngles);
	if (!DispatchSpawn(iEnt)) return -1;
	SetEntProp(iEnt, Prop_Data, "m_takedamage", 0);
	if (iTeam == CS_TEAM_CT) SetEntityRenderColor(iEnt, 150, 190, 255, 255);
	else SetEntityRenderColor(iEnt, 255, 190, 120, 255);
	g_iTerminalRef[iTeam] = EntIndexToEntRef(iEnt);
	return iEnt;
}

// Is the player close to and looking at a terminal? Returns the terminal's team or 0.
int GetAimedTerminal(int iClient) {
	float vecEye[3], vecAng[3], vecFwd[3];
	GetClientEyePosition(iClient, vecEye);
	GetClientEyeAngles(iClient, vecAng);
	GetAngleVectors(vecAng, vecFwd, NULL_VECTOR, NULL_VECTOR);
	float fRange = g_hCvarUseRange.FloatValue;
	for (int t=CS_TEAM_T; t<=CS_TEAM_CT; t++) {
		int iEnt = GetTerminal(t);
		if (iEnt == -1) continue;
		float vecPos[3], vecDir[3];
		GetEntPropVector(iEnt, Prop_Data, "m_vecAbsOrigin", vecPos);
		vecPos[2] += 32.0;
		SubtractVectors(vecPos, vecEye, vecDir);
		float fDist = GetVectorLength(vecDir);
		if (fDist > fRange) continue;
		NormalizeVector(vecDir, vecDir);
		if (fDist < 48.0 || GetVectorDotProduct(vecDir, vecFwd) > 0.6) return t;
	}
	return 0;
}
