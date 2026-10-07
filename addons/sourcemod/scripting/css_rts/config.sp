// css_rts/config.sp -- per-map KeyValues config: addons/sourcemod/configs/css_rts/<map>.cfg
//
// "css_rts_map"
// {
//     "camera"   { "mins" "x y z"  "maxs" "x y z" }      // global commander camera bounds
//     "CT" / "T"
//     {
//         "post_origin"     "x y z"      // terminal position (snapped to floor at spawn)
//         "post_angles"     "0 yaw 0"
//         "terminal_model"  "models/..." // optional
//         "hq_origin"       "x y z"      // HQ (M4)
//         "hq_angles"       "0 yaw 0"
//         "camera_mins" / "camera_maxs"  // optional per-team override
//         "camera_start"    "x y z"      // optional initial camera focus (default post_origin)
//     }
// }
// A team without post_origin gets an automatic post (FindPostSpot, near its spawns).

#define DEFAULT_TERMINAL_MODEL	"models/props_combine/breenconsole.mdl"
#define FALLBACK_TERMINAL_MODEL	"models/props/cs_office/computer.mdl"

enum struct TeamPost {
	bool bValid;
	bool bFromConfig;
	float vecOrigin[3];
	float vecAngles[3];
	bool bHasHQ;
	float vecHQOrigin[3];
	float vecHQAngles[3];
	bool bHasCamBounds;
	float vecCamMins[3];
	float vecCamMaxs[3];
	bool bHasCamStart;
	float vecCamStart[3];
	char sModel[PLATFORM_MAX_PATH];
}

TeamPost g_ePost[4];
bool g_bMapConfigLoaded;
char g_sMapConfigPath[PLATFORM_MAX_PATH];
bool g_bHasCamBounds;
float g_vecCamMins[3];
float g_vecCamMaxs[3];

int TeamFromName(const char[] sName) {
	if (StrEqual(sName, "CT", false) || StrEqual(sName, "3")) return CS_TEAM_CT;
	if (StrEqual(sName, "T", false) || StrEqual(sName, "2")) return CS_TEAM_T;
	return CS_TEAM_NONE;
}

void TeamShortName(int iTeam, char[] sOut, int iLen) {
	strcopy(sOut, iLen, iTeam == CS_TEAM_CT ? "CT" : (iTeam == CS_TEAM_T ? "T" : "?"));
}

bool KvGetVec(KeyValues hKv, const char[] sKey, float vecOut[3]) {
	char sBuf[96];
	hKv.GetString(sKey, sBuf, sizeof(sBuf));
	TrimString(sBuf);
	if (!sBuf[0]) return false;
	char sParts[3][32];
	if (ExplodeString(sBuf, " ", sParts, 3, 32) != 3) {
		LogError("[RTS] %s: key \"%s\" needs 3 numbers, got \"%s\"", g_sMapConfigPath, sKey, sBuf);
		return false;
	}
	for (int i=0; i<3; i++) vecOut[i] = StringToFloat(sParts[i]);
	return true;
}

void GetMapConfigName(char[] sMap, int iLen) {
	GetCurrentMap(sMap, iLen);
	GetMapDisplayName(sMap, sMap, iLen);
}

void LoadMapConfig() {
	for (int t=0; t<4; t++) {
		TeamPost eEmpty;
		g_ePost[t] = eEmpty;
	}
	g_bMapConfigLoaded = false;
	g_bHasCamBounds = false;

	char sMap[PLATFORM_MAX_PATH];
	GetMapConfigName(sMap, sizeof(sMap));
	BuildPath(Path_SM, g_sMapConfigPath, sizeof(g_sMapConfigPath), "configs/css_rts/%s.cfg", sMap);

	KeyValues hKv = new KeyValues("css_rts_map");
	if (FileExists(g_sMapConfigPath) && hKv.ImportFromFile(g_sMapConfigPath)) {
		g_bMapConfigLoaded = true;
		if (hKv.JumpToKey("camera")) {
			g_bHasCamBounds = KvGetVec(hKv, "mins", g_vecCamMins) && KvGetVec(hKv, "maxs", g_vecCamMaxs);
			hKv.GoBack();
		}
		static const char sTeams[][] = {"T", "CT"};
		for (int i=0; i<sizeof(sTeams); i++) {
			if (!hKv.JumpToKey(sTeams[i])) continue;
			int t = TeamFromName(sTeams[i]);
			TeamPost ePost;
			ePost.bValid = ePost.bFromConfig = KvGetVec(hKv, "post_origin", ePost.vecOrigin);
			KvGetVec(hKv, "post_angles", ePost.vecAngles);
			ePost.bHasHQ = KvGetVec(hKv, "hq_origin", ePost.vecHQOrigin);
			KvGetVec(hKv, "hq_angles", ePost.vecHQAngles);
			ePost.bHasCamBounds = KvGetVec(hKv, "camera_mins", ePost.vecCamMins) && KvGetVec(hKv, "camera_maxs", ePost.vecCamMaxs);
			ePost.bHasCamStart = KvGetVec(hKv, "camera_start", ePost.vecCamStart);
			hKv.GetString("terminal_model", ePost.sModel, sizeof(ePost.sModel));
			g_ePost[t] = ePost;
			hKv.GoBack();
		}
		hKv.Rewind();
		Workers_LoadConfig(hKv);
		hKv.Rewind();
		Desks_LoadConfig(hKv);
		LogMessage("Loaded map config %s", g_sMapConfigPath);
	} else {
		Workers_LoadConfig(null);
		Desks_LoadConfig(null);
		LogMessage("No map config at %s; using automatic command posts", g_sMapConfigPath);
	}
	delete hKv;

	for (int t=CS_TEAM_T; t<=CS_TEAM_CT; t++) {
		if (!g_ePost[t].sModel[0]) {
			strcopy(g_ePost[t].sModel, sizeof(TeamPost::sModel), DEFAULT_TERMINAL_MODEL);
		}
		if (!FileExists(g_ePost[t].sModel, true)) {
			LogError("Terminal model %s not found; falling back to %s", g_ePost[t].sModel, FALLBACK_TERMINAL_MODEL);
			strcopy(g_ePost[t].sModel, sizeof(TeamPost::sModel), FALLBACK_TERMINAL_MODEL);
		}
		if (!g_ePost[t].bValid) {
			float vecPos[3], fYaw;
			if (FindPostSpot(t, vecPos, fYaw, false)) {
				g_ePost[t].bValid = true;
				g_ePost[t].vecOrigin = vecPos;
				g_ePost[t].vecAngles[1] = fYaw;
			} else {
				LogError("No command post for team %d on this map (no config and auto-placement failed)", t);
			}
		}
		if (g_ePost[t].bValid && !g_ePost[t].bHasHQ) {
			// Default HQ: 128u behind the terminal
			float vecFwd[3];
			GetAngleVectors(g_ePost[t].vecAngles, vecFwd, NULL_VECTOR, NULL_VECTOR);
			for (int i=0; i<3; i++) g_ePost[t].vecHQOrigin[i] = g_ePost[t].vecOrigin[i] - 128.0*vecFwd[i];
			g_ePost[t].vecHQAngles = g_ePost[t].vecAngles;
		}
	}

	if (!g_bHasCamBounds) {
		AutoCameraBounds(g_vecCamMins, g_vecCamMaxs);
		g_bHasCamBounds = true;
	}
}

// Camera bounds for a team (per-team override > global)
void GetCameraBounds(int iTeam, float vecMins[3], float vecMaxs[3]) {
	if (CS_TEAM_T <= iTeam <= CS_TEAM_CT && g_ePost[iTeam].bHasCamBounds) {
		vecMins = g_ePost[iTeam].vecCamMins;
		vecMaxs = g_ePost[iTeam].vecCamMaxs;
	} else {
		vecMins = g_vecCamMins;
		vecMaxs = g_vecCamMaxs;
	}
}

// Fallback bounds: all spawn points of both teams +-1536u horizontally, -512/+1024u vertically
void AutoCameraBounds(float vecMins[3], float vecMaxs[3]) {
	vecMins = {999999.0, 999999.0, 999999.0};
	vecMaxs = {-999999.0, -999999.0, -999999.0};
	int iFound;
	static const char sClasses[][] = {"info_player_terrorist", "info_player_counterterrorist"};
	for (int c=0; c<sizeof(sClasses); c++) {
		int iEnt = -1;
		while ((iEnt = FindEntityByClassname(iEnt, sClasses[c])) != -1) {
			float vecPos[3];
			GetEntPropVector(iEnt, Prop_Data, "m_vecAbsOrigin", vecPos);
			for (int i=0; i<3; i++) {
				if (vecPos[i] < vecMins[i]) vecMins[i] = vecPos[i];
				if (vecPos[i] > vecMaxs[i]) vecMaxs[i] = vecPos[i];
			}
			iFound++;
		}
	}
	if (!iFound) {
		vecMins = {-4096.0, -4096.0, -1024.0};
		vecMaxs = {4096.0, 4096.0, 2048.0};
		return;
	}
	vecMins[0] -= 1536.0; vecMins[1] -= 1536.0; vecMins[2] -= 512.0;
	vecMaxs[0] += 1536.0; vecMaxs[1] += 1536.0; vecMaxs[2] += 1024.0;
}
