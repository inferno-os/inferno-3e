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
	dTOP, dRIGHT, dLEFT, oRIGHT, oDOWN,
	aCENTRERIGHT, aCENTRELEFT, aUPPERRIGHT,
	EXPAND, FILLX, FILLY, Stackspec: import Cardlib;

game: ref Game;

sevens: array of ref Object;
spare1, spare2: ref Object;
acepiles: array of ref Object;
top2botcount := 3;
top2bot: ref Object;

mainplayer: ref Cplayer;

CLICK, TOP2BOT, REDEAL, SHOW: con iota;

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
	allow->add(SHOW, nil, "show");
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
		allow->add(TOP2BOT, p, "top2bot");
		allow->add(REDEAL, p, "redeal");
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
			if (nc == 0 && stype == "spare1") {
				cardlib->flip(spare2);
				spare2.transfer((0, len spare2.children), spare1, 0);
				return nil;
			}
			case stype {
			"spare2" or
			"open" =>
				if (idx < 0 || idx >= len stack.children)
					return "invalid index";
				select(cp, stack, (idx, nc));
			"spare1" =>
				if ((n := nc) > 3)
					n = 3;
				for (i := 0; i < n; i++) {
					cardlib->setface(stack.children[nc - 1], 1);
					stack.transfer((nc - 1, nc), spare2, -1);
					nc--;
				}
			* =>
				return "you can't move cards from there";
			}
		} else {
			from := sel.stack;
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
			"open" =>
				c := getcard(sel.stack.children[sel.r.start]);
				col := !isred(c);
				n := c.number + 1;
				for (i := sel.r.start; i < sel.r.end; i++) {
					c2 := getcard(sel.stack.children[i]);
					if (c2.face == 0)
						return "cannot move face-down cards";
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
				} else if (c.number != 12)
					return "only kings allowed there";
				sel.transfer(stack, -1);
			* =>
				return "can't move there";
			}
			if (from.getattr("type") == "open" && len from.children > 0)
				cardlib->setface(from.children[len from.children - 1], 1);
		}
	TOP2BOT =>
		if (len spare2.children != 0)
			return "can only top-to-bottom on the whole pile";
		if (top2botcount <= 0)
			return "too late";
		nc := len spare1.children;
		if (nc > 0) {
			spare1.transfer((nc - 1, nc), spare1, 0);
			top2botcount--;
			settop2bottext();
		}
	REDEAL =>
		clearup();
		cardlib->shuffle(spare1);
		deal();
		top2botcount = 3;
		settop2bottext();
	SHOW =>
		game.show(nil);
	}
	return nil;
}

settop2bottext()
{
	top2bot.setattr("text",
		sys->sprint("top to bottom (%d left)", top2botcount), ~0);
}

startgame()
{
	addlayobj, addlayframe: import cardlib;

	entry := game.newobject(nil, ~0, "widget entry");
	entry.setattr("command", "say", ~0);
	addlayobj("entry", nil, nil, dTOP|FILLX, entry);
	addlayframe("arena", nil, nil, dTOP|EXPAND|FILLX|FILLY, dTOP);

	addlayframe("top", "arena", nil, dTOP|EXPAND, dTOP);
	addlayframe("mid", "arena", nil, dTOP|EXPAND, dTOP);
	addlayframe("bot", "arena", nil, dTOP|EXPAND, dTOP);

	sevens = array[7] of {* => newstack(nil, Openspec, "open")};
	acepiles = array[4] of {* => newstack(nil, Untitledpilespec, "acepile")};
	spare1 = newstack(nil, Untitledpilespec, "spare1");
	spare2 = newstack(nil, Untitledpilespec, "spare2");

	cardlib->makecards(spare1, (0, 52), nil);

	for (i := 0; i < 4; i++)
		addlayobj(nil, "top", nil, dRIGHT, acepiles[i]);
	for (i = 0; i < len sevens; i++)
		addlayobj(nil, "mid", nil, dLEFT|oDOWN|EXPAND, sevens[i]);
	addlayframe("buts", "bot", nil, dLEFT|EXPAND|aUPPERRIGHT, dTOP);
	top2bot = newbutton("top2bot", "top to bottom");
	addlayobj(nil, "buts", nil, dTOP, top2bot);
	addlayobj(nil, "buts", nil, dTOP, newbutton("redeal", "redeal"));
	addlayobj(nil, "bot", nil, dLEFT, spare1);
	addlayobj(nil, "bot", nil, dLEFT|EXPAND|aCENTRELEFT, spare2);
	deal();
	settop2bottext();
}

clearup()
{
	for (i := 0; i < len sevens; i++)
		cardlib->discard(sevens[i], spare1, 1);
	for (i = 0; i < len acepiles; i++)
		cardlib->discard(acepiles[i], spare1, 1);
	cardlib->discard(spare2, spare1, 1);
}

deal()
{
	cardlib->shuffle(spare1);

	for (i := 0; i < 7; i++) {
		spare1.transfer((0, i + 1), sevens[i], 0);
		cardlib->setface(sevens[i].children[i], 1);
	}

}

newbutton(cmd, text: string): ref Object
{
	but := game.newobject(nil, ~0, "widget button");
	but.setattr("command", cmd, ~0);
	but.setattr("text", text, ~0);
	return but;
}

newstack(parent: ref Object, spec: Stackspec, stype: string): ref Object
{
	stack := cardlib->newstack(parent, nil, spec);
	stack.setattr("type", stype, 0);
	stack.setattr("actions", "click", ~0);
	return stack;
}

getcard(card: ref Object): Card
{
	c := cardlib->getcard(card);
	c.number = rank[c.number];
	return c;
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
