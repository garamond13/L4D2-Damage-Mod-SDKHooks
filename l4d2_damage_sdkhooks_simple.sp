#include <sourcemod>
#include <sdkhooks>

#pragma semicolon 1
#pragma newdecls required

#define VERSION "3.0.5"

#define DEBUG 0

#define	MAX_WEAPONS 32
#define CLASS_LENGHT 32

Handle key_value_holder;
Handle weapon_index_trie;

float damage_mods[MAX_WEAPONS];

public Plugin myinfo = {
	name = "L4D2 Damage Mod SDKHooks Simple",
	author = "Garamond, AtomicStryker",
	description = "Modify damage",
	version = VERSION,
	url = "https://github.com/garamond13/L4D2-Damage-Mod-SDKHooks"
};

public void OnPluginStart()
{
	weapon_index_trie = CreateTrie();
	char config[PLATFORM_MAX_PATH];
	
	//get config
	BuildPath(Path_SM, config, sizeof(config), "configs/l4d2damagemod.cfg");
	if(!FileExists(config)) 
		SetFailState("l4d2damagemod.cfg cannot be read ... FATAL ERROR!");

	key_value_holder = CreateKeyValues("l4d2damagemod");
	FileToKeyValues(key_value_holder, config);
	KvRewind(key_value_holder);

	//parse config
	if (KvGotoFirstSubKey(key_value_holder)) {
		int i = 0;
		char buffer[CLASS_LENGHT];
		do {
			KvGetString(key_value_holder, "weapon_class", buffer, sizeof(buffer));
			SetTrieValue(weapon_index_trie, buffer, i);
			KvGetString(key_value_holder, "modifier", buffer, sizeof(buffer), "1.0");
			damage_mods[i] = StringToFloat(buffer);
			i++;
		}
		while (KvGotoNextKey(key_value_holder));
	}
	else
		SetFailState("l4d2damagemod.cfg cannnot be parsed ... No subkeys found!");
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

	char classname[CLASS_LENGHT];

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
	int i;
	if (GetTrieValue(weapon_index_trie, classname, i)) {
		damage *= damage_mods[i];
		
		#if DEBUG
		PrintToChatAll("Damage modded by %f to %f", damage_mods[i], damage);
		#endif

		return Plugin_Changed;
	}
	
	return Plugin_Continue;
}
