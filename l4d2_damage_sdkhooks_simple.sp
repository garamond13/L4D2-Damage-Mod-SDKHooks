#pragma newdecls required
#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define PLUGIN_VERSION "1.0.3"

#define DEBUG 0
#define TEST_DEBUG 0
#define TEST_DEBUG_LOG 0

#define	MAX_MODDED_WEAPONS 64
#define	CLASS_STRINGLENGHT 32

#define ENTPROP_MELEE_STRING "m_strMapSetScriptName"
#define CLASSNAME_INFECTED "infected"
#define CLASSNAME_MELEE_WPN "weapon_melee"
#define CLASSNAME_WITCH "witch"

static Handle keyValueHolder;
static Handle weaponIndexTrie;

static float damageModArray[MAX_MODDED_WEAPONS];

public Plugin myinfo =
{
	name = "L4D2 Damage Mod SDKHooks Simple",
	author = "Garamond, AtomicStryker",
	description = "Modify damage",
	version = PLUGIN_VERSION,
	url = "https://github.com/garamond13/L4D2-Damage-Mod-SDKHooks"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) 
{	
	if(GetEngineVersion() != Engine_Left4Dead2) {
		strcopy(error, err_max, "Plugin only supports Left 4 Dead 2.");
		return APLRes_SilentFailure;
	}
	return APLRes_Success; 
}

public void OnPluginStart()
{
	CreateConVar("l4d2_damage_mod_version", PLUGIN_VERSION, "L4D2 Damage Mod Version", FCVAR_REPLICATED | FCVAR_DONTRECORD);
	RegAdminCmd("sm_reloaddamagemod", cmd_ReloadData, ADMFLAG_CHEATS, "Reload the setting file for live changes");
}

public void OnClientPutInServer(int client)
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
    char damageModConfigFile[PLATFORM_MAX_PATH];
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

			KvGetString(keyValueHolder, "modifier", buffer, sizeof(buffer), "1.0");
			value = StringToFloat(buffer);
			damageModArray[i] = value;
			
			#if DEBUG
			DebugPrintToAll("Dataset %i, modifier %f read and saved", i, value);
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

	//get trie value && attacker human player || attacker witch or common, victim human player
	if (GetTrieValue(weaponIndexTrie, classname, i) && (bHumanAttacker || (victim <= MaxClients && IsClientInGame(victim))))
		damage *= damageModArray[i];

	//entity-to-entity damage is unhandled, or no trie value
	else
		return Plugin_Continue;

	#if DEBUG
	DebugPrintToAll("Damage modded by [%f] to [%f]", damageModArray[i], damage);
	#endif
	
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
