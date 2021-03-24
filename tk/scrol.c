#include "lib9.h"
#include "image.h"
#include "tk.h"

/* auto-repeating */
static void *autorpt;
static Tk	*actsb;

extern void	rptwakeup(Tk*, void*);
extern void*	rptproc(char*, int, int, void*, void*);

#define	O(t, e)		((long)(&((t*)0)->e))

static
TkOption opts[] =
{
	"activerelief",	OPTstab,	O(TkScroll, activer),	tkrelief,
	"command",	OPTtext,	O(TkScroll, cmd),	nil,
	"elementborderwidth",
			OPTdist,	O(TkScroll, elembw),	nil,
	"jump",		OPTbool,	O(TkScroll, jump),	nil,
	"orient",	OPTstab,	O(TkScroll, orient),	tkorient,
	nil
};

static
TkEbind b[] = 
{
	{TkLeave,		"%W activate {}"},
	{TkMotion,		"%W activate [%W identify %x %y]"},
	{TkButton1P|TkMotion,	"%W tkScrollDrag %x %y"},
	{TkButton1P,		"%W tkScrolBut1P %x %y"},
	{TkButton1P|TkDouble,	"%W tkScrolBut1P %x %y"},
	{TkButton1R,	"%W tkScrolBut1R; %W activate [%W identify %x %y]"},
	{TkButton2P,		"%W tkScrolBut2P [%W fraction %x %y]"},
};

char*
tkscrollbar(TkTop *t, char *arg, char **ret)
{
	Tk *tk;
	char *e;
	TkName *names;
	TkScroll *tks;
	TkOptab tko[3];

	tk = tknewobj(t, TKscrollbar, sizeof(Tk)+sizeof(TkScroll));
	if(tk == nil)
		return TkNomem;

	tks = TKobj(TkScroll, tk);

	tk->relief = TKsunken;
	tk->borderwidth = 2;
	tks->activer = TKraised;
	tks->orient = Tkvertical;
	tks->elembw = 2;

	tko[0].ptr = tk;
	tko[0].optab = tkgeneric;
	tko[1].ptr = tks;
	tko[1].optab = opts;
	tko[2].ptr = nil;

	names = nil;
	e = tkparse(t, arg, tko, &names);
	if(e != nil) {
		tkfreeobj(tk);
		return e;
	}

	e = tkinitscroll(tk);
	if(e != nil) {
		tkfreeobj(tk);
		return e;
	}

	e = tkaddchild(t, tk, &names);
	tkfreename(names);
	if(e != nil) {
		tkfreeobj(tk);
		return e;
	}
	tk->name->link = nil;

	return tkvalue(ret, "%s", tk->name->name);
}

char*
tkinitscroll(Tk *tk)
{
	int gap;
	TkScroll *tks;

	tks = TKobj(TkScroll, tk);
	
	if(tks->elembw < 0)
		tks->elembw = tk->borderwidth;

	gap = 2*tk->borderwidth;
	if(tks->orient == Tkvertical) {
		if(tk->req.width == 0)
			tk->req.width = Triangle + gap;
		if(tk->req.height == 0)	
			tk->req.height = 2*Triangle + gap + 6*tks->elembw;
	}
	else {
		if(tk->req.width == 0)
			tk->req.width = 2*Triangle + gap + 6*tks->elembw;
		if(tk->req.height == 0)	
			tk->req.height = Triangle + gap;
	}


	return tkbindings(tk->env->top, tk, b, nelem(b));
}

char*
tkscrollcget(Tk *tk, char *arg, char **val)
{
	TkOptab tko[3];
	TkScroll *tks = TKobj(TkScroll, tk);

	tko[0].ptr = tk;
	tko[0].optab = tkgeneric;
	tko[1].ptr = tks;
	tko[1].optab = opts;
	tko[2].ptr = nil;

	return tkgencget(tko, arg, val, tk->env->top);
}

void
tkfreescrlb(Tk *tk)
{
	TkScroll *tks = TKobj(TkScroll, tk);

	if(tks->cmd != nil)
		free(tks->cmd);
	if(tk == actsb)
		actsb = nil;
}

static void
tkvscroll(Tk *tk, TkScroll *tks, Image *i, Point size)
{
	TkEnv *e;
	Rectangle r;
	Point p[3], o;
	Image *d, *l, *t;
	int bo, w, h, triangle, bgnd;

	e = tk->env;

	triangle = tk->act.width - tks->elembw - tk->borderwidth;

	bo = tk->borderwidth + tks->elembw;
	p[0].x = size.x/2;
	p[0].y = bo;
	p[1].x = p[0].x - triangle/2;
	p[1].y = p[0].y + triangle;
	p[2].x = p[0].x + triangle/2;
	p[2].y = p[0].y + triangle;

	bgnd = TkCbackgnd;
	if(tks->flag & (TkactivA1|TkbuttonA1)) {
		bgnd = TkCactivebgnd;
		fillpoly(i, p, 3, ~0, tkgc(e, bgnd), p[0]);
	}

	l = tkgc(e, bgnd + 1);
	d = tkgc(e, bgnd + 2);
	if(tks->flag & TkbuttonA1) {
		t = d;
		d = l;
		l = t;
	}
	line(i, p[1], p[2], 0, 0, 1, d, p[1]);
	line(i, p[2], p[0], 0, 0, 1, d, p[2]);
	line(i, p[0], p[1], 0, 0, 1, l, p[0]);

	tks->a1 = p[2].y;
	h = p[2].y + tks->elembw;

	p[0].y = size.y - bo - 1;
	p[1].y = p[0].y - triangle;
	p[2].y = p[0].y - triangle;

	bgnd = TkCbackgnd;
	if(tks->flag & (TkactivA2|TkbuttonA2)) {
		bgnd = TkCactivebgnd;
		fillpoly(i, p, 3, ~0, tkgc(e, bgnd), p[0]);
	}

	l = tkgc(e, bgnd + 1);
	d = tkgc(e, bgnd + 2);
	if(tks->flag & TkbuttonA2) {
		t = d;
		d = l;
		l = t;
	}
	line(i, p[1], p[2], 0, 0, 1, l, p[1]);
	line(i, p[2], p[0], 0, 0, 1, d, p[2]);
	line(i, p[0], p[1], 0, 0, 1, l, p[0]);

	tks->a2 = p[2].y;

	o.x = tk->borderwidth ;
	o.y = bo + triangle + 2*tks->elembw;
	w = size.x - 2*bo;
	h = p[2].y - 2*tks->elembw - h - 2*tk->borderwidth;

	o.y += (tks->top*h)/Tkfpscalar;
	h *= tks->bot - tks->top;
	h /= Tkfpscalar;

	bgnd = TkCbackgnd;
	if(tks->flag & (TkactivB1|TkbuttonB1)) {
		r.min = o;
		r.max.x = o.x + w + 2*2;
		r.max.y = o.y + h + 2*2;
		bgnd = TkCactivebgnd;
		draw(i, r, tkgc(e, bgnd), nil, ZP);
	}

	tks->t1 = o.y - tks->elembw;
	tks->t2 = o.y + h + tks->elembw;
	l = tkgc(e, bgnd + 1);
	d = tkgc(e, bgnd + 2);
	if(tks->flag & TkbuttonB1)
		tkbevel(i, o, w, h, 2, d, l);
	else
		tkbevel(i, o, w, h, 2, l, d);
}

static void
tkhscroll(Tk *tk, TkScroll *tks, Image *i, Point size)
{
	TkEnv *e;
	Rectangle r;
	Point p[3], o;
	Image *d, *l, *t;
	int bo, w, h, triangle, bgnd;

	e = tk->env;

	triangle = tk->act.height - tks->elembw - tk->borderwidth;

	bo = tk->borderwidth + tks->elembw;
	p[0].x = bo;
	p[0].y = size.y/2;
	p[1].x = p[0].x + triangle;
	p[1].y = p[0].y - triangle/2 + 1;
	p[2].x = p[0].x + triangle;
	p[2].y = p[0].y + triangle/2 - 2;

	bgnd = TkCbackgnd;
	if(tks->flag & (TkactivA1|TkbuttonA1)) {
		bgnd = TkCactivebgnd;
		fillpoly(i, p, 3, ~0, tkgc(e, bgnd), p[0]);
	}

	l = tkgc(e, bgnd + 1);
	d = tkgc(e, bgnd + 2);

	if(tks->flag & TkbuttonA1) {
		t = d;
		d = l;
		l = t;
	}
	line(i, p[1], p[2], 0, 0, 1, d, p[1]);
	line(i, p[2], p[0], 0, 0, 1, d, p[2]);
	line(i, p[0], p[1], 0, 0, 1, l, p[0]);

	tks->a1 = p[2].x;
	w = p[2].x + tks->elembw;

	p[0].x = size.x - bo - 1;
	p[1].x = p[0].x - triangle;
	p[2].x = p[0].x - triangle;

	bgnd = TkCbackgnd;
	if(tks->flag & (TkactivA2|TkbuttonA2)) {
		bgnd = TkCactivebgnd;
		fillpoly(i, p, 3, ~0, tkgc(e, bgnd), p[0]);
	}

	l = tkgc(e, bgnd + 1);
	d = tkgc(e, bgnd + 2);
	if(tks->flag & TkbuttonA2) {
		t = d;
		d = l;
		l = t;
	}
	line(i, p[1], p[2], 0, 0, 1, l, p[1]);
	line(i, p[2], p[0], 0, 0, 1, d, p[2]);
	line(i, p[0], p[1], 0, 0, 1, l, p[0]);

	tks->a2 = p[2].x;

	o.x = bo + triangle + 2*tks->elembw;
	o.y = tk->borderwidth;
	w = p[2].x - 2*tks->elembw - w - 2*tk->borderwidth;
	h = size.y - 2*bo;

	o.x += (tks->top*w)/Tkfpscalar;
	w *= tks->bot - tks->top;
	w /= Tkfpscalar;

	bgnd = TkCbackgnd;
	if(tks->flag & (TkactivB1|TkbuttonB1)) {
		r.min = o;
		r.max.x = o.x + w + 2*2;
		r.max.y = o.y + h + 2*2;
		bgnd = TkCactivebgnd;
		draw(i, r, tkgc(e, bgnd), nil, ZP);
	}

	tks->t1 = o.x - tks->elembw;
	tks->t2 = o.x + w + tks->elembw;
	l = tkgc(e, bgnd + 1);
	d = tkgc(e, bgnd + 2);
	if(tks->flag & TkbuttonB1)
		tkbevel(i, o, w, h, 2, d, l);
	else
		tkbevel(i, o, w, h, 2, l, d);
}

char*
tkdrawscrlb(Tk *tk, Point orig)
{
	Point p;
	TkTop *t;
	TkEnv *e;
	Rectangle r;
	Image *i, *dst;
	TkScroll *tks = TKobj(TkScroll, tk);

	e = tk->env;
	t = e->top;

	dst = tkimageof(tk);
	if(dst == nil)
		return nil;

	r.min = ZP;
	r.max.x = tk->act.width + 2*tk->borderwidth;
	r.max.y = tk->act.height + 2*tk->borderwidth;

	i = tkitmp(t, r.max);
	if(i == nil)
		return nil;

	draw(i, r, tkgc(e, TkCbackgnd), nil, ZP);

	if(tks->orient == Tkvertical)
		tkvscroll(tk, tks, i, r.max);
	else
		tkhscroll(tk, tks, i, r.max);

	tkdrawrelief(i, tk, ZP, 0, TkCbackgnd);

	p.x = tk->act.x + orig.x;
	p.y = tk->act.y + orig.y;
	r = rectaddpt(r, p);
	draw(dst, r, i, nil, ZP);

	return nil;
}

/* Widget Commands (+ means implemented)	
	+activate
	+cget
	+configure
	+delta
	+fraction
	+get
	+identify
	+set
*/

char*
tkscrollconf(Tk *tk, char *arg, char **val)
{
	char *e;
	TkGeom g;
	int bd;
	TkOptab tko[3];
	TkScroll *tks = TKobj(TkScroll, tk);

	tko[0].ptr = tk;
	tko[0].optab = tkgeneric;
	tko[1].ptr = tks;
	tko[1].optab = opts;
	tko[2].ptr = nil;

	if(*arg == '\0')
		return tkconflist(tko, val);

	g = tk->req;
	bd = tk->borderwidth;
	e = tkparse(tk->env->top, arg, tko, nil);
	tkgeomchg(tk, &g, bd);

	tk->flag |= Tkdirty;
	return e;
}

char*
tkscrollactivate(Tk *tk, char *arg, char **val)
{
	int s, gotarg;
	char buf[Tkmaxitem];
	TkScroll *tks = TKobj(TkScroll, tk);

	USED(val);
	tkword(tk->env->top, arg, buf, buf+sizeof(buf), &gotarg);
	s = tks->flag;
	if (!gotarg) {
		char *a;
		if (s & TkactivA1)
			a = "arrow1";
		else if (s & TkactivA2)
			a = "arrow2";
		else if (s & TkactivB1)
			a = "slider";
		else
			a = "";
		return tkvalue(val, a);
	}
	tks->flag &= ~(TkactivA1 | TkactivA2 | TkactivB1);
	if(strcmp(buf, "arrow1") == 0)
		tks->flag |= TkactivA1;
	else
	if(strcmp(buf, "arrow2") == 0)
		tks->flag |= TkactivA2;
	else
	if(strcmp(buf, "slider") == 0)
		tks->flag |= TkactivB1;

	if(s ^ tks->flag)
		tk->flag |= Tkdirty;
	return nil;
}

char*
tkscrollset(Tk *tk, char *arg, char **val)
{
	TkTop *t;
	TkScroll *tks = TKobj(TkScroll, tk);

	USED(val);
	t = tk->env->top;
	arg = tkfrac(t, arg, &tks->top, nil);
	if(*arg == '\0')
		return TkBadvl;
	tkfrac(t, arg, &tks->bot, nil);
	if(tks->top < 0)
		tks->top = 0;
	if(tks->top > TKI2F(1))
		tks->top = TKI2F(1);
	if(tks->bot < 0)
		tks->bot = 0;
	if(tks->bot > TKI2F(1))
		tks->bot = TKI2F(1);

	tk->flag |= Tkdirty;
	return nil;
}

char*
tkscrolldelta(Tk *tk, char *arg, char **val)
{
	int l, delta;
	char buf[Tkmaxitem];
	TkScroll *tks = TKobj(TkScroll, tk);

	arg = tkitem(buf, arg);
	if(tks->orient == Tkvertical)
		tkitem(buf, arg);
	if(*arg == '\0' || *buf == '\0')
		return TkBadvl;

	l = tks->a2-tks->a1-4*tks->elembw;
	delta = Tkfpscalar;
	if(l != 0)
		delta = atoi(buf)*Tkfpscalar / l;
	tkfprint(buf, delta);

	return tkvalue(val, "%s", buf);	
}

char*
tkscrollget(Tk *tk, char *arg, char **val)
{
	char *v, buf[Tkmaxitem];
	TkScroll *tks = TKobj(TkScroll, tk);

	USED(arg);
	v = tkfprint(buf, tks->top);
	*v++ = ' ';
	tkfprint(v, tks->bot);

	return tkvalue(val, "%s", buf);	
}

char*
tkscrollidentify(Tk *tk, char *arg, char **val)
{
	int pix;
	TkTop *t;
	char *v, buf[Tkmaxitem];
	TkScroll *tks = TKobj(TkScroll, tk);

	t = tk->env->top;
	arg = tkword(t, arg, buf, buf+sizeof(buf), nil);
	if(tks->orient == Tkvertical)
		tkword(t, arg, buf, buf+sizeof(buf), nil);
	if(buf[0] == '\0')
		return TkBadvl;

	pix = atoi(buf);
	pix += tk->borderwidth;

	v = "";
	if(pix <= tks->a1)
		v = "arrow1";
	if(pix > tks->a1 && pix <= tks->t1)
		v = "trough1";
	if(pix > tks->t1 && pix < tks->t2)
		v = "slider";
	if(pix >= tks->t2 && pix < tks->a2)
		v = "trough2";
	if(pix >= tks->a2)
		v = "arrow2";
	return tkvalue(val, "%s", v);
}

char*
tkscrollfraction(Tk *tk, char *arg, char **val)
{
	int len, frac, pos;
	char buf[Tkmaxitem];
	TkScroll *tks = TKobj(TkScroll, tk);

	arg = tkitem(buf, arg);
	if(tks->orient == Tkvertical)
		tkitem(buf, arg);
	if(*arg == '\0' || *buf == '\0')
		return TkBadvl;

	pos = atoi(buf);
	if(pos < tks->a1)
		pos = tks->a1;
	if(pos > tks->a2)
		pos = tks->a2;
	len = tks->a2 - tks->a1 - 4*tks->elembw;
	frac = Tkfpscalar;
	if(len != 0)
		frac = (pos-tks->a1)*Tkfpscalar/len;
	tkfprint(buf, frac);
	return tkvalue(val, "%s", buf);
}

char*
tkScrolBut1R(Tk *tk, char *arg, char **val)
{
	TkScroll *tks = TKobj(TkScroll, tk);

	USED(val);
	USED(arg);
	actsb = nil;
	tks->flag &= ~(TkactivA1|TkactivA2|TkactivB1|TkbuttonA1|TkbuttonA2|TkbuttonB1|Tkautorepeat);
	tkclrmgrab(tk->env->top->ctxt);
	tk->flag |= Tkdirty;
	return nil;
}

/* tkScrolBut2P fraction */
char*
tkScrolBut2P(Tk *tk, char *arg, char **val)
{
	TkTop *t;
	char *e, buf[Tkmaxitem], fracbuf[Tkmaxitem];
	TkScroll *tks = TKobj(TkScroll, tk);
	

	USED(val);
	t = tk->env->top;

	if(arg[0] == '\0')
		return TkBadvl;

	tkword(t, arg, fracbuf, fracbuf+sizeof(fracbuf), nil);

	e = nil;
	if(tks->cmd != nil) {
		snprint(buf, sizeof(buf), "%s moveto %s", tks->cmd, fracbuf);
		e = tkexec(t, buf, nil);
	}
	return e;
}

static int
activesb(void *v)
{
	Tk *tk, *tkc;
	TkScroll *tks;

	tk = v;
	tkc = actsb;
	if(tk == nil)
		tk = tkc;
	else if(tk != tkc)
		return 0;
	if(tk != nil){
		tks = TKobj(TkScroll, tk);
		if(tks->flag & Tkautorepeat)
			return 1;
	}
	return 0;
}

static void
updatesb(void *v)
{
	Tk *tk;
	
	tk = (Tk*)v;
	tkdeliver(tk, TkButton1P, &tk->env->top->ctxt->tkmstate);
	tkupdate(tk->env->top);
}

/* tkScrolBut1P %x %y */
char*
tkScrolBut1P(Tk *tk, char *arg, char **val)
{
	int pix;
	TkTop *t;
	char *e, *fmt, buf[Tkmaxitem];
	TkScroll *tks = TKobj(TkScroll, tk);

	USED(val);
	t = tk->env->top;

	arg = tkword(t, arg, buf, buf+sizeof(buf), nil);
	if(tks->orient == Tkvertical)
		tkword(t, arg, buf, buf+sizeof(buf), nil);
	if(buf[0] == '\0')
		return TkBadvl;

	pix = atoi(buf);
	
	tks->dragpix = pix;
	tks->dragtop = tks->top;
	tks->dragbot = tks->bot;

	pix += tk->borderwidth;

	fmt = nil;
	e = nil;
	if(pix <= tks->a1) {
		fmt = "%s scroll -1 unit";
		tks->flag |= TkbuttonA1;
	}
	if(pix > tks->a1 && pix <= tks->t1)
		fmt = "%s scroll -1 page";
	if(pix > tks->t1 && pix < tks->t2 && !(tks->flag & Tkautorepeat))
		tks->flag |= TkbuttonB1;
	if(pix >= tks->t2 && pix < tks->a2)
		fmt = "%s scroll 1 page";
	if(pix >= tks->a2) {
		fmt = "%s scroll 1 unit";
		tks->flag |= TkbuttonA2;
	}
	if(tks->cmd != nil && fmt != nil) {
		snprint(buf, sizeof(buf), fmt, tks->cmd);
		e = tkexec(t, buf, nil);
	}
	tksetmgrab(t->ctxt, tk);
	tk->flag |= Tkdirty;
	if(tks->flag & (TkbuttonA1|TkbuttonA2) && !(tks->flag & Tkautorepeat)){
		if(!autorpt)
			autorpt = rptproc("autorepeat", 200, 100, activesb, updatesb);
		actsb = tk;
		tks->flag |= Tkautorepeat;
		rptwakeup(tk, autorpt);
	}
	return e;
}

/* tkScrolDrag %x %y */
char*
tkScrollDrag(Tk *tk, char *arg, char **val)
{
	TkTop *t;
	int pix, delta;
	char frac[32], buf[Tkmaxitem];
	TkScroll *tks = TKobj(TkScroll, tk);

	USED(val);
	t = tk->env->top;

	if((tks->flag & TkbuttonB1) == 0)
		return nil;

	arg = tkword(t, arg, buf, buf+sizeof(buf), nil);
	if(tks->orient == Tkvertical)
		tkword(t, arg, buf, buf+sizeof(buf), nil);
	if(buf[0] == '\0')
		return TkBadvl;

	pix = atoi(buf);

	delta = (pix-tks->dragpix)*Tkfpscalar;
	if ( tks->a2 == tks->a1 )
		return TkBadvl;
	delta = delta/(tks->a2-tks->a1-4*tks->elembw);
	if(tks->jump) {
		if(tks->dragtop+delta >= 0 &&
		   tks->dragbot+delta <= Tkfpscalar) {
			tks->top = tks->dragtop+delta;
			tks->bot = tks->dragbot+delta;
		}
		return nil;
	}
	if(tks->cmd != nil) {
		delta += tks->dragtop;
		if(delta < 0)
			delta = 0;
		if(delta > Tkfpscalar)
			delta = Tkfpscalar;
		tkfprint(frac, delta);
		snprint(buf, sizeof(buf), "%s moveto %s", tks->cmd, frac);
		return tkexec(t, buf, nil);
	}
	return nil;
}
