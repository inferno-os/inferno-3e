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
	dTOP, dLEFT, oDOWN, EXPAND, FILLX, FILLY, aCENTRELEFT, Stackspec: import Cardlib;

game: ref Game;
CLICK, START, SAY, SHOW: con iota;
KING: con 12;
started := 0;
NACES: con 7;		# number of ace piles to fit across the board.

Dplayer: adt {
	pile,
	spare1,
	spare2: ref Object;
	open, acepiles: array of ref Object;
};
buttons: ref Object;
scores: array of int;
scorelabel: ref Object;

dplayers: array of ref Dplayer;

Openspec := Stackspec(
	"display",		# style
	4,			# maxcards
	0,			# conceal
	""			# title
);

Pilespec := Stackspec(
	"pile",		# style
	13,			# maxcards
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
	allow->add(SHOW, nil, "show");

	cardlib = load Cardlib Cardlib->PATH;
	if (cardlib == nil) {
		sys->print("whist: cannot load %s: %r\n", Cardlib->PATH);
		return "bad module";
	}

	cardlib->init(game, gamesrv);
	buttons = game.newobject(nil, ~0, "buttons");

	return nil;
}


join(p: ref Player): string
{
	sys->print("%s(%d) joining\n", p.name(), p.id);
	if (!started) {
		Cplayer.join(p, -1);
		if (cardlib->nplayers() == 2) {
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
		ord := cp.ord;
		cp.leave();
		dplayers = nil;
		allow->del(CLICK, nil);
		started == 0;
	}
	if (!started && cardlib->nplayers() < 2) {
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
		layout();
		deal();
		n := cardlib->nplayers();
		for (i := 0; i < n; i++)
			allow->add(CLICK, Cplayer.index(i).p, "click %o %d");

	CLICK =>
		# click stack index
		stack := game.objects[int hd tl toks];
		nc := len stack.children;
		idx := int hd tl tl toks;
		sel := cp.sel;
		stype := stack.getattr("type");
		d := dplayers[cp.ord];
		if (sel.isempty() || sel.stack == stack) {
			# selecting a card to move
			if (nc == 0 && stype == "spare1") {
				cardlib->flip(d.spare2);
				d.spare2.transfer((0, len d.spare2.children), d.spare1, 0);
				return nil;
			}
			if (idx < 0 || idx >= len stack.children)
				return "invalid index";
			if (owner(stack) != cp)
				return "not yours, don't touch!";
			case stype {
			"spare2" or
			"pile" =>
				select(cp, stack, (nc - 1, nc));
			"open" =>
				select(cp, stack, (idx, nc));
			"spare1" =>
				if ((n := nc) > 3)
					n = 3;
				for (i := 0; i < n; i++) {
					cardlib->setface(stack.children[nc - 1], 1);
					stack.transfer((nc - 1, nc), d.spare2, -1);
					nc--;
				}
			* =>
				return "you can't move cards from there";
			}
		} else {
			# selecting a stack to move to.
			frompile := sel.stack.getattr("type") == "pile";
			case stype {
			"acepile" =>
				if (sel.r.end != sel.r.start + 1)
					return "only one card at a time!";
				card := getcard(sel.stack.children[sel.r.start]);
				if (nc == 0) {
					if (card.number != 0)
						return "aces only";
				} else {
					top := getcard(stack.children[nc - 1]);
					if (card.number != top.number + 1)
						return "out of sequence";
					if (card.suit != top.suit)
						return "wrong suit";
				}
				sel.transfer(stack, -1);
				if (card.number == KING)	# kings get flipped
					cardlib->setface(stack.children[len stack.children - 1], 0);
			"open" =>
				if (owner(stack) != cp)
					return "not yours, don't touch!";
				c := getcard(sel.stack.children[sel.r.start]);
				col := !isred(c);
				n := c.number + 1;
				for (i := sel.r.start; i < sel.r.end; i++) {
					c2 := getcard(sel.stack.children[i]);
					if (isred(c2) == col)
						return "bad colour sequence";
					if (c2.number != n - 1)
						return "bad number sequence";
					n = c2.number;
					col = isred(c2);
				}
				if (nc != 0) {
					c2 := getcard(stack.children[nc - 1]);
					if (isred(c2) == isred(c) || c2.number != c.number + 1)
						return "invalid move";
				}
				sel.transfer(stack, -1);
			* =>
				return "can't move there";
			}
			if (frompile) {
				nc = len d.pile.children;
				if (nc == 0) {
					endround();
					deal();
				} else {
					cardlib->setface(d.pile.children[nc - 1], 1);
					d.pile.setattr("title", "pile [" + string nc + "]", ~0);
				}
			}
		}
	SAY =>
		game.action("say player " + string p.id + ": '" + joinwords(tl toks) + "'", nil, nil, ~0);

	SHOW =>
		game.show(nil);
	}
	return nil;
}

getcard(card: ref Object): Card
{
	return cardlib->getcard(card);
}

isred(c: Card): int
{
	return c.suit == Cardlib->DIAMONDS || c.suit == Cardlib->HEARTS;
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

owner(stack: ref Object): ref Cplayer
{
	parent := game.objects[stack.parentid];
	n := cardlib->nplayers();
	for (i := 0; i < n; i++) {
		cp := Cplayer.index(i);
		if (cp.obj == parent)
			return cp;
	}
	return nil;
}

layout()
{
	n := cardlib->nplayers();
	dplayers = array[n] of ref Dplayer;
	for (i := 0; i < n; i++) {
		cp := Cplayer.index(i);
		d := dplayers[i] = ref Dplayer;
		d.spare1 = newstack(cp.obj, Untitledpilespec, "spare1");
		d.spare2 = newstack(cp.obj, Untitledpilespec, "spare2");
		d.pile = newstack(cp.obj, Pilespec, "pile");
		d.open = array[4] of {* => newstack(cp.obj, Openspec, "open")};
		d.acepiles = array[4] of {* => newstack(cp.obj, Untitledpilespec, "acepile")};
		cardlib->makecards(d.spare1, (0, 52), string i);
	}

	entry := game.newobject(nil, ~0, "widget entry");
	entry.setattr("command", "say", ~0);
	cardlib->addlayobj(nil, nil, nil, dTOP|FILLX, entry);

	scores = array[n] of {* => 0};
	scorelabel = game.newobject(nil, ~0, "widget label");
	setscores();
	cardlib->addlayobj(nil, nil, nil, dTOP|FILLX, scorelabel);

	cardlib->addlayframe("arena", nil, nil, dTOP|EXPAND|FILLX|FILLY, dTOP);
	row := 0;
	col := 0;
	maketable("arena");
	for (i = 0; i < n; i++) {
		d := dplayers[i];
		f := "p" + string i;
		cardlib->addlayobj(nil, f, nil, dLEFT, d.spare1);
		cardlib->addlayobj(nil, f, nil, dLEFT, d.spare2);
		cardlib->addlayobj(nil, f, nil, dLEFT, d.pile);
		for (j := 0; j < len d.open; j++)
			cardlib->addlayobj(nil, f, nil, dLEFT|EXPAND|oDOWN, d.open[j]);
		for (j = 0; j < len d.acepiles; j++) {
			cardlib->addlayobj(nil, "a" + string row, nil, dLEFT|EXPAND, d.acepiles[j]);
			if (++col >= NACES) {
				col = 0;
				row++;
			}
		}
	}
}

setscores()
{
	s := "Scores: ";
	n := cardlib->nplayers();
	for (i := 0; i < n; i++) {
		s += Cplayer.index(i).p.name() + ": " + string scores[i];
		if (i < n - 1)
			s[len s] = ' ';
	}
	scorelabel.setattr("text", s, ~0);
}

deal()
{
	n := cardlib->nplayers();
	for (i := 0; i < n; i++) {
		cp := Cplayer.index(i);
		d := dplayers[i];
		deck := d.spare1;
		cardlib->shuffle(deck);
		deck.transfer((0, 13), d.pile, 0);
		cardlib->setface(d.pile.children[12], 1);
		d.pile.setattr("title", "pile [13]", ~0);
		for (j := 0; j < len d.open; j++) {
			deck.transfer((0, 1), d.open[j], 0);
			cardlib->setface(d.open[j].children[0], 1);
		}
	}
}

endround()
{
	# go through all the ace piles, moving cards back to the appropriate deck
	# and counting appropriately.
	# move all other cards back too.
	n := cardlib->nplayers();
	for (i := 0; i < n; i++) {
		d := dplayers[i];
		Cplayer.index(i).sel.set(nil);
		for (j := 0; j < len d.acepiles; j++) {
			acepile := d.acepiles[j];
			nc := len acepile.children;
			for (k := nc - 1; k >= 0; k--) {
				card := acepile.children[k];
				back := int card.getattr("rear");
				scores[back]++;
				if (getcard(card).number == KING)
					scores[back] += 5;
				cardlib->setface(card, 0);
				acepile.transfer((k, k + 1), dplayers[back].spare1, -1);
			}
		}
		if (len d.pile.children == 0)
			scores[i] += 10;			# bonus for going out
		else
			scores[i] -= len d.pile.children;
		cardlib->discard(d.pile, d.spare1, 1);
		cardlib->discard(d.spare2, d.spare1, 1);
		for (j = 0; j < len d.open; j++)
			cardlib->discard(d.open[j], d.spare1, 1);
	}
	setscores();
}

maketable(parent: string)
{
	addlayframe: import cardlib;

	n := cardlib->nplayers();
	na := ((n * 4) + (NACES - 1)) / NACES;
	for (i := 0; i < n; i++) {
		layout := Cplayer.index(i).layout;
		# one frame for each player other than self;
		# then all the ace piles; then self.
		for (j := 0; j < n; j++)
			if (j != i)
				addlayframe("p" + string j, parent, layout, dTOP|EXPAND, dTOP);
		for (j = 0; j < na; j++)
			addlayframe("a" + string j, parent, layout, dTOP|EXPAND|aCENTRELEFT, dTOP);
		addlayframe("p" + string i, parent, layout, dTOP|EXPAND, dTOP);
	}
}

newstack(parent: ref Object, spec: Stackspec, stype: string): ref Object
{
	stack := cardlib->newstack(parent, nil, spec);
	stack.setattr("type", stype, 0);
	stack.setattr("actions", "click", ~0);
	return stack;
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
