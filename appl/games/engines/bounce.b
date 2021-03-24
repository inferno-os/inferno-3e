implement Gamemodule;

include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;
	Point, Rect: import draw;
include "math.m";
	math: Math;
include "../gamesrv.m";
	gamesrv: Gamesrv;
	Attributes, Range, Object, Game, Player: import gamesrv;

game: ref Game;

W, H: con 500;
INSET: con 20;
D: con 30;
BATLEN: con 100.0;
GOALSIZE: con 0.1;

MAXPLAYERS: con 32;
nplayers := 0;

Line: adt {
	p1, p2: Point;
	seg: fn(l: self Line, s1, s2: real): Line;
};

batpos: array of Line;
borderpos: array of Line;
colours := array[4] of {"blue", "orange", "yellow", "white"};

batids := array[4] of int;
scores := array[4] of int;
order := array[MAXPLAYERS] of {* => -1};
bats := array[MAXPLAYERS] of ref Object;
started := 0;

arena: ref Object;

clienttype(): string
{
	return "bounce";
}

init(g: ref Game, srvmod: Gamesrv): string
{
	sys = load Sys Sys->PATH;
	math = load Math Math->PATH;
	draw = load Draw Draw->PATH;
	game = g;
	gamesrv = srvmod;

	r := Rect((0, 0), (W, H));
	walls := sides(r.inset(INSET));
	addlines(segs(walls, 0.0, 0.5 - GOALSIZE), nil);
	addlines(segs(walls, 0.5 + GOALSIZE, 1.0), nil);

	batpos = l2a(segs(sides(r.inset(INSET + 50)), 0.1, 0.9));
	borderpos = l2a(sides(r.inset(-1)));

	arena = game.newobject(nil, ~0, "arena");
	arena.setattr("arenasize", string W + " " + string H, ~0);

	return nil;
}


addline(lp: (Point, Point), attrs: list of (string, string)): ref Object
{
	(p1, p2) := lp;
	l := game.newobject(nil, ~0, "line");
	l.setattr("coords", p2s(p1) + " " + p2s(p2), ~0);
	l.setattr("id", string l.id, ~0);
	for (; attrs != nil; attrs = tl attrs) {
		(attr, val) := hd attrs;
		l.setattr(attr, val, ~0);
	}
	return l;
}


join(p: ref Player): string
{
	if (!started && nplayers < len batpos) {
		bat := addline(batpos[nplayers], nil);
		n := nplayers++;
		bat.setattr("pos", "10 " + string (10.0 + BATLEN), ~0);
		bat.setattr("owner", string p.id, ~0);
		bats[p.id] = bat;
		batids[n] = bat.id;
		addline(borderpos[n], ("owner", string p.id) :: nil);
		arena.setattr("player" + string n, string p.id + " " + colours[n], ~0);
		order[p.id] = n;
	}
	return nil;
}

leave(p: ref Player)
{
	n := order[p.id];
	if (n >= 0) {
		order[p.id] = -1;
	}
}

Eusage: con "bad command usage";

Realpoint: adt {
	x, y: real;
};

p2s(p: Point): string
{
	return string p.x + " " + string p.y;
}

rp2s(rp: Realpoint): string
{
	return string rp.x + " " + string rp.y;
}

command(player: ref Player, cmd: string): string
{
	e := ref Sys->Exception;
	if (sys->rescue("parse:*", e) == Sys->EXCEPTION) {
		sys->rescued(Sys->ONCE, nil);
		return e.name[6:];
	}
#	sys->print("cmd: %s", cmd);
	(n, toks) := sys->tokenize(cmd, " \n");
	assert(n > 0, "unknown command");
	case hd toks {
	"start" =>
		# start
		assert(!started, "game has already started");
		r := Rect((0, 0), (W, H)).inset(INSET + 1);
		goals := l2a(sides(r));
		for (i := nplayers; i < len batpos; i++) {
			addline(goals[i], nil);
			addline(borderpos[i], ("owner", string player.id) :: nil);
		}
		started  = 1;
	"newball" =>
		# newball batid p.x p.y v.x v.y speed
		assert(n == 7, Eusage);
		assert(started, "game not in progress");
		assert(bats[player.id] != nil, "you are not playing");
		bat := player.obj(int hd tl toks);
		assert(bat != nil, "no such bat");
		ball := game.newobject(nil, ~0, "ball");
		ball.setattr("state", string bat.id +  " " + string order[player.id] +
			" " + concat(tl tl toks) + " " + string sys->millisec(), ~0);
	"lost" =>
		# lost ballid
		assert(n == 2, Eusage);
		o := player.obj(int hd tl toks);
		assert(o != nil, "bad object");
		assert(o.getattr("state") != nil, "can only lose balls");
		o.delete();
	"state" =>
		# state ballid lasthit owner p.x p.y v.x v.y s time
		# NB. lasthit is a *local* id, not external
		assert(n == 10, Eusage);
		assert(order[player.id] >= 0, "you are not playing");
		o := player.obj(int hd tl toks);
		assert(o != nil, "object does not exist");
		o.setattr("state", concat(tl tl toks), ~0);
		ord := order[player.id];
		scores[ord]++;
		arena.setattr("score" + string ord, string scores[ord], ~0);
	"bat" =>
		# bat pos
		assert(n == 2, Eusage);
		n := order[player.id];
		assert(n >= 0, "you are not playing");
		s1 := real hd tl toks;
		bats[n].setattr("pos", hd tl toks + " " + string (s1 + BATLEN), ~0);
	"time" =>
		# time millisec
		assert(n == 2, Eusage);
		tm := int hd tl toks;
		offset := sys->millisec() - tm;
		game.action("time " + string offset + " " + string tm, nil, nil, 1 << player.id);
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

concat(v: list of string): string
{
	if (v == nil)
		return nil;
	s := hd v;
	for (v = tl v; v != nil; v = tl v)
		s += " " + hd v;
	return s;
}

Line.seg(l: self Line, s1, s2: real): Line
{
	(dx, dy) := (l.p2.x - l.p1.x, l.p2.y - l.p1.y);
	return (((l.p1.x + int (s1 * real dx)), l.p1.y + int (s1 * real dy)),
			((l.p1.x + int (s2 * real dx)), l.p1.y + int (s2 * real dy)));
}

sides(r: Rect): list of Line
{
	return ((r.min.x, r.min.y), (r.min.x, r.max.y)) ::
		((r.max.x, r.min.y), (r.max.x, r.max.y)) ::
		((r.min.x, r.min.y), (r.max.x, r.min.y)) ::
		((r.min.x, r.max.y), (r.max.x, r.max.y)) :: nil;
}

addlines(ll: list of Line, attrs: list of (string, string))
{
	for (; ll != nil; ll = tl ll)
		addline(hd ll, attrs);
}

segs(ll: list of Line, s1, s2: real): list of Line
{
	nll: list of Line;
	for (; ll != nil; ll = tl ll)
		nll = (hd ll).seg(s1, s2) :: nll;
	ll = nil;
	for (; nll != nil; nll = tl nll)
		ll = hd nll :: ll;
	return ll;
}

l2a(ll: list of Line): array of Line
{
	a := array[len ll] of Line;
	for (i := 0; ll != nil; ll = tl ll)
		a[i++] = hd ll;
	return a;
}
