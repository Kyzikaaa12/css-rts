// css_rts/ghost.sp -- hover-ghost placement for the Commander (v0.4: workers; later: buildings)
// A translucent model follows the cursor: green = valid (seat: worker will produce), yellow =
// valid but no seat (idle, no income), red = invalid. Left click confirms, right click cancels.

enum GhostKind {
	Ghost_None = 0,
	Ghost_Worker
}

GhostKind g_eGhost[MAXPLAYERS+1];
int g_iGhostRef[MAXPLAYERS+1] = {INVALID_ENT_REFERENCE, ...};
int g_iGhostOwner[2049];

bool Ghost_IsWorker(int iClient) {
	return g_eGhost[iClient] == Ghost_Worker;
}

bool Ghost_Active(int iClient) {
	return g_eGhost[iClient] != Ghost_None;
}

void Ghost_Start(int iClient, GhostKind eKind) {
	Ghost_Stop(iClient);
	int iEnt = CreateEntityByName("prop_dynamic_override");
	if (iEnt == -1) return;
	DispatchKeyValue(iEnt, "model", g_sWorkerModels[0]);
	DispatchKeyValue(iEnt, "solid", "0");
	DispatchKeyValue(iEnt, "DefaultAnim", "idle_subtle");
	DispatchKeyValue(iEnt, "disableshadows", "1");
	DispatchKeyValue(iEnt, "targetname", "css_rts_ghost");
	DispatchSpawn(iEnt);
	SetEntityRenderMode(iEnt, RENDER_TRANSCOLOR);
	SetEntityRenderColor(iEnt, 80, 255, 80, 140);
	g_iGhostOwner[iEnt] = iClient;
	SDKHook(iEnt, SDKHook_SetTransmit, SDKHookCB_GhostTransmit);
	g_iGhostRef[iClient] = EntIndexToEntRef(iEnt);
	g_eGhost[iClient] = eKind;
	PrintHintText(iClient, "Place the worker: move the cursor to a desk chair\nLeft click = confirm, right click = cancel");
}

void Ghost_Stop(int iClient) {
	int iEnt = EntRefToEntIndex(g_iGhostRef[iClient]);
	if (iEnt != INVALID_ENT_REFERENCE) RemoveEntity(iEnt);
	g_iGhostRef[iClient] = INVALID_ENT_REFERENCE;
	g_eGhost[iClient] = Ghost_None;
}

public Action SDKHookCB_GhostTransmit(int iEnt, int iClient) {
	return g_iGhostOwner[iEnt] == iClient ? Plugin_Continue : Plugin_Handled;
}

// 0 = invalid, 1 = valid (no seat), 2 = valid on a free seat (vecSnap = seat)
int Ghost_WorkerSpot(int iTeam, const float vecCursor[3], float vecSnap[3], float &fYaw) {
	vecSnap = vecCursor;
	float vecFloor[3];
	if (SnapToFloor(vecCursor, vecFloor)) vecSnap = vecFloor;
	Seats_Reclaim();
	int s = -1;
	for (int d = 0; d < g_iDesks; d++) {
		if (!g_bDeskOk[d] || g_iDeskSeat[d] < 0) continue;
		if (g_iDeskTeam[d] && g_iDeskTeam[d] != iTeam) continue;
		if (g_iSeatOwner[g_iDeskSeat[d]] != -1) continue;
		float dx = vecSnap[0] - g_vecDeskWall[d][0], dy = vecSnap[1] - g_vecDeskWall[d][1];
		if (SquareRoot(dx * dx + dy * dy) < 110.0) { s = g_iDeskSeat[d]; break; }
	}
	if (s == -1) s = FindFreeSeat(iTeam, vecSnap, 120.0);
	if (s == -1) {
		float fBest = 140.0;
		for (int i = 0; i < g_iSeats; i++) {
			if (g_iSeatOwner[i] != -1 || (g_iSeatTeam[i] && g_iSeatTeam[i] != iTeam)) continue;
			float dx = vecSnap[0] - g_vecSeat[i][0], dy = vecSnap[1] - g_vecSeat[i][1];
			float d = SquareRoot(dx * dx + dy * dy);
			if (FloatAbs(vecSnap[2] - g_vecSeat[i][2]) < 200.0 && d < fBest) { fBest = d; s = i; }
		}
	}
	if (s != -1) { vecSnap = g_vecSeat[s]; fYaw = g_fSeatYaw[s]; return 2; }
	if (g_iNavAreas > 0) {
		int a = Nav_NearestArea(vecCursor);
		if (a == -1) return 0;
		float vecC[3];
		Nav_Center(a, vecC);
		if (FloatAbs(vecC[2] - vecCursor[2]) > 64.0) return 0;
	}
	float vecUp[3];
	vecUp = vecCursor; vecUp[2] += 8.0;
	float vecMins[3] = {-13.0, -13.0, 0.0}, vecMaxs[3] = {13.0, 13.0, 72.0};
	if (!HullClear(vecUp, vecMins, vecMaxs)) return 0;
	return 1;
}

// Called from the commander cursor code each tick while a ghost is active
void Ghost_Update(int iClient, const float vecCursor[3], int iButtons, int iLastButtons) {
	int iEnt = EntRefToEntIndex(g_iGhostRef[iClient]);
	if (iEnt == INVALID_ENT_REFERENCE) { g_eGhost[iClient] = Ghost_None; return; }
	int t = GetClientTeam(iClient);
	float vecSnap[3], fYaw = g_fCamYaw[iClient] + 180.0;
	int iValid = Ghost_WorkerSpot(t, vecCursor, vecSnap, fYaw);
	float vecAng[3];
	vecAng[1] = fYaw;
	TeleportEntity(iEnt, vecSnap, vecAng, NULL_VECTOR);
	if (iValid == 2) SetEntityRenderColor(iEnt, 60, 255, 60, 150);
	else if (iValid == 1) SetEntityRenderColor(iEnt, 255, 230, 60, 130);
	else SetEntityRenderColor(iEnt, 255, 40, 40, 130);
	int iCost = Worker_NextCost(t);
	Hud_Action(iClient, "%s\nHire worker: %d Intel (have %d)  -  LMB place, RMB cancel",
		iValid == 2 ? "Desk chair: worker will produce Intel" : (iValid == 1 ? "No seat here: worker will stand idle (no income)" : "Invalid spot"),
		iCost, g_iIntel[t]);
	bool bLeft = (iButtons & IN_ATTACK) && !(iLastButtons & IN_ATTACK);
	bool bRight = (iButtons & IN_ATTACK2) && !(iLastButtons & IN_ATTACK2);
	if (bRight) { Ghost_Stop(iClient); PrintHintText(iClient, "Placement cancelled"); return; }
	if (!bLeft) return;
	if (!iValid) { PrintHintText(iClient, "Can't place a worker there"); return; }
	int i = Worker_HireAt(iClient, vecSnap, fYaw);
	if (i == -1) { Ghost_Stop(iClient); return; }
	int s = FindFreeSeat(t, vecSnap, 48.0);
	if (s != -1) {
		if (GetVectorDistance(vecSnap, g_vecSeat[s]) < 40.0) Worker_SeatNow(i, s);
		else Worker_GoToSeat(i, s);
	}
	Ghost_Stop(iClient);
}
