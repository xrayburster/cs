// *************************************************************************************//
// Плагин загружен с  www.neugomon.ru                                                   //
// Автор: Neygomon  [ https://neugomon.ru/members/1/ ]                                  //
// Официальная тема поддержки: https://neugomon.ru/threads/91/                          //
// При копировании материала ссылка на сайт www.neugomon.ru ОБЯЗАТЕЛЬНА!                //
// *************************************************************************************//

#include <amxmodx>
#include <fakemeta>
#include <hamsandwich>
#tryinclude <reapi>
#if !defined _reapi_included
	#include <VtcApi>
#endif
#if AMXX_VERSION_NUM < 183
	#include <colorchat>
#endif

#define DEFAULT_MIN_PLAYERS "0"
#define DEFAULT_AFTER_DEATH_INFO_TIMEOUT "5.0"

#define SORRY				// Разрешить команду /sorry для извинения игроков
#define MUTEMENU			// Поддержка команды /mute
#define GAG_ACCESS	ADMIN_BAN 	// Доступ к функциям гага
#define SORRYTIME 	60		// Как часто можно пользоваться командой /sorry. Время в секундах
#define PREFIX		"AMX Gag" 	// Префикс в чате
#define SUPERADMIN	ADMIN_RCON	// Админ с флагом L может гагать других админов с иммунитетом

new g_BlockTimes[] = 	// Время блокировки в минутах
{
	5,
	10,
	30,
	60,
	180,
	0 // навсегда
}

new g_AllowCommands[][] = // Разрешенные команды
{
	"/me",
	"/top15",
	"/rank",
	"/hp"
}

/* Словарь плагина */
#define MSG_SORRY_FLOOD 	"^1[^4%s^1] ^3Прекратите флудить! ^4Повторно извиниться можно через ^3%d сек"
#define MSG_SORRY_ADMIN 	"^1[^4%s^1] ^4Уважаемый ^3адмнистратор^4, игрок ^3%s ^4просит снять с него ^3GAG^4!"
#define MSG_CHAT_IS_BLOCKED 	"^1[^4%s^1] ^4Уважаемый ^3%s^4, Ваш чат ^3заблокирован^4!"
#define MSG_BLOCK_EXPIRED_TIME 	"^1[^4%s^1] ^4До разблокировки осталось ^1примерно ^3%d ^4мин."
#define MSG_BLOCK_EXPIRED 	"^1[^4%s^1] ^4Время блокировки ^3истекло^4. ^1Подождите обновления информации ..."
#define MSG_SAY_SORRY 		"^1[^4%s^1] ^4Чтобы извиниться, напишите в чат ^3/sorry^4. Возможно, разблокируют раньше :)"
#define MSG_CHAT_UNBLOCK_ALL 	"^1[^4%s^1] ^4Игроку ^3%s ^4был разблокирован чат администратором ^3%s"
#define MSG_CHAT_UNBLOCK_PL 	"^1[^4%s^1] ^4Уважаемый ^3%s^4, администратор ^3%s ^4снял с Вас блокировку чата"
#define MSG_CHAT_BLOCK_ALL 	"^1[^4%s^1] ^4Администратор ^3%s ^4заблокировал чат игроку ^3%s ^1%s"
#define MSG_CHAT_BLOCK_PL 	"^1[^4%s^1] ^4Уважаемый ^3%s^4, администратор ^3%s ^4заблокировал Вам чат ^1%s"
#define MSG_MUTE_ALL_PLAYERS 	"^1[^4%s^1] ^4Вы установили mute на ^3всех ^4игроков." 
#define MSG_UNMUTE_ALL_PLAYERS 	"^1[^4%s^1] ^4Вы сняли mute со ^3всех ^4игроков." 
#define MSG_UNMUTE_PLAYER 	"^1[^4%s^1] ^4Вы сняли ^3mute ^4с игрока ^3%s^4."
#define MSG_MUTE_PLAYER 	"^1[^4%s^1] ^4Вы установили ^3mute ^4на игрока ^3%s^4."
#define MSG_DEATH_INFO_TIMEOUT "^4Время для инфы истекло"
#define MSG_ADMIN_IS_SAYING "говорит админ!"

/* Технические данные */
#if defined MUTEMENU
	#include <fakemeta>
#endif

#define STORAGE 	"addons/amxmodx/data/amx_gag.dat"
#define MAX_ITEMS	1000
#if !defined MAX_PLAYERS
	const MAX_PLAYERS = 32;
#endif
#define	GetBit(%1,%2)	(%1 & (1 << (%2 & 31)))
#define	SetBit(%1,%2)	%1 |= (1 << (%2 & 31))
#define	ResetBit(%1,%2)	%1 &= ~(1 << (%2 & 31))

enum _:DATA
{
	IP[16],
	STEAMID[25],
	BLOCKTIME
};
enum MENUS
{
	GAG,
	MUTE
};
enum _:MENU_SETTINGS
{
	Menu,
	SelectTime,
	Pos
};

new death_info_timeout, min_players;

new g_bitBlockChats,g_bitPlayerIsDead, g_bitIsConnected, g_bitAdminVoice;
new g_iSyncId;
new g_aLoadedData[MAX_PLAYERS + 1][DATA];
new Trie:g_tAllowCmds, Array:g_aUsersBlocked;
new g_arrData[DATA];
new pl[MAX_PLAYERS], pnum;
new g_iMutePlayer[MAX_PLAYERS + 1][MAX_PLAYERS + 1];
new g_arrPlayers[MAX_PLAYERS + 1][MAX_PLAYERS];
new g_iMenuInfo[MAX_PLAYERS + 1][MENU_SETTINGS];

public plugin_init()
{
#define VERSION "2.0.0"
	register_plugin("Advanced Gag with DVC", VERSION, "neygomon/murfur");
	register_cvar("adv_gag", VERSION, FCVAR_SERVER | FCVAR_SPONLY);

	death_info_timeout = register_cvar("dvc_info_timeout", DEFAULT_AFTER_DEATH_INFO_TIMEOUT);
	min_players = register_cvar("dvc_min_players", DEFAULT_MIN_PLAYERS);

#if defined _reapi_included
	if(has_vtc())
	{
		register_clcmd("amx_gagmenu", "ClCmdGagMenu");
	}
	#if !defined MUTEMENU
	else	set_fail_state("Needed meta plugin VTC [а/]");
	#endif
#else
	register_clcmd("amx_gagmenu", "ClCmdGagMenu");
#endif
#if defined MUTEMENU
	register_clcmd("say /mute", "ClCmdMuteMenu");
	register_clcmd("say_team /mute", "ClCmdMuteMenu");
	
	register_forward(FM_Voice_SetClientListening, "SetClientListening_Pre", false);
#endif
#if defined SORRY
	register_clcmd("say /sorry", "SaySorry");
	register_clcmd("say_team /sorry", "SaySorry");
#endif
	register_clcmd("say", "SayChat");
	register_clcmd("say_team", "SayChat");

	register_srvcmd("adv_flush_gags", "SrvCmdFlush");
	
	register_menucmd(register_menuid("AdvGag Menu"), 1023, "MenuHandler");

	set_task(60.0, "CheckBlockedUsers", .flags = "b");

	register_clcmd("+adminvoice", "ClCmd_VoiceOn");
	register_clcmd("-adminvoice", "ClCmd_VoiceOff");

	RegisterHam(Ham_Spawn, "player", "fw_PlayerSpawn_Post", true);
	RegisterHam(Ham_Killed, "player", "fw_PlayerKilled_Post", true);

	g_iSyncId = CreateHudSyncObj();

}

public plugin_cfg()
{
	g_aUsersBlocked = ArrayCreate(DATA);
	
	new fp = fopen(STORAGE, "rt");
	if(fp)
	{
		new i, blocktime[15], buffer[128];
		new sys = get_systime();

		while(!feof(fp) && i < MAX_ITEMS)
		{
			fgets(fp, buffer, charsmax(buffer));
			trim(buffer);
			
			if(buffer[0] == EOS || buffer[0] == ';')
				continue;
			
			if(parse(buffer, 
					g_arrData[IP], charsmax(g_arrData[IP]), 
					g_arrData[STEAMID], charsmax(g_arrData[STEAMID]), 
					blocktime, charsmax(blocktime)
				)
			)
			{
				g_arrData[BLOCKTIME] = str_to_num(blocktime);
				if(!g_arrData[BLOCKTIME] || g_arrData[BLOCKTIME] > sys)
				{
					ArrayPushArray(g_aUsersBlocked, g_arrData);
					i++;
				}	
			}
		}
		fclose(fp);
	}

	g_tAllowCmds = TrieCreate();
	for(new i; i < sizeof g_AllowCommands; ++i)
		TrieSetCell(g_tAllowCmds, g_AllowCommands[i], i);
}

public ClCmd_VoiceOn(id)
{
	if(~get_user_flags(id) & ADMIN_USER ) {
		SetBit(g_bitAdminVoice, id);
		//client_cmd(id, "+voice" );
		//client_cmd(id, "+myvoice" );
		client_cmd(id, "+voicerecord");
		ClearSyncHud(0, g_iSyncId);
		set_hudmessage(102, 69, 0, -1.0, 0.8, 0, 0.0, 10.0, 0.0, 0.0, -1);
		ShowSyncHudMsg(0, g_iSyncId, MSG_ADMIN_IS_SAYING);
	}
	return 1;
}

public ClCmd_VoiceOff(id)
{
	//if(g_iMutePlayer[iReceiver][iSender]) {
	//VTC_MuteClient(id);
	//VTC_UnmuteClient(id);
	if(~get_user_flags(id) & ADMIN_USER) {
		ResetBit(g_bitAdminVoice, id);
		//client_cmd(id, "-voice");
		//client_cmd(id, "-myvoice");
		client_cmd(id, "-voicerecord");
		ClearSyncHud(0, g_iSyncId);
	}
	return 1;
}

public client_putinserver(id)
{
	if(!is_user_bot(id) && !is_user_hltv(id))
	{
		get_user_ip(id, g_aLoadedData[id][IP], charsmax(g_aLoadedData[][IP]), 1);
		get_user_authid(id, g_aLoadedData[id][STEAMID], charsmax(g_aLoadedData[][STEAMID]));
		
		if(IsUserBlocked(id, g_aLoadedData[id][IP], g_aLoadedData[id][STEAMID]) != -1)
		{
			VTC_MuteClient(id);
			SetBit(g_bitBlockChats, id);
		}
		else 	ResetBit(g_bitBlockChats, id);
		
		arrayset(g_iMutePlayer[id], 0, sizeof g_iMutePlayer[]);
	}
	SetBit(g_bitIsConnected, id);
}

public client_disconnected(id)
{
	//log_amx("client_disconnected(%d)",id);
	//ResetBit(g_bitPlayerIsDead,id);
	ResetBit(g_bitIsConnected, id);
}

public fw_PlayerSpawn_Post(id)
{
	//log_amx("fw_PlayerSpawn_Post(%d)",id);
	if(is_user_alive(id))
		ResetBit(g_bitPlayerIsDead,id);
}

public fw_PlayerKilled_Post(id)
{
	//log_amx("fw_PlayerKilled_Post(%d) delay = %f", id, get_pcvar_float(death_info_timeout));
	if(get_playersnum() < get_pcvar_num(min_players))
		return;
	set_task(get_pcvar_float(death_info_timeout), "onAfterDeathInfoTimeout", id);
}

public onAfterDeathInfoTimeout(id)
{
	//log_amx("onAfterDeathInfoTimeout(%d)",id);
	if(!is_user_alive(id)) {
		SetBit(g_bitPlayerIsDead, id);
		//TODO: VTC mute here?
		ChatColor(id, 0, MSG_DEATH_INFO_TIMEOUT);
	}
}

#if defined MUTEMENU
public SetClientListening_Pre(iReceiver, iSender)
{
	if(iSender == iReceiver)
		return FMRES_IGNORED;

	if(!GetBit(g_bitIsConnected,iReceiver) || !GetBit(g_bitIsConnected,iSender))
		return FMRES_IGNORED;

	if(g_iMutePlayer[iReceiver][iSender]) {
		engfunc(EngFunc_SetClientListening, iReceiver, iSender, false);
		forward_return(FMV_CELL, false);
		return FMRES_SUPERCEDE;
	}

	if(get_playersnum() >= get_pcvar_num(min_players)) {
		//
		if(!GetBit(g_bitPlayerIsDead,iSender)) {
			// alive to all: ALLOW
			engfunc(EngFunc_SetClientListening, iReceiver, iSender, true);
			forward_return(FMV_CELL, true);
		} else if(GetBit(g_bitPlayerIsDead,iReceiver)) {
			//dead to dead: ALLOW
			engfunc(EngFunc_SetClientListening, iReceiver, iSender, true);
			forward_return(FMV_CELL, true);
		} else {
			if(GetBit(g_bitAdminVoice, iSender)) {
				//dead by +adminvoice to alive: ALLOW
				//TODO: log such actions to prevent misusage!
				engfunc(EngFunc_SetClientListening, iReceiver, iSender, true);
				forward_return(FMV_CELL, true);
			} else {
				//dead to alive: DENY
				engfunc(EngFunc_SetClientListening, iReceiver, iSender, false);
				forward_return(FMV_CELL, false);
			}
		}
		return FMRES_SUPERCEDE;
	}

	//promiscous mode from all to all: ALLOW
	engfunc(EngFunc_SetClientListening, iReceiver, iSender, true);
	forward_return(FMV_CELL, true);
	return FMRES_SUPERCEDE;
}

#endif
public SaySorry(id)
{
	if(GetBit(g_bitBlockChats, id)) 
	{
		static iFloodTime[33], systime;
		if(iFloodTime[id] > (systime = get_systime()))
			ChatColor(id, 0, MSG_SORRY_FLOOD, PREFIX, iFloodTime[id] - systime);
		else
		{
			new sName[32]; 
			get_user_name(id, sName, charsmax(sName));

			get_players(pl, pnum, "ch");
			for(new i; i < pnum; ++i)
			{
				if(get_user_flags(pl[i]) & GAG_ACCESS)
					ChatColor(pl[i], 0, MSG_SORRY_ADMIN, PREFIX, sName);
			}

			iFloodTime[id] = systime + SORRYTIME;
		}
	}
	return PLUGIN_HANDLED;
}
public SayChat(id)
{
	if(!GetBit(g_bitBlockChats, id)) 
		return PLUGIN_CONTINUE;

	new sMessage[128]; 
	read_args(sMessage, charsmax(sMessage));
	remove_quotes(sMessage);

	if(TrieKeyExists(g_tAllowCmds, sMessage))
		return PLUGIN_CONTINUE;	
	else
	{
		new sName[32], ost; 
		get_user_name(id, sName, charsmax(sName));
		ChatColor(id, 0, MSG_CHAT_IS_BLOCKED, PREFIX, sName);
		
		if(g_aLoadedData[id][BLOCKTIME])
		{
			if((ost = g_aLoadedData[id][BLOCKTIME] - get_systime()) / 60 > 0)
				ChatColor(id, 0, MSG_BLOCK_EXPIRED_TIME, PREFIX, ost / 60);
			else 	ChatColor(id, 0, MSG_BLOCK_EXPIRED, PREFIX);
		}
		
		ChatColor(id, 0, MSG_SAY_SORRY, PREFIX);
	}
	return PLUGIN_HANDLED;
}

public SrvCmdFlush()
{
	ArrayClear(g_aUsersBlocked);
	log_amx("Advanced Gag [v %s] flush gags", VERSION);
	
	for(new id; id < sizeof g_aLoadedData; ++id)
	{
		arrayset(g_aLoadedData[id], 0, sizeof g_aLoadedData[]);
		ResetBit(g_bitBlockChats, id);
	}
}

public CheckBlockedUsers()
{
	if(ArraySize(g_aUsersBlocked))
	{
		get_players(pl, pnum);	
		
		for(new i, sys = get_systime(); i < pnum; ++i)
		{
			if(g_aLoadedData[pl[i]][BLOCKTIME] && sys > g_aLoadedData[pl[i]][BLOCKTIME])
				UserBlock(pl[i], 0);
		}
	}
}

public ClCmdGagMenu(id)
{
	if(get_user_flags(id) & GAG_ACCESS)
	{
		g_iMenuInfo[id][SelectTime] = 0;
		g_iMenuInfo[id][Pos] = 0;
		g_iMenuInfo[id][Menu] = any:GAG;
		
		ShowMenu(id, 0);
	}	
	
	return PLUGIN_HANDLED;
}

public ClCmdMuteMenu(id)
{
	g_iMenuInfo[id][Pos] = 0;
	g_iMenuInfo[id][Menu] = any:MUTE;

	ShowMenu(id, 0);
	return PLUGIN_HANDLED;
}

ShowMenu(id, iPos)
{
	new start, end;
	new iLen, sMenu[512];
	new iKeys = MENU_KEY_0|MENU_KEY_8;
	get_players(g_arrPlayers[id], pnum, "ch"); 
	
	switch(g_iMenuInfo[id][Menu])
	{
		case GAG:
		{
			start = iPos * 7; 
			end   = start + 7;
			iLen  = formatex(sMenu, charsmax(sMenu), "\d[\rAMX Gag\d] \yВыберите игрока\w\R%d/%d^n^n", iPos + 1, (pnum / 7 + ((pnum % 7) ? 1 : 0)));
		}
		case MUTE:
		{
			start = iPos * 6; 
			end   = start + 6;
			iKeys |= MENU_KEY_7;
			iLen  = formatex(sMenu, charsmax(sMenu), "\d[\rMute\d] \yВыберите игрока\w\R%d/%d^n^n", iPos + 1, (pnum / 6 + ((pnum % 6) ? 1 : 0)));
		}
	}
	
	if(start >= pnum)
		start = iPos = g_iMenuInfo[id][Pos] = 0;
	if(end > pnum)
		end = pnum;
	
	switch(g_iMenuInfo[id][Menu])
	{
		case GAG:
		{
		#if defined SUPERADMIN
			for(new i = start, bool:superadmin = bool:(get_user_flags(id) & SUPERADMIN), sName[32], plr, a; i < end; ++i)
		#else
			for(new i = start, sName[32], plr, a; i < end; ++i)
		#endif
			{	
				plr = g_arrPlayers[id][i];
				get_user_name(plr, sName, charsmax(sName));

				if(id == plr)
					iLen += formatex(sMenu[iLen], charsmax(sMenu) - iLen, "\r%d. \d%s \y[\rЭто Вы\y]^n", ++a, sName);
			#if defined SUPERADMIN		
				else if(!superadmin && get_user_flags(plr) & ADMIN_IMMUNITY)
			#else
				else if(get_user_flags(plr) & ADMIN_IMMUNITY)
			#endif
					iLen += formatex(sMenu[iLen], charsmax(sMenu) - iLen, "\r%d. \d%s \y[\rImmunity\y]^n", ++a, sName);	
				else
				{
					iKeys |= (1 << a++);
					
					if(GetBit(g_bitBlockChats, plr))
						iLen += formatex(sMenu[iLen], charsmax(sMenu) - iLen, "\r%d. \w%s \d[\yUngag\d]^n", a, sName);
					else	iLen += formatex(sMenu[iLen], charsmax(sMenu) - iLen, "\r%d. \w%s%s^n", a, sName, VTC_IsClientSpeaking(plr) ? " \d[\rSpeaking\d]" : "");
				}
			}
		
			if(!g_BlockTimes[g_iMenuInfo[id][SelectTime]]) 
				iLen += formatex(sMenu[iLen], charsmax(sMenu) - iLen, "^n\r8. \wGag\d'\wнуть \rнавсегда^n^n");
			else 	iLen += formatex(sMenu[iLen], charsmax(sMenu) - iLen, "^n\r8. \wGag\d'\wнуть на \y%d \wмин^n^n", g_BlockTimes[g_iMenuInfo[id][SelectTime]]);
		}
		case MUTE:
		{
			for(new i = start, sName[32], plr, a; i < end; ++i)
			{	
				plr = g_arrPlayers[id][i];
				get_user_name(plr, sName, charsmax(sName));

				if(id == plr)
					iLen += formatex(sMenu[iLen], charsmax(sMenu) - iLen, "\r%d. \d%s \y[\rЭто Вы\y]^n", ++a, sName);
				else
				{
					iKeys |= (1 << a++);
					iLen += formatex(sMenu[iLen], charsmax(sMenu) - iLen, "\r%d. \w%s%s^n", a, sName, g_iMutePlayer[id][plr] ? " \d[\yMuted\d]" : "");
				}
			}
		
			iLen += formatex(sMenu[iLen], charsmax(sMenu) - iLen, "^n\r7. \wЗаглушить \rвсех^n\r8. \wСнять Mute со \rвсех^n^n");
		}
	}

	if(end != pnum)
	{
		formatex(sMenu[iLen], charsmax(sMenu) - iLen, "\r9. \yДалее^n\r0. \r%s", iPos ? "Назад" : "Выход");
		iKeys |= MENU_KEY_9;
	}
	else formatex(sMenu[iLen], charsmax(sMenu) - iLen, "\r0. \r%s", iPos ? "Назад" : "Выход");

	show_menu(id, iKeys, sMenu, -1, "AdvGag Menu");
	return PLUGIN_HANDLED;
}

public MenuHandler(id, iKey)
{
	switch(iKey)
	{
		case 6:
		{
			switch(g_iMenuInfo[id][Menu])
			{
				case GAG:
				{
					GagHandler(id, g_arrPlayers[id][g_iMenuInfo[id][Pos] * 7 + iKey], g_BlockTimes[g_iMenuInfo[id][SelectTime]]);
				}
				case MUTE:
				{
					arrayset(g_iMutePlayer[id], 1, sizeof g_iMutePlayer[]);
					ChatColor(id, 0, MSG_MUTE_ALL_PLAYERS, PREFIX);
				}
			}
		}
		case 7:
		{
			switch(g_iMenuInfo[id][Menu])
			{
				case GAG:
				{
					if(++g_iMenuInfo[id][SelectTime] > charsmax(g_BlockTimes)) 
						g_iMenuInfo[id][SelectTime] = 0;
					
					ShowMenu(id, g_iMenuInfo[id][Pos]);
				}
				case MUTE:
				{
					arrayset(g_iMutePlayer[id], 0, sizeof g_iMutePlayer[]);
					ChatColor(id, 0, MSG_UNMUTE_ALL_PLAYERS, PREFIX);
				}
			}
		}
		case 8: ShowMenu(id, ++g_iMenuInfo[id][Pos]);
		case 9: 
		{
			if(g_iMenuInfo[id][Pos]) 
				ShowMenu(id, --g_iMenuInfo[id][Pos]);
		}
		default:
		{
			switch(g_iMenuInfo[id][Menu])
			{
				case GAG:
				{
					GagHandler(id, g_arrPlayers[id][g_iMenuInfo[id][Pos] * 7 + iKey], g_BlockTimes[g_iMenuInfo[id][SelectTime]]);
				}
				case MUTE:
				{
					MuteHandler(id, g_arrPlayers[id][g_iMenuInfo[id][Pos] * 6 + iKey]);
				}
			}
		}
	}
	return PLUGIN_HANDLED;
}

GagHandler(id, player, blocktime)
{
	if(!is_user_connected(player))
	{
		return;
	}
	
	new sNameAdmin[32], sNamePlayer[32];
	get_user_name(id, sNameAdmin, charsmax(sNameAdmin));
	get_user_name(player, sNamePlayer, charsmax(sNamePlayer));

	if(GetBit(g_bitBlockChats, player))
	{
		UserBlock(player, 0); 

		ChatColor(0, player, MSG_CHAT_UNBLOCK_ALL, PREFIX, sNamePlayer, sNameAdmin);
		ChatColor(player, 0, MSG_CHAT_UNBLOCK_PL, PREFIX, sNamePlayer, sNameAdmin);
	}
	else
	{
		UserBlock(player, 1, blocktime);

		new blocktimeinfo[32];
		if(!blocktime)
			formatex(blocktimeinfo, charsmax(blocktimeinfo), "навсегда");
		else	formatex(blocktimeinfo, charsmax(blocktimeinfo), "на %d минут", blocktime);

		ChatColor(0, player, MSG_CHAT_BLOCK_ALL, PREFIX, sNameAdmin, sNamePlayer, blocktimeinfo);
		ChatColor(player, 0, MSG_CHAT_BLOCK_PL, PREFIX, sNamePlayer, sNameAdmin, blocktimeinfo);
	}
	ShowMenu(id, g_iMenuInfo[id][Pos]);
}

MuteHandler(id, player)
{
	if(!is_user_connected(player))
	{
		return;
	}
	
	new sNamePlayer[32];
	get_user_name(player, sNamePlayer, charsmax(sNamePlayer));

	g_iMutePlayer[id][player] = !g_iMutePlayer[id][player];
	ChatColor(id, 0, g_iMutePlayer[id][player] ? MSG_MUTE_PLAYER : MSG_UNMUTE_PLAYER, PREFIX, sNamePlayer);
	
	ShowMenu(id, g_iMenuInfo[id][Pos]);
}

UserBlock(id, block, btime = 0)
{
	if(block)
	{
		g_aLoadedData[id][BLOCKTIME] = !btime ? 0 : get_systime() + btime * 60;

		ArrayPushArray(g_aUsersBlocked, g_aLoadedData[id]);
		SetBit(g_bitBlockChats, id);
		VTC_MuteClient(id);
		client_cmd(id, "-voicerecord"); 	// типа отключаем войс, ога
	}
	else	IsUserBlocked(id, g_aLoadedData[id][IP], g_aLoadedData[id][STEAMID], 1);
}

IsUserBlocked(id, const Ip[], const SteamID[], UnBlock = 0)
{
	new i, aSize = ArraySize(g_aUsersBlocked), sys = get_systime();
	
	if(UnBlock)
	{
		for(i = 0; i < aSize; ++i)
		{
			ArrayGetArray(g_aUsersBlocked, i, g_arrData);
			if(strcmp(g_arrData[IP], Ip) == 0 || strcmp(g_arrData[STEAMID], SteamID) == 0)
			{
				ArrayDeleteItem(g_aUsersBlocked, i);
				ResetBit(g_bitBlockChats, id);
				VTC_UnmuteClient(id);
				break;
			}
		}
	}
	else
	{
		for(i = 0; i < aSize; ++i)
		{
			ArrayGetArray(g_aUsersBlocked, i, g_arrData);
			if(strcmp(g_arrData[IP], Ip) == 0 || strcmp(g_arrData[STEAMID], SteamID) == 0)
			{
				if(!g_arrData[BLOCKTIME] || g_arrData[BLOCKTIME] > sys)
				{
					g_aLoadedData[id][BLOCKTIME] = g_arrData[BLOCKTIME];
					return i;
				}
				else	ArrayDeleteItem(g_aUsersBlocked, i);

				break;
			}
		}
	}
	return -1;
}

public plugin_end()
{
	if(file_exists(STORAGE)) 
		unlink(STORAGE);
	
	new aSize, fp = fopen(STORAGE, "w+");
	if(!fprintf(fp, "; File generated by Advanced Gag [v %s][neygomon | https://neugomon.ru/threads/91/]^n^n", VERSION))
	{
		new err[128]; formatex(err, charsmax(err), "Plugin not write file %s! Users not saved!", STORAGE);
		set_fail_state(err);
	}

	aSize = ArraySize(g_aUsersBlocked);
	for(new i; i < aSize; ++i)
	{
		ArrayGetArray(g_aUsersBlocked, i, g_arrData);
		fprintf(fp, "^"%s^" ^"%s^" ^"%d^"^n", g_arrData[IP], g_arrData[STEAMID], g_arrData[BLOCKTIME]);
	}
	
	if(aSize)
	{
		log_amx("Successfully saved %d items in %s :)", aSize, STORAGE);
	}
	
	fclose(fp);
	ArrayDestroy(g_aUsersBlocked);
	TrieDestroy(g_tAllowCmds);
}

stock ChatColor(id, id2, const szMessage[], any:...)
{
	new szMsg[190]; 
	vformat(szMsg, charsmax(szMsg), szMessage, 4);
	
	if(id && id != id2)
	{
		client_print_color(id, print_team_default, szMsg);
	}
	else
	{
		get_players(pl, pnum, "c");
		for(new i; i < pnum; ++i)
		{
			if(pl[i] != id2)
			{
				client_print_color(pl[i], print_team_default, szMsg);
			}
		}
	}
}
