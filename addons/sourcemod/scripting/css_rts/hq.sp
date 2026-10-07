// css_rts/hq.sp -- v0.5.3 command hub (HQ): a big team-coloured composite built around the command
// post terminal (machine behind it + server racks on both sides). One shared HP pool (10,000),
// damaged by enemy fire on any part and by enemy "siege" (enemies standing next to it with line of
// sight). Health bar in the HUD panel, under-attack alert. Destroyed = no more reinforcement waves;
// in HQ Destruction mode (or with "HQ loss = defeat" on) the team loses.

#define HQ_PARTS 4
#define HQ_CORE_MODEL  "models/props_combine/combine_tptimer.mdl"
#define HQ_RACK_MODEL  "models/props_lab/servers.mdl"
#define HQ_ALARM_SOUND "ambient/alarms/klaxon1.wav"

ConVar g_hCvarHQ;
ConVar g_hCvarHQHealth;
ConVar g_hCvarHQSiegeDps;
ConVar g_hCvarHQSiegeRadius;
int g_iHQPart[4][HQ_PARTS];
// g_iHQOwner lives in post.sp (used by its trace filter)
int g_iHQHealth[4];
bool g_bHQDestroyed[4];
float g_fHQLastAlert[4];
float g_fHQLastHit[4];
bool g_bSetHQLoss = true;      // lobby: losing your HQ loses the game in any mode
// v0.5.3.1 wall fit: the whole hub stands in one row flush against a wall (terminal, core, racks), out of walkways
// (fit globals live in desks.sp: included earlier)
// part layout along the wall: side offset (+ = right when facing the wall's normal), back depth, half width, height
//   terminal breenconsole: x -15..21, y -16..12 | core combine_tptimer: x -45..54, y +-69 (x0.7) | rack servers: x -13..15, y +-47

int g_iHQFitVerbose;
void HQ_Init() {
	RegConsoleCmd("sm_rts_debug_hqfit", cmdDebugHQFit, "<t|ct>: re-run the HQ wall fit verbosely (does not respawn)");
	RegConsoleCmd("sm_rts_debug_bounds", cmdDebugBounds, "<model>: print the model bounds (prop_dynamic)");
	g_hCvarHQ = CreateConVar("css_rts_hq", "1", "1 = big attackable command hub (HQ) around each command post", _, true, 0.0, true, 1.0);
	g_hCvarHQHealth = CreateConVar("css_rts_hq_health", "10000", "HQ hit points", _, true, 100.0);
	g_hCvarHQSiegeDps = CreateConVar("css_rts_hq_siege_dps", "15", "Damage per second each enemy deals to an HQ while standing within css_rts_hq_siege_radius with line of sight", _, true, 0.0);
	g_hCvarHQSiegeRadius = CreateConVar("css_rts_hq_siege_radius", "380", "Siege radius around the HQ (units)", _, true, 0.0);
	RegConsoleCmd("sm_rts_debug_hq", cmdDebugHQ, "[t|ct] [damage]: print HQ state, or deal damage to a team's HQ");
	CreateTimer(1.0, Timer_HQ, _, TIMER_REPEAT);
	HookEvent("bullet_impact", Event_HQBulletImpact);
	HookEvent("hegrenade_detonate", Event_HQGrenade);
	for (int t=0; t<4; t++) for (int k=0; k<HQ_PARTS; k++) g_iHQPart[t][k] = INVALID_ENT_REFERENCE;
}

void HQ_MapStart() {
	PrecacheModel(HQ_CORE_MODEL, true);
	PrecacheModel(HQ_RACK_MODEL, true);
	PrecacheSound(HQ_ALARM_SOUND, true);
	for (int t=0; t<4; t++) for (int k=0; k<HQ_PARTS; k++) g_iHQPart[t][k] = INVALID_ENT_REFERENCE;
	HQ_Reset();
}

void HQ_Reset() {
	for (int t=0; t<4; t++) {
		g_iHQHealth[t] = g_hCvarHQHealth.IntValue; g_bHQDestroyed[t] = false; g_fHQLastAlert[t] = 0.0; g_fHQLastHit[t] = 0.0;
		for (int k=0; k<HQ_PARTS; k++) { int e = EntRefToEntIndex(g_iHQPart[t][k]); if (e > 0) HQ_Tint(t, e); }
	}
}

bool HQ_Destroyed(int t) { return g_hCvarHQ.BoolValue && g_bHQDestroyed[t]; }

int HQ_Percent(int t) {
	int m = g_hCvarHQHealth.IntValue;
	return m > 0 ? RoundToCeil(100.0 * g_iHQHealth[t] / m) : 0;
}

// point relative to the post: fFwd along the post's facing, fSide to its right
void HQ_Local(int t, float fFwd, float fSide, float vecOut[3]) {
	float y = DegToRad(g_ePost[t].vecAngles[1]);
	float fx = Cosine(y), fy = Sine(y);
	vecOut[0] = g_ePost[t].vecOrigin[0] + fx * fFwd + fy * fSide;
	vecOut[1] = g_ePost[t].vecOrigin[1] + fy * fFwd - fx * fSide;
	vecOut[2] = g_ePost[t].vecOrigin[2];
}

int HQ_SpawnPart(int t, const char[] sModel, const float vecPos[3], float fYaw, float fScale) {
	int e = CreateEntityByName("prop_dynamic_override");
	if (e == -1) return INVALID_ENT_REFERENCE;
	DispatchKeyValue(e, "model", sModel);
	DispatchKeyValue(e, "solid", "6");
	DispatchKeyValue(e, "targetname", "css_rts_hq");
	DispatchKeyValue(e, "disableshadows", "1");
	float vecAng[3];
	vecAng[1] = fYaw;
	DispatchKeyValueVector(e, "origin", vecPos);
	DispatchKeyValueVector(e, "angles", vecAng);
	DispatchSpawn(e);
	if (fScale != 1.0 && HasEntProp(e, Prop_Send, "m_flModelScale")) SetEntPropFloat(e, Prop_Send, "m_flModelScale", fScale);
	HQ_Tint(t, e);
	SetEntProp(e, Prop_Data, "m_takedamage", 0);   // never a "breakable" for bots; damage = enemy bullet impacts / grenades (HQ_OnImpact)
	SDKHook(e, SDKHook_OnTakeDamage, SDKHookCB_HQDamage);
	g_iHQOwner[e] = t;
	return EntIndexToEntRef(e);
}

void HQ_Tint(int t, int e) {
	SetEntityRenderMode(e, RENDER_TRANSCOLOR);
	if (t == CS_TEAM_CT) SetEntityRenderColor(e, 120, 170, 255, 255);
	else SetEntityRenderColor(e, 255, 165, 90, 255);
}

float HQ_CeilingRoom(const float vecFloor[3]) {
	float a[3], b[3], h[3];
	a = vecFloor; a[2] += 8.0;
	b = vecFloor; b[2] += 400.0;
	TR_TraceRayFilter(a, b, MASK_PLAYERSOLID_BRUSHONLY, RayType_EndPoint, TraceFilter_DeskWorld);
	if (!TR_DidHit()) return 400.0;
	TR_GetEndPosition(h);
	return h[2] - vecFloor[2];
}

// box clear for a part (world + solid brush entities; players/props ignored)
bool HQ_PartFits(const float vecPos[3], float fHalf, float fHeight) {
	float mn[3], mx[3];
	mn[0] = -fHalf; mn[1] = -fHalf; mn[2] = 12.0;
	mx[0] = fHalf; mx[1] = fHalf; mx[2] = fHeight;
	TR_TraceHullFilter(vecPos, vecPos, mn, mx, MASK_PLAYERSOLID, TraceFilter_DeskSolid);
	return !TR_DidHit() && !TR_StartSolid();
}

void HQ_Ensure() {
	if (!g_hCvarHQ.BoolValue) return;
	for (int t=CS_TEAM_T; t<=CS_TEAM_CT; t++) {
		if (!g_ePost[t].bValid || g_bHQDestroyed[t]) continue;
		// the terminal is part 0 (spawned by EnsureTerminals); give it HQ looks + damage
		int iTerm = GetTerminal(t);
		if (iTerm != -1 && g_iHQOwner[iTerm] != t) {
			HQ_Tint(t, iTerm);
			SetEntProp(iTerm, Prop_Data, "m_takedamage", 0);
			SDKHook(iTerm, SDKHook_OnTakeDamage, SDKHookCB_HQDamage);
			g_iHQOwner[iTerm] = t;
			g_iHQPart[t][0] = EntIndexToEntRef(iTerm);
		}
		if (EntRefToEntIndex(g_iHQPart[t][1]) > 0) continue;
		for (int k=1; k<HQ_PARTS; k++) { int e = EntRefToEntIndex(g_iHQPart[t][k]); if (e > 0) RemoveEntity(e); g_iHQPart[t][k] = INVALID_ENT_REFERENCE; }
		float p[3], fYaw = g_ePost[t].vecAngles[1];
		bool bOk;
		if (g_bHQFit[t]) {
			// flush row against the wall (fitted at map start)
			HQ_RowPos(t, 1, p); g_iHQPart[t][1] = HQ_SpawnPart(t, HQ_CORE_MODEL, p, g_fHQYaw[t], g_fHQCoreScale);
			for (int s=0; s<g_iHQRacks[t]; s++) { HQ_RowPos(t, 2 + s, p); g_iHQPart[t][2 + s] = HQ_SpawnPart(t, HQ_RACK_MODEL, p, g_fHQYaw[t], 1.0); }
		} else {
			// no wall fit: core only, behind the terminal, if it fits
			HQ_Local(t, -78.0, 0.0, p);
			float z = Desk_FloorZ(p, bOk); if (bOk) p[2] = z;
			if (HQ_PartFits(p, 48.0, 92.0)) g_iHQPart[t][1] = HQ_SpawnPart(t, HQ_CORE_MODEL, p, fYaw, g_fHQCoreScale);
		}
		if (EntRefToEntIndex(g_iHQPart[t][1]) <= 0) g_iHQPart[t][1] = INVALID_ENT_REFERENCE;
	}
}

public Action SDKHookCB_HQDamage(int iVictim, int &iAttacker, int &iInflictor, float &fDamage, int &iType) {
	int t = g_iHQOwner[iVictim];
	if (!(CS_TEAM_T <= t <= CS_TEAM_CT) || !g_hCvarHQ.BoolValue) return Plugin_Handled;
	if (iAttacker < 1 || iAttacker > MaxClients || !IsClientInGame(iAttacker) || GetClientTeam(iAttacker) == t) return Plugin_Handled;
	float f = fDamage;
	if (iType & DMG_BLAST) f *= 2.0;
	HQ_Damage(t, RoundToCeil(f), iAttacker);
	return Plugin_Handled;   // the props themselves never break or move
}

bool HQ_UnderFire(int t) {
	return t >= CS_TEAM_T && t <= CS_TEAM_CT && !g_bHQDestroyed[t] && g_fHQLastHit[t] > 0.0 && GetGameTime() - g_fHQLastHit[t] <= 5.0;
}

void HQ_CorePoint(int t, float vec[3]) {
	int e = (t >= 0 && t < 4) ? EntRefToEntIndex(g_iHQPart[t][1]) : -1;
	if (e > 0) GetEntPropVector(e, Prop_Data, "m_vecAbsOrigin", vec);
	else if (g_ePost[t].bHasHQ) vec = g_ePost[t].vecHQOrigin;
	else vec = g_ePost[t].vecOrigin;
	vec[2] += 48.0;
}

void HQ_Damage(int t, int iDmg, int iAttacker) {
	if (g_bHQDestroyed[t] || g_eGame != GS_Live || g_bMatchOver || iDmg <= 0) return;
	g_iHQHealth[t] -= iDmg;
	g_fHQLastHit[t] = GetGameTime();
	if (g_iHQHealth[t] <= 0) { g_iHQHealth[t] = 0; HQ_Destroy(t, iAttacker); return; }
	if (GetGameTime() - g_fHQLastAlert[t] >= 12.0) {
		g_fHQLastAlert[t] = GetGameTime();
		TeamChat(t, "\x04[RTS] YOUR HQ IS UNDER ATTACK!\x01 (%d%% left)", HQ_Percent(t));
		for (int i=1; i<=MaxClients; i++) if (IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) == t) EmitSoundToClient(i, HQ_ALARM_SOUND, _, _, _, _, 0.6);
		int c = GetTeamCommander(t);
		if (c && !IsFakeClient(c) && g_eCommander[c].bEnabled) Hud_Action(c, "HQ UNDER ATTACK  -  %d%% left  (Space = jump to base)", HQ_Percent(t));
	}
}

void HQ_Destroy(int t, int iAttacker) {
	g_bHQDestroyed[t] = true;
	char sT[32]; TeamName(t, sT, sizeof(sT));
	char sBy[48] = "";
	if (iAttacker > 0 && iAttacker <= MaxClients && IsClientInGame(iAttacker)) FormatEx(sBy, sizeof(sBy), " by %N", iAttacker);
	PrintToChatAll("\x04[RTS] The %s HQ was destroyed%s!\x01", sT, sBy);
	LogMessage("[RTS] HQ destroyed: team %d", t);
	for (int k=0; k<HQ_PARTS; k++) {
		int e = EntRefToEntIndex(g_iHQPart[t][k]);
		if (e <= 0) continue;
		float p[3];
		GetEntPropVector(e, Prop_Data, "m_vecAbsOrigin", p);
		int x = CreateEntityByName("env_explosion");
		if (x != -1) {
			DispatchKeyValue(x, "iMagnitude", k == 1 ? "320" : "140");
			DispatchKeyValue(x, "spawnflags", "1");
			p[2] += 40.0;
			DispatchKeyValueVector(x, "origin", p);
			DispatchSpawn(x);
			AcceptEntityInput(x, "Explode");
			if (k == 1) EmitSoundToAll("weapons/c4/c4_explode1.wav", e, _, _, _, 1.0);
			CreateTimer(1.0, Timer_KillEnt, EntIndexToEntRef(x));
		}
		if (k == 0) { SetEntityRenderColor(e, 40, 40, 40, 255); continue; }   // keep the terminal (selftests/USE), blackened
		SetEntityRenderColor(e, 30, 30, 30, 255);
	}
}

public Action Timer_KillEnt(Handle h, int iRef) {
	int e = EntRefToEntIndex(iRef);
	if (e > 0) RemoveEntity(e);
	return Plugin_Stop;
}

// siege: enemies close to the HQ with line of sight wear it down
public Action Timer_HQ(Handle h) {
	if (!g_hCvarHQ.BoolValue || g_eGame != GS_Live || g_bMatchOver) return Plugin_Continue;
	float fR = g_hCvarHQSiegeRadius.FloatValue;
	int iDps = g_hCvarHQSiegeDps.IntValue;
	if (iDps <= 0) return Plugin_Continue;
	for (int t=CS_TEAM_T; t<=CS_TEAM_CT; t++) {
		if (!g_ePost[t].bValid || g_bHQDestroyed[t]) continue;
		float vecHQ[3];
		vecHQ = g_ePost[t].vecHQOrigin;
		vecHQ[2] += 48.0;
		int iDmg, iLast;
		for (int i=1; i<=MaxClients; i++) {
			if (!IsClientInGame(i) || !IsPlayerAlive(i) || g_bBodyHidden[i]) continue;
			int ti = GetClientTeam(i);
			if (ti == t || !(CS_TEAM_T <= ti <= CS_TEAM_CT)) continue;
			float vecE[3];
			GetClientEyePosition(i, vecE);
			if (GetVectorDistance(vecE, vecHQ) > fR) continue;
			TR_TraceRayFilter(vecE, vecHQ, MASK_SOLID_BRUSHONLY, RayType_EndPoint, TraceFilter_DeskWorld);
			if (TR_DidHit()) continue;
			iDmg += iDps; iLast = i;
		}
		if (iDmg > 0) HQ_Damage(t, iDmg, iLast);
	}
	return Plugin_Continue;
}

// HUD panel line: "HQ ##########  100%"
void HQ_HudLine(int t, char[] s, int n) {
	if (!g_hCvarHQ.BoolValue || !g_ePost[t].bValid) return;
	int iPct = HQ_Percent(t);
	char sBar[16];
	int iFull = (iPct + 9) / 10;
	for (int k=0; k<10; k++) sBar[k] = k < iFull ? '|' : '.';
	sBar[10] = 0;
	bool bHit = GetGameTime() - g_fHQLastHit[t] < 3.0;
	Format(s, n, "%sHQ  [%s] %d%%%s\n", s, sBar, iPct, g_bHQDestroyed[t] ? "  DESTROYED" : (bHit ? "  !!" : ""));
}

public Action cmdDebugHQ(int iClient, int iArgs) {
	iClient = ResolveClient(iClient);
	if (!HasRTSAccess(iClient)) return Plugin_Handled;
	if (iArgs >= 2) {
		char s[8]; GetCmdArg(1, s, sizeof(s));
		int t = TeamFromName(s);
		if (t) {
			int iDmg = GetCmdArgInt(2);
			g_iHQHealth[t] -= iDmg;
			g_fHQLastHit[t] = GetGameTime();
			if (g_iHQHealth[t] <= 0) { g_iHQHealth[t] = 0; if (!g_bHQDestroyed[t]) HQ_Destroy(t, 0); }
		}
	}
	for (int t=CS_TEAM_T; t<=CS_TEAM_CT; t++) {
		int iParts;
		for (int k=0; k<HQ_PARTS; k++) if (EntRefToEntIndex(g_iHQPart[t][k]) > 0) iParts++;
		ReplyToCommand(iClient, "[RTS] HQ %s: %d/%d (%d%%) destroyed %d parts %d loss_rule %d mode %d", t == CS_TEAM_CT ? "CT" : "T", g_iHQHealth[t], g_hCvarHQHealth.IntValue, HQ_Percent(t), g_bHQDestroyed[t], iParts, g_bSetHQLoss, g_eMode);
	}
	return Plugin_Handled;
}

public Action cmdDebugBounds(int iClient, int iArgs) {
	iClient = ResolveClient(iClient);
	if (!HasRTSAccess(iClient) || iArgs < 1) return Plugin_Handled;
	char sM[128]; GetCmdArg(1, sM, sizeof(sM));
	PrecacheModel(sM, true);
	int e = CreateEntityByName("prop_dynamic_override");
	DispatchKeyValue(e, "model", sM);
	DispatchKeyValue(e, "solid", "6");
	DispatchSpawn(e);
	float mn[3], mx[3];
	GetEntPropVector(e, Prop_Send, "m_vecMins", mn);
	GetEntPropVector(e, Prop_Send, "m_vecMaxs", mx);
	ReplyToCommand(iClient, "[RTS] bounds %s: mins %.0f %.0f %.0f maxs %.0f %.0f %.0f", sM, mn[0], mn[1], mn[2], mx[0], mx[1], mx[2]);
	RemoveEntity(e);
	return Plugin_Handled;
}

// ---------- v0.5.3.1: wall fit ----------
float HQ_PartSide(int t, int k) {
	float c = g_fHQCoreScale, m = g_fHQMirror[t];
	switch (k) {
		case 0: return 0.0;                                   // terminal
		case 1: return -(16.0 + 10.0 + 69.0 * c) * m;         // core, beside the terminal
		case 2: return (16.0 + 10.0 + 47.0) * m;              // rack, other side
		case 3: return -(16.0 + 10.0 + 138.0 * c + 10.0 + 47.0) * m;   // rack beyond the core
	}
	return 0.0;
}
float HQ_PartBack(int k) { switch (k) { case 0: return 15.0; case 1: return 45.0 * g_fHQCoreScale; } return 13.0; }
float HQ_PartFront(int k) { switch (k) { case 0: return 21.0; case 1: return 54.0 * g_fHQCoreScale; } return 15.0; }
float HQ_PartHalfW(int k) { switch (k) { case 0: return 16.0; case 1: return 69.0 * g_fHQCoreScale; } return 47.0; }
float HQ_PartH(int k) { switch (k) { case 0: return 54.0; case 1: return 130.0 * g_fHQCoreScale; } return 101.0; }

// wall-relative point: side along the wall, out from it
void HQ_WallLocal(const float vecWall[3], float fYaw, float fSide, float fOut, float vecOut[3]) {
	float y = DegToRad(fYaw), fx = Cosine(y), fy = Sine(y);
	vecOut[0] = vecWall[0] + fx * fOut + fy * fSide;
	vecOut[1] = vecWall[1] + fy * fOut - fx * fSide;
	vecOut[2] = vecWall[2];
}

void HQ_RowPos(int t, int k, float vecOut[3]) {
	HQ_WallLocal(g_vecHQWall[t], g_fHQYaw[t], HQ_PartSide(t, k), HQ_PartBack(k) + 5.0, vecOut);   // wall point is 4u inside the wall surface
	bool bOk; float z = Desk_FloorZ(vecOut, bOk); if (bOk) vecOut[2] = z;
}

// is a solid wall right behind (fSide) - true also in corners (start solid)
bool HQ_WallBehind(const float vecWall[3], float fYaw, float fSide) {
	for (int hz=0; hz<2; hz++) {
		float a[3], b[3];
		HQ_WallLocal(vecWall, fYaw, fSide, 8.0, a); a[2] += hz == 0 ? 24.0 : 52.0;
		HQ_WallLocal(vecWall, fYaw, fSide, -14.0, b); b[2] = a[2];
		TR_TraceRayFilter(a, b, MASK_PLAYERSOLID, RayType_EndPoint, TraceFilter_DeskSolid);
		if (TR_DidHit() || TR_StartSolid()) return true;
	}
	return false;
}

// placement rules shared by HQ parts and desks: flush (wall behind), not by a doorway/opening, a free walkway in front,
// no doors or spawn points nearby. fSide0..fSide1 = extent along the wall, fDepth = how far it sticks out.
bool Place_RowOk(const float vecWall[3], float fYaw, float fSide0, float fSide1, float fDepth, float fHeight, char[] sWhy, int iWhy) {
	bool bOk;
	// floor + wall behind every 24u along the row
	for (float sd = fSide0; sd <= fSide1 + 0.1; sd += 24.0) {
		float p[3];
		HQ_WallLocal(vecWall, fYaw, sd, fDepth * 0.5, p);
		float z = Desk_FloorZ(p, bOk);
		if (!bOk || FloatAbs(z - vecWall[2]) > 10.0) { FormatEx(sWhy, iWhy, "no floor at %.0f", sd); return false; }
		if (!HQ_WallBehind(vecWall, fYaw, sd)) { FormatEx(sWhy, iWhy, "not flush / opening at %.0f", sd); return false; }
	}
	// doorway / opening next to the row ends (40u beyond each end the wall must continue or turn a corner)
	if (!HQ_WallBehind(vecWall, fYaw, fSide0 - 40.0) || !HQ_WallBehind(vecWall, fYaw, fSide1 + 40.0)) { strcopy(sWhy, iWhy, "doorway/opening beside it"); return false; }
	// body clear (inset 2u)
	{
		float c[3], mn[3], mx[3];
		HQ_WallLocal(vecWall, fYaw, (fSide0 + fSide1) * 0.5, fDepth * 0.5 + 2.0, c);
		float hw = (fSide1 - fSide0) * 0.5 - 2.0, hd = fDepth * 0.5 - 2.0;
		float y = DegToRad(fYaw);
		float ex = FloatAbs(Cosine(y)) * hd + FloatAbs(Sine(y)) * hw, ey = FloatAbs(Sine(y)) * hd + FloatAbs(Cosine(y)) * hw;
		mn[0] = -ex; mn[1] = -ey; mn[2] = 14.0; mx[0] = ex; mx[1] = ey; mx[2] = fHeight;
		TR_TraceHullFilter(c, c, mn, mx, MASK_PLAYERSOLID, TraceFilter_DeskSolid);
		if (TR_DidHit() || TR_StartSolid()) { strcopy(sWhy, iWhy, "body blocked"); return false; }
	}
	// walkway in front: a player hull must pass 96u out from the front face along the whole row
	for (float sd = fSide0; sd <= fSide1 + 0.1; sd += 24.0) {
		float a[3], b[3];
		HQ_WallLocal(vecWall, fYaw, sd, fDepth + 4.0, a); a[2] += 2.0;
		HQ_WallLocal(vecWall, fYaw, sd, fDepth + 4.0 + 96.0, b); b[2] = a[2];
		static float mn2[3] = {-16.0, -16.0, 18.0}, mx2[3] = {16.0, 16.0, 70.0};
		TR_TraceHullFilter(a, b, mn2, mx2, MASK_PLAYERSOLID, TraceFilter_DeskSolid);
		if (TR_DidHit() || TR_StartSolid()) { FormatEx(sWhy, iWhy, "walkway in front too narrow at %.0f", sd); return false; }
	}
	// doors and spawn points
	float vecMid[3];
	HQ_WallLocal(vecWall, fYaw, (fSide0 + fSide1) * 0.5, fDepth * 0.5, vecMid);
	float fReach = (fSide1 - fSide0) * 0.5 + 72.0;
	static const char sCls[][] = {"func_door", "func_door_rotating", "prop_door_rotating", "info_player_terrorist", "info_player_counterterrorist"};
	for (int k=0; k<sizeof(sCls); k++) {
		int e = -1;
		while ((e = FindEntityByClassname(e, sCls[k])) != -1) {
			float v[3];
			GetEntPropVector(e, Prop_Data, "m_vecAbsOrigin", v);
			if (k < 3) { float mn[3], mx[3]; GetEntPropVector(e, Prop_Send, "m_vecMins", mn); GetEntPropVector(e, Prop_Send, "m_vecMaxs", mx); for (int i=0; i<3; i++) v[i] += (mn[i] + mx[i]) * 0.5; }
			if (FloatAbs(v[2] - vecMid[2]) > 80.0) continue;
			float d = SquareRoot((v[0]-vecMid[0])*(v[0]-vecMid[0]) + (v[1]-vecMid[1])*(v[1]-vecMid[1]));
			if (d < (k < 3 ? fReach + 24.0 : fReach - 24.0)) { strcopy(sWhy, iWhy, k < 3 ? "next to a door" : "on a spawn point"); return false; }
		}
	}
	return true;
}

bool HQ_TryRow(int t, const float vecWall[3], float fYaw, int iRacks, char[] sWhy, int iWhy) {
	g_fHQCoreScale = 0.7;
	float fCeil = HQ_CeilingRoom(vecWall);
	if (fCeil < 100.0) g_fHQCoreScale = 0.6;
	float s0 = 99999.0, s1 = -99999.0;
	for (int k=0; k<=1+iRacks; k++) {
		float a = HQ_PartSide(t, k) - HQ_PartHalfW(k), b = HQ_PartSide(t, k) + HQ_PartHalfW(k);
		if (a < s0) s0 = a;
		if (b > s1) s1 = b;
	}
	float fDepth = 0.0, fH = 0.0;
	for (int k=0; k<=3; k++) {
		if (k >= 2 && k - 1 > iRacks) continue;
		float d = HQ_PartBack(k) + HQ_PartFront(k) + 1.0;
		if (d > fDepth) fDepth = d;
		if (HQ_PartH(k) > fH) fH = HQ_PartH(k);
	}
	if (fH > fCeil - 4.0) fH = fCeil - 4.0;
	return Place_RowOk(vecWall, fYaw, s0, s1, fDepth, fH, sWhy, iWhy);
}

// map start: find a wall near the configured post and lay the hub out along it
void HQ_FitPost(int t) {
	g_bHQFit[t] = false;
	g_sHQWhy[t][0] = 0;
	if (!g_ePost[t].bValid || !g_hCvarHQ.BoolValue) return;
	bool bOk;
	float vecA[3], vecWall[3], fYaw;
	char sWhy[48], sFirst[48];
	for (int iTry=0; iTry<6; iTry++) {
		int iRacks = 2 - iTry / 2;
		g_fHQMirror[t] = iTry % 2 == 0 ? 1.0 : -1.0;
		for (int r=0; r<=8; r++) {
			for (int k=0; k<(r == 0 ? 1 : 8); k++) {
				vecA = g_ePost[t].vecOrigin;
				vecA[0] += Cosine(DegToRad(k * 45.0)) * 64.0 * r; vecA[1] += Sine(DegToRad(k * 45.0)) * 64.0 * r;
				float z = Desk_FloorZ(vecA, bOk);
				if (!bOk || FloatAbs(z - g_ePost[t].vecOrigin[2]) > 16.0) continue;
				vecA[2] = z;
				if (!Desk_FindWall(vecA, z, -1.0, vecWall, fYaw)) continue;
				static float fNudge[] = {0.0, 32.0, -32.0, 64.0, -64.0, 96.0, -96.0, 128.0, -128.0};
				for (int n=0; n<sizeof(fNudge); n++) {
					float vecTry[3], vecW2[3], fY2;
					HQ_WallLocal(vecWall, fYaw, fNudge[n], 40.0, vecTry);
					if (!Desk_FindWall(vecTry, z, fYaw, vecW2, fY2) || FloatAbs(AngleDiff(fY2, fYaw)) > 10.0) continue;
					if (HQ_TryRow(t, vecW2, fY2, iRacks, sWhy, sizeof(sWhy))) {
						g_bHQFit[t] = true;
						g_vecHQWall[t] = vecW2; g_fHQYaw[t] = fY2; g_iHQRacks[t] = iRacks;
						// terminal = the post: flush at the wall, facing into the room
						HQ_WallLocal(vecW2, fY2, 0.0, HQ_PartBack(0) + 5.0, g_ePost[t].vecOrigin);
						g_ePost[t].vecAngles[0] = 0.0; g_ePost[t].vecAngles[1] = fY2; g_ePost[t].vecAngles[2] = 0.0;
						HQ_WallLocal(vecW2, fY2, HQ_PartSide(t, 1), HQ_PartBack(1) + 5.0, g_ePost[t].vecHQOrigin);
						g_ePost[t].bHasHQ = true;
						FormatEx(g_sHQWhy[t], sizeof(g_sHQWhy[]), "flush, %d racks, mirror %.0f, moved %.0fu", iRacks, g_fHQMirror[t], GetVectorDistance(vecA, g_ePost[t].vecOrigin));
						LogMessage("[RTS] HQ fit %s: wall %.0f %.0f %.0f yaw %.0f racks %d (%s)", t == CS_TEAM_CT ? "CT" : "T", vecW2[0], vecW2[1], vecW2[2], fY2, iRacks, g_sHQWhy[t]);
						return;
					}
					if (!sFirst[0]) strcopy(sFirst, sizeof(sFirst), sWhy);
					if (g_iHQFitVerbose && iRacks == 0) PrintToServer("[RTS] hqfit r%d k%d n%.0f wall %.0f %.0f yaw %.0f: %s", r, k, fNudge[n], vecW2[0], vecW2[1], fY2, sWhy);
				}
			}
		}
	}
	FormatEx(g_sHQWhy[t], sizeof(g_sHQWhy[]), "no flush spot (%s)", sFirst);
	LogMessage("[RTS] HQ fit %s FAILED: %s", t == CS_TEAM_CT ? "CT" : "T", g_sHQWhy[t]);
}

// enemy bullet hitting an HQ part (bullet_impact; the props take no engine damage so bots never treat them as breakables)
bool HQ_CursorOn(int iClient, const float vecPos[3]) {
	int t = GetClientTeam(iClient);
	if (t < CS_TEAM_T || t > CS_TEAM_CT || !g_ePost[t].bValid || !g_ePost[t].bHasHQ) return false;
	if (GetVectorDistance(vecPos, g_ePost[t].vecHQOrigin) < 220.0) return true;
	int e = EntRefToEntIndex(g_iTerminalRef[t]);
	if (e > 0 && IsValidEntity(e)) {
		float p[3];
		GetEntPropVector(e, Prop_Data, "m_vecAbsOrigin", p);
		if (GetVectorDistance(vecPos, p) < 160.0) return true;
	}
	return false;
}

bool HQ_IsTerminal(int e) {
	if (e <= 0) return false;
	for (int t = CS_TEAM_T; t <= CS_TEAM_CT; t++) if (e == EntRefToEntIndex(g_iTerminalRef[t])) return true;
	return false;
}

bool Seat_NearCursor(int iTeam, const float vec[3], float fDist) {
	for (int s = 0; s < g_iSeats; s++) {
		if (g_iSeatTeam[s] && g_iSeatTeam[s] != iTeam) continue;
		if (GetVectorDistance(vec, g_vecSeat[s]) <= fDist) return true;
	}
	return false;
}

bool HQ_IsHub(int e) {
	if (e <= 0) return false;
	for (int t = CS_TEAM_T; t <= CS_TEAM_CT; t++) {
		if (e == EntRefToEntIndex(g_iTerminalRef[t])) return true;
		for (int k = 0; k < HQ_PARTS; k++) if (e == EntRefToEntIndex(g_iHQPart[t][k])) return true;
	}
	return false;
}

void HQ_OnImpact(int iAttacker, const float vecHit[3], int iDmg) {
	if (!g_hCvarHQ.BoolValue || iAttacker < 1 || iAttacker > MaxClients || !IsClientInGame(iAttacker)) return;
	int ta = GetClientTeam(iAttacker);
	for (int t=CS_TEAM_T; t<=CS_TEAM_CT; t++) {
		if (ta == t) continue;   // allies never damage their own HQ (bullets, grenades, anything)
		for (int k=0; k<HQ_PARTS; k++) {
			int e = EntRefToEntIndex(g_iHQPart[t][k]);
			if (e <= 0) continue;
			float o[3], mn[3], mx[3], fS = 1.0;
			GetEntPropVector(e, Prop_Data, "m_vecAbsOrigin", o);
			GetEntPropVector(e, Prop_Send, "m_vecMins", mn);
			GetEntPropVector(e, Prop_Send, "m_vecMaxs", mx);
			if (HasEntProp(e, Prop_Send, "m_flModelScale")) fS = GetEntPropFloat(e, Prop_Send, "m_flModelScale");
			float r = 0.0;
			for (int i=0; i<2; i++) { float a = FloatAbs(mn[i]) > FloatAbs(mx[i]) ? FloatAbs(mn[i]) : FloatAbs(mx[i]); if (a > r) r = a; }
			r = r * fS + 6.0;
			if (vecHit[2] < o[2] - 4.0 || vecHit[2] > o[2] + mx[2] * fS + 6.0) continue;
			if ((vecHit[0]-o[0])*(vecHit[0]-o[0]) + (vecHit[1]-o[1])*(vecHit[1]-o[1]) > r * r) continue;
			HQ_Damage(t, iDmg, iAttacker);
			return;
		}
	}
}

public void Event_HQBulletImpact(Event hEvent, const char[] sName, bool bDontBroadcast) {
	int c = GetClientOfUserId(hEvent.GetInt("userid"));
	float v[3];
	v[0] = hEvent.GetFloat("x"); v[1] = hEvent.GetFloat("y"); v[2] = hEvent.GetFloat("z");
	HQ_OnImpact(c, v, 12);
}

public void Event_HQGrenade(Event hEvent, const char[] sName, bool bDontBroadcast) {
	int c = GetClientOfUserId(hEvent.GetInt("userid"));
	if (c < 1 || !IsClientInGame(c) || !g_hCvarHQ.BoolValue) return;
	float v[3];
	v[0] = hEvent.GetFloat("x"); v[1] = hEvent.GetFloat("y"); v[2] = hEvent.GetFloat("z");
	HQ_OnGrenade(c, v);
}

void HQ_OnGrenade(int c, const float v[3]) {
	int ta = GetClientTeam(c);
	for (int t=CS_TEAM_T; t<=CS_TEAM_CT; t++) {
		if (ta == t || !g_ePost[t].bValid) continue;   // own grenades never hurt the own HQ
		if (GetVectorDistance(v, g_ePost[t].vecHQOrigin) < 220.0) HQ_Damage(t, 300, c);
	}
}

public Action cmdDebugHQFit(int iClient, int iArgs) {
	iClient = ResolveClient(iClient);
	if (!HasRTSAccess(iClient)) return Plugin_Handled;
	char s[8]; GetCmdArg(1, s, sizeof(s));
	int t = TeamFromName(s);
	if (!t) return Plugin_Handled;
	float vecOld[3], vecOldAng[3], vecOldHQ[3];
	vecOld = g_ePost[t].vecOrigin; vecOldAng = g_ePost[t].vecAngles; vecOldHQ = g_ePost[t].vecHQOrigin;
	if (iArgs >= 4) { g_ePost[t].vecOrigin[0] = GetCmdArgFloat(2); g_ePost[t].vecOrigin[1] = GetCmdArgFloat(3); g_ePost[t].vecOrigin[2] = GetCmdArgFloat(4); }
	g_iHQFitVerbose = 1;
	HQ_FitPost(t);
	g_iHQFitVerbose = 0;
	ReplyToCommand(iClient, "[RTS] hqfit %s: fit %d %s post %.0f %.0f %.0f yaw %.0f", s, g_bHQFit[t], g_sHQWhy[t], g_ePost[t].vecOrigin[0], g_ePost[t].vecOrigin[1], g_ePost[t].vecOrigin[2], g_ePost[t].vecAngles[1]);
	g_ePost[t].vecOrigin = vecOld; g_ePost[t].vecAngles = vecOldAng; g_ePost[t].vecHQOrigin = vecOldHQ;
	return Plugin_Handled;
}
