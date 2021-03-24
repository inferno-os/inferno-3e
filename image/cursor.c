#include <lib9.h>
#include <image.h>

void
cursor(Point hotspot, Image *bits)
{
	uchar *a;

	a = bufimage(bits->display, 1+4+2*4);
	if(a == 0){
		fprint(2, "image cursor: %r\n");
		return;
	}
	a[0] = 'C';
	BPLONG(a+1, bits->id);
	BPLONG(a+5, hotspot.x);
	BPLONG(a+9, hotspot.y);
	flushimage(bits->display, 0);
}

void
cursorset(Display *d, Point p)
{
	uchar *a;

	a = bufimage(d, 1+2*4);
	if (a == 0) {
		fprint(2, "image cursorset: %r\n");
		return;
	}
	a[0] = 'x';
	BPLONG(a+1, p.x);
	BPLONG(a+5, p.y);
	flushimage(d, 0);
}
