#pragma semicolon 1

#define DEBUG

#define PLUGIN_AUTHOR			"Joshua Gibson (port of geominorai/sm-rts-starter)"
#define PLUGIN_VERSION			"0.7.4"
#define GAMEDATA_FILE			"css_rts.games"

#define LASER_MODEL				"sprites/laserbeam.vmt"

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>
#include <smlib>

#define MOUSE_SENSITIVITY		0.0004

#define CLAMP_MOUSE_MIN_X		0.01
#define CLAMP_MOUSE_MAX_X		0.99

#define CLAMP_MOUSE_MIN_Y		0.02
#define CLAMP_MOUSE_MAX_Y		0.99

#define DEFAULT_MIN_ZOOM		80.0
#define DEFAULT_ASPECT_RATIO	1.77777777777777777777777777777777 // 16:9 for 1920x1080

#define ROTATION_KEYPRESS_SPEED	0.025

#define SCROLL_SPEED			500.0
#define SCROLL_DECEL_MULTIPLIER	0.9

#define ZOOM_SPEED				3000.0
#define ZOOM_DECEL_MULTIPLIER	0.9

#define MOUSE2_DRAG_START_DELAY	0.18
#define MOUSE2_DRAG_MIN_DIST	0.045
#define MOUSE2_DRAG_SPEED_MULT	4.0

#define DEFAULT_ANGLES			{45.0, 0.0, 0.0}
#define ZERO_VECTOR				{0.0, 0.0, 0.0}

#define AXIS_OFFSET				0.19634954084936207740391521145497 // FLOAT_PI/16

#define POSITIVE_INFINITY		view_as<float>(0x7F800000)
#define NEGATIVE_INFINITY		view_as<float>(0xFF800000)

#define COLOR_WHITE				{255, 255, 255, 255}
#define COLOR_RED				{255,   0,   0, 255}
#define COLOR_YELLOW			{255, 255,   0, 255}
#define COLOR_GREEN				{  0, 255,   0, 255}
#define COLOR_GRAY				{ 128,  128,  128, 255}

#define HEALTH_BAR_HP_SCALE		0.0001
#define HEALTH_BAR_COLOR_FULL 	{  0, 255, 0, 255}
#define HEALTH_BAR_COLOR_LOW 	{255, 0  , 0, 255}
#define HEALTH_BAR_LOW_PCT		0.3333	// Health percentage minimum before considered low

#define HUD_TEXT_COLOR_IDLE		{255, 255, 255, 255}
#define HUD_TEXT_COLOR_SCROLL	{  0, 255,   0, 255}
#define HUD_TEXT_COLOR_SELECT	{  0, 255,   0, 255}

#define CURSOR_DEFAULT			"+"
#define CURSOR_SELECTABLE		"[ ]"
#define CURSOR_MOVE				"><"

char g_sScrollCursors[8][8] = {
	"^",
	"/",
	"<",
	".",
	"v",
	".",
	">",
	"\\"
};

enum struct Commander {
	bool bEnabled;

	int iFOV;
	int iDefaultFOV;

	bool bHasForceTauntCamProp;
	bool bBackupForceTauntCam;
	int hBackupObsTarget;
	Obs_Mode iBackupObsMode;

	char sCursor[8];

	float vecMins[3];
	float vecMaxs[3];
	float fMinZoom;

	float fAspectRatio;
	int iFocusEntRef;
	int iCameraEntRef;
	int iViewControlEntRef;

	float vecVector[3];
	float fDistance;
	float fMouse[2];

	bool bMouseButton1Down;
	bool bMouseButton2Down;
	ArrayList hSelectedUnits;

	bool bMoving;
	bool bMoveDragging;
	bool bRotating;
	bool bDragging;
	bool bZoomingIn;
	bool bZoomingOut;

	float vecRotatingStartVector[3];
	float vecRotatingStartDistance;
	float fRotatingStartMouse[2];
	float fRotatingKeyPress;

	float vecMoveDragVel[3];

	float fMouseDragStart[2];
	float fMouseDragStartTime;
	float vecSelectionVerticies[12];

	int iSelectBeamsEntRef[4];

	void SetSelectionVertex(int iIdx, float vecVertex[3]) {
		this.vecSelectionVerticies[3*iIdx  ] = vecVertex[0];
		this.vecSelectionVerticies[3*iIdx+1] = vecVertex[1];
		this.vecSelectionVerticies[3*iIdx+2] = vecVertex[2];
	}

	void GetSelectionVertex(int iIdx, float vecVertex[3]) {
		vecVertex[0] = this.vecSelectionVerticies[3*iIdx  ];
		vecVertex[1] = this.vecSelectionVerticies[3*iIdx+1];
		vecVertex[2] = this.vecSelectionVerticies[3*iIdx+2];
	}

	bool SelectionContains(float vecVertex[3]) {
		float vecVectors[4][3];
		this.GetSelectionVertex(0, vecVectors[0]);
		this.GetSelectionVertex(1, vecVectors[1]);
		this.GetSelectionVertex(2, vecVectors[2]);
		this.GetSelectionVertex(3, vecVectors[3]);

		float vecFocusPos[3];
		Entity_GetAbsOrigin(EntRefToEntIndex(this.iFocusEntRef), vecFocusPos);

		float vecCameraPos[3];
		Entity_GetAbsOrigin(EntRefToEntIndex(this.iCameraEntRef), vecCameraPos);

		AddVectors(vecFocusPos, vecCameraPos, vecCameraPos);

		SubtractVectors(vecVectors[0], vecCameraPos, vecVectors[0]);
		SubtractVectors(vecVectors[1], vecCameraPos, vecVectors[1]);
		SubtractVectors(vecVectors[2], vecCameraPos, vecVectors[2]);
		SubtractVectors(vecVectors[3], vecCameraPos, vecVectors[3]);

		float vecNormals[4][3];
		GetVectorCrossProduct(vecVectors[0], vecVectors[1], vecNormals[0]);
		GetVectorCrossProduct(vecVectors[1], vecVectors[2], vecNormals[1]);
		GetVectorCrossProduct(vecVectors[2], vecVectors[3], vecNormals[2]);
		GetVectorCrossProduct(vecVectors[3], vecVectors[0], vecNormals[3]);

		float vecVertexVector[3];
		SubtractVectors(vecVertex, vecCameraPos, vecVertexVector);

		return
			GetVectorDotProduct(vecVertexVector, vecNormals[0]) > 0 &&
			GetVectorDotProduct(vecVertexVector, vecNormals[1]) > 0 &&
			GetVectorDotProduct(vecVertexVector, vecNormals[2]) > 0 &&
			GetVectorDotProduct(vecVertexVector, vecNormals[3]) > 0;
	}
}

enum struct UnitSelection {
	int iUnitEntRef;
	int iHealthBeamEntRef[3];

	void Init(int iSelectedEntity) {
		this.iUnitEntRef = EntIndexToEntRef(iSelectedEntity);
		this.iHealthBeamEntRef = {INVALID_ENT_REFERENCE, INVALID_ENT_REFERENCE, INVALID_ENT_REFERENCE};
	}
}

Commander g_eCommander[MAXPLAYERS+1];



// CSS: CCSBot::MoveTo(const Vector &pos, RouteType route) -- drives bot units via the
// built-in CS bot nav-mesh pathing. Optional: if gamedata is missing, MoveUnit is a no-op.
Handle g_hSDKBotMoveTo;

ConVar g_hCvarPublic;
ConVar g_hCvarUseRange;
ConVar g_hCvarAutoCommander;
ConVar g_hCvarFirstHuman;
bool g_bDeclinedCmdr[MAXPLAYERS+1];
ConVar g_hCvarRequireTerminal;
ConVar g_hCvarAutoBots;
ConVar g_hCvarJoinMenu;
bool g_bSelfTestRunning;
bool g_bMatchOver;
bool g_bUsedCreateSettings;
float g_fWarmupEnd;
ConVar g_hCvarBodyless;
ConVar g_hCvarZoomSpeed;
ConVar g_hCvarZoomStep;
ConVar g_hCvarZoomMax;
float g_fZoomTarget[MAXPLAYERS+1];

#include "css_rts/config.sp"
#include "css_rts/lobby_state.sp"
#include "css_rts/body.sp"
#include "css_rts/countdown.sp"
#include "css_rts/post.sp"
#include "css_rts/role.sp"
#include "css_rts/intel.sp"
#include "css_rts/match.sp"
#include "css_rts/nav.sp"
#include "css_rts/npc.sp"
#include "css_rts/workers.sp"
#include "css_rts/desks.sp"
#include "css_rts/hq.sp"
#include "css_rts/unlocks.sp"
#include "css_rts/armory.sp"
#include "css_rts/abilities.sp"
#include "css_rts/cmdmenu.sp"
#include "css_rts/wcmds.sp"
#include "css_rts/armorycmds.sp"
#include "css_rts/camera.sp"
#include "css_rts/markers.sp"
#include "css_rts/ghost.sp"
#include "css_rts/build.sp"
#include "css_rts/train.sp"
#include "css_rts/lobby.sp"
#include "css_rts/hud.sp"
#include "css_rts/wheel.sp"
#include "css_rts/autojoin.sp"
#include "css_rts/menuconf.sp"
#include "css_rts/lobbymatch.sp"
#include "css_rts/commands.sp"
#include "css_rts/selftest.sp"
#include "css_rts/selftest_lobby.sp"
#include "css_rts/selftest_sides.sp"
#include "css_rts/selftest_wheel.sp"
#include "css_rts/proof.sp"
#include "css_rts/selftest_hq.sp"

public void OnAllPluginsLoaded() {
	// !noclip for the host in test games (only if no other plugin, e.g. funcommands, owns sm_noclip)
	if (!CommandExists("sm_noclip")) RegConsoleCmd("sm_noclip", cmdRtsNoclip, "Toggle noclip (CSS RTS: listen host / css_rts_public)");
}

public Action cmdRtsNoclip(int iClient, int iArgs) {
	iClient = ResolveClient(iClient);
	if (iClient <= 0 || !HasRTSAccess(iClient)) return Plugin_Handled;
	if (!IsPlayerAlive(iClient)) { ReplyToCommand(iClient, "[RTS] noclip: you need to be alive (soldier)"); return Plugin_Handled; }
	bool bOn = GetEntityMoveType(iClient) != MOVETYPE_NOCLIP;
	SetEntityMoveType(iClient, bOn ? MOVETYPE_NOCLIP : MOVETYPE_WALK);
	ReplyToCommand(iClient, "[RTS] noclip %s", bOn ? "ON" : "OFF");
	LogMessage("[RTS] noclip %s for %L", bOn ? "on" : "off", iClient);
	return Plugin_Handled;
}

bool HasRTSAccess(int iClient) {
	if (iClient == 0 || g_hCvarPublic.BoolValue) {
		return true;
	}

	// Listen server host always has access
	if (!IsDedicatedServer() && iClient == ResolveClient(0)) {
		return true;
	}

	if (CheckCommandAccess(iClient, "sm_rts_access", ADMFLAG_ROOT)) {
		return true;
	}

	ReplyToCommand(iClient, "[RTS] No access (set css_rts_public 1 or add yourself as root admin)");
	return false;
}

enum RouteType {
	Route_Default = -1,
	Route_Fastest = 0,
	Route_Safest = 1,
	Route_Retreat = 2
};

public Plugin myinfo = {
	name = "CSS RTS",
	author = PLUGIN_AUTHOR,
	description = "Real-time-strategy game mode for Counter-Strike: Source",
	version = PLUGIN_VERSION,
	url = "https://github.com/geominorai/sm-rts-starter (upstream)"
};

void Rts_ForceLan() {
	ConVar hLan = FindConVar("sv_lan");
	if (hLan) hLan.SetInt(1);
	ConVar hNet = FindConVar("sv_use_steam_networking");
	if (hNet) hNet.SetInt(0);
	ConVar hAdv = FindConVar("sv_allow_server_adverisement_to_master_server");
	if (hAdv) hAdv.SetInt(0);
}

public void OnPluginStart() {
	if (GetEngineVersion() != Engine_CSS) {
		SetFailState("This plugin is for Counter-Strike: Source only");
	}
	Rts_ForceLan();

	LoadGameData();

	RegConsoleCmd("sm_rts", cmdRTS, "Enter RTS mode");

	RegConsoleCmd("sm_rts_zoom_in", cmdRTSZoomIn, "RTS zoom in");
	RegConsoleCmd("sm_rts_zoom_out", cmdRTSZoomOut, "RTS zoom out");

	RegConsoleCmd("sm_rts_aspect_ratio", cmdRTSAspectRatio, "Set RTS aspect ratio");

	// Debug: exercise bot-unit orders from the server console without a commander client
	RegConsoleCmd("sm_rts_debug_botmove", cmdDebugBotMove, "Order all bot units to move to <x> <y> <z>");
	RegConsoleCmd("sm_rts_debug_units", cmdDebugUnits, "List bot units and positions");
	RegConsoleCmd("sm_rts_debug_selftest", cmdDebugSelfTest, "Order all bots to <x> <y> <z> after <delay> s, report distance after <check> s");
	RegConsoleCmd("sm_rts_squad", cmdSquad, "Spawn <n> (default 2) bot units on your team");

	RegConsoleCmd("sm_rts_noclip", cmdRtsNoclip, "Toggle noclip for yourself (listen host / css_rts_public; test games)");
	g_hCvarPublic = CreateConVar("css_rts_public", "0", "1 = any player may use sm_rts* debug commands (testing); 0 = root admin only (listen host always allowed)", _, true, 0.0, true, 1.0);
	g_hCvarUseRange = CreateConVar("css_rts_use_range", "110", "Max distance (units) from eye to terminal for USE", _, true, 32.0);
	g_hCvarFirstHuman = CreateConVar("css_rts_commander_first_human", "1", "1 = the first human on a team becomes its Commander automatically", _, true, 0.0, true, 1.0);
	g_hCvarAutoCommander = CreateConVar("css_rts_commander_auto", "1", "1 = first player to USE a free team terminal becomes commander", _, true, 0.0, true, 1.0);
	g_hCvarRequireTerminal = CreateConVar("css_rts_require_terminal", "0", "1 = command view only via USE on the terminal; 0 = F2/!rts also enter it anywhere (testing)", _, true, 0.0, true, 1.0);
	g_hCvarAutoBots = CreateConVar("css_rts_autobots", "1", "1 = on map start set bot_quota_mode fill / bot_quota css_rts_bot_quota / join any team", _, true, 0.0, true, 1.0);
	g_hCvarJoinMenu = CreateConVar("css_rts_join_menu", "1", "1 = show the Commander/Soldier menu on first spawn", _, true, 0.0, true, 1.0);
	g_hCvarZoomSpeed = CreateConVar("css_rts_zoom_speed", "4.0", "Commander camera zoom easing rate (1/s; higher = snappier)", _, true, 0.1, true, 30.0);
	g_hCvarZoomStep = CreateConVar("css_rts_zoom_step", "48", "Zoom distance change per mouse-wheel notch (units)", _, true, 4.0);
	g_hCvarZoomMax = CreateConVar("css_rts_zoom_max", "9000", "Max commander camera distance (units; the camera ignores walls/roofs, so this can go far above the map)", _, true, 300.0);
	g_hCvarBodyless = CreateConVar("css_rts_commander_bodyless", "1", "1 = Commander has no body (hidden, untouchable, always in the RTS view); 0 = v0.2 style exposed body at the post", _, true, 0.0, true, 1.0);
	Countdown_Init();
	Intel_Init();
	Match_Init();
	Markers_Init();
	Workers_Init();
	Camera_Init();
	Lobby_Init();
	MenuConf_Init();
	Desks_Init();
	HQ_Init();
	AutoJoin_Init();
	Hud_Init();
	CmdMenu_Init();
	Build_Init();
	Wheel_Init();
	SelfTestSides_Init();
	SelfTestWheel_Init();
	Proof_Init();
	SelfTestHQ_Init();
	Armory_Init();
	Abilities_Init();
	ArmoryCmds_Init();
	LobbyTest_Init();
	Unlocks_Init();
	WCmds_Init();
	AutoExecConfig(true, "css_rts");

	LoadTranslations("common.phrases");
	M1_RegisterCommands();
	SelfTest_Register();
	Intel_HookCommands();
	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	RegConsoleCmd("sm_rtshelp", cmdHelp, "CSS RTS help");

	HookEvent("player_death", Event_PlayerChangeState);
	HookEvent("player_spawn", Event_PlayerChangeState);

	// CSS: no player_changeclass event (TF2-only); player_team exists in CSS
	HookEvent("player_team", Event_PlayerChangeState);

	// Late load: map is already running
	// (SourceMod itself calls OnMapStart/OnConfigsExecuted for late-loaded plugins)
	if (IsServerProcessing() || GetClientCount(false) > 0) {
		for (int i=1; i<=MaxClients; i++) {
			if (IsClientInGame(i)) OnClientPutInServer(i);
		}
	}
}

public void OnConfigsExecuted() {
	Rts_ForceLan();
	// v0.5.3.1: test settings live in a cfg the PLUGIN executes (no "Unknown command" noise before SourceMod loads)
	if (FileExists("cfg/sourcemod/css_rts_test.cfg")) ServerCommand("exec sourcemod/css_rts_test.cfg");
	// AutoExecConfig just wrote css_rts.cfg defaults (intel 400, host ct, 5 soldiers) over the Create Server choices.
	MenuConf_Apply();
	if (!g_hCvarAutoBots.BoolValue) {
		return;
	}
	// Zero-config: bot balancer keeps css_rts_fps_per_team FPS players per team; continuous-mode settings
	Match_ApplyServerSettings();
}

public void OnGameFrame() {
	Npc_GameFrame();
	Camera_GameFrame();
	Hud_GameFrame();
}

public void Event_RoundStart(Event hEvent, const char[] sName, bool bDontBroadcast) {
	EnsureTerminals();
	Workers_Ensure();
	Desks_Ensure();
	HQ_Ensure();
	Hostages_Clear();
}

int g_iHostageBlocks;

// RTS Create has no hostage rescue. Block new ones, and remove any the map already spawned.
public void OnEntityCreated(int entity, const char[] classname) {
	if (StrEqual(classname, "hostage_entity")) SDKHook(entity, SDKHook_Spawn, Hostages_BlockSpawn);
}

public Action Hostages_BlockSpawn(int entity) {
	g_iHostageBlocks++;
	RequestFrame(Hostages_RemoveRef, EntIndexToEntRef(entity));
	return Plugin_Handled;
}

public Action Timer_HostageReport(Handle hTimer) {
	int n, e = -1;
	while ((e = FindEntityByClassname(e, "hostage_entity")) != -1) n++;
	LogMessage("[RTS] hostages blocked %d, still on map %d", g_iHostageBlocks, n);
	return Plugin_Stop;
}

void Hostages_RemoveRef(int iRef) {
	int e = EntRefToEntIndex(iRef);
	if (e > MaxClients) RemoveEntity(e);
}

void Hostages_Clear() {
	int n, e = -1;
	while ((e = FindEntityByClassname(e, "hostage_entity")) != -1) {
		RemoveEntity(e);
		n++;
	}
	if (n) LogMessage("[RTS] removed %d hostages", n);
}

public void OnClientPutInServer(int iClient) {
	g_bPostView[iClient] = false;
	g_bMenuShown[iClient] = false;
	g_bWantsCommander[iClient] = false;
	g_iLastButtons[iClient] = 0;
	SDKHook(iClient, SDKHook_OnTakeDamageAlivePost, SDKHookCB_OnTakeDamagePost);
	Body_OnClientPutInServer(iClient);
	AutoJoin_OnClientPutInServer(iClient);
	Hud_OnClientPutInServer(iClient);
	CancelPending(iClient);
	if (!IsFakeClient(iClient)) {
		ClientCommand(iClient, "bind F1 bunny_on");
	}
}

public void SDKHookCB_OnTakeDamagePost(int iVictim, int iAttacker, int iInflictor, float fDamage, int iDamageType) {
	if (g_bPostView[iVictim] && fDamage > 0.0) {
		RequestFrame(Frame_ExitDamage, GetClientUserId(iVictim));
	}
}

public void Frame_ExitDamage(int iUserId) {
	int iClient = GetClientOfUserId(iUserId);
	if (iClient && g_bPostView[iClient]) {
		ExitCommanderView(iClient, "you took damage");
	}
}

public Action cmdHelp(int iClient, int iArgs) {
	iClient = ResolveClient(iClient);
	ReplyToCommand(iClient, "[RTS] !rts / F2 = role menu or toggle command view | !commander = take the role | !uncommander | E on your terminal = command view");
	return Plugin_Handled;
}

public void OnPluginEnd() {
	for (int i=1; i<=MaxClients; i++) {
		ResetClient(i);
	}
	for (int i=1; i<=MaxClients; i++) {
		if (IsClientInGame(i) && g_bBodyHidden[i]) {
			RestoreCommanderBody(i);
		}
	}
	Npc_RemoveAll();
	RemoveTerminals();
}

public void OnMapStart() {
	Rts_ForceLan();
	ServerCommand("mp_buytime 9999");
	ServerCommand("mp_playerid 0");
	g_iHostageBlocks = 0;
	PrecacheModel(LASER_MODEL);
	for (int t=0; t<4; t++) {
		g_iCommanderUserId[t] = 0;
		g_iTerminalRef[t] = INVALID_ENT_REFERENCE;
	}
	RemoveTerminals();
	Npc_RemoveAll();
	Npc_MapStart();
	LoadMapConfig();
	for (int t=CS_TEAM_T; t<=CS_TEAM_CT; t++) HQ_FitPost(t);   // v0.5.3.1: hub flush against a wall (before desks)
	Nav_Load();
	PrecacheTerminals();
	Intel_MapStart();
	Countdown_MapStart();
	Match_MapStart();
	Markers_MapStart();
	Workers_MapStart();
	Unlocks_MapStart();
	Desks_MapStart();
	Desks_Ensure();
	Hostages_Clear();
	CreateTimer(2.0, Timer_HostageReport, _, TIMER_FLAG_NO_MAPCHANGE);
	HQ_MapStart();
	Body_MapStart();
	Lobby_MapStart();
	Hud_MapStart();
	Build_MapStart();
	Train_MapStart();
	Tags_MapStart();
	Wheel_MapStart();
	Armory_MapStart();
	Abilities_MapStart();
	EnsureTerminals();
	LogMessage("[RTS] map start finished");
}

public void OnMapEnd() {
	for (int i=1; i<=MaxClients; i++) {
		ResetClient(i);
	}
}

public void OnClientDisconnect(int iClient) {
	Guard_ClearClient(iClient);
	Train_ClearClient(iClient);
	ResetClient(iClient);
	ReleaseCommander(iClient, true);
	g_bPostView[iClient] = false;
	g_bDeclinedCmdr[iClient] = false;
}

public Action OnPlayerRunCmd(int iClient, int &iButtons, int &iImpulse, float vecVel[3], float vecAng[3], int &iWeapon, int &iSubType, int &iCmdNum, int &iTickCount, int &iSeed, int iMouse[2]) {
	Tags_NoteAlive(iClient);
	int iLastButtons = g_iLastButtons[iClient];
	g_iLastButtons[iClient] = iButtons;
	// Bots never trigger terminals by themselves (their AI taps USE); the selftest simulates USE explicitly
	bool bUsePressed = (iButtons & IN_USE) && !(iLastButtons & IN_USE) && !IsFakeClient(iClient);

	if (!g_eCommander[iClient].bEnabled) {
		if (bUsePressed && IsPlayerAlive(iClient)) {
			if (!Soldier_OrderBot(iClient)) TryUseTerminal(iClient);
		}
		return Plugin_Continue;
	}

	if (bUsePressed && !g_hCvarBodyless.BoolValue && GetGameTime() - g_fViewToggleTime[iClient] >= 0.4) {
		ExitCommanderView(iClient, "use");
		iButtons &= ~IN_USE;
		return Plugin_Changed;
	}

	// Camera reads the raw buttons, then we strip them so the commander's body
	// doesn't shoot/jump/use/move while in the commander view (CSS-specific need:
	// in TF2 the starter relied on deathcam + FL_ATCONTROLS only).
	if (!IsFakeClient(iClient)) {
		ProcessCameraControls(iClient, iButtons, iLastButtons, iMouse);
	}

	iButtons &= ~(IN_ATTACK | IN_ATTACK2 | IN_ATTACK3 | IN_JUMP | IN_DUCK | IN_USE | IN_RELOAD
		| IN_FORWARD | IN_BACK | IN_MOVELEFT | IN_MOVERIGHT | IN_LEFT | IN_RIGHT | IN_SPEED);
	vecVel[0] = vecVel[1] = vecVel[2] = 0.0;
	iImpulse = 0;
	iWeapon = 0;

	return Plugin_Changed;
}

// CSS: TF2_OnConditionAdded/TFCond_Taunting removed -- CSS has no taunts that override the view.

void LoadGameData() {
	GameData hConf = new GameData(GAMEDATA_FILE);
	if (hConf == null) {
		LogError("Gamedata %s.txt not found; bot unit orders disabled", GAMEDATA_FILE);
		return;
	}

	StartPrepSDKCall(SDKCall_Player);
	if (PrepSDKCall_SetFromConf(hConf, SDKConf_Signature, "CCSBot::MoveTo")) {
		PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByRef);
		PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
		g_hSDKBotMoveTo = EndPrepSDKCall();
	}

	if (g_hSDKBotMoveTo == null) {
		LogError("Failed to set up SDKCall CCSBot::MoveTo; bot unit orders disabled");
	}

	delete hConf;
}

// Custom callbacks

public Action Event_PlayerChangeState(Event hEvent, const char[] sName, bool bDontBroadcast) {
	int iClient = GetClientOfUserId(hEvent.GetInt("userid"));
	if (!iClient) {
		return Plugin_Continue;
	}

	if (g_eCommander[iClient].bEnabled) {
		ResetClient(iClient);
		strcopy(g_sLastExitReason[iClient], sizeof(g_sLastExitReason[]), sName);
	}

	if (StrEqual(sName, "player_team")) {
		int iNewTeam = hEvent.GetInt("team");
		int iCmdTeam = GetCommanderTeam(iClient);
		if (iCmdTeam && iCmdTeam != iNewTeam) {
			ReleaseCommander(iClient, true);
		}
	} else if (StrEqual(sName, "player_spawn")) {
		if (g_bBodyHidden[iClient]) {
			RestoreCommanderBody(iClient, false); // fresh body; re-hidden below if still commander
		}
		CreateTimer(0.2, Timer_PostSpawn, GetClientUserId(iClient), TIMER_FLAG_NO_MAPCHANGE);
	}

	return Plugin_Continue;
}

public Action Timer_PostSpawn(Handle hTimer, int iUserId) {
	int iClient = GetClientOfUserId(iUserId);
	if (!iClient || !IsClientInGame(iClient) || !IsPlayerAlive(iClient)) {
		return Plugin_Stop;
	}
	int iTeam = GetClientTeam(iClient);
	if (!(CS_TEAM_T <= iTeam <= CS_TEAM_CT)) {
		return Plugin_Stop;
	}
	if (g_bWantsCommander[iClient]) {
		g_bWantsCommander[iClient] = false;
		AssignCommander(iClient);
	} else if (g_hCvarFirstHuman.BoolValue && !IsFakeClient(iClient) && !GetTeamCommander(iTeam) && !g_bDeclinedCmdr[iClient]) {
		if (AssignCommander(iClient)) {
			g_bMenuShown[iClient] = true;
		}
	}
	if (GetTeamCommander(iTeam) == iClient && g_hCvarBodyless.BoolValue) {
		CommanderStart(iClient);
	} else if (GetTeamCommander(iTeam) == iClient && g_ePost[iTeam].bValid) {
		// Commander spawns at the post, facing the terminal
		float vecStand[3], vecAng[3];
		GetStandSpot(g_ePost[iTeam].vecOrigin, g_ePost[iTeam].vecAngles[1], vecStand);
		if (HullClear(vecStand, PLAYER_MINS, PLAYER_MAXS)) {
			vecAng[1] = g_ePost[iTeam].vecAngles[1] + 180.0;
			vecStand[2] += 4.0;
			TeleportEntity(iClient, vecStand, vecAng, NULL_VECTOR);
		}
		if (!IsFakeClient(iClient)) {
			PrintHintText(iClient, "You are the Commander\nPress E on the terminal (or F2) for the command view");
		}
	} else if (!IsFakeClient(iClient) && !g_bMenuShown[iClient] && g_hCvarJoinMenu.BoolValue) {
		g_bMenuShown[iClient] = true;
		ShowRoleMenu(iClient);
	}
	return Plugin_Stop;
}

public bool TraceEntityFilter_Units(int iEntity, int iContentsMask, int iClient) {
	if (iEntity > MaxClients && HQ_IsHub(iEntity)) return true;
	return iEntity > 0 && IsSelectableUnitEntity(iClient, iEntity);
}

public Action SDKHookCB_SetTransmit_Beam(int iEntity, int iClient) {
	if (GetEntPropEnt(iEntity, Prop_Data, "m_hOwnerEntity") == iClient) {
		return Plugin_Continue;
	}

	return Plugin_Handled;
}

public Action SDKHookCB_SetTransmit_HealthBeam(int iEntity, int iClient) {
	if (GetEntPropEnt(iEntity, Prop_Data, "m_hOwnerEntity") == iClient) {
		ArrayList hSelectedUnits = g_eCommander[iClient].hSelectedUnits;
		int iIdx = hSelectedUnits.FindValue(EntIndexToEntRef(iEntity), UnitSelection::iHealthBeamEntRef);
		if (iIdx != -1) {
			UnitSelection eUnitSelection;
			hSelectedUnits.GetArray(iIdx, eUnitSelection);

			if (HighlightSelectedUnit(iClient, eUnitSelection))	{
				hSelectedUnits.SetArray(iIdx, eUnitSelection);
			}
		}

		return Plugin_Continue;
	}

	return Plugin_Handled;
}

// Commands

public Action cmdRTS(int iClient, int iArgs) {
	iClient = ResolveClient(iClient);

	// No args: role-aware toggle (commander view at the post, or the role menu). Anyone may use it.
	if (iArgs == 0 && iClient && IsClientInGame(iClient)) {
		ToggleCommanderView(iClient);
		return Plugin_Handled;
	}

	// sm_rts <6 bounds>: free debug camera (admin / css_rts_public)
	if (!HasRTSAccess(iClient)) {
		return Plugin_Handled;
	}

	if (iClient == 0 || !IsClientInGame(iClient)) {
		ReplyToCommand(iClient, "[RTS] Must be used by an in-game player");
		return Plugin_Handled;
	}

	if (g_eCommander[iClient].bEnabled) {
		ResetClient(iClient);
		return Plugin_Handled;
	}

	float vecMins[3];
	float vecMaxs[3];

	if (iArgs != 6) {
		char sCmdName[32];
		GetCmdArg(0, sCmdName, sizeof(sCmdName));

		ReplyToCommand(iClient, "Usage: %s [min_x min_y min_z max_x max_y max_z]", sCmdName);

		float vecPos[3];
		GetClientAbsOrigin(iClient, vecPos);
		SetupClient(iClient, _, _, vecPos);
	} else {
		vecMins[0] = GetCmdArgFloat(1);
		vecMins[1] = GetCmdArgFloat(2);
		vecMins[2] = GetCmdArgFloat(3);

		vecMaxs[0] = GetCmdArgFloat(4);
		vecMaxs[1] = GetCmdArgFloat(5);
		vecMaxs[2] = GetCmdArgFloat(6);

		SetupClient(iClient, vecMins, vecMaxs);
	}

	return Plugin_Handled;
}

public Action cmdRTSZoomIn(int iClient, int iArgs) {
	iClient = ResolveClient(iClient);
	if (!g_eCommander[iClient].bEnabled && !HasRTSAccess(iClient)) {
		return Plugin_Handled;
	}

	if (!g_eCommander[iClient].bEnabled || g_eCommander[iClient].bMoving || g_eCommander[iClient].bRotating) {
		return Plugin_Handled;
	}

	g_eCommander[iClient].bZoomingIn = true;
	g_eCommander[iClient].bZoomingOut = false;

	return Plugin_Handled;
}

public Action cmdRTSZoomOut(int iClient, int iArgs) {
	iClient = ResolveClient(iClient);
	if (!g_eCommander[iClient].bEnabled && !HasRTSAccess(iClient)) {
		return Plugin_Handled;
	}

	if (!g_eCommander[iClient].bEnabled || g_eCommander[iClient].bMoving || g_eCommander[iClient].bRotating) {
		return Plugin_Handled;
	}

	g_eCommander[iClient].bZoomingIn = false;
	g_eCommander[iClient].bZoomingOut = true;

	return Plugin_Handled;
}

public Action cmdRTSAspectRatio(int iClient, int iArgs) {
	iClient = ResolveClient(iClient);
	if (!g_eCommander[iClient].bEnabled && !HasRTSAccess(iClient)) {
		return Plugin_Handled;
	}

	if (!(1 <= iArgs <= 2)) {
		char sCmdName[32];
		GetCmdArg(0, sCmdName, sizeof(sCmdName));

		ReplyToCommand(iClient, "Usage: %s <ratio>", sCmdName);
		ReplyToCommand(iClient, "Usage: %s <width> <height>", sCmdName);

		return Plugin_Handled;
	}

	if (iArgs == 1) {
		g_eCommander[iClient].fAspectRatio = GetCmdArgFloat(1);
	} else {
		g_eCommander[iClient].fAspectRatio = GetCmdArgFloat(1) / GetCmdArgFloat(2);
	}

	return Plugin_Handled;
}

public Action cmdDebugBotMove(int iClient, int iArgs) {
	iClient = ResolveClient(iClient);
	if (!HasRTSAccess(iClient)) {
		return Plugin_Handled;
	}

	if (iArgs != 3) {
		ReplyToCommand(iClient, "Usage: sm_rts_debug_botmove <x> <y> <z>");
		return Plugin_Handled;
	}

	float vecPos[3];
	vecPos[0] = GetCmdArgFloat(1);
	vecPos[1] = GetCmdArgFloat(2);
	vecPos[2] = GetCmdArgFloat(3);

	int iCount, iEntity, iIndex;
	while ((iIndex = UnitEntityIterator(iIndex, iEntity)) != INVALID_ENT_REFERENCE) {
		MoveUnit(iClient, iEntity, vecPos);
		iCount++;
	}

	ReplyToCommand(iClient, "[RTS] Ordered %d bot unit(s) to %.0f %.0f %.0f (MoveTo %s)", iCount, vecPos[0], vecPos[1], vecPos[2], g_hSDKBotMoveTo != null ? "ready" : "unavailable");
	return Plugin_Handled;
}

public Action cmdDebugUnits(int iClient, int iArgs) {
	iClient = ResolveClient(iClient);
	if (!HasRTSAccess(iClient)) {
		return Plugin_Handled;
	}

	int iEntity, iIndex;
	while ((iIndex = UnitEntityIterator(iIndex, iEntity)) != INVALID_ENT_REFERENCE) {
		float vecPos[3];
		GetEntPropVector(iEntity, Prop_Data, "m_vecAbsOrigin", vecPos);
		if (iEntity <= MaxClients) {
			ReplyToCommand(iClient, "[RTS] unit %d %N team=%d pos=%.0f %.0f %.0f", iEntity, iEntity, GetClientTeam(iEntity), vecPos[0], vecPos[1], vecPos[2]);
		} else {
			int n = Npc_FromEntity(iEntity);
			ReplyToCommand(iClient, "[RTS] npc %d slot=%d kind=%d team=%d state=%d hp=%d seat=%d pos=%.0f %.0f %.0f", iEntity, n, g_eNpc[n].eKind, g_eNpc[n].iTeam, g_eNpc[n].eState, g_eNpc[n].iHealth, g_eNpc[n].iSeat, vecPos[0], vecPos[1], vecPos[2]);
		}
	}

	return Plugin_Handled;
}

float g_vecSelfTestTarget[3];

public Action cmdDebugSelfTest(int iClient, int iArgs) {
	iClient = ResolveClient(iClient);
	if (!HasRTSAccess(iClient)) {
		return Plugin_Handled;
	}

	if (iArgs < 3) {
		ReplyToCommand(iClient, "Usage: sm_rts_debug_selftest <x> <y> <z> [delay=20] [check=15]");
		return Plugin_Handled;
	}

	g_vecSelfTestTarget[0] = GetCmdArgFloat(1);
	g_vecSelfTestTarget[1] = GetCmdArgFloat(2);
	g_vecSelfTestTarget[2] = GetCmdArgFloat(3);
	float fDelay = iArgs >= 4 ? GetCmdArgFloat(4) : 20.0;
	float fCheck = iArgs >= 5 ? GetCmdArgFloat(5) : 15.0;

	CreateTimer(fDelay, Timer_SelfTestOrder, fCheck, TIMER_FLAG_NO_MAPCHANGE);
	PrintToServer("[RTS] selftest scheduled: order in %.0fs, check %.0fs later", fDelay, fCheck);
	return Plugin_Handled;
}

void SelfTestReport(const char[] sPhase) {
	int iEntity, iIndex, iCount;
	float fTotal;
	while ((iIndex = UnitEntityIterator(iIndex, iEntity)) != INVALID_ENT_REFERENCE) {
		if (iEntity > MaxClients) {
			continue;
		}
		float vecPos[3];
		GetClientAbsOrigin(iEntity, vecPos);
		float fDist = GetVectorDistance(vecPos, g_vecSelfTestTarget);
		fTotal += fDist;
		iCount++;
		PrintToServer("[RTS] selftest %s: %N dist=%.0f", sPhase, iEntity, fDist);
	}
	PrintToServer("[RTS] selftest %s: %d unit(s), avg dist to target %.0f", sPhase, iCount, iCount ? fTotal/iCount : 0.0);
}

public Action Timer_SelfTestOrder(Handle hTimer, float fCheck) {
	SelfTestReport("before");
	int iEntity, iIndex;
	while ((iIndex = UnitEntityIterator(iIndex, iEntity)) != INVALID_ENT_REFERENCE) {
		if (iEntity > MaxClients) continue;
		MoveUnit(0, iEntity, g_vecSelfTestTarget);
	}
	CreateTimer(fCheck, Timer_SelfTestCheck, _, TIMER_FLAG_NO_MAPCHANGE);
	return Plugin_Stop;
}

public Action Timer_SelfTestCheck(Handle hTimer) {
	SelfTestReport("after");
	return Plugin_Stop;
}

public Action cmdSquad(int iClient, int iArgs) {
	iClient = ResolveClient(iClient);
	if (!HasRTSAccess(iClient)) {
		return Plugin_Handled;
	}

	int iCount = iArgs >= 1 ? GetCmdArgInt(1) : 2;
	int iTeam = (iClient && IsClientInGame(iClient)) ? GetClientTeam(iClient) : CS_TEAM_CT;
	if (iTeam != CS_TEAM_T && iTeam != CS_TEAM_CT) {
		ReplyToCommand(iClient, "[RTS] Join T or CT first");
		return Plugin_Handled;
	}

	// bot_quota_mode normal + bot_quota would rebalance teams; add explicitly instead
	ServerCommand("bot_quota_mode normal");
	for (int i=0; i<iCount && i<16; i++) {
		ServerCommand(iTeam == CS_TEAM_T ? "bot_add_t" : "bot_add_ct");
	}

	ReplyToCommand(iClient, "[RTS] Adding %d bot unit(s) to %s (they spawn next round if the round is live; use mp_restartgame 1)", iCount, iTeam == CS_TEAM_T ? "T" : "CT");
	return Plugin_Handled;
}

// Helpers

void SetupClient(
	int iClient,
	float vecMins[3]=NULL_VECTOR,
	float vecMaxs[3]=NULL_VECTOR,
	float vecPosStartFocus[3]=NULL_VECTOR,
	float fMinZoom=DEFAULT_MIN_ZOOM,
	float fAspectRatio=DEFAULT_ASPECT_RATIO) {

	int iFocusEntity = CreateEntityByName("info_target");
	if (iFocusEntity == INVALID_ENT_REFERENCE) {
		return;
	}

	// Separate entity is needed to set camera velocities properly since predictions
	// with point_viewcontrol desynchronizes with beams position calcuations in viewport

	int iCameraEntity = CreateEntityByName("info_target");
	if (iCameraEntity == INVALID_ENT_REFERENCE) {
		Entity_Kill(iFocusEntity);
		return;
	}

	int iViewControl = CreateEntityByName("point_viewcontrol");
	if (iViewControl == INVALID_ENT_REFERENCE) {
		Entity_Kill(iFocusEntity);
		Entity_Kill(iCameraEntity);
		return;
	}

	Entity_SetParent(iCameraEntity, iFocusEntity);
	Entity_SetParent(iViewControl, iCameraEntity);

	Commander eCommander;

	eCommander.sCursor = CURSOR_DEFAULT;

	eCommander.vecMins = IsNullVector(vecMins) ? {NEGATIVE_INFINITY, NEGATIVE_INFINITY, NEGATIVE_INFINITY} : vecMins;
	eCommander.vecMaxs = IsNullVector(vecMaxs) ? {POSITIVE_INFINITY, POSITIVE_INFINITY, POSITIVE_INFINITY} : vecMaxs;
	eCommander.fMinZoom = fMinZoom;
	eCommander.fAspectRatio = fAspectRatio;

	eCommander.iFOV = GetEntProp(iClient, Prop_Send, "m_iFOV");
	eCommander.iDefaultFOV = GetEntProp(iClient, Prop_Send, "m_iDefaultFOV");
	if ((eCommander.bHasForceTauntCamProp = HasEntProp(iClient, Prop_Send, "m_nForceTauntCam"))) {
		eCommander.bBackupForceTauntCam = GetEntProp(iClient, Prop_Send, "m_nForceTauntCam") != 0;
	}

	eCommander.iFocusEntRef = EntIndexToEntRef(iFocusEntity);
	eCommander.iCameraEntRef = EntIndexToEntRef(iCameraEntity);
	eCommander.iViewControlEntRef = EntIndexToEntRef(iViewControl);

	DispatchSpawn(iFocusEntity);
	DispatchSpawn(iCameraEntity);
	DispatchSpawn(iViewControl);

	SetEntityMoveType(iFocusEntity, MOVETYPE_NOCLIP);
	SetEntityMoveType(iCameraEntity, MOVETYPE_NOCLIP);

	float vecPosFocus[3];
	if (IsNullVector(vecPosStartFocus)) {
		if (!IsNullVector(vecMins) && !IsNullVector(vecMaxs)) {
			vecPosFocus[0] = 0.5*(vecMins[0]+vecMaxs[0]);
			vecPosFocus[1] = 0.5*(vecMins[1]+vecMaxs[1]);
			vecPosFocus[2] = vecMins[2];
		}
	} else {
		vecPosFocus = vecPosStartFocus;
	}

	Entity_SetAbsOrigin(iFocusEntity, vecPosFocus);

	float fInitialDistance = g_hCvarCamStartDist.FloatValue;
	GetAngleVectors(DEFAULT_ANGLES, eCommander.vecVector, NULL_VECTOR, NULL_VECTOR);

	float vecCameraPos[3];
	vecCameraPos = eCommander.vecVector;
	ScaleVector(vecCameraPos, -fInitialDistance);

	TeleportEntity(iCameraEntity, vecCameraPos, DEFAULT_ANGLES, ZERO_VECTOR);

	SetClientViewEntity(iClient, iViewControl);
	SetEntityFlags(iClient, GetEntityFlags(iClient) | FL_FROZEN | FL_ATCONTROLS);
	AcceptEntityInput(iViewControl, "Enable", iClient, iViewControl, 0);

	/*
	 * HIDEHUD_MISCSTATUS will hide weapon statuses such as the banner rage bar and killstreak number
	 * but menu panels will also no longer show.  If the player must be alive on a team rather than
	 * as a spectator, these weapons may have to be temporarily removed to hide their HUD elements
	 * and keep the HUD interface clean while still allowing menu panels to show.
	 */

// 	Client_SetHideHud(iClient, HIDEHUD_HEALTH | HIDEHUD_WEAPONSELECTION | HIDEHUD_MISCSTATUS);
	Client_SetHideHud(iClient, HIDEHUD_HEALTH | HIDEHUD_WEAPONSELECTION);

	eCommander.hBackupObsTarget = Client_GetObserverTarget(iClient);
	eCommander.iBackupObsMode = Client_GetObserverMode(iClient);

	Client_SetObserverTarget(iClient, 0);
	Client_SetObserverMode(iClient, OBS_MODE_DEATHCAM, false);

	SetEntProp(iClient, Prop_Send, "m_iFOV", eCommander.iFOV);
	SetEntProp(iClient, Prop_Send, "m_iDefaultFOV", eCommander.iDefaultFOV);
	if (eCommander.bHasForceTauntCamProp) {
		// TF2-only netprop; never present on CSS
		SetEntProp(iClient, Prop_Send, "m_nForceTauntCam", 0);
	}

	eCommander.bEnabled = true;
	eCommander.fMouse = {0.5, 0.5};
	eCommander.fDistance = fInitialDistance;
	eCommander.hSelectedUnits = new ArrayList(sizeof(UnitSelection));

	eCommander.iSelectBeamsEntRef = {INVALID_ENT_REFERENCE, INVALID_ENT_REFERENCE, INVALID_ENT_REFERENCE, INVALID_ENT_REFERENCE};

	g_eCommander[iClient] = eCommander;
	g_fZoomTarget[iClient] = fInitialDistance;
	g_bCamInit[iClient] = false;
}

void ResetClient(int iClient) {
	Camera_HideClear(iClient);
	CmdPanel_Close(iClient);
	Ghost_Stop(iClient);
	Wheel_Close(iClient);
	Camera_SetCutaway(iClient, false);
	if (!g_eCommander[iClient].bEnabled) {
		return;
	}

	int hViewEntity = GetEntPropEnt(iClient, Prop_Data, "m_hViewEntity");
	if (IsValidEntity(hViewEntity) && hViewEntity != iClient) {
		Entity_Disable(hViewEntity);
	}

	SetClientViewEntity(iClient, iClient);

	int iFocusEntity = EntRefToEntIndex(g_eCommander[iClient].iFocusEntRef);
	if (iFocusEntity && IsValidEntity(iFocusEntity)) {
		Entity_Kill(iFocusEntity, true); // Removes hierarchy, including camera enitty
	}

	SetEntProp(iClient, Prop_Send, "m_iFOV", g_eCommander[iClient].iFOV);
	SetEntProp(iClient, Prop_Send, "m_iDefaultFOV", g_eCommander[iClient].iDefaultFOV);
	g_iCamFov[iClient] = 0;

	if (g_eCommander[iClient].bHasForceTauntCamProp) {
		SetEntProp(iClient, Prop_Send, "m_nForceTauntCam", g_eCommander[iClient].bBackupForceTauntCam);
	}

	Client_SetObserverMode(iClient, g_eCommander[iClient].iBackupObsMode, false);

	if (IsValidEntity(g_eCommander[iClient].hBackupObsTarget)) {
		Client_SetObserverTarget(iClient, g_eCommander[iClient].hBackupObsTarget);
	} else {
		Client_SetObserverTarget(iClient, iClient);
	}

	SetEntityFlags(iClient, GetEntityFlags(iClient) & ~(FL_FROZEN | FL_ATCONTROLS));
	SetEntityMoveType(iClient, MOVETYPE_WALK);
	Client_SetHideHud(iClient, 0);   // v0.5.3: the health/ammo HUD stayed hidden after leaving the view

	RemoveSelectBeams(iClient);
	ClearUnitSelection(iClient);

	delete g_eCommander[iClient].hSelectedUnits;

	g_eCommander[iClient].bEnabled = false;
	g_bPostView[iClient] = false;
}

int CreateBeam(int iClient, int iColor[4]=COLOR_WHITE, float fWidth=0.1) {
	int iBeamEnt = CreateEntityByName("env_beam");
	if (!IsValidEntity(iBeamEnt)) {
		return INVALID_ENT_REFERENCE;
	}

	SetEntityModel(iBeamEnt, LASER_MODEL);
	SetEntityRenderColor(iBeamEnt, iColor[0], iColor[1], iColor[2], iColor[3]);

	SetEntProp(iBeamEnt, Prop_Send, "m_nBeamType", 2);
	SetEntPropFloat(iBeamEnt, Prop_Data, "m_fWidth", fWidth);
	SetEntPropFloat(iBeamEnt, Prop_Data, "m_fEndWidth", fWidth);

	SetEntPropEnt(iBeamEnt, Prop_Data, "m_hOwnerEntity", iClient);

	DispatchSpawn(iBeamEnt);

	return iBeamEnt;
}

void AttachBeam(int iBeamEnt, int iOtherEnt) {
	if (!IsValidEntity(iBeamEnt) || !IsValidEntity(iOtherEnt)) {
		return;
	}

	SetEntPropEnt(iBeamEnt, Prop_Send, "m_hAttachEntity", EntIndexToEntRef(iBeamEnt));
	SetEntPropEnt(iBeamEnt, Prop_Send, "m_hAttachEntity", EntIndexToEntRef(iOtherEnt), 1);
	SetEntProp(iBeamEnt, Prop_Send, "m_nNumBeamEnts", 2);

	AcceptEntityInput(iBeamEnt,"TurnOn");
}

void RemoveSelectBeams(int iClient) {
	for (int i=0; i<4; i++) {
		int iEnt = EntRefToEntIndex(g_eCommander[iClient].iSelectBeamsEntRef[i]);
		if (iEnt && IsValidEntity(iEnt)) {
			Entity_Kill(iEnt);
		}

		g_eCommander[iClient].iSelectBeamsEntRef[i] = INVALID_ENT_REFERENCE;
	}
}

void ClearUnitSelection(int iClient) {
	ArrayList hSelectedUnits = g_eCommander[iClient].hSelectedUnits;

	for (int i=0; i<hSelectedUnits.Length; i++) {
		UnitSelection eUnitSelection;
		hSelectedUnits.GetArray(i, eUnitSelection);
		RemoveHealthBeams(eUnitSelection);
		hSelectedUnits.SetArray(i, eUnitSelection);
	}

	hSelectedUnits.Clear();
}

void RemoveHealthBeams(UnitSelection eUnitSelection) {
	for (int i=0; i<sizeof(UnitSelection::iHealthBeamEntRef); i++) {
		int iEnt = EntRefToEntIndex(eUnitSelection.iHealthBeamEntRef[i]);
		if (iEnt && IsValidEntity(iEnt)) {
			Entity_Kill(iEnt);
		}
		eUnitSelection.iHealthBeamEntRef[i] = INVALID_ENT_REFERENCE;
	}
}

void GetCursorVector(int iClient, float vecVector[3], float fMouse[2], float vecCursorVector[3]) {
	// v0.5.3: exact projection (Source FOV is horizontal for 4:3); matches the old approximation at 90
	int iFOV = g_iCamFov[iClient] ? g_iCamFov[iClient] : 90;
	float fAspectRatio = g_eCommander[iClient].fAspectRatio;
	float fHalfH = Tangent(DegToRad(0.5*iFOV)) * 0.75;
	float fCursorX = 2.0*(fMouse[0]-0.5)*fHalfH*fAspectRatio;
	float fCursorY = 2.0*(fMouse[1]-0.5)*fHalfH;

	float vecVectorAng[3];
	GetVectorAngles(vecVector, vecVectorAng);

	Vector_DegToRad(vecVectorAng);

	float vecCursor[3];
	vecCursor[0] = 1.0;
	vecCursor[1] = -fCursorX;
	vecCursor[2] = -fCursorY;

	float matRotation[3][3];
	Matrix_GetRotationMatrix(matRotation, vecVectorAng[2], vecVectorAng[0], vecVectorAng[1]);

	Matrix_VectorMultiply(matRotation, vecCursor, vecCursorVector);
}

void BoxOnPlane(const float vecCam[3], const float vecDir[3], float fZ, float vecOut[3]) {
	float fDz = vecDir[2];
	if (fDz > -0.08 && fDz < 0.08) fDz = fDz < 0.0 ? -0.08 : 0.08;
	float t = (fZ - vecCam[2]) / fDz;
	if (t < 16.0) t = 16.0;
	if (t > 8000.0) t = 8000.0;
	vecOut[0] = vecCam[0] + vecDir[0] * t;
	vecOut[1] = vecCam[1] + vecDir[1] * t;
	vecOut[2] = fZ;
}

void BoxCorner(int iClient, const float vecCam[3], const float vecDir[3], float vecOut[3]) {
	float vecAng[3], vecStart[3];
	GetVectorAngles(vecDir, vecAng);
	vecStart = vecCam;
	if (TR_GetPointContents(vecStart) & (CONTENTS_SOLID | CONTENTS_WINDOW)) {
		for (float d = 8.0; d <= 480.0; d += 8.0) {
			float vecP[3];
			for (int k = 0; k < 3; k++) vecP[k] = vecCam[k] + vecDir[k] * d;
			if (!(TR_GetPointContents(vecP) & (CONTENTS_SOLID | CONTENTS_WINDOW))) { vecStart = vecP; break; }
		}
	}
	TR_TraceRayFilter(vecStart, vecAng, MASK_SOLID, RayType_Infinite, TraceEntityFilter_Units, iClient);
	if (TR_DidHit() && !TR_StartSolid()) TR_GetEndPosition(vecOut);
	else for (int k = 0; k < 3; k++) vecOut[k] = vecStart[k] + vecDir[k] * 400.0;
	vecOut[2] += 6.0;
}

int GetUnitSelectTrace(int iClient, const float vecPos[3], const float vecAng[3], float vecEndPos[3]) {
	float vecDir[3], vecStart[3];
	GetAngleVectors(vecAng, vecDir, NULL_VECTOR, NULL_VECTOR);
	vecStart = vecPos;
	// The commander camera sits inside a roof or wall. A trace that starts there
	// never reaches the floor, so a worker click always lands in the solid.
	if (TR_GetPointContents(vecStart) & (CONTENTS_SOLID | CONTENTS_WINDOW)) {
		for (float d = 8.0; d <= 480.0; d += 8.0) {
			float vecP[3];
			for (int k = 0; k < 3; k++) vecP[k] = vecPos[k] + vecDir[k] * d;
			if (!(TR_GetPointContents(vecP) & (CONTENTS_SOLID | CONTENTS_WINDOW))) { vecStart = vecP; break; }
		}
	}
	TR_TraceRayFilter(vecStart, vecAng, MASK_PLAYERSOLID, RayType_Infinite, TraceEntityFilter_Units, iClient);
	if (TR_DidHit() && !TR_StartSolid()) {
		TR_GetEndPosition(vecEndPos);
		int iEntity = TR_GetEntityIndex();
		if (iEntity > MaxClients) return iEntity;
		float vecFloor[3];
		if (SnapToFloor(vecEndPos, vecFloor)) vecEndPos = vecFloor;
		return iEntity ? iEntity : INVALID_ENT_REFERENCE;
	}
	for (int k = 0; k < 3; k++) vecEndPos[k] = vecStart[k] + vecDir[k] * 900.0;
	float vecFloor[3];
	if (SnapToFloor(vecEndPos, vecFloor)) vecEndPos = vecFloor;
	return INVALID_ENT_REFERENCE;
}

void ProcessCameraControls(int iClient, int iButtons, int iLastButtons, const int iMouse[2]) {
	// Prevents changing camera target or mode
	Client_SetObserverTarget(iClient, 0);
	Client_SetObserverMode(iClient, OBS_MODE_DEATHCAM, false);

	float fMouse[2];
	float fSens = MOUSE_SENSITIVITY * g_hCvarCursorSpeed.FloatValue;
	fMouse[0] = g_eCommander[iClient].fMouse[0] + fSens * iMouse[0];
	fMouse[1] = g_eCommander[iClient].fMouse[1] + fSens * iMouse[1];

	if (!g_eCommander[iClient].bRotating) {
		fMouse[0] = Clamp(fMouse[0], CLAMP_MOUSE_MIN_X, CLAMP_MOUSE_MAX_X);
		fMouse[1] = Clamp(fMouse[1], CLAMP_MOUSE_MIN_Y, CLAMP_MOUSE_MAX_Y);
	}

	g_eCommander[iClient].fMouse = fMouse;

	float vecMins[3], vecMaxs[3];
	vecMins = g_eCommander[iClient].vecMins;
	vecMaxs = g_eCommander[iClient].vecMaxs;

	int iFocusEntity = EntRefToEntIndex(g_eCommander[iClient].iFocusEntRef);
	int iCameraEntity = EntRefToEntIndex(g_eCommander[iClient].iCameraEntRef);

	float vecFocusPos[3];
	Entity_GetAbsOrigin(iFocusEntity, vecFocusPos);

	float vecCameraPos[3];
	Entity_GetAbsOrigin(iCameraEntity, vecCameraPos);  // Relative to parent focus entity

	// v0.5.3 radial wheel: camera frozen, cursor + wheel only
	if (Wheel_IsOpen(iClient)) {
		float vecCamAbs[3], vecView[3];
		AddVectors(vecFocusPos, vecCameraPos, vecCamAbs);
		Entity_SetLocalVelocity(iFocusEntity, ZERO_VECTOR);
		Entity_SetLocalVelocity(iCameraEntity, ZERO_VECTOR);
		g_vecCamVel[iClient] = ZERO_VECTOR;
		if (!g_eCommander[iClient].sCursor[0]) g_eCommander[iClient].sCursor = CURSOR_DEFAULT;
		Hud_CursorColor(iClient, 255, 255, 255);
		vecView = g_eCommander[iClient].vecVector;
		Wheel_Update(iClient, vecCamAbs, vecView, fMouse, iButtons, iLastButtons);
		return;
	}
	if (Wheel_Enabled(iClient) && (iButtons & IN_DUCK) && !(iLastButtons & IN_DUCK)) {
		Wheel_Open(iClient, 0);
		return;
	}

	// v0.4 camera (css_rts/camera.sp)
	Camera_Process(iClient, iButtons, iLastButtons, iMouse, fMouse);
	bool bZoomingIn = false, bZoomingOut = false;
	float vecVector[3];
	vecVector = g_eCommander[iClient].vecVector;
	vecFocusPos = g_vecCamFocus[iClient];
	Entity_GetAbsOrigin(iCameraEntity, vecCameraPos);
	if (g_eCommander[iClient].bDragging) {
		Entity_SetLocalVelocity(iFocusEntity, ZERO_VECTOR);
		Entity_SetLocalVelocity(iCameraEntity, ZERO_VECTOR);
		g_vecCamVel[iClient] = ZERO_VECTOR;
		Entity_GetAbsOrigin(iFocusEntity, vecFocusPos);
		g_vecCamFocus[iClient] = vecFocusPos;
	}

	// Highlight all selected units
	HighlightSelectedUnits(iClient);

	if (!g_eCommander[iClient].sCursor[0]) g_eCommander[iClient].sCursor = CURSOR_DEFAULT;
	if (bZoomingIn || bZoomingOut || g_eCommander[iClient].bRotating) {
		Hud_CursorColor(iClient, 255, 255, 255);
		return;
	}

	bool bMouseButton1Down = g_eCommander[iClient].bMouseButton1Down;
	bool bMouseButton2Down = g_eCommander[iClient].bMouseButton2Down;

	// Cursor point and rectangle selection through a stationary viewport

	float vecCursorVector[3];
	GetCursorVector(iClient, vecVector, fMouse, vecCursorVector);

	float vecCursorAng[3];
	GetVectorAngles(vecCursorVector, vecCursorAng);

	ArrayList hSelectedUnits = g_eCommander[iClient].hSelectedUnits;

	float vecCameraAbsPos[3];
	AddVectors(vecFocusPos, vecCameraPos, vecCameraAbsPos);

	float vecCursorPos[3];
	int iSelectedEntity = GetUnitSelectTrace(iClient, vecCameraAbsPos, vecCursorAng, vecCursorPos);
	DrawCursorMark(iClient, vecCursorPos);

	int iCursorColor[4];
	if (g_eCommander[iClient].bMoveDragging || g_eCommander[iClient].bMoving && !(iButtons & (IN_FORWARD | IN_BACK | IN_MOVELEFT | IN_MOVERIGHT))) {
		iCursorColor = HUD_TEXT_COLOR_SCROLL;
	} else {
		iCursorColor = hSelectedUnits.Length ? HUD_TEXT_COLOR_SELECT : HUD_TEXT_COLOR_IDLE;
	}

	Hud_CursorColor(iClient, iCursorColor[0], iCursorColor[1], iCursorColor[2]);

	if (Ability_Targeting(iClient)) {
		Ability_UpdateTarget(iClient, vecCursorPos, iButtons, iLastButtons);
		return;
	}

	if (Ghost_Active(iClient)) {
		Ghost_Update(iClient, vecCursorPos, iButtons, iLastButtons);
		return;
	}
	if (Build_Active(iClient)) {
		g_iBuildMouseX[iClient] = iMouse[0];
		Build_Update(iClient, vecCursorPos, iButtons, iLastButtons);
		return;
	}
	if ((iButtons & IN_ATTACK) && !(iLastButtons & IN_ATTACK) && HQ_IsHub(iSelectedEntity) && !Seat_NearCursor(GetClientTeam(iClient), vecCursorPos, 36.0)) {
		Armory_ShowHQMenu(iClient);
		return;
	}

	if (iButtons & IN_ATTACK) {
		if (g_eCommander[iClient].bDragging) {
			if (g_eCommander[iClient].bMoving) {
				// TODO: Expand selection while scrolling
				//       In the meantime, block scrolling by moving cursor away from scroll edge

				fMouse[0] = g_eCommander[iClient].fMouse[0] = Clamp(fMouse[0], CLAMP_MOUSE_MIN_X+0.001, CLAMP_MOUSE_MAX_X-0.001);
				fMouse[1] = g_eCommander[iClient].fMouse[1] = Clamp(fMouse[1], CLAMP_MOUSE_MIN_Y+0.001, CLAMP_MOUSE_MAX_Y-0.001);
			}

			// Consistency is required for counter-clockwise order of points used in
			// SelectionContains to generate plane normals that must all point inwards

			float fMouseTopLeft[2];
			fMouseTopLeft[0] = fMouse[0] < g_eCommander[iClient].fMouseDragStart[0] ? fMouse[0] : g_eCommander[iClient].fMouseDragStart[0];
			fMouseTopLeft[1] = fMouse[1] < g_eCommander[iClient].fMouseDragStart[1] ? fMouse[1] : g_eCommander[iClient].fMouseDragStart[1];

			float fMouseBottomRight[2];
			fMouseBottomRight[0] = fMouse[0] > g_eCommander[iClient].fMouseDragStart[0] ? fMouse[0] : g_eCommander[iClient].fMouseDragStart[0];
			fMouseBottomRight[1] = fMouse[1] > g_eCommander[iClient].fMouseDragStart[1] ? fMouse[1] : g_eCommander[iClient].fMouseDragStart[1];

			float vecBoxC0[3], vecBoxC1[3], vecBoxC2[3], vecBoxC3[3], vecDir[3];
			float vecGround[3];
			vecGround = vecCursorPos;
			Cursor_DropToWalk(vecGround);
			float fPlaneZ = vecGround[2] + 16.0;
			GetCursorVector(iClient, vecVector, fMouseTopLeft, vecDir);
			BoxOnPlane(vecCameraAbsPos, vecDir, fPlaneZ, vecBoxC0);
			GetCursorVector(iClient, vecVector, fMouseBottomRight, vecDir);
			BoxOnPlane(vecCameraAbsPos, vecDir, fPlaneZ, vecBoxC2);
			float fTempMouse[2];
			fTempMouse[0] = fMouseBottomRight[0];
			fTempMouse[1] = fMouseTopLeft[1];
			GetCursorVector(iClient, vecVector, fTempMouse, vecDir);
			BoxOnPlane(vecCameraAbsPos, vecDir, fPlaneZ, vecBoxC1);
			fTempMouse[0] = fMouseTopLeft[0];
			fTempMouse[1] = fMouseBottomRight[1];
			GetCursorVector(iClient, vecVector, fTempMouse, vecDir);
			BoxOnPlane(vecCameraAbsPos, vecDir, fPlaneZ, vecBoxC3);

			g_eCommander[iClient].SetSelectionVertex(0, vecBoxC0);
			g_eCommander[iClient].SetSelectionVertex(1, vecBoxC1);
			g_eCommander[iClient].SetSelectionVertex(2, vecBoxC2);
			g_eCommander[iClient].SetSelectionVertex(3, vecBoxC3);

			int iEnt0 = EntRefToEntIndex(g_eCommander[iClient].iSelectBeamsEntRef[0]);
			int iEnt1, iEnt2, iEnt3;
			if (!IsValidEntity(iEnt0)) {
				RemoveSelectBeams(iClient);

				int iBoxCol[4] = {80, 255, 140, 255};
				iEnt0 = CreateBeam(iClient, iBoxCol, 2.4);
				iEnt1 = CreateBeam(iClient, iBoxCol, 2.4);
				iEnt2 = CreateBeam(iClient, iBoxCol, 2.4);
				iEnt3 = CreateBeam(iClient, iBoxCol, 2.4);

				SDKHook(iEnt0, SDKHook_SetTransmit, SDKHookCB_SetTransmit_Beam);
				SDKHook(iEnt1, SDKHook_SetTransmit, SDKHookCB_SetTransmit_Beam);
				SDKHook(iEnt2, SDKHook_SetTransmit, SDKHookCB_SetTransmit_Beam);
				SDKHook(iEnt3, SDKHook_SetTransmit, SDKHookCB_SetTransmit_Beam);

				g_eCommander[iClient].iSelectBeamsEntRef[0] = EntIndexToEntRef(iEnt0);
				g_eCommander[iClient].iSelectBeamsEntRef[1] = EntIndexToEntRef(iEnt1);
				g_eCommander[iClient].iSelectBeamsEntRef[2] = EntIndexToEntRef(iEnt2);
				g_eCommander[iClient].iSelectBeamsEntRef[3] = EntIndexToEntRef(iEnt3);

				AttachBeam(iEnt0, iEnt1);
				AttachBeam(iEnt1, iEnt2);
				AttachBeam(iEnt2, iEnt3);
				AttachBeam(iEnt3, iEnt0);
			} else {
				iEnt1 = EntRefToEntIndex(g_eCommander[iClient].iSelectBeamsEntRef[1]);
				iEnt2 = EntRefToEntIndex(g_eCommander[iClient].iSelectBeamsEntRef[2]);
				iEnt3 = EntRefToEntIndex(g_eCommander[iClient].iSelectBeamsEntRef[3]);
			}

			Entity_SetAbsOrigin(iEnt0, vecBoxC0);
			Entity_SetAbsOrigin(iEnt1, vecBoxC1);
			Entity_SetAbsOrigin(iEnt2, vecBoxC2);
			Entity_SetAbsOrigin(iEnt3, vecBoxC3);
			float fBoxW = g_fCamDist[iClient] * 0.008;
			if (fBoxW < 2.4) fBoxW = 2.4;
			if (fBoxW > 12.0) fBoxW = 12.0;
			SetEntPropFloat(iEnt0, Prop_Data, "m_fWidth", fBoxW);
			SetEntPropFloat(iEnt0, Prop_Data, "m_fEndWidth", fBoxW);
			SetEntPropFloat(iEnt1, Prop_Data, "m_fWidth", fBoxW);
			SetEntPropFloat(iEnt1, Prop_Data, "m_fEndWidth", fBoxW);
			SetEntPropFloat(iEnt2, Prop_Data, "m_fWidth", fBoxW);
			SetEntPropFloat(iEnt2, Prop_Data, "m_fEndWidth", fBoxW);
			SetEntPropFloat(iEnt3, Prop_Data, "m_fWidth", fBoxW);
			SetEntPropFloat(iEnt3, Prop_Data, "m_fEndWidth", fBoxW);
			int iXray = g_iMarkerXray > 0 ? g_iMarkerXray : g_iMarkerBeam;
			if (iXray > 0) {
				int iCol[4] = {80, 255, 140, 255};
				TE_SetupBeamPoints(vecBoxC0, vecBoxC1, iXray, 0, 0, 0, 0.15, fBoxW, fBoxW, 0, 0.0, iCol, 0);
				TE_SendToClient(iClient, 0.0);
				TE_SetupBeamPoints(vecBoxC1, vecBoxC2, iXray, 0, 0, 0, 0.15, fBoxW, fBoxW, 0, 0.0, iCol, 0);
				TE_SendToClient(iClient, 0.0);
				TE_SetupBeamPoints(vecBoxC2, vecBoxC3, iXray, 0, 0, 0, 0.15, fBoxW, fBoxW, 0, 0.0, iCol, 0);
				TE_SendToClient(iClient, 0.0);
				TE_SetupBeamPoints(vecBoxC3, vecBoxC0, iXray, 0, 0, 0, 0.15, fBoxW, fBoxW, 0, 0.0, iCol, 0);
				TE_SendToClient(iClient, 0.0);
			}
		} else if (!(g_eCommander[iClient].bMoving || g_eCommander[iClient].bRotating)) {
			g_eCommander[iClient].bDragging = true;

			g_eCommander[iClient].fMouseDragStart[0] = fMouse[0];
			g_eCommander[iClient].fMouseDragStart[1] = fMouse[1];
		}

		g_eCommander[iClient].bMouseButton1Down = true;

		return;
	}

	if (iButtons & IN_ATTACK2) {
		if (!bMouseButton2Down) {
			g_eCommander[iClient].fMouseDragStart[0] = fMouse[0];
			g_eCommander[iClient].fMouseDragStart[1] = fMouse[1];

			g_eCommander[iClient].fMouseDragStartTime = GetGameTime();
		}

		float fMouseDragStartTime = g_eCommander[iClient].fMouseDragStartTime;

		if (g_eCommander[iClient].bMoveDragging) {
			float fDragDiff0 = g_eCommander[iClient].fMouseDragStart[0] - fMouse[0];
			float fDragDiff1 = g_eCommander[iClient].fMouseDragStart[1] - fMouse[1];

			float fDragAng = ArcTangent2(fDragDiff0, fDragDiff1);
			if (fDragAng < 0) {
				fDragAng += 2*FLOAT_PI;
			}

			int iScrollCursorIdx = RoundToNearest(fDragAng/(FLOAT_PI/4)) % 8;
			g_eCommander[iClient].sCursor = g_sScrollCursors[iScrollCursorIdx];

			float fSpeed = 0.12 * (140.0 + g_fCamDist[iClient]);
			float vecForward[3], vecRight[3];
			vecForward[0] = Cosine(DegToRad(g_fCamYaw[iClient])); vecForward[1] = Sine(DegToRad(g_fCamYaw[iClient]));
			vecRight[0] = vecForward[1]; vecRight[1] = -vecForward[0];
			g_eCommander[iClient].vecMoveDragVel[0] = MOUSE2_DRAG_SPEED_MULT * -fSpeed * (fDragDiff0/0.5*vecRight[0] - fDragDiff1/0.5*vecForward[0]);
			g_eCommander[iClient].vecMoveDragVel[1] = MOUSE2_DRAG_SPEED_MULT * -fSpeed * (fDragDiff0/0.5*vecRight[1] - fDragDiff1/0.5*vecForward[1]);
		} else if (fMouseDragStartTime) {
			if (GetGameTime()-fMouseDragStartTime >= MOUSE2_DRAG_START_DELAY) {
				float fDragDiff0 = g_eCommander[iClient].fMouseDragStart[0] - fMouse[0];
				float fDragDiff1 = g_eCommander[iClient].fMouseDragStart[1] - fMouse[1];

				float fDragDistance = SquareRoot(fDragDiff0*fDragDiff0+fDragDiff1*fDragDiff1);
				if (hSelectedUnits.Length && fDragDistance < MOUSE2_DRAG_MIN_DIST) {
					float vecMove[3];
					vecMove = vecCursorPos;
					Cursor_DropToWalk(vecMove);
					MoveSelectedUnits(iClient, vecMove);
					g_eCommander[iClient].fMouseDragStartTime = 0.0;
				} else {
					g_eCommander[iClient].bMoveDragging = true;
				}
			}
		}

		g_eCommander[iClient].bMouseButton2Down = true;

		return;
	}

	if (bMouseButton1Down) {
		if (g_eCommander[iClient].bDragging) {
			float vecBoxC1[3], vecBoxC3[3];
			g_eCommander[iClient].GetSelectionVertex(0, vecBoxC1);
			g_eCommander[iClient].GetSelectionVertex(2, vecBoxC3);

			bool bAdd = (iButtons & IN_SPEED) != 0;
			float fClickDx = fMouse[0] - g_eCommander[iClient].fMouseDragStart[0];
			float fClickDy = fMouse[1] - g_eCommander[iClient].fMouseDragStart[1];
			bool bClick = SquareRoot(fClickDx * fClickDx + fClickDy * fClickDy) < 0.03;
			if (!bAdd) ClearUnitSelection(iClient);
			if (!bClick && GetVectorDistance(vecBoxC1, vecBoxC3) > 48.0) {
				int iIndex;
				int iUnitEntity;
				bool bArmy;
				while ((iIndex = UnitEntityIterator(iIndex, iUnitEntity)) != INVALID_ENT_REFERENCE) {
					float vecPosUnit[3];
					Entity_GetAbsOrigin(iUnitEntity, vecPosUnit);
					if (!IsSelectableUnitEntity(iClient, iUnitEntity) || !g_eCommander[iClient].SelectionContains(vecPosUnit)) continue;
					if (!Unit_IsWorker(iUnitEntity)) bArmy = true;
				}
				iIndex = 0;
				while ((iIndex = UnitEntityIterator(iIndex, iUnitEntity)) != INVALID_ENT_REFERENCE) {
					float vecPosUnit[3];
					Entity_GetAbsOrigin(iUnitEntity, vecPosUnit);
					if (!IsSelectableUnitEntity(iClient, iUnitEntity) || !g_eCommander[iClient].SelectionContains(vecPosUnit)) continue;
					if (bArmy && Unit_IsWorker(iUnitEntity)) continue;
					if (hSelectedUnits.FindValue(EntIndexToEntRef(iUnitEntity)) == -1) SelectUnit(iClient, iUnitEntity);
				}

				if (!hSelectedUnits.Length && iSelectedEntity != INVALID_ENT_REFERENCE && IsSelectableUnitEntity(iClient, iSelectedEntity)) {
					SelectUnit(iClient, iSelectedEntity);
				}
			} else {
				int iPick = (iSelectedEntity != INVALID_ENT_REFERENCE && IsSelectableUnitEntity(iClient, iSelectedEntity)) ? iSelectedEntity : Click_NearestUnit(iClient, vecCursorPos);
				if (iPick > 0) SelectUnit(iClient, iPick);
			}

			RemoveSelectBeams(iClient);
			g_eCommander[iClient].bDragging = false;
		}
	} else if (bMouseButton2Down) {
		if (g_eCommander[iClient].bMoveDragging) {
			g_eCommander[iClient].bMoveDragging = false;
			g_eCommander[iClient].fMouseDragStartTime = 0.0;
			g_eCommander[iClient].vecMoveDragVel = ZERO_VECTOR;
		} else if (GetGameTime()-g_eCommander[iClient].fMouseDragStartTime < MOUSE2_DRAG_START_DELAY) {
			float vecMove[3];
			vecMove = vecCursorPos;
			Cursor_DropToWalk(vecMove);
			MoveSelectedUnits(iClient, vecMove);
		}
	}

	g_eCommander[iClient].bMouseButton1Down = false;
	g_eCommander[iClient].bMouseButton2Down = false;

	if (iSelectedEntity != INVALID_ENT_REFERENCE) {
		g_eCommander[iClient].sCursor = CURSOR_SELECTABLE;
	} else if (hSelectedUnits.Length) {
		g_eCommander[iClient].sCursor = CURSOR_MOVE;
	} else {
		g_eCommander[iClient].sCursor = CURSOR_DEFAULT;
	}
}

void HighlightSelectedUnits(int iClient) {
	ArrayList hSelectedUnits = g_eCommander[iClient].hSelectedUnits;
	for (int i=0; i<hSelectedUnits.Length; i++) {
		UnitSelection eUnitSelection;
		hSelectedUnits.GetArray(i, eUnitSelection);

		if (HighlightSelectedUnit(iClient, eUnitSelection)) {
			hSelectedUnits.SetArray(i, eUnitSelection);
		}
	}
}

void MoveSelectedUnits(int iClient, float vecMovePos[3]) {
	ArrayList hSelectedUnits = g_eCommander[iClient].hSelectedUnits;

	for (int i=0; i<hSelectedUnits.Length; i++) {
		int iUnitEntity = EntRefToEntIndex(hSelectedUnits.Get(i));
		if (IsValidEntity(iUnitEntity)) {
			MoveUnit(iClient, iUnitEntity, vecMovePos);
			if (i < 8) {
				float vecFrom[3];
				GetEntPropVector(iUnitEntity, Prop_Data, "m_vecAbsOrigin", vecFrom);
				DrawOrderPath(iClient, vecFrom, vecMovePos);
			}
		}
	}
}

void DrawOrderPath(int iClient, const float vecStart[3], const float vecGoal[3]) {
	ArrayList hPath = new ArrayList(3);
	if (!Nav_BuildPath(vecStart, vecGoal, hPath) || hPath.Length < 1) { delete hPath; return; }
	float vecA[3];
	vecA = vecStart;
	vecA[2] += 20.0;
	int iModel = PrecacheModel("sprites/laserbeam.vmt");
	int iCol[4] = {90, 255, 150, 220};
	int iShown;
	for (int i = 0; i < hPath.Length && iShown < 12; i++) {
		float vecB[3];
		hPath.GetArray(i, vecB, 3);
		vecB[2] += 20.0;
		if (GetVectorDistance(vecA, vecB) < 32.0) continue;
		TE_SetupBeamPoints(vecA, vecB, iModel, 0, 0, 0, 2.4, 3.5, 3.5, 1, 0.0, iCol, 0);
		TE_SendToClient(iClient, 0.0);
		vecA = vecB;
		iShown++;
	}
	delete hPath;
}

bool DrawUnitHealthBar(int iClient, UnitSelection eUnitSelection) {
	int iEntity = EntRefToEntIndex(eUnitSelection.iUnitEntRef);
	if (!IsValidEntity(iEntity)) {
		return false;
	}

	int iHealth = GetEntProp(iEntity, Prop_Data, "m_iHealth");
	if (iHealth <= 0.0 || Client_IsValid(iEntity) && !IsPlayerAlive(iEntity)) {
		if (eUnitSelection.iHealthBeamEntRef[0] != INVALID_ENT_REFERENCE) {
			RemoveHealthBeams(eUnitSelection);
			return true;
		}

		return false;
	}

	int iMaxHealth = GetEntProp(iEntity, Prop_Data, "m_iMaxHealth");

	int iFocusEntity = EntRefToEntIndex(g_eCommander[iClient].iFocusEntRef);
	int iCameraEntity = EntRefToEntIndex(g_eCommander[iClient].iCameraEntRef);

	float vecFocusPos[3];
	Entity_GetAbsOrigin(iFocusEntity, vecFocusPos);

	float vecCameraPos[3];
	Entity_GetAbsOrigin(iCameraEntity, vecCameraPos); // Relative to parent focus entity

	AddVectors(vecFocusPos, vecCameraPos, vecCameraPos); // Now absolute in world coordiates

	float vecCameraAng[3];
	Entity_GetAbsAngles(iCameraEntity, vecCameraAng);

	float vecFwd[3], vecRight[3], vecUp[3];
	GetAngleVectors(vecCameraAng, vecFwd, vecRight, vecUp);

	float vecEntityPos[3];
	Entity_GetAbsOrigin(iEntity, vecEntityPos);

	// Calculate the center and the highest point at the top
	// of the bounding box as projected onto the camera plane

	float vecBoundingBoxTop[4][3];
	float fProjectedHeights[4];
	GetEntityBoundingBoxTop(iEntity, vecBoundingBoxTop);

	float vecCenterPos[3];
	int iHighestIdx;
	float fMaxHeight = NEGATIVE_INFINITY;

	for (int i=0; i<sizeof(vecBoundingBoxTop); i++) {
		float vecVectorToPoint[3];
		SubtractVectors(vecBoundingBoxTop[i], vecCameraPos, vecVectorToPoint);
		NormalizeVector(vecVectorToPoint, vecVectorToPoint);

		// Sum total for average calcuation
		AddVectors(vecCenterPos, vecVectorToPoint, vecCenterPos);

		fProjectedHeights[i] = GetVectorDotProduct(vecVectorToPoint, vecUp);
		if (fProjectedHeights[i] > fMaxHeight) {
			fMaxHeight = fProjectedHeights[i];
			iHighestIdx = i;
		}
	}

	// Divide by 4 for average
	ScaleVector(vecCenterPos, 0.25);

	float vecShiftUp[3];
	vecShiftUp = vecUp;
	ScaleVector(vecShiftUp, fProjectedHeights[iHighestIdx] - GetVectorDotProduct(vecCenterPos, vecUp));
	AddVectors(vecCenterPos, vecShiftUp, vecCenterPos);
	NormalizeVector(vecCenterPos, vecCenterPos);

	float vecHealthBarPos[3];
	vecHealthBarPos = vecCenterPos;
	ScaleVector(vecHealthBarPos, 50.0);
	AddVectors(vecCameraPos, vecHealthBarPos, vecHealthBarPos);

	// Move center to the left to offset for bar extending due to overheal
	if (iHealth > iMaxHealth) {
		float vecOverhealOffset[3];
		vecOverhealOffset = vecRight;
		ScaleVector(vecOverhealOffset, HEALTH_BAR_HP_SCALE * (iMaxHealth-iHealth));
		AddVectors(vecHealthBarPos, vecOverhealOffset, vecHealthBarPos);
	}

	float vecHorizontalLeftPos[3];
	float vecHorizontalRightPos[3];

	float fBarMin = HEALTH_BAR_HP_SCALE * iMaxHealth;
	float fBarMax = HEALTH_BAR_HP_SCALE * iMaxHealth;

	float fBarSplit = HEALTH_BAR_HP_SCALE * 2*iHealth;

	float vecRightOffset[3], vecLeftOffset[3];
	vecRightOffset = vecRight;
	ScaleVector(vecRightOffset, 50.0);
	vecLeftOffset = vecRightOffset;
	ScaleVector(vecLeftOffset, -1.0);

	vecHorizontalLeftPos = vecLeftOffset;
	ScaleVector(vecHorizontalLeftPos, fBarMin);
	AddVectors(vecHealthBarPos, vecHorizontalLeftPos, vecHorizontalLeftPos);

	vecHorizontalRightPos = vecRightOffset;
	ScaleVector(vecHorizontalRightPos, fBarSplit);
	AddVectors(vecHorizontalLeftPos, vecHorizontalRightPos, vecHorizontalRightPos);

	bool bModified;

	int iEnt0 = EntRefToEntIndex(eUnitSelection.iHealthBeamEntRef[0]);
	int iEnt1, iEnt2;
	if (!IsValidEntity(iEnt0)) {
		RemoveHealthBeams(eUnitSelection);

		int iHpCol[4] = {60, 230, 90, 255};
		iEnt0 = CreateBeam(iClient, iHpCol, 1.5);
		iEnt1 = CreateEntityByName("info_target");
		AttachBeam(iEnt0, iEnt1);
		SDKHook(iEnt0, SDKHook_SetTransmit, SDKHookCB_SetTransmit_HealthBeam);

		eUnitSelection.iHealthBeamEntRef[0] = EntIndexToEntRef(iEnt0);
		eUnitSelection.iHealthBeamEntRef[1] = EntIndexToEntRef(iEnt1);

		if (iHealth != iMaxHealth) {
			iEnt2 = CreateBeam(iClient, COLOR_GRAY);
			AttachBeam(iEnt2, iEnt1);
			SDKHook(iEnt2, SDKHook_SetTransmit, SDKHookCB_SetTransmit_HealthBeam);

			eUnitSelection.iHealthBeamEntRef[2] = EntIndexToEntRef(iEnt2);
		}

		bModified = true;
	} else {
		iEnt1 = EntRefToEntIndex(eUnitSelection.iHealthBeamEntRef[1]);
		iEnt2 = EntRefToEntIndex(eUnitSelection.iHealthBeamEntRef[2]);

		if (iHealth == iMaxHealth) {
			if (iEnt2 != INVALID_ENT_REFERENCE) {
				Entity_Kill(iEnt2);

				eUnitSelection.iHealthBeamEntRef[2] = INVALID_ENT_REFERENCE;

				bModified = true;
			}
		} else if (iEnt2 == INVALID_ENT_REFERENCE) {
			iEnt2 = CreateBeam(iClient, COLOR_GRAY);
			AttachBeam(iEnt2, iEnt1);
			SDKHook(iEnt2, SDKHook_SetTransmit, SDKHookCB_SetTransmit_Beam);

			eUnitSelection.iHealthBeamEntRef[2] = EntIndexToEntRef(iEnt2);

			bModified = true;
		}
	}

	float vecFeet[3];
	GetEntPropVector(iEntity, Prop_Data, "m_vecAbsOrigin", vecFeet);
	float fYaw = g_fCamYaw[iClient];
	float fRx = Sine(DegToRad(fYaw)), fRy = -Cosine(DegToRad(fYaw));
	float fFrac = iMaxHealth > 0 ? float(iHealth) / float(iMaxHealth) : 0.0;
	if (fFrac < 0.0) fFrac = 0.0;
	if (fFrac > 1.0) fFrac = 1.0;
	float fHalf = 14.0;
	vecHorizontalLeftPos[0] = vecFeet[0] - fRx * fHalf;
	vecHorizontalLeftPos[1] = vecFeet[1] - fRy * fHalf;
	vecHorizontalLeftPos[2] = vecFeet[2] + 84.0;
	vecHorizontalRightPos[0] = vecHorizontalLeftPos[0] + fRx * (fHalf * 2.0 * fFrac);
	vecHorizontalRightPos[1] = vecHorizontalLeftPos[1] + fRy * (fHalf * 2.0 * fFrac);
	vecHorizontalRightPos[2] = vecHorizontalLeftPos[2];
	Entity_SetAbsOrigin(iEnt0, vecHorizontalLeftPos);
	Entity_SetAbsOrigin(iEnt1, vecHorizontalRightPos);

	if (iHealth != iMaxHealth) {
		vecHorizontalLeftPos = vecHorizontalRightPos;

		vecHorizontalRightPos = vecRightOffset;
		ScaleVector(vecHorizontalRightPos, fBarMax);
		AddVectors(vecHealthBarPos, vecHorizontalRightPos, vecHorizontalRightPos);

		Entity_SetAbsOrigin(iEnt2, vecHorizontalRightPos);
	}

	// Color gradient based on health percentage

	float fHealthPercent = Clamp(float(iHealth)/iMaxHealth, 0.0, 1.0);

	int iHealthBarColor[4];
	int iHealthBarColorMix[4];
	iHealthBarColor = HEALTH_BAR_COLOR_LOW;
	iHealthBarColorMix = HEALTH_BAR_COLOR_FULL;

	float fColorMixRatio = fHealthPercent < HEALTH_BAR_LOW_PCT ? 0.0: fHealthPercent;

	float fHealthBarColor[4];
	fHealthBarColor[0] = fColorMixRatio*iHealthBarColorMix[0] + (1.0-fColorMixRatio)*iHealthBarColor[0];
	fHealthBarColor[1] = fColorMixRatio*iHealthBarColorMix[1] + (1.0-fColorMixRatio)*iHealthBarColor[1];
	fHealthBarColor[2] = fColorMixRatio*iHealthBarColorMix[2] + (1.0-fColorMixRatio)*iHealthBarColor[2];
	fHealthBarColor[3] = fColorMixRatio*iHealthBarColorMix[3] + (1.0-fColorMixRatio)*iHealthBarColor[3];

	// Scale to highest value while keeping RGB ratios or else beam color will appear dull and invisible

	float fMaxColorChannel = fHealthBarColor[0] > fHealthBarColor[1] ? fHealthBarColor[0] : fHealthBarColor[1];
	fMaxColorChannel = fMaxColorChannel > fHealthBarColor[2] ? fMaxColorChannel : fHealthBarColor[2];

	float fScaleToMax = 255/fMaxColorChannel;
	fHealthBarColor[0] *= fScaleToMax;
	fHealthBarColor[1] *= fScaleToMax;
	fHealthBarColor[2] *= fScaleToMax;

	iHealthBarColor[0] = RoundToFloor(fHealthBarColor[0]);
	iHealthBarColor[1] = RoundToFloor(fHealthBarColor[1]);
	iHealthBarColor[2] = RoundToFloor(fHealthBarColor[2]);
	iHealthBarColor[3] = RoundToFloor(fHealthBarColor[3]);

	SetEntityRenderColor(iEnt0, iHealthBarColor[0], iHealthBarColor[1], iHealthBarColor[2], iHealthBarColor[3]);

	return bModified;
}

void GetEntityBoundingBoxTop(int iEntity, float vecPoints[4][3]) {
	float vecMins[3], vecMaxs[3];
	Entity_GetMinSize(iEntity, vecMins);
	Entity_GetMaxSize(iEntity, vecMaxs);

	float vecPos[3];
	Entity_GetAbsOrigin(iEntity, vecPos);

	AddVectors(vecPos, vecMins, vecMins);
	AddVectors(vecPos, vecMaxs, vecMaxs);

	vecPoints[0][0] = vecMins[0];
	vecPoints[0][1] = vecMins[1];
	vecPoints[0][2] = vecMaxs[2];

	vecPoints[1][0] = vecMins[0];
	vecPoints[1][1] = vecMaxs[1];
	vecPoints[1][2] = vecMaxs[2];

	vecPoints[2][0] = vecMaxs[0];
	vecPoints[2][1] = vecMins[1];
	vecPoints[2][2] = vecMaxs[2];

	vecPoints[3][0] = vecMaxs[0];
	vecPoints[3][1] = vecMaxs[1];
	vecPoints[3][2] = vecMaxs[2];
}

float Clamp(float fValue, float fMin, float fMax) {
	if (fValue < fMin) {
		return fMin;
	}

	if (fValue > fMax) {
		return fMax;
	}

	return fValue;
}

// Matrix vector ops

void Vector_DegToRad(float vecVector[3]) {
	vecVector[0] = DegToRad(vecVector[0]);
	vecVector[1] = DegToRad(vecVector[1]);
	vecVector[2] = DegToRad(vecVector[2]);
}

void Matrix_VectorMultiply(float matMatrix[3][3], float vecVector[3], float vecResult[3]) {
	vecResult[0] = matMatrix[0][0]*vecVector[0] + matMatrix[0][1]*vecVector[1] + matMatrix[0][2]*vecVector[2];
	vecResult[1] = matMatrix[1][0]*vecVector[0] + matMatrix[1][1]*vecVector[1] + matMatrix[1][2]*vecVector[2];
	vecResult[2] = matMatrix[2][0]*vecVector[0] + matMatrix[2][1]*vecVector[1] + matMatrix[2][2]*vecVector[2];
}

void Matrix_Set(float matMatrix[3][3], float f00, float f01, float f02, float f10, float f11, float f12, float f20, float f21, float f22) {
	matMatrix[0][0] = f00;	matMatrix[0][1] = f01;	matMatrix[0][2] = f02;
	matMatrix[1][0] = f10;	matMatrix[1][1] = f11;	matMatrix[1][2] = f12;
	matMatrix[2][0] = f20;	matMatrix[2][1] = f21;	matMatrix[2][2] = f22;
}

void Matrix_GetRotationMatrix(float matMatrix[3][3], float fA, float fB, float fG) {
	float fSinA = Sine(fA);
	float fCosA = Cosine(fA);

	float fSinB = Sine(fB);
	float fCosB = Cosine(fB);

	float fSinG = Sine(fG);
	float fCosG = Cosine(fG);

	Matrix_Set(matMatrix,
		fCosB*fCosG, 	fSinA*fSinB*fCosG - fCosA*fSinG, 	fCosA*fSinB*fCosG + fSinA*fSinG,
		fCosB*fSinG,	fSinA*fSinB*fSinG + fCosA*fCosG, 	fCosA*fSinB*fSinG - fSinA*fCosG,
		     -fSinB,		                fSinA*fCosB,	                    fCosA*fCosB
	);
}

// Stubs start here
// Fill in with code specific to bot or unit implementation

/**
 * Checks whether the selected entity is a unit controlled by the game mode
 * and can be selected by the commander
 *
 * @param iClient			Commander selecting the unit
 * @param iEntity			Entity being checked
 * @return					True if the entity is a unit
 */
int Click_NearestUnit(int iClient, const float vecPos[3]) {
	float fReach = 80.0 + g_fCamDist[iClient] * 0.035;
	if (fReach > 200.0) fReach = 200.0;
	float fBest = fReach;
	int iBest = -1;
	int iIndex, iEnt;
	while ((iIndex = UnitEntityIterator(iIndex, iEnt)) != INVALID_ENT_REFERENCE) {
		if (!IsSelectableUnitEntity(iClient, iEnt)) continue;
		float p[3];
		Entity_GetAbsOrigin(iEnt, p);
		if (FloatAbs(p[2] - vecPos[2]) > 140.0) continue;
		float d = GetVectorDistance(vecPos, p);
		if (d < fBest) { fBest = d; iBest = iEnt; }
	}
	return iBest;
}

bool Unit_IsWorker(int iEntity) {
	if (iEntity <= MaxClients) return false;
	int n = Npc_FromEntity(iEntity);
	return n != -1 && g_eNpc[n].eKind == Npc_Worker;
}

bool IsSelectableUnitEntity(int iClient, int iEntity) {
	// CSS bots (CCSBot) on the commander's team, or the team's plugin NPCs (workers)
	if (iEntity > MaxClients) {
		int n = Npc_FromEntity(iEntity);
		if (n != -1) return g_eNpc[n].iTeam == GetClientTeam(iClient) && g_eNpc[n].eState != NS_Dead;
		int slot = Build_SlotOf(iEntity);
		return slot != -1 && g_iBuildTeam[slot] == GetClientTeam(iClient);
	}
	return IsUnitBot(iEntity) && GetClientTeam(iEntity) == GetClientTeam(iClient);
}

void DrawCursorMark(int iClient, const float vecPos[3]) {
	int iSprite = g_iMarkerXray > 0 ? g_iMarkerXray : g_iMarkerBeam;
	if (iSprite <= 0) return;
	float p[3];
	p = vecPos;
	p[2] += 6.0;
	int iCol[4] = {80, 255, 120, 255};
	float a[3], b[3];
	a = p; b = p; a[0] -= 16.0; b[0] += 16.0;
	TE_SetupBeamPoints(a, b, iSprite, 0, 0, 0, 0.12, 3.0, 3.0, 0, 0.0, iCol, 0);
	TE_SendToClient(iClient, 0.0);
	a = p; b = p; a[1] -= 16.0; b[1] += 16.0;
	TE_SetupBeamPoints(a, b, iSprite, 0, 0, 0, 0.12, 3.0, 3.0, 0, 0.0, iCol, 0);
	TE_SendToClient(iClient, 0.0);
}

bool IsUnitBot(int iEntity) {
	return 1 <= iEntity <= MaxClients && IsClientInGame(iEntity) && IsFakeClient(iEntity)
		&& !IsClientSourceTV(iEntity) && !IsClientReplay(iEntity) && IsPlayerAlive(iEntity);
}

/**
 * Called when a unit entity is successfully selected
 * 
 * @param iClient			Commander who selected the unit
 * @param iSelectedEntity	Entity of selected unit
 */
void SelectUnit(int iClient, int iSelectedEntity) {
	UnitSelection eUnitSelection;
	eUnitSelection.Init(iSelectedEntity);

	g_eCommander[iClient].hSelectedUnits.PushArray(eUnitSelection);
}

/**
 * Called to highlight a unit that was selected
 * 
 * @param iClient			Commander who selected the unit
 * @param eUnitSelection	Selected unit
 * @return 					True if eUnitSelection has been altered
 */
bool HighlightSelectedUnit(int iClient, UnitSelection eUnitSelection) {
	return DrawUnitHealthBar(iClient, eUnitSelection);
}

/**
 * Called to move a selected unit
 * 
 * @param iClient			Commander who is moving the unit
 * @param iEntity			Entity of unit being moved
 * @param vecMovePos		Coordinates to move the unit to
 */
void MoveUnit(int iClient, int iEntity, float vecMovePos[3]) {
	if (iEntity > MaxClients) {
		int n = Npc_FromEntity(iEntity);
		if (n != -1 && g_eNpc[n].eKind == Npc_Worker) {
			float fLeft;
			if (Worker_Panicked(n, fLeft)) {
				if (iClient) PrintHintText(iClient, "Terrified  %.0fs\nPress G to send them back", fLeft);
			} else Worker_Order(n, vecMovePos);
		}
		else if (n != -1 && g_eNpc[n].eKind == Npc_Soldier) Soldier_Order(n, vecMovePos);
		return;
	}
	Train_NoteOrder(iEntity, vecMovePos);
	if (g_hSDKBotMoveTo == null || !IsUnitBot(iEntity)) {
		return;
	}

	SDKCall(g_hSDKBotMoveTo, iEntity, vecMovePos, Route_Fastest);
	if (iClient) {
		Match_OnUnitOrdered(iEntity);
	}
}

/**
 * Iterate through controllable units
 * 
 * @param iIndex			Index of a controllable unit starting from 0
 * @param iEntity			Entity of unit at this index, or INVALID_ENT_REFERENCE if it does not exist
 * @return					Returns the next unit index or -1 if there are no more
 */
int UnitEntityIterator(int iIndex=0, int &iEntity=INVALID_ENT_REFERENCE) {
	// Units are bot clients 1..MaxClients; iIndex is the next client index to test
	for (int i=iIndex+1; i<=MaxClients; i++) {
		if (IsUnitBot(i)) {
			iEntity = i;
			return i;
		}
	}
	// NPC slots continue the index space after the clients
	int iStart = iIndex + 1 > MaxClients + 1 ? iIndex + 1 : MaxClients + 1;
	for (int i=iStart; i<=MaxClients+MAX_NPCS; i++) {
		int n = i - MaxClients - 1;
		if (g_eNpc[n].bUsed && g_eNpc[n].eState != NS_Dead) {
			int iEnt = Npc_GetEntity(n);
			if (iEnt != -1) {
				iEntity = iEnt;
				return i;
			}
		}
	}
	int iBuild0 = MaxClients + MAX_NPCS + 1;
	int iFrom = iIndex + 1 > iBuild0 ? iIndex + 1 : iBuild0;
	for (int i = iFrom; i < iBuild0 + MAX_BUILDS; i++) {
		int e = g_iBuildEnt[i - iBuild0];
		if (e > 0 && IsValidEntity(e)) {
			iEntity = e;
			return i;
		}
	}

	iEntity = INVALID_ENT_REFERENCE;
	return INVALID_ENT_REFERENCE;
}
