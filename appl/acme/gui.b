implement Gui;

include "common.m";

sys : Sys;
draw : Draw;
acme : Acme;
dat : Dat;
utils : Utils;

Font, Point, Rect, Image, Context, Screen, Display : import draw;
keyboardpid, mousepid : import acme;
ckeyboard, cmouse, Pointer : import dat;
error : import utils;

screen: ref Screen;

init(mods : ref Dat->Mods)
{
	sys = mods.sys;
	draw = mods.draw;
	acme = mods.acme;
	dat = mods.dat;
	utils = mods.utils;

	display = Display.allocate(nil);
	if(display == nil)
		error("can't initialize display: %r");
	screen = Screen.allocate(display.image, display.rgb(16rA1, 16rC3, 16rD1), 1);
	if(screen == nil)
		error("can't initialize screen: %r");

	yellow = display.color(Draw->Yellow);
	green = display.color(Draw->Green);
	red = display.color(Draw->Red);
	blue = display.color(Draw->Blue);
	black = display.color(Draw->Black);
	white = display.color(Draw->White);

	# resize the windows to fill display
	x := display.image.r.max.x;
	y := display.image.r.max.y;

	mainwin = screen.newwindow(Rect((0, 0), (x, y)), Draw->White);
	if(mainwin == nil)
		error("can't initialize window: %r");

	# mainwin.flush(Draw->Flushoff);
}

spawnprocs()
{
	spawn mouseproc();
	spawn keyboardproc();
}

# consctlfd : ref Sys->FD;

keyboardproc()
{
	m, n : int;
	fd : ref Sys->FD;
	buf : array of byte;
	r : int;
	ok : int;

	buf = array[2*Sys->UTFmax] of byte;
	keyboardpid = sys->pctl(0, nil);
	sys->pctl(Sys->FORKFD, nil);
	# fd = sys->open("/dev/consctl", Sys->OWRITE);
	# if (fd == nil)
	#	error("fd == nil in keyboardproc");
	# consctlfd = fd;	# keep it open to stay in raw mode
	# if(sys->write(fd, array of byte "rawon", 5) != 5)
	#	error("write not 5 in keyboardproc");
	fd = sys->open("/dev/keyboard", Sys->OREAD);	# was /dev/cons
	if (fd == nil)
		error("fd == nil in keyboardproc");
	n = 0;
	for(;;){
		while(n>0 && (m = sys->utfbytes(buf, n)) > 0){
			(r, m, ok) = sys->byte2char(buf, 0);
			buf[0:] = buf[m:n];
			n -= m;
			if(r!=0)
				ckeyboard <-= r;
		}
		m = sys->read(fd, buf[n:], len buf - n);
		if(m <= 0){
			sys->fprint(utils->stderr, "kbd: %r\n");
			error("kbd");
			acme->acmeexit("kbderr");
		}
		n += m;
	}
}

mouseproc()
{
	n : int;
	fd : ref Sys->FD;
	m : Pointer;

	mousepid = sys->pctl(0, nil);
	sys->pctl(Sys->FORKFD, nil);
	fd = sys->open("/dev/pointer", Sys->OREAD);
	if (fd == nil)
		error("cannot open /dev/pointer");
	buf := array[100] of byte;
	for(;;){
		n = sys->read(fd, buf, len buf);
		if(n <= 0){
			sys->fprint(utils->stderr, "mouse: %r\n");
			error("mouse");
			acme->acmeexit("mouseerr");
		}
		if (int buf[0] != 'm' || n != 37)
			continue;
		m.xy.x = int(string buf[1:13]);
		m.xy.y = int(string buf[13:25]);
		m.buttons = int(string buf[25:37]);
		if(m.buttons == 128){	# window destroyed
			sys->unmount("#d", "/dev");
			acme->acmeexit(nil);
		}
		m.buttons &= 16r17;
		m.msec = sys->millisec();
		cmouse <-= m;
	}
}

setcursor(p : Point)
{
	display.cursorset(p);
}

killwins()
{
}