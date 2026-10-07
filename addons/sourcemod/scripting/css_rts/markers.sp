// css_rts/markers.sp -- commander-only unit markers, visible THROUGH WALLS (v0.4)
// materials/css_rts/xray.vmt = laserbeam texture with $ignorez, so rings + overhead chevrons
// draw on top of the world. Own bots: team colour (green = selected). Workers: yellow (red =
// fleeing). Allied humans: white. Also: off-screen direction counts, unit list, R = jump to next
// unit, Space = jump to the command post.

#define XRAY_MATERIAL "materials/css_rts/xray.vmt"

int g_iMarkerBeam;
int g_iMarkerXray;
Handle g_hHudUnits;
Handle g_hHudOffscreen;
#define NAME_TAGS 12
Handle g_hNameTag[NAME_TAGS];

bool g_bAltHp[MAXPLAYERS+1];

void Markers_Init() {
	g_hHudUnits = CreateHudSynchronizer();
	g_hHudOffscreen = CreateHudSynchronizer();
	for (int i = 0; i < NAME_TAGS; i++) g_hNameTag[i] = CreateHudSynchronizer();
	RegConsoleCmd("+rtsalt", Cmd_AltDown, "Hold Alt to show HP bars and numbers");
	RegConsoleCmd("-rtsalt", Cmd_AltUp);
}

public Action Cmd_AltDown(int iClient, int iArgs) {
	if (iClient) g_bAltHp[iClient] = true;
	return Plugin_Handled;
}

public Action Cmd_AltUp(int iClient, int iArgs) {
	if (iClient) g_bAltHp[iClient] = false;
	return Plugin_Handled;
}

void Markers_MapStart() {
	g_iMarkerBeam = PrecacheModel(LASER_MODEL, true);
	g_iMarkerXray = PrecacheModel(XRAY_MATERIAL[10], true);   // "css_rts/xray.vmt"
	if (!g_iMarkerXray) g_iMarkerXray = g_iMarkerBeam;
	CreateTimer(0.2, Timer_Markers, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

bool IsUnitSelected(int iCommander, int iEntity) {
	ArrayList hSel = g_eCommander[iCommander].hSelectedUnits;
	if (hSel == null) return false;
	int iRef = EntIndexToEntRef(iEntity);
	for (int i=0; i<hSel.Length; i++) {
		UnitSelection e;
		hSel.GetArray(i, e);
		if (e.iUnitEntRef == iRef) return true;
	}
	return false;
}

void DrawRing(int iClient, const float vecPos[3], float fRadius, const int iColor[4], float fWidth) {
	float vecC[3];
	vecC = vecPos; vecC[2] += 6.0;
	TE_SetupBeamRingPoint(vecC, fRadius, fRadius + 1.0, g_iMarkerXray, 0, 0, 0, 0.3, fWidth, 0.0, iColor, 0, 0);
	TE_SendToClient(iClient);
}

void DrawBeam(int iClient, const float a[3], const float b[3], const int iColor[4], float fWidth) {
	TE_SetupBeamPoints(a, b, g_iMarkerXray, 0, 0, 0, 0.3, fWidth, fWidth, 0, 0.0, iColor, 0);
	TE_SendToClient(iClient);
}

// Downward chevron ("V") floating above a unit, scaled with the camera distance so it stays readable
void DrawChevron(int iClient, const float vecFeet[3], const int iColor[4], float fScale, float fWidth) {
	float fYaw = DegToRad(g_fCamYaw[iClient] + 90.0);
	float rx = Cosine(fYaw) * 14.0 * fScale, ry = Sine(fYaw) * 14.0 * fScale;
	float vecTip[3], vecL[3], vecR[3];
	vecTip = vecFeet; vecTip[2] += 84.0;
	vecL = vecTip; vecL[0] += rx; vecL[1] += ry; vecL[2] += 18.0 * fScale;
	vecR = vecTip; vecR[0] -= rx; vecR[1] -= ry; vecR[2] += 18.0 * fScale;
	DrawBeam(iClient, vecL, vecTip, iColor, fWidth);
	DrawBeam(iClient, vecTip, vecR, iColor, fWidth);
}

void TeamColor(int iTeam, int iColor[4]) {
	if (iTeam == CS_TEAM_CT) iColor = {80, 160, 255, 255}; else iColor = {255, 150, 40, 255};
}

// Off-screen check against the commander camera: returns true if on screen; else iDir = 0..3 (left, up, right, down)
bool Markers_OnScreen(int c, const float vecPos[3], int &iDir) {
	int iFocus = EntRefToEntIndex(g_eCommander[c].iFocusEntRef);
	int iCam = EntRefToEntIndex(g_eCommander[c].iCameraEntRef);
	if (iFocus == INVALID_ENT_REFERENCE || iCam == INVALID_ENT_REFERENCE) return true;
	float vecCam[3], vecLocal[3];
	Entity_GetAbsOrigin(iFocus, vecCam);
	Entity_GetAbsOrigin(iCam, vecLocal);
	AddVectors(vecCam, vecLocal, vecCam);
	float vecAng[3], vecF[3], vecR[3], vecU[3], vecD[3];
	vecAng[0] = g_fCamPitchEff[c]; vecAng[1] = g_fCamYaw[c];
	GetAngleVectors(vecAng, vecF, vecR, vecU);
	SubtractVectors(vecPos, vecCam, vecD);
	vecD[2] += 36.0;
	float z = GetVectorDotProduct(vecD, vecF);
	float x = GetVectorDotProduct(vecD, vecR), y = GetVectorDotProduct(vecD, vecU);
	float fTanX = 0.75 * g_eCommander[c].fAspectRatio, fTanY = 0.75;
	if (z > 1.0 && FloatAbs(x) <= z * fTanX && FloatAbs(y) <= z * fTanY) return true;
	if (z <= 1.0) { z = 1.0; }
	float sx = x / (z * fTanX), sy = y / (z * fTanY);
	if (FloatAbs(sx) >= FloatAbs(sy)) iDir = sx < 0.0 ? 0 : 2;
	else iDir = sy > 0.0 ? 1 : 3;
	return false;
}

bool Markers_Screen(int c, const float vecPos[3], float &fX, float &fY) {
	int iFocus = EntRefToEntIndex(g_eCommander[c].iFocusEntRef);
	int iCam = EntRefToEntIndex(g_eCommander[c].iCameraEntRef);
	if (iFocus == INVALID_ENT_REFERENCE || iCam == INVALID_ENT_REFERENCE) return false;
	float vecCam[3], vecLocal[3];
	Entity_GetAbsOrigin(iFocus, vecCam);
	Entity_GetAbsOrigin(iCam, vecLocal);
	AddVectors(vecCam, vecLocal, vecCam);
	float vecAng[3], vecF[3], vecR[3], vecU[3], vecD[3];
	vecAng[0] = g_fCamPitchEff[c];
	vecAng[1] = g_fCamYaw[c];
	GetAngleVectors(vecAng, vecF, vecR, vecU);
	SubtractVectors(vecPos, vecCam, vecD);
	vecD[2] += 84.0;
	float z = GetVectorDotProduct(vecD, vecF);
	float x = GetVectorDotProduct(vecD, vecR), y = GetVectorDotProduct(vecD, vecU);
	float fTanX = 0.75 * g_eCommander[c].fAspectRatio, fTanY = 0.75;
	if (!(z > 1.0 && FloatAbs(x) <= z * fTanX && FloatAbs(y) <= z * fTanY)) return false;
	fX = 0.5 + (x / (z * fTanX)) * 0.5;
	fY = 0.5 - (y / (z * fTanY)) * 0.5 - 0.025;
	if (fX < 0.01) fX = 0.01;
	if (fX > 0.84) fX = 0.84;
	if (fY < 0.04) fY = 0.04;
	if (fY > 0.90) fY = 0.90;
	return true;
}

void Markers_Names(int c, int iTeam) {
	int iEnts[NAME_TAGS];
	int n;
	for (int i = 1; i <= MaxClients && n < NAME_TAGS; i++) {
		if (i == c || !IsClientInGame(i) || !IsPlayerAlive(i) || GetClientTeam(i) != iTeam || g_bBodyHidden[i]) continue;
		iEnts[n++] = i;
	}
	for (int k = 0; k < MAX_NPCS && n < NAME_TAGS; k++) {
		if (!g_eNpc[k].bUsed || g_eNpc[k].iTeam != iTeam || g_eNpc[k].eState == NS_Dead) continue;
		int e = Npc_GetEntity(k);
		if (e != -1) iEnts[n++] = e;
	}
	int iUsed;
	for (int i = 0; i < n && iUsed < NAME_TAGS; i++) {
		float vec[3], fX, fY;
		GetEntPropVector(iEnts[i], Prop_Data, "m_vecAbsOrigin", vec);
		if (!Markers_Screen(c, vec, fX, fY)) continue;
		char s[48];
		if (iEnts[i] <= MaxClients) FormatEx(s, sizeof(s), "%N  %d", iEnts[i], GetClientHealth(iEnts[i]));
		else {
			int slot = Npc_FromEntity(iEnts[i]);
			if (slot != -1 && g_eNpc[slot].eKind == Npc_Soldier) {
				char sWho[24];
				Train_Label(slot, sWho, sizeof(sWho));
				FormatEx(s, sizeof(s), "%s  %d", sWho, g_eNpc[slot].iHealth);
			} else FormatEx(s, sizeof(s), "Worker %d  %d", slot + 1, slot != -1 ? g_eNpc[slot].iHealth : 0);
		}
		SetHudTextParams(fX, fY, 0.4, 220, 255, 220, 255, 0, 0.0, 0.0, 0.0);
		ShowSyncHudText(c, g_hNameTag[iUsed], "%s", s);
		iUsed++;
	}
	for (int i = iUsed; i < NAME_TAGS; i++) ClearSyncHud(c, g_hNameTag[i]);
}

int g_iOffscreen[MAXPLAYERS+1][4];

void Alt_DrawHP(int c) {
	int iSprite = g_iMarkerXray > 0 ? g_iMarkerXray : g_iMarkerBeam;
	int iUsed, iIndex, iEnt;
	while ((iIndex = UnitEntityIterator(iIndex, iEnt)) != INVALID_ENT_REFERENCE) {
		if (!IsSelectableUnitEntity(c, iEnt)) continue;
		float p[3];
		Entity_GetAbsOrigin(iEnt, p);
		int iHp, iMax = 100;
		if (iEnt <= MaxClients) {
			if (!IsPlayerAlive(iEnt)) continue;
			iHp = GetClientHealth(iEnt);
			iMax = GetEntProp(iEnt, Prop_Data, "m_iMaxHealth");
		} else {
			int n = Npc_FromEntity(iEnt);
			if (n == -1) continue;
			iHp = g_eNpc[n].iHealth;
		}
		if (iHp < 0) iHp = 0;
		if (iMax < 1) iMax = 1;
		float fFrac = float(iHp) / float(iMax);
		if (fFrac > 1.0) fFrac = 1.0;
		if (iSprite > 0) {
			float a[3], b[3], d[3];
			a = p; b = p; d = p;
			a[2] += 82.0; b[2] += 82.0; d[2] += 82.0;
			a[0] -= 16.0; b[0] += 16.0;
			d[0] = a[0] + 32.0 * fFrac;
			int iBg[4] = {20, 20, 20, 220};
			int iFg[4] = {80, 220, 80, 255};
			if (fFrac < 0.35) { iFg[0] = 230; iFg[1] = 40; iFg[2] = 40; }
			TE_SetupBeamPoints(a, b, iSprite, 0, 0, 0, 0.25, 4.0, 4.0, 0, 0.0, iBg, 0);
			TE_SendToClient(c, 0.0);
			if (fFrac > 0.02) {
				TE_SetupBeamPoints(a, d, iSprite, 0, 0, 0, 0.25, 3.0, 3.0, 0, 0.0, iFg, 0);
				TE_SendToClient(c, 0.0);
			}
		}
		float fX, fY;
		if (iUsed < NAME_TAGS && Markers_Screen(c, p, fX, fY) && g_hNameTag[iUsed] != null) {
			SetHudTextParams(fX, fY - 0.04, 0.3, 255, 255, 255, 255, 0, 0.0, 0.0, 0.0);
			ShowSyncHudText(c, g_hNameTag[iUsed], "%d", iHp);
			iUsed++;
		}
	}
	for (int i = iUsed; i < NAME_TAGS; i++) if (g_hNameTag[i] != null) ClearSyncHud(c, g_hNameTag[i]);
}

public Action Timer_Markers(Handle hTimer) {
	for (int c=1; c<=MaxClients; c++) {
		if (!IsClientInGame(c) || IsFakeClient(c) || !g_eCommander[c].bEnabled) continue;
		int iTeam = GetClientTeam(c);
		int iTeamColor[4];
		TeamColor(iTeam, iTeamColor);
		float fScale = Clamp(g_fCamDistEff[c] / 350.0, 0.8, 12.0);
		float fRing = Clamp(g_fCamDistEff[c] / 900.0, 1.0, 8.0);   // v0.5.3.1: rings grow with zoom so they stay readable from high up
		for (int d=0; d<4; d++) g_iOffscreen[c][d] = 0;
		int iDir;
		for (int i=1; i<=MaxClients; i++) {
			if (i == c || !IsClientInGame(i) || !IsPlayerAlive(i) || GetClientTeam(i) != iTeam || g_bBodyHidden[i]) continue;
			// make sure the commander's client receives every ally regardless of the camera PVS
			SetEdictFlags(i, GetEdictFlags(i) | FL_EDICT_ALWAYS);
			float vecPos[3];
			GetClientAbsOrigin(i, vecPos);
			if (!Markers_OnScreen(c, vecPos, iDir)) { g_iOffscreen[c][iDir]++; continue; }
			if (IsFakeClient(i)) {
				bool bSel = IsUnitSelected(c, i);
				int iCol[4];
				iCol = bSel ? view_as<int>({60, 255, 60, 255}) : iTeamColor;
				DrawRing(c, vecPos, (bSel ? 30.0 : 26.0) * fRing, iCol, (bSel ? 5.0 : 3.0) * fRing);
				DrawChevron(c, vecPos, iCol, fScale * (bSel ? 1.3 : 1.0), bSel ? 4.0 : 3.0);
			} else {
				DrawRing(c, vecPos, 22.0 * fRing, view_as<int>({255, 255, 255, 220}), 2.0 * fRing);
				DrawChevron(c, vecPos, view_as<int>({255, 255, 255, 220}), fScale * 0.8, 2.0);
			}
		}
		for (int n=0; n<MAX_NPCS; n++) {
			if (!g_eNpc[n].bUsed || g_eNpc[n].iTeam != iTeam || g_eNpc[n].eState == NS_Dead) continue;
			int iEnt = Npc_GetEntity(n);
			if (iEnt == -1) continue;
			SetEdictFlags(iEnt, GetEdictFlags(iEnt) | FL_EDICT_ALWAYS);
			float vecPos[3];
			GetOrigin(iEnt, vecPos);
			if (!Markers_OnScreen(c, vecPos, iDir)) { g_iOffscreen[c][iDir]++; continue; }
			bool bSel = IsUnitSelected(c, iEnt);
			int iCol[4];
			if (bSel) iCol = {60, 255, 60, 255};
			else if (g_eNpc[n].eState == NS_Fleeing || g_eNpc[n].eState == NS_Cowering) iCol = {255, 40, 40, 255};
			else iCol = {255, 230, 40, 255};
			DrawRing(c, vecPos, 22.0 * fRing, iCol, (bSel ? 5.0 : 3.0) * fRing);
			DrawRing(c, vecPos, 14.0 * fRing, iCol, 2.0 * fRing);
			DrawChevron(c, vecPos, iCol, fScale * 0.8, 3.0);
		}
		Markers_Seats(c, iTeam);
		// v0.5.3.1: HQs (own = team colour, enemy = red) and enemy soldiers (red) through walls at any zoom
		for (int t=CS_TEAM_T; t<=CS_TEAM_CT; t++) {
			if (!g_ePost[t].bValid || !g_hCvarHQ.BoolValue) continue;
			float vecH[3]; vecH = g_ePost[t].vecHQOrigin;
			if (!Markers_OnScreen(c, vecH, iDir)) continue;
			int iHC[4];
			if (t == iTeam) iHC = iTeamColor; else iHC = {255, 40, 40, 255};
			if (g_bHQDestroyed[t]) iHC = {90, 90, 90, 255};
			DrawRing(c, vecH, 110.0 * fRing, iHC, 6.0 * fRing);
			DrawRing(c, vecH, 80.0 * fRing, iHC, 3.0 * fRing);
		}
		for (int i=1; i<=MaxClients; i++) {
			if (!IsClientInGame(i) || !IsPlayerAlive(i) || g_bBodyHidden[i]) continue;
			int ti = GetClientTeam(i);
			if (ti == iTeam || ti < CS_TEAM_T) continue;
			SetEdictFlags(i, GetEdictFlags(i) | FL_EDICT_ALWAYS);
			float vecPos[3];
			GetClientAbsOrigin(i, vecPos);
			if (!Markers_OnScreen(c, vecPos, iDir)) continue;
			DrawRing(c, vecPos, 20.0 * fRing, view_as<int>({255, 40, 40, 255}), 3.0 * fRing);
			DrawChevron(c, vecPos, view_as<int>({255, 40, 40, 255}), fScale * 0.7, 2.0 * fRing);
		}
	}
	return Plugin_Continue;
}

// Unit list for the jump hotkey: own bots, then own workers (entity indices)
int Markers_CollectUnits(int iTeam, int[] iOut, int iMax) {
	int n;
	for (int i=1; i<=MaxClients && n<iMax; i++) {
		if (IsClientInGame(i) && IsFakeClient(i) && IsPlayerAlive(i) && GetClientTeam(i) == iTeam && !g_bBodyHidden[i]) iOut[n++] = i;
	}
	for (int k=0; k<MAX_NPCS && n<iMax; k++) {
		if (g_eNpc[k].bUsed && g_eNpc[k].iTeam == iTeam && g_eNpc[k].eState != NS_Dead) {
			int iEnt = Npc_GetEntity(k);
			if (iEnt != -1) iOut[n++] = iEnt;
		}
	}
	return n;
}

int g_iJumpTarget[MAXPLAYERS+1];

// R: centre the camera on the next unit
void Markers_JumpNext(int c) {
	int iUnits[96];
	int n = Markers_CollectUnits(GetClientTeam(c), iUnits, sizeof(iUnits));
	if (!n) { PrintHintText(c, "No units to jump to"); return; }
	g_iCamCycle[c] = (g_iCamCycle[c] + 1) % n;
	int iEnt = iUnits[g_iCamCycle[c]];
	float vecPos[3];
	GetEntPropVector(iEnt, Prop_Data, "m_vecAbsOrigin", vecPos);
	Camera_GoTo(c, vecPos);
	g_iJumpTarget[c] = EntIndexToEntRef(iEnt);
}

// Space: back to the command post
void Markers_JumpHome(int c) {
	int t = GetClientTeam(c);
	if (!g_ePost[t].bValid) return;
	float vecPos[3];
	vecPos = g_ePost[t].bHasCamStart ? g_ePost[t].vecCamStart : g_ePost[t].vecOrigin;
	Camera_GoTo(c, vecPos);
}

void UnitLabel(int iEnt, char[] sOut, int iLen) {
	if (iEnt <= MaxClients) {
		FormatEx(sOut, iLen, "%N  %dhp", iEnt, GetClientHealth(iEnt));
	} else {
		int n = Npc_FromEntity(iEnt);
		static const char sState[][] = {"idle", "walking", "working", "FLEEING", "hiding", "dead"};
		if (n != -1 && g_eNpc[n].eKind == Npc_Soldier) {
			char sWho[24];
			Train_Label(n, sWho, sizeof(sWho));
			FormatEx(sOut, iLen, "%s  %dhp", sWho, g_eNpc[n].iHealth);
		} else FormatEx(sOut, iLen, "Worker %d  %dhp  %s", n, n != -1 ? g_eNpc[n].iHealth : 0, n != -1 ? sState[g_eNpc[n].eState] : "?");
	}
}


void IntelPlus(int iClient, const float vecFeet[3]) {
	static int iCol[4] = {255, 230, 40, 255};
	for (int k=0; k<3; k++) {
		float z = vecFeet[2] + 96.0 + k * 10.0;
		float a[3], b[3];
		a = vecFeet; b = vecFeet;
		a[2] = b[2] = z;
		a[0] -= 8.0; b[0] += 8.0;
		TE_SetupBeamPoints(a, b, g_iMarkerXray, 0, 0, 0, 0.25 + k * 0.25, 3.0, 3.0, 0, 0.0, iCol, 0);
		TE_SendToClient(iClient, k * 0.25);
		a = vecFeet; b = vecFeet;
		a[2] = z - 8.0; b[2] = z + 8.0;
		TE_SetupBeamPoints(a, b, g_iMarkerXray, 0, 0, 0, 0.25, 3.0, 3.0, 0, 0.0, iCol, 0);
		TE_SendToClient(iClient, k * 0.25);
	}
}

// v0.5.3: desk/seat beacons (through walls). Strong while placing a worker or with a worker selected,
// faint otherwise. Free = green, taken = grey.
bool Markers_WorkerSelected(int c) {
	for (int n=0; n<MAX_NPCS; n++) {
		if (!g_eNpc[n].bUsed || g_eNpc[n].eState == NS_Dead) continue;
		int e = Npc_GetEntity(n);
		if (e != -1 && IsUnitSelected(c, e)) return true;
	}
	return false;
}

int g_iSeatBeaconTick[MAXPLAYERS+1];

void Markers_Seats(int c, int iTeam) {
	// Every free chair, every tick, including ones the camera test used to call off-screen.
	int iSprite = g_iMarkerXray > 0 ? g_iMarkerXray : g_iMarkerBeam;
	if (iSprite <= 0) return;
	float fSR = Clamp(g_fCamDistEff[c] / 900.0, 1.0, 8.0);
	for (int s=0; s<g_iSeats; s++) {
		if (g_iSeatTeam[s] && g_iSeatTeam[s] != iTeam) continue;
		float p[3];
		p = g_vecSeat[s];
		bool bFree = g_iSeatOwner[s] == -1;
		int iCol[4];
		if (bFree) iCol = {255, 220, 40, 255};
		else iCol = {150, 150, 150, 160};
		float vecC[3];
		vecC = p; vecC[2] += 12.0;
		TE_SetupBeamRingPoint(vecC, 16.0 * fSR, 20.0 * fSR, iSprite, 0, 0, 0, 0.35, 5.0 * fSR, 0.0, iCol, 0, 0);
		TE_SendToClient(c);
		if (bFree) {
			float a[3], b[3];
			a = p; a[2] += 14.0;
			b = p; b[2] += 84.0;
			TE_SetupBeamPoints(a, b, iSprite, 0, 0, 0, 0.35, 3.0, 0.6, 0, 0.0, iCol, 0);
			TE_SendToClient(c);
		}
	}
}
