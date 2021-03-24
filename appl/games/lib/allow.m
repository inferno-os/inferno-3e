Allow: module {
	PATH:	con "/dis/games/lib/allow.dis";
	init:		fn(g: ref Game, srvmod: Gamesrv);
	add:		fn(tag: int, player: ref Player, action: string);
	del:		fn(tag: int, player: ref Player);
	action:	fn(player: ref Player, cmd: string): (string, int, list of string);
};
