#pragma newdecls required
#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define PLUGIN_VERSION "1.0.0"

#define DEBUG 0
#define TEST_DEBUG 0
#define TEST_DEBUG_LOG 0

#define	MAX_MODDED_WEAPONS 64
#define	CLASS_STRINGLENGHT 32

#define	L4D2_TEAM_INFECTED 3

#define DAMAGE_MOD_NONE 1.0

#define ENTPROP_MELEE_STRING "m_strMapSetScriptName"
#define CLASSNAME_INFECTED "infected"
#define CLASSNAME_MELEE_WPN "weapon_melee"
#define CLASSNAME_WITCH "witch"

static char damageModConfigFile[PLATFORM_MAX_PATH];
static Handle keyValueHolder;
static Handle weaponIndexTrie;

enum weaponModData
{
	damageModifierFriendly,
	damageModifierEnemy
}

static float damageModArray[MAX_MODDED_WEAPONS][weaponModData];

public Plugin myinfo =
{
	name = "L4D2 Damage Mod SDKHooks Advanced",
	author = "Garamond, AtomicStryker",
	description = "Modify damage",
	version = PLUGIN_VERSION,
	url = "https://github.com/garamond13/L4D2-Damage-Mod-SDKHooks"
};

public void OnPluginStart()
{
	//l4d2 check
	char game_name[CLASS_STRINGLENGHT];
	GetGameFolderName(game_name, sizeof(game_name));
	if (StrContains(game_name, "left4dead2", false) < 0)
		SetFailState("Plugin supports L4D2 only.");

	CreateConVar("l4d2_damage_mod_version", PLUGIN_VERSION, "L4D2 Damage Mod Version", FCVAR_REPLICATED | FCVAR_DONTRECORD);
	RegAdminCmd("sm_reloaddamagemod", cmd_ReloadData, ADMFLAG_CHEATS, "Reload the setting file for live changes");
}

public void OnClientPostAdminCheck(int client)
{
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (StrEqual(classname, CLASSNAME_INFECTED, false) || StrEqual(classname, CLASSNAME_WITCH, false))
		SDKHook(entity, SDKHook_OnTakeDamage, OnTakeDamage);
}

public void OnMapStart()
{
	ReloadKeyValues();
}

public Action cmd_ReloadData(int client, int args)
{
	ReloadKeyValues();
	ReplyToCommand(client, "L4D2 Damage Mod config file re-loaded");
	return Plugin_Handled;
}

static void ReloadKeyValues()
{
	if (weaponIndexTrie != INVALID_HANDLE)
		CloseHandle(weaponIndexTrie);
	weaponIndexTrie = CreateTrie();

	BuildPath(Path_SM, damageModConfigFile, sizeof(damageModConfigFile), "configs/l4d2damagemod.cfg");
	if(!FileExists(damageModConfigFile)) 
		SetFailState("l4d2damagemod.cfg cannot be read ... FATAL ERROR!");
	
	if (keyValueHolder != INVALID_HANDLE)
		CloseHandle(keyValueHolder);
	keyValueHolder = CreateKeyValues("l4d2damagemod");
	FileToKeyValues(keyValueHolder, damageModConfigFile);
	KvRewind(keyValueHolder);
	
	if (KvGotoFirstSubKey(keyValueHolder)) {
		int i = 0;
		char buffer[CLASS_STRINGLENGHT];
		float value;
		do {
			KvGetString(keyValueHolder, "weapon_class", buffer, sizeof(buffer), "1.0");
			SetTrieValue(weaponIndexTrie, buffer, i);
			
			#if DEBUG
			DebugPrintToAll("Dataset %i, weapon_class %s read and saved", i, buffer);
			#endif

			KvGetString(keyValueHolder, "modifier_friendly", buffer, sizeof(buffer), "1.0");
			value = StringToFloat(buffer);
			damageModArray[i][damageModifierFriendly] = value;
			
			#if DEBUG
			DebugPrintToAll("Dataset %i, modifier_friendly %f read and saved", i, value);
			#endif

			KvGetString(keyValueHolder, "modifier_enemy", buffer, sizeof(buffer), "1.0");
			value = StringToFloat(buffer);
			damageModArray[i][damageModifierEnemy] = value;
			
			#if DEBUG
			DebugPrintToAll("Dataset %i, modifier_enemy %f read and saved", i, value);
			#endif

			i++;
		}
		while (KvGotoNextKey(keyValueHolder));
	}
	else
		SetFailState("l4d2damagemod.cfg cannnot be parsed ... No subkeys found!");
}

public Action OnTakeDamage(int victim, int& attacker, int& inflictor, float& damage, int& damagetype)
{
	#if DEBUG
	DebugPrintToAll("attacker %i, inflictor %i dealt [%f] damage to victim %i", attacker, inflictor, damage, victim);
	#endif

	if (!inflictor || !attacker || !victim || !IsValidEdict(victim) || !IsValidEdict(inflictor))
		return Plugin_Continue;
	
	char classname[CLASS_STRINGLENGHT];

	// case: player entity attacks
	bool bHumanAttacker = attacker > 0 && attacker <= MaxClients && IsClientInGame(attacker);
	
	if (bHumanAttacker) {
		
		// case: attack with an equipped weapon (guns, claws)
		if (attacker == inflictor)
			GetClientWeapon(inflictor, classname, sizeof(classname));
			
		// tank special case?
		else
			GetEdictClassname(inflictor, classname, sizeof(classname));
	}
	
	// case: other entity inflicts damage (eg throwable, ability)
	else
		GetEdictClassname(inflictor, classname, sizeof(classname));
	
	// subcase melee weapons
	if (StrEqual(classname, CLASSNAME_MELEE_WPN))
		GetEntPropString(GetPlayerWeaponSlot(attacker, 1), Prop_Data, ENTPROP_MELEE_STRING, classname, sizeof(classname));
	
	#if DEBUG
	DebugPrintToAll("configurable class name: %s", classname);
	#endif

	int i;
	if (!GetTrieValue(weaponIndexTrie, classname, i))
		return Plugin_Continue;
	
	int teamattacker;
	int teamvictim;
	float damagemod;
	
	bool bHumanVictim = victim <= MaxClients && IsClientInGame(victim);
	
	// case: attacker human player
	if (bHumanAttacker) {
		teamattacker = GetClientTeam(attacker);
		
		// case: victim also human player
		if (bHumanVictim) {
			teamvictim = GetClientTeam(victim);
			if (teamattacker == teamvictim)
				damagemod = damageModArray[i][damageModifierFriendly];
			else
				damagemod = damageModArray[i][damageModifierEnemy];
		}

		// case: victim is witch or common or some other entity, we'll assume an adversary
		else {
			if (teamattacker == L4D2_TEAM_INFECTED)
				damagemod = damageModArray[i][damageModifierFriendly];
			else
				damagemod = damageModArray[i][damageModifierEnemy];
		}
	}

	// case: attacker witch or common, victim human player
	else if (bHumanVictim) {
		teamvictim = GetClientTeam(victim);
		if (teamvictim == L4D2_TEAM_INFECTED)
			damagemod = damageModArray[i][damageModifierFriendly];
		else
			damagemod = damageModArray[i][damageModifierEnemy];
	}

	// entity-to-entity damage is unhandled
	else
		return Plugin_Continue;
	
	if (FloatCompare(damagemod, DAMAGE_MOD_NONE) != 0) {
		damage *= damagemod;
		
		#if DEBUG
		DebugPrintToAll("Damage modded by [%f] to [%f]", damagemod, damage);
		#endif
	}
	
	return Plugin_Changed;
}

#if DEBUG
stock void DebugPrintToAll(const char[] format, any ...)
{
	#if TEST_DEBUG	|| TEST_DEBUG_LOG
	decl String:buffer[192];
	
	VFormat(buffer, sizeof(buffer), format, 2);
	
	#if TEST_DEBUG
	PrintToChatAll("[DAMAGE] %s", buffer);
	PrintToConsole(0, "[DAMAGE] %s", buffer);
	#endif
	
	LogMessage("%s", buffer);
	#else
	//suppress "format" never used warning
	if(format[0])
		return;
	else
		return;
	#endif
}
#endif
