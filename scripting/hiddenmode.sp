#include <sourcemod>
#include <sdkhooks>
#include <cstrike>
#include <hiddenmode>

#pragma semicolon 1

#define charsmax(%1) sizeof(%1)-1

// Cvar Handle
new Handle:pCvar_iTimeCountdown;
new Handle:pCvar_bFallDamage;
new Handle:pCvar_iHiddenHP;
new Handle:pCvar_bShowHiddenHP;

// Timer Handle
new Handle:Timer_Countdown;
new Handle:Timer_ShowHiddenHP;

// Global variables
new bool:bRoundStart = false;
new bool:bGameBegin = false;
new bool:bRoundEnd = false;
new gMaxPlayers;
new gHiddenIndex;
new gTimer;
new PlayerClass:gPlayerClass[MAXPLAYERS + 1];
new gPlayerTeam[MAXPLAYERS + 1];
new gRoundCount;
new gHumanWinRound;
new gHiddenWinRound;

public Plugin myinfo = {
	name        = "",
	author      = "",
	description = "",
	version     = "0.0.0",
	url         = ""
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	CreateNative("HM_IsPlayerHidden", Func_IsPlayerHidden);
	CreateNative("HM_IsPlayerHuman", Func_IsPlayerHuman);
	CreateNative("HM_SetPlayerClass", Func_SetPlayerClass);
	
	// Register mod library
	RegPluginLibrary("hiddenmode");
	return APLRes_Success;
}

public void OnPluginStart() {
	HookEvent("round_start", OnRoundStart);
	HookEvent("round_end", OnRoundEnd);
	
	pCvar_iTimeCountdown = CreateConVar("hm_cdtime", "10");
	pCvar_bFallDamage = CreateConVar("hm_falldamage", "0");
	pCvar_iHiddenHP = CreateConVar("hm_hiddenhp", "5000");
	pCvar_bShowHiddenHP = CreateConVar("hm_showhiddenhp", "1");
}



public Func_IsPlayerHidden(Handle plugin, int numParams) {
	int iClient = GetNativeCell(1);
	return gPlayerClass[iClient] == TEAM_HIDDEN ? true : false;
}

public Func_IsPlayerHuman(Handle plugin, int numParams) {
	int iClient = GetNativeCell(1);
	return gPlayerClass[iClient] == TEAM_HUMAN ? true : false;
}

public Func_SetPlayerClass(Handle plugin, int numParams) {
	int iClient = GetNativeCell(1);
	new PlayerClass:class = GetNativeCell(2);
	
	gPlayerClass[iClient] = class;
}

public OnClientPutInServer(client) {
	SDKHook(client, SDKHook_TraceAttack, TraceAttack); 
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
	gPlayerClass[client] = TEAM_HUMAN;
}

public OnRoundStart(Handle:event, const String:name[], bool:dontBroadcast) {
	bRoundStart = true;
	bGameBegin = false;
	bRoundEnd = false;
	
	gTimer = GetConVarInt(pCvar_iTimeCountdown);
	Timer_Countdown = CreateTimer(1.0, TimerCountdown, _, TIMER_REPEAT); 
}

public OnRoundEnd(Handle:event, const String:name[], bool:dontBroadcast) {
	bRoundStart = false;
	bGameBegin = false;
	bRoundEnd = true;
	
	// Reset Hidden ID
	gHiddenIndex = 0;
	
	FuncBalanceTeam();
}

public Action:TimerCountdown(Handle:timer) {
	if (gTimer <= 0) {
		gMaxPlayers = FuncCountPlayerConnected();
		gHiddenIndex = FuncGetRandomPlayerAlive(GetRandomInt(1, gMaxPlayers));
		
		new String:hiddenName[64];
		GetClientName(gHiddenIndex, hiddenName, charsmax(hiddenName));
		PrintHintTextToAll("%s has become The Hidden", hiddenName);
		PrintToChatAll("%s has become The Hidden", hiddenName);
		bGameBegin = true;
		
		StartHiddenMode();
		
		KillTimer(Timer_Countdown);
		return Plugin_Stop;
	}
	
	PrintHintTextToAll("The Hidden will be selected after %d second(s)", gTimer);
	PrintToChatAll("The Hidden will be selected after %d second(s)", gTimer);
	gTimer--;
	return Plugin_Continue;
}

public Action:OnTakeDamage(victim, &attacker, &inflictor, &Float:damage, &damagetype) {
	// Ignore all damage send to player if game is not begin
	if (!bRoundStart || !bGameBegin || bRoundEnd) return Plugin_Handled;
	
	// Game begin
	if (bRoundStart && bGameBegin) {
		if (victim > 0 && victim <= MaxClients) {
			if(attacker <=0 || attacker > MaxClients)
				return Plugin_Handled;
			else
				return Plugin_Continue;
				
		}
	}
	
	return Plugin_Handled;
}

public Action:TraceAttack(victim, &attacker, &inflictor, &Float:damage, &damageType, &ammoType, hitBox, hitGroup) {
	// Ignore all damage send to player if game is not begin
	if (!bRoundStart || !bGameBegin || bRoundEnd) return Plugin_Handled;
	
	// Game begin
	if (bRoundStart && bGameBegin) {
		if (victim > 0 && victim <= MaxClients) {
			if(attacker <=0 || attacker > MaxClients)
				return Plugin_Handled;
			else
				return Plugin_Continue;
				
		}
	}
	
	return Plugin_Handled;
}

public StartHiddenMode() {
	// First, set class Human or Hidden for all of players
	FuncSetPlayersClass();
	
	// Change players team by class
	FuncChangeAllHumanToCT();
	FuncMakeHidden();
	
}

FuncMakeHidden() {
	// Change The Hidden to T
	FuncChangeHiddenToT();
	
	// Set HP to The Hidden
	SetEntityHealth(gHiddenIndex, GetConVarInt(pCvar_iHiddenHP));
	
	// Strip all weapon
	Client_RemoveAllWeapons(gHiddenIndex, 
	
	// Toggle show The Hidden's HP to all players
	if (GetConVarBool(pCvar_bShowHiddenHP))
		Timer_ShowHiddenHP = CreateTimer(0.1, ShowHiddenHP, _, TIMER_REPEAT);
}


public Action:ShowHiddenHP(Handle:timer) {
	if (!bRoundStart || bRoundEnd || gHiddenIndex == 0) {
		KillTimer(Timer_ShowHiddenHP);
		return Plugin_Stop;
	}
	
	if(bGameBegin) {
		PrintHintTextToAll("Hidden's HP: %d", GetClientHealth(gHiddenIndex));
	}
	
	return Plugin_Continue;
}

FuncChangePlayerTeam(int iClient, newTeam) {
	// If change to CS_TEAM_NONE. Stop change team
	if (newTeam == CS_TEAM_NONE) return;
	
	new curTeam = GetClientTeam(iClient);
	
	// If new team is the current team. Stop change team
	if (curTeam == newTeam) return;
	
	// Change team
	CS_SwitchTeam(iClient, newTeam);
}

FuncSetPlayersClass() {
	for (int id = 1; id <= MaxClients; id++) {
		if (IsClientConnected(id)) {
			if (id != gHiddenIndex)
				gPlayerClass[id] = TEAM_HUMAN;
			else
				gPlayerClass[id] = TEAM_HIDDEN;
		}
	}		
}
FuncChangeAllHumanToCT() {
	for (int id = 1; id <= MaxClients; id++) {
		if (!IsClientConnected(id) || gPlayerClass[id] != TEAM_HUMAN) continue;
		
		if (gPlayerClass[id] == TEAM_HUMAN)
			FuncChangePlayerTeam(id, CS_TEAM_CT);
	}
}

FuncChangeHiddenToT() {
	// If no The Hidden selected. Stop change team
	if (gHiddenIndex == 0) return;
	
	// Check chosen player is set to The Hidden or not
	if (gPlayerClass[gHiddenIndex] != TEAM_HIDDEN) return;
	
	// Everything is done
	FuncChangePlayerTeam(gHiddenIndex, CS_TEAM_T);
}

FuncGetRandomPlayerAlive(int n) {
	static iAlive, id;
	iAlive = 0;
	
	for (id = 1; id <= MaxClients; id++) {
		if (IsPlayerAlive(id)) 	iAlive++;
		if (iAlive == n) 		return id;
	}
	
	return -1;
}

FuncBalanceTeam() {
	// Get amount of users playing
	static iPlayersNum;
	iPlayersNum = FuncCountPlayerConnected();
	
	// No players, don't bother
	if (iPlayersNum < 1) return;
	
	// Split players evenly
	static iTerrors, iMaxTerrors, id, curTeam;
	iMaxTerrors = iPlayersNum/2;
	iTerrors = 0;
	
	// First, set everyone to CT
	for (id = 1; id <= MaxClients; id++) {
		// Skip if not connected
		if (!IsClientConnected(id))
			continue;
		
		curTeam = GetClientTeam(id);
		
		// Skip if not playing
		if (curTeam == CS_TEAM_SPECTATOR || curTeam == CS_TEAM_NONE)
			continue;
		
		// Set team
		FuncChangePlayerTeam(id, CS_TEAM_CT);
	}
	
	// Then randomly set half of the players to Terrorists
	while (iTerrors < iMaxTerrors)
	{
		// Keep looping through all players
		if (++id > MaxClients) id = 1;
		
		// Skip if not connected
		if (!IsClientConnected(id))
			continue;
		
		// Skip if not playing or already a Terrorist
		if (GetClientTeam(id) != CS_TEAM_CT)
			continue;
		
		// Random chance
		if (GetRandomInt(0, 1)) {
			FuncChangePlayerTeam(id, CS_TEAM_T);
			iTerrors++;
		}
	}
}

FuncCountPlayerConnected() {
	static iConnect, id;
	iConnect = 0;
	
	for (id = 1; id <= MaxClients; id++) {
		if (IsClientConnected(id)) {
			iConnect++;
		}
	}
	
	return iConnect;
}

FuncCountCTsAlive() {
	static iCTs, id;
	iCTs = 0;
	
	for (id = 1; id <= MaxClients; id++) {
		if (IsPlayerAlive(id)) {
			if (GetClientTeam(id) == CS_TEAM_CT) {
				iCTs++;
			}
		}
	}
	
	return iCTs;
}

FuncCountTsAlive() {
	static iTs, id;
	iTs = 0;
	
	for (id = 1; id <= MaxClients; id++) {
		if (IsPlayerAlive(id)) {
			if (GetClientTeam(id) == CS_TEAM_T) {
				iTs++;
			}
		}
	}
	
	return iTs;
}

/**
 * Gets the offset for a client's weapon list (m_hMyWeapons).
 * The offset will saved globally for optimization.
 *
 * @param client		Client Index.
 * @return				Weapon list offset or -1 on failure.
 */
stock Client_GetWeaponsOffset(client)
{
	static offset = -1;

	if (offset == -1) {
		offset = FindDataMapOffs(client, "m_hMyWeapons");
	}
	
	return offset;
}

/**
 * Changes the active/current weapon of a player by Index.
 * Note: No changing animation will be played !
 *
 * @param client		Client Index.
 * @param weapon		Index of a valid weapon.
 * @noreturn
 */
stock Client_SetActiveWeapon(client, weapon)
{
	SetEntPropEnt(client, Prop_Data, "m_hActiveWeapon", weapon);
	ChangeEdictState(client, FindDataMapOffs(client, "m_hActiveWeapon"));
}

/**
 * Sets the primary and secondary ammo the player carries for a specific weapon index.
 *
 * @param client		Client Index.
 * @param weapon		Weapon Entity Index.
 * @param primaryAmmo	Primary ammo stock value from the client, if -1 the value is untouched.
 * @param secondaryAmmo	Secondary ammo stock value from the client, if -1 the value is untouched.
 * @noreturn		
 */
stock Client_SetWeaponPlayerAmmoEx(client, weapon, primaryAmmo=-1, secondaryAmmo=-1)
{
	new offset_ammo = FindDataMapOffs(client, "m_iAmmo");

	if (primaryAmmo != -1) {
		new offset = offset_ammo + (Weapon_GetPrimaryAmmoType(weapon) * 4);
		SetEntData(client, offset, primaryAmmo, 4, true);
	}

	if (secondaryAmmo != -1) {
		new offset = offset_ammo + (Weapon_GetSecondaryAmmoType(weapon) * 4);
		SetEntData(client, offset, secondaryAmmo, 4, true);
	}
}

/**
 * Removes all weapons of a client.
 * You can specify a weapon it shouldn't remove and if to
 * clear the player's ammo for a weapon when it gets removed.
 *
 * @param client 		Client Index.
 * @param exclude		If not empty, this weapon won't be removed from the client.
 * @param clearAmmo		If true, the ammo the player carries for all removed weapons are set to 0 (primary and secondary).
 * @return				Number of removed weapons.
 */
stock Client_RemoveAllWeapons(client, const String:exclude[]="", bool:clearAmmo=false)
{
	new offset = Client_GetWeaponsOffset(client) - 4;
	
	new numWeaponsRemoved = 0;
	for (new i=0; i < MAX_WEAPONS; i++) {
		offset += 4;

		new weapon = GetEntDataEnt2(client, offset);
		
		if (!Weapon_IsValid(weapon)) {
			continue;
		}
		
		if (exclude[0] != '\0' && Entity_ClassNameMatches(weapon, exclude)) {
			Client_SetActiveWeapon(client, weapon);
			continue;
		}
		
		if (clearAmmo) {
			Client_SetWeaponPlayerAmmoEx(client, weapon, 0, 0);
		}

		if (RemovePlayerItem(client, weapon)) {
			Entity_Kill(weapon);
		}

		numWeaponsRemoved++;
	}
	
	return numWeaponsRemoved;
}