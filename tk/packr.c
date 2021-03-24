#include "lib9.h"
#include "image.h"
#include "tk.h"

#define	O(t, e)		((long)(&((t*)0)->e))

typedef struct Pack Pack;
struct Pack 
{
	Tk*	t;
	Pack*	next;
};
static Pack *packorder;

typedef struct TkParam TkParam;
struct TkParam
{
	Point	pad;
	Point	ipad;
	int	side;
	int	anchor;
	int	fill;
	Tk*	in;
	Tk*	before;
	Tk*	after;
	int	expand;
};

static
TkOption opts[] =
{
	"padx",		OPTdist,	O(TkParam, pad.x),	nil,
	"pady",		OPTdist,	O(TkParam, pad.y),	nil,
	"ipadx",	OPTdist,	O(TkParam, ipad.x),	nil,
	"ipady",	OPTdist,	O(TkParam, ipad.y),	nil,
	"side",		OPTflag,	O(TkParam, side),	tkside,
	"anchor",	OPTflag,	O(TkParam, anchor),	tkanchor,
	"fill",		OPTflag,	O(TkParam, fill),	tkfill,
	"in",		OPTwinp,	O(TkParam, in),		nil,
	"before",	OPTwinp,	O(TkParam, before),	nil,
	"after",	OPTwinp,	O(TkParam, after),	nil,
	"expand",	OPTstab,	O(TkParam, expand),	tkbool,
	nil
};

void
tkdelpack(Tk *t)
{
	Tk *f, **l;

	if(t->master == nil)
		return;

	l = &t->master->slave;
	for(f = *l; f; f = f->next) {
		if(f == t) {
			*l = t->next;
			break;
		}
		l = &f->next;
	}
	t->master = nil;
}

void
tkappendpack(Tk *parent, Tk *tk, int where)
{
	Tk *f, **l;

	tk->master = parent;
	l = &parent->slave;
	for(f = *l; f; f = f->next) {
		if(where-- == 0)
			break;
		l = &f->next;
	}
	*l = tk;
	tk->next = f;

	for( ; parent != nil; parent = parent->master)
		if(parent->parent != nil){
			tk->flag |= Tksubsub;
			break;
		}
}

static void
tkpackqrm(Tk *t)
{
	Pack *f, **l;

	l = &packorder;
	for(f = *l; f; f = f->next) {
		if(f->t == t) {
			*l = f->next;
			free(f);
			break;
		}
		l = &f->next;
	}
}

/* XXX - Tad: leaky... should propagate  */
void
tkpackqit(Tk *t)
{
	Pack *f;

	if(t == nil || (t->flag & Tkdestroy))
		return;

	tkpackqrm(t);
	f = malloc(sizeof(Pack));
	if(f == nil) {
		print("tkpackqit: malloc failed\n");
		return;
	}

	f->t = t;
	f->next = packorder;
	packorder = f;
}

void
tkrunpack(TkTop *t)
{
	TkCtxt *ctxt;

	while(packorder != nil)
		tkpacker(packorder->t);
	ctxt = t->ctxt;
	tkenterleave(ctxt, ctxt->tkmstate.x, ctxt->tkmstate.y);
}

void
tksetopt(TkParam *p, Tk *tk)
{
	if(p->pad.x != 0)
		tk->pad.x = p->pad.x*2;
	if(p->pad.y != 0)
		tk->pad.y = p->pad.y*2;
	if(p->ipad.x != 0)
		tk->ipad.x = p->ipad.x*2;
	if(p->ipad.y != 0)
		tk->ipad.y = p->ipad.y*2;
	if(p->side != 0) {
		tk->flag &= ~Tkside;
		tk->flag |= p->side;
	}
	if(p->anchor != 0) {
		tk->flag &= ~Tkanchor;
		tk->flag |= p->anchor;
	}
	if(p->fill != 0) {
		tk->flag &= ~Tkfill;
		tk->flag |= p->fill;
	}
	if(p->expand != BoolX) {
		if(p->expand == BoolT) {
			tk->flag |= Tkexpand;
		}
		else
			tk->flag &= ~Tkexpand;
	}
}

static char*
tkforget(TkTop *t, char *arg)
{
	Tk *f, *tk, **l;
	char *buf;

	buf = mallocz(Tkmaxitem, 0);
	if(buf == nil)
		return TkNomem;
	for(;;) {
		arg = tkword(t, arg, buf, buf+Tkmaxitem, nil);
		if(buf[0] == '\0')
			break;
		tk = tklook(t, buf, 0);
		if(tk == nil) {
			tkrunpack(t);
			tkerr(t, buf);
			free(buf);
			return TkBadwp;
		}
		if(tk->master != 0) {
			l = &tk->master->slave;
			for(f = *l; f; f = f->next) {
				if(f == tk) {
					*l = tk->next;
					tkpackqit(tk->master);
					tk->master = nil;
					break;
				}
				l = &f->next;
			}
		}
	}
	free(buf);
	tkrunpack(t);
	return nil;
}

static char*
tkpropagate(TkTop *t, char *arg)
{
	Tk *tk;
	TkStab *s;
	char *buf;

	buf = mallocz(Tkmaxitem, 0);
	if(buf == nil)
		return TkNomem;
	arg = tkword(t, arg, buf, buf+Tkmaxitem, nil);
	tk = tklook(t, buf, 0);
	if(tk == nil) {
		tkerr(t, buf);
		free(buf);
		return TkBadwp;
	}

	tkword(t, arg, buf, buf+Tkmaxitem, nil);
	for(s = tkbool; s->val; s++) {
		if(strcmp(s->val, buf) == 0) {
			if(s->con == BoolT)
				tk->flag &= ~Tknoprop;
			else
				tk->flag |= Tknoprop;
			free(buf);
			return nil;
		}
	}
	free(buf);
	return TkBadvl;
}

static char*
tkslaves(TkTop *t, char *arg, char **val)
{
	Tk *tk;
	char *fmt, *e, *buf;

	buf = mallocz(Tkmaxitem, 0);
	if(buf == nil)
		return TkNomem;
	tkword(t, arg, buf, buf+Tkmaxitem, nil);
	tk = tklook(t, buf, 0);
	if(tk == nil){
		tkerr(t, buf);
		free(buf);
		return TkBadwp;
	}
	free(buf);

	fmt = "%s";
	for(tk = tk->slave; tk; tk = tk->next) {
		if (tk->name != nil) {
			e = tkvalue(val, fmt, tk->name->name);
			if(e != nil)
				return e;
			fmt = " %s";
		}
	}
	
	return nil;
}

static int
tkisslave(Tk *in, Tk *tk)
{
	if(in == nil)
		return 0;
	if(in == tk)
		return 1;
	for(tk = tk->slave; tk; tk = tk->next)
		if(tkisslave(in, tk))
			return 1;
	return 0;
}

char*
tkpack(TkTop *t, char *arg, char **val)
{
	TkParam *p;
	TkOptab tko[2];
	Tk *tk, **l, *tkp;
	TkName *names, *n;
	char *e, *w, *buf;

	buf = mallocz(Tkminitem, 0);
	if(buf == nil)
		return TkNomem;

	w = tkword(t, arg, buf, buf+Tkminitem, nil);
	if(strcmp(buf, "forget") == 0) {
		e = tkforget(t, w);
		free(buf);
		return e;
	}
	if(strcmp(buf, "propagate") == 0) {
		e = tkpropagate(t, w);
		free(buf);
		return e;
	}
	if(strcmp(buf, "slaves") == 0) {
		e = tkslaves(t, w, val);
		free(buf);
		return e;
	}
	free(buf);

	p = mallocz(sizeof(TkParam), 1);
	if(p == nil)
		return TkNomem;
	tko[0].ptr = p;
	tko[0].optab = opts;
	tko[1].ptr = nil;

	names = nil;
	e = tkparse(t, arg, tko, &names);
	if(e != nil) {
		free(p);
		return e;
	}

	if((p->before && p->before->master == nil) ||
	   (p->after && p->after->master == nil)) {
		tkfreename(names);
		free(p);
		return TkNotpk;
	}

	for(n = names; n; n = n->link) {
		tkp = tklook(t, n->name, 0);
		if(tkp == nil) {
			tkerr(t, n->name);
			tkfreename(names);
			free(p);
			return TkBadwp;
		}
		if(tkp->flag & Tkwindow) {
			tkfreename(names);
			free(p);
			return TkIstop;
		}
		if(tkp->parent != nil) {
			tkfreename(names);
			free(p);
			return TkWpack;
		}
		n->obj = tkp;
	}

	e = nil;
	for(n = names; n; n = n->link) {
		tk = n->obj;
		if(tk->master == nil) {
			tk->pad = ZP;
			tk->ipad = ZP;
			tk->flag &= ~(Tkanchor|Tkside|Tkfill|Tkexpand);
			tk->flag |= Tktop|Tkcenter;
		}
		if(tk->master != nil) {
			tkpackqit(tk->master);
			tkdelpack(tk);
		}
		if(p->before == nil && p->after == nil && p->in == nil) {
			if(tk->master == nil) {
				tkp = tklook(t, n->name, 1);
				if(tkp == nil) {
					tkerr(t, n->name);
					tkfreename(names);
					free(p);
					return TkBadwp;
				}
				if(tkisslave(tkp, tk)) {
					e = TkRecur;
					continue;
				}
				tkappendpack(tkp, tk, -1);
			}
			else
				if(tkisslave(tk->master, tk)) {
					e = TkRecur;
					continue;
				}
		}
		else {
			if(p->in != nil) {
				if(tkisslave(p->in, tk)) {
					e = TkRecur;
					continue;
				}
				tkappendpack(p->in, tk, -1);
			}
			else
			if(p->before != nil) {
				if(tkisslave(p->before->master, tk)) {
					e = TkRecur;
					continue;
				}
				tk->master = p->before->master;
				l = &tk->master->slave;
				for(;;) {
					if(*l == p->before) {
						tk->next = *l;
						*l = tk;
						break;
					}
					l = &(*l)->next;
				}
				p->before = tk;
			}
			else {
				if(tkisslave(p->after->master, tk)) {
					e = TkRecur;
					continue;
				}
				tk->master = p->after->master;
				tk->next = p->after->next;
				p->after->next = tk;
				p->after = tk;
			}
		}
		tksetopt(p, tk);
		tkpackqit(tk->master);
	}
	tkfreename(names);
	tkrunpack(t);
	free(p);

	return e;
}

static int
tkexpandx(Tk* slave, int cavityWidth)
{
	int numExpand, minExpand, curExpand, childWidth;

	minExpand = cavityWidth;
	numExpand = 0;
	for( ;slave != nil; slave = slave->next) {
		childWidth = slave->req.width + slave->borderwidth*2 +
				slave->pad.x + slave->ipad.x;
		if(slave->flag & (Tktop|Tkbottom)) {
			curExpand = (cavityWidth - childWidth)/numExpand;
			if (curExpand < minExpand)
				minExpand = curExpand;
		}
		else {
	    		cavityWidth -= childWidth;
	    		if(slave->flag & Tkexpand)
				numExpand++;
		}
	}
	curExpand = cavityWidth/numExpand;
	if(curExpand < minExpand)
		minExpand = curExpand;

	return (minExpand < 0) ? 0 : minExpand;
}

static int
tkexpandy(Tk *slave, int cavityHeight)
{
	int numExpand, minExpand, curExpand, childHeight;

	minExpand = cavityHeight;
	numExpand = 0;
	for ( ;slave != nil; slave = slave->next) {
		childHeight = slave->req.height + slave->borderwidth*2 +
			+ slave->pad.y + slave->ipad.y;
		if(slave->flag & (Tkleft|Tkright)) {
			curExpand = (cavityHeight - childHeight)/numExpand;
			if(curExpand < minExpand)
				minExpand = curExpand;
		}
		else {
			cavityHeight -= childHeight;
			if(slave->flag & Tkexpand)
				numExpand++;
		}
	}
	curExpand = cavityHeight/numExpand;
	if(curExpand < minExpand)
		minExpand = curExpand;

	return (minExpand < 0) ? 0 : minExpand;
}

void
tkpacker(Tk *master)
{
	Tk *slave;
	Point border;
	void (*geomfn)(Tk*);
	TkGeom frame, cavity, pos, old;
	int maxwidth, maxheight, tmp, slave2BW;

	tksetbits(master, Tkdirty|Tkrefresh);

	pos.width = 0;
	pos.height = 0;
	maxwidth = 0;
	maxheight = 0;

	for (slave = master->slave; slave != nil; slave = slave->next) {
		slave2BW = slave->borderwidth*2;
		if(slave->flag & (Tktop|Tkbottom)) {
	    		tmp = slave->req.width + slave2BW +
		    		slave->pad.x + slave->ipad.x + pos.width;
			if(tmp > maxwidth)
				maxwidth = tmp;
	    		pos.height += slave->req.height + slave2BW +
		    		slave->pad.y + slave->ipad.y;
		}
		else {
	    		tmp = slave->req.height + slave2BW +
		    		slave->pad.y + slave->ipad.y + pos.height;
	    		if(tmp > maxheight)
				maxheight = tmp;
	    		pos.width += slave->req.width + slave2BW +
		    		+ slave->pad.x + slave->ipad.x;
		}
	}
	if(pos.width > maxwidth)
		maxwidth = pos.width;
	if(pos.height > maxheight)
		maxheight = pos.height;

	if(maxwidth != master->req.width || maxheight != master->req.height)
	if((master->flag & Tknoprop) == 0) {
		if(master->geom != nil) {
			master->geom(master, master->act.x, master->act.y, 
					maxwidth, maxheight);
		} else {
			master->req.width = maxwidth;
			master->req.height = maxheight;
			tkpackqit(master->master);
		}
		return;
    	}

    	cavity.x = 0;
	cavity.y = 0;
	pos.x = 0;
	pos.y = 0;
	cavity.width = master->act.width;
	cavity.height = master->act.height;

	for(slave = master->slave; slave != nil; slave = slave->next) {
		slave2BW = slave->borderwidth*2;
		if(slave->flag & (Tktop|Tkbottom)) {
	    		frame.width = cavity.width;
	    		frame.height = slave->req.height + slave2BW +
		    			slave->pad.y + slave->ipad.y;
	    		if(slave->flag & Tkexpand)
				frame.height += tkexpandy(slave, cavity.height);
	    		cavity.height -= frame.height;
	    		if(cavity.height < 0) {
				frame.height += cavity.height;
				cavity.height = 0;
	    		}
	    		frame.x = cavity.x;
	    		if(slave->flag & Tktop) {
				frame.y = cavity.y;
				cavity.y += frame.height;
	    		}
			else
				frame.y = cavity.y + cavity.height;
		}
		else {
	    		frame.height = cavity.height;
	    		frame.width = slave->req.width + slave2BW + 
					slave->pad.x + slave->ipad.x;
	    		if(slave->flag & Tkexpand)
				frame.width += tkexpandx(slave, cavity.width);
	    		cavity.width -= frame.width;
	    		if(cavity.width < 0) {
				frame.width += cavity.width;
				cavity.width = 0;
	    		}
	    		frame.y = cavity.y;
	    		if(slave->flag & Tkleft) {
				frame.x = cavity.x;
				cavity.x += frame.width;
	    		}
			else
				frame.x = cavity.x + cavity.width;
		}

		border.x = slave->pad.x;
		border.y = slave->pad.y;

		pos.width = slave->req.width + slave2BW + slave->ipad.x;
		if((slave->flag&Tkfillx) || (pos.width > (frame.width - border.x)))
			pos.width = frame.width - border.x;

		pos.height = slave->req.height + slave2BW + slave->ipad.y;
		if((slave->flag&Tkfilly) || (pos.height > (frame.height - border.y)))
	    		pos.height = frame.height - border.y;

		border.x /= 2;
		border.y /= 2;

		if(slave->flag & (Tknorth|Tknortheast|Tknorthwest))
			pos.y = frame.y + border.y;
		else
		if(slave->flag & (Tksouth|Tksoutheast|Tksouthwest))
			pos.y = frame.y + frame.height - pos.height - border.y;
		else
			pos.y = frame.y + (frame.height - pos.height)/2;

		if(slave->flag & (Tkwest|Tknorthwest|Tksouthwest))
			pos.x = frame.x + border.x;
		else
		if(slave->flag & (Tkeast|Tknortheast|Tksoutheast))
			pos.x = frame.x + frame.width - pos.width - border.x;
		else
			pos.x = frame.x + (frame.width - pos.width)/2;

		pos.width -= slave2BW;
		pos.height -= slave2BW;

		if(memcmp(&slave->act, &pos, sizeof(TkGeom)) != 0) {
			old = slave->act;
			slave->act = pos;
			geomfn = tkmethod[slave->type].geom;
			if(geomfn != nil && tkismapped(slave))
				geomfn(slave);
			if(slave->slave)
				tkpackqit(slave);
			tkdeliver(slave, TkConfigure, &old);

			slave->flag |= Tkdirty;
		}
	}

	if(master->parent != nil)
		tksetbits(master, Tksubsub);

	tkdirty(master);
	tkpackqrm(master);
}
