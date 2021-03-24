#include <lib9.h>
#include <kernel.h>
#include "image.h"
#include "tk.h"

#define	O(t, e)		((long)(&((t*)0)->e))
#define OA(t, e)	((long)(((t*)0)->e))

static
TkOption opts[] =
{
	"closeenough",		OPTfrac,	O(TkCanvas, close),	nil,
	"confine",		OPTfrac,	O(TkCanvas, confine),	nil,
	"scrollregion",		OPTfrac,	OA(TkCanvas, scrollr),	IAUX(4),
	"xscrollincrement",	OPTfrac,	O(TkCanvas, xscrolli),	nil,
	"yscrollincrement",	OPTfrac,	O(TkCanvas, yscrolli),	nil,
	"xscrollcommand",	OPTtext,	O(TkCanvas, xscroll),	nil,
	"yscrollcommand",	OPTtext,	O(TkCanvas, yscroll),	nil,
	"width",		OPTfrac,	O(TkCanvas, width),	nil,
	"height",		OPTfrac,	O(TkCanvas, height),	nil,
	"buffered",		OPTstab,	O(TkCanvas, buffered),	tkbool,
	nil
};

static void
tkcvsf2i(Tk *tk, TkCanvas *tkc)
{
	Rectangle r;
	tk->req.width = TKF2I(tkc->width);
	tk->req.height = TKF2I(tkc->height);

	r.min.x = TKF2I(tkc->scrollr[0]);
	r.min.y = TKF2I(tkc->scrollr[1]);
	r.max.x = TKF2I(tkc->scrollr[2]);
	r.max.y = TKF2I(tkc->scrollr[3]);

	/*
	 * make sure that the region is big enough to hold
	 * the actually displayed area
	 */
	if (Dx(r) < tk->act.width)
		r.max.x = r.min.x + tk->act.width;
	if (Dy(r) < tk->act.height)
		r.max.y = r.min.y + tk->act.height;
	tkc->region = r;

	/*
	 * make sure that the view origin is at a valid
	 * position with respect to the scroll region.
	 */
	if (tkc->view.x + tk->act.width > r.max.x)
		tkc->view.x = r.max.x - tk->act.width;
	if (tkc->view.x < r.min.x)
		tkc->view.x = r.min.x;

	if (tkc->view.y + tk->act.height > r.max.y)
		tkc->view.y = r.max.y - tk->act.height;
	if (tkc->view.y < r.min.y)
		tkc->view.y = r.min.y;

}

char*
tkcanvas(TkTop *t, char *arg, char **ret)
{
	Tk *tk;
	char *e;
	TkCanvas *tkc;
	TkName *names;
	TkOptab tko[3];

	tk = tknewobj(t, TKcanvas, sizeof(Tk)+sizeof(TkCanvas));
	if(tk == nil)
		return TkNomem;

	tkc = TKobj(TkCanvas, tk);
	tkc->close = TKI2F(1);
	tkc->xscrolli = TKI2F(1);
	tkc->yscrolli = TKI2F(1);
	tkc->width = TKI2F(360);
	tkc->height = TKI2F(270);
	tkc->actions = 0;
	tkc->actlim = Tksweep;
	tkc->mask = nil;
	tk->sborderwidth = 1;

	tko[0].ptr = tkc;
	tko[0].optab = opts;
	tko[1].ptr = tk;
	tko[1].optab = tkgeneric;
	tko[2].ptr = nil;

	names = nil;
	e = tkparse(t, arg, tko, &names);
	if(e != nil)
		goto err;
	if(names == nil) {
		/* tkerr(t, arg); XXX */
		e = TkBadwp;
		goto err;
	}

	tkc->current = tkmkname("current");
	if(tkc->current == nil) {
		e = TkNomem;
		goto err;
	}

	tkcvsf2i(tk, tkc);

	tk->deliverfn = tkcvsevent;
	tk->dirty = tkcvsupdate;
	tk->relpos = tkcvsrelpos;

	e = tkaddchild(t, tk, &names);
	tkfreename(names);
	if(e != nil) {
		tkfreename(tkc->current);
		tkc->current = nil;
		goto err;
	}
	tk->name->link = nil;

	e = tkvalue(ret, "%s", tk->name->name);
	if(e == nil)
	        return nil;
	
	tkfreename(tkc->current);
	return e;
err:
	tkfreeobj(tk);
	return e;
}

void
tkcvsupdate(Tk *sub)
{
 	TkCitem *i;
	TkCanvas *c;
	TkCwind *win;
	Tk *tk, *parent;
	Rectangle r;
	r.min = ZP;
	parent = nil;
	for(tk = sub; tk && parent == nil;  tk = tk->master) {
		r.min.x += tk->act.x;
		r.min.y += tk->act.y;
		parent = tk->parent;
	}
	r.max.x = r.min.x + sub->act.width + 2 * sub->borderwidth;
	r.max.y = r.min.y + sub->act.height + 2 * sub->borderwidth;

	c = TKobj(TkCanvas, parent);
	for(i = c->head; i; i = i->next) {
		if(i->type == TkCVwindow) {
			win = TKobj(TkCwind, i);
			if(win->sub != nil && tkischild(win->sub, sub)) {
				if (rectclip(&r, i->p.bb)) {
					tkbbmax(&c->update, &i->p.bb);
					parent->flag |= Tkdirty;
				}
				return;
			}
		}
	}
}

char*
tkcvscget(Tk *tk, char *arg, char **val)
{
	TkOptab tko[3];
	TkCanvas *tkc = TKobj(TkCanvas, tk);

	tko[0].ptr = tkc;
	tko[0].optab = opts;
	tko[1].ptr = tk;
	tko[1].optab = tkgeneric;
	tko[2].ptr = nil;

	return tkgencget(tko, arg, val, tk->env->top);
}

char*
tkcvsconf(Tk *tk, char *arg, char **val)
{
	char *e;
	int bd;
	TkGeom g;
	Rectangle r;
	TkOptab tko[3];
	TkCanvas *c = TKobj(TkCanvas, tk);

	tko[0].ptr = c;
	tko[0].optab = opts;
	tko[1].ptr = tk;
	tko[1].optab = tkgeneric;
	tko[2].ptr = nil;

	if(*arg == '\0')
		return tkconflist(tko, val);

	r.min = c->view;
	r.max.x = r.min.x+tk->act.width;
	r.max.y = r.min.y+tk->act.height;
	tkbbmax(&c->update, &r);
	tkbbmax(&c->update, &c->region);

	bd = tk->borderwidth;
	g = tk->req;
	e = tkparse(tk->env->top, arg, tko, nil);
	if(e != nil)
		return e;

	tkcvsf2i(tk, c);
	
	tkcvsgeom(tk);	
	tkgeomchg(tk, &g, bd);
	c->cleanup = 1;
	tkbbmax(&c->update, &c->region);
	tk->flag |= Tkdirty;
	return nil;
}

void
tkcvsfreeitem(TkCitem *i)
{
	int locked;
	Display *d;

	d = i->env->top->display;

	locked = lockdisplay(d, 0);
	tkcimethod[i->type].free(i);
	if(locked)
		unlockdisplay(d);

	tkfreepoint(&i->p);
	tkputenv(i->env);
	free(i);
}

void
tkfreecanv(Tk *tk)
{
	Display *d;
	int j, locked;
	TkCanvas *c;
	TkName *n, *nn;
	TkCtag *t, *tt;
	TkCitem *i, *next;

	c = TKobj(TkCanvas, tk);
	for(i = c->head; i; i = next) {
		next = i->next;
		tkcvsfreeitem(i);
	}

	if(c->xscroll != nil)
		free(c->xscroll);
	if(c->yscroll != nil)
		free(c->yscroll);

	for(j = 0; j < TkChash; j++) {
		for(n = c->thash[j]; n; n = nn) {
			nn = n->link;
			for(t = n->obj; t; t = tt) {
				tt = t->taglist;
				free(t);
			}
			tkfreebind(n->prop.binds);
			free(n);
		}
	}

	free(c->current);

	if(c->image != nil || c->mask != nil) {
		d = c->image->display;
		locked = lockdisplay(d, 0);
		if (c->image != nil)
			freeimage(c->image);
		if (c->mask != nil)
			freeimage(c->mask);
		if(locked)
			unlockdisplay(d);
	}
}

char*
tkdrawcanv(Tk *tk, Point orig)
{
	Point p;
	Image *dst;
	TkCitem *i;
	Display *d;
	int bpix, x;
	TkCanvas *c;
	Rectangle r, bufr, fullr;

	c = TKobj(TkCanvas, tk);
	d = tk->env->top->display;

	if (c->buffered == BoolT)
		bufr = c->region;
	else {
		bufr.min = c->view;
		bufr.max.x = c->view.x + tk->act.width;
		bufr.max.y = c->view.y + tk->act.height;
	}

	if(c->image == nil || eqrect(bufr, c->image->r) == 0) {
		if(c->image != nil)
			freeimage(c->image);
		bpix = tk->env->colors[TkCbackgnd];
		c->image = allocimage(d, bufr, d->image->ldepth, 0, bpix);
		c->update = bufr;
		c->cleanup = 1;
	}
	if(tk->flag & Tkrefresh) {
		c->cleanup = 1;
		tk->flag &= ~Tkrefresh;
	}

	if(c->image == nil)
		return nil;

	r = c->update;
	if (rectclip(&r, c->image->r)) {
		draw(c->image, c->update, tkgc(tk->env, TkCbackgnd), nil, c->view);
		replclipr(c->image, 0, r);
		for(i = c->head; i; i = i->next) {
			if(rectXrect(i->p.bb, r))
				tkcimethod[i->type].draw(c->image, i, tk->env);
		}
		replclipr(c->image, 0, c->image->r);
	}

	r.min.x = orig.x + tk->act.x + tk->borderwidth;
	r.min.y = orig.y + tk->act.y + tk->borderwidth;
	r.max.x = r.min.x + tk->act.width;
	r.max.y = r.min.y + tk->act.height;

	dst = tkimageof(tk);
	p = c->view;
	if(c->cleanup == 0) {
		fullr = r;
		x = c->update.min.x - c->view.x;
		if(x > 0){
			r.min.x += x;
			p.x = c->update.min.x;
		}
		x = c->update.min.y - c->view.y;
		if(x > 0){
			r.min.y += x;
			p.y = c->update.min.y;
		}
		x = c->view.x+Dx(fullr)-c->update.max.x;
		if(x > 0)
			r.max.x -= x;
		x = c->view.y+Dy(fullr)-c->update.max.y;
		if(x > 0)
			r.max.y -= x;
	} else {
		/* avoid drawing background if it will be redrawn anyway */
		if(Dx(c->image->r)<Dx(r) || Dy(c->image->r)<Dy(r))
			draw(dst, r, tkgc(tk->env, TkCbackgnd), nil, c->view);
	}
	c->update = bbnil;
	c->cleanup = 0;

	if (Dx(r) > 0 && Dy(r) > 0)
		draw(dst, r, c->image, nil, p);

	p.x = orig.x + tk->act.x;
	p.y = orig.y + tk->act.y;
	tkdrawrelief(dst, tk, p, 0, TkCbackgnd);
	return nil;
/* err:
	print("tkdrawcanv: out of memory\n");
	return nil; */
}

void
tkcvsappend(TkCanvas *c, TkCitem *i)
{
	if(c->head == nil)
		c->head = i;
	else
		c->tail->next = i;
	c->tail = i;
}

void
tkcvssv(Tk *tk)
{
	TkCanvas *c;
	int top, bot, height;
	char val[Tkminitem], cmd[Tkmaxitem], *v, *e;

	c = TKobj(TkCanvas, tk);
	if(c->yscroll == nil)
		return;

	top = 0;
	bot = Tkfpscalar;

	height = Dy(c->region);
	if(height != 0) {
		top = c->view.y*Tkfpscalar/height;
		bot = (c->view.y+tk->act.height)*Tkfpscalar/height;
	}

	v = tkfprint(val, top);
	*v++ = ' ';
	tkfprint(v, bot);
	snprint(cmd, sizeof(cmd), "%s %s", c->yscroll, val);
	e = tkexec(tk->env->top, cmd, nil);
	if ((e != nil) && (tk->name != nil))
		print("tk: yscrollcommand \"%s\": %s\n", tk->name->name, e);
}

void
tkcvssh(Tk *tk)
{
	int top, bot, width;
	TkCanvas *c = TKobj(TkCanvas, tk);
	char val[Tkminitem], cmd[Tkmaxitem], *v, *e;

	if(c->xscroll == nil)
		return;

	top = 0;
	bot = Tkfpscalar;

	width = Dx(c->region);
	if(width != 0) {
		top = c->view.x*Tkfpscalar/width;
		bot = (c->view.x+tk->act.width)*Tkfpscalar/width;
	}

	v = tkfprint(val, top);
	*v++ = ' ';
	tkfprint(v, bot);
	snprint(cmd, sizeof(cmd), "%s %s", c->xscroll, val);
	e = tkexec(tk->env->top, cmd, nil);
	if ((e != nil) && (tk->name != nil))
		print("tk: xscrollcommand \"%s\": %s\n", tk->name->name, e);
}

void
tkcvsgeom(Tk *tk)
{
	TkCanvas *c;
	c = TKobj(TkCanvas, tk);

	tkcvsf2i(tk, c);
	c->update = c->region;
	c->cleanup = 1;

	tkcvssv(tk);
	tkcvssh(tk);
}

/* Widget Commands (+ means implemented)
	+addtag
		except halo and start options of closest spec
	+bbox
	+bind
	+canvasx
	+canvasy
	+cget
	+configure
	+coords
	+create
	+dchars
	+delete
	+dtag
	+find
	+focus
	+gettags
	+icursor
	+index
	+insert
	+itemcget
	+itemconfigure
	+lower
	+move
	 postscript
	+raise
	+scale
	 scan
	+select
	+type
	+xview
	+yview
*/

char*
tkcvstags(Tk *tk, char *arg, char **val, int af)
{
	TkTop *o;
	int x, y;
	TkName *f;
	TkCtag *t, *tt;
	char *fmt;
	TkCpoints p;
	TkCanvas *c;
	TkCitem *i, *b;
	int d, dist, dx, dy;
	char tag[Tkmaxitem], buf[Tkmaxitem];
	char *e = nil;

	USED(val);

	c = TKobj(TkCanvas, tk);

	o = tk->env->top;
	if(af == TkCadd) {
		arg = tkword(o, arg, tag, tag+sizeof(tag), nil);
		if(tag[0] == '\0' || (tag[0] >= '0' && tag[0] <= '9'))
			return TkBadtg;
	}

	fmt = "%d";
	arg = tkword(o, arg, buf, buf+sizeof(buf), nil);
	if(strcmp(buf, "above") == 0) {
		tkword(o, arg, buf, buf+sizeof(buf), nil);
		f = tkctaglook(tk, nil, buf);
		if(f == nil)
			return TkBadtg;

		t = tkclasttag(c->head, f->obj);
		if(t == nil)
			return TkBadtg;

		for(i = t->item->next; i; i = i->next) {
			if(af == TkCadd) {
				i->tags = tkmkname(tag);
				if(i->tags == nil)
					return TkNomem;
				tkcaddtag(tk, i, 0);
			}
			else {
				e = tkvalue(val, fmt, i->id);
				if(e != nil)
					return e;
				fmt = " %d";
			}
		}
		return nil;
	}

	if(strcmp(buf, "all") == 0) {
		for(i = c->head; i; i = i->next) {
			if(af == TkCadd) {
				i->tags = tkmkname(tag);
				if(i->tags == nil)
					return TkNomem;
				tkcaddtag(tk, i, 0);
			}
			else {
				e = tkvalue(val, fmt, i->id);
				if(e != nil)
					return e;
				fmt = " %d";
			}
		}
		return nil;
	}

	if(strcmp(buf, "below") == 0) {
		tkword(o, arg, buf, buf+sizeof(buf), nil);
		f = tkctaglook(tk, nil, buf);
		if(f == nil)
			return TkBadtg;
		tt = f->obj;
		for(b = c->head; b; b = b->next) {
			for(t = tt; t; t = t->itemlist)
				if(t->item == b)
					goto found;
		}
	found:
		for(i = c->head; i != b; i = i->next) {
			if(af == TkCadd) {
				i->tags = tkmkname(tag);
				if(i->tags == nil)
					return TkNomem;
				tkcaddtag(tk, i, 0);
			}
			else {
				e = tkvalue(val, fmt, i->id);
				if(e != nil)
					return e;
				fmt = " %d";
			}
		}
		return nil;
	}

	if(strcmp(buf, "closest") == 0) {
		arg = tkfrac(o, arg, &x, nil);
		if(arg == nil)
			return TkBadvl;
		arg = tkfrac(o, arg, &y, nil);
		if(*arg != '\0')
			return "!not implemented";

		x = TKF2I(x);
		y = TKF2I(y);
		i = nil;
		dist = 0;
		for(b = c->head; b != nil; b = b->next) {
			dx = x - (b->p.bb.min.x + Dx(b->p.bb)/2);
			dy = y - (b->p.bb.min.y + Dy(b->p.bb)/2);
			d = dx*dx + dy*dy;
			if(d < dist || dist == 0) {
				i = b;
				dist = d;
			}
		}
		if(i == nil)
			return nil;

		if(af == TkCadd) {
			i->tags = tkmkname(tag);
			if(i->tags == nil)
				e = TkNomem;
			else
				tkcaddtag(tk, i, 0);
		}
		else
			e = tkvalue(val, fmt, i->id);
		return e;
	}

	if(strcmp(buf, "enclosed") == 0) {
		p.drawpt = nil;
		p.parampt = nil;
		e = tkparsepts(o, &p, &arg, 0);
		if(e != nil) {
			tkfreepoint(&p);
			return e;
		}
		if(p.npoint != 2) {
			tkfreepoint(&p);
			return TkFewpt;
		}
		for(i = c->head; i; i = i->next) {
			if(rectinrect(i->p.bb, p.bb)) {
				if(af == TkCadd) {
					i->tags = tkmkname(tag);
					if(i->tags == nil) {
						e = TkNomem;
						goto done;
					}
					tkcaddtag(tk, i, 0);
				}
				else {
					e = tkvalue(val, fmt, i->id);
					if(e != nil)
						goto done;
					fmt = " %d";
				}
			}
		}
		goto done;
	}

	if(strcmp(buf, "overlapping") == 0) {
		p.drawpt = nil;
		p.parampt = nil;
		e = tkparsepts(o, &p, &arg, 0);
		if(e != nil)
			goto done;
		if(p.npoint != 2) {
			tkfreepoint(&p);
			return TkFewpt;
		}
		for(i = c->head; i; i = i->next) {
			if(rectXrect(i->p.bb, p.bb)) {
				if(af == TkCadd) {
					i->tags = tkmkname(tag);
					if(i->tags == nil) {
						e = TkNomem;
						goto done;
					}
					tkcaddtag(tk, i, 0);
				}
				else {
					e = tkvalue(val, "%d ", i->id);
					if(e != nil)
						goto done;
				}
			}
		}
		goto done;
	}

	if(strcmp(buf, "withtag") == 0) {
		tkword(o, arg, buf, buf+sizeof(buf), nil);
		f = tkctaglook(tk, nil, buf);
		if(f == nil)
			return TkBadtg;
		for(t = f->obj; t; t = t->taglist) {
			i = t->item;
			if(af == TkCadd) {
				i->tags = tkmkname(tag);
				if(i->tags == nil)
					return TkNomem;
				tkcaddtag(tk, i, 0);
			}
			else {
				e = tkvalue(val, fmt, i->id);
				if(e != nil)
					return e;
				fmt = " %d";
			}
		}
		return nil;
	}

	return TkBadcm;

done: 		 /* both no error and error do the same thing */
		tkfreepoint(&p);
		return e;
}

char*
tkcvsaddtag(Tk *tk, char *arg, char **val)
{
	return tkcvstags(tk, arg, val, TkCadd);
}

char*
tkcvsfind(Tk *tk, char *arg, char **val)
{
	return tkcvstags(tk, arg, val, TkCfind);
}

static void
tksweepcanv(Tk *tk)
{
	int j, k;
	TkCtag *t, *tt;
	TkName **np, *n, *nn;
	TkCitem *i;
	TkCanvas *c;
	TkAction *a;

	c = TKobj(TkCanvas, tk);

	for(j = 0; j < TkChash; j++)
		for(n = c->thash[j]; n != nil; n = n->link)
			n->ref = 0;

	for(i = c->head; i != nil; i = i->next)
		for(t = i->stag; t != nil; t = t->itemlist)
			t->name->ref = 1;

	k = 0;
	for(j = 0; j < TkChash; j++) {
		np = &c->thash[j];
		for(n = *np; n != nil; n = nn) {
			nn = n->link;
			if(n->ref == 0) {
				for(t = n->obj; t != nil; t = tt) {
					tt = t->taglist;
					free(t);
				}
				tkfreebind(n->prop.binds);
				free(n);
				*np = nn;
			} else {
				np = &n->link;
				for(a = n->prop.binds; a != nil; a = a->link)
					k++;
			}
		}
	}

	c->actions = k;
	k = 3 * k / 2;
	if (k < Tksweep)
		c->actlim = Tksweep;
	else
		c->actlim = k;
}

/*
 * extension to tcl/tk:
 * grab set tag
 * grab release tag
 * grab ifunset tag
 */
char*
tkcvsgrab(Tk *tk, char *arg, char **val)
{
	TkCtag *t;
	TkName *f;
	TkCanvas *c;
	char buf[Tkmaxitem];

	c = TKobj(TkCanvas, tk);
	arg = tkword(tk->env->top, arg, buf, buf+sizeof(buf), nil);
	if (strcmp(buf, "status") == 0) {
		if (c->grab != nil)
			return tkvalue(val, "%d", c->grab->id);
	}
	else if (strcmp(buf, "release") == 0) {
		c->grab = nil;
	}
	else if (strcmp(buf, "set") == 0 || strcmp(buf, "ifunset") == 0) {
		if (buf[0] == 'i' && c->grab != nil)
			return nil;
		tkword(tk->env->top, arg, buf, buf + sizeof(buf), nil);

		f = tkctaglook(tk, nil, buf);
		if(f == nil || f->obj == nil)
			return TkBadtg;
	
		c = TKobj(TkCanvas, tk);
		t = tkcfirsttag(c->head, f->obj);
		if(t == nil)
			return TkBadtg;
		c->grab = t->item;
	}
	else
		return TkBadvl;
	return nil;
}

char*
tkcvsbind(Tk *tk, char *arg, char **val)
{
	Rune r;
	TkCtag *t;
	TkName *f;
	TkAction *a;
	TkCanvas *c;
	int event, mode;
	char *cmd, buf[Tkmaxitem];
	char *e;

	c = TKobj(TkCanvas, tk);
	if (c->actions >= c->actlim)
		tksweepcanv(tk);
	arg = tkword(tk->env->top, arg, buf, buf+sizeof(buf), nil);

	f = tkctaglook(tk, nil, buf);
	if(f == nil) {
		f = tkctaglook(tk, tkmkname(buf), buf);
		if(f == nil)
			return TkNomem;
	}

	arg = tkword(tk->env->top, arg, buf, buf+sizeof(buf), nil);
	if(buf[0] == '<') {
		event = tkseqparse(buf+1);
		if(event == -1)
			return TkBadsq;
	}
	else {
		chartorune(&r, buf);
		event = TkKey | r;
	}
	if(event == 0)
		return TkBadsq;

	arg = tkskip(arg, " \t");
	if(*arg == '\0') {
		for(t = f->obj; t; t = t->taglist) {
			for(a = t->name->prop.binds; a; a = a->link)
				if(event == a->event)
					return tkvalue(val, "%s", a->arg);
			for(a = t->name->prop.binds; a; a = a->link)
				if(event & a->event)
					return tkvalue(val, "%s", a->arg);
		}
		return nil;		
	}

	mode = TkArepl;
	if(*arg == '+') {
		mode = TkAadd;
		arg++;
	}
	else if(*arg == '-'){
		mode = TkAsub;
		arg++;
	}

	tkword(tk->env->top, arg, buf, buf+sizeof(buf), nil);
	cmd = strdup(buf);
	if(cmd == nil)
		return TkNomem;
	e = tkaction(&f->prop.binds, event, TkDynamic, cmd, mode);
	if(e != nil)
		free(cmd);
	else
		c->actions++;
	return e;
}

char*
tkcvscreate(Tk *tk, char *arg, char **val)
{
	TkCimeth *m;
	char buf[Tkmaxitem];

	arg = tkword(tk->env->top, arg, buf, buf+sizeof(buf), nil);
	for(m = tkcimethod; m->name; m++)
		if(strcmp(buf, m->name) == 0)
			return m->create(tk, arg, val);

	return TkBadit;
}

char*
tkcvsbbox(Tk *tk, char *arg, char **val)
{
	TkName *f;
	TkCtag *t;
	Rectangle bb;
	char buf[Tkmaxitem];

	bb = bbnil;
	for(;;) {
		arg = tkword(tk->env->top, arg, buf, buf+sizeof(buf), nil);
		if(buf[0] == '\0')
			break;
		f = tkctaglook(tk, nil, buf);
		if(f == nil)
			return TkBadtg;
		for(t = f->obj; t; t = t->taglist)
			tkbbmax(&bb, &t->item->p.bb);
	}
	return tkvalue(val, "%d %d %d %d", bb.min.x, bb.min.y, bb.max.x, bb.max.y);
}

char*
tkcvscanvx(Tk *tk, char *arg, char **val)
{
	int x, s;
	TkCanvas *c;
	Point p;
	char buf[Tkmaxitem];

	c = TKobj(TkCanvas, tk);
	arg = tkword(tk->env->top, arg, buf, buf+sizeof(buf), nil);
	if(buf[0] == '\0')
		return TkBadvl;

	p = tkposn(tk);
	x = atoi(buf) + c->view.x - (p.x + tk->borderwidth);

	if(*arg) {
		tkword(tk->env->top, arg, buf, buf+sizeof(buf), nil);
		s = atoi(buf);
		if ( s )
			x = (x+(s/2)/s)*s;
	}
	return tkvalue(val, "%d", x);
}

char*
tkcvscanvy(Tk *tk, char *arg, char **val)
{
	int y, s;
	TkCanvas *c;
	Point p;
	char buf[Tkmaxitem];

	c = TKobj(TkCanvas, tk);
	arg = tkword(tk->env->top, arg, buf, buf+sizeof(buf), nil);
	if(buf[0] == '\0')
		return TkBadvl;

	p = tkposn(tk);
	y = atoi(buf) + c->view.y - (p.y + tk->borderwidth);

	if(*arg) {
		tkitem(buf, arg);
		s = atoi(buf);
		if ( s )
			y = (y+(s/2)/s)*s;
	}
	return tkvalue(val, "%d", y);
}

char *
tkcvsscreenx(Tk *tk, char *arg, char **val)
{
	int x;
	TkCanvas *c;
	Point p;
	char buf[Tkmaxitem];

	c = TKobj(TkCanvas, tk);
	tkword(tk->env->top, arg, buf, buf+sizeof(buf), nil);
	if(buf[0] == '\0')
		return TkBadvl;
	p = tkposn(tk);
	x = atoi(buf) - c->view.x + (p.x + tk->borderwidth);
	return tkvalue(val, "%d", x);
}

char *
tkcvsscreeny(Tk *tk, char *arg, char **val)
{
	int y;
	TkCanvas *c;
	Point p;
	char buf[Tkmaxitem];

	c = TKobj(TkCanvas, tk);
	tkword(tk->env->top, arg, buf, buf+sizeof(buf), nil);
	if(buf[0] == '\0')
		return TkBadvl;
	p = tkposn(tk);
	y = atoi(buf) - c->view.y + (p.y + tk->borderwidth);
	return tkvalue(val, "%d", y);
}

char*
tkcvscoords(Tk *tk, char *arg, char **val)
{
	int i;
	Point *p;
	TkCtag *t;
	TkName *f;
	TkCanvas *c;
	TkCitem *item;
	char *fmt, *e, *v, buf[Tkmaxitem];

	arg = tkword(tk->env->top, arg, buf, buf+sizeof(buf), nil);
	if(buf[0] == '\0')
		return TkBadvl;

	f = tkctaglook(tk, nil, buf);
	if(f == nil || f->obj == nil)
		return TkBadtg;

	c = TKobj(TkCanvas, tk);

	t = tkcfirsttag(c->head, f->obj);
	if(t == nil)
		return TkBadtg;

	item = t->item;

	if(*arg == '\0') {
		fmt = "%s";
		p = item->p.parampt;
		for(i = 0; i < item->p.npoint; i++) {
			v = tkfprint(buf, p->x);
			*v++ = ' ';
			tkfprint(v, p->y);
			e = tkvalue(val, fmt, buf);
			if(e != nil)
				return e;
			fmt = " %s";
			p++;
		}
		return nil;
	}

	tkbbmax(&c->update, &item->p.bb);
	e = tkcimethod[item->type].coord(item, arg, 0, 0);
	tkbbmax(&c->update, &item->p.bb);
	tk->flag |= Tkdirty;
	return e;
}

char*
tkcvsscale(Tk *tk, char *arg, char **val)
{
	TkName *f;
	TkCtag *t;
	TkCanvas *c;
	TkCpoints pts;
	TkCitem *item;
	int j;
	char *e, buf[Tkmaxitem];
	Point *p, *d, origin, scalef;

	USED(val);

	c = TKobj(TkCanvas, tk);

	arg = tkword(tk->env->top, arg, buf, buf+sizeof(buf), nil);
	f = tkctaglook(tk, nil, buf);
	if(f == nil || f->obj == nil)
		return TkBadtg;

	pts.parampt = nil;
	pts.drawpt = nil;
	e = tkparsepts(tk->env->top, &pts, &arg, 0);
	if(e != nil) {
		tkfreepoint(&pts);
		return e;
	}
	if(pts.npoint != 2) {
		tkfreepoint(&pts);
		return TkFewpt;
	}
	origin = pts.parampt[0];
	scalef = pts.parampt[1];
	tkfreepoint(&pts);
	for(t = f->obj; t; t = t->taglist) {
		item = t->item;
		p = item->p.parampt;
		d = item->p.drawpt;
		for(j = 0; j < item->p.npoint; j++) {
			p->x -= origin.x;
			p->y -= origin.y;
			p->x = (p->x*scalef.x)/Tkfpscalar;
			p->y = (p->y*scalef.y)/Tkfpscalar;
			p->x += origin.x;
			p->y += origin.y;
			d->x = TKF2I(p->x);
			d->y = TKF2I(p->y);
			d++;
			p++;
		}
		tkbbmax(&c->update, &item->p.bb);
		e = tkcimethod[item->type].coord(item, nil, 0, 0);
		tkbbmax(&c->update, &item->p.bb);
		if(e != nil)
			return e;

		tk->flag |= Tkdirty;		
	}
	return nil;
}

char*
tkcvsdtag(Tk *tk, char *arg, char **val)
{
	TkName *f, *dt;
	char buf[Tkmaxitem];
	TkCtag **l, *t, *it, *tf;

	USED(val);

	arg = tkword(tk->env->top, arg, buf, buf+sizeof(buf), nil);
	f = tkctaglook(tk, nil, buf);
	if(f == nil || f->obj == nil)
		return TkBadtg;

/*
	XXX this code doesn't appear to work properly.
	fix it later. for the moment, it's just a somewhat more
	efficient substitute for the later code, so just use that
	instead.

	if(*arg == '\0') {
		for(t = f->obj; t; t = tf) {
			l = &t->item->stag;
			for(it = *l; it; it = it->itemlist) {
				if(it->item == t->item) {
					*l = it->itemlist;
					break;
				}
				l = &it->itemlist;
			}

			tf = t->taglist;
			free(t);
		}
		f->obj = nil;
		return nil;
	}
*/
	if (*arg == '\0')
		dt = f;
	else {
		tkword(tk->env->top, arg, buf, buf+sizeof(buf), nil);
		dt = tkctaglook(tk, nil, buf);
		if(dt == nil || dt->obj == nil)
			return TkBadtg;
	}

	for(t = f->obj; t; t = t->taglist) {
		l = (TkCtag **)&dt->obj;
		for(it = dt->obj; it; it = it->taglist) {
			if(t->item == it->item) {
				*l = it->taglist;
				l = &t->item->stag;
				for(tf = *l; tf; tf = tf->itemlist) {
					if(tf == it) {
						*l = tf->itemlist;
						break;
					}
					l = &tf->itemlist;
				}
				free(it);
				break;
			}
			l = &it->taglist;
		}
	}
	return nil;
}

char*
tkcvsdchars(Tk *tk, char *arg, char **val)
{
	TkCtag *t;
	TkName *f;
	char *e, buf[Tkmaxitem];

	USED(val);

	arg = tkword(tk->env->top, arg, buf, buf+sizeof(buf), nil);
	f = tkctaglook(tk, nil, buf);
	if(f == nil || f->obj == nil)
		return TkBadtg;

	for(t = f->obj; t; t = t->taglist) {
		if(t->item->type == TkCVtext) {
			e = tkcvstextdchar(tk, t->item, arg);
			if(e != nil)
				return e;
		}
	}

	return nil;
}

char*
tkcvsindex(Tk *tk, char *arg, char **val)
{
	TkCtag *t;
	TkName *f;
	char *e, buf[Tkmaxitem];

	USED(val);

	arg = tkword(tk->env->top, arg, buf, buf+sizeof(buf), nil);
	f = tkctaglook(tk, nil, buf);
	if(f == nil || f->obj == nil)
		return TkBadtg;

	for(t = f->obj; t; t = t->taglist) {
		if(t->item->type == TkCVtext) {
			e = tkcvstextindex(tk, t->item, arg, val);
			if(e != nil)
				return e;
			return nil;
		}
	}
	return nil;
}

char*
tkcvsicursor(Tk *tk, char *arg, char **val)
{
	TkCtag *t;
	TkName *f;
	char *e, buf[Tkmaxitem];

	USED(val);

	arg = tkword(tk->env->top, arg, buf, buf+sizeof(buf), nil);
	f = tkctaglook(tk, nil, buf);
	if(f == nil || f->obj == nil)
		return TkBadtg;

	for(t = f->obj; t; t = t->taglist) {
		if(t->item->type == TkCVtext) {
			e = tkcvstexticursor(tk, t->item, arg);
			if(e != nil)
				return e;
			return nil;
		}
	}
	return nil;
}

char*
tkcvsinsert(Tk *tk, char *arg, char **val)
{
	TkCtag *t;
	TkName *f;
	char *e, buf[Tkmaxitem];

	USED(val);

	arg = tkword(tk->env->top, arg, buf, buf+sizeof(buf), nil);
	f = tkctaglook(tk, nil, buf);
	if(f == nil || f->obj == nil)
		return TkBadtg;

	for(t = f->obj; t; t = t->taglist) {
		if(t->item->type == TkCVtext) {
			e = tkcvstextinsert(tk, t->item, arg);
			if(e != nil)
				return e;
		}
	}

	return nil;
}

char*
tkcvsselect(Tk *tk, char *arg, char **val)
{
	int op;
	TkCtag *t;
	TkName *f;
	TkCanvas *c;
	char buf[Tkmaxitem];

	c = TKobj(TkCanvas, tk);

	arg = tkword(tk->env->top, arg, buf, buf+sizeof(buf), nil);
	if(strcmp(buf, "clear") == 0) {
		tkcvstextclr(tk);
		return nil;		
	}
	if(strcmp(buf, "item") == 0) {
		if(c->selection)
			return tkvalue(val, "%d", c->selection->id);
		return nil;		
	}

	if(strcmp(buf, "to") == 0)
		op = TkCselto;
	else
	if(strcmp(buf, "from") == 0)
		op = TkCselfrom;
	else
	if(strcmp(buf, "adjust") == 0)
		op = TkCseladjust;
	else
		return TkBadcm;

	arg = tkword(tk->env->top, arg, buf, buf+sizeof(buf), nil);
	f = tkctaglook(tk, nil, buf);
	if(f == nil)
		return TkBadtg;

	t = tkcfirsttag(c->head, f->obj);
	if(t == nil)
		return TkBadtg;

	return tkcvstextselect(tk, t->item, arg, op);
}

char*
tkcvsitemcget(Tk *tk, char *arg, char **val)
{
	TkName *f;
	TkCtag *t;
	TkCitem *i;
	char buf[Tkmaxitem];

	arg = tkword(tk->env->top, arg, buf, buf+sizeof(buf), nil);
	f = tkctaglook(tk, nil, buf);
	if(f == nil || f->obj == nil)
		return TkBadtg;

	for(i = TKobj(TkCanvas, tk)->head; i; i = i->next) {
		for(t = f->obj; t; t = t->taglist)
			if(i == t->item)
				return tkcimethod[i->type].cget(i, arg, val);
	}
	return nil;
}

char*
tkcvsitemconf(Tk *tk, char *arg, char **val)
{
	char *e;
	TkName *f;
	TkCtag *t;
	TkCitem *i;
	TkCanvas *c;
	char buf[Tkmaxitem];

	USED(val);
	arg = tkword(tk->env->top, arg, buf, buf+sizeof(buf), nil);
	f = tkctaglook(tk, nil, buf);
	if(f == nil || f->obj == nil)
		return TkBadtg;

	c = TKobj(TkCanvas, tk);
	for(t = f->obj; t; t = t->taglist) {
		for(i = c->head; i; i = i->next) {
			if(i == t->item) {
				tkbbmax(&c->update, &i->p.bb);
				e = tkcimethod[i->type].conf(tk, i, arg);
				tkbbmax(&c->update, &i->p.bb);
				tk->flag |= Tkdirty;
				if(e != nil)
					return e;
			}
		}
	}
	return nil;
}

static void
tkcvsfreename(TkCanvas *c, TkName *n)
{
	ulong h;
	char *p, *s;
	TkName *f, **l;
	
	/* just free implicit ones for now */
	if(n == nil)
		return;
	s = n->name;
	if(s == nil || (s[0] < '0' || s[0] > '9'))
		return;
	h = 0;
	for(p = s; *p; p++)
		h += 3*h + *p;
	l = &c->thash[h%TkChash];
	for(f = *l; f; l = &f->link, f = *l)
		if(f == n){
			*l = f->link;
			tkfreebind(f->prop.binds);
			free(f);
			return;
		}
}

char*
tkcvsdelete(Tk *tk, char *arg, char **val)
{
	TkName *f;
	TkCanvas *c;
	char buf[Tkmaxitem];
	TkCitem *item, *prev, *i;
	TkCtag *t, *inext, **l, *dit, *it;

	USED(val);

	c = TKobj(TkCanvas, tk);
	for(;;) {
		arg = tkword(tk->env->top, arg, buf, buf+sizeof(buf), nil);
		if(buf[0] == '\0')
			break;
		f = tkctaglook(tk, nil, buf);
		if(f == nil || f->obj == nil)
			return nil;
		while(f->obj) {
			t = f->obj;
			item = t->item;
			for(it = item->stag; it; it = inext) {
				inext = it->itemlist;
				l = (TkCtag **)&it->name->obj;
				for(dit = *l; dit; dit = dit->taglist) {
					if(dit->item == item) {
						*l = dit->taglist;
						if(dit != t){
							tkcvsfreename(c, dit->name);
							free(dit);
						}
						break;
					}
					l = &dit->taglist;
				}
			}
			tkbbmax(&c->update, &item->p.bb);
			tk->flag |= Tkdirty;
			prev = nil;
			for(i = c->head; i; i = i->next) {
				if(i == item)
					break;
				prev = i;
			}
			if(prev == nil)
				c->head = i->next;
			else
				prev->next = i->next;
			if(c->tail == item)
				c->tail = prev;
			if(c->focus == item)
				c->focus = nil;
			if(c->mouse == item)
				c->mouse = nil;
			if(c->selection == item)
				c->selection = nil;
			if(c->curtag.item == item)
				c->current->obj = nil;
			if (c->grab == item)
				c->grab = nil;

			tkcvsfreeitem(item);
			free(t);
		}
	}
	return nil;
}

char*
tkcvsfocus(Tk *tk, char *arg, char **val)
{
	TkName *f;
	TkCtag *t;
	TkCanvas *c;
	TkCitem *i, *focus;
	char buf[Tkmaxitem];

	c = TKobj(TkCanvas, tk);

	if(*arg == '\0') {
		if(c->focus == nil)
			return nil;
		return tkvalue(val, "%d", c->focus->id);
	}

	tkword(tk->env->top, arg, buf, buf+sizeof(buf), nil);
	if(buf[0] == '\0')
		return TkBadvl;
	f = tkctaglook(tk, nil, buf);
	if(f == nil || f->obj == nil)
		return nil;

	focus = c->focus;
	tkcvstextfocus(tk, focus, 0);

	for(i = c->head; i; i = i->next) {
		if(i->type == TkCVtext || i->type == TkCVwindow) {
			for(t = f->obj; t; t = t->taglist)
				if(t->item == i)
					focus = i;
		}
	}

	if(focus->type == TkCVtext)
		tkcvstextfocus(tk, focus, 1);

	c->focus = focus;
	return nil;
}

char*
tkcvsgettags(Tk *tk, char *arg, char **val)
{
	TkCtag *t;
	TkName *f;
	TkCanvas *c;
	char *fmt, *e, buf[Tkmaxitem];

	tkword(tk->env->top, arg, buf, buf+sizeof(buf), nil);
	if(buf[0] == '\0')
		return TkBadvl;

	f = tkctaglook(tk, nil, buf);
	if(f == nil)
		return TkBadtg;

	c = TKobj(TkCanvas, tk);
	t = tkclasttag(c->head, f->obj);
	if(t == nil)
		return TkBadtg;
	fmt = "%s";
	t = t->item->stag;
	while(t) {
		/* XXX when might t->name be legally nil? */
		if (t->name != nil) {
			if (strcmp(t->name->name, "all")) {
				e = tkvalue(val, fmt, t->name->name);
				if(e != nil)
					return e;
				fmt = " %s";
			}
		}
		t = t->itemlist;
	}
	return nil;
}

char*
tkcvslower(Tk *tk, char *arg, char **val)
{
	TkCtag *t;
	TkCanvas *c;
	TkName *f, *b;
	char buf[Tkmaxitem];
	TkCitem *it, **l, **below, *items, **itemtail, *prev, *iprev;

	USED(val);
	c = TKobj(TkCanvas, tk);

	arg = tkword(tk->env->top, arg, buf, buf+sizeof(buf), nil);
	f = tkctaglook(tk, nil, buf);
	if(f == nil || f->obj == nil)
		return nil;

	below = &c->head;
	tkword(tk->env->top, arg, buf, buf+sizeof(buf), nil);
	if(buf[0] != '\0') {
		b = tkctaglook(tk, nil, buf);
		if(b == nil || f->obj == nil)
			return TkBadtg;
		for(it = c->head; it; it = it->next) {
			for(t = b->obj; t; t = t->taglist)
				if(t->item == it)
					goto found;
			below = &it->next;
		}
	found:;
	}
	l = &c->head;
	prev = iprev = nil;
	itemtail = &items;;
	for (it = *l; it != nil; it = *l) {
		for (t = f->obj; t; t = t->taglist) {
			if(t->item == it) {
				if (it == *below || below == &it->next)
					below = l;
				if (it == c->tail)
					c->tail = prev;
				*l = it->next;
				*itemtail = it;
				iprev = it;
				itemtail = &it->next;
				tkbbmax(&c->update, &it->p.bb);
				goto next;
			}
		}
		prev = it;
		l = &it->next;
next:;
	}
	if (prev == nil)
		c->tail = iprev;
	*itemtail = *below;
	*below = items;
	tk->flag |= Tkdirty;
	return nil;
}

char*
tkcvsmove(Tk *tk, char *arg, char **val)
{
	TkCtag *t;
	int fx, fy;
	TkTop *top;
	TkCpoints *p;
	TkName *tag;
	Rectangle *u;
	TkCitem *item;
	char buf[Tkmaxitem];

	USED(val);
	top = tk->env->top;
	arg = tkword(top, arg, buf, buf+sizeof(buf), nil);
	tag = tkctaglook(tk, nil, buf);
	if(tag == nil)
		return nil;

	arg = tkfrac(top, arg, &fx, nil);
	if(*arg == '\0')
		return TkBadvl;
	arg = tkfrac(top, arg, &fy, nil);
	if(*arg != '\0')
		return TkBadvl;

	u = &TKobj(TkCanvas, tk)->update;
	for(t = tag->obj; t; t = t->taglist) {
		item = t->item;
		p = &item->p;
		tkbbmax(u, &p->bb);
		tkcimethod[item->type].coord(item, nil, fx, fy);
		tkbbmax(u, &p->bb);
	}
	tk->flag |= Tkdirty;
	return nil;
}

char*
tkcvsraise(Tk *tk, char *arg, char **val)
{
	TkCtag *t;
	TkCanvas *c;
	TkName *f, *a;
	char buf[Tkmaxitem];
	TkCitem *last, *it, *above, *items, *itemtail, *next;

	USED(val);
	c = TKobj(TkCanvas, tk);

	arg = tkword(tk->env->top, arg, buf, buf+sizeof(buf), nil);
	f = tkctaglook(tk, nil, buf);
	if(f == nil)
		return nil;

	above = c->tail;
	tkword(tk->env->top, arg, buf, buf+sizeof(buf), nil);
	if(buf[0] != '\0') {
		a = tkctaglook(tk, nil, buf);
		if(a == nil)
			return TkBadtg;
		for(it = c->head; it != nil; it = it->next) {
			for(t = a->obj; t; t = t->taglist)
				if(t->item == it)
					above = it;
		}
	}
	last = nil;
	items = itemtail = nil;
	for (it = c->head; it != nil; it = next) {
		next = it->next;
		for (t = f->obj; t; t = t->taglist) {
			if(t->item == it) {
				if (it == above)
					above = next;
				if (last)
					last->next = next;
				else
					c->head = next;
				if (itemtail)
					itemtail->next = it;
				else
					items = it;
				itemtail = it;
				tkbbmax(&c->update, &it->p.bb);
				goto next;
			}
		}
		last = it;
next:;
	}
	if (items != nil) {
		if (above) {
			itemtail->next = above->next;
			if (above->next == nil)
				c->tail = itemtail;
			above->next = items;
		} else {
			if (last)
				last->next = items;
			else
				c->head = items;
			c->tail = itemtail;
		}
		itemtail->next = nil;
	}

	tk->flag |= Tkdirty;
	return nil;
}

char*
tkcvstype(Tk *tk, char *arg, char **val)
{
	TkCtag *t;
	TkName *f;
	TkCanvas *c;
	char buf[Tkmaxitem];

	tkword(tk->env->top, arg, buf, buf+sizeof(buf), nil);
	if(buf[0] == '\0')
		return TkBadvl;

	f = tkctaglook(tk, nil, buf);
	if(f == nil || f->obj == nil)
		return TkBadtg;

	c = TKobj(TkCanvas, tk);

	t = tkcfirsttag(c->head, f->obj);
	if(t == nil)
		return TkBadtg;

	return tkvalue(val, "%s", tkcimethod[t->item->type].name);
}

static char*
tkcvsview(Tk *tk, char *arg, char **val, int nl, int *posn, int min, int max, int inc)
{
	TkTop *t;
	TkCanvas *c;
	int top, bot, diff, amount;
	char buf[Tkmaxitem], *v;

	c = TKobj(TkCanvas, tk);

	diff = max-min;
	if(*arg == '\0') {
		if ( diff == 0 ) 
			top = bot = 0;
		else {
			top = (*posn-min)*Tkfpscalar/diff;
			bot = (*posn+nl-min)*Tkfpscalar/diff;
		}
		v = tkfprint(buf, top);
		*v++ = ' ';
		tkfprint(v, bot);
		return tkvalue(val, "%s", buf);
	}

	t = tk->env->top;
	arg = tkword(t, arg, buf, buf+sizeof(buf), nil);
	if(strcmp(buf, "moveto") == 0) {
		tkfrac(t, arg, &top, nil);
		*posn = min + (top+1)*diff/Tkfpscalar;
	}
	else
	if(strcmp(buf, "scroll") == 0) {
		arg = tkword(t, arg, buf, buf+sizeof(buf), nil);
		amount = atoi(buf);
		tkword(t, arg, buf, buf+sizeof(buf), nil);
		if(buf[0] == 'p')		/* Pages */
			amount = amount * nl * 9 /10;
		else if (inc > 0)
			amount *= inc;
		else
			amount = amount * nl / 10;
		*posn += amount;
	}
	else	
		return TkBadcm;

	bot = max - nl;
	if(*posn > bot)
		*posn = bot;
	if(*posn < min)
		*posn = min;

	tk->flag |= Tkdirty;
	c->cleanup = 1;
	return nil;
}

char*
tkcvsyview(Tk *tk, char *arg, char **val)
{
	int si;
	char *e;
	TkCanvas *c = TKobj(TkCanvas, tk);

	si = TKF2I(c->yscrolli);
	e = tkcvsview(tk, arg, val, tk->act.height, &c->view.y, c->region.min.y, c->region.max.y, si); 
	tkcvssv(tk);
	return e;
}

char*
tkcvsxview(Tk *tk, char *arg, char **val)
{
	int si;
	char *e;
	TkCanvas *c = TKobj(TkCanvas, tk);

	si = TKF2I(c->xscrolli);
	e = tkcvsview(tk, arg, val, tk->act.width, &c->view.x, c->region.min.x, c->region.max.x, si);
	tkcvssh(tk);
	return e;
}

static int
tkcvsseeone(int *posn, int cmin, int cmax, int smin, int smax)
{
	int v;

	if (cmin <= smin && smin < cmax && cmin <= smax && smax < cmax)
		return 0;
	if (cmin <= smin && smin < cmax)
		v = smax;
	else if (cmin <= smax && smax < cmax)
		v = smin;
	else if (smin >= cmax)
		v = smax;
	else
		v = smin;
	/* v is point to be made visible */
	if (v >= cmax)
		v -= (cmax - cmin);
	*posn = v;
	return 1;
}

			
char*
tkcvssee(Tk *tk, char *arg, char **val)
{
	int scrollv, scrollh;
	TkCanvas *c = TKobj(TkCanvas, tk);
	Rectangle r;
	int n, coords[4];
	char buf[Tkmaxitem];

	USED(val);
	n = 0;
	while (n < 4) {
		arg = tkword(tk->env->top, arg, buf, buf+sizeof(buf), nil);
		if (buf[0] == 0)
			break;
		if (tkfrac(tk->env->top, buf, &coords[n++], nil) == nil)
			return TkBadvl;
	}

	if (n != 2 && n != 4)
		return TkFewpt;

	r.min.x = TKF2I(coords[0]);
	r.min.y = TKF2I(coords[1]);
	if (n == 4) {
		r.max.x = TKF2I(coords[2]);
		r.max.y = TKF2I(coords[3]);
	} else
		r.max = r.min;
	r = canonrect(r);

	scrollh = tkcvsseeone(&c->view.x, c->view.x, c->view.x + tk->act.width,
			r.min.x, r.max.x);
	scrollv = tkcvsseeone(&c->view.y, c->view.y, c->view.y + tk->act.height,
			r.min.y, r.max.y);
	if (scrollh)
		tkcvssh(tk);
	if (scrollv)
		tkcvssv(tk);
	if (scrollh || scrollv) {
		tk->flag |= Tkdirty;
		c->cleanup = 1;
	}
	return nil;
}
