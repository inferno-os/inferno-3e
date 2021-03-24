implement Cardlib;
include "sys.m";
	sys: Sys;
include "draw.m";
include "../gamesrv.m";
	gamesrv: Gamesrv;
	Attributes, Range, Object, Game, Player, rand: import gamesrv;
include "cardlib.m";

MAXPLAYERS: con 4;

Layobject: adt {
	lay:		ref Object;
	name:	string;
	packopts:		int;
	pick {
	Obj =>
		obj:		ref Object;		# nil if it's a frame
	Frame =>
		facing:	int;				# only valid if for frames
	}
};

game:	ref Game;
cplayers: array of ref Cplayer;
cpids := array[8] of list of ref Cplayer;
layouts := array[17] of list of (string, ref Layout, ref Layobject);
maxlayid := 1;
cplayerid := 1;

init(g: ref Game, mod: Gamesrv)
{
	sys = load Sys Sys->PATH;
	game = g;
	gamesrv = mod;
}

Cplayer.join(player: ref Player, ord: int): ref Cplayer
{
	cplayers = (array[len cplayers + 1] of ref Cplayer)[0:] = cplayers;
	if (ord == -1)
		ord = len cplayers - 1;
	else {
		cplayers[ord + 1:] = cplayers[ord:len cplayers - 1];
		for (i := ord + 1; i < len cplayers; i++)
			cplayers[i].ord = i;
	}
	cp := cplayers[ord] = ref Cplayer(ord, cplayerid++, player, nil, nil, nil);
	cp.obj = game.newobject(nil, ~0, "player");
	cp.obj.setattr("id", string cp.id, ~0);
	cp.obj.setattr("name", player.name(), ~0);
	cp.obj.setattr("you", string cp.id, 1<<player.id);
	cp.obj.setattr("gametitle", game.name, ~0);
	cp.layout = newlayout(cp.obj, 1 << player.id);
	cp.sel = ref Selection(nil, cp.id, 1, (0, 0), nil);

	idx := cp.id % len cpids;
	cpids[idx] = cp :: cpids[idx];
	return cp;
}

Cplayer.find(p: ref Player): ref Cplayer
{
	for (i := 0; i < len cplayers; i++)
		if (cplayers[i].p == p)
			return cplayers[i];
	return nil;
}

Cplayer.index(ord: int): ref Cplayer
{
	if (ord < 0 || ord >= len cplayers)
		return nil;
	return cplayers[ord];
}

Cplayer.next(cp: self ref Cplayer, fwd: int): ref Cplayer
{
	if (!fwd)
		return cp.prev(1);
	x := cp.ord + 1;
	if (x >= len cplayers)
		x = 0;
	return cplayers[x];
}

Cplayer.prev(cp: self ref Cplayer, fwd: int): ref Cplayer
{
	if (!fwd)
		return cp.next(1);
	x := cp.ord - 1;
	if (x < 0)
		x = len cplayers - 1;
	return cplayers[x];
}
	
Cplayer.leave(cp: self ref Cplayer)
{
	ord := cp.ord;
	cplayers[ord] = nil;
	cplayers[ord:] = cplayers[ord + 1:];
	cplayers[len cplayers - 1] = nil;
	cplayers = cplayers[0:len cplayers - 1];
	for (i := ord; i < len cplayers; i++)
		cplayers[i].ord = i;
	cp.obj.delete();
	dellayout(cp.layout);
	cp.layout = nil;
	idx := cp.id % len cpids;
	l: list of ref Cplayer;
	ll := cpids[idx];
	for (; ll != nil; ll = tl ll)
		if (hd ll != cp)
			l = hd ll :: l;
	cpids[idx] = l;
	cp.ord = -1;
}

id2cp(id: int): ref Cplayer
{
	for (l := cpids[id % len cpids]; l != nil; l = tl l)
		if ((hd l).id == id)
			return hd l;
	return nil;
}

newstack(parent: ref Object, owner: ref Player, spec: Stackspec): ref Object
{
	vis := ~0;
	if (spec.conceal) {
		vis = 0;
		if (owner != nil)
			vis |= 1<<owner.id;
	}
	o := game.newobject(parent, vis, "stack");
	o.setattr("maxcards", string spec.maxcards, ~0);
	o.setattr("style", spec.style, ~0);

	# XXX provide some means for this to contain the player's name?
	o.setattr("title", spec.title, ~0);
	return o;
}

makecards(deck: ref Object, r: Range, rear: string)
{
	for (i := r.start; i < r.end; i++) {
		card := game.newobject(deck, 0, "card");
		card.setattr("face", "0", ~0);
		card.setattr("number", string i, 0);
		if (rear != nil)
			card.setattr("rear", rear, ~0);
	}
}

# deal n cards to each player, if possible.
# deal in chunks for efficiency.
# if accuracy is required (e.g. dealing from an unshuffled
# deck containing known cards) then this'll have to change.
deal(deck: ref Object, n: int, stacks: array of ref Object, first: int)
{
	ncards := len deck.children;
	ord := 0;
	perplayer := n;
	leftover := 0;
	if (n * len stacks > ncards) {
		# if trying to deal more cards than we've got,
		# deal all that we've got, distributing the remainder fairly.
		perplayer = ncards / len stacks;
		leftover = ncards % len stacks;
	}
	for (i := 0; i < len stacks; i++) {
		n := perplayer;
		if (leftover > 0) {
			n++;
			leftover--;
		}
		priv := stacks[(first + i) % len stacks];
		deck.transfer((ncards - n, ncards), priv, len priv.children);
		priv.setattr("n", string (int priv.getattr("n") + n), ~0);
		# make cards visible to player
		for (i := len priv.children - n; i < len priv.children; i++)
			setface(priv.children[i], 1);
	
		ncards -= n;
	}
}

setface(card: ref Object, face: int)
{
	# XXX check parent stack style and if it's a pile,
	# only expose a face up card at the top.

	card.setattr("face", string face, ~0);
	if (face)
		card.setattrvisibility("number", ~0);
	else
		card.setattrvisibility("number", 0);
}

nplayers(): int
{
	return len cplayers;
}

defaultrank := array[13] of {12, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11};

# XXX should take a "rank" array so that we can cope with custom
# card ranking
Trick.new(pile: ref Object, trumps: int, hands: array of ref Object, rank: array of int): ref Trick
{
	t := ref Trick;
	t.highcard = t.startcard = Card(-1, -1, -1);
	t.winner = -1;
	t.trumps = trumps;
	t.pile = pile;
	t.hands = hands;
	if (rank == nil)
		rank = defaultrank;
	t.rank = rank;
	return t;
}

Trick.play(t: self ref Trick, ord, idx: int): string
{
	stack := t.hands[ord];
	if (idx < 0 || idx >= len stack.children)
		return "invalid card to play";

	c := getcard(stack.children[idx]);
	c.number = t.rank[c.number];
	if (len t.pile.children == 0) {
		t.winner = ord;
		t.startcard = t.highcard = c;
	} else {
		if (c.suit != t.startcard.suit) {
			if (containssuit(stack, t.startcard.suit))
				return "you must play the suit that was led";
			if (c.suit == t.trumps &&
					(t.highcard.suit != t.trumps ||
					c.number > t.highcard.number)) {
				t.highcard = c;
				t.winner = ord;
			}
		} else if (c.suit == t.highcard.suit && c.number > t.highcard.number) {
			t.highcard = c;
			t.winner = ord;
		}
	}

	stack.transfer((idx, idx + 1), t.pile, len t.pile.children);
	stack.setattr("n", string (int stack.getattr("n") - 1), ~0);
	return nil;
}

containssuit(stack: ref Object, suit: int): int
{
	ch := stack.children;
	n := len ch;
	for (i := 0; i < n; i++)
		if (getcard(ch[i]).suit == suit)
			return 1;
	return 0;
}

getcard(card: ref Object): Card
{
	c: Card;
	n := int card.getattr("number");
	(suit, num) := (n % 4, n / 4);
	return Card(suit, num, int card.getattr("face"));
}

getcards(stack: ref Object): array of Card
{
	a := array[len stack.children] of Card;
	for (i := 0; i < len a; i++)
		a[i] = getcard(stack.children[i]);
	return a;
}

discard(stk, pile: ref Object, facedown: int)
{
	n := len stk.children;
	if (facedown)
		for (i := 0; i < n; i++)
			setface(stk.children[i], 0);
	stk.transfer((0, n), pile, len pile.children);
}

# shuffle children into a random order.  first we make all the children
# invisible (which will cause them to be deleted in the clients) then
# shuffle to our heart's content, and make visible again...
shuffle(o: ref Object)
{
	ovis := o.visibility;
	o.setvisibility(0);
	a := o.children;
	n := len a;
	for (i := 0; i < n; i++) {
		j := i + rand(n - i);
		(a[i], a[j]) = (a[j], a[i]);
	}
	o.setvisibility(ovis);
}

# reverse and flip all cards in stack.
flip(stack: ref Object)
{
	ovis := stack.visibility;
	stack.setvisibility(0);
	a := stack.children;
	(n, m) := (len a, len a / 2);
	for (i := 0; i < m; i++) {
		j := n - i - 1;
		(a[i], a[j]) = (a[j], a[i]);
	}
	for (i = 0; i < n; i++)
		setface(a[i], !int a[i].getattr("face"));
	stack.setvisibility(ovis);
}

selection(stack: ref Object): ref Selection
{
	if ((owner := stack.getattr("owner")) != nil &&
			(cp := id2cp(int owner)) != nil)
		return cp.sel;
	return nil;
}

Selection.set(sel: self ref Selection, stack: ref Object)
{
	if (stack == sel.stack)
		return;
	if (stack != nil) {
		oldowner := stack.getattr("owner");
		if (oldowner != nil) {
			oldcp := id2cp(int oldowner);
			if (oldcp != nil)
				oldcp.sel.set(nil);
		}
	}
	if (sel.stack != nil)
		sel.stack.setattr("owner", nil, ~0);
	sel.stack = stack;
	sel.isrange = 1;
	sel.r = (0, 0);
	sel.idxl = nil;
	setsel(sel);
}

Selection.setexcl(sel: self ref Selection, stack: ref Object): int
{
	if (stack != nil && (oldowner := stack.getattr("owner")) != nil)
		if ((cp := id2cp(int oldowner)) != nil && !cp.sel.isempty())
			return 0;
	sel.set(stack);
	return 1;
}

Selection.owner(sel: self ref Selection): ref Cplayer
{
	return id2cp(sel.ownerid);
}

Selection.setrange(sel: self ref Selection, r: Range)
{
	if (!sel.isrange) {
		sel.idxl = nil;
		sel.isrange = 1;
	}
	sel.r = r;
	setsel(sel);
}

Selection.addindex(sel: self ref Selection, i: int)
{
	if (sel.isrange) {
		sel.r = (0, 0);
		sel.isrange = 0;
	}
	ll: list of int;
	for (l := sel.idxl; l != nil; l = tl l) {
		if (hd l >= i)
			break;
		ll = hd l :: ll;
	}
	if (l != nil && hd l == i)
		return;
	l = i :: l;
	for (; ll != nil; ll = tl ll)
		l = hd ll :: l;
	sel.idxl = l;
	setsel(sel);
}

Selection.delindex(sel: self ref Selection, i: int)
{
	if (sel.isrange) {
		sys->print("cardlib: delindex from range-type selection\n");
		return;
	}
	ll: list of int;
	for (l := sel.idxl; l != nil; l = tl l) {
		if (hd l == i) {
			l = tl l;
			break;
		}
		ll = hd l :: ll;
	}
	for (; ll != nil; ll = tl ll)
		l = hd ll :: l;
	sel.idxl = l;
	setsel(sel);
}

Selection.isempty(sel: self ref Selection): int
{
	if (sel.stack == nil)
		return 1;
	if (sel.isrange)
		return sel.r.start == sel.r.end;
	return sel.idxl == nil;
}

Selection.isset(sel: self ref Selection, index: int): int
{
	if (sel.isrange)
		return index >= sel.r.start && index < sel.r.end;
	for (l := sel.idxl; l != nil; l = tl l)
		if (hd l == index)
			return 1;
	return 0;
}

Selection.transfer(sel: self ref Selection, dst: ref Object, index: int)
{
	if (sel.isempty())
		return;
	src := sel.stack;
	if (sel.isrange) {
		r := sel.r;
		sel.set(nil);
		src.transfer(r, dst, index);
	} else {
		if (sel.stack == dst) {
			sys->print("cardlib: cannot move multisel to same stack\n");
			return;
		}
		xl := l := sel.idxl;
		sel.set(nil);
		rl: list of Range;
		for (; l != nil; l = tl l) {
			r := Range(hd l, hd l);
			last := l;
			# concatenate adjacent items, for efficiency.
			for (l = tl l; l != nil; (last, l) = (l, tl l)) {
				if (hd l != r.end + 1)
					break;
				r.end = hd l;
			}
			rl = (r.start, r.end + 1) :: rl;
			l = last;
		}
		# do ranges in reverse, so that later ranges
		# aren't affected by earlier ones.
		if (index == -1)
			index = len dst.children;
		for (; rl != nil; rl = tl rl)
			src.transfer(hd rl, dst, index);
	}
}

setsel(sel: ref Selection)
{
	if (sel.stack == nil)
		return;
	s := "";
	if (sel.isrange) {
		if (sel.r.end > sel.r.start)
			s = string sel.r.start + " - " + string sel.r.end;
	} else {
		if (sel.idxl != nil) {
			s = string hd sel.idxl;
			for (l := tl sel.idxl; l != nil; l = tl l)
				s += " " + string hd l;
		}
	}
	if (s != nil)
		sel.stack.setattr("owner", string sel.owner().id, ~0);
	else
		sel.stack.setattr("owner", nil, ~0);
	vis := 1 << sel.owner().p.id;
	sel.stack.setattr("sel", s, vis);
	sel.stack.setattrvisibility("sel", vis);
}

newlayout(parent: ref Object, vis: int): ref Layout
{
	l := ref Layout(game.newobject(parent, vis, "layout"));
	x := strhash(nil, len layouts);
	layobj := ref Layobject.Frame(nil, "", dTOP|EXPAND|FILLX|FILLY, dTOP);
	layobj.lay = game.newobject(l.lay, ~0, "layframe");
	layobj.lay.setattr("opts", packopts2s(layobj.packopts), ~0);
	layouts[x] = (nil, l, layobj) :: layouts[x];
#	sys->print("[%d] => ('%s', %ux, %ux) (new layout)\n", x, "", l, layobj);
	return l;
}

addlayframe(name, parent: string, layout: ref Layout, packopts: int, facing: int)
{
#	sys->print("addlayframe('%s', %ux, name: %s\n", parent, layout, name);
	addlay(parent, layout, ref Layobject.Frame(nil, name, packopts, facing));
}

addlayobj(name, parent: string, layout: ref Layout, packopts: int, obj: ref Object)
{
#	sys->print("addlayobj('%s', %ux, name: %s, obj %d\n", parent, layout, name, obj.id);
	addlay(parent, layout, ref Layobject.Obj(nil, name, packopts, obj));
}

addlay(parent: string, layout: ref Layout, layobj: ref Layobject)
{
	a := layouts;
	name := layobj.name;
	x := strhash(name, len a);
	added := 0;
	for (nl := a[strhash(parent, len a)]; nl != nil; nl = tl nl) {
		(s, lay, parentlay) := hd nl;
		if (s == parent && (layout == nil || layout == lay)) {
			pick p := parentlay {
			Obj =>
				sys->fprint(sys->fildes(2),
					"cardlib: cannot add layout to non-frame: %d\n", p.obj.id);
			Frame =>
				nlayobj := copylayobj(layobj);
				nlayobj.packopts = packoptsfacing(nlayobj.packopts, p.facing);
				o: ref Object;
				pick lo := nlayobj {
				Obj =>
					o = game.newobject(p.lay, ~0, "layobj");
					id := lo.obj.getattr("layid");
					if (id == nil) {
						id = string maxlayid++;
						lo.obj.setattr("layid", id, ~0);
					}
					o.setattr("layid", id, ~0);
				Frame =>
					o = game.newobject(p.lay, ~0, "layframe");
					lo.facing = (lo.facing + p.facing) % 4;
				}
				o.setattr("opts", packopts2s(nlayobj.packopts), ~0);
				nlayobj.lay = o;
				if (name != nil)
					a[x] = (name, lay, nlayobj) :: a[x];
				added++;
			}
		}
	}
	if (added == 0)
		sys->print("no parent found, adding '%s', parent '%s', layout %ux\n",
			layobj.name, parent, layout);
#	sys->print("%d new entries\n", added);
}

maketable(parent: string)
{
	# make a table for all current players.
	plcount := len cplayers;
	packopts := table[plcount];
	for (i := 0; i < plcount; i++) {
		layout := cplayers[i].layout;
		for (j := 0; j < len packopts; j++) {
			(ord, outer, inner, facing) := packopts[j];
			name := "public";
			if (ord != -1)
				name = "p" + string ((ord + i) % plcount);
			addlayframe("@" + name, parent, layout, outer, dTOP);
			addlayframe(name, "@" + name, layout, inner, facing);
		}
	}
}

table := array[] of {
	0 =>	array[] of {
		(-1, dTOP|EXPAND, dBOTTOM, dTOP),
	},
	1 => array [] of {
		(0, dBOTTOM|FILLX, dBOTTOM, dTOP),
		(-1, dTOP|EXPAND, dBOTTOM, dTOP),
	},
	2 => array[] of {
		(0, dBOTTOM|FILLX, dBOTTOM, dTOP),
		(1, dTOP|FILLX, dTOP, dBOTTOM),
		(-1, dTOP|EXPAND, dBOTTOM, dTOP)
	},
	3 => array[] of {
		(2, dRIGHT|FILLY, dRIGHT, dLEFT),
		(0, dBOTTOM|FILLX, dBOTTOM, dTOP),
		(1, dTOP|FILLX, dTOP, dBOTTOM),
		(-1, dRIGHT|EXPAND, dBOTTOM, dTOP)
	},
	4 => array[] of {
		(3, dLEFT|FILLY, dLEFT, dRIGHT),
		(2, dRIGHT|FILLY, dRIGHT, dLEFT),
		(0, dBOTTOM|FILLX, dBOTTOM, dTOP),
		(1, dTOP|FILLX, dTOP, dBOTTOM),
		(-1, dRIGHT|EXPAND, dBOTTOM, dTOP)
	},
};

dellay(name: string, layout: ref Layout)
{
	a := layouts;
	x := strhash(name, len a);
	rl: list of (string, ref Layout, ref Layobject);
	for (nl := a[x]; nl != nil; nl = tl nl) {
		(s, lay, layobj) := hd nl;
		if (s != name || (layout != nil && layout != lay))
			rl = hd nl :: rl;
	}
	a[x] = rl;
}

dellayout(layout: ref Layout)
{
	for (i := 0; i < len layouts; i++) {
		ll: list of (string, ref Layout, ref Layobject);
		for (nl := layouts[i]; nl != nil; nl = tl nl) {
			(s, lay, layobj) := hd nl;
			if (lay != layout)
				ll = hd nl :: ll;
		}
		layouts[i] = ll;
	}
}

copylayobj(obj: ref Layobject): ref Layobject
{
	pick o := obj {
	Frame =>
		return ref *o;
	Obj =>
		return ref *o;
	}
	return nil;
}

packoptsfacing(opts, facing: int): int
{
	if (facing == dTOP)
		return opts;
	nopts := 0;

	# 4 directions
	nopts |= (facing + (opts & dMASK)) % 4;

	# 2 orientations
	nopts |= ((facing + ((opts & oMASK) >> oSHIFT)) % 4) << oSHIFT;

	# 8 anchorpoints (+ centre)
	a := (opts & aMASK);
	if (a != aCENTRE)
		a = ((((a >> aSHIFT) - 1 + facing * 2) % 8) + 1) << aSHIFT;
	nopts |= a;

	# two fill options
	if (facing % 2) {
		if (opts & FILLX)
			nopts |= FILLY;
		if (opts & FILLY)
			nopts |= FILLX;
	} else
		nopts |= (opts & (FILLX | FILLY));

	nopts |= (opts & EXPAND);
	return nopts;
}

# these arrays are dependent on the ordering of
# the relevant constants defined in cardlib.m

sides := array[] of {"top", "left", "bottom", "right"};
anchors := array[] of {"n", "nw", "w", "sw", "s", "se", "e", "ne", "centre"};
orientations := array[] of {"right", "up", "left", "down"};

packopts2s(opts: int): string
{
	s := orientations[(opts & oMASK) >> oSHIFT] +
			" -side " + sides[opts & dMASK];
	if ((opts & aMASK) != aCENTRE)
		s += " -anchor " + anchors[((opts & aMASK) >> aSHIFT) - 1];
	if (opts & EXPAND)
		s += " -expand 1";
	if ((opts & (FILLX | FILLY)) == (FILLX | FILLY))
		s += " -fill both";
	else if (opts & FILLX)
		s += " -fill x";
	else if (opts & FILLY)
		s += " -fill y";
	return s;
}

assert(b: int, err: string)
{
	if (b == 0)
		sys->raise("parse:" + err);
}

# from Aho Hopcroft Ullman
strhash(s: string, n: int): int
{
	h := 0;
	m := len s;
	for(i := 0; i<m; i++){
		h = 65599 * h + s[i];
	}
	return (h & 16r7fffffff) % n;
}
