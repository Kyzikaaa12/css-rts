// css_rts/wheel.sp -- v0.5.3 Commander RADIAL WHEEL (css_rts_wheel).
// World-space sprites (env_sprite, $ignorez, transmitted only to the Commander) laid out on an
// ellipse ~20 u in front of the command camera. Each segment swaps between generated art variants:
// _n normal, _h hover, _d disabled (locked / too expensive / recharging), _o owned (research, check
// mark). Hover = cursor direction from the screen centre. Open: Ctrl (or F2) in the command view.
// LMB = pick, RMB = back / close. Art: scripts/gen_wheel_art.py -> materials/css_rts/wheel/.

#define WHEEL_SLOTS 17          // 16 tiles + hub
#define WHEEL_HUB 16
#define WHEEL_DIST 20.0

ConVar g_hCvarWheel;
int g_iWheelPage[MAXPLAYERS+1] = {-1, ...};   // -1 closed, 0 main, 1 research, 2 abilities
int g_iWheelHover[MAXPLAYERS+1] = {-1, ...};
int g_iWheelEnt[MAXPLAYERS+1][WHEEL_SLOTS];
char g_sWheelModel[MAXPLAYERS+1][WHEEL_SLOTS][40];
int g_iWheelOwner[2049];
int g_iWheelPicks;   // selftest / debug counter

char g_sWheelMain[][] = {"m_hire", "m_research", "m_abilities", "m_armory", "m_help", "m_soldier"};
char g_sWheelResearch[][] = {"r_nades", "r_pistols", "r_kevlar", "r_helmet", "r_smg", "r_rifle1", "r_rifle2", "r_heavy", "r_kit", "r_stims", "r_training"};
char g_sWheelAbility[][] = {"a_sweep", "a_smoke", "a_supply"};
char g_sWheelHubs[][] = {"hub_main", "hub_research", "hub_abilities"};

void Wheel_Init() {
	g_hCvarWheel = CreateConVar("css_rts_wheel", "0", "1 = EXPERIMENTAL radial wheel (world sprites; drew giant on 1024x576 in v0.5.3, off since v0.5.3.1); 0 = SM menus", _, true, 0.0, true, 1.0);
	RegConsoleCmd("sm_rts_wheel", cmdWheel, "Commander: open/close the radial wheel");
	RegConsoleCmd("sm_rts_debug_wheel", cmdDebugWheel, "<#userid|name> <open|page n|hover n|pick|close|state>: drive the wheel (selftest)");
	for (int i=1; i<=MaxClients; i++) for (int k=0; k<WHEEL_SLOTS; k++) g_iWheelEnt[i][k] = INVALID_ENT_REFERENCE;
}

void Wheel_PrecacheOne(const char[] sName) {
	char s[96];
	FormatEx(s, sizeof(s), "materials/css_rts/wheel/%s.vmt", sName);
	AddFileToDownloadsTable(s);
	PrecacheModel(s[10], true);
	FormatEx(s, sizeof(s), "materials/css_rts/wheel/%s.vtf", sName);
	AddFileToDownloadsTable(s);
}

void Wheel_PrecacheKey(const char[] sKey, bool bOwned) {
	char s[48];
	static const char sVar[][] = {"n", "h", "d", "o"};
	for (int v=0; v<(bOwned ? 4 : 3); v++) { FormatEx(s, sizeof(s), "%s_%s", sKey, sVar[v]); Wheel_PrecacheOne(s); }
}

void Wheel_MapStart() {
	if (!g_hCvarWheel.BoolValue) return;
	for (int k=0; k<sizeof(g_sWheelMain); k++) Wheel_PrecacheKey(g_sWheelMain[k], false);
	for (int k=0; k<sizeof(g_sWheelResearch); k++) Wheel_PrecacheKey(g_sWheelResearch[k], true);
	for (int k=0; k<sizeof(g_sWheelAbility); k++) Wheel_PrecacheKey(g_sWheelAbility[k], false);
	for (int k=0; k<sizeof(g_sWheelHubs); k++) Wheel_PrecacheOne(g_sWheelHubs[k]);
	AddFileToDownloadsTable("materials/css_rts/backdrop.vmt");
	AddFileToDownloadsTable("materials/css_rts/backdrop.vtf");
	PrecacheModel("css_rts/backdrop.vmt", true);
	for (int i=1; i<=MaxClients; i++) { g_iWheelPage[i] = -1; for (int k=0; k<WHEEL_SLOTS; k++) g_iWheelEnt[i][k] = INVALID_ENT_REFERENCE; }
}

bool Wheel_IsOpen(int c) { return g_iWheelPage[c] != -1; }

bool Wheel_Enabled(int c) {
	return g_hCvarWheel.BoolValue && c > 0 && g_eCommander[c].bEnabled && GetCommanderTeam(c) != 0;
}

int Wheel_Count(int iPage) {
	switch (iPage) {
		case 0: return sizeof(g_sWheelMain);
		case 1: return sizeof(g_sWheelResearch);
		case 2: return sizeof(g_sWheelAbility);
	}
	return 0;
}

void Wheel_Key(int iPage, int i, char[] s, int n) {
	switch (iPage) {
		case 0: strcopy(s, n, g_sWheelMain[i]);
		case 1: strcopy(s, n, g_sWheelResearch[i]);
		case 2: strcopy(s, n, g_sWheelAbility[i]);
	}
}

int Wheel_Unlock(int i) { return Unlock_FindKey(g_sWheelResearch[i][2]); }

// 'n' normal, 'd' disabled, 'o' owned
int Wheel_State(int c, int iPage, int i) {
	int t = GetCommanderTeam(c);
	if (!t) return 'd';
	if (iPage == 0) {
		if (i == 0) return Worker_CanHire(c, true) ? 'n' : 'd';
		if (i == 2) return g_hCvarAbilities.BoolValue ? 'n' : 'd';
		if (i == 3) return g_hCvarStockpile.BoolValue ? 'n' : 'd';
		return 'n';
	}
	if (iPage == 1) {
		int u = Wheel_Unlock(i);
		if (u == -1) return 'd';
		if (g_bUnlocked[t][u]) return 'o';
		int r = g_eUnlock[u].iRequires;
		if ((r != -1 && !g_bUnlocked[t][r]) || g_iIntel[t] < Unlock_Cost(u)) return 'd';
		return 'n';
	}
	if (iPage == 2) return Ability_Ready(t, view_as<AbilityId>(i)) ? 'n' : 'd';
	return 'd';
}

// layout: ellipse radii in screen-HEIGHT units (x is divided by the aspect ratio)
void Wheel_Radii(int iPage, float &fRX, float &fRY) {
	switch (iPage) {
		case 1: { fRX = 0.54; fRY = 0.364; }
		case 2: { fRX = 0.40; fRY = 0.26; }
		default: { fRX = 0.46; fRY = 0.30; }
	}
}

void Wheel_ScreenPos(int c, int iPage, int i, float fOut[2]) {
	int n = Wheel_Count(iPage);
	float a = -FLOAT_PI / 2.0 + 2.0 * FLOAT_PI * i / n;
	float fRX, fRY;
	Wheel_Radii(iPage, fRX, fRY);
	fOut[0] = 0.5 + Cosine(a) * fRX / g_eCommander[c].fAspectRatio;
	fOut[1] = 0.5 + Sine(a) * fRY;
}

// index of the segment under the cursor (-1 = centre dead zone)
int Wheel_HoverFromMouse(int c, int iPage, const float fMouse[2]) {
	float dx = (fMouse[0] - 0.5) * g_eCommander[c].fAspectRatio, dy = fMouse[1] - 0.5;
	if (SquareRoot(dx*dx + dy*dy) < 0.10) return -1;
	float fRX, fRY;
	Wheel_Radii(iPage, fRX, fRY);
	float a = ArcTangent2(dy / fRY, dx / fRX);   // angle on the (normalised) ellipse
	int n = Wheel_Count(iPage);
	float fStep = 2.0 * FLOAT_PI / n;
	int k = RoundToNearest((a + FLOAT_PI / 2.0) / fStep);
	k = ((k % n) + n) % n;
	return k;
}

public Action SDKHookCB_WheelTransmit(int iEnt, int iClient) {
	return g_iWheelOwner[iEnt] == iClient ? Plugin_Continue : Plugin_Handled;
}

void Wheel_KillSlot(int c, int k) {
	int iEnt = EntRefToEntIndex(g_iWheelEnt[c][k]);
	if (iEnt != INVALID_ENT_REFERENCE && iEnt > 0) RemoveEntity(iEnt);
	g_iWheelEnt[c][k] = INVALID_ENT_REFERENCE;
	g_sWheelModel[c][k][0] = '\0';
}

// place (or re-skin) one sprite
void Wheel_SetSprite(int c, int k, const char[] sName, const float vecPos[3], float fScale) {
	int iEnt = EntRefToEntIndex(g_iWheelEnt[c][k]);
	if (iEnt != INVALID_ENT_REFERENCE && iEnt > 0 && StrEqual(g_sWheelModel[c][k], sName)) {
		TeleportEntity(iEnt, vecPos, NULL_VECTOR, NULL_VECTOR);
		return;
	}
	Wheel_KillSlot(c, k);
	iEnt = CreateEntityByName("env_sprite");
	if (iEnt == -1) return;
	char sModel[64], sScale[16];
	FormatEx(sModel, sizeof(sModel), "css_rts/wheel/%s.vmt", sName);
	FloatToString(fScale, sScale, sizeof(sScale));
	DispatchKeyValue(iEnt, "model", sModel);
	DispatchKeyValue(iEnt, "rendermode", "2");
	DispatchKeyValue(iEnt, "renderamt", "255");
	DispatchKeyValue(iEnt, "rendercolor", "255 255 255");
	DispatchKeyValue(iEnt, "scale", sScale);
	DispatchKeyValue(iEnt, "spawnflags", "1");
	DispatchKeyValue(iEnt, "targetname", "css_rts_wheel");
	DispatchKeyValueVector(iEnt, "origin", vecPos);
	DispatchSpawn(iEnt);
	AcceptEntityInput(iEnt, "ShowSprite");
	g_iWheelOwner[iEnt] = c;
	SDKHook(iEnt, SDKHook_SetTransmit, SDKHookCB_WheelTransmit);
	g_iWheelEnt[c][k] = EntIndexToEntRef(iEnt);
	strcopy(g_sWheelModel[c][k], sizeof(g_sWheelModel[][]), sName);
}

void Wheel_Close(int c) {
	if (g_iWheelPage[c] == -1) return;
	g_iWheelPage[c] = -1;
	g_iWheelHover[c] = -1;
	for (int k=0; k<WHEEL_SLOTS; k++) Wheel_KillSlot(c, k);
}

void Wheel_Open(int c, int iPage=0) {
	if (!Wheel_Enabled(c)) return;
	Ghost_Stop(c);
	g_iAbilityTarget[c] = -1;
	if (g_iWheelPage[c] != iPage) for (int k=0; k<WHEEL_SLOTS; k++) Wheel_KillSlot(c, k);
	g_iWheelPage[c] = iPage;
	g_iWheelHover[c] = -1;
	g_eCommander[c].fMouse[0] = 0.5;   // cursor to the centre: every direction is one flick away
	g_eCommander[c].fMouse[1] = 0.5;
}

void Wheel_Toggle(int c) {
	if (Wheel_IsOpen(c)) Wheel_Close(c); else Wheel_Open(c, 0);
}

// world position of a screen point on the plane WHEEL_DIST in front of the camera
void Wheel_World(int c, const float vecCam[3], const float vecView[3], float sx, float sy, float vecOut[3]) {
	float fM[2], vecDir[3], vecV[3];
	fM[0] = sx; fM[1] = sy;
	vecV = vecView;
	GetCursorVector(c, vecV, fM, vecDir);
	ScaleVector(vecDir, WHEEL_DIST);
	AddVectors(vecCam, vecDir, vecOut);
}

// hovered-item description for the bottom action line
void Wheel_Describe(int c, int iPage, int i, char[] s, int n) {
	int t = GetCommanderTeam(c);
	int st = Wheel_State(c, iPage, i);
	if (iPage == 0) {
		static const char sMain[][] = {"Hire worker", "Research", "Abilities", "Armory: restock", "Controls help on/off", "Leave command, play as Soldier"};
		strcopy(s, n, sMain[i]);
		if (i == 0) Format(s, n, "%s  -  %d Intel (have %d)%s", s, Worker_NextCost(t), g_iIntel[t], st == 'd' ? "  [not possible now]" : "");
		else if (st == 'd') StrCat(s, n, "  [off on this server]");
	} else if (iPage == 1) {
		int u = Wheel_Unlock(i);
		if (u == -1) { strcopy(s, n, "?"); return; }
		FormatEx(s, n, "%s", g_eUnlock[u].sName);
		int r = g_eUnlock[u].iRequires;
		if (st == 'o') StrCat(s, n, "  -  OWNED");
		else if (r != -1 && !g_bUnlocked[t][r]) Format(s, n, "%s  -  needs %s first", s, g_eUnlock[r].sName);
		else Format(s, n, "%s  -  %d Intel (have %d)", s, Unlock_Cost(u), g_iIntel[t]);
	} else if (iPage == 2) {
		AbilityId a = view_as<AbilityId>(i);
		float fCd = Ability_CooldownLeft(t, a);
		FormatEx(s, n, "%s  -  %d Intel (have %d)", g_sAbilityName[a], Ability_Cost(a), g_iIntel[t]);
		if (!g_hCvarAbilities.BoolValue) StrCat(s, n, "  [off on this server]");
		else if (fCd > 0.0) Format(s, n, "%s  -  ready in %ds", s, RoundToCeil(fCd));
	}
}

// every command tick while open (camera frozen)
void Wheel_Update(int c, const float vecCam[3], const float vecView[3], const float fMouse[2], int iButtons, int iLastButtons) {
	int iPage = g_iWheelPage[c];
	int n = Wheel_Count(iPage);
	int iHover = Wheel_HoverFromMouse(c, iPage, fMouse);
	g_iWheelHover[c] = iHover;
	float fTile = 0.14 * g_eCommander[c].fAspectRatio / 1.7778;   // tile width as a fraction of screen width (16:9 tuned)
	float fTan = Tangent(DegToRad(0.5 * (g_iCamFov[c] ? g_iCamFov[c] : 90)));   // 1.0 at FOV 90; keeps the on-screen size under a widened FOV
	float fScaleTile = WHEEL_DIST * fTile * 2.0 * 1.333 * fTan / 256.0;
	float fScaleHub = WHEEL_DIST * 0.22 * 1.48 * fTan / 256.0;
	char sKey[24], sName[32];
	float vecPos[3], fS[2];
	for (int i=0; i<n; i++) {
		Wheel_Key(iPage, i, sKey, sizeof(sKey));
		int st = Wheel_State(c, iPage, i);
		if (i == iHover && st == 'n') st = 'h';
		FormatEx(sName, sizeof(sName), "%s_%c", sKey, st);
		Wheel_ScreenPos(c, iPage, i, fS);
		Wheel_World(c, vecCam, vecView, fS[0], fS[1], vecPos);
		Wheel_SetSprite(c, i, sName, vecPos, fScaleTile);
	}
	Wheel_World(c, vecCam, vecView, 0.5, 0.5, vecPos);
	Wheel_SetSprite(c, WHEEL_HUB, g_sWheelHubs[iPage], vecPos, fScaleHub);
	char sDesc[160] = "Point at an item  -  LMB pick, RMB back";
	if (iHover != -1) Wheel_Describe(c, iPage, iHover, sDesc, sizeof(sDesc));
	Hud_Action(c, "%s", sDesc);
	bool bLeft = (iButtons & IN_ATTACK) && !(iLastButtons & IN_ATTACK);
	bool bRight = (iButtons & IN_ATTACK2) && !(iLastButtons & IN_ATTACK2);
	bool bDuck = (iButtons & IN_DUCK) && !(iLastButtons & IN_DUCK);
	if (bRight) { if (iPage > 0) Wheel_Open(c, 0); else Wheel_Close(c); return; }
	if (bDuck) { Wheel_Close(c); return; }
	if (bLeft && iHover != -1) Wheel_Pick(c, iPage, iHover);
}

void Wheel_Pick(int c, int iPage, int i) {
	int t = GetCommanderTeam(c);
	if (!t) { Wheel_Close(c); return; }
	g_iWheelPicks++;
	int st = Wheel_State(c, iPage, i);
	if (iPage == 0) {
		switch (i) {
			case 0: { Wheel_Close(c); if (Worker_CanHire(c)) Ghost_Start(c, Ghost_Worker); }
			case 1: Wheel_Open(c, 1);
			case 2: { if (st != 'd') Wheel_Open(c, 2); }
			case 3: { if (st != 'd') { Wheel_Close(c); Armory_ShowRestockMenu(c); } }
			case 4: Hud_ToggleHelp(c);
			case 5: {
				Wheel_Close(c);
				g_bWantsCommander[c] = false;
				g_bDeclinedCmdr[c] = true;
				if (g_hCvarBodyless.BoolValue) SchedulePending(c, Pending_LeaveRole);
				else ReleaseCommander(c);
			}
		}
	} else if (iPage == 1) {
		int u = Wheel_Unlock(i);
		if (u != -1 && st == 'n') Unlock_Buy(c, t, u);
	} else if (iPage == 2) {
		if (st == 'n') { Wheel_Close(c); Ability_Begin(c, view_as<AbilityId>(i)); }
	}
}

public Action cmdWheel(int iClient, int iArgs) {
	if (!iClient) return Plugin_Handled;
	if (!Wheel_Enabled(iClient)) { ReplyToCommand(iClient, "[RTS] The wheel works in the command view (css_rts_wheel 1)."); return Plugin_Handled; }
	Wheel_Toggle(iClient);
	return Plugin_Handled;
}

public Action cmdDebugWheel(int iClient, int iArgs) {
	iClient = ResolveClient(iClient);
	if (!HasRTSAccess(iClient)) return Plugin_Handled;
	char sT[64], sOp[16], sN[8];
	GetCmdArg(1, sT, sizeof(sT)); GetCmdArg(2, sOp, sizeof(sOp)); GetCmdArg(3, sN, sizeof(sN));
	int c = FindTarget(iClient, sT, false, false);
	if (c <= 0) return Plugin_Handled;
	int n = StringToInt(sN);
	if (StrEqual(sOp, "open")) Wheel_Open(c, 0);
	else if (StrEqual(sOp, "page")) Wheel_Open(c, n);
	else if (StrEqual(sOp, "close")) Wheel_Close(c);
	else if (StrEqual(sOp, "hover")) { float fS[2]; Wheel_ScreenPos(c, g_iWheelPage[c], n, fS); g_eCommander[c].fMouse[0] = fS[0]; g_eCommander[c].fMouse[1] = fS[1]; }
	else if (StrEqual(sOp, "pick") && Wheel_IsOpen(c) && g_iWheelHover[c] != -1) Wheel_Pick(c, g_iWheelPage[c], g_iWheelHover[c]);
	if (Wheel_IsOpen(c) && !StrEqual(sOp, "state")) Wheel_DebugTick(c);   // bots don't run the camera code
	int iSprites;
	for (int k=0; k<WHEEL_SLOTS; k++) if (EntRefToEntIndex(g_iWheelEnt[c][k]) > 0) iSprites++;
	char sStates[32];
	for (int i=0; Wheel_IsOpen(c) && i<Wheel_Count(g_iWheelPage[c]) && i < 31; i++) sStates[i] = view_as<char>(Wheel_State(c, g_iWheelPage[c], i));
	ReplyToCommand(iClient, "[RTS] wheel %N: page %d hover %d sprites %d states '%s' picks %d | team %d/%d post %d workers %d cost %d intel %d", c, g_iWheelPage[c], g_iWheelHover[c], iSprites, sStates, g_iWheelPicks,
		GetClientTeam(c), GetCommanderTeam(c), g_ePost[GetCommanderTeam(c)].bValid, Npc_Count(Npc_Worker, GetCommanderTeam(c)), Worker_NextCost(GetCommanderTeam(c)), g_iIntel[GetCommanderTeam(c)]);
	return Plugin_Handled;
}

// one wheel frame without input (bots / selftest: ProcessCameraControls only runs for humans)
void Wheel_DebugTick(int c) {
	int iFocus = EntRefToEntIndex(g_eCommander[c].iFocusEntRef);
	int iCam = EntRefToEntIndex(g_eCommander[c].iCameraEntRef);
	if (iFocus == INVALID_ENT_REFERENCE || iCam == INVALID_ENT_REFERENCE) return;
	float vecF[3], vecC[3], vecAbs[3], vecView[3], fM[2];
	Entity_GetAbsOrigin(iFocus, vecF);
	Entity_GetAbsOrigin(iCam, vecC);
	AddVectors(vecF, vecC, vecAbs);
	vecView = g_eCommander[c].vecVector;
	fM = g_eCommander[c].fMouse;
	Wheel_Update(c, vecAbs, vecView, fM, 0, 0);
}
