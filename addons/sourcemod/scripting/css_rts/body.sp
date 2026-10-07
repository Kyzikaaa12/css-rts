// css_rts/body.sp -- bodyless Commander: alive (keeps team membership/HUD) but hidden, untouchable, parked

#define EF_NODRAW_FLAG		32
#define FSOLID_NOT_SOLID_FLAG	4

bool g_bBodyHidden[MAXPLAYERS+1];

void Body_OnClientPutInServer(int iClient) {
	SDKHook(iClient, SDKHook_SetTransmit, SDKHookCB_HiddenTransmit);
	g_bBodyHidden[iClient] = false;
	SDKHook(iClient, SDKHook_WeaponCanUse, SDKHookCB_WeaponCanUse);
}

public Action SDKHookCB_WeaponCanUse(int iClient, int iWeapon) {
	return g_bBodyHidden[iClient] ? Plugin_Handled : Plugin_Continue;
}

void HideCommanderBody(int iClient) {
	if (!IsPlayerAlive(iClient)) return;
	g_bBodyHidden[iClient] = true;
	Client_RemoveAllWeapons(iClient);
	SetEntityRenderMode(iClient, RENDER_NONE);
	SetEntProp(iClient, Prop_Send, "m_fEffects", GetEntProp(iClient, Prop_Send, "m_fEffects") | EF_NODRAW_FLAG);
	SetEntProp(iClient, Prop_Data, "m_takedamage", 0);
	SetEntProp(iClient, Prop_Send, "m_usSolidFlags", GetEntProp(iClient, Prop_Send, "m_usSolidFlags") | FSOLID_NOT_SOLID_FLAG);
	SetEntProp(iClient, Prop_Send, "m_CollisionGroup", 2); // COLLISION_GROUP_DEBRIS: nothing collides
	// Park below the post so bots can't see (and waste fire on) the invisible body
	int iTeam = GetClientTeam(iClient);
	float vecPark[3];
	if (CS_TEAM_T <= iTeam <= CS_TEAM_CT && g_ePost[iTeam].bValid) vecPark = g_ePost[iTeam].vecOrigin;
	else GetClientAbsOrigin(iClient, vecPark);
	vecPark[2] -= 2048.0;
	TeleportEntity(iClient, vecPark, NULL_VECTOR, view_as<float>({0.0, 0.0, 0.0}));
	SetEntityMoveType(iClient, MOVETYPE_NONE);
}

void RestoreCommanderBody(int iClient, bool bTeleportAndArm=true) {
	if (!g_bBodyHidden[iClient]) return;
	g_bBodyHidden[iClient] = false;
	if (!IsClientInGame(iClient) || !IsPlayerAlive(iClient)) return;
	SetEntityRenderMode(iClient, RENDER_NORMAL);
	SetEntProp(iClient, Prop_Send, "m_fEffects", GetEntProp(iClient, Prop_Send, "m_fEffects") & ~EF_NODRAW_FLAG);
	SetEntProp(iClient, Prop_Data, "m_takedamage", 2);
	SetEntProp(iClient, Prop_Send, "m_usSolidFlags", GetEntProp(iClient, Prop_Send, "m_usSolidFlags") & ~FSOLID_NOT_SOLID_FLAG);
	SetEntProp(iClient, Prop_Send, "m_CollisionGroup", 5); // COLLISION_GROUP_PLAYER
	SetEntityMoveType(iClient, MOVETYPE_WALK);
	if (!bTeleportAndArm) return;
	int iTeam = GetClientTeam(iClient);
	// The hidden commander is parked under the hub. Drop them on a real team spawn inside the buy zone.
	if (!Soldier_DropAtBuy(iClient)) CS_RespawnPlayer(iClient);
	GivePlayerItem(iClient, "weapon_knife");
	GivePlayerItem(iClient, iTeam == CS_TEAM_CT ? "weapon_usp" : "weapon_glock");
}

// Hidden commander body must not show on the radar / be sent to other clients:
// mark it "not alive" in the player resource (radar + scoreboard read m_bAlive) and block its
// entity transmission to everyone but the commander himself.
void Body_MapStart() {
	CreateTimer(1.0, Timer_HookPlayerResource, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_HookPlayerResource(Handle hTimer) {
	int iRes = FindEntityByClassname(-1, "cs_player_manager");
	if (iRes != -1) SDKHook(iRes, SDKHook_ThinkPost, SDKHookCB_ResourceThinkPost);
	return Plugin_Stop;
}

public void SDKHookCB_ResourceThinkPost(int iEnt) {
	for (int i=1; i<=MaxClients; i++) {
		if (g_bBodyHidden[i]) SetEntProp(iEnt, Prop_Send, "m_bAlive", 0, _, i);
		else if (IsClientInGame(i) && IsPlayerAlive(i)) {
			int t = GetClientTeam(i);
			int iEnemy = t == CS_TEAM_T ? CS_TEAM_CT : (t == CS_TEAM_CT ? CS_TEAM_T : 0);
			if (iEnemy && Ability_SweepActive(iEnemy)) SetEntProp(iEnt, Prop_Send, "m_bPlayerSpotted", 1, _, i);
		}
	}
}

public Action SDKHookCB_HiddenTransmit(int iEntity, int iClient) {
	if (iEntity != iClient && iEntity <= MaxClients && g_bBodyHidden[iEntity]) return Plugin_Handled;
	return Plugin_Continue;
}
