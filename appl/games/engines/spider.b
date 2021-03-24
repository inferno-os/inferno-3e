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
	aCENTRERIGHT, aCENTRELEFT, aUPPERRIGHT, aUPPERCENTRE,
	EXPAND, FILLX, FILLY, Stackspec: import Cardlib;

game: ref Game;

open: array of ref Object;		# [10]
deck: ref Object;
discard: ref Object;
dealbutton: ref Object;

mainplayer: ref Cplayer;

CLICK, MORECARDS: con iota;

Openspec := Stackspec(
	"display",		# style
	19,			# maxcards
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
		allow->add(MORECARDS, p, "morecards");
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
			"open" =>
				select(cp, stack, (idx, nc));
			* =>
				return "you can't move cards from there";
			}
		} else {
			from := sel.stack;
			case stype {
			"open" =>
				c := getcard(sel.stack.children[sel.r.start]);
				n := c.number + 1;
				for (i := sel.r.start; i < sel.r.end; i++) {
					c2 := getcard(sel.stack.children[i]);
					if (c2.face == 0)
						return "cannot move face down cards";
					if (c2.number != n - 1)
						return "bad number sequence";
					n = c2.number;
				}
				if (nc != 0) {
					c2 := getcard(stack.children[nc - 1]);
					if (c2.number != c.number + 1)
						return "descending, only";
				}
				srcstack := sel.stack;
				sel.transfer(stack, -1);
				turntop(srcstack);

				nc = len stack.children;
				if (nc >= 13) {
					c := getcard(stack.children[nc - 1]);
					suit := c.suit;
					for (i := 0; i < 13; i++) {
						c = getcard(stack.children[nc - i - 1]);
						if (c.suit != suit || c.number != i)
							break;
					}
					if (i == 13) {
						stack.transfer((nc - 13, nc), discard, -1);
						turntop(stack);
					}
				}
			* =>
				return "can't move there";
			}
		}
	MORECARDS =>
		for (i := 0; i < 10; i++)
			if (len open[i].children == 0)
				return "spaces must be filled before redeal";
		for (i = 0; i < 10; i++) {
			if (len deck.children == 0)
				break;
			cp.sel.set(nil);
			cardlib->setface(deck.children[0], 1);
			deck.transfer((0, 1), open[i], -1);
		}
		setdealbuttontext();
	}
	return nil;
}

setdealbuttontext()
{
	dealbutton.setattr("text", sys->sprint("deal more (%d left)", len deck.children), ~0);
}

turntop(stack: ref Object)
{
	if (len stack.children > 0)
		cardlib->setface(stack.children[len stack.children - 1], 1);
}

startgame()
{
	addlayobj, addlayframe: import cardlib;
	open = array[10] of {* => newstack(nil, Openspec, "open", nil)};
	deck = game.newobject(nil, ~0, "stack");
	discard = game.newobject(nil, ~0, "stack");
	cardlib->makecards(deck, (0, 52), "0");
	cardlib->makecards(deck, (0, 52), "1");
	addlayframe("arena", nil, nil, dTOP|EXPAND|FILLX|FILLY, dTOP);
	addlayframe("top", "arena", nil, dTOP|EXPAND|FILLX|FILLY, dTOP);

	for (i := 0; i < 10; i++)
		addlayobj(nil, "top", nil, dLEFT|oDOWN|EXPAND|aUPPERCENTRE, open[i]);
	addlayframe("bot", "arena", nil, dTOP, dTOP);
	dealbutton = newbutton("morecards", "deal more");
	addlayobj(nil, "bot", nil, dLEFT, dealbutton);
	deal();
	setdealbuttontext();
}

deal()
{
	cardlib->shuffle(deck);
	for (i := 0; i < 10; i++) {
		deck.transfer((0, 4), open[i], 0);
		turntop(open[i]);
	}
}

newstack(parent: ref Object, spec: Stackspec, stype, title: string): ref Object
{
	stack := cardlib->newstack(parent, nil, spec);
	stack.setattr("type", stype, 0);
	stack.setattr("actions", "click", ~0);
	stack.setattr("title", title, ~0);
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

newbutton(cmd, text: string): ref Object
{
	but := game.newobject(nil, ~0, "widget button");
	but.setattr("command", cmd, ~0);
	but.setattr("text", text, ~0);
	return but;
}

