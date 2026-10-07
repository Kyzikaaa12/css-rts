// css_rts/camera.sp -- RTS camera. Pan, orbit, zoom, and (v0.5.4.1) a roof/wall hide:
// the camera sits inside the first solid on the view ray so the engine culls that roof or
// wall, while the field of view stays put. Open sky keeps the full zoom.

ConVar g_hCvarCamPitch;
ConVar g_hCvarCamPanSpeed;
ConVar g_hCvarCamMinPitch;
ConVar g_hCvarCamStartDist;
ConVar g_hCvarCamFovMax;
ConVar g_hCvarCamFov;
ConVar g_hCvarCamXray;
ConVar g_hCvarCamCollide;
ConVar g_hCvarCamHide;
ConVar g_hCvarCamHidePitch;
ConVar g_hCvarCursorSpeed;

#define CAM_HIDE_MAX 12
int g_iHideEnt[MAXPLAYERS+1][CAM_HIDE_MAX];
int g_iHideCount[MAXPLAYERS+1];
int g_iHideOwnedRef[2049];
int g_iHideProbe[CAM_HIDE_MAX];
int g_iHideProbeN;
bool g_bCutaway[MAXPLAYERS+1];          // X: camera ignores ceilings/roofs and looks down through them
int g_iBackdropRef[MAXPLAYERS+1] = {INVALID_ENT_REFERENCE, ...};
bool g_bForcedAlways[2049];
bool g_bCutawayAny;
int g_iCamFov[MAXPLAYERS+1];            // current view FOV (0 = default 90); widened under low ceilings

float g_fCamYaw[MAXPLAYERS+1];
float g_fCamYawTarget[MAXPLAYERS+1];
float g_fCamPitch[MAXPLAYERS+1];        // user pitch (degrees down)
float g_fCamPitchEff[MAXPLAYERS+1];     // pitch after ceiling adaptation
float g_fCamDist[MAXPLAYERS+1];         // eased zoom distance
float g_fCamDistEff[MAXPLAYERS+1];      // distance after collision
float g_vecCamFocus[MAXPLAYERS+1][3];
float g_vecCamVel[MAXPLAYERS+1][3];
float g_vecCamGoto[MAXPLAYERS+1][3];
bool g_bCamGoto[MAXPLAYERS+1];
bool g_bCamInit[MAXPLAYERS+1];
int g_iCamRotateSteps[MAXPLAYERS+1];    // queued Q presses (lastinv listener)
int g_iCamCycle[MAXPLAYERS+1];
int g_iCamLastTick[MAXPLAYERS+1];

void Camera_Init() {
	g_hCvarCamPitch = CreateConVar("css_rts_cam_pitch", "64", "Default camera pitch in degrees (90 = straight down)", _, true, 20.0, true, 89.0);
	g_hCvarCamMinPitch = CreateConVar("css_rts_cam_min_pitch", "32", "Lowest pitch the camera flattens to under low ceilings", _, true, 10.0, true, 80.0);
	g_hCvarCamStartDist = CreateConVar("css_rts_cam_start_dist", "1800", "Camera distance when entering the view (higher = more overview)", _, true, 300.0);
	g_hCvarCamFovMax = CreateConVar("css_rts_cam_fov_max", "112", "Widest FOV the old ceiling camera opens to when a low ceiling stops it zooming out (90 = never widen). Unused while css_rts_cam_hide is on", _, true, 90.0, true, 130.0);
	g_hCvarCamFov = CreateConVar("css_rts_cam_fov", "104", "Steady commander field of view while roof hiding is on", _, true, 90.0, true, 120.0);
	g_hCvarCamCollide = CreateConVar("css_rts_cam_collide", "0", "1 = old ceiling camera (flattens and shortens under roofs). 0 = do not flatten. Roof and wall hiding is css_rts_cam_hide", _, true, 0.0, true, 1.0);
	g_hCvarCamHide = CreateConVar("css_rts_cam_hide", "1", "1 = commander view hides the roof and the wall the camera is looking through, and keeps a steady field of view", _, true, 0.0, true, 1.0);
	g_hCvarCamHidePitch = CreateConVar("css_rts_cam_hide_pitch", "60", "While a roof or wall blocks the zoom, look down at least this many degrees so the room stays in frame", _, true, 40.0, true, 80.0);
	g_hCvarCursorSpeed = CreateConVar("css_rts_cursor_speed", "1.6", "Commander mouse cursor speed multiplier (1.0 = v0.5.3 speed)", _, true, 0.1, true, 10.0);
	g_hCvarCamXray = CreateConVar("css_rts_cam_cutaway", "1", "1 = allow the cutaway view (X in the command view: the camera ignores ceilings and roofs and looks down through them)", _, true, 0.0, true, 1.0);
	RegConsoleCmd("sm_rts_debug_camhide", cmdDebugCamHide, "[#userid|name]: print roof-hide pitch, distance, solidity and hidden brushes");
	RegConsoleCmd("sm_rts_debug_cutaway", cmdDebugCutaway, "<target> <0|1>: set the cutaway view (prints forced-transmit count)");
	RegConsoleCmd("sm_rts_cutaway", cmdCutaway, "Commander: toggle the cutaway view (look through ceilings/roofs; rts.cfg binds X)");
	CreateTimer(0.5, Timer_CutawayTransmit, _, TIMER_REPEAT);
	RegConsoleCmd("sm_rts_rotate", cmdRotate, "Commander: rotate the camera around its focus by <degrees> (rts.cfg binds [ and ])");
	g_hCvarCamPanSpeed = CreateConVar("css_rts_cam_pan_speed", "0.85", "Camera pan speed multiplier", _, true, 0.1, true, 5.0);
	RegConsoleCmd("sm_rts_debug_camsim", cmdDebugCamSim, "<target> <ticks> <buttons> [mx] [my]: simulate camera input");
	RegConsoleCmd("sm_rts_debug_camgrid", cmdDebugCamGrid, "[pitch] [dist]: solve the camera at every nav area and report fit");
	AddCommandListener(CmdListener_CamLastInv, "lastinv");
	AddCommandListener(CmdListener_CamWheel, "invprev");
	AddCommandListener(CmdListener_CamWheel, "invnext");
}

public Action CmdListener_CamLastInv(int iClient, const char[] sCmd, int iArgc) {
	if (iClient > 0 && g_eCommander[iClient].bEnabled) {
		g_iCamRotateSteps[iClient]++;
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

// Default binds: mouse wheel = invprev/invnext -> zoom while commanding
public Action CmdListener_CamWheel(int iClient, const char[] sCmd, int iArgc) {
	if (iClient > 0 && g_eCommander[iClient].bEnabled) {
		Camera_Zoom(iClient, StrEqual(sCmd, "invprev") ? -1 : 1);
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

void Camera_Zoom(int iClient, int iDir) {
	float f = g_fZoomTarget[iClient];
	f *= iDir < 0 ? 0.87 : 1.15;
	g_fZoomTarget[iClient] = Clamp(f, g_eCommander[iClient].fMinZoom, g_hCvarZoomMax.FloatValue);
}

void Camera_Reset(int iClient, const float vecFocus[3], float fYaw) {
	g_vecCamFocus[iClient] = vecFocus;
	g_vecCamVel[iClient] = ZERO_VECTOR;
	g_fCamYaw[iClient] = g_fCamYawTarget[iClient] = fYaw;
	g_fCamPitch[iClient] = g_fCamPitchEff[iClient] = g_hCvarCamPitch.FloatValue;
	g_fCamDist[iClient] = g_fCamDistEff[iClient] = g_fZoomTarget[iClient];
	g_bCamGoto[iClient] = false;
	g_iCamRotateSteps[iClient] = 0;
	g_bCamInit[iClient] = true;
}

void Camera_GoTo(int iClient, const float vecPos[3]) {
	g_vecCamGoto[iClient] = vecPos;
	g_bCamGoto[iClient] = true;
}

float AngleDiff(float a, float b) {
	float d = a - b;
	while (d > 180.0) d -= 360.0;
	while (d < -180.0) d += 360.0;
	return d;
}

public bool TraceFilter_CamWorld(int iEntity, int iMask) {
	return iEntity == 0;
}

void Camera_Forward(float fPitch, float fYaw, float vecFwd[3]) {
	float vecAng[3];
	vecAng[0] = fPitch; vecAng[1] = fYaw;
	GetAngleVectors(vecAng, vecFwd, NULL_VECTOR, NULL_VECTOR);
}

// Distance to the first world brush along the camera ray. Sky counts as open air.
float Camera_Occluder(const float vecFocus[3], float fPitch, float fYaw, float fDist, bool &bSky) {
	float vecFwd[3], vecStart[3], vecEnd[3];
	Camera_Forward(fPitch, fYaw, vecFwd);
	vecStart = vecFocus;
	vecStart[2] += 40.0;
	for (int k = 0; k < 3; k++) vecEnd[k] = vecStart[k] - vecFwd[k] * fDist;
	static float vecMins[3] = {-10.0, -10.0, -10.0};
	static float vecMaxs[3] = {10.0, 10.0, 10.0};
	TR_TraceHullFilter(vecStart, vecEnd, vecMins, vecMaxs, MASK_PLAYERSOLID_BRUSHONLY, TraceFilter_CamWorld);
	bSky = TR_DidHit() && (TR_GetSurfaceFlags() & SURF_SKY) != 0;
	if (TR_StartSolid()) return 0.0;
	if (!TR_DidHit()) return fDist;
	float fHit = TR_GetFraction() * fDist;
	// Stop short of the sky. Flying through it puts the view outside the map.
	if (bSky) {
		fHit -= 32.0;
		if (fHit < 48.0) fHit = 48.0;
	}
	return fHit;
}

bool Camera_PointBlocks(const float vecP[3]) {
	return (TR_GetPointContents(vecP) & (CONTENTS_SOLID | CONTENTS_WINDOW)) != 0;
}

// Free camera distance from the focus along -forward (world brushes only, small hull margin)
float Camera_FreeDist(const float vecFocus[3], float fPitch, float fYaw, float fDist) {
	float vecFwd[3], vecStart[3], vecEnd[3];
	Camera_Forward(fPitch, fYaw, vecFwd);
	vecStart = vecFocus; vecStart[2] += 40.0;
	for (int k=0; k<3; k++) vecEnd[k] = vecStart[k] - vecFwd[k] * fDist;
	static float vecMins[3] = {-10.0, -10.0, -10.0}, vecMaxs[3] = {10.0, 10.0, 10.0};
	TR_TraceHullFilter(vecStart, vecEnd, vecMins, vecMaxs, MASK_PLAYERSOLID_BRUSHONLY, TraceFilter_CamWorld);
	if (TR_StartSolid()) return 0.0;  // focus inside geometry: stay at the focus
	return TR_GetFraction() * fDist;
}

// Pick an effective pitch/distance: keep the user pitch if the camera fits, otherwise flatten
// towards css_rts_cam_min_pitch (lower, more angled view under ceilings), then shorten.
void Camera_Solve(const float vecFocus[3], float fPitch, float fYaw, float fDist, float &fPitchOut, float &fDistOut) {
	float fMin = g_hCvarCamMinPitch.FloatValue;
	float fBestPitch = fPitch, fBestDist = -1.0;
	for (float p = fPitch; ; p -= 8.0) {
		if (p < fMin) p = fMin;
		float d = Camera_FreeDist(vecFocus, p, fYaw, fDist);
		if (d >= fDist * 0.92) { fBestPitch = p; fBestDist = d; break; }
		if (d > fBestDist + 24.0) { fBestPitch = p; fBestDist = d; }
		if (p <= fMin) break;
	}
	fPitchOut = fBestPitch;
	fDistOut = fBestDist - 12.0;
	if (fDistOut < 0.0) fDistOut = 0.0;
}

float Camera_GroundZ(const float vecPos[3], float fFallback) {
	float vecStart[3], vecEnd[3];
	vecStart = vecPos; vecStart[2] += 56.0;
	vecEnd = vecPos; vecEnd[2] -= 700.0;
	TR_TraceRayFilter(vecStart, vecEnd, MASK_PLAYERSOLID_BRUSHONLY, RayType_EndPoint, TraceFilter_CamWorld);
	if (TR_StartSolid() || !TR_DidHit()) return fFallback;
	float vecHit[3];
	TR_GetEndPosition(vecHit);
	return vecHit[2];
}

// Called every usercmd for an active commander. Writes vecVector/fDistance/bMoving/sCursor and
// drives the focus + camera entities with velocities (smooth client interpolation).
void Camera_Process(int iClient, int iButtons, int iLastButtons, const int iMouse[2], float fMouse[2]) {
	int iFocusEntity = EntRefToEntIndex(g_eCommander[iClient].iFocusEntRef);
	int iCameraEntity = EntRefToEntIndex(g_eCommander[iClient].iCameraEntRef);
	if (iFocusEntity == INVALID_ENT_REFERENCE || iCameraEntity == INVALID_ENT_REFERENCE) return;
	float dt = GetTickInterval();
	if (!g_bCamInit[iClient]) {
		float vecF[3];
		Entity_GetAbsOrigin(iFocusEntity, vecF);
		Camera_Reset(iClient, vecF, 0.0);
	}

	// ---- hotkeys: R = jump to next unit, Space = jump to the command post
	if ((iButtons & IN_RELOAD) && !(iLastButtons & IN_RELOAD)) Markers_JumpNext(iClient);
	if ((iButtons & IN_JUMP) && !(iLastButtons & IN_JUMP)) Markers_JumpHome(iClient);

	// ---- rotation: E (+use) / Q (lastinv) = 45 deg steps, arrows (+left/+right), middle-drag
	if ((iButtons & IN_USE) && !(iLastButtons & IN_USE)) g_fCamYawTarget[iClient] -= 45.0;
	while (g_iCamRotateSteps[iClient] > 0) { g_fCamYawTarget[iClient] += 45.0; g_iCamRotateSteps[iClient]--; }
	if (iButtons & IN_LEFT) g_fCamYawTarget[iClient] += 150.0 * dt;
	if (iButtons & IN_RIGHT) g_fCamYawTarget[iClient] -= 150.0 * dt;
	if (iButtons & IN_ATTACK3) {
		if (!g_eCommander[iClient].bRotating) g_eCommander[iClient].fRotatingStartMouse = g_eCommander[iClient].fMouse;
		g_eCommander[iClient].bRotating = true;
		g_eCommander[iClient].bMoveDragging = false;
		g_fCamYawTarget[iClient] -= iMouse[0] * 0.15;
		g_fCamPitch[iClient] = Clamp(g_fCamPitch[iClient] + iMouse[1] * 0.08, 30.0, 85.0);
		fMouse = g_eCommander[iClient].fRotatingStartMouse;
		g_eCommander[iClient].fMouse = fMouse;
	} else if (g_eCommander[iClient].bRotating) {
		g_eCommander[iClient].bRotating = false;
	}
	g_fCamYaw[iClient] += AngleDiff(g_fCamYawTarget[iClient], g_fCamYaw[iClient]) * Clamp(dt * 9.0, 0.0, 1.0);

	// ---- zoom (wheel commands adjust g_fZoomTarget)
	if (g_eCommander[iClient].bZoomingIn || g_eCommander[iClient].bZoomingOut) {
		Camera_Zoom(iClient, g_eCommander[iClient].bZoomingIn ? -1 : 1);
		g_eCommander[iClient].bZoomingIn = g_eCommander[iClient].bZoomingOut = false;
	}
	g_fZoomTarget[iClient] = Clamp(g_fZoomTarget[iClient], g_eCommander[iClient].fMinZoom, g_hCvarZoomMax.FloatValue);
	g_fCamDist[iClient] += (g_fZoomTarget[iClient] - g_fCamDist[iClient]) * Clamp(dt * g_hCvarZoomSpeed.FloatValue * 1.5, 0.0, 1.0);

	// ---- pan: WASD + screen edges, accelerated; Shift = fast
	float vecFwd2[3], vecRight2[3];
	vecFwd2[0] = Cosine(DegToRad(g_fCamYaw[iClient])); vecFwd2[1] = Sine(DegToRad(g_fCamYaw[iClient]));
	vecRight2[0] = vecFwd2[1]; vecRight2[1] = -vecFwd2[0];
	float fWishX, fWishY;  // x = right, y = forward
	bool bEdge = false;
	if (iButtons & IN_MOVELEFT) fWishX -= 1.0;
	if (iButtons & IN_MOVERIGHT) fWishX += 1.0;
	if (iButtons & IN_FORWARD) fWishY += 1.0;
	if (iButtons & IN_BACK) fWishY -= 1.0;
	if (!g_eCommander[iClient].bRotating) {
		if (fMouse[0] <= CLAMP_MOUSE_MIN_X) { fWishX = -1.0; bEdge = true; }
		else if (fMouse[0] >= CLAMP_MOUSE_MAX_X) { fWishX = 1.0; bEdge = true; }
		if (fMouse[1] <= CLAMP_MOUSE_MIN_Y) { fWishY = 1.0; bEdge = true; }
		else if (fMouse[1] >= CLAMP_MOUSE_MAX_Y) { fWishY = -1.0; bEdge = true; }
	}
	float fMax = (350.0 + g_fCamDist[iClient] * 1.1) * g_hCvarCamPanSpeed.FloatValue * ((iButtons & IN_SPEED) ? 2.2 : 1.0);
	float vecWish[3];
	for (int k=0; k<2; k++) vecWish[k] = (vecRight2[k] * fWishX + vecFwd2[k] * fWishY) * fMax;
	bool bInput = fWishX != 0.0 || fWishY != 0.0;
	if (bInput) g_bCamGoto[iClient] = false;
	if (g_eCommander[iClient].bMoveDragging) {
		vecWish = g_eCommander[iClient].vecMoveDragVel;
		vecWish[2] = 0.0;
		g_bCamGoto[iClient] = false;
		g_vecCamVel[iClient] = vecWish;
	} else if (g_bCamGoto[iClient]) {
		for (int k=0; k<2; k++) g_vecCamVel[iClient][k] = (g_vecCamGoto[iClient][k] - g_vecCamFocus[iClient][k]) * 5.0;
		if (GetVectorDistance(g_vecCamGoto[iClient], g_vecCamFocus[iClient]) < 8.0) g_bCamGoto[iClient] = false;
	} else {
		float fRate = Clamp(dt * (bInput ? 7.0 : 9.0), 0.0, 1.0);
		for (int k=0; k<2; k++) g_vecCamVel[iClient][k] += (vecWish[k] - g_vecCamVel[iClient][k]) * fRate;
	}
	g_eCommander[iClient].bMoving = bInput || g_eCommander[iClient].bMoveDragging;
	if (bEdge && !(iButtons & (IN_FORWARD | IN_BACK | IN_MOVELEFT | IN_MOVERIGHT))) {
		float fDragAng = ArcTangent2(-fWishX, fWishY);
		if (fDragAng < 0) fDragAng += 2*FLOAT_PI;
		g_eCommander[iClient].sCursor = g_sScrollCursors[RoundToNearest(fDragAng/(FLOAT_PI/4)) % 8];
	}

	Camera_Apply(iClient, iFocusEntity, iCameraEntity, dt);
}

void Camera_Apply(int iClient, int iFocusEntity, int iCameraEntity, float dt) {
	float vecMins[3], vecMaxs[3];
	vecMins = g_eCommander[iClient].vecMins;
	vecMaxs = g_eCommander[iClient].vecMaxs;
	float vecFocus[3];
	vecFocus = g_vecCamFocus[iClient];
	for (int k=0; k<2; k++) {
		vecFocus[k] += g_vecCamVel[iClient][k] * dt;
		if (vecFocus[k] < vecMins[k]) { vecFocus[k] = vecMins[k]; g_vecCamVel[iClient][k] = 0.0; }
		if (vecFocus[k] > vecMaxs[k]) { vecFocus[k] = vecMaxs[k]; g_vecCamVel[iClient][k] = 0.0; }
	}
	if (g_bCamGoto[iClient]) vecFocus[2] += (g_vecCamGoto[iClient][2] - vecFocus[2]) * Clamp(dt * 8.0, 0.0, 1.0);
	float fGround = Camera_GroundZ(vecFocus, vecFocus[2]);
	bool bFree = !g_hCvarCamCollide.BoolValue;
	vecFocus[2] += (fGround - vecFocus[2]) * Clamp(dt * (bFree ? 2.0 : 6.0), 0.0, 1.0);   // free cam: slow height follow = no bumping over stairs/walls
	g_vecCamFocus[iClient] = vecFocus;

	float fPitchUser = g_fCamPitch[iClient];
	float fYaw = g_fCamYaw[iClient];
	float fWant = g_fCamDist[iClient];
	bool bHide = g_hCvarCamHide.BoolValue;
	if (!bHide) {
		float fPitchEff = fPitchUser, fDistEff = fWant;
		if (!bFree) Camera_Solve(vecFocus, fPitchUser, fYaw, fWant, fPitchEff, fDistEff);
		float fOutRate = Clamp(dt * 4.0, 0.0, 1.0);
		if (fDistEff < g_fCamDistEff[iClient]) g_fCamDistEff[iClient] = fDistEff;
		else g_fCamDistEff[iClient] += (fDistEff - g_fCamDistEff[iClient]) * fOutRate;
		if (g_bCutaway[iClient] || bFree) { fPitchEff = fPitchUser; g_fCamDistEff[iClient] = fWant; }
		g_fCamPitchEff[iClient] += (fPitchEff - g_fCamPitchEff[iClient]) * Clamp(dt * 6.0, 0.0, 1.0);
		Camera_UpdateFov(iClient, fWant, (g_bCutaway[iClient] || bFree) ? fWant : g_fCamDistEff[iClient]);
	} else {
		// Scroll wheel owns the distance. WASD only pans; it must not pull the camera closer.
		g_fCamPitchEff[iClient] += (fPitchUser - g_fCamPitchEff[iClient]) * Clamp(dt * 8.0, 0.0, 1.0);
		float fDelta = fWant - g_fCamDistEff[iClient];
		if (FloatAbs(fDelta) < 1.0) g_fCamDistEff[iClient] = fWant;
		else g_fCamDistEff[iClient] += fDelta * Clamp(dt * 10.0, 0.0, 1.0);
		Camera_UpdateFov(iClient, fWant, g_fCamDistEff[iClient]);
	}

	float vecFwd[3];
	Camera_Forward(g_fCamPitchEff[iClient], g_fCamYaw[iClient], vecFwd);
	float vecLocal[3];
	for (int k=0; k<3; k++) vecLocal[k] = -vecFwd[k] * g_fCamDistEff[iClient];
	vecLocal[2] += 40.0;
	if (!bHide && !g_bCutaway[iClient] && !bFree && vecFocus[2] + vecLocal[2] > vecMaxs[2]) vecLocal[2] = vecMaxs[2] - vecFocus[2];

	// velocities that land the entities on the targets next tick (keeps client interpolation smooth)
	float vecCur[3], vecVel[3];
	Entity_GetAbsOrigin(iFocusEntity, vecCur);
	for (int k=0; k<3; k++) vecVel[k] = (vecFocus[k] - vecCur[k]) / dt;
	if (GetVectorDistance(vecFocus, vecCur) > 2000.0) { TeleportEntity(iFocusEntity, vecFocus, NULL_VECTOR, ZERO_VECTOR); vecVel = ZERO_VECTOR; }
	Entity_SetLocalVelocity(iFocusEntity, vecVel);
	Entity_GetAbsOrigin(iCameraEntity, vecCur);  // local (parented)
	for (int k=0; k<3; k++) vecVel[k] = (vecLocal[k] - vecCur[k]) / dt;
	Entity_SetLocalVelocity(iCameraEntity, vecVel);

	float vecAng[3];
	vecAng[0] = g_fCamPitchEff[iClient]; vecAng[1] = g_fCamYaw[iClient];
	float vecOldAng[3];
	GetEntPropVector(iCameraEntity, Prop_Data, "m_angRotation", vecOldAng);
	if (FloatAbs(AngleDiff(vecOldAng[0], vecAng[0])) > 0.01 || FloatAbs(AngleDiff(vecOldAng[1], vecAng[1])) > 0.01) {
		TeleportEntity(iCameraEntity, NULL_VECTOR, vecAng, NULL_VECTOR);
	}

	g_eCommander[iClient].vecVector = vecFwd;
	g_eCommander[iClient].fDistance = g_fCamDistEff[iClient];
	if (bHide) {
		float vecCamW[3], vecEye[3];
		AddVectors(vecFocus, vecLocal, vecCamW);
		vecEye = vecFocus;
		vecEye[2] += 40.0;
		Camera_HideSegment(iClient, vecEye, vecCamW);
	} else Camera_HideClear(iClient);
	if (g_bCutaway[iClient]) {
		float vecCamW[3];
		AddVectors(vecFocus, vecLocal, vecCamW);
		Camera_Backdrop(iClient, vecCamW, vecFwd);
	}
	g_iCamLastTick[iClient] = GetGameTickCount();
}

// OnGameFrame: if a commander's usercmd didn't arrive this tick (lag / packet loss), stop the
// camera entities instead of letting the last velocity carry them away.
void Camera_GameFrame() {
	int iTick = GetGameTickCount();
	for (int c=1; c<=MaxClients; c++) {
		if (!g_eCommander[c].bEnabled || iTick - g_iCamLastTick[c] < 2) continue;
		int iFocus = EntRefToEntIndex(g_eCommander[c].iFocusEntRef);
		int iCam = EntRefToEntIndex(g_eCommander[c].iCameraEntRef);
		if (iFocus != INVALID_ENT_REFERENCE) Entity_SetLocalVelocity(iFocus, ZERO_VECTOR);
		if (iCam != INVALID_ENT_REFERENCE) Entity_SetLocalVelocity(iCam, ZERO_VECTOR);
	}
}

// Headless geometry check: solve the camera at every nav area centre and report how it fits.
public Action cmdDebugCamGrid(int iClient, int iArgs) {
	iClient = ResolveClient(iClient);
	if (!HasRTSAccess(iClient)) return Plugin_Handled;
	float fPitch = iArgs >= 1 ? GetCmdArgFloat(1) : g_hCvarCamPitch.FloatValue;
	float fDist = iArgs >= 2 ? GetCmdArgFloat(2) : 700.0;
	int n, nFlat, nShort, nSolid, nBad, nSlab;
	float fSumDist, fMinDist = 99999.0, fSumSlab;
	for (int a=0; a<g_iNavAreas; a++) {
		float vecFocus[3];
		Nav_Center(a, vecFocus);
		for (int r=0; r<4; r++) {
			float fYaw = 45.0 + r * 90.0, p, d;
			Camera_Solve(vecFocus, fPitch, fYaw, fDist, p, d);
			float vecFwd[3], vecCam[3];
			Camera_Forward(p, fYaw, vecFwd);
			for (int k=0; k<3; k++) vecCam[k] = vecFocus[k] - vecFwd[k] * d;
			vecCam[2] += 40.0;
			n++;
			fSumDist += d;
			if (d < fMinDist) fMinDist = d;
			if (p < fPitch - 0.1) nFlat++;
			if (d < fDist * 0.5) nShort++;
			if (TR_PointOutsideWorld(vecCam)) nBad++;
			if (TR_GetPointContents(vecCam) & CONTENTS_SOLID) nSolid++;
			float d0 = Camera_FreeDist(vecFocus, fPitch, fYaw, fDist);
			float dS = Camera_SlabDist(vecFocus, fPitch, fYaw, d0, fDist);
			if (dS > 0.0) { nSlab++; fSumSlab += dS; }
		}
	}
	ReplyToCommand(iClient, "[RTS] camgrid pitch=%.0f dist=%.0f: %d samples, avg dist %.0f, min %.0f, flattened %d, <50%% dist %d, cam in solid %d, outside world %d, cutaway slab %d (avg %.0f)",
		fPitch, fDist, n, n ? fSumDist / n : 0.0, fMinDist, nFlat, nShort, nSolid, nBad, nSlab, nSlab ? fSumSlab / nSlab : 0.0);
	return Plugin_Handled;
}

// Headless: drive the camera of <target> (must be in the command view) for <ticks> with <buttons>
public Action cmdDebugCamSim(int iClient, int iArgs) {
	iClient = ResolveClient(iClient);
	if (!HasRTSAccess(iClient) || iArgs < 3) { ReplyToCommand(iClient, "[RTS] usage: sm_rts_debug_camsim <target> <ticks> <buttons> [mousex] [mousey]"); return Plugin_Handled; }
	char s[64]; GetCmdArg(1, s, sizeof(s));
	int iT = FindTarget(iClient, s, false, false);
	if (iT <= 0 || !g_eCommander[iT].bEnabled) { ReplyToCommand(iClient, "[RTS] target not in command view"); return Plugin_Handled; }
	int n = GetCmdArgInt(2), iButtons = GetCmdArgInt(3);
	int iMouse[2];
	if (iArgs >= 5) { iMouse[0] = GetCmdArgInt(4); iMouse[1] = GetCmdArgInt(5); }
	for (int k=0; k<n; k++) ProcessCameraControls(iT, iButtons, k == 0 ? 0 : iButtons, iMouse);
	int iCam = EntRefToEntIndex(g_eCommander[iT].iCameraEntRef);
	float vecL[3];
	if (iCam != INVALID_ENT_REFERENCE) Entity_GetAbsOrigin(iCam, vecL);
	ReplyToCommand(iClient, "[RTS] camsim focus %.0f %.0f %.0f yaw %.0f/%.0f pitch %.0f dist %.0f/%.0f zoomT %.0f vel %.0f %.0f camLocal %.0f %.0f %.0f",
		g_vecCamFocus[iT][0], g_vecCamFocus[iT][1], g_vecCamFocus[iT][2], g_fCamYaw[iT], g_fCamYawTarget[iT], g_fCamPitchEff[iT],
		g_fCamDist[iT], g_fCamDistEff[iT], g_fZoomTarget[iT], g_vecCamVel[iT][0], g_vecCamVel[iT][1], vecL[0], vecL[1], vecL[2]);
	return Plugin_Handled;
}

public Action cmdRotate(int iClient, int iArgs) {
	if (iClient <= 0 || !g_eCommander[iClient].bEnabled) return Plugin_Handled;
	float f = iArgs >= 1 ? GetCmdArgFloat(1) : 45.0;
	g_fCamYawTarget[iClient] += f;
	return Plugin_Handled;
}

// Distance inside the roof the camera should occupy, or -1 to stay in the air.
// A thin solid with room behind it is a wall or window: step through it.
// A thicker solid is the roof: sit a few units inside so the engine stops drawing it.
// Cap the depth. A roof that joins the sky volume must not swallow the camera.
float Camera_SlabDist(const float vecFocus[3], float fPitch, float fYaw, float fFrom, float fMax) {
	float vecFwd[3], vecP[3];
	Camera_Forward(fPitch, fYaw, vecFwd);
	float fIn = -1.0;
	float fStart = fFrom + 2.0;
	if (fStart < 2.0) fStart = 2.0;
	for (float d = fStart; d <= fMax; d += 2.0) {
		for (int k = 0; k < 3; k++) vecP[k] = vecFocus[k] - vecFwd[k] * d;
		vecP[2] += 40.0;
		bool bSolid = Camera_PointBlocks(vecP);
		if (!bSolid && TR_PointOutsideWorld(vecP)) {
			if (fIn < 0.0) break;
			float fStay = fIn + 4.0;
			if (fStay > d - 2.0) fStay = fIn + 2.0;
			return fStay;
		}
		if (bSolid) {
			if (fIn < 0.0) fIn = d;
			if (d - fIn >= 14.0) return fIn + 6.0;
		} else if (fIn >= 0.0) {
			if (d - fIn <= 16.0) { fIn = -1.0; continue; }
			return fIn + 6.0;
		}
	}
	if (fIn < 0.0) return -1.0;
	return fIn + 4.0;
}

// FOV stays at css_rts_cam_fov while roof hiding is on. The old path still widens under a low ceiling.
void Camera_UpdateFov(int iClient, float fWant, float fGot) {
	int iFov = 90;
	if (g_hCvarCamHide.BoolValue) {
		iFov = g_hCvarCamFov.IntValue;
		if (iFov > 120) iFov = 120;
	} else {
		int iMax = g_hCvarCamFovMax.IntValue;
		float r = fWant > 1.0 ? fGot / fWant : 1.0;
		if (r < 0.85 && iMax > 90) iFov = 90 + RoundToFloor(Clamp((0.85 - r) / 0.55, 0.0, 1.0) * (iMax - 90));
	}
	iFov = (iFov / 4) * 4;
	if (iFov < 90) iFov = 90;
	int iCur = g_iCamFov[iClient] ? g_iCamFov[iClient] : 90;
	if (iFov == iCur) return;
	if (HasEntProp(iClient, Prop_Send, "m_iFOVStart")) SetEntProp(iClient, Prop_Send, "m_iFOVStart", iCur);
	if (HasEntProp(iClient, Prop_Send, "m_flFOVTime")) SetEntPropFloat(iClient, Prop_Send, "m_flFOVTime", GetGameTime());
	if (HasEntProp(iClient, Prop_Data, "m_flFOVRate")) SetEntPropFloat(iClient, Prop_Data, "m_flFOVRate", 0.35);
	SetEntProp(iClient, Prop_Send, "m_iFOV", iFov);
	g_iCamFov[iClient] = iFov;
}

bool Camera_IsViewBlocker(int e) {
	if (e <= MaxClients || !IsValidEntity(e)) return false;
	char s[32];
	GetEntityClassname(e, s, sizeof(s));
	return StrEqual(s, "func_brush") || StrEqual(s, "func_wall") || StrEqual(s, "func_wall_toggle")
		|| StrEqual(s, "func_breakable") || StrEqual(s, "func_illusionary")
		|| StrEqual(s, "func_door") || StrEqual(s, "func_door_rotating") || StrEqual(s, "prop_door_rotating");
}

public bool TraceFilter_HideBrush(int iEntity, int iMask) {
	if (iEntity <= 0) return false;
	for (int i = 0; i < g_iHideProbeN; i++) if (g_iHideProbe[i] == iEntity) return false;
	return Camera_IsViewBlocker(iEntity);
}

bool Camera_HideWanted(int r, int iExcept) {
	for (int c = 1; c <= MaxClients; c++) {
		if (c == iExcept) continue;
		for (int i = 0; i < g_iHideCount[c]; i++) if (g_iHideEnt[c][i] == r) return true;
	}
	return false;
}

void Camera_HideRelease(int c, int r) {
	if (Camera_HideWanted(r, c)) return;
	int e = EntRefToEntIndex(r);
	if (e <= 0 || e >= 2049 || !IsValidEntity(e)) return;
	if (g_iHideOwnedRef[e] != r) return;
	SetEntProp(e, Prop_Send, "m_fEffects", GetEntProp(e, Prop_Send, "m_fEffects") & ~EF_NODRAW_FLAG);
	g_iHideOwnedRef[e] = 0;
}

void Camera_HideClear(int c) {
	if (c <= 0 || c > MaxClients) return;
	for (int i = 0; i < g_iHideCount[c]; i++) Camera_HideRelease(c, g_iHideEnt[c][i]);
	g_iHideCount[c] = 0;
}

void Camera_HideSync(int c, const int iNew[CAM_HIDE_MAX], int n) {
	for (int i = 0; i < g_iHideCount[c]; i++) {
		int r = g_iHideEnt[c][i];
		bool bKeep = false;
		for (int j = 0; j < n; j++) if (iNew[j] == r) { bKeep = true; break; }
		if (!bKeep) Camera_HideRelease(c, r);
	}
	int nKeep = 0;
	for (int j = 0; j < n; j++) {
		int e = EntRefToEntIndex(iNew[j]);
		if (e <= 0 || e >= 2049 || !IsValidEntity(e) || !HasEntProp(e, Prop_Send, "m_fEffects")) continue;
		int f = GetEntProp(e, Prop_Send, "m_fEffects");
		if (!(f & EF_NODRAW_FLAG)) {
			SetEntProp(e, Prop_Send, "m_fEffects", f | EF_NODRAW_FLAG);
			g_iHideOwnedRef[e] = EntIndexToEntRef(e);
		}
		g_iHideEnt[c][nKeep] = iNew[j];
		nKeep++;
	}
	g_iHideCount[c] = nKeep;
}

// Doors and brush entities along the view ray are not world brushes, so nodraw those.
// World roofs and walls are handled by sitting inside them.
void Camera_HideSegment(int c, const float vecFrom[3], const float vecTo[3]) {
	int iNew[CAM_HIDE_MAX];
	int n = 0;
	g_iHideProbeN = 0;
	float vecA[3];
	vecA = vecFrom;
	for (int step = 0; step < CAM_HIDE_MAX && n < CAM_HIDE_MAX; step++) {
		TR_TraceRayFilter(vecA, vecTo, MASK_SOLID, RayType_EndPoint, TraceFilter_HideBrush);
		int e = TR_GetEntityIndex();
		bool bStart = TR_StartSolid();
		if (!bStart && (!TR_DidHit() || e <= 0)) break;
		if (e <= 0 || !Camera_IsViewBlocker(e)) break;
		iNew[n++] = EntIndexToEntRef(e);
		g_iHideProbe[g_iHideProbeN++] = e;
		float vecHit[3], vecDir[3];
		if (bStart) vecHit = vecA;
		else TR_GetEndPosition(vecHit);
		MakeVectorFromPoints(vecHit, vecTo, vecDir);
		if (GetVectorLength(vecDir) < 8.0) break;
		NormalizeVector(vecDir, vecDir);
		for (int k = 0; k < 3; k++) vecA[k] = vecHit[k] + vecDir[k] * (bStart ? 8.0 : 4.0);
	}
	Camera_HideSync(c, iNew, n);
}

public Action cmdDebugCamHide(int iClient, int iArgs) {
	iClient = ResolveClient(iClient);
	if (!HasRTSAccess(iClient)) return Plugin_Handled;
	int t = iClient;
	if (iArgs >= 1) t = GetTargetArg(iClient, 1);
	if (t <= 0 || !g_eCommander[t].bEnabled) { ReplyToCommand(iClient, "[RTS] target not in the command view"); return Plugin_Handled; }
	float vecFwd[3], vecCam[3];
	Camera_Forward(g_fCamPitchEff[t], g_fCamYaw[t], vecFwd);
	for (int k = 0; k < 3; k++) vecCam[k] = g_vecCamFocus[t][k] - vecFwd[k] * g_fCamDistEff[t];
	vecCam[2] += 40.0;
	int iBits = TR_GetPointContents(vecCam);
	ReplyToCommand(iClient, "[RTS] hide %d pitch %.0f/%.0f dist %.0f/%.0f fov %d solid %d window %d outside %d brushes %d cam %.0f %.0f %.0f",
		g_hCvarCamHide.BoolValue, g_fCamPitch[t], g_fCamPitchEff[t], g_fCamDist[t], g_fCamDistEff[t], g_iCamFov[t],
		(iBits & CONTENTS_SOLID) != 0, (iBits & CONTENTS_WINDOW) != 0, TR_PointOutsideWorld(vecCam), g_iHideCount[t],
		vecCam[0], vecCam[1], vecCam[2]);
	return Plugin_Handled;
}

// ---- cutaway view ----
void Camera_SetCutaway(int c, bool bOn) {
	if (g_bCutaway[c] == bOn) return;
	g_bCutaway[c] = bOn;
	if (bOn) {
		if (g_fZoomTarget[c] < 1400.0) g_fZoomTarget[c] = 1400.0;
		g_fCamPitch[c] = g_fCamPitch[c] < 70.0 ? 70.0 : g_fCamPitch[c];
	} else {
		int e = EntRefToEntIndex(g_iBackdropRef[c]);
		if (e > 0) RemoveEntity(e);
		g_iBackdropRef[c] = INVALID_ENT_REFERENCE;
		if (g_fZoomTarget[c] > g_hCvarCamStartDist.FloatValue) g_fZoomTarget[c] = g_hCvarCamStartDist.FloatValue;
	}
	Camera_RefreshTransmit();
}

public Action cmdCutaway(int iClient, int iArgs) {
	if (iClient <= 0 || !g_eCommander[iClient].bEnabled) return Plugin_Handled;
	if (!g_hCvarCamXray.BoolValue) { PrintHintText(iClient, "Cutaway view is off on this server"); return Plugin_Handled; }
	Camera_SetCutaway(iClient, !g_bCutaway[iClient]);
	Hud_Action(iClient, "%s", g_bCutaway[iClient] ? "CUTAWAY VIEW: looking through roofs  (X = normal view)" : "Normal view");
	return Plugin_Handled;
}

public Action SDKHookCB_BackdropTransmit(int iEnt, int iClient) {
	return EntIndexToEntRef(iEnt) == g_iBackdropRef[iClient] ? Plugin_Continue : Plugin_Handled;
}

// dark sprite far behind the map: fills the empty void (otherwise the client smears old frames there)
void Camera_Backdrop(int c, const float vecCam[3], const float vecFwd[3]) {
	return;   // v0.5.3.1: no full-screen sprites at all (the backdrop could cover the screen)
	int e = EntRefToEntIndex(g_iBackdropRef[c]);
	float fD = g_fCamDistEff[c] + 4000.0;
	float vecPos[3];
	for (int k=0; k<3; k++) vecPos[k] = vecCam[k] + vecFwd[k] * fD;
	if (e <= 0) {
		e = CreateEntityByName("env_sprite");
		if (e == -1) return;
		char sScale[16];
		FloatToString(fD * 2.0 * 1.6 * 1.6 / 16.0, sScale, sizeof(sScale));
		DispatchKeyValue(e, "model", "css_rts/backdrop.vmt");
		DispatchKeyValue(e, "rendermode", "0");
		DispatchKeyValue(e, "scale", sScale);
		DispatchKeyValue(e, "spawnflags", "1");
		DispatchKeyValue(e, "targetname", "css_rts_backdrop");
		DispatchKeyValueVector(e, "origin", vecPos);
		DispatchSpawn(e);
		AcceptEntityInput(e, "ShowSprite");
		g_iBackdropRef[c] = EntIndexToEntRef(e);
		SDKHook(e, SDKHook_SetTransmit, SDKHookCB_BackdropTransmit);
		return;
	}
	SetEntPropFloat(e, Prop_Data, "m_flSpriteScale", fD * 2.0 * 1.6 * 1.6 / 16.0);
	TeleportEntity(e, vecPos, NULL_VECTOR, NULL_VECTOR);
}

bool Camera_TransmitView() {
	if (g_hCvarCamHide.BoolValue) return true;
	return !g_hCvarCamCollide.BoolValue;
}

// From inside a roof the server PVS is empty, so force-send the things the Commander needs to see
void Camera_RefreshTransmit() {
	g_bCutawayAny = false;
	for (int c=1; c<=MaxClients; c++) if ((g_bCutaway[c] || Camera_TransmitView()) && g_eCommander[c].bEnabled && IsClientInGame(c) && !IsFakeClient(c)) g_bCutawayAny = true;
	int iMax = GetMaxEntities();
	char sCls[32];
	for (int e=1; e<iMax && e<2049; e++) {
		if (!IsValidEdict(e)) { g_bForcedAlways[e] = false; continue; }
		bool bWant = false;
		if (g_bCutawayAny) {
			if (e <= MaxClients) bWant = IsClientInGame(e) && IsPlayerAlive(e);
			else {
				GetEdictClassname(e, sCls, sizeof(sCls));
				bWant = StrContains(sCls, "prop_") == 0 || StrContains(sCls, "func_door") == 0 || StrContains(sCls, "weapon_") == 0 || StrEqual(sCls, "hostage_entity");
			}
		}
		int f = GetEdictFlags(e);
		if (bWant && !(f & FL_EDICT_ALWAYS)) { SetEdictFlags(e, f | FL_EDICT_ALWAYS); g_bForcedAlways[e] = true; }
		else if (!bWant && g_bForcedAlways[e]) { SetEdictFlags(e, f & ~FL_EDICT_ALWAYS); g_bForcedAlways[e] = false; }
	}
}

public Action Timer_CutawayTransmit(Handle h) {
	bool bFreeCam = false;
	if (Camera_TransmitView()) for (int c=1; c<=MaxClients; c++) if (g_eCommander[c].bEnabled && IsClientInGame(c) && !IsFakeClient(c)) bFreeCam = true;
	if (g_bCutawayAny || bFreeCam) {
		for (int c=1; c<=MaxClients; c++) if (g_bCutaway[c] && !g_eCommander[c].bEnabled) g_bCutaway[c] = false;
		Camera_RefreshTransmit();
	}
	return Plugin_Continue;
}

public Action cmdDebugCutaway(int iClient, int iArgs) {
	iClient = ResolveClient(iClient);
	if (!HasRTSAccess(iClient) || iArgs < 2) return Plugin_Handled;
	int t = GetTargetArg(iClient, 1);
	if (!t || !g_eCommander[t].bEnabled) { ReplyToCommand(iClient, "[RTS] target not in the command view"); return Plugin_Handled; }
	Camera_SetCutaway(t, GetCmdArgInt(2) != 0);
	int n;
	for (int e=1; e<2049; e++) if (g_bForcedAlways[e]) n++;
	ReplyToCommand(iClient, "[RTS] cutaway %N = %d, forced-transmit %d, zoomT %.0f pitch %.0f backdrop %d", t, g_bCutaway[t], n, g_fZoomTarget[t], g_fCamPitch[t], EntRefToEntIndex(g_iBackdropRef[t]));
	return Plugin_Handled;
}
