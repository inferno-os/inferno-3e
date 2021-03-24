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
	Trick: import cardlib;
	dTOP, dLEFT, oLEFT, oRIGHT, EXPAND, FILLX, FILLY, Stackspec: import Cardlib;

game: ref Game;
CLICK, START, SAY: con iota;

started := 0;

buttons: ref Object;
scores: ref Object;
deck, pile: ref Object;
hands, taken, passon: array of ref Object;

MINPLAYERS: con 2;
MAXPLAYERS: con 4;

leader, turn: int;
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

Passonspec := Stackspec(
	"display",
	3,
	0,
	"pass on"
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
	cardlib->makecards(deck, (0, 52), 1);
	cardlib->shuffle(deck);
	buttons = game.newobject(nil, ~0, "buttons");
	scores = game.newobject(nil, ~0, "scoretable");

	return nil;
}

join(p: ref Player): string
{
	sys->print("%s(%d) joining\n", p.name(), p.id);
	if (!started && cardlib->nplayers() < MAXPLAYERS) {
		(nil, err) := cardlib->join(p, -1);
		if (err == nil) {
			if (cardlib->nplayers() == MINPLAYERS) {
				mkbutton("Start", "start");
				allow->add(START, nil, "start");
			}
		} else
			sys->print("error on join: %s\n", err);
	}
	return nil;
}
		
leave(p: ref Player)
{
	cardlib->leave(p);
	started == 0;
	if (cardlib->nplayers() < MINPLAYERS) {
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
	ord := cardlib->order(p);
	case tag {
	START =>
		buttons.deletechildren((0, len buttons.children));
		allow->del(START, nil);
		startgame();
		n := cardlib->nplayers();
		leader = rand(n);
		starthand();
		titles := "";
		for (i := 0; i < n; i++)
			titles += cardlib->info(i).p.name() + " ";
		game.newobject(scores, ~0, "score").setattr("score", titles, ~0);

	CLICK =>
		# click stackid index
		hand := hands[ord];
		if (int hd tl toks != hand.id)
			return "can't click there";
		index := int hd tl tl toks;
		if (index < 0 || index >= len hand.children)
			return "index out of range";
		cardlib->setsel(hands[ord], (index, len hands[ord].children), p);
		break;
		err := trick.play(cardlib->order(p), int hd tl toks);
		if (err != nil)
			return err;

		turn = next(turn);		# clockwise
		if (turn == leader) {			# come full circle
			winner := trick.winner;
			inf := cardlib->info(winner);
			remark(sys->sprint("%s won the trick", inf.p.name()));
			cardlib->discard(pile, taken[winner], 0);
			taken[winner].setattr("title",
				string (len taken[winner].children / cardlib->nplayers()) +
				" " + "tricks", ~0);
			o := cardlib->info(winner).obj;
			trick = nil;
			s := "";
			for (i := 0; i < cardlib->nplayers(); i++) {
				if (i == winner)
					s += "1 ";
				else
					s += "0 ";
			}
			game.newobject(scores, ~0, "score").setattr("score", s, ~0);
			if (len hands[winner].children > 0) {
				leader = turn = winner;
				trick = Trick.new(pile, -1, hands);
			} else {
				remark("one round down, some to go");
				leader = turn  = -1;		# XXX this round over
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
	cardlib->startgame();
	entry := game.newobject(nil, ~0, "widget entry");
	entry.setattr("command", "say", ~0);
	cardlib->addlayobj("entry", nil, nil, dTOP|FILLX, entry);
	cardlib->addlayframe("arena", nil, nil, dTOP|EXPAND|FILLX|FILLY, dTOP);
	cardlib->maketable("arena");

	pile = cardlib->newstack(nil, nil, Trickpilespec);
	cardlib->addlayobj(nil, "public", nil, dTOP|oLEFT, pile);
	n := cardlib->nplayers();
	hands = array[n] of ref Object;
	taken = array[n] of ref Object;
	passon = array[n] of ref Object;
	tt := game.newobject(nil, ~0, "widget menu");
	tt.setattr("text", "hello", ~0);
	for (ml := "one" :: "two" :: "three" :: nil; ml != nil; ml = tl ml) {
		o := game.newobject(tt, ~0, "menuentry");
		o.setattr("text", hd ml, ~0);
		o.setattr("command", hd ml, ~0);
	}
	for (i := 0; i < n; i++) {
		inf := cardlib->info(i);
		hands[i] = cardlib->newstack(inf.obj, inf.p, Handspec);
		taken[i] = cardlib->newstack(inf.obj, inf.p, Takenspec);
		passon[i] = cardlib->newstack(inf.obj, inf.p, Passonspec);
		p := "p" + string i;
		cardlib->addlayframe(p + ".f", p, nil, dLEFT|oLEFT, dTOP);
		cardlib->addlayobj(nil, p + ".f", inf.layout, dTOP, tt);
		cardlib->addlayobj(nil, p + ".f", nil, dTOP|oLEFT, hands[i]);
		cardlib->addlayobj(nil, p, nil, dLEFT|oLEFT, taken[i]);
		cardlib->addlayobj(nil, p, nil, dLEFT|oLEFT, passon[i]);
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
	trick = Trick.new(pile, -1, hands);
	turn = leader;
	canplay(turn);
}

canplay(ord: int)
{
	allow->del(CLICK, nil);
	for (i := 0; i < cardlib->nplayers(); i++) {
		inf := cardlib->info(i);
		inf.obj.setattr("status", nil, 1<<inf.p.id);
		hands[i].setattr("actions", nil, 1<<inf.p.id);
	}
	if (ord != -1) {
		allow->add(CLICK, player(ord), "click %o %d");
		inf := cardlib->info(ord);
		inf.obj.setattr("status", "It's your turn to play", 1<<inf.p.id);
		hands[ord].setattr("actions", "click", 1<<inf.p.id);
	}
}

playerobj(p: ref Player): ref Object
{
	return cardlib->info(cardlib->order(p)).obj;
}

player(ord: int): ref Player
{
	return cardlib->info(ord).p;
}

next(i: int): int
{
	i++;
	if (i >= cardlib->nplayers())
		i = 0;
	return i;
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
