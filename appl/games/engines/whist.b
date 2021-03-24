implement Gamemodule;

include "sys.m";
	sys: Sys;
include "draw.m";
include "../gamesrv.m";
	gamesrv: Gamesrv;
	Attributes, Range, Object, Game, Player, rand: import gamesrv;
include "allow.m";
	allow: Allow;
include "cardlib.m";
	cardlib: Cardlib;
	Trick, Selection, Cplayer: import cardlib;
	dTOP, dLEFT, oRIGHT, EXPAND, FILLX, FILLY, Stackspec: import Cardlib;

game: ref Game;
CLICK, START, SAY: con iota;

started := 0;

buttons: ref Object;
scores: ref Object;
deck, pile: ref Object;
hands, taken: array of ref Object;

MINPLAYERS: con 2;
MAXPLAYERS: con 4;

leader, turn: ref Cplayer;
trick: ref Trick;

Trickpilespec := Stackspec(
	"display",		# style
	4,			# maxcards
	0,			# conceal
	"trick pile"	# title
);

Handspec := Stackspec(
	"display",
	13,
	1,
	""
);

Takenspec := Stackspec(
	"pile",
	52,
	0,
	"tricks"
);

clienttype(): string
{
	return "cards";
}

init(g: ref Game, srvmod: Gamesrv): string
{
	sys = load Sys Sys->PATH;
	game = g;
	gamesrv = srvmod;

	allow = load Allow Allow->PATH;
	if (allow == nil) {
		sys->print("whist: cannot load %s: %r\n", Allow->PATH);
		return "bad module";
	}
	allow->init(game, gamesrv);
	allow->add(SAY, nil, "say &");

	cardlib = load Cardlib Cardlib->PATH;
	if (cardlib == nil) {
		sys->print("whist: cannot load %s: %r\n", Cardlib->PATH);
		return "bad module";
	}

	cardlib->init(game, gamesrv);
	deck = game.newobject(nil, ~0, "stack");
	cardlib->makecards(deck, (0, 52), nil);
	cardlib->shuffle(deck);
	buttons = game.newobject(nil, ~0, "buttons");
	scores = game.newobject(nil, ~0, "scoretable");

	return nil;
}

join(p: ref Player): string
{
	sys->print("%s(%d) joining\n", p.name(), p.id);
	if (!started && cardlib->nplayers() < MAXPLAYERS) {
		Cplayer.join(p, -1);
		if (cardlib->nplayers() == MINPLAYERS) {
			mkbutton("Start", "start");
			allow->add(START, nil, "start");
		}
	}
	return nil;
}
		
leave(p: ref Player)
{
	cp := Cplayer.find(p);
	if (cp != nil) {
		cp.leave();
		started == 0;
	}
	if (!started && cardlib->nplayers() < MINPLAYERS) {
		buttons.deletechildren((0, len buttons.children));
		allow->del(START, nil);
	}
}

command(p: ref Player, cmd: string): string
{
	e := ref Sys->Exception;
	if (sys->rescue("parse:*", e) == Sys->EXCEPTION) {
		sys->rescued(Sys->ONCE, nil);
		return e.name[6:];
	}
	(err, tag, toks) := allow->action(p, cmd);
	if (err != nil)
		return err;
	cp := Cplayer.find(p);
	if (cp == nil)
		return "you're only watching";
	case tag {
	START =>
		buttons.deletechildren((0, len buttons.children));
		allow->del(START, nil);
		startgame();
		n := cardlib->nplayers();
		leader = Cplayer.index(rand(n));
		starthand();
		titles := "";
		for (i := 0; i < n; i++)
			titles += Cplayer.index(i).p.name() + " ";
		game.newobject(scores, ~0, "score").setattr("score", titles, ~0);

	CLICK =>
		# click stackid index
		err := trick.play(cp.ord, int hd tl toks);
		if (err != nil)
			return err;

		turn = turn.next(1);
		if (turn == leader) {			# come full circle
			winner := Cplayer.index(trick.winner);
			remark(sys->sprint("%s won the trick", winner.p.name()));
			cardlib->discard(pile, taken[winner.ord], 0);
			nplayers := cardlib->nplayers();
			taken[winner.ord].setattr("title",
				string (len taken[winner.ord].children / nplayers) +
				" tricks", ~0);
			o := winner.obj;
			trick = nil;
			s := "";
			for (i := 0; i < nplayers; i++) {
				if (i == winner.ord)
					s += "1 ";
				else
					s += "0 ";
			}
			game.newobject(scores, ~0, "score").setattr("score", s, ~0);
			if (len hands[winner.ord].children > 0) {
				leader = turn = winner;
				trick = Trick.new(pile, -1, hands, nil);
			} else {
				remark("one round down, some to go");
				leader = turn  = nil;		# XXX this round over
			}
		}
		canplay(turn);
	SAY =>
		game.action("say player " + string p.id + ": '" + joinwords(tl toks) + "'", nil, nil, ~0);
	}
	return nil;
}

startgame()
{
	entry := game.newobject(nil, ~0, "widget entry");
	entry.setattr("command", "say", ~0);
	cardlib->addlayobj("entry", nil, nil, dTOP|FILLX, entry);
	cardlib->addlayframe("arena", nil, nil, dTOP|EXPAND|FILLX|FILLY, dTOP);
	cardlib->maketable("arena");

	pile = cardlib->newstack(nil, nil, Trickpilespec);
	cardlib->addlayobj(nil, "public", nil, dTOP|oRIGHT, pile);
	n := cardlib->nplayers();
	hands = array[n] of ref Object;
	taken = array[n] of ref Object;
	tt := game.newobject(nil, ~0, "widget menu");
	tt.setattr("text", "hello", ~0);
	for (ml := "one" :: "two" :: "three" :: nil; ml != nil; ml = tl ml) {
		o := game.newobject(tt, ~0, "menuentry");
		o.setattr("text", hd ml, ~0);
		o.setattr("command", hd ml, ~0);
	}
	for (i := 0; i < n; i++) {
		cp := Cplayer.index(i);
		hands[i] = cardlib->newstack(cp.obj, cp.p, Handspec);
		taken[i] = cardlib->newstack(cp.obj, cp.p, Takenspec);
		p := "p" + string i;
		cardlib->addlayframe(p + ".f", p, nil, dLEFT|oRIGHT, dTOP);
		cardlib->addlayobj(nil, p + ".f", cp.layout, dTOP, tt);
		cardlib->addlayobj(nil, p + ".f", nil, dTOP, hands[i]);
		cardlib->addlayobj(nil, "p" + string i, nil, dLEFT|oRIGHT, taken[i]);
	}
}

joinwords(v: list of string): string
{
	if (v == nil)
		return nil;
	s := hd v;
	for (v = tl v; v != nil; v = tl v)
		s += " " + hd v;
	return s;
}

starthand()
{
	cardlib->deal(deck, 13, hands, 0);
	trick = Trick.new(pile, -1, hands, nil);
	turn = leader;
	canplay(turn);
}

canplay(cp: ref Cplayer)
{
	allow->del(CLICK, nil);
	for (i := 0; i < cardlib->nplayers(); i++) {
		ccp := Cplayer.index(i);
		ccp.obj.setattr("status", nil, 1<<ccp.p.id);
		hands[i].setattr("actions", nil, 1<<ccp.p.id);
	}
	if (cp.ord != -1) {
		allow->add(CLICK, cp.p, "click %d %d");
		cp.obj.setattr("status", "It's your turn to play", 1<<cp.p.id);
		hands[cp.ord].setattr("actions", "click", 1<<cp.p.id);
	}
}

remark(s: string)
{
	game.action("remark " + s, nil, nil, ~0);
}

mkbutton(text, cmd: string): ref Object
{
	but := game.newobject(buttons, ~0, "button");
	but.setattr("text", text, ~0);
	but.setattr("command", cmd, ~0);
	return but;
}
