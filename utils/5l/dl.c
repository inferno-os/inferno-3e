#include	"l.h"

#define KIF	"kernel interface file"

static Prog *datp;
static Sym *linkt;

static int *strind;

static Prog* newprg(int, Prog*);

static int
isstring(Sym *s)
{
	return s != S && strcmp(s->name, ".string") == 0;
}

void
kif(char *f)
{	
	int i, n, d;
	long o;
	Prog *p, *q, *fp, *lp, *dp;
	Sym *s;

	s = lookup("__link", 0);
	if(s->type != 0){
		diag("dynamic link table entry __link already defined\n");
		errorexit();
	}
	s->type = SBSS;
	s->value = sizeof(long*);
	linkt = s;

	fp = firstp;
	lp = lastp;
	dp = datap;
	objfile(f);
	if(fp != firstp || lp != lastp){
		diag("code in %s %s\n", KIF, f);
		errorexit();
	}
	p = datap;
	datap = dp;
	dp = P;
	for( ; p != P && p != datap; p = q){
		q = p->link;
		p->link = dp;
		dp = p;
	}

	o = 0;
	s = S;
	lp = nil;
	d = 0;
	for(p = dp; p != P; p = p->link){
		if(isstring(p->from.sym) || isstring(p->to.sym)){
			if(lp == nil)
				dp = p->link;
			else
				lp->link = p->link;
			continue;
		}
		lp = p;
		if(p->as == ADYNT || p->as == AINIT){
			diag("bad data type in %s %s\n", KIF, f);
			errorexit();
		}
		if(s == S)
			s = p->from.sym;
		if(s != p->from.sym){
			diag("more than one data item in %s %s\n", KIF, f);
			errorexit();
		}
		if(d == 0 && p->from.offset > 0){
			d = p->from.offset;
			o += d;
		}
		if(o != p->from.offset){
			diag("bad data size in %s %s\n", KIF, f);
			errorexit();
		}
		o += d;
		if(p->to.sym == nil){
			diag("bad pointer value in %s %s\n", KIF, f);
			errorexit();
		}
		if(p->to.sym->type != SXREF){
			diag("%s pointer value %s already defined\n", KIF, p->to.sym->name);
			errorexit();
		}
	}
	datp = dp;
	n = o/d;
	strind = (int *)malloc(n*sizeof(int));
	for(i = 0; i < n; i++)
		strind[i] = 0;
}

static Prog*
newprg(int op, Prog* p)
{
	Prog* q;

	q = prg();
	q->as = op;
	q->line = p->line;
	q->pc = p->pc;
	q->reg = NREG;
	q->link = p->link;
	p->link = q;
	return q;
}

int
dynfn(Sym *s)
{
	int i, k;
	Prog *dp;

	k = -1;
	for(i = 0, dp = datp; dp != P; i++, dp = dp->link){
		if(s == dp->to.sym){
			k = i;
			strind[k] = 1;	/* used */
			break;
		}
	}
	return k;
}

int
dyncall(Prog *p, int div)
{
	int k;
	Prog *q, *q0, t;

	if((k = dynfn(p->to.sym)) < 0)
		return 0;

	if(!seenthumb && debug['y']){
		p->to.offset = 0;
		p->to.type = D_BRANCH;
		p->cond = P;
		return 1;
	}

#define R	1

	if(!seenthumb && debug['x']){
		p->to.sym->value = 0x7fffff00;
		p->to.sym->type = SDYN;

		p->as = AMOVW;
		p->from.type = D_CONST;
		p->from.name = D_EXTERN;
		p->from.sym = p->to.sym;
		p->from.offset = k;
		p->reg = NREG;
		p->to.type = D_REG;
		p->to.name = D_NONE;
		p->to.sym = S;
		p->to.reg = R;

		q = newprg(ABL, p);
		q->to.type = D_OREG;
		q->to.offset = 0;
		q->to.reg = R;
		q->scond = p->scond;
	}
	else{
		p->as = AMOVW;
		p->from.type = D_OREG;
		p->from.name = D_EXTERN;
		p->from.sym = linkt;
		p->from.offset = 0;
		p->reg = NREG;
		p->to.type = D_REG;
		p->to.name = D_NONE;
		p->to.sym = nil;
		p->to.reg = R;
	
		q = newprg(AMOVW, p);
		q->from.type = D_OREG;
		q->from.name = D_NONE;
		q->from.reg = R;
		q->from.offset = 3*k*sizeof(long*);
		q->to.type = D_REG;
		q->to.reg = R;
		q->scond = p->scond;

		q = newprg(ABL, q);
		q->from.type = D_NONE;
		q->to.type = D_OREG;
		q->to.name = D_NONE;
		q->to.reg = R;
		q->to.offset = 0;
		q->scond = p->scond;
	}

	if(div){
		q0 = newprg(AMOVW, p);
		q0->from.type = D_REG;
		q0->from.reg = R;
		q0->to.type = D_OREG;
		q0->to.reg = REGSP;
		q0->to.offset = 0;
		q0->scond = p->scond;

		t = *p;
		*p = *q0;
		*q0 = t;
		q0->link = p->link;
		p->link = q0;

		q = newprg(AMOVW, q);
		q->from.type = D_OREG;
		q->from.reg = REGSP;
		q->from.offset = 0;
		q->to.type = D_REG;
		q->to.reg = R;
		q->scond = p->scond;
	}

#undef R

	return 1;
}

static struct relocinfo{
	long n;
	long m;
	long *rel;
} reloc[5];

static void
grow(struct relocinfo *r)
{
	int n;
	long *nrel;

	n = r->m;
	r->m += 32;
	nrel = malloc(r->m*sizeof(long));
	memmove(nrel, r->rel, n*sizeof(long));
	free(r->rel);
	r->rel = nrel;
}

static int
inrel(long a, struct relocinfo *r)
{
	int i;
	long n, *rel;

	n = r->n;
	rel = r->rel;
	for(i = 0; i < n; i++)
		if(rel[i] == a)
			return 1;
	return 0;
}

void
dynreloc(long a, int intext, Sym *s)
{
	int i = 0;
	struct relocinfo *r;

	if(!intext)
		i = 2;
	if(s == S || s->type == STEXT || s->type == SLEAF)
		;
	else if(s->type == SDATA || s->type == SDATA1 || s->type == SBSS)
		i++;
	else if(s->type == SXREF)
		return;
	else
		diag("help: dynreloc cannot cope\n");
	r = &reloc[i];
	if(inrel(a, r))
		return;
	if(r->n >= r->m)
		grow(r);
	r->rel[r->n++] = a;
}

void
creloc(int f, long a)
{
	struct relocinfo *r = &reloc[4];

	if(f < 0 || f > 255){
		diag("bad function table index");
		errorexit();
	}
	if(inrel(a, r))
		return;
	if(r->n >= r->m)
		grow(r);
	r->rel[r->n++] = f;
	r->rel[r->n++] = a;
}

static void
outrel(struct relocinfo *r)
{
	int i, n = r->n;
	long *p;

	lput(n);
	for(i = 0, p = r->rel; i < n; i++, p++)
		lput(*p);
}

static void
outstrtab(int sz)
{
	int k;
	char *s;
	Prog *dp;

	lput(sz);
	for(k = 0, dp = datp; dp != P; k++, dp = dp->link){
		if(strind[k] >= 0){
			for(s = dp->to.sym->name; *s != '\0'; s++)
				cput(*s);
			cput('\0');
		}
	}
}

static void
dostrind(void)
{
	int i, k;
	Prog *dp;

	i = 0;
	for(k = 0, dp = datp; dp != P; k++, dp = dp->link){
		if(strind[k]){
			strind[k] = i;
			i += strlen(dp->to.sym->name)+1;
		}
		else
			strind[k] = -1;
	}
	outstrtab(i);
}

static void
coutrel(void)
{
	struct relocinfo *r = &reloc[4];
	int i, n = r->n;
	long *p;

	dostrind();
	if(debug['y'])
		cput(0x80+24);	/* 24 bit relative */
	else if(debug['x'])
		cput(32);			/* 32 bit absolute */
	else
		diag("bad coutrel");
	lput(n/2);
	for(i = 0, p = r->rel; i < n; i++){
		/* cput(*p++); */
		hput(strind[*p++]);
		lput(*p++);
	}
}

static void
dreloc(void)
{
	Prog *p;
	long a;

	for(p = datap; p != P; p = p->link){
		if(p->to.type == D_CONST && p->to.sym){
			if(isfnptr(&p->to) && dynfn(p->to.sym) >= 0)
				diag("cannot use interface function %s as a function pointer", p->to.sym->name);
			a = p->from.sym->value + p->from.offset + INITDAT;
			dynreloc(a, 0, p->to.sym);
		}
		/* print("%P\n", p); */
	}	
}

void
asmdyn(void)
{
	int i;
	Prog *p;
	Sym *s;
	char buf[32];

	dreloc();

	for(p = datp; p != P; p = p->link)
		p->to.sym->type = STEXT;	// stop undefined messages at end

	lput(0xfedcba98);
	if(module != nil){
		for(i = 0; module[i]; i++)
			cput(module[i]);
	}
	cput(0);
	if(module != nil){
		strcpy(buf, module);
		strcat(buf, "end");
		s = lookup(buf, 0);
		if(s->type == STEXT){
			if(s->thumb)
				lput(s->value+1);	// T bit
			else
				lput(s->value);
		}
		else
			lput(-1);
	}
	else
		lput(-1);
	if(linkt != S)
		lput(linkt->value);
	else
		lput(-1);
	if(module != nil){
		strcpy(buf, module);
		strcat(buf, "modtab");
		s = lookup(buf, 0);
		if(s == nil){
			diag("missing module table: %s\n", buf);
			errorexit();
		}
		lput(s->value);
	}
	else
		lput(-1);
	// [tt|td|dt|dd]reloc
	for(i = 0; i < 4; i++)
		outrel(&reloc[i]);
	// call reloc
	if(reloc[4].n > 0){
		lput(0x89abcdef);
		coutrel();
	}
}

long
dynentry(Sym *s)
{
	char buf[32];

	s->type = STEXT;	// prevent error message
	if(module == nil)
		return -1;
	strcpy(buf, module);
	strcat(buf, "init");
/*
	for(p = buf; *p != 0; p++){
		if(*p >= 'A' && *p <= 'Z')
			*p += 'a' - 'A';
	}
*/
	s = lookup(buf, 0);
	if(s->type == STEXT){
		if(s->thumb)
			return  s->value+1;	// T bit
		else
			return s->value;
	}
	return -1;
}
