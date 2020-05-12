// Copyright (C) 2007-2011 CodingDirect LLC
// This File is Licensed under GPLv3, see 'Licenses/License_KAC.txt' for Details

// Compiler Settings

#pragma newdecls optional
#pragma dynamic 393216 // 1536KB (1024+512) // 25.10.19 - 205924(1.8)-255224(1.10) bytes required - I know this MUCH for a Plugin, the normal Stack is 4KB! But do mind that this is nothing compared to only 1 GB of Memory!


//- Includes -//

#include <sdktools>
#undef REQUIRE_EXTENSIONS 
#include <sdkhooks>
#define REQUIRE_EXTENSIONS
// #include <socket> // Required for the networking Module
#include <smlib_kacr> // Copyright (C) SMLIB Contributors // This Include is Licensed under GPLv3, see 'Licenses/License_SMLIB.txt' for Details
#include <autoexecconfig_kacr> //  Copyright (C) 2013-2017 Impact // This Include is Licensed under GPLv3, see 'Licenses/License_AutoExecConfig.txt' for Details 
#undef REQUIRE_PLUGIN
#include <ASteambot> // Copyright (c) ASteamBot Contributors // This Include is Licensed under The MIT License, see 'Licenses/License_ASteambot.txt' for Details // BUG: Native "ASteambot_SendMesssage" was not found
#define REQUIRE_PLUGIN


//- Natives -//

// SourceBans++
native void SBPP_BanPlayer(int iAdmin, int iTarget, int iTime, const char[] sReason);
native void SBPP_ReportPlayer(int iReporter, int iTarget, const char[] sReason);

// Sourcebans 2.X
native void SBBanPlayer(client, target, time, char[] reason);
native void SB_ReportPlayer(int client, int target, const char[] reason);

native int AddTargetsToMenu2(Handle menu, int source_client, int flags); // TODO: Normally this dosent need to be done, but ive got some strange BUG with this #ref 273812


//- Defines -//

#define PLUGIN_VERSION "0.1" // TODO: No versioning right now, we are on a Rolling Release Cycle
#define MAX_ENTITIES 2048 // Maximum networkable Entitys (Edicts), 2048 is hardcoded in the Engine

#define loop for(;;) // Unlimited Loop

#define KACR_Action_Count 13 // 18.11.19 - 12+1 carryed
#define KACR_Action_Ban 1
#define KACR_Action_TimeBan 2
#define KACR_Action_ServerBan 3
#define KACR_Action_ServerTimeBan 4
#define KACR_Action_Kick 5
#define KACR_Action_Crash 6
#define KACR_Action_ReportSB 7
#define KACR_Action_ReportAdmins 8
#define KACR_Action_ReportSteamAdmins 9
#define KACR_Action_AskSteamAdmin 10
#define KACR_Action_Log 11
#define KACR_Action_ReportIRC 12


//- Global Variables -//

Handle g_hValidateTimer[MAXPLAYERS + 1];
Handle g_hClearTimer, g_hCVar_Version;
EngineVersion g_hGame;

StringMap g_hCLang[MAXPLAYERS + 1];
StringMap g_hSLang, g_hDenyArray;

bool g_bConnected[MAXPLAYERS + 1]; // I use these instead of the natives because they are cheaper to call
bool g_bAuthorized[MAXPLAYERS + 1]; // When I need to check on a client's state.  Natives are very taxing on
bool g_bInGame[MAXPLAYERS + 1]; // system resources as compared to these. - Kigen
bool g_bIsAdmin[MAXPLAYERS + 1];
bool g_bIsFake[MAXPLAYERS + 1];
bool g_bSourceBans, g_bSourceBansPP, g_bASteambot, g_bAdminmenu, g_bMapStarted;


//- KACR Modules -// Note that the ordering of these Includes is important

#include "kigen-ac_redux/translations.sp"	// Translations Module - NEEDED FIRST
#include "kigen-ac_redux/client.sp"			// Client Module
#include "kigen-ac_redux/commands.sp"		// Commands Module
#include "kigen-ac_redux/cvars.sp"			// CVar Module
#include "kigen-ac_redux/eyetest.sp"		// Eye Test Module
#include "kigen-ac_redux/rcon.sp"			// RCON Module
#include "kigen-ac_redux/status.sp"			// Status Module
#include "kigen-ac_redux/stocks.sp"			// Stocks Module


public Plugin myinfo = 
{
	name = "Kigen's Anti-Cheat Redux", 
	author = "Playa (Formerly Max Krivanek)", 
	description = "An Universal Anti Cheat Solution compactible with most Source Engine Games", 
	version = PLUGIN_VERSION, 
	url = "github.com/DJPlaya/Kigen-AC-Redux"
};


//- Plugin, Native Config Functions -//

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, err_max)
{
	MarkNativeAsOptional("SDKHook");
	MarkNativeAsOptional("SDKUnhook");
	MarkNativeAsOptional("SBPP_BanPlayer");
	MarkNativeAsOptional("SBPP_ReportPlayer");
	MarkNativeAsOptional("SBBanPlayer");
	MarkNativeAsOptional("SB_ReportPlayer");
	MarkNativeAsOptional("ASteambot_RegisterModule");
	MarkNativeAsOptional("ASteambot_RemoveModule");
	MarkNativeAsOptional("ASteambot_SendMesssage");
	MarkNativeAsOptional("ASteambot_IsConnected");
	MarkNativeAsOptional("AddTargetsToMenu2"); // TODO: Normally this dosent need to be done, but ive got some strange BUG with this #ref 273812
	
	return APLRes_Success;
}

public void OnPluginStart()
{
	if (GetMaxEntities() > MAX_ENTITIES) // I know this is a bit overkill, still we want to be on the safe Side // AskPluginLoad may be called before Mapstart, so we check this once we do load
		KACR_Log(true, "[Critical] The Server has more Entitys available then the Plugin can handle, Report this Error to get it fixed")
		
	g_hDenyArray = new StringMap();
	g_hGame = GetEngineVersion(); // Identify the game
	
	AutoExecConfig_SetFile("Kigen-AC_Redux"); // Set which file to write Cvars to
	
	//- Module Calls -//
	Status_OnPluginStart();
	Client_OnPluginStart()
	Commands_OnPluginStart();
	CVars_OnPluginStart();
	Eyetest_OnPluginStart();
	RCON_OnPluginStart();
	Trans_OnPluginStart();
	
	//- Get server language -//
	char f_sLang[8];
	GetLanguageInfo(GetServerLanguage(), f_sLang, sizeof(f_sLang));
	if (!g_hLanguages.GetValue(f_sLang, any:g_hSLang)) // If we can't find the server's Language revert to English. - Kigen
		g_hLanguages.GetValue("en", any:g_hSLang);
		
	g_hClearTimer = CreateTimer(14400.0, KACR_ClearTimer, _, TIMER_REPEAT); // Clear the Deny Array every 4 hours.
	
	AutoExecConfig_ExecuteFile(); // Execute the Config
	AutoExecConfig_CleanFile(); // Cleanup the Config (slow process)
	
	g_hCVar_Version = CreateConVar("kacr_version", PLUGIN_VERSION, "KACR Plugin Version (do not touch)", FCVAR_NOTIFY | FCVAR_SPONLY | FCVAR_DONTRECORD | FCVAR_UNLOGGED); // "notify" - So that we appear on Server Tracking Sites, "sponly" because we do not want Chat Messages about this CVar caused by "notify", "dontrecord" - So that we don't get saved to the Auto cfg, "unlogged" - Because changes of this CVar dosent need to be logged
	
	SetConVarString(g_hCVar_Version, PLUGIN_VERSION); // TODO: Is this really needed?
	HookConVarChange(g_hCVar_Version, ConVarChanged_Version); // Made, so no one touches the Version
	
	KACR_PrintToServer(KACR_LOADED);
}

public void OnPluginEnd()
{
	Commands_OnPluginEnd();
	Eyetest_OnPluginEnd();
	Trans_OnPluginEnd();
	
	if (g_bASteambot)
		ASteambot_RemoveModule();
		
	for (int iClient = 1; iClient <= MaxClients; iClient++)
	{
		g_bConnected[iClient] = false;
		g_bAuthorized[iClient] = false;
		g_bInGame[iClient] = false;
		g_bIsAdmin[iClient] = false;
		g_hCLang[iClient] = g_hSLang;
		g_bShouldProcess[iClient] = false;
		
		if (g_hValidateTimer[iClient] != INVALID_HANDLE)
			CloseHandle(g_hValidateTimer[iClient]);
			
		CVars_OnClientDisconnect(iClient);
	}
	
	if (g_hClearTimer != INVALID_HANDLE)
		CloseHandle(g_hClearTimer);
}

public void OnAllPluginsLoaded()
{
	char cReason[256], cAuthID[64];
	
	//- Library/Plugin Checks -//
	
	if (LibraryExists("sourcebans++")) // FindPluginByFile("sbpp_main.smx")
		g_bSourceBansPP = true;
		
	if (LibraryExists("sourcebans")) // FindPluginByFile("sourcebans.smx")
	{
		g_bSourceBans = true;
		if (g_bSourceBansPP && g_bSourceBans)
			KACR_Log(false, "[Warning] Sourcebans++ and Sourcebans 2.X are installed at the same Time! This can Result in Problems, KACR will only use SB++ for now");
	}
	
	if (LibraryExists("ASteambot"))
	{
		ASteambot_RegisterModule("KACR");
		g_bASteambot = true;
	}
	
	if (LibraryExists("adminmenu"))
		g_bAdminmenu = true;
		
	//- Module Calls -//
	Commands_OnAllPluginsLoaded();
	
	//- Late load stuff -//
	for (int ig_iSongCount = 1; ig_iSongCount <= MaxClients; ig_iSongCount++)
	{
		if (IsClientConnected(ig_iSongCount))
		{
			if (!OnClientConnect(ig_iSongCount, cReason, sizeof(cReason))) // Check all Clients because were late
				continue;
				
			if (IsClientAuthorized(ig_iSongCount) && GetClientAuthId(ig_iSongCount, AuthId_Steam2, cAuthID, sizeof(cAuthID)))
			{
				OnClientAuthorized(ig_iSongCount, cAuthID);
				OnClientPostAdminCheck(ig_iSongCount);
			}
			
			if (IsClientInGame(ig_iSongCount))
				OnClientPutInServer(ig_iSongCount);
		}
	}
}

public void OnConfigsExecuted() // TODO: Make this Part bigger // This dosent belong into cvars because that is for client vars only // TODO: Move sv_cheats to here
{
	//- Prevent Speeds -//
	Handle hVar1 = FindConVar("sv_max_usercmd_future_ticks"); // Prevent Speedhacks
	if (hVar1) // != INVALID_HANDLE
	{
		if (GetConVarInt(hVar1) > 8)// The Value of 1 is outdated, CSS and CSGO do have 8 as default Value - 5.20 // (GetConVarInt(hVar1) != 1) // TODO: Replace with 'hVar1.IntValue != 1' once we dropped legacy Support
		{
			KACR_Log(false, "[Warning] 'sv_max_usercmd_future_ticks' was set to '%i' which is a risky Value, re-setting it to its default '8'", GetConVarInt(hVar1)); // TODO: Replace with 'hVar1.IntValue' once we dropped legacy Support
			SetConVarInt(hVar1, 8); // TODO: Replace with 'hVar1.SetInt(...)' once we dropped legacy Support
		}
	}
}

public void OnLibraryAdded(const char[] cName)
{
	if (StrEqual(cName, "sourcebans++", false)) // FindPluginByFile("sbpp_main.smx")
	{
		g_bSourceBansPP = true;
		if (g_bSourceBansPP && g_bSourceBans)
			KACR_Log(false, "[Warning] Sourcebans++ and Sourcebans 2.X are installed at the same Time! This can Result in Problems, KACR will only use SB++ for now");
	}
	
	else if (StrEqual(cName, "sourcebans", false)) // FindPluginByFile("sourcebans.smx")
	{
		g_bSourceBans = true;
		if (g_bSourceBansPP && g_bSourceBans)
			KACR_Log(false, "[Warning] Sourcebans++ and Sourcebans 2.X are installed at the same Time! This can Result in Problems, KACR will only use SB++ for now");
	}
	
	else if (StrEqual(cName, "ASteambot", false) && !g_bASteambot) // Check so we do not register twice
	{
		ASteambot_RegisterModule("KACR");
		g_bASteambot = true;
	}
	
	else if (StrEqual(cName, "adminmenu", false))
		g_bAdminmenu = true;
}

public void OnLibraryRemoved(const char[] cName)
{
	if (StrEqual(cName, "sourcebans++", false)) // FindPluginByFile("sbpp_main.smx")
		g_bSourceBansPP = false;
		
	else if (StrEqual(cName, "sourcebans", false)) // FindPluginByFile("sourcebans.smx")
		g_bSourceBans = false;
		
	else if (StrEqual(cName, "ASteambot", false))
		g_bASteambot = false;
		
	else if (StrEqual(cName, "adminmenu", false))
		g_bAdminmenu = false;
}


//- Map Functions -//

public void OnMapStart()
{
	g_bMapStarted = true;
	CVars_CreateNewOrder();
}

public void OnMapEnd()
{
	g_bMapStarted = false;
	Client_OnMapEnd();
}


//- Client Functions -//

public bool OnClientConnect(iClient, char[] rejectmsg, size)
{
	if (IsFakeClient(iClient)) // Bots suck.
	{
		g_bIsFake[iClient] = true;
		return true;
	}
	
	g_bConnected[iClient] = true;
	g_hCLang[iClient] = g_hSLang;
	
	return Client_OnClientConnect(iClient, rejectmsg, size);
}

public void OnClientAuthorized(iClient, const char[] cAuth)
{
	if (IsFakeClient(iClient)) // Bots are annoying...
		return;
		
	Handle f_hTemp;
	char cReason[256];
	if (g_hDenyArray.GetString(cAuth, cReason, sizeof(cReason)))
	{
		KickClient(iClient, "%s", cReason);
		OnClientDisconnect(iClient);
		return;
	}
	
	g_bAuthorized[iClient] = true;
	
	if (g_bInGame[iClient])
		g_hPeriodicTimer[iClient] = CreateTimer(0.1, CVars_PeriodicTimer, iClient);
		
	f_hTemp = g_hValidateTimer[iClient];
	g_hValidateTimer[iClient] = INVALID_HANDLE;
	
	if (f_hTemp != INVALID_HANDLE)
		CloseHandle(f_hTemp);
}

public void OnClientPutInServer(iClient)
{
	Eyetest_OnClientPutInServer(iClient); // Ok, we'll help them bots too.
	
	if (IsFakeClient(iClient)) // Death to them bots!
		return;
		
	char f_sLang[8];
	
	g_bInGame[iClient] = true;
	
	if (!g_bAuthorized[iClient]) // Not authorized yet?!?
		g_hValidateTimer[iClient] = CreateTimer(10.0, KACR_ValidateTimer, iClient);
		
	else
		g_hPeriodicTimer[iClient] = CreateTimer(0.1, CVars_PeriodicTimer, iClient);
		
	GetLanguageInfo(GetClientLanguage(iClient), f_sLang, sizeof(f_sLang));
	if (!g_hLanguages.GetValue(f_sLang, g_hCLang[iClient]))
		g_hCLang[iClient] = g_hSLang;
}

public void OnClientPostAdminCheck(iClient)
{
	if (IsFakeClient(iClient)) // Humans for the WIN!
		return;
		
	if ((GetUserFlagBits(iClient) & ADMFLAG_GENERIC))
		g_bIsAdmin[iClient] = true; // Generic Admin
}

public void OnClientDisconnect(iClient)
{
	// if ( IsFake aww, screw it. :P
	Handle hTemp;
	
	g_bConnected[iClient] = false;
	g_bAuthorized[iClient] = false;
	g_bInGame[iClient] = false;
	g_bIsAdmin[iClient] = false;
	g_bIsFake[iClient] = false;
	g_hCLang[iClient] = g_hSLang;
	g_bShouldProcess[iClient] = false;
	g_bHooked[iClient] = false;
	
	//OnClientDisconnect(iClient); // TODO: Test this out #ref 573823
	for (int iCount = 1; iCount <= MaxClients; iCount++) // TODO: Is this really needed #ref 573823
		if (g_bConnected[iCount] && (!IsClientConnected(iCount) || IsFakeClient(iCount)))
			OnClientDisconnect(iCount);
			
	hTemp = g_hValidateTimer[iClient];
	g_hValidateTimer[iClient] = INVALID_HANDLE;
	if (hTemp != INVALID_HANDLE)
		CloseHandle(hTemp);
		
	CVars_OnClientDisconnect(iClient);
}


//- Timers -//

public Action KACR_ValidateTimer(Handle hTimer, any iClient)
{
	g_hValidateTimer[iClient] = INVALID_HANDLE;
	
	if (!g_bInGame[iClient] || g_bAuthorized[iClient])
		return Plugin_Stop;
		
	KACR_Kick(iClient, KACR_FAILEDAUTH); // Failed to auth in-time
	return Plugin_Stop;
}

public Action KACR_ClearTimer(Handle hTimer)
{
	g_hDenyArray.Clear();
}


//- ConVar Hook -//

public void ConVarChanged_Version(Handle hCvar, const char[] cOldValue, const char[] cNewValue)
{
	if (!StrEqual(cNewValue, PLUGIN_VERSION))
		SetConVarString(g_hCVar_Version, PLUGIN_VERSION);
}