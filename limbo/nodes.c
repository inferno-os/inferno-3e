#include "limbo.h"

int
istuple(Node *n)
{
	Decl *d;

	switch(n->op){
	case Otuple:
		return 1;
	case Oname:
		d = n->decl;
		if(d->importid != nil)
			d = d->importid;
		return d->store == Dconst && (n->ty->kind == Ttuple || n->ty->kind == Tadt);
	case Odot:
		return istuple(n->left);
	}
	return 0;
}

static Node*
tuplemem(Node *n, Decl *d)
{
	Type *ty;
	Decl *ids;

	ty = n->ty;
	n = n->left;
	for(ids = ty->ids; ids != nil; ids = ids->next){
		if(ids->sym == d->sym)
			break;
		else
			n = n->right;
	}
	if(n == nil)
		fatal("tuplemem cannot cope !\n");
	return n->left;
}

int
varcom(Decl *v)
{
	Node *n, tn;

	n = v->init;
	n = fold(n);
	v->init = n;
	if(debug['v'])
		print("variable '%D' val %V\n", v, n);
	if(n == nil)
		return 1;

	tn = znode;
	tn.op = Oname;
	tn.decl = v;
	tn.src = v->src;
	tn.ty = v->ty;
	return initable(&tn, n, 0);
}

int
initable(Node *v, Node *n, int allocdep)
{
	Node *e;

	switch(n->ty->kind){
	case Tiface:
	case Tgoto:
	case Tcase:
	case Tcasec:
	case Talt:
		return 1;
	case Tint:
	case Tbig:
	case Tbyte:
	case Treal:
	case Tstring:
		if(n->op != Oconst)
			break;
		return 1;
	case Tadt:
	case Tadtpick:
	case Ttuple:
		if(n->op == Otuple)
			n = n->left;
		else if(n->op == Ocall)
			n = n->right;
		else
			break;
		for(; n != nil; n = n->right)
			if(!initable(v, n->left, allocdep))
				return 0;
		return 1;
	case Tarray:
		if(n->op != Oarray)
			break;
		if(allocdep >= DADEPTH){
			nerror(v, "%Vs initializer has arrays nested more than %d deep", v, allocdep);
			return 0;
		}
		allocdep++;
		usedesc(mktdesc(n->ty->tof));
		if(n->left->op != Oconst){
			nerror(v, "%Vs size is not a constant", v);
			return 0;
		}
		for(e = n->right; e != nil; e = e->right)
			if(!initable(v, e->left->right, allocdep))
				return 0;
		return 1;
	case Tany:
		return 1;
	case Tref:
	case Tlist:
	default:
		nerror(v, "can't initialize %Q", v);
		return 0;
	}
	nerror(v, "%Vs initializer, %V, is not a constant expression", v, n);
	return 0;
}

/*
 * merge together two sorted lists, yielding a sorted list
 */
static Node*
elemmerge(Node *e, Node *f)
{
	Node rock, *r;

	r = &rock;
	while(e != nil && f != nil){
		if(e->left->left->val <= f->left->left->val){
			r->right = e;
			e = e->right;
		}else{
			r->right = f;
			f = f->right;
		}
		r = r->right;
	}
	if(e != nil)
		r->right = e;
	else
		r->right = f;
	return rock.right;
}

/*
 * recursively split lists and remerge them after they are sorted
 */
static Node*
recelemsort(Node *e, int n)
{
	Node *r, *ee;
	int i, m;

	if(n <= 1)
		return e;
	m = n / 2 - 1;
	ee = e;
	for(i = 0; i < m; i++)
		ee = ee->right;
	r = ee->right;
	ee->right = nil;
	return elemmerge(recelemsort(e, n / 2),
			recelemsort(r, (n + 1) / 2));
}

/*
 * sort the elems by index; wild card is first
 */
Node*
elemsort(Node *e)
{
	Node *ee;
	int n;

	n = 0;
	for(ee = e; ee != nil; ee = ee->right){
		if(ee->left->left->op == Owild)
			ee->left->left->val = -1;
		n++;
	}
	return recelemsort(e, n);
}

/*
 * constant folding for typechecked expressions,
 */
Node*
fold(Node *n)
{
	if(n == nil)
		return nil;
	if(debug['F'])
		print("fold %n\n", n);
	n = efold(n);
	if(debug['F'])
		print("folded %n\n", n);
	return n;
}

Node*
efold(Node *n)
{
	Decl *d;
	Node *left, *right;

	if(n == nil)
		return nil;

	left = n->left;
	right = n->right;
	switch(n->op){
	case Oname:
		d = n->decl;
		if(d->importid != nil)
			d = d->importid;
		if(d->store != Dconst){
			if(d->store == Dtag){
				n->op = Oconst;
				n->ty = tint;
				n->val = d->tag;
			}
			break;
		}
		switch(n->ty->kind){
		case Tbig:
			n->op = Oconst;
			n->val = d->init->val;
			break;
		case Tbyte:
			n->op = Oconst;
			n->val = d->init->val & 0xff;
			break;
		case Tint:
			n->op = Oconst;
			n->val = d->init->val;
			break;
		case Treal:
			n->op = Oconst;
			n->rval = d->init->rval;
			break;
		case Tstring:
			n->op = Oconst;
			n->decl = d->init->decl;
			break;
		case Ttuple:
			*n = *d->init;
			break;
		case Tadt:
			*n = *d->init;
			n = rewrite(n);	/* was call */
			break;
		default:
			fatal("unknown const type %T in efold", n->ty);
			break;
		}
		break;
	case Oadd:
		left = efold(left);
		right = efold(right);
		n->left = left;
		n->right = right;
		if(n->ty == tstring && left->op == Oconst && right->op == Oconst)
			n = mksconst(&n->src, stringcat(left->decl->sym, right->decl->sym));
		break;
	case Olen:
		left = efold(left);
		n->left = left;
		if(left->ty == tstring && left->op == Oconst)
			n = mkconst(&n->src, utflen(left->decl->sym->name));
		break;
	case Oslice:
		if(right->left->op == Onothing)
			right->left = mkconst(&right->left->src, 0);
		n->left = efold(left);
		n->right = efold(right);
		break;
	case Oinds:
		n->left = left = efold(left);
		n->right = right = efold(right);
		if(right->op == Oconst && left->op == Oconst){
			;
		}
		break;
	case Ocast:
		n->op = Ocast;
		left = efold(left);
		n->left = left;
		if(n->ty == left->ty)
			return left;
		if(left->op == Oconst)
			return foldcast(n, left);
		break;
	case Odot:
	case Omdot:
		/*
		 * what about side effects from left?
		 */
		d = right->decl;
		switch(d->store){
		case Dconst:
		case Dtag:
		case Dtype:
			/*
			 * set it up as a name and let that case do the hard work
			 */
			n->op = Oname;
			n->decl = d;
			n->left = nil;
			n->right = nil;
			return efold(n);
		}
		n->left = efold(left);
		if(n->left->op == Otuple)
			n = tuplemem(n->left, d);
		else
			n->right = efold(right);
		break;
	case Otagof:
		if(n->decl != nil){
			n->op = Oconst;
			n->left = nil;
			n->right = nil;
			n->val = n->decl->tag;			
			return efold(n);
		}
		n->left = efold(left);
		break;
	default:
		n->left = efold(left);
		n->right = efold(right);
		break;
	}

	left = n->left;
	right = n->right;
	if(left == nil)
		return n;

	if(right == nil){
		if(left->op == Oconst){
			if(left->ty == tint || left->ty == tbyte || left->ty == tbig)
				return foldc(n);
			if(left->ty == treal)
				return foldr(n);
		}
		return n;
	}

	if(left->op == Oconst){
		switch(n->op){
		case Ooror:
			if(left->ty == tint || left->ty == tbyte || left->ty == tbig){
				if(left->val == 0){
					n = mkbin(Oneq, right, mkconst(&right->src, 0));
					n->ty = right->ty;
					n->left->ty = right->ty;
					return efold(n);
				}
				if(!hasside(right)){
					left->val = 1;
					return left;
				}
			}
			break;
		case Oandand:
			if(left->ty == tint || left->ty == tbyte || left->ty == tbig){
				if(left->val == 0)
					return left;
				n = mkbin(Oneq, right, mkconst(&right->src, 0));
				n->ty = right->ty;
				n->left->ty = right->ty;
				return efold(n);
			}
			break;
		}
	}
	if(left->op == Oconst && right->op != Oconst
	&& opcommute[n->op]
	&& n->ty != tstring){
		n->op = opcommute[n->op];
		n->left = right;
		n->right = left;
		left = right;
		right = n->right;
	}
	if(right->op == Oconst && left->op == n->op && left->right->op == Oconst
	&& (n->op == Oadd || n->op == Omul || n->op == Oor || n->op == Oxor || n->op == Oand)
	&& n->ty != tstring){
		n->left = left->left;
		left->left = right;
		right = efold(left);
		n->right = right;
		left = n->left;
	}
	if(right->op == Oconst){
		if(right->ty == tint || right->ty == tbyte || left->ty == tbig){
			if(left->op == Oconst)
				return foldc(n);
			return foldvc(n);
		}
		if(right->ty == treal && left->op == Oconst)
			return foldr(n);
	}
	return n;
}

/*
 * does evaluating the node have any side effects?
 */
int
hasside(Node *n)
{
	for(; n != nil; n = n->right){
		if(sideeffect[n->op])
			return 1;
		if(hasside(n->left))
			return 1;
	}
	return 0;
}

Node*
foldcast(Node *n, Node *left)
{
	Real r;
	char *buf, *e;

	switch(left->ty->kind){
	case Tint:
		left->val &= 0xffffffff;
		if(left->val & 0x80000000)
			left->val |= (Long)0xffffffff << 32;
		return foldcasti(n, left);
	case Tbyte:
		left->val &= 0xff;
		return foldcasti(n, left);
	case Tbig:
		return foldcasti(n, left);
	case Treal:
		switch(n->ty->kind){
		case Tint:
		case Tbyte:
		case Tbig:
			r = left->rval;
			left->val = r < 0 ? r - .5 : r + .5;
			break;
		case Tstring:
			buf = allocmem(NumSize);
			e = seprint(buf, buf+NumSize, "%g", left->rval);
			return mksconst(&n->src, enterstring(buf, e-buf));
		default:
			return n;
		}
		break;
	case Tstring:
		switch(n->ty->kind){
		case Tint:
		case Tbyte:
		case Tbig:
			left->val = strtoi(left->decl->sym->name, 10);
			break;
		case Treal:
			left->rval = strtod(left->decl->sym->name, nil);
			break;
		default:
			return n;
		}
		break;
	default:
		return n;
	}
	left->ty = n->ty;
	left->src = n->src;
	return left;
}

/*
 * left is some kind of int type
 */
Node*
foldcasti(Node *n, Node *left)
{
	char *buf, *e;

	switch(n->ty->kind){
	case Tint:
		left->val &= 0xffffffff;
		if(left->val & 0x80000000)
			left->val |= (Long)0xffffffff << 32;
		break;
	case Tbyte:
		left->val &= 0xff;
		break;
	case Tbig:
		break;
	case Treal:
		left->rval = left->val;
		break;
	case Tstring:
		buf = allocmem(NumSize);
		e = seprint(buf, buf+NumSize, "%lld", left->val);
		return mksconst(&n->src, enterstring(buf, e-buf));
	default:
		return n;
	}
	left->ty = n->ty;
	left->src = n->src;
	return left;
}

/*
 * right is a const int
 */
Node*
foldvc(Node *n)
{
	Node *left, *right;

	left = n->left;
	right = n->right;
	switch(n->op){
	case Oadd:
	case Osub:
	case Oor:
	case Oxor:
	case Olsh:
	case Orsh:
	case Ooror:
		if(right->val == 0)
			return left;
		break;
	case Omul:
		if(right->val == 1)
			return left;
		break;
	case Oandand:
		if(right->val != 0)
			return left;
		break;
	case Oneq:
		if(!isrelop[left->op])
			return n;
		if(right->val == 0)
			return left;
		n->op = Onot;
		n->right = nil;
		break;
	case Oeq:
		if(!isrelop[left->op])
			return n;
		if(right->val != 0)
			return left;
		n->op = Onot;
		n->right = nil;
		break;
	}
	return n;
}

/*
 * left and right are const ints
 */
Node*
foldc(Node *n)
{
	Node *left, *right;
	Long lv, v;
	int rv, nb;

	left = n->left;
	right = n->right;
	switch(n->op){
	case Oadd:
		v = left->val + right->val;
		break;
	case Osub:
		v = left->val - right->val;
		break;
	case Omul:
		v = left->val * right->val;
		break;
	case Odiv:
		if(right->val == 0){
			nerror(n, "divide by 0 in constant expression");
			return n;
		}
		v = left->val / right->val;
		break;
	case Omod:
		if(right->val == 0){
			nerror(n, "mod by 0 in constant expression");
			return n;
		}
		v = left->val % right->val;
		break;
	case Oand:
		v = left->val & right->val;
		break;
	case Oor:
		v = left->val | right->val;
		break;
	case Oxor:
		v = left->val ^ right->val;
		break;
	case Olsh:
		lv = left->val;
		rv = right->val;
		if(rv < 0 || rv >= n->ty->size * 8){
			nwarn(n, "shift amount %d out of range", rv);
			rv = 0;
		}
		if(rv == 0){
			v = lv;
			break;
		}
		v = lv << rv;
		break;
	case Orsh:
		lv = left->val;
		rv = right->val;
		nb = n->ty->size * 8;
		if(rv < 0 || rv >= nb){
			nwarn(n, "shift amount %d out of range", rv);
			rv = 0;
		}
		if(rv == 0){
			v = lv;
			break;
		}
		v = lv >> rv;

		/*
		 * properly sign extend c right shifts
		 */
		if((n->ty == tint || n->ty == tbig)
		&& rv != 0
		&& (lv & (1<<(nb-1)))){
			lv = 0;
			lv = ~lv;
			v |= lv << (nb - rv);
		}
		break;
	case Oneg:
		v = -left->val;
		break;
	case Ocomp:
		v = ~left->val;
		break;
	case Oeq:
		v = left->val == right->val;
		break;
	case Oneq:
		v = left->val != right->val;
		break;
	case Ogt:
		v = left->val > right->val;
		break;
	case Ogeq:
		v = left->val >= right->val;
		break;
	case Olt:
		v = left->val < right->val;
		break;
	case Oleq:
		v = left->val <= right->val;
		break;
	case Oandand:
		v = left->val && right->val;
		break;
	case Ooror:
		v = left->val || right->val;
		break;
	case Onot:
		v = !left->val;
		break;
	default:
		return n;
	}
	if(n->ty == tint){
		v &= 0xffffffff;
		if(v & 0x80000000)
			v |= (Long)0xffffffff << 32;
	}else if(n->ty == tbyte)
		v &= 0xff;
	n->left = nil;
	n->right = nil;
	n->decl = nil;
	n->op = Oconst;
	n->val = v;
	return n;
}

/*
 * left and right are const reals
 */
Node*
foldr(Node *n)
{
	Node *left, *right;
	double rv;
	Long v;

	rv = 0.;
	v = 0;

	left = n->left;
	right = n->right;
	switch(n->op){
	case Ocast:
		return n;
	case Oadd:
		rv = left->rval + right->rval;
		break;
	case Osub:
		rv = left->rval - right->rval;
		break;
	case Omul:
		rv = left->rval * right->rval;
		break;
	case Odiv:
		rv = left->rval / right->rval;
		break;
	case Oneg:
		rv = -left->rval;
		break;
	case Oeq:
		v = left->rval == right->rval;
		break;
	case Oneq:
		v = left->rval != right->rval;
		break;
	case Ogt:
		v = left->rval > right->rval;
		break;
	case Ogeq:
		v = left->rval >= right->rval;
		break;
	case Olt:
		v = left->rval < right->rval;
		break;
	case Oleq:
		v = left->rval <= right->rval;
		break;
	default:
		return n;
	}
	n->left = nil;
	n->right = nil;

	if(isnan(rv))
		rv = canonnan;

	n->rval = rv;
	n->val = v;

	n->op = Oconst;
	return n;
}

Node*
varinit(Decl *d, Node *e)
{
	Node *n;

	n = mkdeclname(&e->src, d);
	if(d->next == nil)
		return mkbin(Oas, n, e);
	return mkbin(Oas, n, varinit(d->next, e));
}

/*
 * given: an Oseq list with left == next or the last child
 * make a list with the right == next
 * ie: Oseq(Oseq(a, b),c) ==> Oseq(a, Oseq(b, Oseq(c, nil))))
 */
Node*
rotater(Node *e)
{
	Node *left;

	if(e == nil)
		return e;
	if(e->op != Oseq)
		return mkunary(Oseq, e);
	e->right = mkunary(Oseq, e->right);
	while(e->left->op == Oseq){
		left = e->left;
		e->left = left->right;
		left->right = e;
		e = left;
	}
	return e;
}

/*
 * reverse the case labels list
 */
Node*
caselist(Node *s, Node *nr)
{
	Node *r;

	r = s->right;
	s->right = nr;
	if(r == nil)
		return s;
	return caselist(r, s);
}

/*
 * e is a seq of expressions; make into cons's to build a list
 */
Node*
etolist(Node *e)
{
	Node *left, *n;

	if(e == nil)
		return nil;
	n = mknil(&e->src);
	n->src.start = n->src.stop;
	if(e->op != Oseq)
		return mkbin(Ocons, e, n);
	e->right = mkbin(Ocons, e->right, n);
	while(e->left->op == Oseq){
		e->op = Ocons;
		left = e->left;
		e->left = left->right;
		left->right = e;
		e = left;
	}
	e->op = Ocons;
	return e;
}

Node*
dupn(int resrc, Src *src, Node *n)
{
	Node *nn;

	nn = allocmem(sizeof *nn);
	*nn = *n;
	if(resrc)
		nn->src = *src;
	if(nn->left != nil)
		nn->left = dupn(resrc, src, nn->left);
	if(nn->right != nil)
		nn->right = dupn(resrc, src, nn->right);
	return nn;
}

Node*
mkn(int op, Node *left, Node *right)
{
	Node *n;

	n = allocmem(sizeof *n);
	*n = znode;
	n->op = op;
	n->left = left;
	n->right = right;
	return n;
}

Node*
mkunary(int op, Node *left)
{
	Node *n;

	n = mkn(op, left, nil);
	n->src = left->src;
	return n;
}

Node*
mkbin(int op, Node *left, Node *right)
{
	Node *n;

	n = mkn(op, left, right);
	n->src.start = left->src.start;
	n->src.stop = right->src.stop;
	return n;
}

Node*
mkdeclname(Src *src, Decl *d)
{
	Node *n;

	n = mkn(Oname, nil, nil);
	n->src = *src;
	n->decl = d;
	n->ty = d->ty;
	d->refs++;
	return n;
}

Node*
mknil(Src *src)
{
	return mkdeclname(src, nildecl);
}

Node*
mkname(Src *src, Sym *s)
{
	Node *n;

	n = mkn(Oname, nil, nil);
	n->src = *src;
	if(s->unbound == nil){
		s->unbound = mkdecl(src, Dunbound, nil);
		s->unbound->sym = s;
	}
	n->decl = s->unbound;
	return n;
}

Node*
mkconst(Src *src, Long v)
{
	Node *n;

	n = mkn(Oconst, nil, nil);
	n->ty = tint;
	n->val = v;
	n->src = *src;
	return n;
}

Node*
mkrconst(Src *src, Real v)
{
	Node *n;

	n = mkn(Oconst, nil, nil);
	n->ty = treal;
	n->rval = v;
	n->src = *src;
	return n;
}

Node*
mksconst(Src *src, Sym *s)
{
	Node *n;

	n = mkn(Oconst, nil, nil);
	n->ty = tstring;
	n->decl = mkdecl(src, Dconst, tstring);
	n->decl->sym = s;
	n->src = *src;
	return n;
}

int
opconv(Fmt *f)
{
	int op;
	char buf[32];

	op = va_arg(f->args, int);
	if(op < 0 || op > Oend) {
		seprint(buf, buf+sizeof(buf), "op %d", op);
		return fmtstrcpy(f, buf);
	}
	return fmtstrcpy(f, opname[op]);
}

int
etconv(Fmt *f)
{
	Node *n;
	char buf[1024];

	n = va_arg(f->args, Node*);
	if(n->ty == tany || n->ty == tnone || n->ty == terror)
		seprint(buf, buf+sizeof(buf), "%V", n);
	else
		seprint(buf, buf+sizeof(buf), "%V of type %T", n, n->ty);
	return fmtstrcpy(f, buf);
}

int
expconv(Fmt *f)
{
	Node *n;
	char buf[4096], *p;

	n = va_arg(f->args, Node*);
	p = buf;
	*p = 0;
	if(f->r == 'V')
		*p++ = '\'';
	p = eprint(p, buf+sizeof(buf)-1, n);
	if(f->r == 'V')
		*p++ = '\'';
	*p = 0;
	return fmtstrcpy(f, buf);
}

char*
eprint(char *buf, char *end, Node *n)
{
	if(n == nil)
		return buf;
	if(n->parens)
		buf = secpy(buf, end, "(");
	switch(n->op){
	case Obreak:
	case Ocont:
		buf = secpy(buf, end, opname[n->op]);
		if(n->decl != nil){
			buf = seprint(buf, end, " %s", n->decl->sym->name);
		}
		break;
	case Oexit:
	case Owild:
		buf = secpy(buf, end, opname[n->op]);
		break;
	case Onothing:
		break;
	case Oadr:
	case Oused:
		buf = eprint(buf, end, n->left);
		break;
	case Oseq:
		buf = eprintlist(buf, end, n, ", ");
		break;
	case Oname:
		if(n->decl == nil)
			buf = secpy(buf, end, "<nil>");
		else
			buf = seprint(buf, end, "%s", n->decl->sym->name);
		break;
	case Oconst:
		if(n->ty->kind == Tstring){
			buf = stringpr(buf, end, n->decl->sym);
			break;
		}
		if(n->decl != nil && n->decl->sym != nil){
			buf = seprint(buf, end, "%s", n->decl->sym->name);
			break;
		}
		switch(n->ty->kind){
		case Tint:
		case Tbyte:
			buf = seprint(buf, end, "%ld", (long)n->val);
			break;
		case Tbig:
			buf = seprint(buf, end, "%lld", n->val);
			break;
		case Treal:
			buf = seprint(buf, end, "%g", n->rval);
			break;
		default:
			buf = secpy(buf, end, opname[n->op]);
			break;
		}
		break;
	case Ocast:
		buf = seprint(buf, end, "%T ", n->ty);
		buf = eprint(buf, end, n->left);
		break;
	case Otuple:
		if(n->ty != nil && n->ty->kind == Tadt)
			buf = seprint(buf, end, "%s", n->ty->decl->sym->name);
		buf = seprint(buf, end, "(");
		buf = eprintlist(buf, end, n->left, ", ");
		buf = secpy(buf, end, ")");
		break;
	case Ochan:
		if(n->left){
			buf = secpy(buf, end, "chan [");
			buf = eprint(buf, end, n->left);
			buf = secpy(buf, end, "] of ");
			buf = seprint(buf, end, "%T", n->ty->tof);
		}else
			buf = seprint(buf, end, "chan of %T", n->ty->tof);
		break;
	case Oarray:
		buf = secpy(buf, end, "array [");
		if(n->left != nil)
			buf = eprint(buf, end, n->left);
		buf = secpy(buf, end, "] of ");
		if(n->right != nil){
			buf = secpy(buf, end, "{");
			buf = eprintlist(buf, end, n->right, ", ");
			buf = secpy(buf, end, "}");
		}else{
			buf = seprint(buf, end, "%T", n->ty->tof);
		}
		break;
	case Oelem:
	case Olabel:
		if(n->left != nil){
			buf = eprintlist(buf, end, n->left, " or ");
			buf = secpy(buf, end, " =>");
		}
		buf = eprint(buf, end, n->right);
		break;
	case Orange:
		buf = eprint(buf, end, n->left);
		buf = secpy(buf, end, " to ");
		buf = eprint(buf, end, n->right);
		break;
	case Ospawn:
		buf = secpy(buf, end, "spawn ");
		buf = eprint(buf, end, n->left);
		break;
	case Ocall:
		buf = eprint(buf, end, n->left);
		buf = secpy(buf, end, "(");
		buf = eprintlist(buf, end, n->right, ", ");
		buf = secpy(buf, end, ")");
		break;
	case Oinc:
	case Odec:
		buf = eprint(buf, end, n->left);
		buf = secpy(buf, end, opname[n->op]);
		break;
	case Oindex:
	case Oindx:
	case Oinds:
		buf = eprint(buf, end, n->left);
		buf = secpy(buf, end, "[");
		buf = eprint(buf, end, n->right);
		buf = secpy(buf, end, "]");
		break;
	case Oslice:
		buf = eprint(buf, end, n->left);
		buf = secpy(buf, end, "[");
		buf = eprint(buf, end, n->right->left);
		buf = secpy(buf, end, ":");
		buf = eprint(buf, end, n->right->right);
		buf = secpy(buf, end, "]");
		break;
	case Oload:
		buf = seprint(buf, end, "load %T ", n->ty);
		buf = eprint(buf, end, n->left);
		break;
	case Oref:
	case Olen:
	case Ohd:
	case Otl:
	case Otagof:
		buf = secpy(buf, end, opname[n->op]);
		buf = secpy(buf, end, " ");
		buf = eprint(buf, end, n->left);
		break;
	default:
		if(n->right == nil){
			buf = secpy(buf, end, opname[n->op]);
			buf = eprint(buf, end, n->left);
		}else{
			buf = eprint(buf, end, n->left);
			buf = secpy(buf, end, opname[n->op]);
			buf = eprint(buf, end, n->right);
		}
		break;
	}
	if(n->parens)
		buf = secpy(buf, end, ")");
	return buf;
}

char*
eprintlist(char *buf, char *end, Node *elist, char *sep)
{
	if(elist == nil)
		return buf;
	for(; elist->right != nil; elist = elist->right){
		if(elist->op == Onothing)
			continue;
		buf = eprint(buf, end, elist->left);
		buf = secpy(buf, end, sep);
	}
	buf = eprint(buf, end, elist->left);
	return buf;
}

int
nodeconv(Fmt *f)
{
	Node *n;
	char buf[4096];

	n = va_arg(f->args, Node*);
	buf[0] = 0;
	nprint(buf, buf+sizeof(buf), n, 0);
	return fmtstrcpy(f, buf);
}

char*
nprint(char *buf, char *end, Node *n, int indent)
{
	int i;

	if(n == nil)
		return buf;
	buf = seprint(buf, end, "\n");
	for(i = 0; i < indent; i++)
		if(buf < end-1)
			*buf++ = ' ';
	switch(n->op){
	case Oname:
		if(n->decl == nil)
			buf = secpy(buf, end, "<nil>");
		else
			buf = seprint(buf, end, "%s", n->decl->sym->name);
		break;
	case Oconst:
		if(n->decl != nil && n->decl->sym != nil)
			buf = seprint(buf, end, "%s", n->decl->sym->name);
		else
			buf = seprint(buf, end, "%O", n->op);
		if(n->ty == tint || n->ty == tbyte || n->ty == tbig)
			buf = seprint(buf, end, " (%ld)", (long)n->val);
		break;
	default:
		buf = seprint(buf, end, "%O", n->op);
		break;
	}
	buf = seprint(buf, end, " %T %d %d", n->ty, n->addable, n->temps);
	indent += 2;
	buf = nprint(buf, end, n->left, indent);
	buf = nprint(buf, end, n->right, indent);
	return buf;
}
