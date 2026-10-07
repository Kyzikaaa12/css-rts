// css_rts/nav.sp -- area-graph pathing for plugin NPCs (workers, later combat units)
// Graph file: configs/css_rts/nav/<map>.txt  (scripts/nav2graph.py from the map's .nav)
// line: id x1 y1 x2 y2 z1 z2 n1,n2,...

#define NAV_MAX_AREAS	4096
#define NAV_MAX_EDGES	16384
#define NAV_MAX_ID		32768

int g_iNavAreas;
float g_fNavX1[NAV_MAX_AREAS], g_fNavY1[NAV_MAX_AREAS], g_fNavX2[NAV_MAX_AREAS], g_fNavY2[NAV_MAX_AREAS], g_fNavZ[NAV_MAX_AREAS];
int g_iNavNbrStart[NAV_MAX_AREAS], g_iNavNbrCount[NAV_MAX_AREAS];
int g_iNavNbr[NAV_MAX_EDGES];
int g_iNavEdges;
bool g_bNavLoaded;

int iIdToIdx[NAV_MAX_ID];

// A* scratch
float g_fNavG[NAV_MAX_AREAS], g_fNavF[NAV_MAX_AREAS];
int g_iNavFrom[NAV_MAX_AREAS];
int g_iNavState[NAV_MAX_AREAS]; // 0 new, 1 open, 2 closed

bool Nav_Load() {
	g_bNavLoaded = false;
	g_iNavAreas = 0;
	g_iNavEdges = 0;
	char sMap[PLATFORM_MAX_PATH], sPath[PLATFORM_MAX_PATH];
	GetMapConfigName(sMap, sizeof(sMap));
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/css_rts/nav/%s.txt", sMap);
	File hFile = OpenFile(sPath, "r");
	if (hFile == null) {
		LogMessage("No nav graph %s; NPCs walk in straight lines", sPath);
		return false;
	}
	for (int i=0; i<NAV_MAX_ID; i++) iIdToIdx[i] = -1;
	// pass 1: areas; neighbour ids kept as raw ids, remapped after
	char sLine[1024], sParts[8][512];
	while (hFile.ReadLine(sLine, sizeof(sLine)) && g_iNavAreas < NAV_MAX_AREAS) {
		TrimString(sLine);
		if (!sLine[0] || sLine[0] == '/') continue;
		if (ExplodeString(sLine, " ", sParts, 8, 512) < 8) continue;
		int iId = StringToInt(sParts[0]);
		if (iId < 0 || iId >= NAV_MAX_ID) continue;
		int a = g_iNavAreas++;
		iIdToIdx[iId] = a;
		g_fNavX1[a] = StringToFloat(sParts[1]); g_fNavY1[a] = StringToFloat(sParts[2]);
		g_fNavX2[a] = StringToFloat(sParts[3]); g_fNavY2[a] = StringToFloat(sParts[4]);
		g_fNavZ[a] = 0.5 * (StringToFloat(sParts[5]) + StringToFloat(sParts[6]));
		g_iNavNbrStart[a] = g_iNavEdges;
		g_iNavNbrCount[a] = 0;
		if (sParts[7][0] != '-') {
			char sNbr[64][8];
			int n = ExplodeString(sParts[7], ",", sNbr, 64, 8);
			for (int k=0; k<n && g_iNavEdges < NAV_MAX_EDGES; k++) {
				g_iNavNbr[g_iNavEdges++] = StringToInt(sNbr[k]);
				g_iNavNbrCount[a]++;
			}
		}
	}
	delete hFile;
	for (int e=0; e<g_iNavEdges; e++) {
		int iId = g_iNavNbr[e];
		g_iNavNbr[e] = (0 <= iId < NAV_MAX_ID) ? iIdToIdx[iId] : -1;
	}
	g_bNavLoaded = g_iNavAreas > 0;
	LogMessage("Nav graph %s: %d areas, %d edges", sPath, g_iNavAreas, g_iNavEdges);
	return g_bNavLoaded;
}

void Nav_Center(int a, float vec[3]) {
	vec[0] = 0.5 * (g_fNavX1[a] + g_fNavX2[a]);
	vec[1] = 0.5 * (g_fNavY1[a] + g_fNavY2[a]);
	vec[2] = g_fNavZ[a];
}

// Area containing the point (closest in z), else nearest by centre distance
int Nav_NearestArea(const float vecPos[3]) {
	int iBest = -1;
	float fBest = 999999.0;
	for (int a=0; a<g_iNavAreas; a++) {
		if (vecPos[0] >= g_fNavX1[a] - 1.0 && vecPos[0] <= g_fNavX2[a] + 1.0 && vecPos[1] >= g_fNavY1[a] - 1.0 && vecPos[1] <= g_fNavY2[a] + 1.0) {
			float dz = FloatAbs(vecPos[2] - g_fNavZ[a]);
			if (dz < 80.0 && dz < fBest) { fBest = dz; iBest = a; }
		}
	}
	if (iBest != -1) return iBest;
	fBest = 999999.0;
	for (int a=0; a<g_iNavAreas; a++) {
		float c[3];
		Nav_Center(a, c);
		float d = GetVectorDistance(c, vecPos) + 2.0 * FloatAbs(c[2] - vecPos[2]);
		if (d < fBest) { fBest = d; iBest = a; }
	}
	return iBest;
}

// Walkable floor under a click. A roof hit drops to the floor below. A step or crate that is in the nav stays.
void Cursor_DropToWalk(float vec[3]) {
	int iBest = -1;
	float fBest = 999999.0;
	for (int a = 0; a < g_iNavAreas; a++) {
		if (vec[0] < g_fNavX1[a] - 8.0 || vec[0] > g_fNavX2[a] + 8.0) continue;
		if (vec[1] < g_fNavY1[a] - 8.0 || vec[1] > g_fNavY2[a] + 8.0) continue;
		if (g_fNavZ[a] > vec[2] + 48.0) continue;
		float dz = vec[2] - g_fNavZ[a];
		if (dz < fBest) { fBest = dz; iBest = a; }
	}
	if (iBest == -1) return;
	vec[2] = g_fNavZ[iBest];
}

// Nearest walkable spot whose floor is close to fZ. Used to get a worker off a roof.
bool Nav_NearestAtHeight(const float vecFrom[3], float fZ, float vecOut[3]) {
	int iBest = -1;
	float fBest = 999999.0;
	for (int a = 0; a < g_iNavAreas; a++) {
		if (FloatAbs(g_fNavZ[a] - fZ) > 72.0) continue;
		float dx = (g_fNavX1[a] + g_fNavX2[a]) * 0.5 - vecFrom[0];
		float dy = (g_fNavY1[a] + g_fNavY2[a]) * 0.5 - vecFrom[1];
		float d = dx * dx + dy * dy;
		if (d < fBest) { fBest = d; iBest = a; }
	}
	if (iBest == -1) return false;
	vecOut[0] = (g_fNavX1[iBest] + g_fNavX2[iBest]) * 0.5;
	vecOut[1] = (g_fNavY1[iBest] + g_fNavY2[iBest]) * 0.5;
	vecOut[2] = g_fNavZ[iBest];
	return true;
}

// True when vec is inside a nav area. Z is pulled onto that floor so a ledge or roof lip is not a floor.
bool Nav_Snap(float vec[3]) {
	int iBest = -1;
	float fBest = 999999.0;
	for (int a = 0; a < g_iNavAreas; a++) {
		if (vec[0] < g_fNavX1[a] - 4.0 || vec[0] > g_fNavX2[a] + 4.0) continue;
		if (vec[1] < g_fNavY1[a] - 4.0 || vec[1] > g_fNavY2[a] + 4.0) continue;
		float dz = FloatAbs(vec[2] - g_fNavZ[a]);
		if (dz > 72.0 || dz >= fBest) continue;
		fBest = dz;
		iBest = a;
	}
	if (iBest == -1) return false;
	vec[2] = g_fNavZ[iBest];
	return true;
}

float NavClamp(float v, float lo, float hi) {
	if (lo > hi) { float t = lo; lo = hi; hi = t; }
	return v < lo ? lo : (v > hi ? hi : v);
}

// Builds a path of points from vecStart to vecGoal into hPath (ArrayList of [3]). Returns false if unreachable.
bool Nav_BuildPath(const float vecStart[3], const float vecGoal[3], ArrayList hPath) {
	hPath.Clear();
	if (!g_bNavLoaded) {
		hPath.PushArray(vecGoal, 3);
		return true;
	}
	int s = Nav_NearestArea(vecStart), g = Nav_NearestArea(vecGoal);
	if (s == -1 || g == -1) return false;
	for (int a=0; a<g_iNavAreas; a++) { g_iNavState[a] = 0; g_iNavFrom[a] = -1; }
	float cg[3];
	Nav_Center(g, cg);
	g_fNavG[s] = 0.0;
	float cs[3];
	Nav_Center(s, cs);
	g_fNavF[s] = GetVectorDistance(cs, cg);
	g_iNavState[s] = 1;
	bool bFound = false;
	while (true) {
		int iCur = -1;
		float fBest = 999999999.0;
		for (int a=0; a<g_iNavAreas; a++) {
			if (g_iNavState[a] == 1 && g_fNavF[a] < fBest) { fBest = g_fNavF[a]; iCur = a; }
		}
		if (iCur == -1) break;
		if (iCur == g) { bFound = true; break; }
		g_iNavState[iCur] = 2;
		float cc[3];
		Nav_Center(iCur, cc);
		for (int k=0; k<g_iNavNbrCount[iCur]; k++) {
			int n = g_iNavNbr[g_iNavNbrStart[iCur] + k];
			if (n < 0 || g_iNavState[n] == 2) continue;
			float cn[3];
			Nav_Center(n, cn);
			float fG = g_fNavG[iCur] + GetVectorDistance(cc, cn);
			float fHigh = cn[2] - cg[2];
			if (fHigh > 48.0) fG += fHigh * 8.0;
			if (g_iNavState[n] == 1 && fG >= g_fNavG[n]) continue;
			g_fNavG[n] = fG;
			g_fNavF[n] = fG + GetVectorDistance(cn, cg);
			g_iNavFrom[n] = iCur;
			g_iNavState[n] = 1;
		}
	}
	if (!bFound) return false;
	// walk back g -> s, then emit portal points in forward order
	static int iChain[NAV_MAX_AREAS];
	int n = 0;
	for (int a=g; a!=-1 && n<sizeof(iChain); a=g_iNavFrom[a]) iChain[n++] = a;
	for (int i=n-1; i>0; i--) {
		int A = iChain[i], B = iChain[i-1];
		float p[3], cb[3];
		Nav_Center(B, cb);
		p[0] = NavClamp(cb[0], g_fNavX1[A] > g_fNavX1[B] ? g_fNavX1[A] : g_fNavX1[B], g_fNavX2[A] < g_fNavX2[B] ? g_fNavX2[A] : g_fNavX2[B]);
		p[1] = NavClamp(cb[1], g_fNavY1[A] > g_fNavY1[B] ? g_fNavY1[A] : g_fNavY1[B], g_fNavY2[A] < g_fNavY2[B] ? g_fNavY2[A] : g_fNavY2[B]);
		p[2] = g_fNavZ[B];
		hPath.PushArray(p, 3);
		hPath.PushArray(cb, 3);
	}
	hPath.PushArray(vecGoal, 3);
	return true;
}
