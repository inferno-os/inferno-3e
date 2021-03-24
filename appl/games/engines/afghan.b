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
	dTOP, dLEFT, oLEFT, oRIGHT, EXPAND, FILLX, FILLY, aUPPERCENTRE,
		Stackspec: import Cardlib;

game: ref Game;
rows, central: array of ref Object;
chokey, deck: ref Object;
CLICK, REDEAL: con iota;

mainplayer: ref Cplayer;

direction := 0;
nredeals := 0;

Rowpilespec := Stackspec(
	"display",		# style
	10,			# maxcards
	0,			# conceal
	nil			# title
);

Centralpilespec := Stackspec(
	"pile",
	13,
	0,
	nil
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
	cardlib = load Cardlib Cardlib->PATH;
	if (cardlib == nil) {
		sys->print("whist: cannot load %s: %r\n", Cardlib->PATH);
		return "bad module";
	}
	cardlib->init(game, gamesrv);
	return nil;
}

join(p: ref Player): string
{
	sys->print("%s(%d) joining\n", p.name(), p.id);
	if (mainplayer == nil) {
		mainplayer = Cplayer.join(p, -1);
		startgame();
		allow->add(CLICK, p, "click %o %d");
	} else {
		lay := mainplayer.layout.lay;
		lay.setvisibility(lay.visibility | (1 << p.id));
	}
	return nil;
}
		
leave(p: ref Player)
{
	if ((cp := Cplayer.find(p)) != nil) {
		cp.leave();
		mainplayer = nil;
	} else if (mainplayer != nil) {
		lay := mainplayer.layout.lay;
		lay.setvisibility(lay.visibility & ~(1 << p.id));
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
		return "you are not playing";

	case tag {
	REDEAL =>
		if (nredeals >= 3)
			return "no more redeals";
		redeal();
		nredeals++;
	CLICK =>
		# click stack index
		stack := game.objects[int hd tl toks];
		nc := len stack.children;
		idx := int hd tl tl toks;
		sel := cp.sel;
		stype := stack.getattr("type");

		if (sel.isempty() || sel.stack == stack) {
			# selecting a card to move
			if (idx < 0 || idx >= len stack.children)
				return "invalid index";
			case stype {
			"row" or
			"chokey" =>
				select(cp, stack, (nc - 1, nc));
			* =>
				return "you can't move cards from there";
			}
		} else {
			# selecting a stack to move to.
			card := cardlib->getcard(sel.stack.children[sel.r.start]);
			case stype {
			"central" =>
				top := cardlib->getcard(stack.children[nc - 1]);
				if (direction == 0) {
					if (card.number != (top.number + 1) % 13 &&
							card.number != (top.number + 12) % 13)
						return "out of sequence";
					if (card.suit != top.suit)
						return "wrong suit";
					direction = card.number - top.number;
				} else {
					if (card.number != (top.number + direction + 13) % 13)
						return "out of sequence";
					if (card.suit != top.suit)
						return "wrong suit";
				}
			"row" =>
				if (nc == 0 || sel.stack.getattr("type") == "chokey")
					return "you wish!";
				top := cardlib->getcard(stack.children[nc - 1]);
				if (card.suit != top.suit)
					return "wrong suit";
				if (card.number != (top.number + 1) % 13 &&
						card.number != (top.number + 12) % 13)
					return "out of sequence";
			"chokey" =>
				if (nc != 0)
					return "only one card allowed there";
			* =>
				return "can't move there";
			}
			sel.transfer(stack, -1);
		}
	}
	return nil;
}

startgame()
{
	addlayobj, addlayframe: import cardlib;

	entry := game.newobject(nil, ~0, "widget entry");
	entry.setattr("command", "say", ~0);

	but := game.newobject(nil, ~0, "widget button");
	but.setattr("text", "Redeal", ~0);
	but.setattr("command", "redeal", ~0);
	allow->add(REDEAL, Cplayer.index(0).p, "redeal");

	addlayframe("topf", nil, nil, dTOP|EXPAND|FILLX|aUPPERCENTRE, dTOP);
	addlayobj(nil, "topf", nil, dLEFT, but);
	addlayobj(nil, "topf", nil, dLEFT|EXPAND|FILLX, entry);

	addlayframe("arena", nil, nil, dTOP|EXPAND|FILLX|FILLY, dTOP);

	addlayframe("left", "arena", nil, dLEFT|EXPAND, dTOP);
	addlayframe("central", "arena", nil, dLEFT|EXPAND, dTOP);
	addlayframe("right", "arena", nil, dLEFT|EXPAND, dTOP);

	rows = array[10] of {* => newstack(nil, Rowpilespec, "row")};
	central = array[4] of {* => newstack(nil, Centralpilespec, "central")};
	chokey = newstack(nil, Centralpilespec, "chokey");

	deck = game.newobject(nil, ~0, "stack");
	cardlib->makecards(deck, (0, 52), nil);
	cardlib->shuffle(deck);

	for (i := 0; i < 5; i++)
		addlayobj(nil, "left", nil, dTOP|oRIGHT, rows[i]);
	for (i = 5; i < 10; i++)
		addlayobj(nil, "right", nil, dTOP|oRIGHT, rows[i]);
	for (i = 0; i < 4; i++)
		addlayobj(nil, "central", nil, dTOP, central[i]);
	addlayobj(nil, "central", nil, dTOP, chokey);

	for (i = 0; i < 52; i++)
		cardlib->setface(deck.children[i], 1);
	# get top card from deck for central piles.
	c := deck.children[len deck.children - 1];
	v := cardlib->getcard(c);
	j := 0;
	for (i = len deck.children - 1; i >= 0; i--) {
		w := cardlib->getcard(deck.children[i]);
		if (w.number == v.number)
			deck.transfer((i, i + 1), central[j++], -1);
	}
	for (i = 0; i < 10; i += 5) {
		for (j := i; j < i + 4; j++)
			deck.transfer((0, 5), rows[j], -1);
		deck.transfer((0, 4), rows[j], -1);
	}
}

redeal()
{
	for (i := 0; i < len rows; i++)
		cardlib->discard(rows[i], deck, 0);
	cardlib->shuffle(deck);

	i = 0;
	while ((n := len deck.children) > 0) {
		l, r: int;
		if (n >= 10)
			l = r = 5;
		else {
			l = n / 2;
			r = n - l;
		}
		deck.transfer((0, l), rows[i], 0);
		deck.transfer((0, r), rows[i + 5], 0);
		i++;
	}

	n = cardlib->nplayers();
	for (i = 0; i < n; i++)
		Cplayer.index(i).sel.set(nil);
}

newstack(parent: ref Object, spec: Stackspec, stype: string): ref Object
{
	stack := cardlib->newstack(parent, nil, spec);
	stack.setattr("type", stype, 0);
	stack.setattr("actions", "click", ~0);
	return stack;
}

select(cp: ref Cplayer, stack: ref Object, r: Range)
{
	if (cp.sel.isempty()) {
		cp.sel.set(stack);
		cp.sel.setrange(r);
	} else {
		if (cp.sel.r.start == r.start && cp.sel.r.end == r.end)
			cp.sel.set(nil);
		else
			cp.sel.setrange(r);
	}
}

