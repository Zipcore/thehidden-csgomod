#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <cstrike>
#include <hiddenmode>

#pragma semicolon 1

#define charsmax(%1) sizeof(%1)-1

// Cvar Handle
new Handle:pCvar_iTimeCountdown;
new Handle:pCvar_bFallDamage;
new Handle:pCvar_iHiddenHP;
new Handle:pCvar_bShowHiddenHP;
new Handle:pCvar_fHiddenSpeedMul;
new Handle:pCvar_fHiddenGravityMul;
new Handle:pCvar_fJumpPower;
new Handle:pCvar_fSkillCountdown;
new Handle:pCvar_bShowHiddenBlood;
new Handle:pCvar_bPainShock;


// Timer Handle
new Handle:Timer_Countdown;
new Handle:Timer_ShowHiddenHP;
new Handle:Timer_SkillCountdown;

// Global variables
new bool:bRoundStart = false;
new bool:bGameBegin = false;
new bool:bRoundEnd = false;

new gMaxPlayers;
new gHiddenIndex;
new gTimer;
new Float:gSkillCountdown;
new PlayerClass:gPlayerClass[MAXPLAYERS + 1];


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
	
	AddCommandListener(OnLookWeaponPressed, "+lookatweapon");
	
	pCvar_iTimeCountdown 	= CreateConVar("hm_cdtime", "10");
	pCvar_bFallDamage 		= CreateConVar("hm_falldamage", "0");
	pCvar_iHiddenHP 		= CreateConVar("hm_hiddenhp", "5000");
	pCvar_bShowHiddenHP 	= CreateConVar("hm_showhiddenhp", "1");
	pCvar_fHiddenSpeedMul 	= CreateConVar("hm_hiddenspeedmul", "2.0");
	pCvar_fHiddenGravityMul = CreateConVar("hm_hiddengravitymul", "0.5");
	pCvar_fJumpPower 		= CreateConVar("hm_jumppower", "1000.0");
	pCvar_fSkillCountdown 	= CreateConVar("hm_skillcd", "5.0");
	pCvar_bShowHiddenBlood 	= CreateConVar("hm_showhiddenblood", "1");
	// Notice: Require turn on Show Hidden Blood to turn off Pain Shock
	pCvar_bPainShock		= CreateConVar("hm_hiddenpainshock", "0");
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
	SDKHook(client, SDKHook_TraceAttack, OnTraceAttack); 
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
	
	// Unhook transmit to make player visible again
	SDKUnhook(gHiddenIndex, SDKHook_SetTransmit, Hook_SetTransmit);  
	
	// Reset player gravity
	SetEntityGravity(gHiddenIndex, 1.0);
	
	// Disable wall seeing
	MakeHumanGlow(false);
	
	// Reset everything is done. Finally reset The Hidden's index
	gHiddenIndex = 0;
	
	FuncBalanceTeam();
}

public Action:OnLookWeaponPressed(client, const String:command[], argc) {
	
	if (gHiddenIndex == 0 || client != gHiddenIndex) return Plugin_Continue;
	
	if (gSkillCountdown == 0.0) {
		DoSkill(client);
		gSkillCountdown = GetConVarFloat(pCvar_fSkillCountdown);
		Timer_SkillCountdown = CreateTimer(1.0, OnSkillCountdown, _, TIMER_REPEAT);
	}
	
	return Plugin_Handled;
}

public Action:OnTraceAttack(victim, &attacker, &inflictor, &Float:damage, &damageType, &ammoType, hitBox, hitGroup) {
	// Ignore all damage send to player if game is not begin
	if (!bRoundStart || !bGameBegin || bRoundEnd) return Plugin_Handled;
	
	// Game begin
	if (bRoundStart && bGameBegin) {
		if (attacker == 0) return Plugin_Continue;
		
		if (victim == gHiddenIndex && attacker > 0 && attacker <= MaxClients) {
			if(!GetConVarBool(pCvar_bShowHiddenBlood)) {
				int health = GetEntProp(victim, Prop_Send, "m_iHealth");
				health -= RoundFloat(damage);
				SetEntProp(victim, Prop_Data, "m_iHealth", health);
				
				return Plugin_Handled;
			}
			else return Plugin_Continue;
		}
		
		if (attacker == gHiddenIndex && victim > 0 && victim <= MaxClients)
			return Plugin_Continue;
		
		if (attacker < 0 || attacker > MaxClients) return Plugin_Handled;
	}
	return Plugin_Handled;
}

public Action:OnTakeDamage(victim, &attacker, &inflictor, &Float:damage, &damagetype) {
	// Ignore all damage send to player if game is not begin
	if (!bRoundStart || !bGameBegin || bRoundEnd) return Plugin_Handled;
	
	// Game begin
	if (bRoundStart && bGameBegin) {
		if (attacker == 0) return Plugin_Continue;
		
		if (victim == gHiddenIndex && attacker > 0 && attacker <= MaxClients) {
			if (GetConVarBool(pCvar_bShowHiddenBlood)) {
				if (!GetConVarBool(pCvar_bPainShock)) {
					int health = GetEntProp(victim, Prop_Send, "m_iHealth");
					health -= RoundFloat(damage);
					SetEntProp(victim, Prop_Data, "m_iHealth", health);
					
					return Plugin_Handled;
				}
				else return Plugin_Continue;
			}
		}
		
		if (attacker == gHiddenIndex && victim > 0 && victim <= MaxClients)
			return Plugin_Continue;
		
		if (attacker < 0 || attacker > MaxClients) return Plugin_Handled;
	}
	return Plugin_Handled;
}

public Action:Hook_SetTransmit(entity, client) 
{ 
    if (entity != client) 
        return Plugin_Handled;
     
    return Plugin_Continue; 
}  

public StartHiddenMode() {
	// First, set class Human or Hidden for all of players
	FuncSetPlayersClass();
	
	// Change players team by class
	FuncChangeAllHumanToCT();
	
	// Finally, create The Hidden
	FuncMakeHidden();
	
}

/** Timer function **/
public Action:TimerCountdown(Handle:timer) {
	if (gTimer <= 0) {
		gMaxPlayers = FuncCountPlayerConnected();
		gHiddenIndex = FuncGetRandomPlayerAlive(GetRandomInt(1, gMaxPlayers));
		
		bGameBegin = true;
		
		StartHiddenMode();
		//KillTimer(Timer_Countdown);
		return Plugin_Stop;
	}
	
	if(gTimer == 1)
		PrintHintTextToAll("The Hidden will be selected after 1 second");
	else
		PrintHintTextToAll("The Hidden will be selected after %d seconds", gTimer);
		
	gTimer--;
	
	return Plugin_Continue;
}

public Action:OnSkillCountdown(Handle:timer) {
	if (gSkillCountdown <= 0.0) {
		//KillTimer(Timer_SkillCountdown);
		return Plugin_Stop;
	}
	
	gSkillCountdown--;
	
	return Plugin_Continue;
}

public Action:ShowHiddenHP(Handle:timer) {
	if (!bRoundStart || bRoundEnd || gHiddenIndex == 0) {
		//KillTimer(Timer_ShowHiddenHP)
		return Plugin_Stop;
	}
	
	if(bGameBegin) {
		static String:name[64];
		GetClientName(gHiddenIndex, name, charsmax(name));
		if (gSkillCountdown != 0.0)
			PrintHintTextToAll("Hidden: %s\nHP: %d\nSkill: <font color='#ff0000'>Boost</font> (Press F) %d", name, GetClientHealth(gHiddenIndex), RoundFloat(gSkillCountdown));
		else
			PrintHintTextToAll("Hidden: %s\nHP: %d\nSkill: Boost (Press F)", name, GetClientHealth(gHiddenIndex));
	}
	
	return Plugin_Continue;
}

/**** Private function ****/
FuncMakeHidden() {
	// Change The Hidden to T
	FuncChangeHiddenToT();
	
	// Set abilities to The Hidden: HP, Speed, Gravity,....
	SetEntityHealth(gHiddenIndex, GetConVarInt(pCvar_iHiddenHP));
	
	new Float:speedMul = GetConVarFloat(pCvar_fHiddenSpeedMul);
	SetEntPropFloat(gHiddenIndex, Prop_Send, "m_flLaggedMovementValue", speedMul);
	
	new Float:gravityMul = GetConVarFloat(pCvar_fHiddenGravityMul);
	SetEntityGravity(gHiddenIndex, gravityMul);
	
	// Make The Hidden invisible by using hook
	SDKHook(gHiddenIndex, SDKHook_SetTransmit, Hook_SetTransmit); 
	
	// The Hidden can see through wall
	MakeHumanGlow(true);
	
	if (GetConVarBool(pCvar_bShowHiddenHP))
		Timer_ShowHiddenHP = CreateTimer(0.1, ShowHiddenHP, _, TIMER_REPEAT);
	
	// Strip all weapon except knife
	new knife = GetPlayerWeaponSlot(gHiddenIndex, 2);
	if (IsValidEntity(knife)) {
		new String:knife_name[32];
		GetEntityClassname(knife, knife_name, 32);
		Client_RemoveAllWeapons(gHiddenIndex, knife_name, true);
	}
}

DoSkill(int iClient) {
	// Get current player's velocity
	float fEyeAngles[3], fDirection[3];
	GetClientEyeAngles(iClient, fEyeAngles);
	GetAngleVectors(fEyeAngles, fDirection, NULL_VECTOR, NULL_VECTOR);
	
	float fPower = GetConVarFloat(pCvar_fJumpPower);
	ScaleVector(fDirection, fPower);
	
	TeleportEntity(iClient, NULL_VECTOR , NULL_VECTOR, fDirection);  
}

MakeHumanGlow(bool bForever) {
	SetEntPropFloat(gHiddenIndex, Prop_Send, "m_flDetectedByEnemySensorTime", bForever ? (GetGameTime() + 9999.0) : 0.0);
}

FuncChangePlayerTeam(int iClient, newTeam) {
	// Stop if change to CS_TEAM_NONE
	if (newTeam == CS_TEAM_NONE) return;
	
	new curTeam = GetClientTeam(iClient);
	
	// Stop f new team is the current team
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
	// Stop if no The Hidden selected
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

/***************************************************
	* Some of these stocks were extracted from  *
	* SMLib and were changed a bit in order to 	*
	* suitable for this plugin.					* 
	* 	    ___  _____  ____   ____         	*
	* 	   |       |   |    | |      |  /   	*
	* 	   |__     |   |    | |      |/     	*
	* 	      |    |   |    | |      |\     	*
	* 	   ___|    |   |____| |____  |  \  		*
	* 											*
 ***************************************************/ 
 
 /**
 * Gets the Classname of an entity.
 * This is like GetEdictClassname(), except it works for ALL
 * entities, not just edicts.
 *
 * @param entity			Entity index.
 * @param buffer			Return/Output buffer.
 * @param size				Max size of buffer.
 * @return					
 */
stock Entity_GetClassName(entity, String:buffer[], size)
{
	GetEntPropString(entity, Prop_Data, "m_iClassname", buffer, size);
	
	if (buffer[0] == '\0') {
		return false;
	}
	
	return true;
}

/**
 * Checks if an entity is a player or not.
 * No checks are done if the entity is actually valid,
 * the player is connected or ingame.
 *
 * @param entity			Entity index.
 * @return 				True if the entity is a player, false otherwise.
 */
stock bool:Entity_IsPlayer(entity)
{
	if (entity < 1 || entity > MaxClients) {
		return false;
	}
	
	return true;
}

/**
 * Checks if an entity matches a specific entity class.
 *
 * @param entity		Entity Index.
 * @param class			Classname String.
 * @return				True if the classname matches, false otherwise.
 */
stock bool:Entity_ClassNameMatches(entity, const String:className[], partialMatch=false)
{
	decl String:entity_className[64];
	Entity_GetClassName(entity, entity_className, sizeof(entity_className));

	if (partialMatch) {
		return (StrContains(entity_className, className) != -1);
	}
	
	return StrEqual(entity_className, className);
}

/**
 * Kills an entity on the next frame (delayed).
 * It is safe to use with entity loops.
 * If the entity is is player ForcePlayerSuicide() is called.
 *
 * @param kenny			Entity index.
 * @return 				True on success, false otherwise
 */
stock bool:Entity_Kill(entity)
{
	if (Entity_IsPlayer(entity)) {
		ForcePlayerSuicide(entity);
		return true;
	}
	
	return AcceptEntityInput(entity, "kill");
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
		offset = FindDataMapInfo(client, "m_hMyWeapons");
	}
	
	return offset;
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
	for (new i=0; i < 48; i++) {
		offset += 4;

		new weapon = GetEntDataEnt2(client, offset);
		
		if (!IsValidEdict(weapon)) {
			continue;
		}
		
		if (exclude[0] != '\0' && Entity_ClassNameMatches(weapon, exclude)) {
			SetEntPropEnt(client, Prop_Data, "m_hActiveWeapon", weapon);
			ChangeEdictState(client, FindDataMapInfo(client, "m_hActiveWeapon"));
			continue;
		}
		
		if (clearAmmo) {
			new offset_ammo = FindDataMapInfo(client, "m_iAmmo");
			
			new priOffset = offset_ammo + (GetEntProp(weapon, Prop_Data, "m_iPrimaryAmmoType") * 4);
			SetEntData(client, priOffset, 0, 4, true);
			
			new secondOffset = offset_ammo + (GetEntProp(weapon, Prop_Data, "m_iSecondaryAmmoType") * 4);
			SetEntData(client, secondOffset, 0, 4, true);
		}

		if (RemovePlayerItem(client, weapon)) {
			Entity_Kill(weapon);
		}

		numWeaponsRemoved++;
	}
	
	return numWeaponsRemoved;
}