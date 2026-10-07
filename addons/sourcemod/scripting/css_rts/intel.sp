// css_rts/intel.sp -- team Intel economy, HUD, buy/drop blocking in the commander view
//
// Combined rule (DESIGN.md 1a):  income = floor(workers * yield * M) + oversight
//   M = mult_view (commander in view at post) | mult_alive | mult_dead (dead or no commander)
//   oversight = css_rts_intel_per_tick, only while the commander is in the view.
// M1 has no workers (CountProducingWorkers() == 0), so Intel only ticks while commanding.

enum CommanderState {
	CmdState_None = 0,
	CmdState_Dead,
	CmdState_Alive,
	CmdState_InView
};

int g_iIntel[4];
int g_iLastIncome[4];
int g_iBlockedBuys;
int g_iBlockedCmds;
Handle g_hIntelTimer;
Handle g_hHudIntel;

ConVar g_hCvarIntelBase;
ConVar g_hCvarIntelTick;
ConVar g_hCvarIntelPerTick;
ConVar g_hCvarWorkerYield;
ConVar g_hCvarMultView;
ConVar g_hCvarMultAlive;
ConVar g_hCvarMultDead;
ConVar g_hCvarIntelStart;

void Intel_Init() {
	g_hCvarIntelBase = CreateConVar("css_rts_intel_base", "5", "Flat Intel per second every team earns from match start", _, true, 0.0);
	g_hCvarIntelTick = CreateConVar("css_rts_intel_tick", "1.0", "Seconds between Intel ticks", _, true, 0.5);
	g_hCvarIntelPerTick = CreateConVar("css_rts_intel_per_tick", "0", "Oversight Intel per tick while the commander is in the command view", _, true, 0.0);
	g_hCvarWorkerYield = CreateConVar("css_rts_intel_worker_yield", "5", "Intel per seated worker per second", _, true, 0.0);
	g_hCvarMultView = CreateConVar("css_rts_intel_mult_view", "1.0", "Worker income multiplier while the commander is in the view", _, true, 0.0);
	g_hCvarMultAlive = CreateConVar("css_rts_intel_mult_alive", "1.0", "Worker income multiplier while the commander is alive elsewhere", _, true, 0.0);
	g_hCvarMultDead = CreateConVar("css_rts_intel_mult_dead", "1.0", "Worker income multiplier while the commander is dead / absent", _, true, 0.0);
	g_hCvarIntelStart = CreateConVar("css_rts_intel_start", "400", "Team Intel at map start", _, true, 0.0);
	g_hCvarIntelTick.AddChangeHook(OnIntelTickChanged);
	g_hHudIntel = CreateHudSynchronizer();
}

void Intel_MapStart() {
	for (int t=0; t<4; t++) { g_iIntel[t] = g_hCvarIntelStart.IntValue; g_iLastIncome[t] = 0; }
	Unlocks_Reset();
	g_hIntelTimer = null; // NO_MAPCHANGE timer was already freed by the map change
	RestartIntelTimer();
	CreateTimer(1.0, Timer_Hud, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public void OnIntelTickChanged(ConVar hCvar, const char[] sOld, const char[] sNew) {
	RestartIntelTimer();
}

void RestartIntelTimer() {
	delete g_hIntelTimer;
	g_hIntelTimer = CreateTimer(g_hCvarIntelTick.FloatValue, Timer_IntelTick, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

CommanderState GetCommanderState(int iTeam) {
	int iCmdr = GetTeamCommander(iTeam);
	if (!iCmdr) return CmdState_None;
	if (!IsPlayerAlive(iCmdr)) return CmdState_Dead;
	if (g_bPostView[iCmdr] && g_eCommander[iCmdr].bEnabled) return CmdState_InView;
	return CmdState_Alive;
}

// M1.5 hook: number of workers currently seated and producing for iTeam.
int CountProducingWorkers(int iTeam) {
	return CountSeatedWorkers(iTeam);
}

float GetIntelMult(int iTeam) {
	switch (GetCommanderState(iTeam)) {
		case CmdState_InView: return g_hCvarMultView.FloatValue;
		case CmdState_Alive: return g_hCvarMultAlive.FloatValue;
	}
	return g_hCvarMultDead.FloatValue;
}

int g_iIncomeHandicap;   // 0 even, 1 you half, 2 you double, 3 enemy half, 4 enemy double
int g_iHandicapHost;      // team the "you" side of the handicap applies to (0 = even)

float Intel_Handicap(int iTeam) {
	if (g_iIncomeHandicap == 0 || !g_iHandicapHost) return 1.0;
	bool bYou = iTeam == g_iHandicapHost;
	if (g_iIncomeHandicap == 1) return bYou ? 0.5 : 1.0;
	if (g_iIncomeHandicap == 2) return bYou ? 2.0 : 1.0;
	if (g_iIncomeHandicap == 3) return bYou ? 1.0 : 0.5;
	if (g_iIncomeHandicap == 4) return bYou ? 1.0 : 2.0;
	return 1.0;
}

int ComputeIntelIncome(int iTeam) {
	CommanderState eState = GetCommanderState(iTeam);
	float fMult = GetIntelMult(iTeam);
	int iIncome = CountProducingWorkers(iTeam) * RoundToFloor((g_hCvarWorkerYield.IntValue + Unlocks_WorkerBonus(iTeam)) * fMult);
	if (eState == CmdState_InView) iIncome += g_hCvarIntelPerTick.IntValue;
	iIncome += g_hCvarIntelBase.IntValue;
	iIncome = RoundToFloor(float(iIncome) * Intel_Handicap(iTeam));
	if (iIncome < 0) iIncome = 0;
	return iIncome;
}

public Action Timer_IntelTick(Handle hTimer) {
	if (InWarmup() || g_bMatchOver) return Plugin_Continue;
	for (int t=CS_TEAM_T; t<=CS_TEAM_CT; t++) {
		int iIncome = ComputeIntelIncome(t);
		g_iLastIncome[t] = iIncome;
		g_iIntel[t] += iIncome;
		g_iIntelEarned[t] += iIncome;
		Workers_OnIntelTick(t, RoundToFloor((g_hCvarWorkerYield.IntValue + Unlocks_WorkerBonus(t)) * GetIntelMult(t)));
	}
	Unlocks_Tick();
	return Plugin_Continue;
}

public Action Timer_Hud(Handle hTimer) {
	// v0.5.2: the Intel / match lines moved into the single HUD panel (hud.sp)
	EnsureTerminals();
	Workers_Ensure();
	Desks_Ensure();
	HQ_Ensure();
	return Plugin_Continue;
}

// ---- buy / drop blocking while in the commander view ----

void Intel_HookCommands() {
	static const char sCmds[][] = {"buy", "buymenu", "autobuy", "rebuy", "drop", "buyequip", "buyammo1", "buyammo2"};
	for (int i=0; i<sizeof(sCmds); i++) AddCommandListener(CmdListener_Block, sCmds[i]);
}

public Action CmdListener_Block(int iClient, const char[] sCmd, int iArgc) {
	iClient = ResolveClient(iClient);
	if (iClient && g_eCommander[iClient].bEnabled) {
		g_iBlockedCmds++;
		if (!IsFakeClient(iClient)) PrintHintText(iClient, "Not available in command view");
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

public Action CS_OnBuyCommand(int iClient, const char[] sWeapon) {
	if (iClient > 0 && g_eCommander[iClient].bEnabled) {
		g_iBlockedCmds++;
		return Plugin_Handled;
	}
	if (iClient > 0 && Unlocks_BlockBuy(iClient, sWeapon)) {
		g_iBlockedBuys++;
		return Plugin_Handled;
	}
	if (iClient > 0 && Armory_OnBuy(iClient, sWeapon)) {
		g_iBlockedBuys++;
		return Plugin_Handled;
	}
	return Plugin_Continue;
}
