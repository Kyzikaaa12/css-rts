// css_rts/wcmds.sp -- commands for workers + unlocks (v0.4)

void WCmds_Init() {
	RegConsoleCmd("sm_rts_unlocks", cmdUnlocks, "List your team's Commander unlocks");
	RegConsoleCmd("sm_rts_hire", cmdHire, "Commander: hire a worker (costs Intel)");
	RegConsoleCmd("sm_rts_debug_workers", cmdDebugWorkers, "List worker NPCs, seats and flee points");
	RegConsoleCmd("sm_rts_debug_buyworker", cmdDebugBuyWorker, "Spawn a worker for <t|ct> (free, counts as owned)");
	RegConsoleCmd("sm_rts_debug_workerorder", cmdDebugWorkerOrder, "Order NPC slot <n> to <x> <y> <z>");
	RegConsoleCmd("sm_rts_debug_workerflee", cmdDebugWorkerFlee, "Make NPC slot <n> flee");
	RegConsoleCmd("sm_rts_debug_npchurt", cmdDebugNpcHurt, "Damage NPC slot <n> by <dmg> [attacker #userid|name]");
	RegConsoleCmd("sm_rts_debug_unlock", cmdDebugUnlock, "<t|ct> <key|all|reset>: grant unlocks for free (or reset)");
	RegConsoleCmd("sm_rts_debug_ghostspot", cmdDebugGhostSpot, "<t|ct> <x> <y> <z>: worker placement validity");
	RegConsoleCmd("sm_rts_debug_buycheck", cmdDebugBuyCheck, "<#userid|name> <item>: would this buy be blocked?");
	RegConsoleCmd("sm_rts_debug_workerreturn", cmdDebugWorkerReturn, "Send NPC slot <n> back to its desk (or the nearest free one)");
	RegConsoleCmd("sm_rts_debug_npcanim", cmdDebugNpcAnim, "Show NPC slot <n> animation: name, sequence, cycle, rate, speed, state");
	RegConsoleCmd("sm_rts_debug_deskcam", cmdDebugDeskCam, "<desk_id> [#userid|name] [dist] [height]: look at a desk (commander view: camera; otherwise teleport the player)");
}

int ArgTeam(int iArg) {
	char s[8];
	GetCmdArg(iArg, s, sizeof(s));
	return TeamFromName(s);
}

public Action cmdUnlocks(int iClient, int iArgs) {
	iClient = ResolveClient(iClient);
	int t = iClient ? GetClientTeam(iClient) : ArgTeam(1);
	if (!(CS_TEAM_T <= t <= CS_TEAM_CT)) { ReplyToCommand(iClient, "[RTS] Join a team first (server: sm_rts_unlocks t|ct)"); return Plugin_Handled; }
	ReplyToCommand(iClient, "[RTS] Unlocks for %s (economy %s), Intel %d:", t == CS_TEAM_CT ? "CT" : "T", g_hCvarUnlocks.BoolValue ? "on" : "off", g_iIntel[t]);
	for (int u=0; u<g_iUnlocks; u++) {
		ReplyToCommand(iClient, "  %-9s %-6s %4d  %s  [%s]", g_eUnlock[u].sKey, g_bUnlocked[t][u] ? "OWNED" : "locked", Unlock_Cost(u), g_eUnlock[u].sName, g_eUnlock[u].sItems);
	}
	return Plugin_Handled;
}

public Action cmdHire(int iClient, int iArgs) {
	iClient = ResolveClient(iClient);
	if (!iClient || !GetCommanderTeam(iClient)) { ReplyToCommand(iClient, "[RTS] Commanders only"); return Plugin_Handled; }
	Worker_Buy(iClient);
	return Plugin_Handled;
}

public Action cmdDebugWorkers(int iClient, int iArgs) {
	iClient = ResolveClient(iClient);
	if (!HasRTSAccess(iClient)) return Plugin_Handled;
	ReplyToCommand(iClient, "[RTS] workers T=%d/%d owned (seated %d)  CT=%d/%d owned (seated %d)  nav=%d areas",
		Npc_Count(Npc_Worker, CS_TEAM_T), g_iWorkersOwned[CS_TEAM_T], CountSeatedWorkers(CS_TEAM_T),
		Npc_Count(Npc_Worker, CS_TEAM_CT), g_iWorkersOwned[CS_TEAM_CT], CountSeatedWorkers(CS_TEAM_CT), g_iNavAreas);
	for (int i=0; i<MAX_NPCS; i++) {
		if (!g_eNpc[i].bUsed) continue;
		int iEnt = Npc_GetEntity(i);
		float v[3];
		if (iEnt != -1) GetOrigin(iEnt, v);
		ReplyToCommand(iClient, "  slot %d ent %d team %d state %d hp %d seat %d path %d pos %.0f %.0f %.0f", i, iEnt, g_eNpc[i].iTeam,
			g_eNpc[i].eState, g_eNpc[i].iHealth, g_eNpc[i].iSeat, g_eNpc[i].hPath ? g_eNpc[i].hPath.Length : -1, v[0], v[1], v[2]);
	}
	for (int s=0; s<g_iSeats; s++) ReplyToCommand(iClient, "  seat %d team %d owner %d at %.0f %.0f %.0f yaw %.0f", s, g_iSeatTeam[s], g_iSeatOwner[s], g_vecSeat[s][0], g_vecSeat[s][1], g_vecSeat[s][2], g_fSeatYaw[s]);
	for (int f=0; f<g_iFlee; f++) ReplyToCommand(iClient, "  flee %d team %d at %.0f %.0f %.0f", f, g_iFleeTeam[f], g_vecFlee[f][0], g_vecFlee[f][1], g_vecFlee[f][2]);
	return Plugin_Handled;
}

public Action cmdDebugBuyWorker(int iClient, int iArgs) {
	iClient = ResolveClient(iClient);
	if (!HasRTSAccess(iClient)) return Plugin_Handled;
	int t = ArgTeam(1);
	if (!t) { ReplyToCommand(iClient, "[RTS] usage: sm_rts_debug_buyworker <t|ct> [desk_id] [near]"); return Plugin_Handled; }
	int iSeat = -1;
	if (iArgs >= 2) {
		char sId[16]; GetCmdArg(2, sId, sizeof(sId));
		int d = Desks_FindId(sId);
		if (d == -1 || !g_bDeskOk[d] || g_iDeskSeat[d] == -1) { ReplyToCommand(iClient, "[RTS] no placed desk '%s' (see sm_rts_debug_desks)", sId); return Plugin_Handled; }
		iSeat = g_iDeskSeat[d];
		if (g_iSeatOwner[iSeat] != -1) { ReplyToCommand(iClient, "[RTS] desk %s is taken by slot %d", sId, g_iSeatOwner[iSeat]); return Plugin_Handled; }
	}
	char sNear[8]; GetCmdArg(3, sNear, sizeof(sNear));
	int i = Worker_DebugSpawn(t, iSeat, StrEqual(sNear, "near"));
	ReplyToCommand(iClient, "[RTS] spawned worker slot %d for team %d (seat %d) path %d", i, t, i != -1 ? g_eNpc[i].iSeat : -1, i != -1 ? g_eNpc[i].hPath.Length : -1);
	return Plugin_Handled;
}

// free worker; iSeat -1 = nearest free desk; bNear = start ~8 nav nodes before the desk instead of at the post
int Worker_DebugSpawn(int t, int iSeat, bool bNear) {
	g_iWorkersOwned[t]++;
	int i = Worker_Spawn(t, iSeat == -1);
	if (i != -1 && iSeat != -1) {
		Worker_GoToSeat(i, iSeat);
		int n = g_eNpc[i].hPath.Length;
		if (bNear && n > 0) {
			// start a short walk away instead of at the post (keeps proof recordings short)
			float v[3];
			int k = n > 8 ? n - 8 : 0;
			g_eNpc[i].hPath.GetArray(k, v);
			TeleportEntity(Npc_GetEntity(i), v, NULL_VECTOR, NULL_VECTOR);
			g_eNpc[i].iPathIdx = k;
			g_eNpc[i].vecLastPos = v;
			Npc_MoveTo(i, g_vecSeat[iSeat], 80.0, NS_Walking, true, g_fSeatYaw[iSeat]);
		}
	}
	return i;
}

bool ArgNpc(int iClient, int &i) {
	i = GetCmdArgInt(1);
	if (i < 0 || i >= MAX_NPCS || !g_eNpc[i].bUsed || Npc_GetEntity(i) == -1) { ReplyToCommand(iClient, "[RTS] no NPC in slot %d", i); return false; }
	return true;
}

public Action cmdDebugWorkerOrder(int iClient, int iArgs) {
	iClient = ResolveClient(iClient);
	int i;
	if (!HasRTSAccess(iClient) || iArgs < 4 || !ArgNpc(iClient, i)) return Plugin_Handled;
	float v[3];
	v[0] = GetCmdArgFloat(2); v[1] = GetCmdArgFloat(3); v[2] = GetCmdArgFloat(4);
	Worker_Order(i, v);
	ReplyToCommand(iClient, "[RTS] slot %d ordered; state %d seat %d path %d", i, g_eNpc[i].eState, g_eNpc[i].iSeat, g_eNpc[i].hPath ? g_eNpc[i].hPath.Length : -1);
	return Plugin_Handled;
}

public Action cmdDebugWorkerFlee(int iClient, int iArgs) {
	iClient = ResolveClient(iClient);
	int i;
	if (!HasRTSAccess(iClient) || !ArgNpc(iClient, i)) return Plugin_Handled;
	Worker_Flee(i);
	ReplyToCommand(iClient, "[RTS] slot %d fleeing; state %d", i, g_eNpc[i].eState);
	return Plugin_Handled;
}

public Action cmdDebugNpcHurt(int iClient, int iArgs) {
	iClient = ResolveClient(iClient);
	int i;
	if (!HasRTSAccess(iClient) || iArgs < 2 || !ArgNpc(iClient, i)) return Plugin_Handled;
	int iAttacker = 0;
	if (iArgs >= 3) {
		char s[64]; GetCmdArg(3, s, sizeof(s));
		iAttacker = FindTarget(iClient, s, false, false);
		if (iAttacker < 0) iAttacker = 0;
	}
	SDKHooks_TakeDamage(Npc_GetEntity(i), iAttacker, iAttacker, GetCmdArgFloat(2), DMG_BULLET, -1, NULL_VECTOR, NULL_VECTOR, false);
	ReplyToCommand(iClient, "[RTS] slot %d hp %d state %d", i, g_eNpc[i].iHealth, g_eNpc[i].eState);
	return Plugin_Handled;
}

public Action cmdDebugUnlock(int iClient, int iArgs) {
	iClient = ResolveClient(iClient);
	if (!HasRTSAccess(iClient)) return Plugin_Handled;
	int t = ArgTeam(1);
	char sKey[16]; GetCmdArg(2, sKey, sizeof(sKey));
	if (!t || !sKey[0]) { ReplyToCommand(iClient, "[RTS] usage: sm_rts_debug_unlock <t|ct> <key|all|reset>"); return Plugin_Handled; }
	if (StrEqual(sKey, "reset")) { for (int u=0; u<MAX_UNLOCKS; u++) g_bUnlocked[t][u] = false; }
	else if (StrEqual(sKey, "all")) { for (int u=0; u<g_iUnlocks; u++) g_bUnlocked[t][u] = true; }
	else {
		int u = Unlock_FindKey(sKey);
		bool bOk = Unlock_Buy(0, t, u, iArgs >= 3 && GetCmdArgInt(3) == 1 ? false : true);
		ReplyToCommand(iClient, "[RTS] unlock %s for team %d: %s", sKey, t, bOk ? "ok" : "failed");
	}
	ReplyToCommand(iClient, "[RTS] team %d has %d/%d unlocks, Intel %d", t, Unlocks_Count(t), g_iUnlocks, g_iIntel[t]);
	return Plugin_Handled;
}

public Action cmdDebugBuyCheck(int iClient, int iArgs) {
	iClient = ResolveClient(iClient);
	if (!HasRTSAccess(iClient) || iArgs < 2) return Plugin_Handled;
	char s[64], sItem[32];
	GetCmdArg(1, s, sizeof(s)); GetCmdArg(2, sItem, sizeof(sItem));
	int iTarget = FindTarget(iClient, s, false, false);
	if (iTarget <= 0) return Plugin_Handled;
	bool bBlocked = Unlocks_BlockBuy(iTarget, sItem);
	ReplyToCommand(iClient, "[RTS] buycheck %N %s: %s", iTarget, sItem, bBlocked ? "BLOCKED" : "allowed");
	return Plugin_Handled;
}

public Action cmdDebugGhostSpot(int iClient, int iArgs) {
	iClient = ResolveClient(iClient);
	if (!HasRTSAccess(iClient) || iArgs < 4) { ReplyToCommand(iClient, "[RTS] usage: sm_rts_debug_ghostspot <t|ct> <x> <y> <z>"); return Plugin_Handled; }
	int t = ArgTeam(1);
	float v[3], vecSnap[3], fYaw;
	v[0] = GetCmdArgFloat(2); v[1] = GetCmdArgFloat(3); v[2] = GetCmdArgFloat(4);
	int r = Ghost_WorkerSpot(t, v, vecSnap, fYaw);
	ReplyToCommand(iClient, "[RTS] ghostspot team %d at %.0f %.0f %.0f -> %s snap %.0f %.0f %.0f", t, v[0], v[1], v[2], r == 2 ? "SEAT" : (r == 1 ? "FLOOR" : "INVALID"), vecSnap[0], vecSnap[1], vecSnap[2]);
	return Plugin_Handled;
}

public Action cmdDebugWorkerReturn(int iClient, int iArgs) {
	iClient = ResolveClient(iClient);
	int i;
	if (!HasRTSAccess(iClient) || !ArgNpc(iClient, i)) return Plugin_Handled;
	int s = g_eNpc[i].iSeat;
	float v[3]; GetOrigin(Npc_GetEntity(i), v);
	if (s == -1) s = FindFreeSeat(g_eNpc[i].iTeam, v);
	if (s == -1) { ReplyToCommand(iClient, "[RTS] slot %d: no free desk", i); return Plugin_Handled; }
	g_eNpc[i].fLastHurt = 0.0;
	bool bOk = Worker_GoToSeat(i, s);
	ReplyToCommand(iClient, "[RTS] slot %d returning to seat %d: %s state %d path %d", i, s, bOk ? "ok" : "NO PATH", g_eNpc[i].eState, g_eNpc[i].hPath.Length);
	return Plugin_Handled;
}

public Action cmdDebugNpcAnim(int iClient, int iArgs) {
	iClient = ResolveClient(iClient);
	int i;
	if (!HasRTSAccess(iClient) || !ArgNpc(iClient, i)) return Plugin_Handled;
	int e = Npc_GetEntity(i);
	if (iArgs >= 2) { char sA[48]; GetCmdArg(2, sA, sizeof(sA)); g_eNpc[i].sAnim[0] = 0; Npc_SetAnim(i, sA); }
	float v[3]; GetOrigin(e, v);
	ReplyToCommand(iClient, "[RTS] pose %.2f %.2f %.2f %.2f %.2f %.2f %.2f %.2f %.2f", GetEntPropFloat(e, Prop_Send, "m_flPoseParameter", 0), GetEntPropFloat(e, Prop_Send, "m_flPoseParameter", 1),
		GetEntPropFloat(e, Prop_Send, "m_flPoseParameter", 2), GetEntPropFloat(e, Prop_Send, "m_flPoseParameter", 3), GetEntPropFloat(e, Prop_Send, "m_flPoseParameter", 4),
		GetEntPropFloat(e, Prop_Send, "m_flPoseParameter", 5), GetEntPropFloat(e, Prop_Send, "m_flPoseParameter", 6), GetEntPropFloat(e, Prop_Send, "m_flPoseParameter", 7), GetEntPropFloat(e, Prop_Send, "m_flPoseParameter", 8));
	ReplyToCommand(iClient, "[RTS] slot %d anim '%s' seq %d cycle %.2f rate %.2f speed %.0f state %d seat %d pos %.0f %.0f %.0f", i, g_eNpc[i].sAnim,
		GetEntProp(e, Prop_Send, "m_nSequence"), GetEntPropFloat(e, Prop_Send, "m_flCycle"), GetEntPropFloat(e, Prop_Send, "m_flPlaybackRate"),
		Npc_IsMoving(i) ? g_eNpc[i].fSpeed : 0.0, g_eNpc[i].eState, g_eNpc[i].iSeat, v[0], v[1], v[2]);
	return Plugin_Handled;
}

public Action cmdDebugDeskCam(int iClient, int iArgs) {
	iClient = ResolveClient(iClient);
	if (!HasRTSAccess(iClient) || iArgs < 1) { ReplyToCommand(iClient, "[RTS] usage: sm_rts_debug_deskcam <desk_id> [#userid|name] [dist=150] [height=80]"); return Plugin_Handled; }
	char sId[16]; GetCmdArg(1, sId, sizeof(sId));
	if (StrEqual(sId, "off")) {
		int iT = iClient;
		if (iArgs >= 2) { char s2[64]; GetCmdArg(2, s2, sizeof(s2)); iT = FindTarget(iClient, s2, false, false); }
		if (iT > 0 && IsPlayerAlive(iT)) SetEntityMoveType(iT, MOVETYPE_WALK);
		ReplyToCommand(iClient, "[RTS] deskcam off (noclip cleared)");
		return Plugin_Handled;
	}
	int d = Desks_FindId(sId);
	if (d == -1 || !g_bDeskOk[d]) { ReplyToCommand(iClient, "[RTS] no placed desk '%s'", sId); return Plugin_Handled; }
	int iTarget = iClient;
	if (iArgs >= 2) { char s[64]; GetCmdArg(2, s, sizeof(s)); iTarget = FindTarget(iClient, s, false, false); }
	if (iTarget <= 0) { ReplyToCommand(iClient, "[RTS] give a player: sm_rts_debug_deskcam %s <name>", sId); return Plugin_Handled; }
	float fDist = iArgs >= 3 ? GetCmdArgFloat(3) : 150.0;
	float fHeight = iArgs >= 4 ? GetCmdArgFloat(4) : 80.0;
	float vecDesk[3], vecFwd[3];
	vecDesk = g_vecDeskWall[d];
	vecFwd[0] = Cosine(DegToRad(g_fDeskYaw[d])); vecFwd[1] = Sine(DegToRad(g_fDeskYaw[d]));
	vecDesk[0] += vecFwd[0] * 20.0; vecDesk[1] += vecFwd[1] * 20.0; vecDesk[2] += 30.0;
	if (GetCommanderTeam(iTarget) && g_bBodyHidden[iTarget]) {
		Camera_GoTo(iTarget, vecDesk);
		ReplyToCommand(iClient, "[RTS] camera of %N moving to desk %s", iTarget, sId);
		return Plugin_Handled;
	}
	float vecEye[3];
	DeskCam_Place(iTarget, d, fDist, fHeight, vecEye);
	ReplyToCommand(iClient, "[RTS] %N at %.0f %.0f %.0f looking at desk %s (alive players are put in noclip)", iTarget, vecEye[0], vecEye[1], vecEye[2], sId);
	return Plugin_Handled;
}

// put a player (noclip) in the room, a bit off-axis, looking at desk d + chair; stays inside the world
void DeskCam_Place(int iTarget, int d, float fDist, float fHeight, float vecEye[3]) {
	float vecDesk[3], vecFwd[3], vecAng[3];
	vecDesk = g_vecDeskWall[d];
	vecFwd[0] = Cosine(DegToRad(g_fDeskYaw[d])); vecFwd[1] = Sine(DegToRad(g_fDeskYaw[d]));
	vecDesk[0] += vecFwd[0] * 20.0; vecDesk[1] += vecFwd[1] * 20.0; vecDesk[2] += 30.0;
	float fYaw = g_fDeskYaw[d] + 20.0;
	float vecDir[3];
	vecDir[0] = Cosine(DegToRad(fYaw)); vecDir[1] = Sine(DegToRad(fYaw));
	float vecFrom[3]; vecFrom = vecDesk;
	vecEye[0] = vecDesk[0] + vecDir[0] * fDist; vecEye[1] = vecDesk[1] + vecDir[1] * fDist; vecEye[2] = g_vecDeskWall[d][2] + fHeight;
	vecFrom[2] = vecEye[2];
	TR_TraceHullFilter(vecFrom, vecEye, view_as<float>({-16.0, -16.0, 0.0}), view_as<float>({16.0, 16.0, 8.0}), MASK_PLAYERSOLID, TraceFilter_CamWorld);
	TR_GetEndPosition(vecEye);
	float vecLook[3];
	SubtractVectors(vecDesk, vecEye, vecLook);
	GetVectorAngles(vecLook, vecAng);
	float vecFeet[3]; vecFeet = vecEye; vecFeet[2] -= 64.0;
	if (IsPlayerAlive(iTarget)) SetEntityMoveType(iTarget, MOVETYPE_NOCLIP);
	TeleportEntity(iTarget, IsPlayerAlive(iTarget) ? vecFeet : vecEye, vecAng, ZERO_VECTOR);
}
