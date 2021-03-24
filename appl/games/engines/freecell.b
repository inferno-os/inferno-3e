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
	Trick, Selection, Cplayer, Card: import cardlib;
	getcard: import cardlib;
	dTOP, dRIGHT, dLEFT, oRIGHT, oDOWN,
	aCENTRERIGHT, aCENTRELEFT, aUPPERRIGHT,
	EXPAND, FILLX, FILLY, Stackspec: import Cardlib;

game: ref Game;

open: array of ref Object;		# [8]
cells: array of ref Object;		# [4]
acepiles: array of ref Object;	# [4]
txpiles: array of ref Object;	# [len open + len cells]
deck: ref Object;

suitsout := array[4] of {* => -1};

mainplayer: ref Cplayer;

CLICK: con iota;

Openspec := Stackspec(
	"display",		# style
	19,			# maxcards
	0,			# conceal
	""			# title
);

Pilespec := Stackspec(
	"pile",		# style
	19,			# maxcards
	0,			# conceal
	"pile"		# title
);

Untitledpilespec := Stackspec(
	"pile",		# style
	13,			# maxcards
	0,			# conceal
	""			# title
);

clienttype(): string
{
	return "cards";
}

rank := array[] of {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12};

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
		mainplayer.layout.lay.setvisibility(lay.visibility & ~(1 << p.id));
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
	CLICK =>
		# click stack index
		stack := game.objects[int hd tl toks];
		nc := len stack.children;
		idx := int hd tl tl toks;
		sel := cp.sel;
		stype := stack.getattr("type");
		if (sel.isempty() || sel.stack == stack) {
			if (idx < 0 || idx >= len stack.children)
				return "invalid index";
			case stype {
			"cell" or
			"open" =>
				select(cp, stack, (idx, nc));
			* =>
				return "you can't move cards from there";
			}
		} else {
			from := sel.stack;
			case stype {
			"acepile" =>
				if (sel.r.end != sel.r.start + 1)
					return "only one card at a time!";
				addtoacepile(sel.stack);
				sel.set(nil);
				movefree();
			"open" =>
				c := getcard(sel.stack.children[sel.r.start]);
				col := !isred(c.suit);
				n := c.number + 1;
				for (i := sel.r.start; i < sel.r.end; i++) {
					c2 := getcard(sel.stack.children[i]);
					if (isred(c2.suit) == col)
						return "bad colour sequence";
					if (c2.number != n - 1)
						return "bad number sequence";
					n = c2.number;
					col = isred(c2.suit);
				}
				if (nc != 0) {
					c2 := getcard(stack.children[nc - 1]);
					if (isred(c2.suit) == isred(c.suit) || c2.number != c.number + 1)
						return "opposite colours, descending, only";
				}
				r := sel.r;
				selstack := sel.stack;
				sel.set(nil);
				fc := freecells(stack);
				if (r.end - r.start - 1 > len fc)
					return "not enough free cells";
				n = 0;
				for (i = r.end - 1; i >= r.start + 1; i--)
					selstack.transfer((i, i + 1), fc[n++], -1);
				selstack.transfer((i, i + 1), stack, -1);
				while (--n >= 0)
					fc[n].transfer((0, 1), stack, -1);
				movefree();
			"cell" =>
				if (sel.r.end - sel.r.start > 1 || nc > 0)
					return "only one card allowed there";
				sel.transfer(stack, -1);
				movefree();
			* =>
				return "can't move there";
			}
		}
	}
	return nil;
}

freecells(dest: ref Object): array of ref Object
{
	fc := array[len txpiles] of ref Object;
	n := 0;
	for (i := 0; i < len txpiles; i++)
		if (len txpiles[i].children == 0 && txpiles[i] != dest)
			fc[n++] = txpiles[i];
	return fc[0:n];
}

# move any cards that can be moved.
movefree()
{
	nmoved := 1;
	while (nmoved > 0) {
		nmoved = 0;
		for (i := 0; i < len txpiles; i++) {
			pile := txpiles[i];
			nc := len pile.children;
			if (nc == 0)
				continue;
			card := getcard(pile.children[nc - 1]);
			if (suitsout[card.suit] != card.number - 1)
				continue;
			# card can be moved; now make sure there's no card out
			# that might be moved onto this card
			for (j := 0; j < len suitsout; j++)
				if (isred(j) != isred(card.suit) && card.number > 1 && suitsout[j] < card.number - 1)
					break;
			if (j == len suitsout) {
				addtoacepile(pile);
				nmoved++;
			}
		}
	}
}

addtoacepile(pile: ref Object)
{
	nc := len pile.children;
	if (nc == 0)
		return;
	card := getcard(pile.children[nc - 1]);
	for (i := 0; i < len acepiles; i++) {
		anc := len acepiles[i].children;
		if (anc == 0) {
			if (card.number == 0)
				break;
			continue;
		}
		acard := getcard(acepiles[i].children[anc - 1]);
		if (acard.suit == card.suit && acard.number == card.number - 1)
			break;
	}
	if (i < len acepiles) {
		pile.transfer((nc - 1, nc), acepiles[i], -1);
		suitsout[card.suit] = card.number;
	}
}

startgame()
{
	addlayobj, addlayframe: import cardlib;

	open = array[8] of {* => newstack(nil, Openspec, "open", nil)};
	acepiles = array[4] of {* => newstack(nil, Untitledpilespec, "acepile", nil)};
	cells = array[4] of {* => newstack(nil, Untitledpilespec, "cell", "cell")};
	for (i := 0; i < len cells; i++)
		cells[i].setattr("showsize", "0", ~0);

	txpiles = array[12] of ref Object;
	txpiles[0:] = open;
	txpiles[len open:] = cells;
	deck = game.newobject(nil, ~0, "stack");

	cardlib->makecards(deck, (0, 52), nil);

	addlayframe("arena", nil, nil, dTOP|EXPAND|FILLX|FILLY, dTOP);
	addlayframe("top", "arena", nil, dTOP|EXPAND, dTOP);
	addlayframe("bot", "arena", nil, dTOP|EXPAND, dTOP);
	for (i = 0; i < 4; i++)
		addlayobj(nil, "top", nil, dRIGHT, acepiles[i]);
	for (i = 0; i < 4; i++)
		addlayobj(nil, "top", nil, dLEFT, cells[i]);
	for (i = 0; i < len open; i++)
		addlayobj(nil, "bot", nil, dLEFT|oDOWN|EXPAND, open[i]);
	deal();
}

deal()
{
	cardlib->shuffle(deck);
	cardlib->deal(deck, 7, open, 0);
}

newstack(parent: ref Object, spec: Stackspec, stype, title: string): ref Object
{
	stack := cardlib->newstack(parent, nil, spec);
	stack.setattr("type", stype, 0);
	stack.setattr("actions", "click", ~0);
	stack.setattr("title", title, ~0);
	return stack;
}

isred(suit: int): int
{
	return suit == Cardlib->DIAMONDS || suit == Cardlib->HEARTS;
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
