// css_rts/lobby_state.sp -- lobby/game state globals (included early; logic in lobby.sp)

enum GameState {
	GS_Lobby = 0,
	GS_Countdown,
	GS_Live,
	GS_Ended
}

enum GameMode {
	Mode_Workers = 0,   // kill all enemy workers
	Mode_Attrition,     // enemy unit pool runs out
	Mode_IntelRace,     // first team to earn the Intel target
	Mode_HQ             // destroy the enemy command hub
}

GameState g_eGame = GS_Lobby;
GameMode g_eMode = Mode_Attrition;
int g_iSetPool = 200;
int g_iSetMinutes = 40;
int g_iSetBots = 5;           // FPS slots per team (humans + bots)
int g_iSetDifficulty = 1;     // bot_difficulty 0..3
int g_iSetSeries = 1;         // 1 / 3 / 5
int g_iSetIntelTarget = 10000;
int g_iSetCmdrUserId[4];      // 0 = auto (first human)
bool g_bVsAi;                 // Create Server: Vs AI mirrors the host's buys onto the other team
bool g_bVsAiBusy;

int g_iHostUserId;
float g_fCountdownEnd;
float g_fMatchStart;
float g_fMatchEnd;
int g_iSeriesWins[4];
int g_iSeriesGame;            // games finished in this series
int g_iEndGen;                // increments on every end so stale AfterGame timers no-op
int g_iIntelEarned[4];        // Intel Race counts earned Intel (spending doesn't hurt)
bool g_bHadWorkers[4];
Handle g_hHudLobby;
ConVar g_hCvarLobby;
ConVar g_hCvarCountdown;
ConVar g_hCvarWEWorkers;

char g_sModeNames[][] = {"Workers Elimination", "Attrition", "Intel Race", "HQ Destruction"};
char g_sDiffNames[][] = {"Easy", "Normal", "Hard", "Expert"};

