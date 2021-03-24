implement Gamemodule;

include "sys.m";
	sys: Sys;
include "draw.m";
include "../gamesrv.m";
	gamesrv: Gamesrv;
	Attributes, Range, Object, Game, Player: import gamesrv;

stderr: ref Sys->FD;
game: ref Game;

Black, White, None: con iota;		# first two must be 0 and 1.
N: con 8;

boardobj: ref Object;
board:	array of array of int;
pieces:	array of int;
turn		:= None;
players	:= array[2] of ref Player;			# player ids of those playing
nplayers := 0;

Point: adt {
	x, y: int;
	add: fn(p: self Point, p1: Point): Point;
	inboard: fn(p: self Point): int;
};

clienttype(): string
{
	return "othello";
}

init(g: ref Game, srvmod: Gamesrv): string
{
	sys = load Sys Sys->PATH;
	game = g;
	gamesrv = srvmod;
	boardobj = game.newobject(nil, ~0, nil);
	return nil;
}

join(p: ref Player): string
{
	if (nplayers < 2) {
		players[nplayers++] = p;
		if (nplayers == 2)
			startgame();
	}
	return nil;
}

leave(p: ref Player)
{
	if (turn != None && (p == players[Black] || p == players[White]))
		gameover();
}

startgame()
{
	boardobj.setattr("players", string players[Black].id + " " + string players[White].id, ~0);
	board = array[N] of {* => array[N] of {* => None}};
	pieces = array[2] of {* => 0};
	for (ps := (Black, (3, 3)) :: (Black, (4, 4)) :: (White, (3, 4)) :: (White, Point(4, 3)) :: nil;
			ps != nil;
			ps = tl ps) {
		(colour, p) := hd ps;
		setpiece(colour, p);
	}
	turn = Black;
	boardobj.setattr("turn", string Black, ~0);
}

gameover()
{
	turn = None;
	boardobj.setattr("winner", string winner(), ~0);
	boardobj.setattr("turn", string turn, ~0);
}

command(player: ref Player, cmd: string): string
{
	e := ref Sys->Exception;
	if (sys->rescue("parse:*", e) == Sys->EXCEPTION) {
		sys->rescued(Sys->ONCE, nil);
		return e.name[6:];
	}
	(n, toks) := sys->tokenize(cmd, " \n");
	assert(n > 0, "unknown command");

	case hd toks {
	"move" =>
		assert(n == 3, "bad command usage");
		assert(nplayers >= 2, "game not yet in progress");
		assert(turn != None, "game has finished");
		assert(player == players[White] || player == players[Black], "you are not playing");
		assert(player == players[turn], "it is not your turn");
		p := Point(int hd tl toks, int hd tl tl toks);
		assert(p.x >= 0 && p.x < N && p.y >= 0 && p.y < N, "invalid move position");
		assert(board[p.x][p.y] == None, "position is already occupied");
		assert(newmove(turn, p, 1), "cannot move there");

		turn = reverse(turn);
		if (!canplay()) {
			turn = reverse(turn);
			if (!canplay())
				gameover();
		}
		boardobj.setattr("turn", string turn, ~0);
		return nil;
	}
	sys->fprint(stderr, "othello: unknown client command '%s'\n", hd toks);
	return "who knows";
}

Directions := array[] of {Point(0, 1), (1, 1), (1, 0), (1, -1), (0, -1), (-1, -1), (-1, 0), (-1, 1)};

setpiece(colour: int, p: Point)
{
	v := board[p.x][p.y];
	if (v != None)
		pieces[v]--;
	board[p.x][p.y] = colour;
	pieces[colour]++;
	boardobj.setattr(pt2attr(p), string colour, ~0);
}

pt2attr(pt: Point): string
{
	s := "  ";
	s[0] = pt.x + 'a';
	s[1] = pt.y + 'a';
	return  s;
}

# player colour has tried to place a piece at mp.
# return -1 if it's an illegal move, 0 otherwise.
# (in which case appropriate updates are sent out all round).
# if update is 0, just check for the move's validity
# (no change to the board, no updates sent)
newmove(colour: int, mp: Point, update: int): int
{
	totchanged := 0;
	for (i := 0; i < len Directions; i++) {
		d := Directions[i];
		n := 0;
		for (p := mp.add(d); p.inboard(); p = p.add(d)) {
			n++;
			if (board[p.x][p.y] == colour || board[p.x][p.y] == None)
				break;
		}
		if (p.inboard() && board[p.x][p.y] == colour && n > 1) {
			if (!update)
				return 1;
			totchanged += n - 1;
			for (p = mp.add(d); --n > 0; p = p.add(d))
				setpiece(reverse(board[p.x][p.y]), p);
		}
	}
	if (totchanged > 0) {
		setpiece(colour, mp);
		return 1;
	}
	return 0;
}

# who has most pieces?
winner(): int
{
	if (pieces[White] > pieces[Black])
		return White;
	else if (pieces[Black] > pieces[White])
		return Black;
	return None;
}

# is there any possible legal move?
canplay(): int
{
	for (y := 0; y < N; y++)
		for (x := 0; x < N; x++)
			if (board[x][y] == None && newmove(turn, (x, y), 0))
				return 1;
	return 0;
}

reverse(colour: int): int
{
	if (colour == None)
		return None;
	return !colour;
}

Point.add(p: self Point, p1: Point): Point
{
	return (p.x + p1.x, p.y + p1.y);
}

Point.inboard(p: self Point): int
{
	return p.x >= 0 && p.x < N && p.y >= 0 && p.y < N;
}

assert(b: int, err: string)
{
	if (b == 0)
		sys->raise("parse:" + err);
}
