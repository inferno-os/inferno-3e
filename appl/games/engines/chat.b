implement Gamemodule;

include "sys.m";
	sys: Sys;
include "draw.m";
include "../gamesrv.m";
	gamesrv: Gamesrv;
	Attributes, Range, Object, Game, Player: import gamesrv;

game: ref Game;

clienttype(): string
{
	return "chat";
}

init(g: ref Game, srvmod: Gamesrv): string
{
	sys = load Sys Sys->PATH;
	game = g;
	gamesrv = srvmod;
	return nil;
}

join(nil: ref Player): string
{
	return nil;
}

leave(nil: ref Player)
{
}

Eusage: con "bad command usage";

command(player: ref Player, cmd: string): string
{
	e := ref Sys->Exception;
	if (sys->rescue("parse:*", e) == Sys->EXCEPTION) {
		sys->rescued(Sys->ONCE, nil);
		return e.name[6:];
	}
	(n, toks) := sys->tokenize(cmd, " \n");
	assert(n > 0, "unknown command");
	case hd toks {
	"say" =>
		# say something
		assert(n == 2, Eusage);
		game.action("say " + string player.id + " " + hd tl toks, nil, nil, ~0);
	* =>
		assert(0, "bad command");
	}
	return nil;
}

assert(b: int, err: string)
{
	if (b == 0)
		sys->raise("parse:" + err);
}
