// css_rts/match.sp -- continuous mode: warm-up, reinforcement waves, team unit pool, win check,
// bot balancer (N FPS slots per team + commander extra), defensive bot hold.

ConVar g_hCvarContinuous;
ConVar g_hCvarWaveInterval;
ConVar g_hCvarUnitPool;
ConVar g_hCvarFpsPerTeam;
ConVar g_hCvarDefend;
ConVar g_hCvarDefendRadius;
ConVar g_hCvarTimeLimit;

int g_iUnitPool[4];
float g_fNextWave;
float g_fOrderedUntil[MAXPLAYERS+1];
float g_fLastHurt[MAXPLAYERS+1];
float g_fBotMoved[MAXPLAYERS+1];

void Match_Init() {
	g_hCvarContinuous = CreateConVar("css_rts_continuous", "1", "1 = continuous mode (no round wins; respawn waves; unit pool); 0 = normal CS rounds", _, true, 0.0, true, 1.0);
	g_hCvarWaveInterval = CreateConVar("css_rts_wave_interval", "20", "Seconds between reinforcement waves", _, true, 3.0);
	g_hCvarUnitPool = CreateConVar("css_rts_unit_pool", "200", "Respawns available per team per match", _, true, 0.0);
	g_hCvarFpsPerTeam = CreateConVar("css_rts_fps_per_team", "5", "FPS players per team (humans + bots); the Commander is extra. Guards add on top, up to the server slot cap (CS:S max is 64).", _, true, 0.0, true, 32.0);
	g_hCvarDefend = CreateConVar("css_rts_bots_defend", "1", "1 = idle bots hold around their own base", _, true, 0.0, true, 1.0);
	g_hCvarDefendRadius = CreateConVar("css_rts_defend_radius", "700", "Bots further than this from base get pulled back (units)", _, true, 100.0);
	g_hCvarTimeLimit = CreateConVar("css_rts_timelimit", "40", "Match length in minutes for continuous mode (mp_timelimit)", _, true, 0.0);
	HookEvent("player_hurt", Event_MatchPlayerHurt);
	HookEvent("player_death", Event_DogTag, EventHookMode_Post);
	Tags_RemoveOldRadios();
}

#define AI_MIX 0
#define AI_ATTACK 1
#define AI_DEFEND 2
int g_iAiMode[4];
float g_fCoverUntil[MAXPLAYERS+1];
int g_iBotFollow[MAXPLAYERS+1];
int g_iBotOrderTarget[MAXPLAYERS+1];

void Match_MapStart() {
	g_bMatchOver = false;
	g_iAiMode[CS_TEAM_T] = AI_MIX;
	g_iAiMode[CS_TEAM_CT] = AI_MIX;
	for (int i = 1; i <= MaxClients; i++) { g_fCoverUntil[i] = 0.0; g_iBotFollow[i] = 0; }
	ResetPools();
	g_fWarmupEnd = 0.0;
	g_fNextWave = 0.0;
	CreateTimer(1.0, Timer_Match, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	CreateTimer(3.0, Timer_BotBalance, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	CreateTimer(1.5, Timer_BotDefend, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

void ResetPools() {
	for (int t=0; t<4; t++) g_iUnitPool[t] = g_hCvarUnitPool.IntValue;
}

bool InWarmup() {
	return InLobby();   // v0.5: the lobby replaces the timed warm-up
}

void Match_ApplyServerSettings() {
	ServerCommand("bot_join_after_player 0");
	ServerCommand("bot_quota_mode normal");
	ServerCommand("bot_auto_vacate 0");
	ServerCommand("mp_autoteambalance 0");
	ServerCommand("mp_limitteams 0");
	if (g_hCvarContinuous.BoolValue) {
		ServerCommand("mp_ignore_round_win_conditions 1");
		ServerCommand("mp_roundtime 9");
		ServerCommand("mp_freezetime 2");
		ServerCommand("mp_buytime 9999");
		ServerCommand("mp_timelimit %d", g_hCvarTimeLimit.IntValue);
	} else {
		ServerCommand("mp_roundtime 9");
		ServerCommand("mp_freezetime 3");
	}
}

public void Event_MatchPlayerHurt(Event hEvent, const char[] sName, bool bDontBroadcast) {
	int iClient = GetClientOfUserId(hEvent.GetInt("userid"));
	if (iClient) g_fLastHurt[iClient] = GetGameTime();
}

int TeamUnits(int iTeam) {
	if (!(CS_TEAM_T <= iTeam <= CS_TEAM_CT)) return 0;
	return CountFps(iTeam, true) + Npc_Count(Npc_Worker, iTeam);
}

int CountFps(int iTeam, bool bAliveOnly=false, int &iBots=0) {
	int n;
	iBots = 0;
	for (int i=1; i<=MaxClients; i++) {
		if (!IsClientInGame(i) || GetClientTeam(i) != iTeam || IsClientSourceTV(i)) continue;
		if (GetTeamCommander(iTeam) == i) continue;
		if (bAliveOnly && !IsPlayerAlive(i)) continue;
		if (IsFakeClient(i)) iBots++;
		n++;
	}
	return n;
}

public Action Timer_Match(Handle hTimer) {
	float fNow = GetGameTime();
	bool bWarm = InWarmup();
	if (!g_hCvarContinuous.BoolValue || g_bMatchOver) return Plugin_Continue;

	if (bWarm) {
		RespawnDead(false); // instant, free
		return Plugin_Continue;
	}
	if (g_fNextWave <= 0.0) g_fNextWave = fNow + g_hCvarWaveInterval.FloatValue;
	if (fNow >= g_fNextWave) {
		RespawnDead(true);
		g_fNextWave = fNow + g_hCvarWaveInterval.FloatValue;
	}
	return Plugin_Continue;
}

void RespawnDead(bool bUsePool) {
	for (int i=1; i<=MaxClients; i++) {
		if (!IsClientInGame(i) || IsPlayerAlive(i)) continue;
		int t = GetClientTeam(i);
		if (!(CS_TEAM_T <= t <= CS_TEAM_CT)) continue;
		bool bCmdr = GetTeamCommander(t) == i;
		if (bUsePool && !bCmdr && HQ_Destroyed(t)) continue;   // v0.5.3: no HQ, no reinforcements
		if (bUsePool && !bCmdr) {
			if (g_iUnitPool[t] <= 0) continue;
			g_iUnitPool[t]--;
		}
		CS_RespawnPlayer(i);
	}
}

void CheckPoolDefeat() {
	for (int t=CS_TEAM_T; t<=CS_TEAM_CT; t++) {
		if (g_iUnitPool[t] > 0) continue;
		if (CountFps(t, true) > 0 || CountFps(t) == 0) continue;
		int iWinner = t == CS_TEAM_T ? CS_TEAM_CT : CS_TEAM_T;
		g_bMatchOver = true;
		PrintToChatAll("\x04[RTS]\x01 %s are out of units. \x04%s WIN!\x01 New match in 10 s.", t == CS_TEAM_T ? "Terrorists" : "Counter-Terrorists", iWinner == CS_TEAM_T ? "TERRORISTS" : "COUNTER-TERRORISTS");
		CS_SetTeamScore(iWinner, CS_GetTeamScore(iWinner) + 1);
		SetTeamScore(iWinner, CS_GetTeamScore(iWinner));
		CS_TerminateRound(10.0, iWinner == CS_TEAM_T ? CSRoundEnd_TerroristWin : CSRoundEnd_CTWin, true);
		CreateTimer(10.5, Timer_NewMatch, _, TIMER_FLAG_NO_MAPCHANGE);
		return;
	}
}

public Action Timer_NewMatch(Handle hTimer) {
	g_bMatchOver = false;
	ResetPools();
	for (int t=0; t<4; t++) g_iIntel[t] = g_hCvarIntelStart.IntValue;
	Unlocks_Reset();
	Workers_ResetMatch();
	g_fNextWave = GetGameTime() + g_hCvarWaveInterval.FloatValue;
	return Plugin_Stop;
}

// HUD line for Intel HUD
void Match_HudLine(int iClient, char[] sOut, int iLen) {
	int t = GetClientTeam(iClient);
	if (InWarmup()) {
		if (g_eGame == GS_Countdown) FormatEx(sOut, iLen, "MATCH STARTS IN %ds", RoundToCeil(g_fCountdownEnd - GetGameTime()));
		else FormatEx(sOut, iLen, "LOBBY - waiting for the host to press Start");
		return;
	}
	if (g_eGame == GS_Ended) { strcopy(sOut, iLen, "GAME OVER"); return; }
	if (!g_hCvarContinuous.BoolValue) { sOut[0] = '\0'; return; }
	int iEnemy = t == CS_TEAM_T ? CS_TEAM_CT : CS_TEAM_T;
	if (!IsPlayerAlive(iClient) && g_iUnitPool[t] <= 0) {
		FormatEx(sOut, iLen, "CT %d    T %d    NO REINFORCEMENTS LEFT", TeamUnits(CS_TEAM_CT), TeamUnits(CS_TEAM_T));
	} else {
		int iLeft = g_fMatchEnd > 0.0 ? RoundToCeil(g_fMatchEnd - GetGameTime()) : 0;
		FormatEx(sOut, iLen, "CT %d    T %d    %d:%02d left", TeamUnits(CS_TEAM_CT), TeamUnits(CS_TEAM_T), iLeft / 60, iLeft % 60);
		if (g_eMode == Mode_IntelRace) Format(sOut, iLen, "%s\nINTEL RACE %d / %d (enemy %d)", sOut, g_iIntelEarned[t], g_iSetIntelTarget, g_iIntelEarned[iEnemy]);
		else if (g_eMode == Mode_Workers) Format(sOut, iLen, "%s\nWORKERS %d (enemy %d)", sOut, Npc_Count(Npc_Worker, t), Npc_Count(Npc_Worker, iEnemy));
	}
}

// ---- bot balancer: keep css_rts_fps_per_team FPS players per team ----
public Action Timer_BotBalance(Handle hTimer) {
	if (g_bSelfTestRunning || g_eGame != GS_Live) return Plugin_Continue;
	for (int t=CS_TEAM_T; t<=CS_TEAM_CT; t++) {
		int iWant = g_hCvarFpsPerTeam.IntValue + Guard_Extra(t) + Train_Extra(t);
		int iBots;
		int iFps = CountFps(t, false, iBots);
		if (iFps < iWant) {
			ServerCommand(t == CS_TEAM_T ? "bot_add_t" : "bot_add_ct");
		} else if (iFps > iWant && iBots > 0) {
			int iKick = PickBotToKick(t);
			if (iKick) ServerCommand("bot_kick \"%N\"", iKick);
		}
	}
	return Plugin_Continue;
}

int PickBotToKick(int iTeam) {
	int iAlive;
	for (int i=MaxClients; i>=1; i--) {
		if (!IsClientInGame(i) || !IsFakeClient(i) || IsClientSourceTV(i) || GetClientTeam(i) != iTeam) continue;
		if (GetTeamCommander(iTeam) == i || Guard_Is(i) || Train_Is(i)) continue;
		if (!IsPlayerAlive(i)) return i;
		if (!iAlive) iAlive = i;
	}
	return iAlive;
}

// ---- defensive hold: idle bots far from base walk back to a random spawn/post point ----
void Match_OnUnitOrdered(int iUnit) {
	if (1 <= iUnit <= MaxClients) g_fOrderedUntil[iUnit] = GetGameTime() + 60.0;
}

bool Match_EnemyAt(int iTeam, const float vecFrom[3], float fRange, float vecOut[3]) {
	float fBest = fRange;
	bool bHit;
	int iEnemy = iTeam == CS_TEAM_T ? CS_TEAM_CT : CS_TEAM_T;
	for (int i=1; i<=MaxClients; i++) {
		if (!IsClientInGame(i) || !IsPlayerAlive(i) || GetClientTeam(i) != iEnemy || g_bBodyHidden[i]) continue;
		float v[3]; GetClientAbsOrigin(i, v);
		float d = GetVectorDistance(vecFrom, v);
		if (d < fBest) { fBest = d; vecOut = v; bHit = true; }
	}
	return Npc_NearestEnemy(iEnemy, vecFrom, fBest, vecOut) || bHit;
}

// Office lanes are nav centers on cs_office: CT stairs, front offices, hall approach,
// T corridor mouth, side hall, T wing. Other maps use a ring around the team's own base.
int Soldier_NearestBot(int iClient) {
	float vecMe[3], vecEye[3], vecAng[3], vecFwd[3];
	GetClientAbsOrigin(iClient, vecMe);
	GetClientEyePosition(iClient, vecEye);
	GetClientEyeAngles(iClient, vecAng);
	GetAngleVectors(vecAng, vecFwd, NULL_VECTOR, NULL_VECTOR);
	int iBest, t = GetClientTeam(iClient);
	float fBest = 99999.0;
	for (int i = 1; i <= MaxClients; i++) {
		if (i == iClient || !IsUnitBot(i) || !IsPlayerAlive(i) || GetClientTeam(i) != t || g_bBodyHidden[i]) continue;
		float p[3], vecDir[3];
		GetClientAbsOrigin(i, p);
		float d = GetVectorDistance(vecMe, p);
		if (d > 150.0) continue;
		MakeVectorFromPoints(vecEye, p, vecDir);
		NormalizeVector(vecDir, vecDir);
		float fScore = d - GetVectorDotProduct(vecDir, vecFwd) * 50.0;
		if (fScore < fBest) { fBest = fScore; iBest = i; }
	}
	return iBest;
}

bool Soldier_OrderBot(int iClient) {
	int iBot = Soldier_NearestBot(iClient);
	if (!iBot) return false;
	g_iBotOrderTarget[iClient] = GetClientUserId(iBot);
	Menu hMenu = new Menu(MenuHandler_SoldierOrder);
	char sTitle[96];
	FormatEx(sTitle, sizeof(sTitle), "ORDER  %N\n ", iBot);
	hMenu.SetTitle(sTitle);
	hMenu.AddItem("follow", "Follow me");
	hMenu.AddItem("hq", "Attack Enemy HQ");
	hMenu.AddItem("a", "Defend office seats");
	hMenu.AddItem("b", "Defend base seats");
	hMenu.ExitButton = true;
	hMenu.Display(iClient, 15);
	return true;
}

public int MenuHandler_SoldierOrder(Menu hMenu, MenuAction eAction, int iClient, int iItem) {
	if (eAction == MenuAction_End) delete hMenu;
	else if (eAction == MenuAction_Select) {
		int iBot = GetClientOfUserId(g_iBotOrderTarget[iClient]);
		if (!iBot || !IsClientInGame(iBot) || !IsPlayerAlive(iBot) || !IsFakeClient(iBot)) {
			PrintHintText(iClient, "That soldier is gone");
			return 0;
		}
		char sInfo[12];
		hMenu.GetItem(iItem, sInfo, sizeof(sInfo));
		int t = GetClientTeam(iBot);
		g_iBotFollow[iBot] = 0;
		g_fCoverUntil[iBot] = 0.0;
		if (StrEqual(sInfo, "follow")) {
			g_iBotFollow[iBot] = iClient;
			PrintHintText(iClient, "%N will follow you", iBot);
		} else if (StrEqual(sInfo, "hq")) {
			int iOther = t == CS_TEAM_T ? CS_TEAM_CT : CS_TEAM_T;
			float vecAim[3];
			if (GetBasePoint(iOther, vecAim, false) && g_hSDKBotMoveTo != null) {
				SDKCall(g_hSDKBotMoveTo, iBot, vecAim, Route_Fastest);
				g_fOrderedUntil[iBot] = GetGameTime() + 120.0;
				g_fBotMoved[iBot] = GetGameTime();
			}
			PrintHintText(iClient, "%N is attacking the enemy HQ", iBot);
		} else {
			bool bOffice = StrEqual(sInfo, "a");
			float vecPost[3];
			if (Seat_GroupPoint(t, bOffice, iBot, vecPost) && g_hSDKBotMoveTo != null) {
				SDKCall(g_hSDKBotMoveTo, iBot, vecPost, Route_Fastest);
				g_fBotMoved[iBot] = GetGameTime();
				g_fOrderedUntil[iBot] = GetGameTime() + 45.0;
			}
			PrintHintText(iClient, "%N is defending %s seats", iBot, bOffice ? "office" : "base");
		}
	}
	return 0;
}

void Ai_ModeName(int iTeam, char[] s, int n) {
	int iMode = (iTeam >= CS_TEAM_T && iTeam <= CS_TEAM_CT) ? g_iAiMode[iTeam] : AI_MIX;
	if (iMode == AI_ATTACK) strcopy(s, n, "Attack");
	else if (iMode == AI_DEFEND) strcopy(s, n, "Defend");
	else strcopy(s, n, "Mix");
}

void Ai_Touch(int iTeam) {
	if (iTeam < CS_TEAM_T || iTeam > CS_TEAM_CT) return;
	float fNow = GetGameTime();
	for (int i = 1; i <= MaxClients; i++) {
		if (!IsClientInGame(i) || !IsFakeClient(i) || GetClientTeam(i) != iTeam) continue;
		if (g_fOrderedUntil[i] > fNow) continue;
		g_fCoverUntil[i] = 0.0;
		g_fBotMoved[i] = 0.0;
	}
}

void Bot_Move(int iBot, const float vec[3], float fNow) {
	if (g_hSDKBotMoveTo == null) return;
	SDKCall(g_hSDKBotMoveTo, iBot, vec, Route_Fastest);
	g_fBotMoved[iBot] = fNow;
}

bool Bot_Low(int iBot) {
	int iMax = GetEntProp(iBot, Prop_Data, "m_iMaxHealth");
	if (iMax < 1) iMax = 100;
	return GetClientHealth(iBot) * 100 < iMax * 40;
}

bool Bot_Free(int iBot, int iTeam, float fNow) {
	if (!IsUnitBot(iBot) || g_bBodyHidden[iBot] || GetClientTeam(iBot) != iTeam) return false;
	if (Guard_Hold(iBot) || Train_Hold(iBot) || g_iBotFollow[iBot]) return false;
	if (g_fOrderedUntil[iBot] > fNow) return false;
	return true;
}

int Bot_Role(int iBot, int iTeam, float fNow) {
	int iMode = g_iAiMode[iTeam];
	if (iMode == AI_ATTACK || iMode == AI_DEFEND) return iMode;
	int n, iRank;
	for (int i = 1; i <= MaxClients; i++) {
		if (!Bot_Free(i, iTeam, fNow)) continue;
		n++;
		if (i < iBot) iRank++;
	}
	if (n < 1) n = 1;
	return iRank < (n + 1) / 2 ? AI_ATTACK : AI_DEFEND;
}

int Bot_HealthyAlly(int iBot, int iTeam, float vecOut[3]) {
	float vecMe[3];
	GetClientAbsOrigin(iBot, vecMe);
	int iBest;
	float fBest = 1100.0;
	for (int i = 1; i <= MaxClients; i++) {
		if (i == iBot || !IsUnitBot(i) || g_bBodyHidden[i] || GetClientTeam(i) != iTeam) continue;
		int iMax = GetEntProp(i, Prop_Data, "m_iMaxHealth");
		if (iMax < 1) iMax = 100;
		if (GetClientHealth(i) * 100 < iMax * 55) continue;
		float p[3];
		GetClientAbsOrigin(i, p);
		float d = GetVectorDistance(vecMe, p);
		if (d < fBest) { fBest = d; iBest = i; vecOut = p; }
	}
	return iBest;
}

void Bot_Behind(const float vecAlly[3], const float vecThreat[3], float vecOut[3]) {
	float dx = vecAlly[0] - vecThreat[0];
	float dy = vecAlly[1] - vecThreat[1];
	float d = SquareRoot(dx * dx + dy * dy);
	if (d < 1.0) d = 1.0;
	vecOut[0] = vecAlly[0] + dx / d * 140.0;
	vecOut[1] = vecAlly[1] + dy / d * 140.0;
	vecOut[2] = vecAlly[2];
}

void Bot_StepBack(int iBot, int iTeam, float fDist, float vecOut[3]) {
	float vecMe[3], vecBase[3];
	GetClientAbsOrigin(iBot, vecMe);
	if (!GetBasePoint(iTeam, vecBase, false)) vecBase = vecMe;
	float dx = vecBase[0] - vecMe[0];
	float dy = vecBase[1] - vecMe[1];
	float d = SquareRoot(dx * dx + dy * dy);
	vecOut = vecMe;
	if (d < 1.0) return;
	vecOut[0] = vecMe[0] + dx / d * fDist;
	vecOut[1] = vecMe[1] + dy / d * fDist;
}

void Bot_PushHQ(int iBot, int iTeam, float vecOut[3]) {
	int iOther = iTeam == CS_TEAM_T ? CS_TEAM_CT : CS_TEAM_T;
	if (!GetBasePoint(iOther, vecOut, false)) GetClientAbsOrigin(iBot, vecOut);
	float fAng = float(iBot) * 0.85;
	vecOut[0] += Cosine(fAng) * 160.0;
	vecOut[1] += Sine(fAng) * 160.0;
}

void Bot_RushHome(int iBot, int iTeam, float fNow) {
	float vecHq[3], vecMe[3], vecEnemy[3];
	HQ_CorePoint(iTeam, vecHq);
	GetClientAbsOrigin(iBot, vecMe);
	if (Match_EnemyAt(iTeam, vecHq, 800.0, vecEnemy)) {
		if (GetVectorDistance(vecMe, vecEnemy) > 80.0 && fNow - g_fBotMoved[iBot] > 1.4) Bot_Move(iBot, vecEnemy, fNow);
		return;
	}
	if (GetVectorDistance(vecMe, vecHq) > 220.0 && fNow - g_fBotMoved[iBot] > 2.0) Bot_Move(iBot, vecHq, fNow);
}

void Bot_AttackThink(int iBot, int iTeam, float fNow) {
	if (g_fCoverUntil[iBot] > fNow) return;
	float vecMe[3], vecHq[3], vecEnemy[3];
	GetClientAbsOrigin(iBot, vecMe);
	Bot_PushHQ(iBot, iTeam, vecHq);
	bool bHurt = fNow - g_fLastHurt[iBot] < 1.6;
	if (Bot_Low(iBot)) {
		float vecAlly[3];
		int iAlly = Bot_HealthyAlly(iBot, iTeam, vecAlly);
		if (iAlly) {
			float d = GetVectorDistance(vecMe, vecAlly);
			float vecGo[3];
			if (d < 240.0) Bot_Behind(vecAlly, vecHq, vecGo);
			else vecGo = vecAlly;
			if (d > 80.0 && fNow - g_fBotMoved[iBot] > 2.2) Bot_Move(iBot, vecGo, fNow);
		} else if (bHurt && fNow - g_fBotMoved[iBot] > 2.0) {
			float vecBack[3];
			Bot_StepBack(iBot, iTeam, 140.0, vecBack);
			Bot_Move(iBot, vecBack, fNow);
			g_fCoverUntil[iBot] = fNow + 5.0;
		}
		return;
	}
	if (bHurt && fNow - g_fBotMoved[iBot] > 2.0 && g_fCoverUntil[iBot] < fNow - 2.0) {
		float vecBack[3];
		Bot_StepBack(iBot, iTeam, 90.0, vecBack);
		Bot_Move(iBot, vecBack, fNow);
		g_fCoverUntil[iBot] = fNow + 1.2;
		return;
	}
	if (Match_EnemyAt(iTeam, vecMe, 800.0, vecEnemy) && GetVectorDistance(vecMe, vecEnemy) > 60.0 && fNow - g_fBotMoved[iBot] > 1.2) {
		Bot_Move(iBot, vecEnemy, fNow);
		return;
	}
	if (fNow - g_fBotMoved[iBot] < 1.6) return;
	Bot_Move(iBot, vecHq, fNow);
}

void Bot_DefendThink(int iBot, int iTeam, float fNow) {
	int nDef, iSlot;
	for (int i = 1; i <= MaxClients; i++) {
		if (!Bot_Free(i, iTeam, fNow)) continue;
		if (Bot_Role(i, iTeam, fNow) != AI_DEFEND) continue;
		if (i < iBot) iSlot++;
		nDef++;
	}
	if (nDef < 1) nDef = 1;
	float vecPost[3], vecMe[3], vecEnemy[3];
	if (!Seat_DefendPoint(iTeam, iSlot, nDef, vecPost) && !GetBasePoint(iTeam, vecPost, false)) return;
	GetClientAbsOrigin(iBot, vecMe);
	if (Bot_Low(iBot)) {
		float vecAlly[3];
		int iAlly = Bot_HealthyAlly(iBot, iTeam, vecAlly);
		if (iAlly && GetVectorDistance(vecMe, vecAlly) < 500.0 && GetVectorDistance(vecAlly, vecPost) < 420.0) {
			float vecGo[3];
			Bot_Behind(vecAlly, vecPost, vecGo);
			if (fNow - g_fBotMoved[iBot] > 2.5) Bot_Move(iBot, vecGo, fNow);
			return;
		}
	}
	if (Match_EnemyAt(iTeam, vecMe, 700.0, vecEnemy) && GetVectorDistance(vecMe, vecEnemy) > 50.0) {
		if (fNow - g_fBotMoved[iBot] > 1.2) Bot_Move(iBot, vecEnemy, fNow);
		return;
	}
	if (Match_EnemyAt(iTeam, vecPost, 900.0, vecEnemy) && GetVectorDistance(vecMe, vecEnemy) > 80.0) {
		if (fNow - g_fBotMoved[iBot] > 1.4) Bot_Move(iBot, vecEnemy, fNow);
		return;
	}
	if (GetVectorDistance(vecMe, vecPost) > 120.0 && fNow - g_fBotMoved[iBot] > 1.8) Bot_Move(iBot, vecPost, fNow);
}

public Action Timer_BotDefend(Handle hTimer) {
	if (g_hSDKBotMoveTo == null || g_bSelfTestRunning || InLobby()) return Plugin_Continue;
	float fNow = GetGameTime();
	for (int i = 1; i <= MaxClients; i++) {
		if (!IsUnitBot(i) || g_bBodyHidden[i]) continue;
		if (Guard_Hold(i) || Train_Hold(i)) continue;
		if (g_iBotFollow[i]) {
			int iLead = g_iBotFollow[i];
			if (iLead < 1 || iLead > MaxClients || !IsClientInGame(iLead) || !IsPlayerAlive(iLead) || GetClientTeam(iLead) != GetClientTeam(i)) {
				g_iBotFollow[i] = 0;
			} else {
				float vecLead[3], vecMe[3];
				GetClientAbsOrigin(iLead, vecLead);
				GetClientAbsOrigin(i, vecMe);
				if (GetVectorDistance(vecMe, vecLead) > 110.0 && fNow - g_fBotMoved[i] > 1.2) Bot_Move(i, vecLead, fNow);
				continue;
			}
		}
		if (g_fOrderedUntil[i] > fNow) continue;
		if (GetEntProp(i, Prop_Send, "m_bIsDefusing")) continue;
		int t = GetClientTeam(i);
		if (t < CS_TEAM_T || t > CS_TEAM_CT) continue;
		if (HQ_UnderFire(t)) { Bot_RushHome(i, t, fNow); continue; }
		if (Bot_Role(i, t, fNow) == AI_DEFEND) Bot_DefendThink(i, t, fNow);
		else Bot_AttackThink(i, t, fNow);
	}
	return Plugin_Continue;
}

#define MAX_TAGS 24
#define TAG_LIFE 15.0
#define TAG_CHANNEL 5.0
int g_iTagEnt[MAX_TAGS] = {-1, ...};
int g_iTagTeam[MAX_TAGS];
int g_iTagValue[MAX_TAGS];
float g_fTagDie[MAX_TAGS];
float g_vecTag[MAX_TAGS][3];
float g_fTagStart[MAXPLAYERS+1];
float g_vecAlive[MAXPLAYERS+1][3];

void Tags_NoteAlive(int iClient) {
	if (iClient && IsPlayerAlive(iClient) && !g_bBodyHidden[iClient]) GetClientAbsOrigin(iClient, g_vecAlive[iClient]);
}

void Tags_MapStart() {
	Tags_RemoveOldRadios();
	for (int i=0; i<MAX_TAGS; i++) g_iTagEnt[i] = -1;
	PrecacheModel("sprites/glow01.vmt", true);
	CreateTimer(0.25, Timer_Tags, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

void Tags_RemoveOldRadios() {
	int iList[64], n, e = -1;
	while ((e = FindEntityByClassname(e, "prop_dynamic_override")) != -1 && n < 64) {
		char sModel[96];
		GetEntPropString(e, Prop_Data, "m_ModelName", sModel, sizeof(sModel));
		if (StrContains(sModel, "radio.mdl", false) != -1) iList[n++] = e;
	}
	for (int i=0; i<n; i++) if (IsValidEntity(iList[i])) RemoveEntity(iList[i]);
	int iSprite[32], nSprite;
	e = -1;
	while ((e = FindEntityByClassname(e, "env_sprite")) != -1 && nSprite < 32) {
		char sName[32];
		GetEntPropString(e, Prop_Data, "m_iName", sName, sizeof(sName));
		if (StrEqual(sName, "css_rts_intel")) iSprite[nSprite++] = e;
	}
	for (int i = 0; i < nSprite; i++) if (IsValidEntity(iSprite[i])) RemoveEntity(iSprite[i]);
}

void Tags_ClearSlot(int slot, bool bReturn) {
	if (bReturn && g_iTagValue[slot] > 0) {
		int t = g_iTagTeam[slot];
		if (CS_TEAM_T <= t <= CS_TEAM_CT) g_iIntel[t] += g_iTagValue[slot];
	}
	int e = g_iTagEnt[slot];
	if (e > 0 && IsValidEntity(e)) RemoveEntity(e);
	g_iTagEnt[slot] = -1;
	g_iTagValue[slot] = 0;
	for (int i=1; i<=MaxClients; i++) if (g_fTagStart[i] > 0.0) g_fTagStart[i] = 0.0;
}

public void Event_DogTag(Event hEvent, const char[] sName, bool bDontBroadcast) {
	int iVictim = GetClientOfUserId(hEvent.GetInt("userid"));
	if (!iVictim || !IsClientInGame(iVictim) || g_bBodyHidden[iVictim]) return;
	int t = GetClientTeam(iVictim);
	if (!(CS_TEAM_T <= t <= CS_TEAM_CT)) return;
	if (GetRandomFloat(0.0, 100.0) > 5.0) return;
	int iDrop = 50;
	float v[3];
	v = g_vecAlive[iVictim];
	if (v[0] == 0.0 && v[1] == 0.0 && v[2] == 0.0) GetClientAbsOrigin(iVictim, v);
	float vecFloor[3];
	if (SnapToFloor(v, vecFloor)) v = vecFloor;
	v[2] += 48.0;
	int slot = -1;
	for (int i=0; i<MAX_TAGS; i++) if (g_iTagEnt[i] <= 0 || !IsValidEntity(g_iTagEnt[i])) { slot = i; break; }
	if (slot == -1) return;
	int e = CreateEntityByName("env_sprite");
	if (e == -1) return;
	DispatchKeyValue(e, "model", "sprites/glow01.vmt");
	DispatchKeyValue(e, "scale", "0.12");
	DispatchKeyValue(e, "rendermode", "5");
	DispatchKeyValue(e, "renderamt", "255");
	DispatchKeyValue(e, "rendercolor", "255 196 40");
	DispatchKeyValue(e, "GlowProxySize", "6");
	DispatchKeyValue(e, "spawnflags", "1");
	DispatchKeyValue(e, "targetname", "css_rts_intel");
	DispatchKeyValueVector(e, "origin", v);
	DispatchSpawn(e);
	AcceptEntityInput(e, "ShowSprite");
	g_iTagEnt[slot] = e;
	g_iTagTeam[slot] = t;
	g_iTagValue[slot] = iDrop;
	g_fTagDie[slot] = GetGameTime() + TAG_LIFE;
	g_vecTag[slot] = v;
}

public Action Timer_Tags(Handle hTimer) {
	float fNow = GetGameTime();
	for (int n=0; n<MAX_TAGS; n++) {
		int e = g_iTagEnt[n];
		if (e <= 0 || !IsValidEntity(e)) { g_iTagEnt[n] = -1; g_iTagValue[n] = 0; continue; }
		if (fNow >= g_fTagDie[n]) { Tags_ClearSlot(n, true); continue; }
		float p[3];
		p = g_vecTag[n];
		p[2] += Sine(fNow * 4.0) * 5.0;
		TeleportEntity(e, p, NULL_VECTOR, NULL_VECTOR);
	}
	for (int i=1; i<=MaxClients; i++) {
		if (!IsClientInGame(i) || !IsPlayerAlive(i) || g_bBodyHidden[i] || g_eCommander[i].bEnabled) { g_fTagStart[i] = 0.0; continue; }
		float v[3]; GetClientAbsOrigin(i, v);
		int iNear = -1;
		float fBest = IsFakeClient(i) ? 560.0 : 120.0;
		for (int n=0; n<MAX_TAGS; n++) {
			if (g_iTagEnt[n] <= 0 || !IsValidEntity(g_iTagEnt[n])) continue;
			float d = GetVectorDistance(v, g_vecTag[n]);
			if (d < fBest) { fBest = d; iNear = n; }
		}
		if (IsFakeClient(i)) {
			int tBot = GetClientTeam(i);
			if (iNear == -1 || fBest > 110.0) {
				g_fTagStart[i] = 0.0;
				if (iNear != -1 && !HQ_UnderFire(tBot) && g_hSDKBotMoveTo != null && fNow - g_fBotMoved[i] > 1.0) {
					Bot_Move(i, g_vecTag[iNear], fNow);
					g_fOrderedUntil[i] = fNow + 1.2;
				}
				continue;
			}
			g_fOrderedUntil[i] = fNow + 0.6;
		}
		bool bGrab = IsFakeClient(i) || (iNear != -1 && (GetClientButtons(i) & IN_USE));
		if (!bGrab) { g_fTagStart[i] = 0.0; continue; }
		if (g_fTagStart[i] <= 0.0) g_fTagStart[i] = fNow;
		float fLeft = TAG_CHANNEL - (fNow - g_fTagStart[i]);
		float fFrac = 1.0 - (fLeft / TAG_CHANNEL);
		if (fFrac < 0.0) fFrac = 0.0;
		if (fFrac > 1.0) fFrac = 1.0;
		float a[3], b[3];
		a = g_vecTag[iNear]; b = g_vecTag[iNear];
		a[2] += 18.0; b[2] += 18.0;
		b[0] += 56.0 * fFrac;
		int iCol[4] = {255, 210, 60, 255};
		TE_SetupBeamPoints(a, b, PrecacheModel("sprites/laserbeam.vmt"), 0, 0, 0, 0.35, 2.4, 2.4, 1, 0.0, iCol, 0);
		TE_SendToAll();
		if (!IsFakeClient(i)) PrintHintText(i, "Intel +%d    %.0fs", g_iTagValue[iNear], fLeft > 0.0 ? fLeft : 0.0);
		if (fLeft > 0.0) continue;
		int t = GetClientTeam(i);
		int iGot = g_iTagValue[iNear];
		g_iTagValue[iNear] = 0;
		if (CS_TEAM_T <= t <= CS_TEAM_CT) { g_iIntel[t] += iGot; g_iIntelEarned[t] += iGot; }
		Tags_ClearSlot(iNear, false);
		g_fTagStart[i] = 0.0;
		if (!IsFakeClient(i)) PrintToChat(i, "\x04[RTS]\x01 Recovered \x04+%d Intel\x01.", iGot);
	}
	return Plugin_Continue;
}

// Team base = command post (or spawn centroid). bRandom: a random spawn point / post spot to hold.
bool GetBasePoint(int iTeam, float vecOut[3], bool bRandom) {
	float vecSpawns[64][3];
	int n = CollectSpawns(iTeam, vecSpawns);
	if (bRandom && n > 0 && GetRandomInt(0, 3) != 0) {
		vecOut = vecSpawns[GetRandomInt(0, n-1)];
		return true;
	}
	if (g_ePost[iTeam].bValid) { vecOut = g_ePost[iTeam].vecOrigin; return true; }
	if (!n) return false;
	vecOut = vecSpawns[0];
	return true;
}
