#include "lib9.h"
#include "image.h"
#include "tk.h"

#define	O(t, e)		((long)(&((t*)0)->e))

static
TkOption opts[] =
{
	"text",		OPTtext,	O(TkMenubut, lab.text),		nil,
	"anchor",	OPTflag,	O(TkMenubut, lab.anchor),	tkanchor,
	"underline",	OPTdist,	O(TkMenubut, lab.ul),		nil,
	"menu",		OPTtext,	O(TkMenubut, menu),		nil,
	"bitmap",	OPTbmap,	O(TkLabel, bitmap),		nil,
	"image",	OPTimag,	O(TkLabel, img),		nil,
	nil
};

static
TkEbind b[] = 
{
	{TkEnter,		"%W configure -state active"},
	{TkLeave,		"%W tkMBleave %x %y"},
	{TkButton1P,		"%W tkMBpress %x %y"},
	{TkButton1R,		"%W tkMBrelease %x %y"},
	{TkButton1P|TkMotion,	""},
};

char*
tkmenubutton(TkTop *t, char *arg, char **ret)
{
	Tk *tk;
	char *e, *p;
	TkName *names;
	TkMenubut *tkm;
	TkOptab tko[3];

	tk = tknewobj(t, TKmenubutton, sizeof(Tk)+sizeof(TkMenubut));
	if(tk == nil)
		return TkNomem;
	tk->borderwidth = 2;

	tkm = TKobj(TkMenubut, tk);
	tkm->lab.ul = -1;

	tko[0].ptr = tk;
	tko[0].optab = tkgeneric;
	tko[1].ptr = tkm;
	tko[1].optab = opts;
	tko[2].ptr = nil;

	names = nil;
	e = tkparse(t, arg, tko, &names);
	if(e != nil) {
		tkfreeobj(tk);
		return e;
	}

	e = tkbindings(t, tk, b, nelem(b));

	if(e != nil) {
		tkfreeobj(tk);
		return e;
	}

	p = tkm->lab.text;
	if(tkm->lab.ul >= 0 && p != nil && tkm->lab.ul < strlen(p)) {
		e = tkaction(&tk->binds, TkKey|TKKEY(p[tkm->lab.ul]), TkStatic,
		    "%W menupost [%W cget menu];focus %W", TkAadd);
	}

	if(e != nil) {
		tkfreeobj(tk);
		return e;
	}

	tksizelabel(tk);

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
tkmenubutcget(Tk *tk, char *arg, char **val)
{
	TkOptab tko[3];
	TkMenubut *tkm = TKobj(TkMenubut, tk);

	tko[0].ptr = tk;
	tko[0].optab = tkgeneric;
	tko[1].ptr = tkm;
	tko[1].optab = opts;
	tko[2].ptr = nil;

	return tkgencget(tko, arg, val, tk->env->top);
}

char*
tkmenubutconf(Tk *tk, char *arg, char **val)
{
	char *e;
	TkGeom g;
	int bd;
	TkOptab tko[3];
	TkMenubut *tkm = TKobj(TkMenubut, tk);

	tko[0].ptr = tk;
	tko[0].optab = tkgeneric;
	tko[1].ptr = tkm;
	tko[1].optab = opts;
	tko[2].ptr = nil;

	if(*arg == '\0')
		return tkconflist(tko, val);

	g = tk->req;
	bd = tk->borderwidth;
	e = tkparse(tk->env->top, arg, tko, nil);
	tksizelabel(tk);
	tkgeomchg(tk, &g, bd);

	tk->flag |= Tkdirty;
	return e;
}

char*
tkmenubutpost(Tk *tk, char *arg, char **val)
{
	Tk *mtk;
	TkTop *t;
	Point g;
	char *buf;

	USED(val);
	buf = mallocz(Tkmaxitem, 0);
	if(buf == nil)
		return TkNomem;
	t = tk->env->top;
	tkword(t, arg, buf, buf+Tkmaxitem, nil);
	mtk = tklook(t, buf, 0);
	if(mtk == nil){
		tkerr(t, buf);
		free(buf);
		return TkBadwp;
	}
	free(buf);

	g = tkposn(tk);
	g.x -= tk->borderwidth;
	g.y += 2*tk->borderwidth;
	mtk->flag |= Tkleave;
	return tkmpost(mtk, g.x, g.y+tk->act.height);
}

char*
tkMBleave(Tk *tk, char *arg, char **val)
{
	Tk *menu, *master, *sib;
	TkCtxt *c;
	TkMenubut *tkm = TKobj(TkMenubut, tk);
	char *e;
	Point mp;

	USED(val);
	tkmenubutconf(tk, "-state normal", nil);

	c = tk->env->top->ctxt;

	menu = tklook(tk->env->top, tkm->menu, 0);
	if(menu != nil && (menu->flag & Tkmapped)) {
		tkclrmgrab(c);
		tksetmgrab(c, menu);
	}
	if(c->tkmstate.b == 0 || tkm->menu == nil)
		return nil;

	/* Moved out with button down; check if moved into another menubutton */
	if(arg == nil )
		return nil;
	e = tktxyparse(tk, &arg, &mp);
	if(e != nil )
		return e;
	mp.x += tk->act.x + tk->borderwidth * (mp.x < 0 ? -2 : 
					mp.x >= tk->act.width ? 2 : 0);
	mp.y += tk->act.y + tk->borderwidth * (mp.y < 0 ? -2 :
					mp.y >= tk->act.height ? 2 : 0);
	master = tk->master;
	if(master != nil ) {
		for(sib = master->slave; sib; sib = sib->next ) {
			if(sib->type != TKmenubutton || sib == tk || sib->flag&Tkdisabled)
				continue;
			if(mp.x < sib->act.x ||
			     mp.x >= sib->act.x + sib->act.width ||
			     mp.y < sib->act.y ||
			     mp.y >= sib->act.y + sib->act.height )
				continue;
			tkMBpress(tk, nil, nil); 	/* pop down existing */
			return tkMBpress(sib, nil, nil);/* pop up new */
		}
	}
	return nil;
}

void
tkunmapmenu(Tk *tk)
{
	Tk *mb;
	TkWin * w;
	TkCtxt * c;
	TkMenubut * tkb;

	w = TKobj(TkWin, tk);

	c = tk->env->top->ctxt;
	/* If we are holding the focus, give it back before unmap */
	if(c->tkMgrab == tk)
		tkclrmgrab(c);

	if(c->tkKgrab == tk) {
		c->tkKgrab = nil; /* Ensure we don't get notified of focus loss */
		if(w->lastfocus != nil && w->lastfocus->name != nil)
			tkfocus(tk->env->top, w->lastfocus->name->name, nil);
		else 
			tkclrfocus(tk->env->top->root, tk);
	}
	/* If menu was popped up by a menubutton, the menubutton relief should revert back to its normal state */
	for(mb = tk->env->top->root; mb; mb = mb->siblings) {
		if(mb->type != TKmenubutton || (mb->flag & Tkdisabled))
			continue;
		tkb = TKobj(TkMenubut, mb);
		if(tkb->menu != nil)
			if(tk->name != nil && strcmp(tk->name->name, tkb->menu) == 0){
				if(mb->relief < 0) {		/* shown as activated */
					mb->relief = -mb->relief;
					mb->flag |= Tkdirty;
				}
				if(c->tkMgrab == mb)
					tkclrmgrab(c);
			}
	}

	w->unmapFocusCtl = TkUnmapOnFocusOut;
	tkunmap(tk);
}


void
tkunmapmenus(TkTop *t, Tk *tk)
{
	Tk *old;
	TkWin *tkw;

	tkw = TKobj(TkWin, tk);
	if(tkw->cascade != nil) {
		old = tklook(t, tkw->cascade, 0);
		if(old != nil)
			tkunmapmenus(t, old);
		free(tkw->cascade);
		tkw->cascade = nil;
	}
	tkunmapmenu(tk);
}

char*
tkMBpress(Tk *tk, char *arg, char **val)
{
	char *e;
	Tk *menu;
	TkMenubut *tkm = TKobj(TkMenubut, tk);

	USED(arg);
	USED(val);

	/* implement key-binding for closing an open menu */

	menu = tk->env->top->ctxt->tkMgrab;
	if(menu == tk ||
	   menu == nil && tkm->menu != nil ||	/* as a trial */
	   tkm->menu != nil && menu != nil && menu->name != nil &&
	   strcmp(tkm->menu, menu->name->name) == 0){
               if(tkm->menu != nil)
			menu = tklook(tk->env->top, tkm->menu, 0);
	       if(menu != nil && (menu->flag & Tkmapped) ) {
			tkunmapmenus(tk->env->top, menu);
			tkclrmgrab(tk->env->top->ctxt);
			return nil;
	       }
	}
	if(tkm->menu != nil) {
		e = tkmenubutpost(tk, tkm->menu, nil);
		if(e != nil)
			print("tk: menubutton post: %s: %s\n", tkm->menu, e);
	}

	tk->relief = -tk->relief;
	tk->flag |= Tkdirty;
	tksetmgrab(tk->env->top->ctxt, tk);

	return nil;
}

char*
tkMBrelease(Tk *tk, char *arg, char **val)
{
	Tk *menu;
	int x, y, bw;
	TkCtxt *c;
	char *buf;
	TkMenubut *tkm = TKobj(TkMenubut, tk);

	USED(val);
	buf = mallocz(Tkmaxitem, 0);
	if(buf == nil)
		return TkNomem;
	arg = tkword(tk->env->top, arg, buf, buf+Tkmaxitem, nil);
	if(buf[0] == '\0' || arg == nil)
		return TkBadvl;
	x = atoi(buf);
	tkword(tk->env->top, arg, buf, buf+Tkmaxitem, nil);
	if(buf[0] == '\0')
		return TkBadvl;
	y = atoi(buf);
	free(buf);

	c = tk->env->top->ctxt;
	if(c->tkMgrab == tk)
		tkclrmgrab(c);

	menu = nil;
	if(tkm->menu != nil)
		menu = tklook(tk->env->top, tkm->menu, 0);

	bw = tk->borderwidth;
	if(x < -bw || x > tk->act.width+bw || y < -bw || y > tk->act.height+bw) {
		if(menu != nil)
			tkunmap(menu);
	}
		
	tk->flag |= Tkdirty;
	return nil;
}

void
tkfreemenub(Tk *tk)
{
	TkMenubut *tkm = TKobj(TkMenubut, tk);

	if(tkm->menu != nil)
		free(tkm->menu);

	tkfreelabel(tk);
}

static
TkEbind m[] = 
{
	{TkEnter,	"grab ifunset %W"},
	{TkMotion,	"%W tkMenuMotion %x %y"},
	{TkLeave,	"%W activate none"},
	{TkButton1P,	"%W tkMenuButtonDn %x @%y"},
	{TkButton1R,	"%W tkMenuButtonUp %x %y"},
	{TkFocusout,	"%W tkMenuButtonLostfocus"},
};

static
TkOption menuopt[] =
{
	"postcommand",	OPTtext,	O(TkWin, postcmd),		nil,
	nil,
};

char*
tkmenu(TkTop *t, char *arg, char **ret)
{
	Tk *tk;
	char *e;
	TkWin *tkw;
	TkName *names;
	TkOptab tko[3];

	tk = tknewobj(t, TKmenu, sizeof(Tk)+sizeof(TkWin));
	if(tk == nil)
		return TkNomem;

	tkw = TKobj(TkWin, tk);
	tk->relief = TKraised;
	tk->flag |= Tkstopevent;
	tk->borderwidth = 2;

	tko[0].ptr = tk;
	tko[0].optab = tkgeneric;
	tko[1].ptr = tkw;
	tko[1].optab = menuopt;
	tko[2].ptr = nil;

	names = nil;
	e = tkparse(t, arg, tko, &names);
	if(e != nil) {
		tkfreeobj(tk);
		return e;
	}

	e = tkbindings(t, tk, m, nelem(m));

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

	tk->flag |= Tkwindow;
	tk->geom = tkmoveresize;

	tkw->unmapFocusCtl = TkUnmapOnFocusOut;
	tkw->itemcount = 0;
	tkw->next = t->windows;
	t->windows = tk;

	return tkvalue(ret, "%s", tk->name->name);
}

void
tkfreemenu(Tk *top)
{
	Tk *tk, *f, *nexttk, *nextf;

	for(tk = top->slave; tk; tk = nexttk) {
		nexttk = tk->next;
		for(f = tk->slave; f; f = nextf) {
			nextf = f->next;
			tkfreeobj(f);
		}
		tkfreeobj(tk);
	}
	top->slave = nil;
	tkfreeframe(top);
}

static
TkOption mopt[] =
{
	"menu",		OPTtext,	O(TkMenubut, menu),		nil,
	nil,
};

static void
tkbuildmopt(TkOptab *tko, int n, Tk *tk)
{
	memset(tko, 0, n*sizeof(TkOptab));

	n = 0;
	tko[n].ptr = tk;
	tko[n++].optab = tkgeneric;

	switch(tk->type) {
	case TKcascade:
		tko[n].ptr = TKobj(TkMenubut, tk);
		tko[n++].optab = mopt;
		goto norm;
	case TKradiobutton:	
	case TKcheckbutton:
		tko[n].ptr = TKobj(TkLabel, tk);
		tko[n++].optab = tkradopts;
	case TKlabel:
	norm:
		tko[n].ptr = TKobj(TkLabel, tk);
		tko[n].optab = tkbutopts;
		break;	
	}
}

/*
 *	Change shortcut bindings for menu items whenever the shortcut
 *	character changes (may happen if either the button text or the
 *	underline position changes).  May have to do, or undo, two bindings,
 *	as shortcut invocation should be case insensitive.  Note that at
 *	present this is not internationalized.
 */
void
tkmenubindshortcut(Tk *menu, TkLabel *tkl, int old)
{
	int ul, new, ocase, ncase;

	ul = tkl->ul;
	new = -1;
	if(ul >= 0 && tkl->text != nil && strlen(tkl->text) > ul)
		new = tkl->text[ul];
	ocase = -1;
	if(old >= 'a' && old <= 'z')
		ocase = old + 'A' - 'a';
	else if(old >= 'A' && old <= 'Z')
		ocase = old + 'a' - 'A';
	if(new != old && new != ocase) {
		if(old >= 0)
			tkcancel(&menu->binds, TkKey|TKKEY(old));
		if(ocase >= 0)
			tkcancel(&menu->binds, TkKey|TKKEY(ocase));
		ncase = -1;
		if(new >= 'a' && new <= 'z')
			ncase = new + 'A' - 'a';
		else if(new >= 'A' && new <= 'Z')
			ncase = new + 'a' - 'A';
		if(new >= 0)
			tkaction(&menu->binds, TkKey|TKKEY(new),
					TkStatic, "%W tkMenuAccel %s", TkAadd);
		if(ncase >= 0)
			tkaction(&menu->binds, TkKey|TKKEY(ncase),
					TkStatic, "%W tkMenuAccel %s", TkAadd);
	}
}

static char*
tkmenuentryconf(Tk *menu, Tk *tk, char *arg)
{
	char *e;
	TkOptab tko[4];
	TkLabel *tkl;
	int ul, oldchar;

	/*
	 *  If text or underline is changed, need to adjust bindings;
	 *  an entry might also change between separator and label.
	 */
	oldchar = -1;
	if(tk->type != TKseparator) {
		tkl = TKobj(TkLabel, tk);
		ul = tkl->ul;
		if(ul >= 0 && tkl->text != nil && strlen(tkl->text) > ul)
			oldchar = tkl->text[ul];
	}
	tkbuildmopt(tko, nelem(tko), tk);
	e = tkparse(tk->env->top, arg, tko, nil);
	if(tk->type != TKseparator) {
		tksizelabel(tk);
		tkl = TKobj(TkLabel, tk);
		tkmenubindshortcut(menu, tkl, oldchar);
	}

	return e;
}

static char*
menuadd(Tk *menu, char *arg, int where)
{
	Tk *tkc;
	char *e;
	TkTop *t;
	TkLabel *tkl;
	TkWin *tkw;
	char buf[Tkmaxitem];
	
	t = menu->env->top;
	tkw = TKobj(TkWin, menu);

	arg = tkword(t, arg, buf, buf+sizeof(buf), nil);

	e = nil;
	if(strcmp(buf, "checkbutton") == 0) {
		tkc = tknewobj(t, TKcheckbutton, sizeof(Tk)+sizeof(TkLabel));
		tkc->flag = Tkwest|Tkfillx|Tktop;
		tkc->borderwidth = 2;
		tkl = TKobj(TkLabel, tkc);
		tkl->anchor = Tkwest;
		tkl->ul = -1;
		tkl->justify = Tkleft;
		e = tkmenuentryconf(menu, tkc, arg);
		tkw->itemcount++;
	}
	else
	if(strcmp(buf, "radiobutton") == 0) {
		tkc = tknewobj(t, TKradiobutton, sizeof(Tk)+sizeof(TkLabel));
		tkc->flag = Tkwest|Tkfillx|Tktop;
		tkc->borderwidth = 2;
		tkl = TKobj(TkLabel, tkc);
		tkl->anchor = Tkwest;
		tkl->ul = -1;
		tkl->justify = Tkleft;
		e = tkmenuentryconf(menu, tkc, arg);
		tkw->itemcount++;
	}
	else
	if(strcmp(buf, "command") == 0) {
		tkc = tknewobj(t, TKlabel, sizeof(Tk)+sizeof(TkLabel));
		tkc->flag = Tkwest|Tkfillx|Tktop;
		tkc->ipad.x = 2*CheckSpace;
		tkc->borderwidth = 2;
		tkl = TKobj(TkLabel, tkc);
		tkl->anchor = Tkwest;
		tkl->ul = -1;
		tkl->justify = Tkleft;
		e = tkmenuentryconf(menu, tkc, arg);
		tkw->itemcount++;
	}
	else
	if(strcmp(buf, "cascade") == 0) {
		tkc = tknewobj(t, TKcascade, sizeof(Tk)+sizeof(TkMenubut));
		tkc->flag = Tkwest|Tkfillx|Tktop;
		tkc->ipad.x = 2*CheckSpace;
		tkc->borderwidth = 2;
		tkl = TKobj(TkLabel, tkc);
		tkl->anchor = Tkwest;
		tkl->ul = -1;
		tkl->justify = Tkleft;
		e = tkmenuentryconf(menu, tkc, arg);
		tkw->itemcount++;
	}
	else
	if(strcmp(buf, "separator") == 0) {
		tkc = tknewobj(t, TKseparator, sizeof(Tk)+sizeof(TkFrame));
		tkc->flag = Tkfillx|Tktop;
		tkc->req.height = Sepheight;
		tkw->itemcount++;
	}
	else
		return TkBadvl;

	if(tkc->env == t->env && menu->env != t->env) {
		tkputenv(tkc->env);
		tkc->env = menu->env;
		tkc->env->ref++;
	}

	if(e != nil) {
		tkfreeobj(tkc);
		return e;
	}	

	tkappendpack(menu, tkc, where);

	tkpackqit(menu);		/* Should be more efficient .. */
	tkrunpack(menu->env->top);
	return nil;
}

static int
tkmindex(Tk *tk, char *p)
{
	int y, n;

	if(*p >= '0' && *p <= '9')
		return atoi(p);
	n = 0;
	if(*p == '@') {
		y = atoi(p+1);
		for(tk = tk->slave; tk; tk = tk->next) {
			if(y >= tk->act.y && y < tk->act.y+tk->act.height+2*tk->borderwidth )
				return n;
			n++;
		}
	}
	if(strcmp(p, "end") == 0 || strcmp(p, "last") == 0) {
		for(tk = tk->slave; tk && tk->next; tk = tk->next)
			n++;
		return n;
	}
	if(strcmp(p, "active") == 0) {
		for(tk = tk->slave; tk; tk = tk->next) {
			if(tk->flag & Tkfocus)
				return n;
			n++;
		}
	}
	if(strcmp(p, "none") == 0)
		return 100000;

	return -1;
}

static int
tkmenudel(Tk *tk, int y)
{
	Tk *f, **l, *next;

	l = &tk->slave;
	for(tk = tk->slave; tk; tk = tk->next) {
		if(y-- == 0) {
			*l = tk->next;
			for(f = tk->slave; f; f = next) {
				next = f->next;
				tkfreeobj(f);
			}
			tkfreeobj(tk);
			return 1;
		}
		l = &tk->next;
	}
	return 0;	
}

/*
static int
tkneedkbd(Tk *tk)
{
	TkAction *a;

	for(a = tk->binds; a != nil; a = a->link)
		if(a->event & TkKey)
			return 1;
	return 0;
}
*/

char*
tkmpost(Tk *tk, int x, int y)
{
	char *e;
	TkWin *w;
	Tk *f;
	TkCtxt *c;
	TkTop *t;
	Rectangle *dr;

	w = TKobj(TkWin, tk);
	if(w->postcmd != nil) {
		e = tkexec(tk->env->top, w->postcmd, nil);
		if(e != nil) {
			print("%s: postcommand: %s: %s\n", tk->name != nil ?
				tk->name->name : "(unnamed)", w->postcmd, e);
			return e;
		}
	}
	t = tk->env->top;
	dr = &t->display->image->r;
	if(x+tk->act.width > dr->max.x)
		x = dr->max.x - tk->act.width;
	if(x < 0)
		x = 0;
	if(y+tk->act.height > dr->max.y)
		y = dr->max.y - tk->act.height;
	if(y < 0)
		y = 0;
	tkmoveresize(tk, x, y, tk->act.width, tk->act.height);
	e = tkmap(tk);
	if(e != nil)
		return e;
	
	/* Keep track of who held the focus so we can give it back at unmap */
	c = tk->env->top->ctxt;
	w->lastfocus = c->tkKgrab;

	if((w->lastfocus != tk) && (tk->name != nil) /* && tkneedkbd(tk) */)
		tkfocus(tk->env->top, tk->name->name, nil);

	/* Make sure slaves are redrawn */
	for(f = tk->slave; f; f = f->next)
		f->flag |= Tkdirty;
	return tkupdate(tk->env->top);
}

/* Widget Commands (+ means implemented)
	+activate
	+add
	+cget
	+configure
	+delete
	+entrycget
	+entryconfigure
	+index
	+insert
	+invoke
	+post
	+postcascade
	+type
	+unpost
	+yposition
*/

Tk*
tkmenuindex2ptr(Tk *tk, char **arg)
{
	int index;
	char *buf;

	buf = mallocz(Tkmaxitem, 0);
	if(buf == nil)
		return nil;
	*arg = tkword(tk->env->top, *arg, buf, buf+Tkmaxitem, nil);
	index = tkmindex(tk, buf);
	free(buf);
	if(index < 0)
		return nil;

	for(tk = tk->slave; tk && index; tk = tk->next)
			index--;

	if(tk == nil)
		return nil;

	return tk;
}

char*
tkmenuentrycget(Tk *tk, char *arg, char **val)
{
	Tk *etk;
	TkOptab tko[4];

	etk = tkmenuindex2ptr(tk, &arg);
	if(etk == nil)
		return TkBadix;

	tkbuildmopt(tko, nelem(tko), etk);
	return tkgencget(tko, arg, val, tk->env->top);
}

char*
tkmenucget(Tk *tk, char *arg, char **val)
{
	TkWin *tkw;
	TkOptab tko[4];

	tkw = TKobj(TkWin, tk);
	tko[0].ptr = tk;
	tko[0].optab = tkgeneric;
	tko[1].ptr = tk;
	tko[1].optab = tktop;
	tko[2].ptr = tkw;
	tko[2].optab = menuopt;
	tko[3].ptr = nil;

	return tkgencget(tko, arg, val, tk->env->top);
}

char*
tkmenuconf(Tk *tk, char *arg, char **val)
{
	char *e;
	TkGeom g;
	int bd;
	TkWin *tkw;
	TkOptab tko[3];

	tkw = TKobj(TkWin, tk);
	tko[0].ptr = tk;
	tko[0].optab = tkgeneric;
	tko[1].ptr = tkw;
	tko[1].optab = menuopt;
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
tkmenuadd(Tk *tk, char *arg, char **val)
{
	USED(val);
	return menuadd(tk, arg, -1);	
}

char*
tkmenuinsert(Tk *tk, char *arg, char **val)
{
	int index;
	char *buf;

	USED(val);
	buf = mallocz(Tkmaxitem, 0);
	if(buf == nil)
		return TkNomem;
	arg = tkword(tk->env->top, arg, buf, buf+Tkmaxitem, nil);
	index = tkmindex(tk, buf);
	free(buf);
	return menuadd(tk, arg, index);
}

static void
tkmenuclr(Tk *tk)
{
	Tk *f;

	for(f = tk->slave; f; f = f->next) {
		if(f->flag & Tkfocus) {
			f->flag &= ~Tkfocus;
			f->relief = TKflat;
			if(f->type != TKseparator)
				tklabelrestorerelief(f, nil, nil);
			f->flag |= Tkdirty;
		}
	}
}

char*
tkmenuactivate(Tk *tk, char *arg, char **val)
{
	Tk *f;
	int index;
	char *buf;
	
	USED(val);
	buf = mallocz(Tkmaxitem, 0);
	if(buf == nil)
		return TkNomem;
	tkword(tk->env->top, arg, buf, buf+Tkmaxitem, nil);
	index = tkmindex(tk, buf);
	free(buf);

	for(f = tk->slave; f; f = f->next)
		if(index-- == 0)
			break;

	if(f == nil || f->flag & Tkdisabled) {
		tkmenuclr(tk);
		return nil;
	}
	if(f->flag & Tkfocus)
		return nil;

	tkmenuclr(tk);
	f->flag |= Tkfocus|Tkdirty;
	if(f->type != TKseparator)
		tklabelsaverelief(f, nil, nil);
	f->relief = TKraised;

	return nil;
}

static Tk*
tkpostcascade(Tk *tk)
{
	Tk *tkm;
	Point g;
	TkMenubut *m;
	Rectangle *dr;
	TkLabel *tkl;

	if(tk->flag & Tkdisabled)
		return nil;

	m = TKobj(TkMenubut, tk);
	tkm = tklook(tk->env->top, m->menu, 0);
	if(tkm == nil)
		return nil;

	dr = &tk->env->top->display->image->r;
	g = tkposn(tk);
	g.x += tk->act.width;
	g.y += 2;
	if(g.x+tkm->act.width > dr->max.x){
		if(g.x >= tk->act.width+tkm->act.width)
			g.x -= tk->act.width+tkm->act.width;
		else if(g.y >= tkm->act.height+4)
			g.y -= tkm->act.height+4;
	}
	if(tkmpost(tkm, g.x, g.y) == nil){
		tkl = TKobj(TkLabel, tk);
		if(tkl->command != nil)
			tkexec(tk->env->top, tkl->command, nil);
		return tkm;
	}
	return nil;
}

char*
tkmenuinvoke(Tk *tk, char *arg, char **val)
{
	USED(val);
	tk = tkmenuindex2ptr(tk, &arg);
	if(tk == nil)
		return nil;

	switch(tk->type) {
	case TKlabel:
	case TKcheckbutton:
		tkbuttoninvoke(tk, arg, nil);
		break;
	case TKradiobutton:
		tkradioinvoke(tk, arg, nil);
		break;
	case TKcascade:
		tkpostcascade(tk);
		break;
	}
	return nil;
}

char*
tkmenudelete(Tk *tk, char *arg, char **val)
{
	int index1, index2;
	char *buf;

	USED(val);
	buf = mallocz(Tkmaxitem, 0);
	if(buf == nil)
		return TkNomem;
	arg = tkitem(buf, arg);
	index1 = tkmindex(tk, buf);
	if(index1 == -1) {
		free(buf);
		return TkBadvl;
	}
	index2 = index1;
	if(*arg != '\0') {
		tkitem(buf, arg);
		index2 = tkmindex(tk, buf);
	}
	free(buf);
	if(index2 == -1)
		return TkBadvl;
	while(index2 >= index1 && tkmenudel(tk, index2))
		index2--;

	tkpackqit(tk);
	tkrunpack(tk->env->top);
	return nil;
}

char*
tkmenupost(Tk *tk, char *arg, char **val)
{
	int x, y;
	TkTop *t;
	char *buf;

	USED(val);
	buf = mallocz(Tkmaxitem, 0);
	if(buf == nil)
		return TkNomem;
	t = tk->env->top;
	arg = tkword(t, arg, buf, buf+Tkmaxitem, nil);
	if(buf[0] == '\0') {
		free(buf);
		return TkBadvl;
	}
	x = atoi(buf);
	tkword(t, arg, buf, buf+Tkmaxitem, nil);
	if(buf[0] == '\0') {
		free(buf);
		return TkBadvl;
	}
	y = atoi(buf);
	free(buf);

	return tkmpost(tk, x, y);
}

char*
tkmenuunpost(Tk *tk, char *arg, char **val)
{
	USED(arg);
	USED(val);
	tkunmapmenu(tk);
	return nil;
}

char*
tkmenuindex(Tk *tk, char *arg, char **val)
{
	char *buf;
	char *e;

	buf = mallocz(Tkmaxitem, 0);
	if(buf == nil)
		return TkNomem;
	tkword(tk->env->top, arg, buf, buf+Tkmaxitem, nil);
	e = tkvalue(val, "%d", tkmindex(tk, buf));
	free(buf);
	return e;
}

char*
tkmenuyposn(Tk *tk, char *arg, char **val)
{
	tk = tkmenuindex2ptr(tk, &arg);
	if(tk == nil)
		return TkBadix;
	return tkvalue(val, "%d", tk->act.y);
}

char*
tkmenupostcascade(Tk *tk, char *arg, char **val)
{
	USED(val);
	tk = tkmenuindex2ptr(tk, &arg);
	if(tk == nil || tk->type != TKcascade)
		return nil;

	tk = tkpostcascade(tk);
	if(tk == nil)
		return TkBadwp;
	return nil;
}

char*
tkmenutype(Tk *tk, char *arg, char **val)
{
	tk = tkmenuindex2ptr(tk, &arg);
	if(tk == nil)
		return TkBadix;

	return tkvalue(val, tk->type == TKlabel ? "command" : tkmethod[tk->type].name);
}

char*
tkmenuentryconfig(Tk *tk, char *arg, char **val)
{
	Tk *etk;
	char *e;

	USED(val);
	etk = tkmenuindex2ptr(tk, &arg);
	if(etk == nil)
		return TkBadix;

	e = tkmenuentryconf(tk, etk, arg);
	tkpackqit(tk);
	tkrunpack(tk->env->top);
	return e;
}

/* default bindings */
char*
tkMenuMotion(Tk *tk, char *arg, char **val)
{
	int x;
	char *buf;
	char *e;

	tk->flag &= ~Tkleave;

	buf = mallocz(Tkmaxitem, 0);
	if(buf == nil)
		return TkNomem;
	arg = tkword(tk->env->top, arg, buf, buf+Tkmaxitem, nil);
	if(buf[0] == '\0' || arg == nil) {
		free(buf);
		return TkBadvl;
	}

	x = atoi(buf);
	if(x < 0 || x > tk->act.width) {
		free(buf);
		return nil;
	}

	buf[0] = '@';
	strncpy(buf+1, tkskip(arg, " \t"), Tkmaxitem-2);
	e = tkmenuactivate(tk, buf, val);
	free(buf);
	return e;
}

char*
tkMenuButtonLostfocus(Tk *tk, char *arg, char **val)
{
	TkWin *tkw;

	USED(val);
	USED(arg);

	tk->flag &= ~Tkleave;

	tkw = TKobj(TkWin, tk);

	if(tkw->unmapFocusCtl & TkUnmapOnFocusOut) {
		tkunmapmenu(tk);
	}
	
	return nil;
}

char*
tkMenuButtonDn(Tk *tk, char *arg, char **val)
{
	int x;
	TkTop *t;
	TkWin *tkw;
	Tk *post, *old, *f;
	char *buf;

	USED(val);

	tk->flag &= ~Tkleave;

	buf = mallocz(Tkmaxitem, 0);
	if(buf == nil)
		return TkNomem;

	t = tk->env->top;
	arg = tkword(t, arg, buf, buf+Tkmaxitem, nil);
	if(buf[0] == '\0' || arg == nil) {
		free(buf);
		return TkBadvl;
	}

	x = atoi(buf);
	free(buf);

	/* Shouldn't the menu be unmapped on button 1 press outside menu? */
	if(x < 0 || x > tk->act.width) {
		tkunmapmenus(t, tk);
		return nil;
	}

	tkw = TKobj(TkWin, tk);
	tkw->unmapFocusCtl = TkUnmapOnFocusOut;
	f = tkmenuindex2ptr(tk, &arg);
	if(f != nil && (f->flag & Tkfocus) == 0) {
		tkmenuclr(tk);
		f->flag |= Tkfocus | Tkdirty;
	}
	post = nil;
	if(f != nil && f->type == TKcascade) {
		tkw->unmapFocusCtl = TkNoUnmapOnFocusOut;
		post = tkpostcascade(f);
	}

	if(tkw->cascade != nil) {
		old = tklook(t, tkw->cascade, 0);
		if(old == post)
			return nil;
		if(old != nil)
			tkunmapmenus(t, old);
		free(tkw->cascade);
		tkw->cascade = nil;
	}
	if(post != nil) {
	        if(post->name != nil) 
			tkw->cascade = strdup(post->name->name);
		else 
			tkw->cascade = nil; /* not sure about the error msg */
		if(tkw->cascade == nil)
			return TkNomem;
		f->flag |= Tkfocus | Tkdirty;
		post->flag |= Tkleave;
	}

	return nil;
}

char*
tkMenuButtonUp(Tk *tk, char *arg, char **val)
{
	TkTop *t;
	TkWin *tkw;
	Tk *item, *next;
	char *f2, *find = "active";

	if(tk->flag&Tkleave){
		tk->flag &= ~Tkleave;
		return nil;
	}

	USED(arg);
	USED(val);
	f2 = find;
	item = tkmenuindex2ptr(tk, &f2);
	if(item != nil && (item->type == TKcascade || item->type == TKseparator))
		return nil;

	tkmenuinvoke(tk, find, nil);

	t = tk->env->top;
	/* Unpost menu tree */
	for(;;) {
		tkw = TKobj(TkWin, tk);
		next = tklook(t, tk->name->name, 1);
		tkunmapmenu(tk);
		if(tkw->cascade != nil) {
			item = tklook(t, tkw->cascade, 0);
			if(item != nil)
				tkunmapmenu(item);
			free(tkw->cascade);
			tkw->cascade = nil;
		}
		tk = next;
		if(tk == nil || tk->type != TKmenu)
			break;
	}
	return nil;
}

char*
tkMenuAccel(Tk *tk, char *arg, char **val)
{
	TkTop *t;
	TkWin *tkw;
	Tk *button;
	TkLabel *tkl;
	char buf[Tkmaxitem], *p, *e;
	int k, l;
	
	USED(val);

	t = tk->env->top;
	arg = tkword(t, arg, buf, buf+sizeof(buf), nil);
	if(buf[0] == '\0' || arg == nil)
		return TkBadvl;
	k = atoi(buf);

	/* Find the button corresponding to the key event */
	for(button = tk->slave; button ; button = button->next) {
		if((button->flag & Tkdisabled) == 0 && (
				button->type == TKcheckbutton ||
				button->type == TKradiobutton ||
				button->type == TKlabel       ||
				button->type == TKcascade)) {
			tkl = TKobj(TkLabel, button);
	  		p = tkl->text;
			if(tkl->ul >= 0 && p != nil && tkl->ul < strlen(p)) {
				l = p[tkl->ul];
				/* Comparison not internationalized */
				if(k >= 'a' && k <= 'z')
					k += 'A' - 'a';
				if(l >= 'a' && l <= 'z')
					l += 'A' - 'a';
				if(k == l) {
					e = tkmenuentryconf(tk, button, "-state active");
					if(e != nil )
						return e;
					tkclrmgrab(tk->env->top->ctxt);
					tkw = TKobj(TkWin, tk);
					if(tk->env->top->ctxt->tkKgrab == tk) {
						tk->env->top->ctxt->tkKgrab = nil;
						if(tkw->lastfocus != nil && tkw->lastfocus->name != nil)
							tkfocus(tk->env->top, tkw->lastfocus->name->name, nil);
						else
							tkclrfocus(tk->env->top->root, tk);
					}
					e = tkMenuButtonDn(tk, "0 active", nil);
					if(e == nil )
						e = tkMenuButtonUp(tk, nil, nil);
					tkmenuclr(tk);
					return e;
				}
			}
		}
	}
	return nil;
}
