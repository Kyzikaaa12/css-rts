// css_rts/proof.sp -- v0.5.4: one-command worker proof recording (sm_rts_debug_proof [desk_id] [player]).
// Force-starts the match if needed, makes the player a soldier in noclip looking at the desk, spawns a worker a
// few nav nodes away, waits until it sits, threatens it (flee to Safety, cower), sends it back, and announces every
// phase + animation change in chat (wall clock + seconds since start). A follow camera tracks the worker while it moves.

enum ProofPhase {
	PP_Off = 0,
	PP_Live,        // wait for a live match
	PP_Soldier,     // leave the commander role, wait for a body
	PP_Desk,        // camera at the desk
	PP_Walk,        // worker walking in
	PP_Seated,      // seated, hold
	PP_Flee,        // running to Safety (follow cam)
	PP_Safety,      // cowering, hold
	PP_Return,      // jogging back (follow cam)
	PP_Reseated     // seated again, hold, then done
};

ProofPhase g_ePP;
int g_iPPClient, g_iPPDesk, g_iPPSlot = -1, g_iPPTeam;
float g_fPPStart, g_fPPPhase, g_fPPWalk, g_fPPFlee, g_fPPRet, g_fPPSitLoop;
char g_sPPAnim[48];
float g_vecPPCam[3];
Handle g_hPPTimer;
char g_sPPDeskArg[16];
bool g_bPPLeaving;

void Proof_Init() {
	RegConsoleCmd("sm_rts_debug_proof", cmdProof, "[desk_id|stop] [#userid|name]: scripted worker proof (walk in, sit, flee to Safety, return) with chat timestamps");
}

void Proof_Say(const char[] sFmt, any ...) {
	char sMsg[192], sTime[16];
	VFormat(sMsg, sizeof(sMsg), sFmt, 2);
	FormatTime(sTime, sizeof(sTime), "%H:%M:%S");
	float t = GetGameTime() - g_fPPStart;
	PrintToChatAll("\x04[RTS proof %s t+%.1fs]\x01 %s", sTime, t, sMsg);
	PrintToServer("[RTS proof %s t+%.1fs] %s", sTime, t, sMsg);
	LogMessage("[RTS proof t+%.1fs] %s", t, sMsg);
}

void Proof_Stop(const char[] sWhy) {
	if (g_ePP == PP_Off) return;
	Proof_Say("%s", sWhy);
	g_ePP = PP_Off;
	g_iProofWorker = -1;
	if (g_iPPClient > 0 && IsClientInGame(g_iPPClient) && IsPlayerAlive(g_iPPClient)) SetEntityMoveType(g_iPPClient, MOVETYPE_WALK);
	delete g_hPPTimer;
}

void Proof_SetPhase(ProofPhase e) { g_ePP = e; g_fPPPhase = GetGameTime(); }

int Proof_PickDesk(int t, const char[] sWant) {
	if (sWant[0]) {
		int d = Desks_FindId(sWant);
		if (d != -1 && g_bDeskOk[d] && g_iDeskSeat[d] != -1 && g_iSeatOwner[g_iDeskSeat[d]] == -1) return d;
		return -1;
	}
	char sId[16]; FormatEx(sId, sizeof(sId), "%s_b1", t == CS_TEAM_T ? "t" : "ct");
	int d = Desks_FindId(sId);
	if (d != -1 && g_bDeskOk[d] && g_iDeskSeat[d] != -1 && g_iSeatOwner[g_iDeskSeat[d]] == -1) return d;
	for (d=0; d<g_iDesks; d++) if (g_iDeskTeam[d] == t && g_bDeskOk[d] && g_iDeskSeat[d] != -1 && g_iSeatOwner[g_iDeskSeat[d]] == -1) return d;
	return -1;
}

public Action cmdProof(int iClient, int iArgs) {
	iClient = ResolveClient(iClient);
	if (!HasRTSAccess(iClient)) return Plugin_Handled;
	char sDesk[16]; GetCmdArg(1, sDesk, sizeof(sDesk));
	if (StrEqual(sDesk, "stop")) { Proof_Stop("stopped"); return Plugin_Handled; }
	int c = iClient;
	if (iArgs >= 2) { char s[64]; GetCmdArg(2, s, sizeof(s)); c = FindTarget(iClient, s, false, false); }
	if (c <= 0) { ReplyToCommand(iClient, "[RTS] proof needs a player (sm_rts_debug_proof [desk] <name>)"); return Plugin_Handled; }
	if (g_ePP != PP_Off) Proof_Stop("restarted");
	g_iPPClient = c;
	g_iPPDesk = -1;
	g_iPPSlot = -1;
	g_bPPLeaving = false;
	strcopy(g_sPPAnim, sizeof(g_sPPAnim), "");
	if (sDesk[0] && Desks_FindId(sDesk) == -1) { ReplyToCommand(iClient, "[RTS] no desk '%s' (sm_rts_debug_desks)", sDesk); return Plugin_Handled; }
	g_fPPStart = GetGameTime();
	g_ePP = PP_Live;
	g_fPPPhase = GetGameTime();
	g_fPPWalk = g_fPPFlee = g_fPPRet = g_fPPSitLoop = 0.0;
	strcopy(g_sPPDeskArg, sizeof(g_sPPDeskArg), sDesk);
	Proof_Say("start: player %N, desk %s", c, sDesk[0] ? sDesk : "(auto: <team>_b1 or first free)");
	if (g_eGame != GS_Live && InLobby()) { LogMessage("[RTS] state: forcestart by proof"); Lobby_BeginMatch(); Proof_Say("match force-started"); }
	delete g_hPPTimer;
	g_hPPTimer = CreateTimer(0.1, Timer_Proof, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	return Plugin_Handled;
}

void Proof_TrackAnim() {
	if (g_iPPSlot == -1 || !g_eNpc[g_iPPSlot].bUsed) return;
	if (!StrEqual(g_eNpc[g_iPPSlot].sAnim, g_sPPAnim)) {
		strcopy(g_sPPAnim, sizeof(g_sPPAnim), g_eNpc[g_iPPSlot].sAnim);
		Proof_Say("worker anim: %s", g_sPPAnim);
		if (IsClientInGame(g_iPPClient)) PrintHintText(g_iPPClient, "worker anim: %s", g_sPPAnim);
	}
}

// noclip follow camera: keeps its side of the worker, ~170 u away, 70 u up, smoothed; never inside walls
void Proof_FollowCam(bool bSnap) {
	int c = g_iPPClient, e = Npc_GetEntity(g_iPPSlot);
	if (e == -1 || !IsPlayerAlive(c)) return;
	float vecW[3], vecHead[3], vecDir[3], vecWant[3], vecAng[3], vecLook[3];
	GetOrigin(e, vecW);
	vecHead = vecW; vecHead[2] += 60.0;
	SubtractVectors(g_vecPPCam, vecW, vecDir);
	vecDir[2] = 0.0;
	if (GetVectorLength(vecDir) < 1.0) { vecDir[0] = 1.0; vecDir[1] = 0.0; }
	NormalizeVector(vecDir, vecDir);
	vecWant[0] = vecW[0] + vecDir[0] * 170.0; vecWant[1] = vecW[1] + vecDir[1] * 170.0; vecWant[2] = vecW[2] + 110.0;
	TR_TraceHullFilter(vecHead, vecWant, view_as<float>({-12.0, -12.0, -12.0}), view_as<float>({12.0, 12.0, 12.0}), MASK_PLAYERSOLID_BRUSHONLY, TraceFilter_CamWorld);
	TR_GetEndPosition(vecWant);
	if (bSnap) g_vecPPCam = vecWant;
	else for (int k=0; k<3; k++) g_vecPPCam[k] += (vecWant[k] - g_vecPPCam[k]) * 0.25;
	float vecTarget[3]; vecTarget = vecW; vecTarget[2] += 40.0;
	SubtractVectors(vecTarget, g_vecPPCam, vecLook);
	GetVectorAngles(vecLook, vecAng);
	float vecFeet[3]; vecFeet = g_vecPPCam; vecFeet[2] -= 64.0;
	SetEntityMoveType(c, MOVETYPE_NOCLIP);
	TeleportEntity(c, vecFeet, vecAng, ZERO_VECTOR);
}

bool Proof_SitLoop() {
	return g_eNpc[g_iPPSlot].eState == NS_Seated && !StrEqual(g_eNpc[g_iPPSlot].sAnim, "Idle_to_Sit_Chair", false);
}

public Action Timer_Proof(Handle h) {
	int c = g_iPPClient;
	if (g_ePP == PP_Off) { g_hPPTimer = null; return Plugin_Stop; }
	if (c <= 0 || !IsClientInGame(c)) { g_hPPTimer = null; g_ePP = PP_Off; Proof_Say("aborted: player left"); return Plugin_Stop; }
	float fNow = GetGameTime(), fIn = fNow - g_fPPPhase;
	if (g_ePP >= PP_Walk) {
		if (g_iPPSlot == -1 || !g_eNpc[g_iPPSlot].bUsed || Npc_GetEntity(g_iPPSlot) == -1 || g_eNpc[g_iPPSlot].eState == NS_Dead) { g_hPPTimer = null; Proof_Stop("aborted: worker gone"); return Plugin_Stop; }
		Proof_TrackAnim();
	}
	switch (g_ePP) {
		case PP_Live: {
			if (g_eGame == GS_Live && fIn > 1.5) { Proof_Say("match live"); Proof_SetPhase(PP_Soldier); }
			else if (fIn > 45.0) { g_hPPTimer = null; Proof_Stop("aborted: match did not go live (lobby countdown?)"); return Plugin_Stop; }
		}
		case PP_Soldier: {
			g_bWantsCommander[c] = false;
			g_bDeclinedCmdr[c] = true;
			if (GetCommanderTeam(c) && !g_bPPLeaving) {
				g_bPPLeaving = true;
				CancelPending(c);
				ReleaseCommander(c, false);
				Proof_Say("leaving the Commander role (soldier)");
			}
			if (!IsPlayerAlive(c)) {
				// Leaving the bodyless Commander parks the player under the map. The match restart
				// kills that body, and CS:S does not give another one until something respawns it.
				static float fNextRespawn;
				if (fNow >= fNextRespawn && GetClientTeam(c) >= CS_TEAM_T) {
					fNextRespawn = fNow + 1.0;
					CS_RespawnPlayer(c);
					Proof_Say("respawning soldier body");
				}
			}
			if (!GetCommanderTeam(c) && IsPlayerAlive(c) && fIn > 0.5) {
				g_bPPLeaving = false;
				g_iPPTeam = GetClientTeam(c);
				if (g_iPPTeam < CS_TEAM_T) g_iPPTeam = CS_TEAM_CT;
				g_iPPDesk = Proof_PickDesk(g_iPPTeam, g_sPPDeskArg);
				if (g_iPPDesk == -1) { g_hPPTimer = null; Proof_Stop("aborted: desk missing or taken (try another id from sm_rts_debug_desks)"); return Plugin_Stop; }
				g_iPPTeam = g_iDeskTeam[g_iPPDesk];
				float vecEye[3];
				DeskCam_Place(c, g_iPPDesk, 150.0, 80.0, vecEye);
				g_vecPPCam = vecEye;
				Proof_Say("soldier + noclip camera at desk %s (team %s)", g_sDeskId[g_iPPDesk], g_iPPTeam == CS_TEAM_T ? "T" : "CT");
				Proof_SetPhase(PP_Desk);
			} else if (fIn > 20.0) { g_bPPLeaving = false; g_hPPTimer = null; Proof_Stop("aborted: no body after respawn"); return Plugin_Stop; }
		}
		case PP_Desk: {
			if (fIn > 1.5) {
				g_iPPSlot = Worker_DebugSpawn(g_iPPTeam, g_iDeskSeat[g_iPPDesk], true);
				if (g_iPPSlot == -1) { g_hPPTimer = null; Proof_Stop("aborted: worker spawn failed"); return Plugin_Stop; }
				g_iProofWorker = g_iPPSlot;
				Proof_Say("worker slot %d (protected from stray fire during the proof) spawned ~8 nav nodes away, walking to %s (path %d)", g_iPPSlot, g_sDeskId[g_iPPDesk], g_eNpc[g_iPPSlot].hPath.Length);
				Proof_SetPhase(PP_Walk);
			}
		}
		case PP_Walk: {
			if (g_eNpc[g_iPPSlot].eState == NS_Seated) {
				g_fPPWalk = fIn;
				Proof_Say("arrived, sitting down (walk-in %.1f s)", fIn);
				Proof_SetPhase(PP_Seated);
			} else if (fIn > 45.0) { g_hPPTimer = null; Proof_Stop("aborted: worker never reached the desk"); return Plugin_Stop; }
		}
		case PP_Seated: {
			if (g_fPPSitLoop == 0.0 && Proof_SitLoop()) { g_fPPSitLoop = fIn; Proof_Say("seated loop after %.1f s: %s", fIn, g_eNpc[g_iPPSlot].sAnim); }
			if (g_fPPSitLoop > 0.0 && fIn > g_fPPSitLoop + 5.0) {
				g_bProofHurting = true;
				SDKHooks_TakeDamage(Npc_GetEntity(g_iPPSlot), 0, 0, 1.0, DMG_BULLET, -1, NULL_VECTOR, NULL_VECTOR, false);
				g_bProofHurting = false;
				Proof_Say("THREAT: worker hurt (1 dmg) -> should flee to Safety (state %d)", g_eNpc[g_iPPSlot].eState);
				Proof_FollowCam(true);
				Proof_SetPhase(PP_Flee);
			} else if (fIn > 20.0) { g_hPPTimer = null; Proof_Stop("aborted: never reached the seated loop"); return Plugin_Stop; }
		}
		case PP_Flee: {
			Proof_FollowCam(false);
			if (g_eNpc[g_iPPSlot].eState == NS_Cowering) {
				g_fPPFlee = fIn;
				float v[3]; GetOrigin(Npc_GetEntity(g_iPPSlot), v);
				Proof_Say("at Safety, cowering (flee %.1f s) at %.0f %.0f %.0f", fIn, v[0], v[1], v[2]);
				Proof_SetPhase(PP_Safety);
			} else if (fIn > 45.0) { g_hPPTimer = null; Proof_Stop("aborted: worker never reached Safety"); return Plugin_Stop; }
		}
		case PP_Safety: {
			Proof_FollowCam(false);
			if (fIn > 5.0) {
				g_eNpc[g_iPPSlot].fLastHurt = 0.0;
				bool bOk = Worker_GoToSeat(g_iPPSlot, g_iDeskSeat[g_iPPDesk]);
				Proof_Say("RETURN order: back to desk %s (%s)", g_sDeskId[g_iPPDesk], bOk ? "path ok" : "NO PATH");
				Proof_SetPhase(PP_Return);
			}
		}
		case PP_Return: {
			Proof_FollowCam(false);
			if (g_eNpc[g_iPPSlot].eState == NS_Seated) {
				g_fPPRet = fIn;
				float vecEye[3];
				DeskCam_Place(c, g_iPPDesk, 150.0, 80.0, vecEye);
				Proof_Say("back at the desk, sitting down (return %.1f s)", fIn);
				g_fPPSitLoop = 0.0;
				Proof_SetPhase(PP_Reseated);
			} else if (fIn > 60.0) { g_hPPTimer = null; Proof_Stop("aborted: worker never got back"); return Plugin_Stop; }
		}
		case PP_Reseated: {
			if (g_fPPSitLoop == 0.0 && Proof_SitLoop()) { g_fPPSitLoop = fIn; Proof_Say("seated loop again: %s", g_eNpc[g_iPPSlot].sAnim); }
			if ((g_fPPSitLoop > 0.0 && fIn > g_fPPSitLoop + 4.0) || fIn > 15.0) {
				Proof_Say("DONE: walk-in %.1f s, flee %.1f s, return %.1f s, worker slot %d at %s", g_fPPWalk, g_fPPFlee, g_fPPRet, g_iPPSlot, g_sDeskId[g_iPPDesk]);
				g_ePP = PP_Off;
				g_iProofWorker = -1;
				if (IsPlayerAlive(c)) SetEntityMoveType(c, MOVETYPE_WALK);
				g_hPPTimer = null;
				return Plugin_Stop;
			}
		}
	}
	return Plugin_Continue;
}
