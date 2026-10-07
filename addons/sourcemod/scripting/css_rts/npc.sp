// css_rts/npc.sp -- generic non-player NPC (prop_dynamic): spawn, path movement, animation, health,
// damage and death. No player slot, not on the scoreboard. Workers use it now; combat units next.

#define MAX_NPCS			96
#define NPC_HULL_RADIUS		13.0
#define NPC_HULL_HEIGHT		72.0

enum NpcKind {
	Npc_None = 0,
	Npc_Worker,
	Npc_Soldier
};

enum NpcState {
	NS_Idle = 0,
	NS_Walking,
	NS_Seated,
	NS_Fleeing,
	NS_Cowering,
	NS_Dead
};

enum struct Npc {
	bool bUsed;
	int iRef;
	int iTeam;
	NpcKind eKind;
	NpcState eState;
	int iHealth;
	int iMaxHealth;
	ArrayList hPath;
	int iPathIdx;
	float fSpeed;
	bool bHasGoalYaw;
	float fGoalYaw;
	char sAnim[32];
	int iSeat;          // worker: seat index it owns (-1 none)
	float fLastHurt;
	float fSafeSince;
	float fStuckTime;
	float vecLastPos[3];
}

Npc g_eNpc[MAX_NPCS];
float g_fNpcLastFrame;

bool g_bNpcDebug = false;

void Npc_MapStart() {
	for (int i=0; i<MAX_NPCS; i++) {
		delete g_eNpc[i].hPath;
		Npc eEmpty;
		g_eNpc[i] = eEmpty;
	}
	g_fNpcLastFrame = 0.0;
}

int Npc_GetEntity(int i) {
	if (!g_eNpc[i].bUsed) return -1;
	int iEnt = EntRefToEntIndex(g_eNpc[i].iRef);
	return (iEnt > 0 && IsValidEntity(iEnt)) ? iEnt : -1;
}

bool Npc_NearestEnemy(int iEnemy, const float vecFrom[3], float &fBest, float vecOut[3]) {
	bool bHit;
	for (int n=0; n<MAX_NPCS; n++) {
		if (!g_eNpc[n].bUsed || g_eNpc[n].iTeam != iEnemy || g_eNpc[n].eState == NS_Dead) continue;
		int e = Npc_GetEntity(n);
		if (e == -1) continue;
		float v[3];
		GetEntPropVector(e, Prop_Data, "m_vecAbsOrigin", v);
		float d = GetVectorDistance(vecFrom, v);
		if (d < fBest) { fBest = d; vecOut = v; bHit = true; }
	}
	return bHit;
}

int Npc_FromEntity(int iEnt) {
	if (iEnt <= MaxClients) return -1;
	int iRef = EntIndexToEntRef(iEnt);
	for (int i=0; i<MAX_NPCS; i++) {
		if (g_eNpc[i].bUsed && g_eNpc[i].iRef == iRef) return i;
	}
	return -1;
}

int Npc_Count(NpcKind eKind, int iTeam, bool bAliveOnly=true) {
	int n;
	for (int i=0; i<MAX_NPCS; i++) {
		if (!g_eNpc[i].bUsed || g_eNpc[i].eKind != eKind || g_eNpc[i].iTeam != iTeam) continue;
		if (bAliveOnly && g_eNpc[i].eState == NS_Dead) continue;
		n++;
	}
	return n;
}

int Npc_Spawn(NpcKind eKind, int iTeam, const char[] sModel, const float vecPos[3], float fYaw, int iHealth) {
	int iSlot = -1;
	for (int i=0; i<MAX_NPCS; i++) {
		if (!g_eNpc[i].bUsed) { iSlot = i; break; }
	}
	if (iSlot == -1) return -1;
	int iEnt = CreateEntityByName("prop_dynamic_override");
	if (iEnt == -1) return -1;
	char sName[32];
	FormatEx(sName, sizeof(sName), "css_rts_npc_%d", iSlot);
	DispatchKeyValue(iEnt, "targetname", sName);
	DispatchKeyValue(iEnt, "model", sModel);
	DispatchKeyValue(iEnt, "solid", "2");           // SOLID_BBOX: bullets hit, players bump
	DispatchKeyValue(iEnt, "DefaultAnim", "idle_subtle");
	DispatchKeyValue(iEnt, "disableshadows", "0");
	float vecAng[3];
	vecAng[1] = fYaw;
	DispatchKeyValueVector(iEnt, "origin", vecPos);
	DispatchKeyValueVector(iEnt, "angles", vecAng);
	if (!DispatchSpawn(iEnt)) return -1;
	float vecMins[3], vecMaxs[3];
	vecMins[0] = vecMins[1] = -NPC_HULL_RADIUS;
	vecMaxs[0] = vecMaxs[1] = NPC_HULL_RADIUS;
	vecMaxs[2] = NPC_HULL_HEIGHT;
	SetEntPropVector(iEnt, Prop_Send, "m_vecMins", vecMins);
	SetEntPropVector(iEnt, Prop_Send, "m_vecMaxs", vecMaxs);
	SetEntProp(iEnt, Prop_Send, "m_nSolidType", 2);
	SetEntProp(iEnt, Prop_Data, "m_takedamage", 2);
	SetEntProp(iEnt, Prop_Data, "m_iHealth", iHealth);
	SetEntProp(iEnt, Prop_Data, "m_iMaxHealth", iHealth);
	SDKHook(iEnt, SDKHook_OnTakeDamage, SDKHookCB_NpcTakeDamage);

	Npc e;
	e.bUsed = true;
	e.iRef = EntIndexToEntRef(iEnt);
	e.iTeam = iTeam;
	e.eKind = eKind;
	e.eState = NS_Idle;
	e.iHealth = e.iMaxHealth = iHealth;
	e.hPath = new ArrayList(3);
	e.fSpeed = 80.0;
	e.iSeat = -1;
	e.vecLastPos = vecPos;
	g_eNpc[iSlot] = e;
	Npc_SetAnim(iSlot, "idle_subtle");
	return iSlot;
}

void Npc_SetAnim(int i, const char[] sAnim, float fRate=1.0) {
	int iEnt = Npc_GetEntity(i);
	if (iEnt == -1) return;
	if (!StrEqual(g_eNpc[i].sAnim, sAnim)) {
		strcopy(g_eNpc[i].sAnim, sizeof(Npc::sAnim), sAnim);
		SetVariantString(sAnim);
		AcceptEntityInput(iEnt, "SetAnimation");
		SetVariantString(sAnim);
		AcceptEntityInput(iEnt, "SetDefaultAnimation");
		Npc_ForceSequence(iEnt);
	}
	SetEntPropFloat(iEnt, Prop_Send, "m_flPlaybackRate", fRate);
}

// v0.5.3: prop_dynamic routes SetAnimation through the model's transition graph and only switches
// when the current loop ends -- idle_subtle is long, so workers used to glide for seconds before
// walk/run kicked in. Snap straight to the goal sequence instead.
void Npc_ForceSequence(int iEnt) {
	static int s_iHas = -1;
	if (s_iHas == -1) s_iHas = HasEntProp(iEnt, Prop_Data, "m_iGoalSequence") ? 1 : 0;
	if (!s_iHas) return;
	int iGoal = GetEntProp(iEnt, Prop_Data, "m_iGoalSequence");
	if (iGoal <= 0 || GetEntProp(iEnt, Prop_Send, "m_nSequence") == iGoal) return;
	SetEntProp(iEnt, Prop_Send, "m_nSequence", iGoal);
	SetEntPropFloat(iEnt, Prop_Send, "m_flCycle", 0.0);
	if (HasEntProp(iEnt, Prop_Data, "m_bSequenceLoops")) SetEntProp(iEnt, Prop_Data, "m_bSequenceLoops", 1);
	if (HasEntProp(iEnt, Prop_Data, "m_bSequenceFinished")) SetEntProp(iEnt, Prop_Data, "m_bSequenceFinished", 0);
}

// Order a move along the nav graph. fSpeed ~80 walk / ~190 run.
bool Npc_MoveTo(int i, const float vecGoal[3], float fSpeed, NpcState eState, bool bHasYaw=false, float fYaw=0.0) {
	int iEnt = Npc_GetEntity(i);
	if (iEnt == -1 || g_eNpc[i].eState == NS_Dead) return false;
	float vecPos[3];
	GetEntPropVector(iEnt, Prop_Data, "m_vecAbsOrigin", vecPos);
	if (!Nav_BuildPath(vecPos, vecGoal, g_eNpc[i].hPath)) return false;
	g_eNpc[i].iPathIdx = 0;
	g_eNpc[i].fSpeed = fSpeed;
	g_eNpc[i].eState = eState;
	g_eNpc[i].bHasGoalYaw = bHasYaw;
	g_eNpc[i].fGoalYaw = fYaw;
	g_eNpc[i].fStuckTime = 0.0;
	g_eNpc[i].vecLastPos = vecPos;
	Npc_SetAnim(i, fSpeed > 120.0 ? "run_all" : "walk_all", fSpeed > 120.0 ? fSpeed / 190.0 : fSpeed / 75.0);
	return true;
}

bool Npc_IsMoving(int i) {
	return g_eNpc[i].bUsed && (g_eNpc[i].eState == NS_Walking || g_eNpc[i].eState == NS_Fleeing) && g_eNpc[i].iPathIdx < g_eNpc[i].hPath.Length;
}

public bool TraceFilter_NpcGround(int iEntity, int iMask) {
	return iEntity == 0 || (iEntity > MaxClients && Npc_FromEntity(iEntity) == -1 && GetTerminalTeam(iEntity) == 0);
}

int GetTerminalTeam(int iEnt) {
	for (int t=CS_TEAM_T; t<=CS_TEAM_CT; t++) if (iEnt == GetTerminal(t)) return t;
	return 0;
}

void Npc_GameFrame() {
	float fNow = GetGameTime();
	float dt = g_fNpcLastFrame > 0.0 ? fNow - g_fNpcLastFrame : 0.0;
	g_fNpcLastFrame = fNow;
	if (dt <= 0.0 || dt > 0.25) return;
	for (int i=0; i<MAX_NPCS; i++) {
		if (!Npc_IsMoving(i)) continue;
		int iEnt = Npc_GetEntity(i);
		if (iEnt == -1) { g_eNpc[i].bUsed = false; continue; }
		float vecPos[3], vecTarget[3];
		GetEntPropVector(iEnt, Prop_Data, "m_vecAbsOrigin", vecPos);
		g_eNpc[i].hPath.GetArray(g_eNpc[i].iPathIdx, vecTarget, 3);
		float dx = vecTarget[0] - vecPos[0], dy = vecTarget[1] - vecPos[1];
		float fDist = SquareRoot(dx*dx + dy*dy);
		float fStep = g_eNpc[i].fSpeed * dt;
		float vecOld[3];
		vecOld = vecPos;
		if (fDist <= fStep + 1.0) {
			vecPos[0] = vecTarget[0]; vecPos[1] = vecTarget[1];
			g_eNpc[i].iPathIdx++;
		} else {
			vecPos[0] += dx / fDist * fStep;
			vecPos[1] += dy / fDist * fStep;
		}
		// Stay on the nav floor. A ledge or invisible lip along a wall is not a path.
		if (!Nav_Snap(vecPos)) {
			vecPos = vecOld;
			g_eNpc[i].iPathIdx = g_eNpc[i].iPathIdx > 0 && fDist <= fStep + 1.0 ? g_eNpc[i].iPathIdx - 1 : g_eNpc[i].iPathIdx;
		}
		float vecAng[3];
		if (fDist > 0.5) vecAng[1] = RadToDeg(ArcTangent2(dy, dx));
		else GetEntPropVector(iEnt, Prop_Data, "m_angAbsRotation", vecAng);
		bool bArrived = g_eNpc[i].iPathIdx >= g_eNpc[i].hPath.Length;
		if (bArrived && g_eNpc[i].bHasGoalYaw) vecAng[1] = g_eNpc[i].fGoalYaw;
		TeleportEntity(iEnt, vecPos, vecAng, NULL_VECTOR);
		// stuck: < 16u in 2 s -> hop to the next path point
		g_eNpc[i].fStuckTime += dt;
		if (g_eNpc[i].fStuckTime >= 2.0) {
			bool bStuck = GetVectorDistance(vecPos, g_eNpc[i].vecLastPos) < 16.0 && !bArrived && g_eNpc[i].hPath.Length > 0;
			g_eNpc[i].fStuckTime = 0.0;
			g_eNpc[i].vecLastPos = vecPos;
			if (bStuck) {
				float vecGoal[3];
				g_eNpc[i].hPath.GetArray(g_eNpc[i].hPath.Length - 1, vecGoal, 3);
				Npc_MoveTo(i, vecGoal, g_eNpc[i].fSpeed, g_eNpc[i].eState, g_eNpc[i].bHasGoalYaw, g_eNpc[i].fGoalYaw);
				continue;
			}
		}
		if (bArrived) Npc_OnArrive(i);
	}
}

void Npc_OnArrive(int i) {
	switch (g_eNpc[i].eKind) {
		case Npc_Worker: Worker_OnArrive(i);
		default: { g_eNpc[i].eState = NS_Idle; Npc_SetAnim(i, "idle_subtle"); }
	}
}

int g_iProofWorker = -1;
bool g_bProofHurting;
public Action SDKHookCB_NpcTakeDamage(int iVictim, int &iAttacker, int &iInflictor, float &fDamage, int &iDamageType) {
	int i = Npc_FromEntity(iVictim);
	if (g_bNpcDebug) PrintToServer("[RTS] npc dmg ent %d slot %d att %d dmg %.1f", iVictim, i, iAttacker, fDamage);
	if (i == -1 || g_eNpc[i].eState == NS_Dead) return Plugin_Handled;
	if (i == g_iProofWorker && !g_bProofHurting) return Plugin_Handled;   // proof worker: only the scripted hurt lands
	// no friendly fire on NPCs
	if (1 <= iAttacker <= MaxClients && IsClientInGame(iAttacker) && GetClientTeam(iAttacker) == g_eNpc[i].iTeam && !g_bSelfTestRunning) return Plugin_Handled;
	int iDmg = RoundToCeil(fDamage);
	if (iDmg < 1) iDmg = 1;
	g_eNpc[i].iHealth -= iDmg;
	g_eNpc[i].fLastHurt = GetGameTime();
	SetEntProp(iVictim, Prop_Data, "m_iHealth", g_eNpc[i].iHealth > 0 ? g_eNpc[i].iHealth : 0);
	if (g_eNpc[i].iHealth <= 0) {
		Npc_Kill(i, iAttacker);
	} else if (g_eNpc[i].eKind == Npc_Worker) {
		Worker_OnHurt(i, iAttacker);
	}
	return Plugin_Handled; // never let prop_dynamic break/gib itself
}

void Npc_Kill(int i, int iAttacker) {
	g_eNpc[i].eState = NS_Dead;
	g_eNpc[i].hPath.Clear();
	if (g_eNpc[i].eKind == Npc_Worker) Worker_OnKilled(i, iAttacker);
	int iEnt = Npc_GetEntity(i);
	if (iEnt != -1) {
		SDKUnhook(iEnt, SDKHook_OnTakeDamage, SDKHookCB_NpcTakeDamage);
		AcceptEntityInput(iEnt, "BecomeRagdoll"); // client-side ragdoll, removes the entity
		CreateTimer(0.2, Timer_NpcRemoveIfAlive, EntIndexToEntRef(iEnt), TIMER_FLAG_NO_MAPCHANGE);
	}
	delete g_eNpc[i].hPath;
	Npc eEmpty;
	g_eNpc[i] = eEmpty;
}

public Action Timer_NpcRemoveIfAlive(Handle hTimer, int iRef) {
	int iEnt = EntRefToEntIndex(iRef);
	if (iEnt > 0 && IsValidEntity(iEnt)) RemoveEntity(iEnt); // BecomeRagdoll unsupported -> just remove
	return Plugin_Stop;
}

void Npc_RemoveAll() {
	for (int i=0; i<MAX_NPCS; i++) {
		int iEnt = Npc_GetEntity(i);
		if (iEnt != -1) RemoveEntity(iEnt);
		delete g_eNpc[i].hPath;
		Npc eEmpty;
		g_eNpc[i] = eEmpty;
	}
	// leftovers from a previous plugin instance
	int iEnt = -1;
	char sName[64];
	while ((iEnt = FindEntityByClassname(iEnt, "prop_dynamic")) != -1) {
		GetEntPropString(iEnt, Prop_Data, "m_iName", sName, sizeof(sName));
		if (StrContains(sName, "css_rts_npc_") == 0) RemoveEntity(iEnt);
	}
}
