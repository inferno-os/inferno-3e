#include <lib9.h>
#include <image.h>


static int
rgba2cmap(ulong c)
{
	return rgb2cmap(c>>24, c>>16, c>>8);
}

Image*
allocimagemix(Display *d, ulong color1, ulong color3)
{
	Image *t, *b;

	t = allocimage(d, Rect(0,0,1,1), d->image->ldepth, 0, rgba2cmap(color1));
	if(t == nil)
		return nil;

	b = allocimage(d, Rect(0,0,2,2), d->image->ldepth, 1, rgba2cmap(color3));
	if(b == nil){
		freeimage(t);
		return nil;
	}

	draw(b, Rect(0,0,1,1), t, nil, ZP);
	freeimage(t);
	return b;
}
