implement Graph;

include "common.m";

sys : Sys;
drawm : Draw;
dat : Dat;
gui : Gui;
utils : Utils;

Image, Point, Rect, Font, Display : import drawm;
black, white, display : import gui;
error : import utils;

ones : ref Image;
refp : ref Point;
pixarr : array of byte;

init(mods : ref Dat->Mods)
{
	sys = mods.sys;
	drawm = mods.draw;
	dat = mods.dat;
	gui = mods.gui;
	utils = mods.utils;

	ones = display.ones;
	refp = ref Point;
	refp.x = refp.y = 0;
}

charwidth(f : ref Font, c : int) : int
{
	s : string = "z";

	s[0] = c;
	return f.width(s);
}

strwidth(f : ref Font, s : string) : int
{
	return f.width(s);
}

balloc(r : Rect, ldepth : int, col : int) : ref Image
{
	im := display.newimage(r, ldepth, 0, col);
	return im;
}

draw(d : ref Image, r : Rect, s : ref Image, m : ref Image, p : Point)
{
	d.draw(r, s, m, p);
}

stringx(d : ref Image, p : Point, f : ref Font, s : string, c : ref Image)
{
	d.text(p, c, (0, 0), f, s);
}

cursorset(p : Point)
{
	gui->setcursor(p);
}

cursorswitch(c : ref Dat->Cursor)
{
	bits : ref Image;

	if (c != nil) {
		bits = c.bits;
		refp.x = c.hotspot.x;
		refp.y = c.hotspot.y;
	}
	else {
		bits = display.image;
		refp.x = refp.y = 0;
	}
	display.cursor(bits, refp);
}

binit()
{
}

bflush()
{
}

berror(s : string)
{
	error(s);
}