// css_rts/workers.sp -- M1.5 worker economy: seats, buying, sitting income, threat/flee, death bounty
//
// cs_office.cfg:
//   "seats" { "1" { "origin" "x y z"  "yaw" "90"  "team" "T" } ... }   team: T | CT | any
//   "flee"  { "1" { "origin" "x y z"  "team" "T" } ... }               (default flee point: own command post)

#define MAX_SEATS		48
#define MAX_FLEE		16

char g_sWorkerModels[][] = {
	"models/humans/group01/male_02.mdl", "models/humans/group01/female_01.mdl", "models/humans/group01/male_07.mdl",
	"models/humans/group01/female_04.mdl", "models/humans/group01/male_04.mdl", "models/humans/group01/male_09.mdl"
};

int g_iSeats;
float g_vecSeat[MAX_SEATS][3];
float g_fSeatYaw[MAX_SEATS];
int g_iSeatTeam[MAX_SEATS];     // 0 = any
int g_iSeatOwner[MAX_SEATS];    // npc slot or -1
int g_iFlee;
int g_iWorkerHome[MAX_NPCS];
float g_vecFlee[MAX_FLEE][3];
int g_iFleeTeam[MAX_FLEE];

ConVar g_hCvarWorkerAutoReturn;
ConVar g_hCvarWorkerSitAnim;
int g_iFloatTeam[2049];
int g_iWorkersOwned[4];         // workers a team should have (respawned after map cleanup)
int g_iWorkersBought[4];
float g_fWorkerPanic[MAX_NPCS];

ConVar g_hCvarWorkerHealth;
ConVar g_hCvarWorkerStart;
ConVar g_hCvarWorkerCap;
ConVar g_hCvarWorkerCost;
ConVar g_hCvarWorkerCostStep;
ConVar g_hCvarWorkerBountyIntel;
ConVar g_hCvarWorkerBountyCash;
ConVar g_hCvarWorkerThreatRadius;

void Workers_Init() {
	g_hCvarWorkerHealth = CreateConVar("css_rts_worker_health", "60", "Worker hit points", _, true, 1.0);
	g_hCvarWorkerStart = CreateConVar("css_rts_worker_start", "0", "Workers each team starts with", _, true, 0.0, true, 6.0);
	g_hCvarWorkerCap = CreateConVar("css_rts_worker_cap", "8", "Max workers per team", _, true, 0.0, true, 32.0);
	g_hCvarWorkerCost = CreateConVar("css_rts_worker_cost", "360", "Intel per worker (flat; a seated worker earns it back in ~2 min at +3/s)", _, true, 0.0);
	g_hCvarWorkerCostStep = CreateConVar("css_rts_worker_cost_step", "0", "Extra Intel per worker already bought", _, true, 0.0);
	g_hCvarWorkerBountyIntel = CreateConVar("css_rts_worker_bounty_intel", "250", "Intel the killer's team gets for killing a worker", _, true, 0.0);
	g_hCvarWorkerBountyCash = CreateConVar("css_rts_worker_bounty_cash", "300", "Cash the killer gets for killing a worker", _, true, 0.0);
	g_hCvarWorkerSitAnim = CreateConVar("css_rts_worker_sit_anim", "sitchairtable1", "Seated worker loop: sitchairtable1 (forearms on the desk) or Sit_Chair (upright, hands in lap)");
	g_hCvarWorkerAutoReturn = CreateConVar("css_rts_worker_auto_return", "0", "1 = fled workers return to their seat by themselves after 8 safe seconds; 0 = wait for the Commander's order", _, true, 0.0, true, 1.0);
	g_hCvarWorkerThreatRadius = CreateConVar("css_rts_worker_threat_radius", "550", "Workers flee from visible enemies within this distance", _, true, 0.0);
	AddCommandListener(Cmd_WorkerBack, "drop");
}

void Workers_LoadConfig(KeyValues hKv) {
	g_iSeats = 0;
	g_iFlee = 0;
	if (hKv == null) return;
	char sTeam[8];
	if (hKv.JumpToKey("seats") && hKv.GotoFirstSubKey()) {
		do {
			if (g_iSeats >= MAX_SEATS) break;
			if (!KvGetVec(hKv, "origin", g_vecSeat[g_iSeats])) continue;
			g_fSeatYaw[g_iSeats] = hKv.GetFloat("yaw");
			hKv.GetString("team", sTeam, sizeof(sTeam), "any");
			g_iSeatTeam[g_iSeats] = TeamFromName(sTeam);
			g_iSeatOwner[g_iSeats] = -1;
			g_iSeats++;
		} while (hKv.GotoNextKey());
		hKv.GoBack(); hKv.GoBack();
	}
	if (hKv.JumpToKey("flee") && hKv.GotoFirstSubKey()) {
		do {
			if (g_iFlee >= MAX_FLEE) break;
			if (!KvGetVec(hKv, "origin", g_vecFlee[g_iFlee])) continue;
			hKv.GetString("team", sTeam, sizeof(sTeam), "any");
			g_iFleeTeam[g_iFlee] = TeamFromName(sTeam);
			g_iFlee++;
		} while (hKv.GotoNextKey());
		hKv.GoBack(); hKv.GoBack();
	}
	LogMessage("Workers: %d seats, %d flee points", g_iSeats, g_iFlee);
}

void Workers_MapStart() {
	for (int k=0; k<sizeof(g_sWorkerModels); k++) PrecacheModel(g_sWorkerModels[k], true);
	for (int s=0; s<MAX_SEATS; s++) g_iSeatOwner[s] = -1;
	Workers_ResetMatch(false);
	CreateTimer(0.5, Timer_WorkerThink, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

// Match (re)start: every team back to the starting workers
void Workers_ResetMatch(bool bRemove=true) {
	if (bRemove) {
		Npc_RemoveAll();
		for (int s=0; s<MAX_SEATS; s++) g_iSeatOwner[s] = -1;   // v0.5.1: seats were left "owned" by removed workers
	}
	for (int t=0; t<4; t++) { g_iWorkersOwned[t] = g_hCvarWorkerStart.IntValue; g_iWorkersBought[t] = 0; }
}

int Worker_NextCost(int iTeam) {
	return g_hCvarWorkerCost.IntValue + g_hCvarWorkerCostStep.IntValue * g_iWorkersBought[iTeam];
}

// Called every second (HUD timer) and on round_start: respawn owned workers that map cleanup removed
void Workers_Ensure() {
	for (int i=0; i<MAX_NPCS; i++) {
		if (g_eNpc[i].bUsed && Npc_GetEntity(i) == -1) {
			if (g_eNpc[i].iSeat != -1) g_iSeatOwner[g_eNpc[i].iSeat] = -1;
			delete g_eNpc[i].hPath;
			Npc eEmpty;
			g_eNpc[i] = eEmpty;
		}
	}
	for (int t=CS_TEAM_T; t<=CS_TEAM_CT; t++) {
		if (!g_ePost[t].bValid) continue;
		int iHave = Npc_Count(Npc_Worker, t);
		for (int k=iHave; k<g_iWorkersOwned[t]; k++) Worker_Spawn(t, true);
	}
}

int Worker_Spawn(int iTeam, bool bAutoSeat) {
	float vecPos[3];
	GetStandSpot(g_ePost[iTeam].vecOrigin, g_ePost[iTeam].vecAngles[1], vecPos);
	vecPos[0] += GetRandomFloat(-24.0, 24.0);
	vecPos[1] += GetRandomFloat(-24.0, 24.0);
	return Worker_SpawnAt(iTeam, vecPos, g_ePost[iTeam].vecAngles[1], bAutoSeat);
}

int Worker_SpawnAt(int iTeam, const float vecPos[3], float fYaw, bool bAutoSeat) {
	int i = Npc_Spawn(Npc_Worker, iTeam, g_sWorkerModels[GetRandomInt(0, sizeof(g_sWorkerModels)-1)], vecPos, fYaw, g_hCvarWorkerHealth.IntValue);
	if (i == -1) return -1;
	g_iWorkerHome[i] = -1;
	int iEnt = Npc_GetEntity(i);
	if (iTeam == CS_TEAM_CT) SetEntityRenderColor(iEnt, 200, 220, 255, 255); else SetEntityRenderColor(iEnt, 255, 225, 190, 255);
	if (bAutoSeat) {
		int s = FindFreeSeat(iTeam, vecPos);
		if (s != -1) Worker_GoToSeat(i, s);
	}
	return i;
}

void Seats_Reclaim() {
	for (int s = 0; s < g_iSeats; s++) {
		int o = g_iSeatOwner[s];
		if (o < 0) continue;
		if (o >= MAX_NPCS || !g_eNpc[o].bUsed || g_eNpc[o].eKind != Npc_Worker || g_eNpc[o].eState == NS_Dead || g_eNpc[o].iSeat != s) g_iSeatOwner[s] = -1;
	}
}

int FindFreeSeat(int iTeam, const float vecNear[3], float fMaxDist=999999.0) {
	Seats_Reclaim();
	int iBest = -1;
	float fBest = fMaxDist;
	for (int s=0; s<g_iSeats; s++) {
		if (g_iSeatOwner[s] != -1 || (g_iSeatTeam[s] && g_iSeatTeam[s] != iTeam)) continue;
		float d = GetVectorDistance(vecNear, g_vecSeat[s]);
		if (d < fBest) { fBest = d; iBest = s; }
	}
	return iBest;
}

void Worker_ReleaseSeat(int i) {
	if (g_eNpc[i].iSeat != -1 && g_iSeatOwner[g_eNpc[i].iSeat] == i) g_iSeatOwner[g_eNpc[i].iSeat] = -1;
	g_eNpc[i].iSeat = -1;
}

// v0.5.1: workers jog on long trips (cs_office: CT seats are ~1700u from the CT post, T's are next
// to it) so both teams' workers start producing within a few seconds of each other
float Worker_Speed(int i, const float vecGoal[3]) {
	int iEnt = Npc_GetEntity(i);
	if (iEnt == -1) return 80.0;
	float v[3];
	GetEntPropVector(iEnt, Prop_Data, "m_vecAbsOrigin", v);
	return GetVectorDistance(v, vecGoal) > 600.0 ? 170.0 : 80.0;
}

// Already standing on the chair the commander clicked: sit there, do not path back via the hub.
void Worker_SeatNow(int i, int s) {
	Worker_ReleaseSeat(i);
	g_iSeatOwner[s] = i;
	g_eNpc[i].iSeat = s;
	g_iWorkerHome[i] = s;
	int iEnt = Npc_GetEntity(i);
	if (iEnt != -1) {
		float vecAng[3];
		vecAng[1] = g_fSeatYaw[s];
		TeleportEntity(iEnt, g_vecSeat[s], vecAng, NULL_VECTOR);
	}
	g_eNpc[i].eState = NS_Idle;
	Worker_OnArrive(i);
}

public Action Cmd_WorkerBack(int iClient, const char[] sCmd, int iArgs) {
	if (!iClient || !g_eCommander[iClient].bEnabled) return Plugin_Continue;
	if (!Worker_SendHome(iClient)) return Plugin_Continue;
	return Plugin_Handled;
}

bool Worker_SendHome(int iClient) {
	ArrayList hList = g_eCommander[iClient].hSelectedUnits;
	if (hList == null) return false;
	bool bAny, bSoon;
	float fSoon;
	for (int n = 0; n < hList.Length; n++) {
		int iEnt = EntRefToEntIndex(hList.Get(n));
		int i = iEnt > MaxClients ? Npc_FromEntity(iEnt) : -1;
		if (i < 0 || g_eNpc[i].eKind != Npc_Worker) continue;
		float fLeft;
		if (Worker_Panicked(i, fLeft)) {
			bSoon = true;
			if (fLeft > fSoon) fSoon = fLeft;
			continue;
		}
		bool bAway = g_eNpc[i].eState == NS_Cowering || g_eNpc[i].eState == NS_Idle || g_eNpc[i].eState == NS_Fleeing;
		if (!bAway) continue;
		int s = g_iWorkerHome[i];
		if (s < 0 || s >= g_iSeats) s = g_eNpc[i].iSeat;
		if (s < 0 || (g_iSeatOwner[s] != -1 && g_iSeatOwner[s] != i)) s = FindFreeSeat(g_eNpc[i].iTeam, g_vecSeat[s < 0 ? 0 : s]);
		if (s >= 0) Worker_GoToSeat(i, s);
		bAny = true;
	}
	if (bAny) PrintHintText(iClient, "Back to work");
	else if (bSoon) PrintHintText(iClient, "Still terrified  %.0fs", fSoon);
	return bAny || bSoon;
}

bool Worker_CampNear(int iTeam, float vec[3]) {
	for (int n = 0; n < MAX_NPCS; n++) {
		if (!g_eNpc[n].bUsed || g_eNpc[n].eKind != Npc_Worker || g_eNpc[n].iTeam != iTeam || g_eNpc[n].eState == NS_Dead) continue;
		int e = Npc_GetEntity(n);
		if (e == -1) continue;
		GetEntPropVector(e, Prop_Data, "m_vecAbsOrigin", vec);
		vec[0] += 70.0;
		return true;
	}
	return false;
}

bool Worker_Panicked(int i, float &fLeft) {
	fLeft = g_fWorkerPanic[i] - GetGameTime();
	return fLeft > 0.0;
}

bool Worker_GoToSeat(int i, int s) {
	Worker_ReleaseSeat(i);
	g_iSeatOwner[s] = i;
	g_eNpc[i].iSeat = s;
	g_iWorkerHome[i] = s;
	bool bOk = Npc_MoveTo(i, g_vecSeat[s], Worker_Speed(i, g_vecSeat[s]), NS_Walking, true, g_fSeatYaw[s]);
	// v0.5.3.1: decide walk/jog by the real path length (stairs/detours), not the straight line
	if (bOk && g_eNpc[i].fSpeed < 120.0 && g_eNpc[i].hPath != null && g_eNpc[i].hPath.Length > 1) {
		float fLen, a[3], b[3];
		int iEnt = Npc_GetEntity(i);
		if (iEnt != -1) GetEntPropVector(iEnt, Prop_Data, "m_vecAbsOrigin", a);
		for (int k=g_eNpc[i].iPathIdx; k<g_eNpc[i].hPath.Length; k++) { g_eNpc[i].hPath.GetArray(k, b); fLen += GetVectorDistance(a, b); a = b; }
		if (fLen > 700.0) { g_eNpc[i].fSpeed = 170.0; Npc_SetAnim(i, "run_all", 170.0 / 190.0); }
	}
	return bOk;
}

// Commander right-click: a free seat near the point -> sit there; otherwise just walk there
bool Worker_Order(int i, const float vecPos[3]) {
	float fLeft;
	if (Worker_Panicked(i, fLeft)) return false;
	int s = FindFreeSeat(g_eNpc[i].iTeam, vecPos, 72.0);
	if (s == -1 && g_eNpc[i].iSeat != -1 && GetVectorDistance(vecPos, g_vecSeat[g_eNpc[i].iSeat]) < 72.0) s = g_eNpc[i].iSeat;
	if (s != -1) {
		Worker_GoToSeat(i, s);
	} else {
		Worker_ReleaseSeat(i);
		Npc_MoveTo(i, vecPos, Worker_Speed(i, vecPos), NS_Walking);
	}
	return true;
}

void Worker_OnArrive(int i) {
	int s = g_eNpc[i].iSeat;
	int iEnt = Npc_GetEntity(i);
	if (g_eNpc[i].eState == NS_Fleeing) {
		g_eNpc[i].eState = NS_Cowering;
		g_eNpc[i].fSafeSince = 0.0;
		Npc_SetAnim(i, "cower");
		return;
	}
	float vecHere[3];
	if (iEnt != -1) GetOrigin(iEnt, vecHere);
	vecHere[2] = g_vecSeat[s == -1 ? 0 : s][2];
	if (s != -1 && iEnt != -1 && GetVectorDistance(g_vecSeat[s], vecHere) < 32.0) {
		float vecAng[3];
		vecAng[1] = g_fSeatYaw[s];
		TeleportEntity(iEnt, g_vecSeat[s], vecAng, NULL_VECTOR);
		g_eNpc[i].eState = NS_Seated;
		// v0.5.3: sit-down transition, then the seated work loop (css_rts_worker_sit_anim)
		Npc_SetAnim(i, "Idle_to_Sit_Chair");
		DataPack hPack;
		CreateDataTimer(1.8, Timer_WorkerSitLoop, hPack, TIMER_FLAG_NO_MAPCHANGE);
		hPack.WriteCell(i);
		hPack.WriteCell(g_eNpc[i].iRef);
		return;
	}
	g_eNpc[i].eState = NS_Idle;
	Npc_SetAnim(i, "idle_subtle");
}

public Action Timer_WorkerSitLoop(Handle hTimer, DataPack hPack) {
	hPack.Reset();
	int i = hPack.ReadCell();
	int iRef = hPack.ReadCell();
	if (!g_eNpc[i].bUsed || g_eNpc[i].iRef != iRef || g_eNpc[i].eState != NS_Seated) return Plugin_Stop;
	char sAnim[48];
	g_hCvarWorkerSitAnim.GetString(sAnim, sizeof(sAnim));
	Npc_SetAnim(i, sAnim[0] ? sAnim : "Sit_Chair");
	return Plugin_Stop;
}

void GetOrigin(int iEnt, float v[3]) {
	GetEntPropVector(iEnt, Prop_Data, "m_vecAbsOrigin", v);
}

void Worker_Spread(int i, float vec[3]) {
	int t = g_eNpc[i].iTeam;
	int slot;
	for (int k = 0; k < MAX_NPCS; k++) {
		if (k == i || !g_eNpc[k].bUsed || g_eNpc[k].eKind != Npc_Worker || g_eNpc[k].iTeam != t) continue;
		if (g_eNpc[k].eState == NS_Cowering || g_eNpc[k].eState == NS_Fleeing) slot++;
	}
	float fAng = float(slot) * 1.15;
	float fRad = 48.0 + float(slot % 4) * 22.0;
	vec[0] += Cosine(fAng) * fRad;
	vec[1] += Sine(fAng) * fRad;
	if (!Nav_Snap(vec)) {
		vec[0] -= Cosine(fAng) * fRad;
		vec[1] -= Sine(fAng) * fRad;
		Nav_Snap(vec);
	}
}

void Worker_CowerHere(int i, const float vec[3]) {
	int iEnt = Npc_GetEntity(i);
	g_eNpc[i].eState = NS_Cowering;
	g_eNpc[i].iPathIdx = 9999;
	if (iEnt != -1) TeleportEntity(iEnt, vec, NULL_VECTOR, view_as<float>({0.0, 0.0, 0.0}));
	Npc_SetAnim(i, "cower");
}

void Worker_Flee(int i) {
	int iEnt = Npc_GetEntity(i);
	if (iEnt == -1) return;
	float vecPos[3];
	GetOrigin(iEnt, vecPos);
	g_eNpc[i].fSafeSince = 0.0;
	g_fWorkerPanic[i] = GetGameTime() + 30.0;
	int s = g_eNpc[i].iSeat;
	if (s < 0 || s >= g_iSeats) s = g_iWorkerHome[i];
	if (s < 0 || s >= g_iSeats || GetVectorDistance(vecPos, g_vecSeat[s]) > 140.0) s = -1;
	if (s >= 0) g_iWorkerHome[i] = s;
	float vecSpot[3];
	if (s >= 0) vecSpot = g_vecSeat[s];
	else vecSpot = vecPos;
	float fAng = GetRandomFloat(0.0, 6.28318);
	float vecHide[3];
	vecHide[0] = vecSpot[0] + Cosine(fAng) * GetRandomFloat(40.0, 80.0);
	vecHide[1] = vecSpot[1] + Sine(fAng) * GetRandomFloat(40.0, 80.0);
	vecHide[2] = vecSpot[2];
	bool bNear = Nav_Snap(vecHide) && GetVectorDistance(vecHide, vecPos) <= 120.0 && GetVectorDistance(vecHide, vecSpot) <= 110.0 && FloatAbs(vecHide[2] - vecPos[2]) <= 36.0;
	if (!bNear || !Npc_MoveTo(i, vecHide, 210.0, NS_Fleeing)) {
		g_eNpc[i].eState = NS_Cowering;
		g_eNpc[i].iPathIdx = 9999;
		Npc_SetAnim(i, "cower");
	}
}

void Worker_OnHurt(int i, int iAttacker) {
	#pragma unused iAttacker
	if (g_eNpc[i].eState != NS_Fleeing) Worker_Flee(i);
}

void Worker_OnKilled(int i, int iAttacker) {
	int t = g_eNpc[i].iTeam;
	Worker_ReleaseSeat(i);
	if (g_iWorkersOwned[t] > 0) g_iWorkersOwned[t]--;
	if (1 <= iAttacker <= MaxClients && IsClientInGame(iAttacker)) {
		int at = GetClientTeam(iAttacker);
		if (at != t && (at == CS_TEAM_T || at == CS_TEAM_CT)) {
			g_iIntel[at] += g_hCvarWorkerBountyIntel.IntValue;
			SetEntProp(iAttacker, Prop_Send, "m_iAccount", GetEntProp(iAttacker, Prop_Send, "m_iAccount") + g_hCvarWorkerBountyCash.IntValue);
			if (!IsFakeClient(iAttacker)) PrintToChat(iAttacker, "\x04[RTS]\x01 Enemy worker killed: +$%d, team +%d Intel.", g_hCvarWorkerBountyCash.IntValue, g_hCvarWorkerBountyIntel.IntValue);
		}
	}
	TeamChat(t, "\x04[RTS]\x01 \x02A worker was killed!\x01 (%d left)", Npc_Count(Npc_Worker, t) - 1);
}

void TeamChat(int iTeam, const char[] sFmt, any ...) {
	char sMsg[192];
	VFormat(sMsg, sizeof(sMsg), sFmt, 3);
	for (int c=1; c<=MaxClients; c++) {
		if (IsClientInGame(c) && !IsFakeClient(c) && GetClientTeam(c) == iTeam) PrintToChat(c, "%s", sMsg);
	}
}

// Visible enemy player within the threat radius?
bool Worker_Threatened(int i, const float vecPos[3]) {
	float fR = g_hCvarWorkerThreatRadius.FloatValue;
	float vecEye[3];
	vecEye = vecPos; vecEye[2] += 60.0;
	if (g_iProofWorker == i) return false;   // sm_rts_debug_proof: only the scripted threat counts (clean recording)
	for (int c=1; c<=MaxClients; c++) {
		if (!IsClientInGame(c) || !IsPlayerAlive(c) || g_bBodyHidden[c] || GetEntityMoveType(c) == MOVETYPE_NOCLIP) continue;   // noclip = observer/proof camera
		int ct = GetClientTeam(c);
		if (ct == g_eNpc[i].iTeam || (ct != CS_TEAM_T && ct != CS_TEAM_CT)) continue;
		float vecC[3];
		GetClientEyePosition(c, vecC);
		if (GetVectorDistance(vecC, vecEye) > fR) continue;
		TR_TraceRayFilter(vecEye, vecC, MASK_VISIBLE, RayType_EndPoint, TraceFilter_NpcGround);
		if (!TR_DidHit()) return true;
	}
	return false;
}

public Action Timer_WorkerThink(Handle hTimer) {
	float fNow = GetGameTime();
	for (int i=0; i<MAX_NPCS; i++) {
		if (!g_eNpc[i].bUsed || g_eNpc[i].eKind != Npc_Worker || g_eNpc[i].eState == NS_Dead) continue;
		int iEnt = Npc_GetEntity(i);
		if (iEnt == -1) continue;
		float vecPos[3];
		GetOrigin(iEnt, vecPos);
		bool bThreat = Worker_Threatened(i, vecPos) || fNow - g_eNpc[i].fLastHurt < 3.0;
		NpcState eState = g_eNpc[i].eState;
		if (g_fWorkerPanic[i] > fNow) {
			float fLeft = g_fWorkerPanic[i] - fNow;
			if (eState == NS_Fleeing && fLeft < 2.0) {
				g_eNpc[i].eState = NS_Cowering;
				g_eNpc[i].iPathIdx = 9999;
				Npc_SetAnim(i, "cower");
			} else if (eState != NS_Fleeing && eState != NS_Cowering) Worker_Flee(i);
			continue;
		}
		if (bThreat) {
			if (eState == NS_Seated || eState == NS_Walking || eState == NS_Idle) Worker_Flee(i);
			g_eNpc[i].fSafeSince = 0.0;
		} else if (g_bVsAi && g_eNpc[i].iTeam == VsAi_Enemy() && eState == NS_Idle && g_eNpc[i].iSeat < 0) {
			int s = FindFreeSeat(g_eNpc[i].iTeam, vecPos);
			if (s != -1) Worker_GoToSeat(i, s);
		} else if (eState == NS_Cowering && (g_hCvarWorkerAutoReturn.BoolValue || (g_bVsAi && g_eNpc[i].iTeam == VsAi_Enemy()))) {
			if (g_eNpc[i].fSafeSince == 0.0) g_eNpc[i].fSafeSince = fNow;
			else if (fNow - g_eNpc[i].fSafeSince > 4.0) {
				int s = g_iWorkerHome[i];
				if (s < 0 || s >= g_iSeats) s = g_eNpc[i].iSeat;
				if (s >= 0 && s < g_iSeats && (g_iSeatOwner[s] == -1 || g_iSeatOwner[s] == i)) Worker_GoToSeat(i, s);
				else { g_eNpc[i].eState = NS_Idle; Npc_SetAnim(i, "idle_subtle"); }
			}
		}
	}
	return Plugin_Continue;
}

int CountSeatedWorkers(int iTeam) {
	int n;
	for (int i=0; i<MAX_NPCS; i++) {
		if (g_eNpc[i].bUsed && g_eNpc[i].eKind == Npc_Worker && g_eNpc[i].iTeam == iTeam && g_eNpc[i].eState == NS_Seated) n++;
	}
	return n;
}

// Intel tick feedback: floating "+N" above each seated worker, visible to its team
int g_iWorkerTickCount[4];

// Every 5 ticks: a rising "+" marker (through walls) over each producing worker for the commander,
// plus a hint with the batch total. (CSS has no point_worldtext, so no world-space numbers.)
void Workers_OnIntelTick(int iTeam, int iPerWorker) {
	if (iPerWorker <= 0) return;
	if (++g_iWorkerTickCount[iTeam] % 5 != 0) return;
	int iCmdr = GetTeamCommander(iTeam);
	if (!iCmdr || IsFakeClient(iCmdr) || !g_eCommander[iCmdr].bEnabled) return;
	int n;
	for (int i=0; i<MAX_NPCS; i++) {
		if (!g_eNpc[i].bUsed || g_eNpc[i].eKind != Npc_Worker || g_eNpc[i].iTeam != iTeam || g_eNpc[i].eState != NS_Seated) continue;
		int iEnt = Npc_GetEntity(i);
		if (iEnt == -1) continue;
		float vecPos[3];
		GetOrigin(iEnt, vecPos);
		IntelPlus(iCmdr, vecPos);
		n++;
	}
	// v0.5.2: no centre text every 5 s (the "+" pulses above the workers + the HUD Intel line show it)
}


bool g_bWorldTextChecked, g_bWorldTextOk;

void FloatText(int iTeam, const float vecPos[3], const char[] sText) {
	if (!g_bWorldTextChecked || g_bWorldTextOk) {
		int iEnt = CreateEntityByName("point_worldtext");
		g_bWorldTextChecked = true;
		g_bWorldTextOk = iEnt != -1;
		if (iEnt != -1) {
			DispatchKeyValue(iEnt, "message", sText);
			DispatchKeyValue(iEnt, "textsize", "12");
			DispatchKeyValue(iEnt, "color", iTeam == CS_TEAM_CT ? "120 200 255 255" : "255 200 80 255");
			DispatchKeyValue(iEnt, "orientation", "1"); // face camera
			DispatchKeyValueVector(iEnt, "origin", vecPos);
			DispatchSpawn(iEnt);
			g_iFloatTeam[iEnt] = iTeam;
			SDKHook(iEnt, SDKHook_SetTransmit, SDKHookCB_FloatTextTransmit);
			DataPack hPack;
			CreateDataTimer(0.05, Timer_FloatRise, hPack, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
			hPack.WriteCell(EntIndexToEntRef(iEnt));
			hPack.WriteFloat(GetGameTime());
			return;
		}
	}
	// fallback: hint text to the commander only
	int iCmdr = GetTeamCommander(iTeam);
	if (iCmdr && !IsFakeClient(iCmdr)) PrintCenterText(iCmdr, "Workers %s Intel", sText);
}

public Action SDKHookCB_FloatTextTransmit(int iEnt, int iClient) {
	return (GetClientTeam(iClient) == g_iFloatTeam[iEnt]) ? Plugin_Continue : Plugin_Handled;
}

public Action Timer_FloatRise(Handle hTimer, DataPack hPack) {
	hPack.Reset();
	int iEnt = EntRefToEntIndex(hPack.ReadCell());
	float fStart = hPack.ReadFloat();
	if (iEnt <= 0 || !IsValidEntity(iEnt)) return Plugin_Stop;
	if (GetGameTime() - fStart > 1.5) { RemoveEntity(iEnt); return Plugin_Stop; }
	float v[3];
	GetOrigin(iEnt, v);
	v[2] += 2.0;
	TeleportEntity(iEnt, v, NULL_VECTOR, NULL_VECTOR);
	return Plugin_Continue;
}

// Commander menu: buy worker
bool Worker_CanHire(int iClient, bool bQuiet=false) {
	int t = GetClientTeam(iClient);
	if (!g_ePost[t].bValid) { if (!bQuiet) PrintToChat(iClient, "\x04[RTS]\x01 No command post on this map."); return false; }
	if (Npc_Count(Npc_Worker, t) >= g_hCvarWorkerCap.IntValue) { if (!bQuiet) PrintToChat(iClient, "\x04[RTS]\x01 Worker cap reached (%d).", g_hCvarWorkerCap.IntValue); return false; }
	int iCost = Worker_NextCost(t);
	if (g_iIntel[t] < iCost) { if (!bQuiet) PrintToChat(iClient, "\x04[RTS]\x01 Need %d Intel (have %d).", iCost, g_iIntel[t]); return false; }
	return true;
}

// Pay + spawn at the command post. Returns the NPC slot or -1.
int Worker_HireAt(int iClient, const float vecPos[3], float fYaw) {
	if (!Worker_CanHire(iClient)) return -1;
	int t = GetClientTeam(iClient);
	int i = Worker_SpawnAt(t, vecPos, fYaw, false);
	if (i == -1) return -1;
	g_iIntel[t] -= Worker_NextCost(t);
	g_iWorkersBought[t]++;
	g_iWorkersOwned[t]++;
	if (!IsFakeClient(iClient)) PrintToChat(iClient, "\x04[RTS]\x01 Worker hired (%d/%d).", Npc_Count(Npc_Worker, t), g_hCvarWorkerCap.IntValue);
	VsAi_MirrorWorker(t);
	return i;
}

int Worker_Hire(int iClient, bool bAutoSeat) {
	if (!Worker_CanHire(iClient)) return -1;
	int t = GetClientTeam(iClient);
	int i = Worker_Spawn(t, bAutoSeat);
	if (i == -1) return -1;
	g_iIntel[t] -= Worker_NextCost(t);
	g_iWorkersBought[t]++;
	g_iWorkersOwned[t]++;
	if (!IsFakeClient(iClient)) PrintToChat(iClient, "\x04[RTS]\x01 Worker hired (%d/%d).", Npc_Count(Npc_Worker, t), g_hCvarWorkerCap.IntValue);
	VsAi_MirrorWorker(t);
	return i;
}

void VsAi_MirrorWorker(int iTeam) {
	if (!VsAi_FromPlayer(iTeam)) return;
	int e = VsAi_Enemy();
	if (e < CS_TEAM_T || e > CS_TEAM_CT || !g_ePost[e].bValid) return;
	if (Npc_Count(Npc_Worker, e) >= g_hCvarWorkerCap.IntValue) return;
	g_bVsAiBusy = true;
	int iCost = Worker_NextCost(e);
	int iHad = g_iIntel[e];
	if (iHad < iCost) g_iIntel[e] = iCost;
	int i = Worker_Spawn(e, true);
	if (i != -1) {
		g_iIntel[e] -= iCost;
		if (iHad < iCost) g_iIntel[e] = 0;
		g_iWorkersBought[e]++;
		g_iWorkersOwned[e]++;
	} else g_iIntel[e] = iHad;
	g_bVsAiBusy = false;
}

bool Worker_Buy(int iClient) {
	return Worker_Hire(iClient, true) != -1;
}
