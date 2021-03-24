#include <lib9.h>
#include <kernel.h>
#include "image.h"
#include "tk.h"

enum
{
	tkBackR		= 0xdd,		/* Background base color */
	tkBackG 	= 0xdd,
	tkBackB 	= 0xdd,

	tkSelectR	= 0xb0,		/* Check box selected color */
	tkSelectG	= 0x30,
	tkSelectB	= 0x60,

	tkSelectbgndR	= 0x40,		/* Selected item background */
	tkSelectbgndG	= 0x40,
	tkSelectbgndB	= 0x40
};

typedef struct Coltab Coltab;
struct Coltab {
	int	c;
	int	r;
	int	g;
	int	b;
};

static Coltab coltab[] =
{
	TkCbackgnd,
		tkBackR,
		tkBackG,
		tkBackB,
	TkCbackgndlght,
		tkBackR+Tkshdelta,
		tkBackG+Tkshdelta,
		tkBackB+Tkshdelta,
	TkCbackgnddark,
		tkBackR-Tkshdelta,
		tkBackG-Tkshdelta,
		tkBackB-Tkshdelta,
	TkCactivebgnd,
		tkBackR+0x10,
		tkBackG+0x10,
		tkBackB+0x10,
	TkCactivebgndlght,
		tkBackR+0x10+Tkshdelta,
		tkBackG+0x10+Tkshdelta,
		tkBackB+0x10+Tkshdelta,
	TkCactivebgnddark,
		tkBackR+0x10-Tkshdelta,
		tkBackG+0x10-Tkshdelta,
		tkBackB+0x10-Tkshdelta,
	TkCactivefgnd,
		0, 0, 0,
	TkCforegnd,
		0, 0, 0,
	TkCselect,
		tkSelectR,
		tkSelectG,
		tkSelectB,
	TkCselectbgnd,
		tkSelectbgndR,
		tkSelectbgndG,
		tkSelectbgndB,
	TkCselectbgndlght,
		tkSelectbgndR+Tkshdelta,
		tkSelectbgndG+Tkshdelta,
		tkSelectbgndB+Tkshdelta,
	TkCselectbgnddark,
		tkSelectbgndR-Tkshdelta,
		tkSelectbgndG-Tkshdelta,
		tkSelectbgndB-Tkshdelta,
	TkCselectfgnd,
		0xff, 0xff, 0xff,
	-1,
};

typedef struct Cmd Cmd;
struct Cmd
{
	char*	name;
	char*	(*fn)(TkTop*, char*, char**);
};
static struct Cmd cmdmain[] =
{
	"bind",		tkbind,
	"button",	tkbutton,
	"canvas",	tkcanvas,
	"checkbutton",	tkcheckbutton,
	"cursor",	tkcursorcmd,
	"destroy",	tkdestroy,
	"entry",	tkentry,
	"focus",	tkfocus,
	"frame",	tkframe,
	"grab",		tkgrab,
	"image",	tkimage,
	"label",	tklabel,
	"listbox",	tklistbox,
	"lower",	tklower,
	"menu",		tkmenu,
	"menubutton",	tkmenubutton,
	"pack",		tkpack,
	"puts",		tkputs,
	"radiobutton",	tkradiobutton,
	"raise",	tkraise,
	"scale",	tkscale,
	"scrollbar",	tkscrollbar,
	"send",		tksend,
	"text",		tktext,
	"update",	tkupdatecmd,
	"variable",	tkvariable,
	"winfo",	tkwinfo,
};

char*	tkfont;

Image*
tkgc(TkEnv *e, int col)
{
	int pix;
	Image *i;
	TkCtxt *c;
	Rectangle r;

	if(col < nelem(e->evim) && e->evim[col] != nil)
		return e->evim[col];

	c = e->top->ctxt;
	pix = e->colors[col];
	if(c->colors[pix] != nil)
		return c->colors[pix];
	r.min = ZP;
	r.max.x = 1;
	r.max.y = 1;

	i = allocimage(c->screen->display, r, 3, 1, pix);
	c->colors[pix] = i;

	if(i == nil)
		i = c->screen->display->ones;	/* black */

	return i;
}

TkEnv*
tknewenv(TkTop *t)
{
	TkEnv *e;

	e = malloc(sizeof(TkEnv));
	if(e == nil)
		return nil;

	e->ref = 1;
	e->top = t;
	return e;
}

TkEnv*
tkdefaultenv(TkTop *t)
{
	Coltab *c;
	int locked;
	TkEnv *env;
	Display *d;

	if(t->env != nil) {
		t->env->ref++;
		return t->env;
	}
	t->env = malloc(sizeof(TkEnv));
	if(t->env == nil)
		return nil;

	env = t->env;
	env->ref = 1;
	env->top = t;

	if(tkfont == nil)
		tkfont = "/fonts/pelm/unicode.8.font";

	d = t->display;
	env->font = font_open(d, tkfont);
	if(env->font == nil) {
		env->font = font_open(d, "*default*");
		if(env->font == nil) {
			free(t->env);
			t->env = nil;
			return nil;
		}
	}

	locked = lockdisplay(d, 0);
	env->wzero = stringwidth(env->font, "0");
	if ( env->wzero <= 0 )
		env->wzero = env->font->height / 2;
	if(locked)
		unlockdisplay(d);

	c = &coltab[0];
	while(c->c != -1) {
		env->colors[c->c] = rgb2cmap(c->r, c->g, c->b);
		env->set |= (1<<c->c);
		c++;
	}

	return env;
}

void
tkputenv(TkEnv *env)
{
	Display *d;
	int i, locked;

	if(env == nil)
		return;

	env->ref--;
	if(env->ref != 0)
		return;

	d = env->top->display;
	locked = lockdisplay(d, 0);

	for(i = 0; i < nelem(env->evim); i++) {
		if(env->evim[i] != nil)
			freeimage(env->evim[i]);
	}

	if(env->font != nil)
		font_close(env->font);

	if(locked)
		unlockdisplay(d);

	free(env);
}

Image*
tkdupcolor(Image *c)
{
	Image *n;
	Rectangle r;

	r.min = ZP;
	r.max.x = 1;
	r.max.y = 1;

	n = allocimage(c->display, r, 3, 1, 0);
	if(n != nil)
		draw(n, r, c, nil, ZP);
	return n;
}

TkEnv*
tkdupenv(TkEnv **env)
{
	Display *d;
	int i, locked;
	TkEnv *e, *ne;

	e = *env;
	if(e->ref == 1)
		return e;

	ne = malloc(sizeof(TkEnv));
	if(ne == nil)
		return nil;

	ne->ref = 1;
	ne->top = e->top;

	locked = 0;
	d = e->top->display;
	for(i = 0; i < nelem(e->evim); i++) {
		if(e->evim[i] != nil) {
			if(locked == 0)
				locked = lockdisplay(d, 0);
			ne->evim[i] = tkdupcolor(e->evim[i]);
		}
	}
	if(locked)
		unlockdisplay(d);

	memmove(ne->colors, e->colors, sizeof(e->colors));
	ne->set = e->set;
	ne->font = font_open(d, e->font->name);
	ne->wzero = e->wzero;

	e->ref--;
	*env = ne;
	return ne;
}

Tk*
tknewobj(TkTop *t, int type, int n)
{
	Tk *tk;

	tk = malloc(n);
	if(tk == 0)
		return 0;

	tk->type = type;		/* Defaults */
	tk->flag = Tkcenter|Tktop;
	tk->relief = TKflat;
	tk->env = tkdefaultenv(t);
	if(tk->env == nil) {
		free(tk);
		return nil;
	}

	return tk;
}

void
tkfreebind(TkAction *a)
{
	TkAction *next;

	while(a != nil) {
		next = a->link;
		if((a->type & 0xff) == TkDynamic)
			free(a->arg);
		free(a);
		a = next;
	}
}

void
tkfreename(TkName *f)
{
	TkName *n;

	while(f != nil) {
		n = f->link;
		free(f);
		f = n;
	}
}

void
tkfreeobj(Tk *tk)
{
	TkCtxt *c;

	c = tk->env->top->ctxt;
	if(c != nil) {
		if(c->tkKgrab == tk)
			c->tkKgrab = nil;
		if(c->tkMgrab == tk)
			tkclrmgrab(c);
		if(c->tkMfocus == tk)
			c->tkMfocus = nil;
	}
	if(tk->env->top->select == tk)
		tk->env->top->select = nil;

	tkmethod[tk->type].free(tk);
	tkputenv(tk->env);
	tkfreebind(tk->binds);
	if(tk->name != nil)
		free(tk->name);
	free(tk);
}

char*
tkaddchild(TkTop *t, Tk *tk, TkName **names)
{
	TkName *n;
	Tk *f, **l;
	int found, len;
	char *s, *ep;

	n = *names;
	if(n == nil || n->name[0] != '.'){
		if(n != nil)
			tkerr(t, n->name);
		return TkBadwp;
	}

	if (n->name[1] == '\0')
		return TkDupli;

	/*
	 * check that the name is well-formed.
	 * ep will point to end of parent component of the name.
	 */
	ep = nil;
	for (s = n->name + 1; *s; s++) {
		if (*s == '.'){
			tkerr(t, n->name);
			return TkBadwp;
		}
		for (; *s && *s != '.'; s++)
			;
		if (*s == '\0')
			break;
		ep = s;
	}
	if (ep == s - 1){
		tkerr(t, n->name);
		return TkBadwp;
	}
	if (ep == nil)
		ep = n->name + 1;
	len = ep - n->name;

	found = 0;
	l = &t->root;
	for(f = *l; f; f = f->siblings) {
		if (f->name != nil) {
			if (strcmp(n->name, f->name->name) == 0)
				return TkDupli;
			if (!found &&
					strncmp(n->name, f->name->name, len) == 0 &&
					f->name->name[len] == '\0')
				found = 1;
		}
		l = &f->siblings;
	}
	if (0) {		/* don't enable this until a reasonably major release... if ever */
		/*
		 * parent widget must already exist
		 */
		if (!found){
			tkerr(t, n->name);
			return TkBadwp;
		}
	}
	*l = tk;
	tk->name = n;
	*names = n->link;

	return nil;
}

Tk*
tklook(TkTop *t, char *wp, int parent)
{
	Tk *f;
	char *p, *q;

	if(wp == nil)
		return nil;
	p = strdup(wp);
	if(p == nil)
		return nil;

	if(parent) {
		q = strrchr(p, '.');
		if(q == nil)
			abort();
		if(q == p) {
			free(p);
			return t->root;
		}
		*q = '\0';	
	}

	for(f = t->root; f; f = f->siblings)
		if ((f->name != nil) && (strcmp(f->name->name, p) == 0))
			break;

	if(f != nil && (f->flag & Tkdestroy))
		f = nil;

	free(p);
	return f;
}

void
tktextsdraw(Image *img, Rectangle r, TkEnv *e, int sbw)
{
	Rectangle s;

	draw(img, r, tkgc(e, TkCselectbgnd), nil, ZP);
	s.min = r.min;
	s.min.x -= sbw;
	s.min.y -= sbw;
	s.max.x = r.max.x;
	s.max.y = r.min.y;
	draw(img, s, tkgc(e, TkCselectbgndlght), nil, ZP);
	s.max.x = s.min.x + sbw;
	s.max.y = r.max.y + sbw;
	draw(img, s, tkgc(e, TkCselectbgndlght), nil, ZP);
	s.max = r.max;
	s.max.x += sbw;
	s.max.y += sbw;
	s.min.x = r.min.x;
	s.min.y = r.max.y;
	draw(img, s, tkgc(e, TkCselectbgnddark), nil, ZP);
	s.min.x = r.max.x;
	s.min.y = r.min.y - sbw;
	draw(img, s, tkgc(e, TkCselectbgnddark), nil, ZP);
}

void
tkbevel(Image *i, Point o, int w, int h, int bw, Image *top, Image *bottom)
{
	Rectangle r;
	int x, border;

	border = 2 * bw;

	r.min = o;
	r.max.x = r.min.x + w + border;
	r.max.y = r.min.y + bw;
	draw(i, r, top, nil, ZP);

	r.max.x = r.min.x + bw;
	r.max.y = r.min.y + h + border;
	draw(i, r, top, nil, ZP);

	r.max.x = o.x + w + border;
	r.max.y = o.y + h + border;
	r.min.x = o.x + bw;
	r.min.y = r.max.y - bw;
	for(x = 0; x < bw; x++) {
		draw(i, r, bottom, nil, ZP);
		r.min.x--;
		r.min.y++;
	}
	r.min.x = o.x + bw + w;
	r.min.y = o.y + bw;
	for(x = bw; x >= 0; x--) {
		draw(i, r, bottom, nil, ZP);
		r.min.x++;
		r.min.y--;
	}
}

/*
 * draw a relief border.
 * color is an index into tk->env->colors and assumes
 * light and dark versions following immediately after
 * that index
 */
void
tkdrawrelief(Image *i, Tk *tk, Point o, int inset, int color)
{
	TkEnv *e;
	Image *l, *d, *t;
	int h, w, bd, bd1, bd2, rlf;

	if(tk->borderwidth == 0)
		return;

	h = tk->act.height;
	w = tk->act.width;

	if(inset != 0) {
		o.x += inset;
		o.y += inset;
		inset *= 2;
		h -= inset;
		w -= inset;
	}
	e = tk->env;
	l = tkgc(e, color + 1);
	d = tkgc(e, color + 2);
	bd = tk->borderwidth;
	rlf = tk->relief;
	if(rlf < 0)
		rlf = TKraised;
	switch(rlf) {
	case TKflat:
		break;
	case TKsunken:
		tkbevel(i, o, w, h, bd, d, l);
		break;	
	case TKraised:
		tkbevel(i, o, w, h, bd, l, d);
		break;	
	case TKgroove:
		t = d;
		d = l;
		l = t;
		/* fall through */
	case TKridge:
		bd1 = bd/2;
		bd2 = bd - bd1;
		if(bd1 > 0)
			tkbevel(i, o, w + 2*bd2, h + 2*bd2, bd1, l, d);
		o.x += bd1;
		o.y += bd1;
		tkbevel(i, o, w, h, bd2, d, l);
		break;
	}
}

Point
tkstringsize(Tk *tk, char *text)
{
	char *q;
	int locked;
	Display *d;
	Point p, t;

	if(text == nil) {
		p.x = 0;
		p.y = 0;
		return p;
	}

	d = tk->env->top->display;
	locked = lockdisplay(d, 0);

	p = ZP;
	while(*text) {
		q = strchr(text, '\n');
		if(q != nil)
			*q = '\0';
		t = stringsize(tk->env->font, text);
		p.y += t.y;
		if(p.x < t.x)
			p.x = t.x;
		if(q == nil)
			break;
		text = q+1;
		*q = '\n';
	}
	if(locked)
		unlockdisplay(d);

	return p;	
}

char*
tkul(TkEnv *e, Image *i, Point o, int ul, char *text)
{
	char c, *v;
	Rectangle r;

	v = text+ul+1;
	c = *v;
	*v = '\0';
	r.max = stringsize(e->font, text);
	r.max = addpt(r.max, o);
	r.min = stringsize(e->font, v-1);
	*v = c;
	r.min.x = r.max.x - r.min.x;
	r.min.y = r.max.y - 1;
	r.max.y += 2;
	draw(i, r, tkgc(e, TkCforegnd), nil, ZP);	

	return nil;
}

char*
tkdrawstring(Tk *tk, Image *i, Point o, char *text, int ul, int col, int j)
{
	int n, l, maxl, sox;
	char *q, *txt;
	Point p;
	TkEnv *e;

	e = tk->env;
	sox = maxl = 0;
	if(j != Tkleft){
		maxl = 0;
		txt = text;
		while(*txt){
			q = strchr(txt, '\n');
			if(q != nil)
				*q = '\0';
			l = stringwidth(e->font, txt);
			if(l > maxl)
				maxl = l;
			if(q == nil)
				break;
			txt = q+1;
			*q = '\n';
		}
		sox = o.x;
	}
	while(*text) {
		q = strchr(text, '\n');
		if(q != nil)
			*q = '\0';
		if(j != Tkleft){
			o.x = sox;
			l = stringwidth(e->font, text);
			if(j == Tkcenter)
				o.x += (maxl-l)/2;
			else
				o.x += maxl-l;
		}
		p = string(i, o, tkgc(e, col), o, e->font, text);
		if(ul >= 0) {
			n = strlen(text);
			if(ul < n) {
				char *r;

				r = tkul(e, i, o, ul, text);
				if(r != nil)
					return r;
				ul = -1;
			}
			ul -= n;
		}
		o.y += e->font->height;
		if(q == nil)
			break;
		text = q+1;
		*q = '\n';
	}
	return nil;
}

void
tkdeliver(Tk *tk, int event, void *data)
{
	if(tk == nil || ((tk->flag&Tkdestroy) && event != TkDestroy))
		return;

	if(tk->deliverfn != nil)
		tk->deliverfn(tk, event, data);
	else
	if((tk->flag & Tkdisabled) == 0)
		tksubdeliver(tk, tk->binds, event, data);
}

int
tksubdeliver(Tk *tk, TkAction *binds, int event, void *data)
{
	TkAction *a;
	int delivered, genkey, delivered2, iskey;

	delivered = TkDnone;
	genkey = 0;
	for(a = binds; a != nil; a = a->link) {
		if(event == a->event) {
			tkcmdbind(tk, event, a->arg, data);
			delivered = TkDdelivered;
		} else if (a->event == TkKey && (a->type>>8)==TkAadd)
			genkey = 1;
	}
	if(delivered != TkDnone && !((event & TkKey) && genkey))
		return delivered;

	delivered2 = delivered;
	for(a = binds; a != nil; a = a->link) {
		/*
		 * only bind to non-specific key events; if a specific
		 * key event has already been delivered, only deliver event if
		 * the non-specific binding was added. (TkAadd)
		 */
		iskey = (a->event & TkKey);
		if (iskey ^ (event & TkKey))
			continue;
		if(iskey && (TKKEY(a->event) != 0
					|| ((a->type>>8) != TkAadd && delivered != TkDnone)))
			continue;
		if(!iskey && (a->event & TkMotion) && (a->event&TkEpress) != 0)
			continue;
		if(!(event & TkDouble) && (a->event & TkDouble))
			continue;
		if((event & ~TkDouble) & a->event) {
			tkcmdbind(tk, event, a->arg, data);
			delivered2 = TkDdelivered;
		}
	}
	return delivered2;
}

void
tkcancel(TkAction **l, int event)
{
	TkAction *a;

	for(a = *l; a; a = *l) {
		if(a->event == event) {
			*l = a->link;
			a->link = nil;
			tkfreebind(a);
			continue;
		}
		l = &a->link;
	}
}

static void
tkcancela(TkAction **l, int event, int type, char *arg)
{
	TkAction *a;

	for(a = *l; a; a = *l) {
		if(a->event == event && a->arg == arg && (a->type&0xff) == type){
			*l = a->link;
			a->link = nil;
			tkfreebind(a);
			continue;
		}
		l = &a->link;
	}
}

void
tksetselect(Tk *tk)
{
	TkTop *top;
	Tk *oldsel;

	if (tk == nil)
		return;
	top = tk->env->top;
	oldsel = top->select;
	if (oldsel != nil && oldsel != tk) {
		switch (oldsel->type) {
		case TKtext:
			tktextselection(top->select, " clear", nil);
			break;
		case TKentry:
			tkentryselect(top->select, "clear", nil);
			break;
/*
 *		case TKlistbox:
 *			tklistbselection(top->select, "clear 0 end", nil);
 *			break;
 */
		default:
			/* How serious is this? */
			oldsel = nil;
			break;
		}
		if (oldsel != nil)
			tkdirty(oldsel);
	}
	top->select = tk;
}

char*
tkaction(TkAction **l, int event, int type, char *arg, int how)
{
	TkAction *a;

	if(arg == nil)
		return nil;
	if(how == TkArepl)
		tkcancel(l, event);
	else if(how == TkAadd){
		for(a = *l; a; a = a->link)
			if(a->event == event && a->arg == arg && (a->type&0xff) == type){
				a->type = type + (how << 8);
				return nil;
			}
	}
	else if(how == TkAsub){
		tkcancela(l, event, type, arg);
		return nil;
	}

	a = malloc(sizeof(TkAction));
	if(a == nil) {
		if(type == TkDynamic)
			free(arg);
		return TkNomem;
	}

	a->event = event;
	a->arg = arg;
	a->type = type + (how << 8);

	a->link = *l;
	*l = a;

	return nil;
}

void
tkfliprelief(Tk *tk)
{
	switch(tk->relief) {
	case TKraised:
		tk->relief = TKsunken;
		break;
	case TKsunken:
		tk->relief = TKraised;
		break;
	case TKridge:
		tk->relief = TKgroove;
		break;
	case TKgroove:
		tk->relief = TKridge;
		break;
	}
}

char*
tkitem(char *buf, char *a)
{
	char *e;

	while(*a && (*a == ' ' || *a == '\t'))
		a++;

	e = buf + Tkmaxitem - 1;
	while(*a && *a != ' ' && *a != '\t' && buf < e)
		*buf++ = *a++;

	*buf = '\0';
	while(*a && (*a == ' ' || *a == '\t'))
		a++;
	return a;
}

int
tkismapped(Tk *tk)
{
	while(tk->master)
		tk = tk->master;

	/* We need subwindows of text & canvas to appear mapped always
	 * so that the geom function update are seen by the parent
	 * widget
	 */
	if((tk->flag & Tkwindow) == 0)
		return 1;

	return tk->flag & Tkmapped;
}

/*
 * Return absolute screen position of tk (just outside its top-left border).
 * When a widget is embedded in a text or canvas widget, we need to
 * use the text or canvas's relpos() function instead of act{x,y}, and we
 * need to folow up the parent pointer rather than the master one.
 */
Point
tkposn(Tk *tk)
{
	Tk *f;
	Point g;

	if(tk->parent != nil) {
		g = tk->parent->relpos(tk);
		f = tk->parent;
	}
	else {
		g.x = tk->act.x;
		g.y = tk->act.y;
		f = tk->master;
	}
	while(f) {
		g.x += f->borderwidth;
		g.y += f->borderwidth;
		if(f->parent != nil) {
			g = addpt(g, f->parent->relpos(f));
			f = f->parent;
		}
		else {
			g.x += f->act.x;
			g.y += f->act.y;
			f = f->master;
		}
	}
	return g;
}


/*
 * Parse a floating point number into a decimal fixed point representation
 */
char*
tkfrac(TkTop *t, char *arg, int *f, TkEnv *e)
{
	int c, minus, i, fscale, seendigit;
	char *p, *buf;

	seendigit = 0;
	buf = mallocz(Tkmaxitem, 0);
	if(buf == nil)
		return TkNomem;

	arg = tkword(t, arg, buf, buf+Tkmaxitem, nil);
	p = buf;

	minus = 0;
	if(*p == '-') {
		minus = 1;
		p++;
	}
	i = 0;
	while(*p) {
		c = *p;
		if(c == '.')
			break;
		if(c < '0' || c > '9')
			break;
		i = i*10 + (c - '0');
		seendigit = 1;
		p++;
	}
	i *= Tkfpscalar;
	if(*p == '.')
		p++;
	fscale = Tkfpscalar;
	while(*p && *p >= '0' && *p <= '9') {
		fscale /= 10;
		i += fscale * (*p++ - '0');
		seendigit = 1;
	}

	if(minus)
		i = -i;

	if(!seendigit || tkunits(*p, &i, e) != nil) {
		free(buf);
		return nil;
	}
	free(buf);

	*f = i;
	return arg;
}

char*
tkfprint(char *v, int frac)
{
	int fscale;

	if(frac < 0) {
		*v++ = '-';
		frac = -frac;
	}
	v += sprint(v, "%d", frac/Tkfpscalar);
	frac = frac%Tkfpscalar;
	if(frac != 0)
		*v++ = '.';
	fscale = Tkfpscalar/10;
	while(frac) {
		*v++ = '0' + frac/fscale;
		frac %= fscale;
		fscale /= 10;
	}
	*v = '\0';
	return v;	
}

char*
tkvalue(char **val, char *fmt, ...)
{
	int l;
	va_list arg;
	char *v, *buf;


	if(val == nil)
		return nil;

	buf = mallocz(Tkmaxitem, 0);
	if(buf == nil)
		return TkNomem;

	va_start(arg, fmt);
	v = vseprint(buf, buf+Tkmaxitem, fmt, arg);
	va_end(arg);
	l = 0;
	if(*val != nil)
		l = strlen(*val);
	v = realloc(*val, l+(v-buf)+1);
	if(v == nil) {
		free(*val);
		free(buf);
		return TkNomem;
	}
	strcpy(v+l, buf);
	free(buf);
	*val = v;
	return nil;
}

char*
tkunits(char c, int *d, TkEnv *e)
{
	switch(c) {
	default:
		if(c >= '0' || c <= '9' || c == '.')
			break;
		return TkBadvl;
	case '\0':
		break;
	case 'c':		/* Centimeters */
		*d *= (Tkdpi*100)/254;
		break;
	case 'm':		/* Millimeters */
		*d *= (Tkdpi*10)/254;
		break;
	case 'i':		/* Inches */
		*d *= Tkdpi;
		break;
	case 'p':		/* Points */
		*d = (*d*Tkdpi)/72;
		break;
	case 'w':		/* Character width */
		if(e == nil)
			return TkBadvl;
		*d = *d * e->wzero;
		break;
	case 'h':		/* Character height */
		if(e == nil)
			return TkBadvl;
		*d = *d * e->font->height;
		break;
	}
	return nil;
}

char*
tkwidgetcmd(TkTop *t, Tk *tk, char *arg, char **val)
{
	TkMethod *cm;
	TkCmdtab *ct;
	int bot, top, new, r;
	char *e, *buf;

	buf = mallocz(Tkmaxitem, 0);
	if(buf == nil)
		return TkNomem;

	arg = tkword(t, arg, buf, buf+Tkmaxitem, nil);
	if(val != nil)
		*val = nil;

	cm = &tkmethod[tk->type];

	e = TkBadcm;
	bot = 0;
	top = cm->ncmd - 1;

	while(bot <= top) {
		new = (bot + top)/2;
		ct = &cm->cmd[new];
		r = strcmp(ct->name, buf);
		if(r == 0) {
			e = ct->fn(tk, arg, val);
			break;
		}
		if(r < 0)
			bot = new + 1;
		else
			top = new - 1;
	}
	free(buf);
	tkdirty(tk);
	return e;
}

void
tkdirty(Tk *tk)
{
	Tk *parent, *sub;
	if((tk->flag&(Tksubsub|Tkdirty)) != (Tksubsub|Tkdirty))
		return;

	sub = tk;
	while(tk) {
		parent = tk->parent;
		if(parent != nil) {
			parent->dirty(sub);
			tk = sub = parent;
			if((tk->flag&(Tksubsub|Tkdirty)) == (Tksubsub|Tkdirty))
				continue;
			else
				break;
		}
		tk = tk->master;
	}
}

static int
qcmdcmp(const void *a, const void *b)
{
	return strcmp(((TkCmdtab*)a)->name, ((TkCmdtab*)b)->name);
}

void
tksorttable(void)
{
	int i;
	TkMethod *c;
	TkCmdtab *cmd;

	for(i = 0; i < TKwidgets; i++) {
		c = &tkmethod[i];
		if(c->cmd == nil)
			continue;

		for(cmd = c->cmd; cmd->name != nil; cmd++)
			;
		c->ncmd = cmd - c->cmd;

		qsort(c->cmd, c->ncmd, sizeof(TkCmdtab), qcmdcmp);
	}
}

char*
tksinglecmd(TkTop *t, char *arg, char **val)
{
	Tk *tk;
	int bot, top, new;
	char *e, *buf;

	if(t->debug)
		print("tk: '%s'\n", arg);

	buf = mallocz(Tkmaxitem, 0);
	if(buf == nil)
		return TkNomem;

	arg = tkword(t, arg, buf, buf+Tkmaxitem, nil);
	switch(buf[0]) {
	case '\0':
		free(buf);
		return nil;
	case '.':
		tk = tklook(t, buf, 0);
		if(tk == nil){
			tkerr(t, buf);
			free(buf);
			return TkBadwp;
		}
		e = tkwidgetcmd(t, tk, arg, val);
		free(buf);
		return e;
	}

	bot = 0;
	top = nelem(cmdmain) - 1;
	e = TkBadcm;
	while(bot <= top) {
		int rc;
		new = (bot + top)/2;
		rc = strcmp(cmdmain[new].name, buf); 
		if(!rc) {
			e = cmdmain[new].fn(t, arg, val);
			break;
		}

		if(rc < 0) 
			bot = new + 1;
		else
			top = new - 1;
	}
	free(buf);
	return e;
}

static char*
tkmatch(int inc, int dec, char *p)
{
	int depth, esc, c;

	esc = 0;
	depth = 1;
	while(*p) {
		c = *p;
		if(esc == 0) {
			if(c == inc)
				depth++;
			if(c == dec)
				depth--;
			if(depth == 0)
				return p;
		}
		if(c == '\\' && esc == 0)
			esc = 1;
		else
			esc = 0;
		p++;
	}
	return nil;
}

char*
tkexec(TkTop *t, char *arg, char **val)
{
	int cmdsz, n;
	char *p, *cmd, *e;

	if(t->depth >= 0 && ++t->depth > 128)
		return TkDepth;

	cmd = nil;
	cmdsz = 0;

	p = arg;
	for(;;) {
		switch(*p++) {
		case '[':
			p = tkmatch('[', ']', p);
			if(p == nil)
				return TkSyntx;
			break;
		case '{':
			p = tkmatch('{', '}', p);
			if(p == nil)
				return TkSyntx;
			break;
		case ';':
			n = p - arg - 1;
			if(cmdsz < n)
				cmdsz = n;
			cmd = realloc(cmd, cmdsz+1);
			if(cmd == nil)
				return TkNomem;
			memmove(cmd, arg, n);
			cmd[n] = '\0';
			e = tksinglecmd(t, cmd, nil);
			if(e != nil) {
				t->err = e;
				strncpy(t->errcmd, cmd, sizeof(t->errcmd));
				t->errcmd[sizeof(t->errcmd)-1] = '\0';
				free(cmd);
				return e;
			}
			arg = p;
			break;
		case '\0':
		case '\'':
			if(cmd != nil)
				free(cmd);
			e = tksinglecmd(t, arg, val);
			if(e != nil) {
				t->err = e;
				strncpy(t->errcmd, arg, sizeof(t->errcmd));
				t->errcmd[sizeof(t->errcmd)-1] = '\0';
			}
			return e;
		}
	}
}

static struct {
	char *name;
	int mask;
} events[] = {
	"TkButton1P"	, (1<<0),
	"TkButton1R"	, (1<<1),
	"TkButton2P"	, (1<<2),
	"TkButton2R"	, (1<<3),
	"TkButton3P"	, (1<<4),
	"TkButton3R"	, (1<<5),
	"TkButton4P"	, (1<<6),
	"TkButton4R"	, (1<<7),
	"TkButton5P"	, (1<<8),
	"TkButton5R"	, (1<<9),
	"TkButton6P"	, (1<<10),
	"TkButton6R"	, (1<<11),
	"TkDestroy"	, (1 << 21),
	"TkEnter"		, (1<<22),
	"TkLeave"		, (1<<23),
	"TkMotion"	, (1<<24),
	"TkMap"		, (1<<25),
	"TkUnmap"	, (1<<26),
	"TkKey"		, (1<<27),
	"TkFocusin"	, (1<<28),
	"TkFocusout"	, (1<<29),
	"TkConfigure"	, (1<<30),
	"TkDouble"	, (1<<31),
	nil, 0,
};

void
tkeprnt(int e, char *buf, char *ebuf)
{
	int k, i, d, len;

	k = -1;
	if (e & TkKey) {
		k = e & 0xffff;
		e &= ~0xffff;
	}
	d = 0;
	for (i = 0; events[i].name; i++) {
		if (e & events[i].mask) {
			len = ebuf - buf;
			if (d && len > 0) {
				*buf++ = '|';
				len--;
			}
			buf += snprint(buf, len, "%s", events[i].name);
			d = 1;
		}
	}
	if (k != -1) {
		snprint(buf, ebuf - buf, "[%c]", k);
	} else if (e == 0)
		snprint(buf, ebuf - buf, "Noevent");
}

void
tkprintevent(int e)
{
	char buf[Tkmaxitem];

	tkeprnt(e, buf, buf + sizeof(buf));
	print("%s", buf);
}

void
tkerr(TkTop *t, char *e)
{
	if(t != nil && e != nil){
		strncpy(t->errx, e, sizeof(t->errx));
		t->errx[sizeof(t->errx)-1] = '\0';
	}
}

char*
tkerrstr(TkTop *t, char *e)
{
	char *s = malloc(strlen(e)+1+strlen(t->errx)+1);

	strcpy(s, e);
	if(*e == '!'){
		strcat(s, " ");
		strcat(s, t->errx);
	}
	t->errx[0] = '\0';
	return s;
}

void
tksetmgrab(TkCtxt *c, Tk *tk)
{
	if(tk != c->tkMgrab){
		c->otkMgrab = c->tkMgrab;
		c->tkMgrab = tk;
	}
}

void
tkclrmgrab(TkCtxt *c)
{
	c->tkMgrab = c->otkMgrab;
	c->otkMgrab = nil;
}

int
tkinsidepoly(Point *poly, int np, int winding, Point p)
{
	Point pi, pj;
	int i, j, hit;

	hit = 0;
	j = np - 1;
	for (i = 0; i < np; j = i++) {
		pi = poly[i];
		pj = poly[j];
		if ((pi.y <= p.y && p.y < pj.y || pj.y <= p.y && p.y < pi.y) &&
				p.x < (pj.x - pi.x) * (p.y - pi.y) / (pj.y - pi.y) + pi.x) {
			if (winding == 1 || pi.y > p.y)
				hit++;
			else
				hit--;
		}
	}
	return (hit & winding) != 0;
}

int
tklinehit(Point *a, int np, int w, Point p)
{
	Point *b;
	int z, nx, ny, nrm;
	while(np-- > 1) {
		b = a+1;
		nx = a->y - b->y;
		ny = b->x - a->x;
		nrm = (nx < 0? -nx : nx) + (ny < 0? -ny : ny);
		if(nrm)
			z = (p.x-b->x)*nx/nrm + (p.y-b->y)*ny/nrm;
		else
			z = (p.x-b->x) + (p.y-b->y);
		if(z < 0)
			z = -z;
		if(z < w)
			return 1;
		a++;
	}
	return 0;
}
