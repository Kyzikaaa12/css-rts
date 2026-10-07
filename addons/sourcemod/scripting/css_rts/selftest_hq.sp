// css_rts/selftest_hq.sp -- v0.5.3.1: HQ friendly-fire selftest (bots only, ~16 s). Allies crowd their own HQ and
// "shoot"/"nade" it (same code path as real bullet_impact / hegrenade_detonate events): it must stay at 100%.
// Enemy hits must count. HQ props must not be engine-damageable (bots never treat them as breakables).

float g_vecHTOld[MAXPLAYERS+1][3];

void SelfTestHQ_Init() {
	RegConsoleCmd("sm_rts_selftest_hq", cmdSelfTestHQ, "HQ friendly-fire selftest (bots only, ~16 s, needs a live match)");
}

public Action cmdSelfTestHQ(int iClient, int iArgs) {
	iClient = ResolveClient(iClient);
	if (!HasRTSAccess(iClient)) return Plugin_Handled;
	if (g_eGame != GS_Live) {
		if (InLobby()) Lobby_BeginMatch();
		PrintToServer("[RTS-SELFTEST] scenario skipped: not live (started the match) - run again in ~20 s");
		return Plugin_Handled;
	}
	g_iSTPass = g_iSTFail = 0;
	PrintToServer("[RTS-SELFTEST] scenario hq friendly fire (~16s)");
	HQ_Reset();
	for (int t=CS_TEAM_T; t<=CS_TEAM_CT; t++) {
		char sT[4]; TeamShortName(t, sT, sizeof(sT));
		ST(g_bHQFit[t], "hq_wall_fit", "%s %s", sT, g_sHQWhy[t]);
		int iParts, iDmgable;
		for (int k=0; k<HQ_PARTS; k++) {
			int e = EntRefToEntIndex(g_iHQPart[t][k]);
			if (e <= 0) continue;
			iParts++;
			if (GetEntProp(e, Prop_Data, "m_takedamage") != 0) iDmgable++;
		}
		ST(iParts >= 2 && iDmgable == 0, "hq_parts_not_breakable", "%s parts %d damageable %d", sT, iParts, iDmgable);
		// park allied bots right in front of their HQ and fire friendly hits
		int n;
		for (int i=1; i<=MaxClients; i++) {
			if (!IsClientInGame(i) || !IsFakeClient(i) || !IsPlayerAlive(i) || GetClientTeam(i) != t || g_bBodyHidden[i]) continue;
			float p[3];
			HQ_WallLocal(g_vecHQWall[t], g_fHQYaw[t], -60.0 + 40.0 * n, 120.0, p);
			p[2] += 8.0;
			GetClientAbsOrigin(i, g_vecHTOld[i]);
			TeleportEntity(i, p, NULL_VECTOR, ZERO_VECTOR);
			float h[3]; h = g_ePost[t].vecHQOrigin; h[2] += 40.0;
			for (int b=0; b<20; b++) HQ_OnImpact(i, h, 12);
			HQ_OnGrenade(i, h);
			if (++n >= 3) break;
		}
		ST(n > 0 && g_iHQHealth[t] == g_hCvarHQHealth.IntValue, "hq_friendly_hits_ignored", "%s allies %d hp %d%%", sT, n, HQ_Percent(t));
	}
	CreateTimer(15.0, Timer_HTCheck, _, TIMER_FLAG_NO_MAPCHANGE);
	return Plugin_Handled;
}

public Action Timer_HTCheck(Handle h) {
	for (int t=CS_TEAM_T; t<=CS_TEAM_CT; t++) {
		char sT[4]; TeamShortName(t, sT, sizeof(sT));
		ST(g_iHQHealth[t] == g_hCvarHQHealth.IntValue && !g_bHQDestroyed[t], "hq_100_with_allies_around", "%s %d%% after 15 s", sT, HQ_Percent(t));
		LogMessage("[RTS] HQ proof: %s HQ %d%% after 15 s with only allies around (bots fired 20 friendly bullets + 1 HE at it)", sT, HQ_Percent(t));
	}
	// an enemy hit must count
	int iEnemy = 0;
	for (int i=1; i<=MaxClients && !iEnemy; i++) if (IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == CS_TEAM_T) iEnemy = i;
	if (iEnemy) {
		float v[3]; v = g_ePost[CS_TEAM_CT].vecHQOrigin; v[2] += 40.0;
		HQ_OnImpact(iEnemy, v, 12);
		ST(g_iHQHealth[CS_TEAM_CT] < g_hCvarHQHealth.IntValue, "hq_enemy_hit_counts", "CT hp %d", g_iHQHealth[CS_TEAM_CT]);
	}
	HQ_Reset();
	PrintToServer("[RTS-SELFTEST] DONE: %d passed, %d failed", g_iSTPass, g_iSTFail);
	return Plugin_Stop;
}
