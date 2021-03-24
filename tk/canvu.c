#include <lib9.h>
#include <kernel.h>
#include "image.h"
#include "tk.h"

char*
tkparsepts(TkTop *t, TkCpoints *i, char **arg, int close)
{
	char *s;
	Point *p, *d;
	int n, npoint;

	s = *arg;
	npoint = 0;
	while(*s) {
		s = tkskip(s, " \t");
		if(*s == '-' && (s[1] < '0' || s[1] > '9'))
			break;
		while(*s && *s != ' ' && *s != '\t')
			s++;
		npoint++;
	}

	i->parampt = realloc(i->parampt, npoint*sizeof(Point));
	if(i->parampt == nil)
		return TkNomem;

	s = *arg;
	p = i->parampt;
	npoint = 0;
	while(*s) {
		s = tkfrac(t, s, &p->x, nil);
		if(s == nil)
			return TkBadvl;
		s = tkfrac(t, s, &p->y, nil);
		if(s == nil)
			return TkBadvl;
		npoint++;
		s = tkskip(s, " \t");
		if(*s == '-' && (s[1] < '0' || s[1] > '9'))
			break;
		p++;
	}
	*arg = s;
	close = (close != 0);
	i->drawpt = realloc(i->drawpt, (npoint+close)*sizeof(Point));
	if(i->drawpt == nil)
		return TkNomem;

	i->bb = bbnil;

	d = i->drawpt;
	p = i->parampt;
	for(n = 0; n < npoint; n++) {
		d->x = TKF2I(p->x);
		d->y = TKF2I(p->y);
		if(d->x < i->bb.min.x)
			i->bb.min.x = d->x;
		if(d->x > i->bb.max.x)
			i->bb.max.x = d->x;
		if(d->y < i->bb.min.y)
			i->bb.min.y = d->y;
		if(d->y > i->bb.max.y)
			i->bb.max.y = d->y;
		d++;
		p++;
	}
	if (close)
		*d = i->drawpt[0];			

	i->npoint = npoint;
	return nil;
}

TkCitem*
tkcnewitem(Tk *tk, int t, int n)
{
	TkCitem *i;

	i = malloc(n);
	if(i == nil)
		return nil;
	memset(i, 0, n);

	i->type = t;
	i->env = tk->env;
	i->env->ref++;

	return i;
}

void
tkxlatepts(Point *p, int npoints, int x, int y)
{
	while(npoints--) {
		p->x += x;
		p->y += y;
		p++;
	}
}

void
tkbbmax(Rectangle *bb, Rectangle *r)
{
	if(r->min.x < bb->min.x)
		bb->min.x = r->min.x;
	if(r->min.y < bb->min.y)
		bb->min.y = r->min.y;
	if(r->max.x > bb->max.x)
		bb->max.x = r->max.x;
	if(r->max.y > bb->max.y)
		bb->max.y = r->max.y;
}

void
tkpolybound(Point *p, int n, Rectangle *r)
{
	while(n--) {
		if(p->x < r->min.x)
			r->min.x = p->x;
		if(p->y < r->min.y)
			r->min.y = p->y;
		if(p->x > r->max.x)
			r->max.x = p->x;
		if(p->y > r->max.y)
			r->max.y = p->y;
		p++;
	}
}

/*
 * look up a tag for a canvas item.
 * if n is non-nil, and the tag isn't found,
 * then add it to the canvas's taglist.
 * NB if there are no binds done on the
 * canvas, these tags never get cleared out,
 * even if nothing refers to them.
 */
TkName*
tkctaglook(Tk* tk, TkName *n, char *name)
{
	ulong h;
	TkCanvas *c;
	char *p, *s;
	TkName *f, **l;

	c = TKobj(TkCanvas, tk);

	s = name;
	if(s == nil)
		s = n->name;

	if(strcmp(s, "current") == 0)
		return c->current;

	h = 0;
	for(p = s; *p; p++)
		h += 3*h + *p;

	l = &c->thash[h%TkChash];
	for(f = *l; f; f = f->link)
		if(strcmp(f->name, s) == 0)
			return f;

	if(n == nil)
		return nil;
	n->link = *l;
	*l = n;
	return n;
}

char*
tkcaddtag(Tk *tk, TkCitem *i, int new)
{
	TkCtag *t;
	TkCanvas *c;
	char buf[16];
	TkName *n, *f, *link;

	c = TKobj(TkCanvas, tk);
	if(new != 0) {
		i->id = ++c->id;
		snprint(buf, sizeof(buf), "%d", i->id);
		n = tkmkname(buf);
		if(n == nil)
			return TkNomem;
		n->link = i->tags;
		i->tags = n;
	}

	for(n = i->tags; n; n = link) {
		link = n->link;
		f = tkctaglook(tk, n, nil);
		if(n != f)
			free(n);

		for(t = i->stag; t; t = t->itemlist)
			if(t->name == f)
				break;
		if(t == nil) {
			t = malloc(sizeof(TkCtag));
			if(t == nil) {
				tkfreename(link);
				return TkNomem;
			}
			t->name = f;
			t->taglist = f->obj;		/* add to head of items with this tag */
			f->obj = t;
			t->item = i;
			t->itemlist = i->stag;	/* add to head of tags for this item */
			i->stag = t;
		}
	}
	i->tags = nil;

	if(new != 0) {
		i->tags = tkmkname("all");
		if(i->tags == nil)
			return TkNomem;		/* XXX - Tad: memory leak? */
		return tkcaddtag(tk, i, 0);
	}

	return nil;
}

void
tkfreepoint(TkCpoints *p)
{
	if(p->drawpt != nil)
		free(p->drawpt);
	if(p->parampt != nil)
		free(p->parampt);
}

/*
 * of all the items in ilist tagged with tag,
 * return that tag for the first (topmost) item.
 */
TkCtag*
tkclasttag(TkCitem *ilist, TkCtag* tag)
{
	TkCtag *last, *t;

	if (tag == nil || tag->taglist == nil)
		return tag;
	last = nil;
	while(ilist) {
		for(t = tag; t; t = t->taglist) {
			if(t->item == ilist) {
				last = t;
				break;
			}
		}
		ilist = ilist->next;
	}
	return last;
}

/*
 * of all the items in ilist tagged with tag,
 * return that tag for the first (bottommost) item.
 */
TkCtag*
tkcfirsttag(TkCitem *ilist, TkCtag* tag)
{
	TkCtag *t;

	if (tag == nil || tag->taglist == nil)
		return tag;
	for (; ilist != nil; ilist = ilist->next)
		for(t = tag; t; t = t->taglist)
			if(t->item == ilist)
				return t;
	return nil;
}


/*
 * make a mask image for a stipple drawing operation.
 * reallocate existing mask if it's too small, otherwise
 * blank out relevant area of mask.
 * set org to position in dst's coord system of (0,0) in mask.
 * return false if there's nothing to be drawn.
 */
int
tkmkmask(TkCanvas *c, Image *dst, TkCitem *i, Point *org)
{
	Display *d;
	Rectangle r,mr;
	r = i->p.bb;
	if (!rectclip(&r, dst->r) || !rectclip(&r, dst->clipr))
		return 0;
	mr = Rect(0, 0, Dx(r), Dy(r));
	d = dst->display;
	if (c->mask == nil) {
		c->mask = allocimage(d, mr, 0, 0, 0);
	} else if (mr.max.x > Dx(c->mask->r) || mr.max.y > Dy(c->mask->r)) {
		freeimage(c->mask);
		c->mask = allocimage(d, mr, 0, 0, 0);
	} else {
		replclipr(c->mask, 0, mr);
		draw(c->mask, mr, d->zeros, nil, ZP);
	}
	*org = r.min;
	return c->mask != nil;
}

void
tkmkstipple(Image *stipple)
{
	int locked;
	if (stipple != nil && !stipple->repl) {
		locked = lockdisplay(stipple->display, 0);
		replclipr(stipple, 1, huger);
		if (locked)
			unlockdisplay(stipple->display);
	}
}

		
/*
 * XXX tkmkpen is not sufficient, as according to the tk standard
 * canvas items drawn with a stipple pattern should be transparent
 * where the stipple is transparent - however, it's not possible (directly)
 * to apply the draw operators through a mask, which is what
 * we'd need to do. this is fixed by tkmkmask, but currently
 * only implemented for ovals, polygons and rectangles.
 */
void
tkmkpen(Image **pen, TkEnv *e, TkEnv *ce, Image *stipple)
{
	int locked;
	Display *d;
	Image *new, *fill, *bg;

	bg = tkgc(ce, TkCbackgnd);
	fill = tkgc(e, TkCfill);

	d = e->top->display;
	locked = lockdisplay(d, 0);
	if(*pen != nil) {
		freeimage(*pen);
		*pen = nil;
	}
	if(stipple == nil) {
		if(locked)
			unlockdisplay(d);
		return;
	}

	if(fill == nil)
		fill = d->ones;	/* black */
	new = allocimage(d, stipple->r, 3, 1, 0);
	if(new != nil) {
		draw(new, stipple->r, bg, nil, ZP);
		draw(new, stipple->r, fill, stipple, ZP);
	}
	else
		new = fill;
	if(locked)
		unlockdisplay(d);
	*pen = new;
}

Point
tkcvsanchor(Point dp, int w, int h, int anchor)
{
	Point o;

	if(anchor & (Tknorth|Tknortheast|Tknorthwest))
		o.y = dp.y;
	else
	if(anchor & (Tksouth|Tksoutheast|Tksouthwest))
		o.y = dp.y - h;
	else
		o.y = dp.y - h/2;

	if(anchor & (Tkwest|Tknorthwest|Tksouthwest))
		o.x = dp.x;
	else
	if(anchor & (Tkeast|Tknortheast|Tksoutheast))
		o.x = dp.x - w;
	else
		o.x = dp.x - w/2;

	return o;
}

static TkCitem*
tkcvsmousefocus(TkCanvas *c, Point p)
{
	TkCitem *i, *s;
	int (*hit)(TkCitem*, Point);

	if (c->grab != nil)
		return c->grab;
	s = nil;
	for(i = c->head; i; i = i->next)
		if(ptinrect(p, i->p.bb)) {
			if ((hit = tkcimethod[i->type].hit) != nil && !(*hit)(i, p))
				continue;
			s = i;
		}

	return s;
}

static void
tkcvsdeliver(Tk *tk, TkCitem *i, int event, void *data)
{
	Tk *ftk;
	TkMouse m;
	TkCtag *t;
	TkCwind *w;
	Point mp, g;
	TkCanvas *c;
	TkAction *a;

	if(i->type == TkCVwindow) {
		w = TKobj(TkCwind, i);
		if(w->sub == nil)
			return;

		if(!(event & TkKey) && (event & TkEmouse)) {
			m = *(TkMouse*)data;
			g = tkposn(tk);
			c = TKobj(TkCanvas, tk);
			mp.x = m.x - (g.x + tk->borderwidth) + c->view.x;
			mp.y = m.y - (g.y + tk->borderwidth) + c->view.y;
			ftk = tkinwindow(w->sub, mp);
			if(ftk != w->focus) {
				tkdeliver(w->focus, TkLeave, data);
				tkdeliver(ftk, TkEnter, data);
				w->focus = ftk;
			}
			if(ftk != nil)
				tkdeliver(ftk, event, &m);
		}
		else
		if(w->sub != nil) {
			if ((event & TkLeave) && (w->focus != w->sub)) {
				tkdeliver(w->focus, TkLeave, data);
				w->focus = nil;
				event &= ~TkLeave;
			}
			if (event)
				tkdeliver(w->sub, event, data);
		}
		return;
	}

	for(t = i->stag; t != nil; t = t->itemlist) {
		a = t->name->prop.binds;
		if(a != nil)
			tksubdeliver(tk, a, event, data);
	}
}

void
tkcvsevent(Tk *tk, int event, void *data)
{
	TkMouse m;
	TkCitem *f;
	Point mp, g;
	TkCanvas *c;

	c = TKobj(TkCanvas, tk);

	if(event == TkLeave && c->mouse != nil) {
		tkcvsdeliver(tk, c->mouse, TkLeave, data);
		c->mouse = nil;
	}

	if(!(event & TkKey) && (event & TkEmouse)) {
		m = *(TkMouse*)data;
		g = tkposn(tk);
		mp.x = (m.x - g.x - tk->borderwidth) + c->view.x;
		mp.y = (m.y - g.y - tk->borderwidth) + c->view.y;
		f = tkcvsmousefocus(c, mp);
		if(c->mouse != f) {
			if(c->mouse != nil) {
				tkcvsdeliver(tk, c->mouse, TkLeave, data);
				c->current->obj = nil;
			}
			if(f != nil) {
				c->current->obj = &c->curtag;
				c->curtag.item = f;
				tkcvsdeliver(tk, f, TkEnter, data);
			}
			c->mouse = f;
		}
		f = c->mouse;
		if(f != nil)
			tkcvsdeliver(tk, f, event, &m);
	}

	if(event & TkKey) {
		f = c->focus;
		if(f != nil)
			tkcvsdeliver(tk, f, event, data);
	}
	tksubdeliver(tk, tk->binds, event, data);
}
