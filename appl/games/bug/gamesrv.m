Gamesrv: module
{
	Attribute: adt {
		name:	string;
		val:		string;
		visibility:	int;			# set of players that can see attr
		needupdate:	int;		# set of players that have not got an update queued
	};
	
	Attributes: adt {
		a:		array of list of ref Attribute;
		set:		fn(attr: self ref Attributes, name, val: string, vis: int): (int, ref Attribute);
		get:		fn(attr: self ref Attributes, name: string): ref Attribute;
		new:		fn(): ref Attributes;
	};
	
	Range: adt {
		start:		int;
		end:		int;
	};
	
	Object: adt {
		id:		int;
		attrs:		ref Attributes;
		visibility:	int;
		parentid:	int;
		children:	cyclic array of ref Object;		# not actually cyclic
		gameid:	int;
		objtype:	string;
	
		transfer:		fn(o: self ref Object, r: Range, dst: ref Object, i: int);
		setvisibility:	fn(o: self ref Object, visibility: int);
		setattrvisibility:	fn(o: self ref Object, name: string, visibility: int);
		setattr:		fn(o: self ref Object, name: string, val: string, vis: int);
		getattr:		fn(o: self ref Object, name: string): string;
		delete:		fn(o: self ref Object);
		deletechildren:	fn(o: self ref Object, r: Range);
	};
	
	# this might also be known as a "group", as there's nothing
	# inherently game-like about it; it's just a group of players
	# mutually creating and manipulating objects.
	Game: adt {
		name:	string;
		objects:	array of ref Object;
		freelist:	list of int;
		mod:	Gamemodule;
		id:		int;
		fileid:	int;
		playerids:	int;	# set of allocated player ids
	
		newobject:	fn(game: self ref Game, parent: ref Object, visibility: int, objtype: string): ref Object;
		action:		fn(game: self ref Game, cmd: string,
						objs: list of int, rest: string, whoto: int);
		show:		fn(game: self ref Game, player: ref Player);
		player:	fn(game: self ref Game, id: int): ref Player;
	};
	
	# a Player is involved in one game only
	Player: adt {
		id:		int;
		gameid:	int;
		clientid:	int;
		obj2ext:	array of int;
		ext2obj:	array of ref Object;
		freelist:	list of int;

		ext:		fn(player: self ref Player, id: int): int;
		obj:		fn(player: self ref Player, id: int): ref Object;
		hangup:	fn(player: self ref Player);
		name:	fn(player: self ref Player): string;
	};
	init:   fn(ctxt: ref Draw->Context, argv: list of string);
	rand:	fn(n: int): int;
};

Gamemodule: module {
	clienttype:	fn(): string;
	init:			fn(game: ref Gamesrv->Game, srvmod: Gamesrv): string;
	command:	fn(player: ref Gamesrv->Player, e: string): string;
	join:			fn(player: ref Gamesrv->Player): string;
	leave:		fn(player: ref Gamesrv->Player);
};
