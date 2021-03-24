Cardlib: module {
	PATH:		con "/dis/games/lib/cardlib.dis";

	Layout: adt {
		lay:			ref Object;		# the actual layout object
	};

	Stackspec: adt {
		style:	string;
		maxcards:	int;
		conceal:	int;
		title:		string;
	};

	Card: adt {
		suit:		int;
		number:	int;
		face:		int;
	};

	Trick: adt {
		trumps:	int;
		startcard:	Card;
		highcard:	Card;
		winner:	int;
		pile:		ref Object;
		hands:	array of ref Object;
		rank:		array of int;

		new:		fn(pile: ref Object, trumps: int,
					hands: array of ref Object, rank: array of int): ref Trick;
		play:		fn(t: self ref Trick, ord, idx: int): string;
	};

	# a player currently playing
	Cplayer: adt {
		ord:		int;
		id:		int;
		p:		ref Player;
		obj:		ref Object;
		layout:	ref Layout;
		sel:		ref Selection;

		join:		fn(p: ref Player, ord: int): ref Cplayer;
		index:	fn(ord: int): ref Cplayer;
		find:		fn(p: ref Player): ref Cplayer;
		leave:	fn(cp: self ref Cplayer);
		next:		fn(cp: self ref Cplayer, fwd: int): ref Cplayer;
		prev:		fn(cp: self ref Cplayer, fwd: int): ref Cplayer;
	};

	Selection: adt {
		stack:	ref Object;
		ownerid:	int;
		isrange:	int;
		r:		Range;
		idxl:		list of int;

		set:		fn(sel: self ref Selection, stack: ref Object);
		setexcl:	fn(sel: self ref Selection, stack: ref Object): int;
		setrange:	fn(sel: self ref Selection, r: Range);
		addindex:	fn(sel: self ref Selection, i: int);
		delindex:	fn(sel: self ref Selection, i: int);
		isempty:	fn(sel: self ref Selection): int;
		isset:		fn(sel: self ref Selection, index: int): int;
		transfer:	fn(sel: self ref Selection, dst: ref Object, index: int);
		owner:	fn(sel: self ref Selection): ref Cplayer;
	};

	selection:	fn(stack: ref Object): ref Selection;

	# pack and facing directions (clockwise by face direction)
	dTOP, dLEFT, dBOTTOM, dRIGHT: con iota;
	dMASK: con 7;
	
	# anchor positions
	aSHIFT: con 4;
	aMASK: con 16rf0;
	aCENTRE, aUPPERCENTRE, aUPPERLEFT, aCENTRELEFT,
		aLOWERLEFT, aLOWERCENTRE, aLOWERRIGHT,
		aCENTRERIGHT, aUPPERRIGHT: con iota << aSHIFT;
	
	# orientations
	oMASK: con 16rf00;
	oSHIFT: con 8;
	oRIGHT, oUP, oLEFT, oDOWN: con iota << oSHIFT;

	EXPAND: con 16r1000;
	FILLX: con 16r2000;
	FILLY: con 16r4000;

	CLUBS, DIAMONDS, HEARTS, SPADES: con iota;

	addlayframe:	fn(name: string, parent: string, layout: ref Layout, packopts: int, facing: int);
	addlayobj:	fn(name: string, parent: string, layout: ref Layout, packopts: int, obj: ref Object);
	dellay:		fn(name: string, layout: ref Layout);


	newstack:		fn(parent: ref Object, p: ref Player, spec: Stackspec): ref Object;

	init:			fn(game: ref Game, gamesrv: Gamesrv);
	newlayout:	fn(parent: ref Object, vis: int): ref Layout;
	makecards:	fn(stack: ref Object, r: Range, rear: string);
	maketable:	fn(parent: string);
	deal:			fn(stack: ref Object, n: int, stacks: array of ref Object, first: int);
	shuffle:		fn(stack: ref Object);

	getcard:		fn(card: ref Object): Card;
	getcards:		fn(stack: ref Object): array of Card;
	discard:		fn(stk, pile: ref Object, facedown: int);
	setface:		fn(card: ref Object, face: int);

	flip:			fn(stack: ref Object);

	nplayers:		fn(): int;
};
