implement Allow;
include "sys.m";
	sys: Sys;
include "draw.m";
include "../gamesrv.m";
	gamesrv: Gamesrv;
	Attributes, Range, Object, Game, Player, rand: import gamesrv;
include "allow.m";

Action: adt {
	tag:		int;
	player:	ref Player;
	action:	string;
};

actions: list of Action;
game: ref Game;

init(g: ref Game, srvmod: Gamesrv)
{
	sys = load Sys Sys->PATH;
	(game, gamesrv) = (g, srvmod);
}

add(tag: int, player: ref Player, action: string)
{
#	sys->print("allow: add %d, player %ux, action: %s\n", tag, player, action);
	actions = (tag, player, action) :: actions;
}

del(tag: int, player: ref Player)
{
#	sys->print("allow: del %d\n", tag);
	na: list of Action;
	for (a := actions; a != nil; a = tl a) {
		action := hd a;
		if (action.tag == tag && (player == nil || action.player == player))
			continue;
		na = action :: na;
	}
	actions = na;
}

action(player: ref Player, cmd: string): (string, int, list of string)
{
	for (al := actions; al != nil; al = tl al) {
		a := hd al;
		if (a.player == nil || a.player == player) {
			(e, v) := match(player, a.action, cmd);
			if (e != nil || v != nil)
				return (e, a.tag, v);
		}
	}
	return ("you can't do that", -1, nil);
}

match(player: ref Player, pat, action: string): (string, list of string)
{
#	sys->print("allow: matching pat: '%s' against action '%s'\n", pat, action);
	toks: list of string;
	na := len action;
	if (na > 0 && action[na - 1] == '\n')
		na--;

	(nil, ptoks) := 
	(i, j) := (0, 0);
	for (;;) {
		for (; i < len pat; i++)
			if (pat[i] != ' ')
				break;
		for (; j < na; j++)
			if (action[j] != ' ')
				break;
		for (i1 := i; i1 < len pat; i1++)
			if (pat[i1] == ' ')
				break;
		for (j1 := j; j1 < na; j1++)
			if (action[j1] == ' ')
				break;
		if (i == i1) {
			if (j == j1)
				break;
			return (nil, nil);
		}
		if (j == j1) {
			if (pat == "&")
				break;
			return (nil, nil);
		}
		pw := pat[i : i1];
		w := action[j : j1];
		case pw[0] {
		'*' =>
			toks = w :: toks;
			break;
		'&' =>
			toks = w :: toks;
			pat = "&";
			i1 = 0;
		'%' =>
			(ok, nw) := checkformat(player, pw[1], w);
			if (!ok)
				return ("invalid field value", nil);
			toks = nw :: toks;
		* =>
			if (w != pw)
				return (nil, nil);
			toks = w :: toks;
		}
		(i, j) = (i1, j1);
	}
	return (nil, revs(toks));
}

revs(l: list of string): list of string
{
	m: list of string;
	for (; l != nil; l = tl l)
		m = hd l :: m;
	return m;
}

checkformat(p: ref Player, fmt: int, w: string): (int, string)
{
	case fmt {
	'o' =>
		# object id
		if (isnum(w) && (o := p.obj(int w)) != nil)
			return (1, string o.id);
	'd' =>
		# integer
		if (isnum(w))
			return (1, w);
	'p' =>
		# player id
		if (isnum(w) && (player := game.player(int w)) != nil)
			return (1, w);
	}
	return (0, nil);
}

isnum(w: string): int
{
	# XXX lazy for the time being...
	if (w != nil && ((w[0] >= '0' && w[0] <= '9') || w[0] == '-'))
		return 1;
	return 0;
}
