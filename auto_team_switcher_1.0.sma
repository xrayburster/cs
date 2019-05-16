#include <amxmodx>
#include <amxmisc>
#include <cstrike>
#include <reapi>

#define PLUGIN "Auto Team Switcher"
#define VERSION "1.0"
#define AUTHOR "nikhilgupta345"

#pragma semicolon 1

new roundnumber = 0;
new Atsround;

new score_T,score_CT;

public plugin_init() 
{
	register_plugin(PLUGIN, VERSION, AUTHOR);
	
	register_clcmd( "say /roundnumber", "sayRound" );
	register_concmd( "amx_roundrestart", "restartnumber", ADMIN_KICK );
	
	register_logevent( "roundend", 2, "1=Round_End" );
	register_event( "TextMsg","restart","a","2&#Game_C", "2&#Game_W" ); // Event for "Game Commencing" TextMsg and "Game Will Restart in X Seconds" TextMsg

	register_event("TeamScore","get_teamscore","a");

	Atsround = register_cvar( "amx_atsrounds", "15" );
	
}

public get_teamscore()
{
	new szTeam[2];
	read_data(1, szTeam, 1);
	if( szTeam[0] == 'T' ) {
		score_T = read_data(2);
	} else {
		score_CT = read_data(2);
	}
	return PLUGIN_CONTINUE;
}

public sayRound( id )
{
	client_print( id, print_chat, "The current round is %i.", roundnumber );
	return PLUGIN_HANDLED;
}

public roundend()
{
	roundnumber++;
	
	if( roundnumber >= get_pcvar_num( Atsround ) )
	{
		new players[32], num;
		get_players( players, num );
		for( new i; i < num; i++ )
			add_delay( players[i] ); // Prevent Server Crash with a lot of people.
		//swap teamscores
		rg_update_teamscores(score_T,score_CT,false);
	}
}


public restartnumber( id, level, cid )
{
	if( !cmd_access( id, level, cid, 1 ) )
		return PLUGIN_HANDLED;
	
	roundnumber = 0;
	return PLUGIN_HANDLED;
}

public restart( id )
{
	roundnumber = 0;
	return PLUGIN_HANDLED;
}

public changeTeam( id )
{
	switch( cs_get_user_team( id ) )
	{
		case CS_TEAM_CT: cs_set_user_team( id, CS_TEAM_T );
		
		case CS_TEAM_T: cs_set_user_team( id, CS_TEAM_CT );
	}

	roundnumber = 0;
}

add_delay( id )
{
	switch( id )
	{
		case 1..7: set_task( 0.1, "changeTeam", id );
		case 8..15: set_task( 0.2, "changeTeam", id );
		case 16..23: set_task( 0.3, "changeTeam", id );
		case 24..32: set_task( 0.4, "changeTeam", id );
	}
}
