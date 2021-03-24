implement ttt;

include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;
	Point, Rect, Image, Font, Context, Screen, Display: import draw;
include "tk.m";
	tk: Tk;
	Toplevel: import tk;
include "wmlib.m";
	wmlib: Wmlib;
include "daytime.m";
	daytime: Daytime;
include "rand.m";
	rand: Rand;

stderr: ref Sys->FD;

ttt: module 
{
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

mainwin: ref Toplevel;

brdr: Rect;

brdx, brdy : int;

BOARD_SIZE: con 3;
INTERNAL_SIZE: con BOARD_SIZE+2;	# internal board is 2 larger than visible board

NOUGHT, CROSS, BLANK, FINISHED: con (1<<iota);

black, white: ref Image;

Cell: adt {
	pos: int;
};

board: array of array of Cell;

init(ctxt: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	tk = load Tk Tk->PATH;
	wmlib = load Wmlib Wmlib->PATH;
	daytime = load Daytime Daytime->PATH;
	rand = load Rand Rand->PATH;

	stderr = sys->fildes(2);
	rand->init(daytime->now());
	daytime = nil;

	if(ctxt == nil)
		fatal("wm not running");
	wmlib->init();
	(win, wmcmd) := wmlib->titlebar(ctxt.screen, "", "tic tac toe", Wmlib->Hide);
	mainwin = win;
	sys->pctl(Sys->NEWPGRP, nil);
	cmdch := chan of string;
	tk->namechan(win, cmdch, "cmd");
	mvch := chan of (int, int);
	display_board();
	pid := -1;
	init_board();
	for (;;) {
		alt {		

			c := <- wmcmd =>	# wm commands
				case c {
					"exit" =>
						if(pid != -1)
							kill(pid);
						exit;
					* =>
						wmlib->titlectl(win, c);
						brdr = canvposn(mainwin);
				}
			c := <- cmdch =>	# tk commands
				(n, toks) := sys->tokenize(c, " ");
				case hd toks {
					"b" =>
						#sys->fprint(stderr, "getting here");
						x := int hd tl toks;
						y := int hd tl tl toks;
						make_move(x,y);
						cmd(mainwin, "update");
					"restart" =>
						init_board();
						reset_display();
					* =>
						sys->fprint(stderr, "%s\n", c);
				}
			}
	}
}

display_board() 
{
	i, j: int;
	for(i = 0; i < len win_config; i++)
	{
		cmd(mainwin, win_config[i]);
	}

	for (i = 0; i < len win_config2; i++)
		cmd (mainwin, win_config2[i]);

	brdr = canvposn(mainwin);

	black = mainwin.image.display.color(Draw->Black);
	white = mainwin.image.display.color(Draw->White);
	
	brdx = brdr.dx()/BOARD_SIZE;
	brdy = brdr.dy()/BOARD_SIZE;
	
	mainwin.image.draw(brdr, white, mainwin.image.display.ones, (0,0));

	for(i=1; i<BOARD_SIZE; i++)
	{
		drawLine(lmap(i,0), lmap(i, BOARD_SIZE));
		drawLine(lmap(0,i), lmap(BOARD_SIZE, i));
	}

	fiximage(mainwin);
}

lmap(m, n: int): Point
{
	return brdr.min.add((m*brdx, n*brdy));

}

canvposn(win: ref Toplevel):Rect
{
	r: Rect;
	r.min.x = int cmd(mainwin, ".c cget -actx") + int cmd(win, ".c cget -bd");
	r.min.y = int cmd(mainwin, ".c cget -acty") + int cmd(win, ".c cget -bd");
	r.max.x = r.min.x + int cmd(mainwin, ".c cget -actwidth");
	r.max.y = r.min.y + int cmd(mainwin, ".c cget -actheight");
	return r;

}

drawLine(p0,p1:Point)
{
	mainwin.image.line(p0,p1, Draw->Endsquare, Draw->Endsquare, 0, mainwin.image.display.ones, (0,0));
}

fiximage(win: ref Toplevel)
{
	r := canvposn(win);
	displ := win.image.display;
	cmd(win, ".c configure -width [.c cget -actwidth]");
	cmd(win, ".c configure -width [.c cget -actheight]");
	saveimage := displ.newimage(r, displ.image.ldepth, 0 , Draw->White);
	saveimage.draw(r, win.image, displ.ones, r.min);
	tk->imageput(win, "saveimage", saveimage, nil);
	cmd(win, ".c coords saveimage 0 0");
	cmd(win, "update");

}


drawNought(m, n: int)
{
	mainwin.image.fillellipse(cmap(m,n), 3*brdx/8, 3*brdy/8, black, (0,0));
	mainwin.image.fillellipse(cmap(m,n), 3*brdx/9, 3*brdy/9, white, (0,0));
}

drawCross(m, n: int)
{
	topL, topR, botL, botR, mid: Point;
	x1, x2, y1, y2: int;
	mid = cmap(m,n);
	x1 = mid.x;
	x2 = mid.x;
	y1 = mid.y;
	y2 = mid.y;
	x1 += 3*brdx/8;
	x2 -= 3*brdx/8;
	y1 += 3*brdx/8;
	y2 -= 3*brdx/8;
	 
	topL=(x2, y1);
	topR=(x1, y1);
	botL=(x2, y2);
	botR=(x1, y2);

	drawLine(topL, botR);
	drawLine(topR, botL);

}

cmap(m, n: int): Point
{
	return brdr.min.add((m*brdx-brdx/2, n*brdy-brdy/2));
}

reset_display()
{
	mainwin.image.draw(brdr, white, mainwin.image.display.ones, (0,0));
	for(i:=1; i<BOARD_SIZE; i++)
	{
		drawLine(lmap(i,0), lmap(i, BOARD_SIZE));
		drawLine(lmap(0,i), lmap(BOARD_SIZE, i));
	}
	cmd(mainwin, ".ft.l configure -text {  }");

	fiximage(mainwin);
}

init_board()
{
	i, j: int;
	board = array[INTERNAL_SIZE] of array of Cell;
	for (i = 0; i < INTERNAL_SIZE; i++)
		board[i] = array[INTERNAL_SIZE] of Cell;

	# initialize board
	for (i = 0; i < INTERNAL_SIZE; i++)
		for (j =0; j < INTERNAL_SIZE; j++) 
		{
			board[i][j].pos = BLANK;
		}

	cmd(mainwin, "update");
}

display_win()
{
	cmd(mainwin, ".ft.l configure -text {Congratulations - you win}");
}

display_lost()
{
	cmd(mainwin, ".ft.l configure -text {You have Lost}");
}

display_draw()
{
	cmd(mainwin, ".ft.l configure -text {It's a draw!}");
}

make_move(x, y :int)
{
	x = x/brdx+1;
	y= y/brdy+1;

	if (board[x][y].pos==BLANK)
	{
		drawNought(x,y);
		fiximage(mainwin);
		sys->sleep(500);
		board[x][y].pos=NOUGHT;
	
		won:=playerWon(NOUGHT);	
		if (won)
		{
			end_of_game();
			display_win();
			return;
		}
		placed := allMovesMade();
		if (placed==1)
		{
			display_draw();
		}
		else
		{
			makeCrossMove();
			won=playerWon(CROSS);
			if (won)
			{
				display_lost();
				end_of_game();
			}
		}
	}
}

# check to see if there are any remaining moves that can be made
allMovesMade():int
{
	allDone:=1;
	for (i:= 1; i <= BOARD_SIZE; i++)
		for (j :=1; j <= BOARD_SIZE; j++) 
		{
			if (board[i][j].pos == BLANK)
				allDone=0;
		}
	return allDone;
}

playerWon(player : int) : int
{
	playerWin:=0;
		
	if ((board[1][1].pos==player && board[1][2].pos==player && board[1][3].pos==player)
	|| (board[2][1].pos==player && board[2][2].pos==player && board[2][3].pos==player)
	|| (board[3][1].pos==player && board[3][2].pos==player && board[3][3].pos==player)
	|| (board[1][1].pos==player && board[2][2].pos==player && board[3][3].pos==player)
	|| (board[3][1].pos==player && board[2][2].pos==player && board[1][3].pos==player)
	|| (board[1][1].pos==player && board[2][1].pos==player && board[3][1].pos==player)
	|| (board[1][2].pos==player && board[2][2].pos==player && board[3][2].pos==player)
	|| (board[1][3].pos==player && board[2][3].pos==player && board[3][3].pos==player))
	{
		playerWin=1;
	}
	
	return playerWin;
}

makeCrossMove() 
{

	x,y:int;
	x=0;
	y=0;

	# first try to win	
	if ((board[1][1].pos==CROSS && board[1][2].pos==CROSS && board[1][3].pos==BLANK)
	|| (board[3][1].pos==CROSS && board[2][2].pos==CROSS && board[1][3].pos==BLANK)
	|| (board[3][3].pos==CROSS && board[2][3].pos==CROSS && board[1][3].pos==BLANK))
	{
		x = 1;
		y = 3;
	}
	else if ((board[2][1].pos==CROSS && board[2][2].pos==CROSS && board[2][3].pos==BLANK)
	|| (board[1][3].pos==CROSS && board[3][3].pos==CROSS && board[2][3].pos==BLANK))
	{
		x=2;
		y=3;
	}
	else if ((board[3][1].pos==CROSS && board[3][2].pos==CROSS && board[3][3].pos==BLANK)
	|| (board[1][3].pos==CROSS && board[2][3].pos==CROSS && board[3][3].pos==BLANK)
	|| (board[1][1].pos==CROSS && board[2][2].pos==CROSS && board[3][3].pos==BLANK))
	{
		x=3;
		y=3;
	}
	else if ((board[1][3].pos==CROSS && board[1][2].pos==CROSS && board[1][1].pos==BLANK)
	|| (board[3][3].pos==CROSS && board[2][2].pos==CROSS && board[1][1].pos==BLANK)
	|| (board[3][1].pos==CROSS && board[2][1].pos==CROSS && board[1][1].pos==BLANK))
	{
		x = 1;
		y = 1;
	}
	else if ((board[2][3].pos==CROSS && board[2][2].pos==CROSS && board[2][1].pos==BLANK)
	|| (board[1][1].pos==CROSS && board[3][1].pos==CROSS && board[2][1].pos==BLANK))
	{
		x=2;
		y=1;
	}
	else if ((board[1][1].pos==CROSS && board[2][1].pos==CROSS && board[3][1].pos==BLANK)
	|| (board[3][2].pos==CROSS && board[3][3].pos==CROSS && board[3][1].pos==BLANK)
	|| (board[1][3].pos==CROSS && board[2][2].pos==CROSS && board[3][1].pos==BLANK))
	{
		x=3;
		y=1;
	}
	else if ((board[2][2].pos==CROSS && board[3][2].pos==CROSS && board[1][2].pos==BLANK)
	|| (board[1][1].pos==CROSS && board[1][3].pos==CROSS && board[1][2].pos==BLANK))
	{
		x = 1;
		y = 2;
	}
	else if ((board[3][1].pos==CROSS && board[3][3].pos==CROSS && board[3][2].pos==BLANK)
	|| (board[1][2].pos==CROSS && board[2][2].pos==CROSS && board[3][2].pos==BLANK))
	{
		x=3;
		y=2;
	}
	else if ((board[1][1].pos==CROSS && board[3][3].pos==CROSS && board[2][2].pos==BLANK)
	|| (board[3][1].pos==CROSS && board[1][3].pos==CROSS && board[2][2].pos==BLANK)
	|| (board[2][1].pos==CROSS && board[2][3].pos==CROSS && board[2][2].pos==BLANK)
	|| (board[1][2].pos==CROSS && board[3][2].pos==CROSS && board[2][2].pos==BLANK))
	{
		x=2;
		y=2;
	}

	# try to block!!!
	else if ((board[1][1].pos==NOUGHT && board[1][2].pos==NOUGHT && board[1][3].pos==BLANK)
	|| (board[3][1].pos==NOUGHT && board[2][2].pos==NOUGHT && board[1][3].pos==BLANK)
	|| (board[3][3].pos==NOUGHT && board[2][3].pos==NOUGHT && board[1][3].pos==BLANK))
	{
		x = 1;
		y = 3;
	}
	else if ((board[2][1].pos==NOUGHT && board[2][2].pos==NOUGHT && board[2][3].pos==BLANK)
	|| (board[1][3].pos==NOUGHT && board[3][3].pos==NOUGHT && board[2][3].pos==BLANK))
	{
		x=2;
		y=3;
	}
	else if ((board[3][1].pos==NOUGHT && board[3][2].pos==NOUGHT && board[3][3].pos==BLANK)
	|| (board[1][3].pos==NOUGHT && board[2][3].pos==NOUGHT && board[3][3].pos==BLANK)
	|| (board[1][1].pos==NOUGHT && board[2][2].pos==NOUGHT && board[3][3].pos==BLANK))
	{
		x=3;
		y=3;
	}
	else if ((board[1][3].pos==NOUGHT && board[1][2].pos==NOUGHT && board[1][1].pos==BLANK)
	|| (board[3][3].pos==NOUGHT && board[2][2].pos==NOUGHT && board[1][1].pos==BLANK)
	|| (board[3][1].pos==NOUGHT && board[2][1].pos==NOUGHT && board[1][1].pos==BLANK))
	{
		x = 1;
		y = 1;
	}
	else if ((board[2][3].pos==NOUGHT && board[2][2].pos==NOUGHT && board[2][1].pos==BLANK)
	|| (board[1][1].pos==NOUGHT && board[3][1].pos==NOUGHT && board[2][1].pos==BLANK))
	{
		x=2;
		y=1;
	}
	else if ((board[1][1].pos==NOUGHT && board[2][1].pos==NOUGHT && board[3][1].pos==BLANK)
	|| (board[3][2].pos==NOUGHT && board[3][3].pos==NOUGHT && board[3][1].pos==BLANK)
	|| (board[1][3].pos==NOUGHT && board[2][2].pos==NOUGHT && board[3][1].pos==BLANK))
	{
		x=3;
		y=1;
	}
	else if ((board[2][2].pos==NOUGHT && board[3][2].pos==NOUGHT && board[1][2].pos==BLANK)
	|| (board[1][1].pos==NOUGHT && board[1][3].pos==NOUGHT && board[1][2].pos==BLANK))
	{
		x = 1;
		y = 2;
	}
	else if ((board[3][1].pos==NOUGHT && board[3][3].pos==NOUGHT && board[3][2].pos==BLANK)
	|| (board[1][2].pos==NOUGHT && board[2][2].pos==NOUGHT && board[3][2].pos==BLANK))
	{
		x=3;
		y=2;
	}
	else if ((board[1][1].pos==NOUGHT && board[3][3].pos==NOUGHT && board[2][2].pos==BLANK)
	|| (board[3][1].pos==NOUGHT && board[1][3].pos==NOUGHT && board[2][2].pos==BLANK)
	|| (board[2][1].pos==NOUGHT && board[2][3].pos==NOUGHT && board[2][2].pos==BLANK)
	|| (board[1][2].pos==NOUGHT && board[3][2].pos==NOUGHT && board[2][2].pos==BLANK))
	{
		x=2;
		y=2;
	}

	while (x==0 && y==0)
	{
		j:= rand->rand(BOARD_SIZE*BOARD_SIZE);
		x = (j/BOARD_SIZE)+1;
		y = (j%BOARD_SIZE)+1;
		if (board[x][y].pos==CROSS || board[x][y].pos==NOUGHT)
		{
			x=0;
			y=0;
		}
	}

	drawCross(x,y);
	board[x][y].pos=CROSS;
	fiximage(mainwin);
}

end_of_game()
{
	i, j: int;
	for (i = 0; i < INTERNAL_SIZE; i++)
		for (j =0; j < INTERNAL_SIZE; j++) 
		{
			if (board[i][j].pos == BLANK)
				board[i][j].pos = FINISHED;
		}
}

fatal(s: string)
{
	sys->fprint(stderr, "%s\n", s);
	exit;
}

kill(pid: int): int
{
	fd := sys->open("#p/"+string pid+"/ctl", Sys->OWRITE);
	if(fd == nil)
		return -1;
	if(sys->write(fd, array of byte "kill", 4) != 4)
		return -1;
	return 0;
}

cmd(top: ref Toplevel, s: string): string
{
	e := tk->cmd(top, s);
	if (e != nil && e[0] == '!')
		sys->fprint(stderr, "ttt: tk error on '%s': %s\n", s, e);
	return e;
}
				
win_config := array[] of 
{
	"frame .f -width 220 -height 220",

	"menubutton .f.sz -text Options -menu .f.sz.sm",
	"menu .f.sz.sm",
	".f.sz.sm add command -label restart -command { send cmd restart }",
	"pack .f.sz -side left",

	"frame .ft",
	"label .ft.l -text {  }",
	"pack .ft.l -side right",

	"pack .f -side top -fill x",
	"pack .ft -side bottom -fill x",
	
	"canvas .c -bd 3 -relief sunken -width 220 -height 220",
	"image create bitmap saveimage",
	".c create image 0 0 -image saveimage -anchor nw -tags saveimage",

	"bind .c <Button-1> {send cmd b %x %y}",

	"pack .c -side bottom -fill both -expand 1",

};

win_config2 := array[] of 
{

	"pack propagate . 0",
	"update",
};

