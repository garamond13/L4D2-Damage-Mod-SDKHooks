#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#pragma semicolon 1
#pragma newdecls required

#define VERSION "3.1.0"

#define DEBUG 0

Handle weapon_trie;

public Plugin myinfo = {
	name = "L4D2 Damage Mod SDKHooks Simple",
	author = "Garamond, AtomicStryker",
	description = "Modify damage",
	version = VERSION,
	url = "https://github.com/garamond13/L4D2-Damage-Mod-SDKHooks"
};

public void OnPluginStart()
{
	//get config
	char config[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, config, sizeof(config), "configs/l4d2_damagemod.txt");
	if(!FileExists(config)) 
		SetFailState("l4d2_damagemod.txt cannot be read ... FATAL ERROR!");

	Handle key_values = CreateKeyValues("l4d2_damagemod");
	FileToKeyValues(key_values, config);
	weapon_trie = CreateTrie();
	
	//parse config
	if (KvGotoFirstSubKey(key_values)) {
		char weapon_class[32];
		char modifier[16];
		do {
			KvGetString(key_values, "weapon_class", weapon_class, sizeof(weapon_class));
			KvGetString(key_values, "modifier", modifier, sizeof(modifier), "1.0");
			SetTrieValue(weapon_trie, weapon_class, StringToFloat(modifier));
		}
		while (KvGotoNextKey(key_values));
	}
	else
		SetFailState("l4d2_damagemod.txt cannnot be parsed ... No subkeys found!");
	CloseHandle(key_values);
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_OnTakeDamage, on_take_damage);
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (!strcmp(classname, "infected") || !strcmp(classname, "witch"))
		SDKHook(entity, SDKHook_OnTakeDamage, on_take_damage);
}

public Action on_take_damage(int victim, int& attacker, int& inflictor, float& damage, int& damagetype)
{
	#if DEBUG
	PrintToChatAll("attacker %i, inflictor %i dealt %f damage to victim %i", attacker, inflictor, damage, victim);
	#endif

	char classname[32];

	//attack with equipped weapon
	if (attacker > 0 && attacker <= MaxClients && IsClientInGame(attacker) && attacker == inflictor)
		GetClientWeapon(inflictor, classname, sizeof(classname));
	
	//other source of damage
	else if (!GetEdictClassname(inflictor, classname, sizeof(classname)))
		return Plugin_Continue;

	#if DEBUG
	PrintToChatAll("configurable class name: %s", classname);
	#endif

	//get damage modifier
	float modifier;
	if (GetTrieValue(weapon_trie, classname, modifier)) {
		damage *= modifier;
		
		#if DEBUG
		PrintToChatAll("Damage modded by %f to %f", damage_mods[i], damage);
		#endif

		return Plugin_Changed;
	}
	
	return Plugin_Continue;
}
