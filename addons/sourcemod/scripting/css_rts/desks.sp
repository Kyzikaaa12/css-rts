// css_rts/desks.sp -- v0.5.3 real office desks (data-driven per map).
// Config "desks" { "<id>" { "origin" "x y z" "team" "CT|T" "group" "office|base" ["yaw" "<into-room yaw>"] } }
// Each desk is fitted against the nearest wall (or the wall behind the given yaw), checked for floor
// and clearance, nudged along the wall when blocked, then a desk set is spawned: desk + monitor +
// keyboard + phone + office chair. The chair spot becomes a worker seat (the worker faces the desk).
// If a map has "desks", its old "seats" list is ignored.

#define MAX_DESKS 24
#define DESK_MODEL     "models/props_interiors/furniture_desk01a.mdl"
#define DESK_MONITOR   "models/props/cs_office/computer_monitor.mdl"
#define DESK_KEYBOARD  "models/props/cs_office/computer_keyboard.mdl"
#define DESK_PHONE     "models/props/cs_office/phone.mdl"
#define DESK_CHAIR     "models/props/cs_office/chair_office.mdl"
#define DESK_PROPS 5

int g_iDesks;
// v0.5.3.1 HQ wall fit (hq.sp)
bool g_bHQFit[4];
float g_vecHQWall[4][3];        // wall point behind the terminal
float g_fHQYaw[4];              // facing out of the wall (into the room)
int g_iHQRacks[4];              // racks that fit (0-2)
char g_sHQWhy[4][48];
float g_fHQCoreScale = 0.7;
float g_fHQMirror[4] = {1.0, ...};
int g_iDeskBlocker;
char g_sDeskId[MAX_DESKS][16];
int g_iDeskTeam[MAX_DESKS];
bool g_bDeskOffice[MAX_DESKS];
float g_vecDeskAnchor[MAX_DESKS][3];
float g_fDeskYawHint[MAX_DESKS];       // -1 = auto (nearest wall)
bool g_bDeskOk[MAX_DESKS];
float g_vecDeskWall[MAX_DESKS][3];     // fitted point at the wall (floor height)
float g_fDeskYaw[MAX_DESKS];           // into-room direction
int g_iDeskSeat[MAX_DESKS];
int g_iDeskProp[MAX_DESKS][DESK_PROPS];
char g_sDeskWhy[MAX_DESKS][32];
bool g_bDeskFree[MAX_DESKS];          // v0.5.4: "wall" "0" = freestanding (open yards, e.g. de_dust2 CT spawn)

void Desks_Init() {
	RegConsoleCmd("sm_rts_debug_slice", cmdDebugSlice, "<name> <x> <y> <z> [half=192] [step=6]: top-down solid map at waist height -> data/css_rts_slice_<map>.txt (contact sheets)");
	RegConsoleCmd("sm_rts_debug_roofmap", cmdDebugRoofMap, "Write per-nav-area roof/ceiling data to data/css_rts_roof_<map>.txt (planning)");
	RegConsoleCmd("sm_rts_debug_desks", cmdDebugDesks, "List fitted desks (id team group wall-point yaw seat ok)");
	RegConsoleCmd("sm_rts_debug_deskfit", cmdDebugDeskFit, "<x> <y> <z> [yaw]: try to fit a desk at a point and print the result");
	for (int d=0; d<MAX_DESKS; d++) for (int k=0; k<DESK_PROPS; k++) g_iDeskProp[d][k] = INVALID_ENT_REFERENCE;
}

void Desks_LoadConfig(KeyValues hKv) {
	g_iDesks = 0;
	if (hKv == null) return;
	char sTeam[8], sGroup[16];
	if (hKv.JumpToKey("desks") && hKv.GotoFirstSubKey()) {
		do {
			if (g_iDesks >= MAX_DESKS) break;
			int d = g_iDesks;
			if (!KvGetVec(hKv, "origin", g_vecDeskAnchor[d])) continue;
			hKv.GetSectionName(g_sDeskId[d], sizeof(g_sDeskId[]));
			hKv.GetString("team", sTeam, sizeof(sTeam), "any");
			g_iDeskTeam[d] = TeamFromName(sTeam);
			hKv.GetString("group", sGroup, sizeof(sGroup), "office");
			g_bDeskOffice[d] = !StrEqual(sGroup, "base", false);
			g_fDeskYawHint[d] = hKv.GetFloat("yaw", -1.0);
			g_bDeskFree[d] = hKv.GetNum("wall", 1) == 0 && g_fDeskYawHint[d] >= 0.0;
			g_iDeskSeat[d] = -1;
			g_bDeskOk[d] = false;
			g_iDesks++;
		} while (hKv.GotoNextKey());
		hKv.GoBack(); hKv.GoBack();
	}
	LogMessage("Desks: %d in config", g_iDesks);
}

void Desks_MapStart() {
	if (!g_iDesks) return;
	PrecacheModel(DESK_MODEL, true); PrecacheModel(DESK_MONITOR, true); PrecacheModel(DESK_KEYBOARD, true);
	PrecacheModel(DESK_PHONE, true); PrecacheModel(DESK_CHAIR, true);
	for (int d=0; d<MAX_DESKS; d++) for (int k=0; k<DESK_PROPS; k++) g_iDeskProp[d][k] = INVALID_ENT_REFERENCE;
	// the desks replace the config's placeholder seats
	g_iSeats = 0;
	int iOk;
	for (int d=0; d<g_iDesks; d++) {
		g_bDeskOk[d] = Desk_FitSearch(d);
		g_iDeskSeat[d] = -1;
		if (!g_bDeskOk[d] || g_iSeats >= MAX_SEATS) { LogError("Desk %s at %.0f %.0f %.0f not placed: %s", g_sDeskId[d], g_vecDeskAnchor[d][0], g_vecDeskAnchor[d][1], g_vecDeskAnchor[d][2], g_sDeskWhy[d]); continue; }
		int s = g_iSeats++;
		Desk_LocalFloor(d, 0.0, 58.0, 0.0, g_vecSeat[s]);
		g_fSeatYaw[s] = AngleNorm(g_fDeskYaw[d] + 180.0);
		g_iSeatTeam[s] = g_iDeskTeam[d];
		g_iSeatOwner[s] = -1;
		g_iDeskSeat[d] = s;
		iOk++;
	}
	LogMessage("Desks: %d/%d fitted, %d seats", iOk, g_iDesks, g_iSeats);
}

int Seat_EnemiesNear(int iTeam, const float vec[3], float fRange) {
	int n = 0;
	int iEnemy = iTeam == CS_TEAM_T ? CS_TEAM_CT : CS_TEAM_T;
	for (int i = 1; i <= MaxClients; i++) {
		if (!IsClientInGame(i) || !IsPlayerAlive(i) || GetClientTeam(i) != iEnemy || g_bBodyHidden[i]) continue;
		float p[3];
		GetClientAbsOrigin(i, p);
		if (GetVectorDistance(vec, p) <= fRange) n++;
	}
	return n;
}

void Seat_BotPost(int s, int iSalt, float vecOut[3]) {
	vecOut = g_vecSeat[s];
	float fAng = (g_fSeatYaw[s] + 180.0) * 0.0174533;
	float fSide = (g_fSeatYaw[s] + 90.0) * 0.0174533;
	float fOff = float((iSalt % 3) - 1) * 72.0;
	vecOut[0] += Cosine(fAng) * 90.0 + Cosine(fSide) * fOff;
	vecOut[1] += Sine(fAng) * 90.0 + Sine(fSide) * fOff;
}

bool Seat_GroupPoint(int iTeam, bool bOffice, int iSalt, float vecOut[3]) {
	int iList[16];
	int n = 0;
	for (int d = 0; d < g_iDesks && n < 16; d++) {
		if (!g_bDeskOk[d] || g_bDeskOffice[d] != bOffice) continue;
		if (g_iDeskTeam[d] && g_iDeskTeam[d] != iTeam) continue;
		int s = g_iDeskSeat[d];
		if (s < 0 || s >= g_iSeats) continue;
		iList[n++] = s;
	}
	if (!n) return Seat_DefendPoint(iTeam, 0, 1, vecOut);
	Seat_BotPost(iList[iSalt % n], iSalt, vecOut);
	return true;
}

bool Seat_DefendPoint(int iTeam, int iSlot, int nDef, float vecOut[3]) {
	int iSeats[MAX_SEATS];
	int nSeats = 0;
	for (int s = 0; s < g_iSeats && nSeats < MAX_SEATS; s++) {
		if (g_iSeatTeam[s] && g_iSeatTeam[s] != iTeam) continue;
		iSeats[nSeats++] = s;
	}
	if (!nSeats) return false;
	if (iSlot < 0) iSlot = 0;
	if (nDef < 1) nDef = 1;

	int iClusterOf[MAX_SEATS], iClusterSeat[8], iClusterN[8];
	int nClus = 0;
	for (int i = 0; i < nSeats; i++) iClusterOf[i] = 0;
	for (int c = 0; c < 8; c++) { iClusterSeat[c] = 0; iClusterN[c] = 0; }
	for (int i = 0; i < nSeats; i++) {
		int s = iSeats[i];
		int iJoin = -1;
		for (int c = 0; c < nClus; c++) {
			if (GetVectorDistance(g_vecSeat[s], g_vecSeat[iClusterSeat[c]]) <= 520.0) { iJoin = c; break; }
		}
		if (iJoin == -1 && nClus < 8) {
			iJoin = nClus;
			iClusterSeat[nClus] = s;
			nClus++;
		}
		if (iJoin < 0) iJoin = 0;
		iClusterOf[i] = iJoin;
		iClusterN[iJoin]++;
	}

	int iEnemies[8];
	for (int c = 0; c < 8; c++) iEnemies[c] = 0;
	for (int c = 0; c < nClus; c++) {
		for (int i = 0; i < nSeats; i++) {
			if (iClusterOf[i] != c) continue;
			int n = Seat_EnemiesNear(iTeam, g_vecSeat[iSeats[i]], 560.0);
			if (n > iEnemies[c]) iEnemies[c] = n;
		}
	}
	int iHot = 0, iMax = 0, nTied = 0;
	for (int c = 0; c < nClus; c++) if (iEnemies[c] > iMax) iMax = iEnemies[c];
	for (int c = 0; c < nClus; c++) if (iMax > 0 && iEnemies[c] == iMax) { nTied++; iHot = c; }
	bool bFocus = iMax > 0 && nTied == 1;

	int iPick = iSeats[0];
	if (bFocus) {
		int nHot = iClusterN[iHot];
		if (nHot < 1) nHot = 1;
		int iReserve = 0;
		if (nDef > 2) {
			int iOthers = nClus - 1;
			int iSpare = nDef - 2;
			if (iSpare > iOthers) iSpare = iOthers;
			iReserve = iSpare;
		}
		int nFocus = nDef - iReserve;
		if (nFocus < 1) nFocus = nDef;
		if (iSlot < nFocus) {
			int iWant = iSlot % nHot;
			int k = 0;
			for (int i = 0; i < nSeats; i++) {
				if (iClusterOf[i] != iHot) continue;
				if (k == iWant) { iPick = iSeats[i]; break; }
				k++;
			}
		} else {
			int iQuiet = iSlot - nFocus, iSeen = -1;
			for (int c = 0; c < nClus; c++) {
				if (c == iHot) continue;
				iSeen++;
				if (iSeen != iQuiet) continue;
				for (int i = 0; i < nSeats; i++) if (iClusterOf[i] == c) { iPick = iSeats[i]; break; }
				break;
			}
		}
	} else {
		bool bPicked[MAX_SEATS];
		int iOrder[MAX_SEATS];
		for (int i = 0; i < nSeats; i++) bPicked[i] = false;
		iOrder[0] = 0;
		bPicked[0] = true;
		for (int k = 1; k < nSeats; k++) {
			int iBest = 0;
			float fBest = -1.0;
			for (int i = 0; i < nSeats; i++) {
				if (bPicked[i]) continue;
				float fNear = 999999.0;
				for (int j = 0; j < k; j++) {
					float d = GetVectorDistance(g_vecSeat[iSeats[i]], g_vecSeat[iSeats[iOrder[j]]]);
					if (d < fNear) fNear = d;
				}
				if (fNear > fBest) { fBest = fNear; iBest = i; }
			}
			iOrder[k] = iBest;
			bPicked[iBest] = true;
		}
		iPick = iSeats[iOrder[iSlot % nSeats]];
	}
	Seat_BotPost(iPick, iSlot, vecOut);
	return true;
}

float AngleNorm(float a) {
	while (a < 0.0) a += 360.0;
	while (a >= 360.0) a -= 360.0;
	return a;
}

// point relative to a fitted desk: fSide along the wall, fOut into the room, fUp above the floor
// like Desk_Local, but on the floor found under that point (curbs, slopes)
void Desk_LocalFloor(int d, float fSide, float fOut, float fUp, float vecOut[3]) {
	Desk_Local(d, fSide, fOut, 0.0, vecOut);
	bool bOk;
	float z = Desk_FloorZ(vecOut, bOk);
	if (bOk && FloatAbs(z - g_vecDeskWall[d][2]) <= 14.0) vecOut[2] = z;
	vecOut[2] += fUp;
}

void Desk_Local(int d, float fSide, float fOut, float fUp, float vecOut[3]) {
	float y = DegToRad(g_fDeskYaw[d]);
	float fx = Cosine(y), fy = Sine(y);
	vecOut[0] = g_vecDeskWall[d][0] + fx * fOut + fy * fSide;
	vecOut[1] = g_vecDeskWall[d][1] + fy * fOut - fx * fSide;
	vecOut[2] = g_vecDeskWall[d][2] + fUp;
}

public bool TraceFilter_DeskWorld(int iEntity, int iMask) {
	return iEntity == 0;
}

float Desk_FloorZ(const float vecPos[3], bool &bOk) {
	float a[3], b[3], h[3];
	a = vecPos; a[2] += 40.0;
	b = vecPos; b[2] -= 120.0;
	TR_TraceRayFilter(a, b, MASK_PLAYERSOLID_BRUSHONLY, RayType_EndPoint, TraceFilter_DeskWorld);
	bOk = TR_DidHit() && !TR_StartSolid();
	TR_GetEndPosition(h);
	return h[2];
}

bool Desk_BoxClear(const float vecPos[3], float fHalf, float fZ0, float fZ1) {
	float mn[3], mx[3];
	mn[0] = -fHalf; mn[1] = -fHalf; mn[2] = fZ0;
	mx[0] = fHalf; mx[1] = fHalf; mx[2] = fZ1;
	TR_TraceHullFilter(vecPos, vecPos, mn, mx, MASK_PLAYERSOLID, TraceFilter_DeskSolid);
	g_iDeskBlocker = TR_GetEntityIndex();
	return !TR_DidHit() && !TR_StartSolid();
}
void Desk_BlockWhy(const char[] sWhat, char[] sWhy, int iWhy) {
	char s[24] = "world";
	if (g_iDeskBlocker > 0 && IsValidEntity(g_iDeskBlocker)) GetEntityClassname(g_iDeskBlocker, s, sizeof(s));
	FormatEx(sWhy, iWhy, "%s blocked (%s)", sWhat, s);
}

// world + anything solid except players/NPC workers/our own desk props
public bool TraceFilter_DeskSolid(int iEntity, int iMask) {
	if (iEntity == 0) return true;
	if (iEntity <= MaxClients) return false;
	char s[32];
	GetEntityClassname(iEntity, s, sizeof(s));
	if (StrContains(s, "prop_physics") == 0) return false;   // chairs, boxes: pushable
	if (StrEqual(s, "func_door") || StrEqual(s, "func_door_rotating") || StrEqual(s, "prop_door_rotating")) return true;
	return StrContains(s, "func_") == 0 && !StrEqual(s, "func_buyzone") && !StrEqual(s, "func_hostage_rescue") && !StrEqual(s, "func_bomb_target");
}

// find the wall: trace from the anchor (desk height) in 16 directions, or behind the hint yaw
bool Desk_FindWall(const float vecAnchor[3], float fFloor, float fYawHint, float vecWall[3], float &fYaw) {
	float a[3], b[3], h[3], n[3];
	a = vecAnchor; a[2] = fFloor + 30.0;
	static float mn[3] = {-4.0, -4.0, -4.0}, mx[3] = {4.0, 4.0, 4.0};
	float fBest = 99999.0;
	bool bFound;
	for (int k=0; k<16; k++) {
		float yaw = fYawHint >= 0.0 ? fYawHint + 180.0 : k * 22.5;
		if (fYawHint >= 0.0 && k > 0) break;
		b[0] = a[0] + Cosine(DegToRad(yaw)) * 220.0;
		b[1] = a[1] + Sine(DegToRad(yaw)) * 220.0;
		b[2] = a[2];
		TR_TraceHullFilter(a, b, mn, mx, MASK_PLAYERSOLID_BRUSHONLY, TraceFilter_DeskWorld);
		if (TR_StartSolid() || !TR_DidHit()) continue;
		TR_GetPlaneNormal(INVALID_HANDLE, n);
		if (FloatAbs(n[2]) > 0.3) continue;           // not a wall
		float f = TR_GetFraction() * 220.0;
		if (f < fBest) {
			fBest = f; bFound = true;
			TR_GetEndPosition(h);
			vecWall[0] = h[0] - n[0] * 4.0; vecWall[1] = h[1] - n[1] * 4.0; vecWall[2] = fFloor;   // on the wall surface
			fYaw = AngleNorm(RadToDeg(ArcTangent2(n[1], n[0])));
			// snap to the nearest 90 degrees when the wall is almost axis-aligned (cs_office is)
			float fSnap = float(RoundToNearest(fYaw / 90.0)) * 90.0;
			if (FloatAbs(AngleDiff(fYaw, fSnap)) < 8.0) fYaw = AngleNorm(fSnap);
		}
	}
	return bFound;
}

bool Desk_CheckAt(int d, char[] sWhy, int iWhy) {
	// floor under desk ends, chair; clear boxes; wall behind both desk ends; spacing to other desks
	float p[3];
	bool bOk;
	static float fChecks[][3] = {{-28.0, 20.0, 0.0}, {28.0, 20.0, 0.0}, {0.0, 58.0, 0.0}, {0.0, 90.0, 0.0}};
	for (int k=0; k<sizeof(fChecks); k++) {
		Desk_Local(d, fChecks[k][0], fChecks[k][1], 0.0, p);
		float z = Desk_FloorZ(p, bOk);
		if (!bOk || FloatAbs(z - g_vecDeskWall[d][2]) > 10.0) { FormatEx(sWhy, iWhy, "no floor (%d)", k); return false; }
	}
	Desk_Local(d, -18.0, 22.0, 0.0, p); if (!Desk_BoxClear(p, 15.0, 12.0, 44.0)) { Desk_BlockWhy("desk L", sWhy, iWhy); return false; }
	Desk_Local(d, 18.0, 22.0, 0.0, p);  if (!Desk_BoxClear(p, 15.0, 12.0, 44.0)) { Desk_BlockWhy("desk R", sWhy, iWhy); return false; }
	Desk_Local(d, 0.0, 60.0, 0.0, p);   if (!Desk_BoxClear(p, 15.0, 12.0, 60.0)) { Desk_BlockWhy("chair", sWhy, iWhy); return false; }
	Desk_Local(d, 0.0, 96.0, 0.0, p);   if (!Desk_BoxClear(p, 16.0, 12.0, 64.0)) { Desk_BlockWhy("access", sWhy, iWhy); return false; }
	// wall right behind the desk centre and at least one end (else it sits in a doorway / opening)
	int iEnds = g_bDeskFree[d] ? 1 : 0;
	for (int sd=-1; sd<=1 && !g_bDeskFree[d]; sd++) {
		bool bHit = false;
		for (int hz=0; hz<3 && !bHit; hz++) {
			float a[3], b[3];
			float fH = hz == 0 ? 20.0 : (hz == 1 ? 32.0 : 46.0);
			Desk_Local(d, sd * 30.0, 10.0, fH, a);
			Desk_Local(d, sd * 30.0, -14.0, fH, b);
			TR_TraceRayFilter(a, b, MASK_PLAYERSOLID, RayType_EndPoint, TraceFilter_DeskSolid);
			bHit = TR_DidHit();
		}
		if (sd == 0 && !bHit) { strcopy(sWhy, iWhy, "opening behind"); return false; }
		if (sd != 0 && bHit) iEnds++;
	}
	if (iEnds == 0) { strcopy(sWhy, iWhy, "opening behind"); return false; }
	// v0.5.3.1: flush along the whole desk, no doorway beside it, 96u walkway in front of desk + chair, no doors/spawns near
	if (!g_bDeskFree[d] && !Place_RowOk(g_vecDeskWall[d], g_fDeskYaw[d], -34.0, 34.0, 76.0, 44.0, sWhy, iWhy)) return false;
	// keep clear of player spawn points (desk + chair + a little room to step off)
	float vecC[3], vecD[3], vecS[3];
	Desk_Local(d, 0.0, 58.0, 0.0, vecC);
	Desk_Local(d, 0.0, 20.0, 0.0, vecD);
	int e = -1;
	static const char sSpawns[][] = {"info_player_terrorist", "info_player_counterterrorist"};
	for (int k=0; k<2; k++) {
		e = -1;
		while ((e = FindEntityByClassname(e, sSpawns[k])) != -1) {
			GetEntPropVector(e, Prop_Data, "m_vecAbsOrigin", vecS);
			if (FloatAbs(vecS[2] - vecC[2]) > 64.0) continue;
			vecS[2] = vecC[2];
			if (GetVectorDistance(vecS, vecC) < 52.0 || GetVectorDistance(vecS, vecD) < 56.0) { strcopy(sWhy, iWhy, "on a spawn point"); return false; }
		}
	}
	// keep clear of the command posts / HQ hubs
	for (int t=CS_TEAM_T; t<=CS_TEAM_CT; t++) {
		if (g_ePost[t].bValid && GetVectorDistance(g_ePost[t].vecOrigin, vecD) < 120.0) { strcopy(sWhy, iWhy, "too close to the post"); return false; }
		if (g_ePost[t].bHasHQ && GetVectorDistance(g_ePost[t].vecHQOrigin, vecD) < 140.0) { strcopy(sWhy, iWhy, "too close to the HQ"); return false; }
		if (g_bHQFit[t]) for (int k=1; k<=1+g_iHQRacks[t]; k++) {
			float vecP[3]; HQ_RowPos(t, k, vecP);
			if (FloatAbs(vecP[2] - vecD[2]) < 80.0 && GetVectorDistance(vecP, vecD) < HQ_PartHalfW(k) + 90.0) { strcopy(sWhy, iWhy, "too close to the HQ"); return false; }
		}
	}
	for (int o=0; o<g_iDesks; o++) {
		if (o == d || !g_bDeskOk[o]) continue;
		if (GetVectorDistance(g_vecDeskWall[o], g_vecDeskWall[d]) < 84.0) { strcopy(sWhy, iWhy, "too close to another desk"); return false; }
	}
	return true;
}

bool Desk_Fit(int d, const float vecAnchor[3], float fYawHint, float vecWall[3], float &fYaw, char[] sWhy, int iWhy) {
	bool bOk;
	float fFloor = Desk_FloorZ(vecAnchor, bOk);
	if (!bOk) { strcopy(sWhy, iWhy, "anchor has no floor"); return false; }
	if (FloatAbs(fFloor - g_vecDeskAnchor[d][2]) > 16.0 && d < g_iDesks) { strcopy(sWhy, iWhy, "other floor level"); return false; }
	static float fNudge[] = {0.0, 24.0, -24.0, 48.0, -48.0, 72.0, -72.0, 96.0, -96.0, 128.0, -128.0};
	float vecA[3];
	vecA = vecAnchor; vecA[2] = fFloor;
	if (!Desk_FindWall(vecA, fFloor, fYawHint, vecWall, fYaw)) { strcopy(sWhy, iWhy, "no wall within 220u"); return false; }
	float fBaseYaw = fYaw, vecBase[3];
	vecBase = vecWall;
	for (int k=0; k<sizeof(fNudge); k++) {
		// slide along the wall (tangent), re-find the wall from a point 40u out
		float y = DegToRad(fBaseYaw), vecTry[3];
		vecTry[0] = vecBase[0] + Cosine(y) * 40.0 + Sine(y) * fNudge[k];
		vecTry[1] = vecBase[1] + Sine(y) * 40.0 - Cosine(y) * fNudge[k];
		vecTry[2] = fFloor;
		float fz = Desk_FloorZ(vecTry, bOk);
		if (!bOk || FloatAbs(fz - fFloor) > 10.0) continue;
		if (!Desk_FindWall(vecTry, fFloor, fBaseYaw, g_vecDeskWall[d], g_fDeskYaw[d])) continue;
		if (FloatAbs(AngleDiff(g_fDeskYaw[d], fBaseYaw)) > 20.0) continue;
		if (Desk_CheckAt(d, sWhy, iWhy)) { vecWall = g_vecDeskWall[d]; fYaw = g_fDeskYaw[d]; sWhy[0] = 0; return true; }
	}
	vecWall = vecBase; fYaw = fBaseYaw;
	g_vecDeskWall[d] = vecBase; g_fDeskYaw[d] = fBaseYaw;
	if (!sWhy[0]) strcopy(sWhy, iWhy, "blocked");
	return false;
}

int Desk_SpawnProp(const char[] sModel, const float vecPos[3], float fYaw, bool bSolid, const int iColor[4]) {
	int e = CreateEntityByName("prop_dynamic_override");
	if (e == -1) return INVALID_ENT_REFERENCE;
	DispatchKeyValue(e, "model", sModel);
	DispatchKeyValue(e, "solid", bSolid ? "6" : "0");
	DispatchKeyValue(e, "targetname", "css_rts_desk");
	DispatchKeyValue(e, "disableshadows", "1");
	float vecAng[3];
	vecAng[1] = fYaw;
	DispatchKeyValueVector(e, "origin", vecPos);
	DispatchKeyValueVector(e, "angles", vecAng);
	DispatchSpawn(e);
	if (iColor[3] > 0) { SetEntityRenderMode(e, RENDER_TRANSCOLOR); SetEntityRenderColor(e, iColor[0], iColor[1], iColor[2], 255); }
	return EntIndexToEntRef(e);
}

// spawn missing desk sets (map start, round restarts clean plugin props up)
// v0.5.3.1: loose physics props (chairs, boxes, monitors) lying inside a desk set get removed so nothing sits in the desk
void Desks_ClearPhysics() {
	int e = -1;
	char sCls[32];
	while ((e = FindEntityByClassname(e, "prop_physics*")) != -1) {
		GetEntityClassname(e, sCls, sizeof(sCls));
		float v[3];
		GetEntPropVector(e, Prop_Data, "m_vecAbsOrigin", v);
		for (int d=0; d<g_iDesks; d++) {
			if (!g_bDeskOk[d] || FloatAbs(v[2] - g_vecDeskWall[d][2]) > 70.0) continue;
			// desk-local coordinates
			float y = DegToRad(g_fDeskYaw[d]), dx = v[0] - g_vecDeskWall[d][0], dy = v[1] - g_vecDeskWall[d][1];
			float fOut = dx * Cosine(y) + dy * Sine(y), fSide = dx * Sine(y) - dy * Cosine(y);
			if (fOut > -4.0 && fOut < 80.0 && FloatAbs(fSide) < 44.0) { RemoveEntity(e); break; }
		}
	}
}

void Desks_Ensure() {
	Desks_ClearPhysics();
	for (int d=0; d<g_iDesks; d++) {
		if (!g_bDeskOk[d]) continue;
		if (EntRefToEntIndex(g_iDeskProp[d][0]) > 0) continue;
		for (int k=1; k<DESK_PROPS; k++) { int e = EntRefToEntIndex(g_iDeskProp[d][k]); if (e > 0) RemoveEntity(e); }
		float p[3], p2[3];
		int iNone[4], iTeam[4];
		iTeam = g_iDeskTeam[d] == CS_TEAM_CT ? view_as<int>({150, 190, 255, 255}) : view_as<int>({255, 190, 130, 255});
		Desk_LocalFloor(d, 0.0, 20.0, 20.0, p);  g_iDeskProp[d][0] = Desk_SpawnProp(DESK_MODEL, p, g_fDeskYaw[d], true, iNone);
		Desk_LocalFloor(d, 0.0, 20.0, 40.0, p); p2 = p; Desk_Local(d, 4.0, 12.0, 0.0, p); p[2] = p2[2];  g_iDeskProp[d][1] = Desk_SpawnProp(DESK_MONITOR, p, g_fDeskYaw[d], false, iNone);
		Desk_Local(d, 4.0, 28.0, 0.0, p); p[2] = p2[2];  g_iDeskProp[d][2] = Desk_SpawnProp(DESK_KEYBOARD, p, g_fDeskYaw[d], false, iNone);
		Desk_Local(d, -22.0, 22.0, 0.0, p); p[2] = p2[2]; g_iDeskProp[d][3] = Desk_SpawnProp(DESK_PHONE, p, g_fDeskYaw[d] + 20.0, false, iNone);
		Desk_LocalFloor(d, 0.0, 58.0, 0.0, p);   g_iDeskProp[d][4] = Desk_SpawnProp(DESK_CHAIR, p, g_fDeskYaw[d] + 180.0, false, iTeam);
	}
}

public Action cmdDebugDesks(int iClient, int iArgs) {
	iClient = ResolveClient(iClient);
	if (!HasRTSAccess(iClient)) return Plugin_Handled;
	for (int d=0; d<g_iDesks; d++) {
		int s = g_iDeskSeat[d];
		ReplyToCommand(iClient, "DESK %s %s %s wall %.0f %.0f %.0f yaw %.0f seat %d (%.0f %.0f) owner %d props %d ok %d %s",
			g_sDeskId[d], g_iDeskTeam[d] == CS_TEAM_CT ? "CT" : "T", g_bDeskOffice[d] ? "office" : "base",
			g_vecDeskWall[d][0], g_vecDeskWall[d][1], g_vecDeskWall[d][2], g_fDeskYaw[d], s,
			s >= 0 ? g_vecSeat[s][0] : 0.0, s >= 0 ? g_vecSeat[s][1] : 0.0, s >= 0 ? g_iSeatOwner[s] : -2,
			EntRefToEntIndex(g_iDeskProp[d][0]) > 0, g_bDeskOk[d], g_sDeskWhy[d]);
	}
	for (int f=0; f<g_iFlee; f++) ReplyToCommand(iClient, "FLEE %s %.0f %.0f %.0f", g_iFleeTeam[f] == CS_TEAM_CT ? "CT" : "T", g_vecFlee[f][0], g_vecFlee[f][1], g_vecFlee[f][2]);
	return Plugin_Handled;
}

public Action cmdDebugDeskFit(int iClient, int iArgs) {
	iClient = ResolveClient(iClient);
	if (!HasRTSAccess(iClient) || iArgs < 3) return Plugin_Handled;
	if (g_iDesks >= MAX_DESKS) return Plugin_Handled;
	int d = g_iDesks;   // scratch slot (not counted)
	float a[3], w[3], y;
	a[0] = GetCmdArgFloat(1); a[1] = GetCmdArgFloat(2); a[2] = GetCmdArgFloat(3);
	float fHint = iArgs >= 4 ? GetCmdArgFloat(4) : -1.0;
	char sWhy[32];
	bool bOk = Desk_Fit(d, a, fHint, w, y, sWhy, sizeof(sWhy));
	ReplyToCommand(iClient, "FIT %.0f %.0f %.0f -> ok %d wall %.0f %.0f %.0f yaw %.0f %s", a[0], a[1], a[2], bOk, w[0], w[1], w[2], y, sWhy);
	return Plugin_Handled;
}

// try the anchor + hint first, then nearby points (rings of 48u) and the other wall directions
bool Desk_FitFree(int d, const float vecAnchor[3]) {
	bool bOk;
	float z = Desk_FloorZ(vecAnchor, bOk);
	if (!bOk || FloatAbs(z - g_vecDeskAnchor[d][2]) > 16.0) { strcopy(g_sDeskWhy[d], sizeof(g_sDeskWhy[]), "anchor has no floor"); return false; }
	g_vecDeskWall[d] = vecAnchor; g_vecDeskWall[d][2] = z;
	g_fDeskYaw[d] = g_fDeskYawHint[d];
	return Desk_CheckAt(d, g_sDeskWhy[d], sizeof(g_sDeskWhy[]));
}

bool Desk_FitSearch(int d) {
	float a[3];
	char sFirst[32];
	if (g_bDeskFree[d]) {
		if (Desk_FitFree(d, g_vecDeskAnchor[d])) { strcopy(g_sDeskWhy[d], sizeof(g_sDeskWhy[]), "freestanding"); return true; }
		strcopy(sFirst, sizeof(sFirst), g_sDeskWhy[d]);
		for (int r=1; r<=3; r++) for (int k=0; k<8; k++) {
			a = g_vecDeskAnchor[d];
			a[0] += Cosine(DegToRad(k * 45.0)) * 32.0 * r; a[1] += Sine(DegToRad(k * 45.0)) * 32.0 * r;
			if (Desk_FitFree(d, a)) { FormatEx(g_sDeskWhy[d], sizeof(g_sDeskWhy[]), "freestanding, moved %du (%s)", 32 * r, sFirst); return true; }
		}
		strcopy(g_sDeskWhy[d], sizeof(g_sDeskWhy[]), sFirst);
		return false;
	}
	if (Desk_Fit(d, g_vecDeskAnchor[d], g_fDeskYawHint[d], g_vecDeskWall[d], g_fDeskYaw[d], g_sDeskWhy[d], sizeof(g_sDeskWhy[]))) return true;
	strcopy(sFirst, sizeof(sFirst), g_sDeskWhy[d]);
	for (int r=1; r<=4; r++) {
		for (int k=0; k<8; k++) {
			float ang = DegToRad(k * 45.0);
			a = g_vecDeskAnchor[d];
			a[0] += Cosine(ang) * 48.0 * r; a[1] += Sine(ang) * 48.0 * r;
			for (int y=0; y<5; y++) {
				float fHint = y == 0 ? g_fDeskYawHint[d] : (y - 1) * 90.0;
				if (y > 0 && g_fDeskYawHint[d] >= 0.0 && FloatAbs(AngleDiff(fHint, g_fDeskYawHint[d])) < 1.0) continue;
				if (y == 0 && fHint < 0.0) continue;
				if (Desk_Fit(d, a, fHint, g_vecDeskWall[d], g_fDeskYaw[d], g_sDeskWhy[d], sizeof(g_sDeskWhy[]))) {
					FormatEx(g_sDeskWhy[d], sizeof(g_sDeskWhy[]), "moved %du (%s)", 48 * r, sFirst);
					return true;
				}
			}
		}
	}
	strcopy(g_sDeskWhy[d], sizeof(g_sDeskWhy[]), sFirst);
	return false;
}

int Desks_FindId(const char[] sId) {
	for (int d=0; d<g_iDesks; d++) if (StrEqual(g_sDeskId[d], sId, false)) return d;
	return -1;
}

// v0.5.4 planning: per nav area, is there a roof (non-sky ceiling) above? -> data/css_rts_roof_<map>.txt
public Action cmdDebugRoofMap(int iClient, int iArgs) {
	iClient = ResolveClient(iClient);
	if (!HasRTSAccess(iClient)) return Plugin_Handled;
	char sMap[64], sPath[PLATFORM_MAX_PATH];
	GetCurrentMap(sMap, sizeof(sMap));
	BuildPath(Path_SM, sPath, sizeof(sPath), "data/css_rts_roof_%s.txt", sMap);
	File f = OpenFile(sPath, "w");
	if (!f) return Plugin_Handled;
	int nRoof;
	for (int a=0; a<g_iNavAreas; a++) {
		float c[3], e[3];
		Nav_Center(a, c);
		c[2] += 40.0;
		e = c; e[2] += 2000.0;
		TR_TraceRayFilter(c, e, MASK_SOLID_BRUSHONLY, RayType_EndPoint, TraceFilter_CamWorld);
		float h = 2000.0;
		int iSky = 1;
		if (TR_DidHit()) {
			float p[3]; TR_GetEndPosition(p);
			h = p[2] - c[2];
			iSky = (TR_GetSurfaceFlags() & SURF_SKY) ? 1 : 0;
		}
		char sSurf[64] = "-";
		if (TR_DidHit()) TR_GetSurfaceName(null, sSurf, sizeof(sSurf));
		if (!iSky) nRoof++;
		f.WriteLine("%d %.0f %.0f %.0f %.0f %d %s", a, c[0], c[1], c[2] - 40.0, h, iSky, sSurf);
		// wall probes: 8 directions at knee and head height; both hit within 300u -> "W x y"
		for (int k=0; k<8; k++) {
			float fA = DegToRad(k * 45.0), e1[3], e2[3], c2[3], p1[3], p2[3];
			c2 = c; c2[2] += 30.0;
			e1[0] = c[0] + Cosine(fA) * 300.0; e1[1] = c[1] + Sine(fA) * 300.0; e1[2] = c[2];
			e2 = e1; e2[2] = c2[2];
			TR_TraceRayFilter(c, e1, MASK_PLAYERSOLID, RayType_EndPoint, TraceFilter_CamWorld);
			if (!TR_DidHit()) continue;
			TR_GetEndPosition(p1);
			TR_TraceRayFilter(c2, e2, MASK_PLAYERSOLID, RayType_EndPoint, TraceFilter_CamWorld);
			if (!TR_DidHit()) continue;
			TR_GetEndPosition(p2);
			f.WriteLine("W %.0f %.0f %.0f", p1[0], p1[1], p1[2] - 40.0);
		}
	}
	delete f;
	ReplyToCommand(iClient, "[RTS] roofmap: %d areas, %d roofed -> %s", g_iNavAreas, nRoof, sPath);
	return Plugin_Handled;
}

public bool TraceFilter_SliceAll(int iEntity, int iMask) {
	return iEntity == 0 || iEntity > MaxClients;
}

// top-down slice: per cell '#' world/static, 'D' door, 'o' our desk props, 'H' our HQ, '.' free; plus 'f' = no floor below
public Action cmdDebugSlice(int iClient, int iArgs) {
	iClient = ResolveClient(iClient);
	if (!HasRTSAccess(iClient) || iArgs < 4) return Plugin_Handled;
	char sName[32]; GetCmdArg(1, sName, sizeof(sName));
	float c[3]; c[0] = GetCmdArgFloat(2); c[1] = GetCmdArgFloat(3); c[2] = GetCmdArgFloat(4);
	float fHalf = iArgs >= 5 ? GetCmdArgFloat(5) : 192.0, fStep = iArgs >= 6 ? GetCmdArgFloat(6) : 6.0;
	int n = RoundToFloor(fHalf * 2.0 / fStep);
	if (n > 160) n = 160;
	char sMap[64], sPath[PLATFORM_MAX_PATH];
	GetCurrentMap(sMap, sizeof(sMap));
	BuildPath(Path_SM, sPath, sizeof(sPath), "data/css_rts_slice_%s.txt", sMap);
	File f = OpenFile(sPath, "a");
	if (f == null) return Plugin_Handled;
	f.WriteLine("S %s %.0f %.0f %.0f %.1f %d", sName, c[0] - fHalf, c[1] + fHalf, c[2], fStep, n);
	char sRow[164], sCls[32], sTn[32];
	static float mn[3] = {-1.0, -1.0, -1.0}, mx[3] = {1.0, 1.0, 1.0};
	for (int r=0; r<n; r++) {
		for (int k=0; k<n; k++) {
			float p[3], q[3];
			p[0] = c[0] - fHalf + (k + 0.5) * fStep; p[1] = c[1] + fHalf - (r + 0.5) * fStep;
			char ch = '.';
			for (int hz=0; hz<2 && ch == '.'; hz++) {
				p[2] = c[2] + (hz == 0 ? 30.0 : 60.0);
				q = p; q[2] += 2.0;
				TR_TraceHullFilter(p, q, mn, mx, MASK_PLAYERSOLID, TraceFilter_SliceAll);
				if (!TR_DidHit() && !TR_StartSolid()) continue;
				int e = TR_GetEntityIndex();
				if (e <= 0) { ch = '#'; break; }
				GetEntityClassname(e, sCls, sizeof(sCls));
				GetEntPropString(e, Prop_Data, "m_iName", sTn, sizeof(sTn));
				if (StrContains(sCls, "door") != -1) ch = 'D';
				else if (StrEqual(sTn, "css_rts_desk")) ch = 'o';
				else if (StrEqual(sTn, "css_rts_hq") || StrContains(sTn, "css_rts_terminal") == 0) ch = 'H';
				else if (StrContains(sCls, "prop_physics") == 0) ch = 'p';
				else ch = '#';
			}
			if (ch == '.') {
				// floor within 24u below?
				float a[3], b[3]; a = p; a[2] = c[2] + 16.0; b = p; b[2] = c[2] - 24.0;
				TR_TraceRayFilter(a, b, MASK_PLAYERSOLID_BRUSHONLY, RayType_EndPoint, TraceFilter_DeskWorld);
				if (!TR_DidHit()) ch = 'f';
			}
			sRow[k] = ch;
		}
		sRow[n] = 0;
		f.WriteLine("%s", sRow);
	}
	delete f;
	ReplyToCommand(iClient, "[RTS] slice %s written (%dx%d)", sName, n, n);
	return Plugin_Handled;
}
