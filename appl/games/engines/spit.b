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
	dTOP, dLEFT, dBOTTOM, oDOWN, EXPAND, FILLX, FILLY, aCENTRELEFT, Stackspec: import Cardlib;

game: ref Game;
CLICK, SPIT, SAY, SHOW: con iota;
started := 0;
playing := 0;
dealt := 0;
NACES: con 7;		# number of ace piles to fit across the board.
Dplayer: adt {
	spare:	ref Object;
	row:		array of ref Object;
	centre:	ref Object;
};
deck: ref Object;
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

publicplayer: ref Cplayer;

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
	if (!started && cardlib->nplayers() < 2) {
		Cplayer.join(p, -1);
		if (cardlib->nplayers() == 2) {
			layout();
			deal();
			dealt = 1;
			playing = 0;
			started = 1;
			allow->add(SPIT, nil, "spit");
		}
	} else if ((cp := Cplayer.index(0)) != nil) {
		if (publicplayer == nil)
			publicplayer = cp;
		lay := cp.layout.lay;
		lay.setvisibility(lay.visibility | (1 << p.id));
	}
	return nil;
}
		
leave(p: ref Player)
{
	cp := Cplayer.find(p);
	if (cp != nil) {
		n := cardlib->nplayers();
		if (started) {
			for (i := n-1; i >= 0; i--) {
				x := Cplayer.index(i);
				x.leave();
				if (x != cp)
					Cplayer.join(x.p, -1);
			}
		} else
			cp.leave();
		dplayers = nil;
		allow->del(CLICK, nil);
		started = 0;
		clearsel();
		if (cp == publicplayer)
			publicplayer = nil;
	} else if (publicplayer != nil) {
		lay := publicplayer.layout.lay;
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
		return "you're only watching";
	case tag {
	SPIT =>
		if (!dealt) {
			deal();
			dealt = 1;
		} else if (!playing) {
			go();
			allow->add(CLICK, nil, "click %o %d");
			playing = 1;
		} else if (!canplay()) {
			go();
		} else
			return "it is possible to play";
		
	CLICK =>
		stack := game.objects[int hd tl toks];
		nc := len stack.children;
		idx := int hd tl tl toks;
		sel := cp.sel;
		stype := stack.getattr("type");
		d := dplayers[cp.ord];
		if (sel.isempty() || sel.stack == stack) {
			# selecting a card to move
			if (idx < 0 || idx >= len stack.children)
				return "invalid index";
			if (owner(stack) != cp)
				return "not yours, don't touch!";
			case stype {
			"row" =>
				card := getcard(stack.children[nc - 1]);
				if (card.face == 0)
					cardlib->setface(stack.children[nc - 1], 1);
				else
					select(cp, stack, (nc - 1, nc));
			* =>
				return "you can't move cards from there";
			}
		} else {
			# selecting a stack to move to.
			case stype {
			"centre" =>
				card := getcard(sel.stack.children[sel.r.start]);
				onto := getcard(stack.children[nc - 1]);
				if ((card.number + 1) % 13 != onto.number &&
						(card.number + 12) % 13 != onto.number) {
					sel.set(nil);
					return "out of sequence";
				}
				sel.transfer(stack, -1);
				for (i := 0; i < len d.row; i++)
					if (len d.row[i].children > 0)
						break;
				if (i == len d.row) {
					if (len d.spare.children == 0) {
						remark(string p.id + " has won");
						allow->del(CLICK, nil);
						allow->del(SPIT, nil);
						clearsel();
					} else
						finish(cp);
				}
			"row" =>
				if (owner(stack) != cp) {
					sel.set(nil);
					return "not yours, don't touch!";
				}
				if (nc != 0) {
					sel.set(nil);
					return "cannot stack cards";
				}
				sel.transfer(stack, -1);
			* =>
				sel.set(nil);
				return "can't move there";
			}
		}
		
	SAY =>
		game.action("say player " + string p.id + ": '" + joinwords(tl toks) + "'", nil, nil, ~0);

	SHOW =>
		game.show(nil);
	}
	return nil;
}

canplay(): int
{
	for (i := 0; i < 2; i++) {
		d := dplayers[i];
		nmulti := nfree := 0;
		for (j := 0; j < len d.row; j++) {
			s1 := d.row[j];
			if (len s1.children > 0) {
				if (len s1.children > 1)
					nmulti++;
				card1 := getcard(s1.children[len s1.children - 1]);
				for (k := 0; k < 2; k++) {
					s2 := dplayers[k].centre;
					if (len s2.children > 0) {
						card2 := getcard(s2.children[len s2.children - 1]);
						if ((card1.number + 1) % 13 == card2.number ||
								(card1.number + 12) % 13 == card2.number)
							return 1;
					}
				}
			} else
				nfree++;
		}
		if (nmulti > 0 && nfree > 0)
			return 1;
	}
	return 0;
}

bottomdiscard(src, dst: ref Object)
{
	cardlib->flip(src);
	for (i := 0; i < len src.children; i++)
		cardlib->setface(src.children[i], 0);
	src.transfer((0, len src.children), dst, 0);
}

finish(winner: ref Cplayer)
{
	loser := dplayers[!winner.ord];
	for (i := 0; i < 2; i++) {
		d := dplayers[i];
		bottomdiscard(d.centre, loser.spare);
		for (j := 0; j < len d.row; j++)
			bottomdiscard(d.row[j], loser.spare);
	}
	playing = 0;
	dealt = 0;
	allow->del(CLICK, nil);
	allow->add(SPIT, nil, "spit");
	clearsel();
}

go()
{
	for (i := 0; i < 2; i++) {
		d := dplayers[i];
		n := len d.spare.children;
		if (n > 0)
			d.spare.transfer((n - 1, n), d.centre, -1);
		else if ((m := len dplayers[!i].spare.children) > 0)
			dplayers[!i].spare.transfer((m - 1, m), d.centre, -1);
		else {
			# both players' spare piles are used up; use central piles instead
			for (j := 0; j < 2; j++) {
				cardlib->discard(dplayers[j].centre, dplayers[j].spare, 0);
				cardlib->flip(dplayers[j].spare);
			}
			go();
			return;
		}
		cardlib->setface(d.centre.children[len d.centre.children - 1], 1);
	}
}

getcard(card: ref Object): Card
{
	return cardlib->getcard(card);
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

# must have two players to lay out by this point
layout()
{
	dplayers = array[2] of ref Dplayer;
	for (i := 0; i < 2; i++) {
		cp := Cplayer.index(i);
		d := dplayers[i] = ref Dplayer;
		d.spare = newstack(cp.obj, Untitledpilespec, "spare");
		d.row = array[4] of {* => newstack(cp.obj, Openspec, "row")};
		d.centre = newstack(cp.obj, Untitledpilespec, "centre");
	}
	deck = game.newobject(nil, ~0, "stack");
	cardlib->makecards(deck, (0, 52), "0");
	cardlib->shuffle(deck);

	entry := game.newobject(nil, ~0, "widget entry");
	entry.setattr("command", "say", ~0);
	cardlib->addlayobj(nil, nil, nil, dTOP|FILLX, entry);

	cardlib->addlayframe("arena", nil, nil, dTOP|EXPAND|FILLX|FILLY, dTOP);
	maketable("arena");
	spitbutton := newbutton("spit", "Spit!");
	for (i = 0; i < 2; i++) {
		d := dplayers[i];
		f := "p" + string i;

		subf := "f" + string i;
		cardlib->addlayframe(subf, f, nil, dLEFT, dTOP);
		cardlib->addlayobj(nil, subf, Cplayer.index(i).layout, dTOP, spitbutton);
		cardlib->addlayobj(nil, subf, nil, dTOP, d.spare);
		for (j := 0; j < len d.row; j++)
			cardlib->addlayobj(nil, f, nil, dLEFT|EXPAND|oDOWN, d.row[j]);
		cardlib->addlayobj(nil, "centre", nil, dLEFT|EXPAND, d.centre);
	}
}

newbutton(cmd, text: string): ref Object
{
	but := game.newobject(nil, ~0, "widget button");
	but.setattr("command", cmd, ~0);
	but.setattr("text", text, ~0);
	return but;
}

settopface(stack: ref Object, face: int)
{
	n := len stack.children;
	if (n > 0)
		cardlib->setface(stack.children[n - 1], face);
}

transfertop(src, dst: ref Object, index: int)
{
	n := len src.children;
	src.transfer((n - 1, n), dst, index);
}

deal()
{
	clearsel();
	n := len deck.children;
	if (n > 0) {
		deck.transfer((0, n / 2), dplayers[0].spare, 0);
		deck.transfer((0, len deck.children), dplayers[1].spare, 0);
	}

	for (i := 0; i < 2; i++) {
		d := dplayers[i];
loop:		for (j := 0; j < len d.row; j++) {
			for (k := j; k < len d.row; k++) {
				if (len d.spare.children == 0)
					break loop;
				transfertop(d.spare, d.row[k], -1);
			}
		}
		for (j = 0; j < len d.row; j++)
			settopface(d.row[j], 1);
	}
}

maketable(parent: string)
{
	addlayframe: import cardlib;

	for (i := 0; i < 2; i++) {
		layout := Cplayer.index(i).layout;
		addlayframe("p" + string !i, parent, layout, dTOP|EXPAND, dBOTTOM);
		addlayframe("p" + string i, parent, layout, dBOTTOM|EXPAND, dTOP);
		if (i == 0)
			addlayframe("centre", parent, layout, dTOP|EXPAND, dTOP);
		else
			addlayframe("centre", parent, layout, dTOP|EXPAND, dTOP);
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

clearsel()
{
	n := cardlib->nplayers();
	for (i := 0; i < n; i++)
		Cplayer.index(i).sel.set(nil);
}
