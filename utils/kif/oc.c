#define EXTERN

#include "cc.h"

/* dummy back end */

#define SZ_CHAR	1
#define SZ_SHORT	2
#define SZ_INT	4
#define SZ_LONG	4
#define SZ_FLOAT	4
#define SZ_IND	4
#define SZ_VLONG	8
#define SZ_DOUBLE	8

schar	ewidth[NTYPE] =
{
	-1,		/* [TXXX] */
	SZ_CHAR,	/* [TCHAR] */
	SZ_CHAR,	/* [TUCHAR] */
	SZ_SHORT,	/* [TSHORT] */
	SZ_SHORT,	/* [TUSHORT] */
	SZ_INT,		/* [TINT] */
	SZ_INT,		/* [TUINT] */
	SZ_LONG,	/* [TLONG] */
	SZ_LONG,	/* [TULONG] */
	SZ_VLONG,	/* [TVLONG] */
	SZ_VLONG,	/* [TUVLONG] */
	SZ_FLOAT,	/* [TFLOAT] */
	SZ_DOUBLE,	/* [TDOUBLE] */
	SZ_IND,		/* [TIND] */
	0,		/* [TFUNC] */
	-1,		/* [TARRAY] */
	0,		/* [TVOID] */
	-1,		/* [TSTRUCT] */
	-1,		/* [TUNION] */
	SZ_INT,		/* [TENUM] */
};

long	ncast[NTYPE] =
{
	0,				/* [TXXX] */
	BCHAR|BUCHAR,			/* [TCHAR] */
	BCHAR|BUCHAR,			/* [TUCHAR] */
	BSHORT|BUSHORT,			/* [TSHORT] */
	BSHORT|BUSHORT,			/* [TUSHORT] */
	BINT|BUINT|BLONG|BULONG|BIND,	/* [TINT] */
	BINT|BUINT|BLONG|BULONG|BIND,	/* [TUINT] */
	BINT|BUINT|BLONG|BULONG|BIND,	/* [TLONG] */
	BINT|BUINT|BLONG|BULONG|BIND,	/* [TULONG] */
	BVLONG|BUVLONG,			/* [TVLONG] */
	BVLONG|BUVLONG,			/* [TUVLONG] */
	BFLOAT,				/* [TFLOAT] */
	BDOUBLE,			/* [TDOUBLE] */
	BLONG|BULONG|BIND,		/* [TIND] */
	0,				/* [TFUNC] */
	0,				/* [TARRAY] */
	0,				/* [TVOID] */
	BSTRUCT,			/* [TSTRUCT] */
	BUNION,				/* [TUNION] */
	0,				/* [TENUM] */
};

void
codgen(Node *n, Node *nn)
{
	USED(n);
	USED(nn);
}

void
xcom(Node *n)
{
	USED(n);
}

long
outstring(char *s, long n)
{
	USED(s);
	USED(n);
	return 0;
}

long
outlstring(ushort *s, long n)
{
	USED(s);
	USED(n);
	return 0;
}

void
gextern(Sym *s, Node *a, long o, long w)
{
	USED(s);
	USED(a);
	USED(o);
	USED(w);
}

void
ginit(void)
{
	thechar = 'o';
	thestring = "nobody";
	tfield = types[TLONG];
}

void
gclean(void)
{
}

long
exreg(Type *t)
{
	USED(t);
	return 0;
}

long
align(long i, Type *t, int op)
{
	long o;
	Type *v;
	int w;

	o = i;
	w = 1;
	switch(op) {
	default:
		diag(Z, "unknown align opcode %d", op);
		break;

	case Asu2:	/* padding at end of a struct */
		w = SZ_LONG;
		break;

	case Ael1:	/* initial allign of struct element */
		for(v=t; v->etype==TARRAY; v=v->link)
			;
		w = ewidth[v->etype];
		if(w <= 0 || w >= SZ_LONG)
			w = SZ_LONG;
		break;

	case Ael2:	/* width of a struct element */
		o += t->width;
		break;

	case Aarg0:	/* initial passbyptr argument in arg list */
		if(typesuv[t->etype]) {
			o = align(o, types[TIND], Aarg1);
			o = align(o, types[TIND], Aarg2);
		}
		break;

	case Aarg1:	/* initial allign of parameter */
		w = ewidth[t->etype];
		if(w <= 0 || w >= SZ_LONG) {
			w = SZ_LONG;
			break;
		}
		w = 1;		/* little endian no adjustment */
		break;

	case Aarg2:	/* width of a parameter */
		o += t->width;
		w = SZ_LONG;
		break;

	case Aaut3:	/* total allign of automatic */
		o = align(o, t, Ael2);
		o = align(o, t, Ael1);
		w = SZ_LONG;	/* because of a pun in cc/dcl.c:contig() */
		break;
	}
	o = round(o, w);
	if(debug['A'])
		print("align %s %ld %T = %ld\n", bnames[op], i, t, o);
	return o;
}

long
maxround(long max, long v)
{
	v = round(v, SZ_LONG);
	if(v > max)
		return v;
	return max;
}
