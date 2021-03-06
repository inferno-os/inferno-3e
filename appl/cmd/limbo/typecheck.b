fndecls:	ref Decl;
labstack:	array of ref Node;
maxlabdep:	int;

typecheck(checkimp: int): ref Decl
{
	entry, d, m: ref Decl;

	if(errors)
		return nil;

	#
	# generate the set of all functions
	# compile one function at a time
	#
	gdecl(tree);
	gbind(tree);
	fns = array[nfns] of ref Decl;
	i := gcheck(tree, fns, 0);
	if(i != nfns)
		fatal("wrong number of functions found in gcheck");
	tree = nil;

	maxlabdep = 0;
	for(i = 0; i < nfns; i++){
		d = fns[i];
		if(d != nil)
			fncheck(d);
	}

	if(errors)
		return nil;

	entry = nil;
	if(checkimp){
		if(impmod == nil){
			yyerror("no implementation module");
			return nil;
		}
		if(impdecl == nil || impdecl.ty == nil){
			yyerror("no definition for implementation module "+impmod.name);
			return nil;
		}

		#
		# can't check the module spec until all types and imports are determined,
		# which happens in scheck
		#
		impdecl.ty = usetype(impdecl.ty);
		if(impdecl.store != Dtype || impdecl.ty.kind != Tmodule){
			error(impdecl.src.start, "cannot implement "+declconv(impdecl));
			return nil;
		}
	
		s := enter("init", 0);
		impdecl.refs++;
		for(m = impdecl.ty.ids; m != nil; m = m.next){
			m.ty = usetype(m.ty);
			m.refs++;
	
			if(m.sym == s && m.ty.kind == Tfn)
				entry = m;
	
			if(m.store == Dglobal || m.store == Dfn)
				modrefable(m.ty);
	
			if(m.store == Dtype && m.ty.kind == Tadt){
				for(d = m.ty.ids; d != nil; d = d.next){
					d.ty = usetype(d.ty);
					modrefable(d.ty);
					d.refs++;
				}
			}
		}
		checkrefs(impdecl.ty.ids);
	}
	if(errors)
		return nil;

	return entry;
}
#
# introduce all global declarations
# also adds all fields to adts and modules
# note the complications due to nested Odas expressions
#
gdecl(n: ref Node)
{
	for(;;){
		if(n == nil)
			return;
		if(n.op != Oseq)
			break;
		gdecl(n.left);
		n = n.right;
	}
	case n.op{
	Oimport =>
		importdecled(n);
		gdasdecl(n.right);
	Oadtdecl =>
		adtdecled(n);
	Ocondecl =>
		condecled(n);
		gdasdecl(n.right);
	Omoddecl =>
		moddecled(n);
	Otypedecl =>
		typedecled(n);
	Ovardecl =>
		vardecled(n);
	Ovardecli =>
		vardecled(n.left);
		gdasdecl(n.right);
	Ofunc =>
		fndecled(n);
	Oas or
	Odas or
	Onothing =>
		gdasdecl(n);
	* =>
		fatal("can't deal with "+opconv(n.op)+" in gdecl");
	}
}

#
# bind all global type ids,
# including those nested inside modules
# this needs to be done, since we may use such
# a type later in a nested scope, so if we bound
# the type ids then, the type could get bound
# to a nested declaration
#
gbind(n: ref Node)
{
	ids: ref Decl;

	for(;;){
		if(n == nil)
			return;
		if(n.op != Oseq)
			break;
		gbind(n.left);
		n = n.right;
	}
	case n.op{
	Oas or
	Ocondecl or
	Odas or
	Ofunc or
	Oimport or
	Onothing or
	Ovardecl or
	Ovardecli =>
		break;
	Ofielddecl or
	Otypedecl =>
		bindtypes(n.decl.ty);
	Opickdecl =>
		gbind(n.left);
		d := n.right.left.decl;
		bindtypes(d.ty);
		repushids(d.ty.ids);
		gbind(n.right.right);
		# get new ids for undefined types; propagate outwards
		ids = popids(d.ty.ids);
		if(ids != nil)
			installids(Dundef, ids);
	Oadtdecl or
	Omoddecl =>
		bindtypes(n.ty);
		repushids(n.ty.ids);
		gbind(n.left);
		# get new ids for undefined types; propagate outwards
		ids = popids(n.ty.ids);
		if(ids != nil)
			installids(Dundef, ids);
	* =>
		fatal("can't deal with "+opconv(n.op)+" in gbind");
	}
}

#
# check all of the global declarations
# bind all type ids referred to within types at the global level
# record decls for defined functions
#
gcheck(n: ref Node, fns: array of ref Decl, nfns: int): int
{
	ok, allok: int;

	for(;;){
		if(n == nil)
			return nfns;
		if(n.op != Oseq)
			break;
		nfns = gcheck(n.left, fns, nfns);
		n = n.right;
	}

	case n.op{
	Ofielddecl or
	Onothing or
	Opickdecl or
	Otypedecl =>
		break;
	Oadtdecl or
	Omoddecl =>
		repushids(n.ty.ids);
		if(gcheck(n.left, nil, 0))
			fatal("gcheck fn decls nested in modules or adts");
		if(popids(n.ty.ids) != nil)
			fatal("gcheck installs new ids in a module or adt");
	Ovardecl =>
		varcheck(n, 1);
	Ocondecl =>
		concheck(n, 1);
	Oimport =>
		importcheck(n, 1);
	Ovardecli =>
		varcheck(n.left, 1);
		(ok, allok) = echeck(n.right, 0, 1);
		if(ok){
			if(allok)
				n.right = fold(n.right);
			globalas(n.right.left, n.right.right, allok);
		}
	Oas or
	Odas =>
		(ok, allok) = echeck(n, 0, 1);
		if(ok){
			if(allok)
				n = fold(n);
			globalas(n.left, n.right, allok);
		}
	Ofunc =>
		(ok, allok) = echeck(n.left, 0, 1);
		d : ref Decl = nil;
		if(ok)
			d = fnchk(n);
		fns[nfns++] = d;
	* =>
		fatal("can't deal with "+opconv(n.op)+" in gcheck");
	}
	return nfns;
}

#
# check for unused expression results
# make sure the any calculated expression has
# a destination
#
checkused(n: ref Node): ref Node
{
	#
	# only nil; and nil = nil; should have type tany
	#
	if(n.ty == tany){
		if(n.op == Oname)
			return n;
		if(n.op == Oas)
			return checkused(n.right);
		fatal("line "+lineconv(n.src.start)+" checkused "+nodeconv(n));
	}

	if(isused[n.op] && (n.op != Ocall || n.left.ty.kind == Tfn))
		return n;
	t := n.ty;
	if(t.kind == Tfn)
		nerror(n, "function "+expconv(n)+" not called");
	else if(t.kind == Tadt && t.tags != nil || t.kind == Tadtpick)
		nerror(n, "expressions cannot have type "+typeconv(t));
	else
		nwarn(n, "result of expression "+expconv(n)+" not used");
	n = mkunary(Oused, n);
	n.ty = n.left.ty;
	return n;
}

fncheck(d: ref Decl)
{
	n := d.init;
	if(debug['t'])
		print("typecheck tree: %s\n", nodeconv(n));

	fndecls = nil;
	repushids(d.ty.ids);

	labdep = 0;
	labstack = array[maxlabdep] of ref Node;
	n.right = scheck(n.right, d.ty.tof, Sother);
	if(labdep != 0)
		fatal("unbalanced label stack in fncheck");
	labstack = nil;

	d.locals = appdecls(popids(d.ty.ids), fndecls);
	fndecls = nil;

	checkrefs(d.ty.ids);
	checkrefs(d.locals);
}

scheck(n: ref Node, ret: ref Type, kind : int): ref Node
{
	s: ref Sym;
	rok: int;
	
	top := n;
	last: ref Node = nil;
	for(; n != nil; n = n.right){
		left := n.left;
		right := n.right;
		case n.op{
		Ovardecl =>
			vardecled(n);
			varcheck(n, 0);
			if (zeroptrs && nested() && tmustzero(n.decl.ty))
				decltozero(n);
#			else if (zeroptrs && inloop() && tmustzero(n.decl.ty))
#				decltozero(n);
			return top;
		Ovardecli =>
			vardecled(left);
			varcheck(left, 0);
			echeck(right, 0, 0);
			if (zeroptrs && nested() && tmustzero(left.decl.ty))
				decltozero(left);
			return top;
		Otypedecl =>
			typedecled(n);
			bindtypes(n.ty);
			return top;
		Ocondecl =>
			condecled(n);
			concheck(n, 0);
			return top;
		Oimport =>
			importdecled(n);
			importcheck(n, 0);
			return top;
		Ofunc =>
			fatal("scheck func");
		Oscope =>
			if (kind == Sother)
				kind = Sscope;
			pushscope(n, kind);
			if (left != nil)
				fatal("Oscope has left field");
			echeck(left, 0, 0);
			n.right = scheck(right, ret, Sother);
			d := popscope();
			fndecls = appdecls(fndecls, d);
			return top;
		Olabel =>
			echeck(left, 0, 0);
			n.right = scheck(right, ret, Sother);
			return top;
		Oseq =>
			n.left = scheck(left, ret, Sother);
			# next time will check n.right
		Oif =>
			(rok, nil) = echeck(left, 0, 0);
			if(rok && left.op != Onothing && left.ty != tint)
				nerror(n, "if conditional must be an int, not "+etconv(left));
			right.left = scheck(right.left, ret, Sother);
			# next time will check n.right.right
			n = right;
		Ofor =>
			(rok, nil) = echeck(left, 0, 0);
			if(rok && left.op != Onothing && left.ty != tint)
				nerror(n, "for conditional must be an int, not "+etconv(left));
			#
			# do the continue clause before the body
			# this reflects the ordering of declarations
			#
			pushlabel(n);
			right.right = scheck(right.right, ret, Sother);
			right.left = scheck(right.left, ret, Sloop);
			labdep--;
			if(n.decl != nil && !n.decl.refs)
				nwarn(n, "label "+n.decl.sym.name+" never referenced");
			return top;
		Odo =>
			(rok, nil) = echeck(left, 0, 0);
			if(rok && left.op != Onothing && left.ty != tint)
				nerror(n, "do conditional must be an int, not "+etconv(left));
			pushlabel(n);
			n.right = scheck(n.right, ret, Sloop);
			labdep--;
			if(n.decl != nil && !n.decl.refs)
				nwarn(n, "label "+n.decl.sym.name+" never referenced");
			return top;
		Oalt or
		Ocase or
		Opick =>
			pushlabel(n);
			case n.op{
			Oalt =>
				altcheck(n, ret);
			Ocase =>
				casecheck(n, ret);
			Opick =>
				pickcheck(n, ret);
			}
			labdep--;
			if(n.decl != nil && !n.decl.refs)
				nwarn(n, "label "+n.decl.sym.name+" never referenced");
			return top;
		Oret =>
			(rok, nil) = echeck(left, 0, 0);
			if(!rok)
				return top;
			if(left == nil){
				if(ret != tnone)
					nerror(n, "return of nothing from a fn of "+typeconv(ret));
			}else if(ret == tnone){
				if(left.ty != tnone)
					nerror(n, "return "+etconv(left)+" from a fn with no return type");
			}else if(!tcompat(ret, left.ty, 0))
				nerror(n, "return "+etconv(left)+" from a fn of "+typeconv(ret));
			return top;
		Obreak or
		Ocont =>
			s = nil;
			if(n.decl != nil)
				s = n.decl.sym;
			for(i := 0; i < labdep; i++){
				if(s == nil || labstack[i].decl != nil && labstack[i].decl.sym == s){
					if(n.op == Ocont
					&& labstack[i].op != Ofor && labstack[i].op != Odo)
						continue;
					if(s != nil)
						labstack[i].decl.refs++;
					return top;
				}
			}
			nerror(n, "no appropriate target for "+expconv(n));
			return top;
		Oexit or
		Onothing =>
			return top;
		* =>
			(nil, rok) = echeck(n, 0, 0);
			if(rok)
				n = checkused(n);
			if(last == nil)
				return n;
			last.right = n;
			return top;
		}
		last = n;
	}
	return top;
}

pushlabel(n: ref Node)
{
	s: ref Sym;

	if(labdep >= maxlabdep){
		maxlabdep += MaxScope;
		labs := array[maxlabdep] of ref Node;
		labs[:] = labstack;
		labstack = labs;
	}
	if(n.decl != nil){
		s = n.decl.sym;
		n.decl.refs = 0;
		for(i := 0; i < labdep; i++)
			if(labstack[i].decl != nil && labstack[i].decl.sym == s)
				nerror(n, "label " + s.name + " duplicated on line " + lineconv(labstack[i].decl.src.start));
	}
	labstack[labdep++] = n;
}

varcheck(n: ref Node, isglobal: int)
{
	t := validtype(n.ty, nil);
	t = topvartype(t, n.decl, isglobal);
	last := n.left.decl;
	for(ids := n.decl; ids != last.next; ids = ids.next)
		ids.ty = t;
}

concheck(n: ref Node, isglobal: int)
{
	t: ref Type;
	init: ref Node;

	pushscope(nil, Sother);
	installids(Dconst, iota);
	(ok, allok) := echeck(n.right, 0, isglobal);
	popscope();

	init = n.right;
	if(!ok){
		t = terror;
	}else{
		t = init.ty;
		if(!tattr[t.kind].conable){
			nerror(init, "cannot have a "+typeconv(t)+" constant");
			allok = 0;
		}
	}

	last := n.left.decl;
	for(ids := n.decl; ids != last.next; ids = ids.next)
		ids.ty = t;

	if(!allok)
		return;

	i := 0;
	for(ids = n.decl; ids != last.next; ids = ids.next){
		if(ok){
			iota.init.c.val = big i;
			ids.init = dupn(0, nosrc, init);
			if(!varcom(ids))
				ok = 0;
		}
		i++;
	}
}

importcheck(n: ref Node, isglobal: int)
{
	(ok, nil) := echeck(n.right, 1, isglobal);
	if(!ok)
		return;

	m := n.right;
	if(m.ty.kind != Tmodule || m.op != Oname){
		nerror(n, "cannot import from "+etconv(m));
		return;
	}

	last := n.left.decl;
	for(id := n.decl; id != last.next; id = id.next){
		v := namedot(m.ty.ids, id.sym);
		if(v == nil){
			error(id.src.start, id.sym.name+" is not a member of "+expconv(m));
			id.store = Dwundef;
			continue;
		}
		id.store = v.store;
		v.ty = validtype(v.ty, nil);
		id.ty = t := v.ty;
		if(id.store == Dtype && t.decl != nil){
			id.timport = t.decl.timport;
			t.decl.timport = id;
		}
		id.init = v.init;
		id.importid = v;
		id.eimport = m;
	}
}

#
# annotate the expression with types
#
echeck(n: ref Node, typeok, isglobal: int): (int, int)
{
	tg, id, callee: ref Decl;
	t, tt: ref Type;
	ok, allok, max, nocheck, kidsok: int;

	ok = allok = 1;
	if(n == nil)
		return (1, 1);

	if(n.op == Oseq){
		for( ; n != nil && n.op == Oseq; n = n.right){
			(okl, allokl) := echeck(n.left, 0, isglobal);
			ok &= okl;
			allok &= allokl;
			n.ty = tnone;
		}
		if(n == nil)
			return (ok, allok);
	}

	left := n.left;
	right := n.right;

	nocheck = 0;
	if(n.op == Odot || n.op == Omdot || n.op == Ocall || n.op == Oref || n.op == Otagof)
		nocheck = 1;
	if(n.op != Odas			# special case
	&& n.op != Oload)		# can have better error recovery
		(ok, allok) = echeck(left, nocheck, isglobal);
	if(n.op != Odas			# special case
	&& n.op != Odot			# special check
	&& n.op != Omdot		# special check
	&& n.op != Ocall		# can have better error recovery
	&& n.op != Oindex){
		(okr, allokr) := echeck(right, 0, isglobal);
		ok &= okr;
		allok &= allokr;
	}
	if(!ok){
		n.ty = terror;
		return (0, 0);
	}

	case n.op{
	Odas =>
		(ok, allok) = echeck(right, 0, isglobal);
		if(!ok)
			right.ty = terror;
		if(!isglobal && !dasdecl(left)){
			ok = 0;
		}else if(!specific(right.ty) || !declasinfer(left, right.ty)){
			nerror(n, "cannot declare "+expconv(left)+" from "+etconv(right));
			declaserr(left);
			ok = 0;
		}
		left.ty = right.ty;
		n.ty = right.ty;
		usedty(n.ty);
		if (zeroptrs && nested() && tmustzero(left.ty))
			decltozero(left);
		return (ok, allok & ok);
	Oseq or
	Onothing =>
		n.ty = tnone;
	Owild =>
		n.ty = tint;
	Ocast =>
		t = usetype(n.ty);
		n.ty = t;
		tt = left.ty;
		if(tcompat(tt, t, 0)){
			left.ty = t;
			break;
		}
		if(tt.kind == Tarray){
			if(tt.tof == tbyte && t == tstring)
				break;
		}else if(t.kind == Tarray){
			if(t.tof == tbyte && tt == tstring)
				break;
		}else if(casttab[tt.kind][t.kind]){
			break;
		}
		nerror(n, "cannot make a "+typeconv(n.ty)+" from "+etconv(left));
		return (0, 0);
	Ochan =>
		n.ty = usetype(n.ty);
		if(left != nil && left.ty.kind != Tint){
			nerror(n, "channel size "+etconv(left)+" is not an int");
			return (0, 0);
		}
	Oload =>
		n.ty = usetype(n.ty);
		(nil, kidsok) = echeck(left, 0, isglobal);
		if(n.ty.kind != Tmodule){
			nerror(n, "cannot load a "+typeconv(n.ty));
			return (0, 0);
		}
		if(!kidsok){
			allok = 0;
			break;
		}
		if(left.ty != tstring){
			nerror(n, "cannot load a module from "+etconv(left));
			allok = 0;
			break;
		}
if(n.ty.tof.decl.refs != 0)
n.ty.tof.decl.refs++;
n.ty.decl.refs++;
		usetype(n.ty.tof);
	Oref =>
		t = left.ty;
		if(t.kind != Tadt && t.kind != Tadtpick && t.kind != Tfn && t.kind != Ttuple){
			nerror(n, "cannot make a ref from "+etconv(left));
			return (0, 0);
		}
		if(t.kind == Tadt && t.tags != nil && valistype(left)){
			nerror(n, "instances of ref "+expconv(left)+" must be qualified with a pick tag");
			return (0, 0);
		}
		if(t.kind == Tadtpick)
			t.tof = usetype(t.tof);
		n.ty = usetype(mktype(n.src.start, n.src.stop, Tref, t, nil));
	Oarray =>
		max = 0;
		if(right != nil){
			max = assignindices(n);
			if(max < 0)
				return (0, 0);
			if(!specific(right.left.ty)){
				nerror(n, "type for array not specific");
				return (0, 0);
			}
			n.ty = mktype(n.src.start, n.src.stop, Tarray, right.left.ty, nil);
		}
		n.ty = usetype(n.ty);

		if(left.op == Onothing)
			n.left = left = mkconst(n.left.src, big max);

		if(left.ty.kind != Tint){
			nerror(n, "array size "+etconv(left)+" is not an int");
			return (0, 0);
		}
	Oelem =>
		n.ty = right.ty;
	Orange =>
		if(left.ty != right.ty
		|| left.ty != tint && left.ty != tstring){
			nerror(left, "range "+etconv(left)+" to "+etconv(right)+" is not an int or string range");
			return (0, 0);
		}
		n.ty = left.ty;
	Oname =>
		id = n.decl;
		if(id == nil){
			nerror(n, "name with no declaration");
			return (0, 0);
		}
		if(id.store == Dunbound){
			s := id.sym;
			id = s.decl;
			if(id == nil)
				id = undefed(n.src, s);
			# save a little space
			s.unbound = nil;
			n.decl = id;
			id.refs++;
		}
		n.ty = id.ty = usetype(id.ty);
		case id.store{
		Dfn or
		Dglobal or
		Darg or
		Dlocal or
		Dimport or
		Dfield or
		Dtag =>
			break;
		Dunbound =>
			fatal("unbound symbol found in echeck");
		Dundef =>
			nerror(n, id.sym.name+" is not declared");
			id.store = Dwundef;
			return (0, 0);
		Dwundef =>
			return (0, 0);
		Dconst =>
			if(id.init == nil){
				nerror(n, id.sym.name+"'s value cannot be determined");
				id.store = Dwundef;
				return (0, 0);
			}
		Dtype =>
			if(typeok)
				break;
			nerror(n, declconv(id)+" is not a variable");
			return (0, 0);
		* =>
			fatal("echeck: unknown symbol storage");
		}
		
		if(n.ty == nil){
			nerror(n, declconv(id)+"'s type is not fully defined");
			id.store = Dwundef;
			return (0, 0);
		}
		if(id.importid != nil && valistype(id.eimport)
		&& id.store != Dconst && id.store != Dtype && id.store != Dfn){
			nerror(n, "cannot use "+expconv(n)+" because "+expconv(id.eimport)+" is a module interface");
			return (0, 0);
		}
	Oconst =>
		if(n.ty == nil){
			nerror(n, "no type in "+expconv(n));
			return (0, 0);
		}
	Oas =>
		if(!tcompat(left.ty, right.ty, 1)){
			nerror(n, "type clash in "+etconv(left)+" = "+etconv(right));
			return (0, 0);
		}
		t = right.ty;
		if(t == tany)
			t = left.ty;
		n.ty = t;
		left.ty = t;
		if(islval(left))
			break;
		return (0, 0);
	Osnd =>
		if(left.ty.kind != Tchan){
			nerror(n, "cannot send on "+etconv(left));
			return (0, 0);
		}
		if(!tcompat(left.ty.tof, right.ty, 0)){
			nerror(n, "type clash in "+etconv(left)+" <-= "+etconv(right));
			return (0, 0);
		}
		t = right.ty;
		if(t == tany)
			t = left.ty.tof;
		n.ty = t;
	Orcv =>
		t = left.ty;
		if(t.kind == Tarray)
			t = t.tof;
		if(t.kind != Tchan){
			nerror(n, "cannot receive on "+etconv(left));
			return (0, 0);
		}
		if(left.ty.kind == Tarray)
			n.ty = usetype(mktype(n.src.start, n.src.stop, Ttuple, nil,
					mkids(n.src, nil, tint, mkids(n.src, nil, t.tof, nil))));
		else
			n.ty = t.tof;
	Ocons =>
		if(right.ty.kind != Tlist && right.ty != tany){
			nerror(n, "cannot :: to "+etconv(right));
			return (0, 0);
		}
		n.ty = right.ty;
		if(right.ty == tany)
			n.ty = usetype(mktype(n.src.start, n.src.stop, Tlist, left.ty, nil));
		else if(!tcompat(right.ty.tof, left.ty, 0)){
			t = tparent(right.ty.tof, left.ty);
			if(!tcompat(t, left.ty, 0)){
				nerror(n, "type clash in "+etconv(left)+" :: "+etconv(right));
				return (0, 0);
			}
			else
				n.ty = usetype(mktype(n.src.start, n.src.stop, Tlist, t, nil));
		}
	Ohd or
	Otl =>
		if(left.ty.kind != Tlist || left.ty.tof == nil){
			nerror(n, "cannot "+opconv(n.op)+" "+etconv(left));
			return (0, 0);
		}
		if(n.op == Ohd)
			n.ty = left.ty.tof;
		else
			n.ty = left.ty;
	Otuple =>
		n.ty = usetype(mktype(n.src.start, n.src.stop, Ttuple, nil, tuplefields(left)));
	Ospawn =>
		if(left.op != Ocall || left.left.ty.kind != Tfn){
			nerror(left, "cannot spawn "+expconv(left));
			return (0, 0);
		}
		if(left.ty != tnone){
			nerror(left, "cannot spawn functions which return values, such as "+etconv(left));
			return (0, 0);
		}
	Ocall =>
		(nil, kidsok) = echeck(right, 0, isglobal);
		t = left.ty;
		usedty(t);
		if(t.kind == Tref)
			t = t.tof;
		if(t.kind != Tfn)
			return callcast(n, kidsok, allok);
		n.ty = t.tof;
		if(!kidsok){
			allok = 0;
			break;
		}

		#
		# get the name to call and any associated module
		#
		mod : ref Node = nil;
		id = nil;
		if(left.op == Odot){
			callee = left.right.decl;
			id = callee.dot;
			right = passimplicit(left, right);
			n.right = right;
			tt = left.left.ty;
			if(tt.kind == Tref)
				tt = tt.tof;
			if(tt.decl != nil && tt.decl.timport != nil)
				mod = tt.decl.timport.eimport;

			#
			# stash the import module under a rock,
			# because we won't be able to get it later
			# after scopes are popped
			#
			left.right.left = mod;
		}else if(left.op == Omdot){
			if(left.right.op == Odot){
				callee = left.right.right.decl;
				right = passimplicit(left.right, right);
				n.right = right;
			}else
				callee = left.right.decl;
			mod = left.left;
		}else if(left.op == Oname){
			callee = left.decl;
			id = callee;
			mod = id.eimport;
		}else{
			nerror(left, expconv(left)+" is not a function name");
			allok = 0;
			break;
		}
		if(callee == nil)
			fatal("can't find called function: "+nodeconv(left));
		if(callee.store != Dfn){
			nerror(left, expconv(left)+" is not a function");
			allok = 0;
			break;
		}
		if(mod != nil && mod.ty.kind != Tmodule){
			nerror(left, "cannot call "+expconv(left));
			allok = 0;
			break;
		}
		if(mod != nil){
			if(valistype(mod)){
				nerror(left, "cannot call "+expconv(left)+" because "+expconv(mod)+" is a module interface");
				allok = 0;
				break;
			}
		}else if(id != nil && id.dot != nil && id.dot.sym != impmod){
			nerror(left, "cannot call "+expconv(left)+" without importing "+id.sym.name+" from a variable");
			allok = 0;
			break;
		}
		if(mod != nil)
			modrefable(left.ty);
		if(t.varargs != byte 0){
			t = mkvarargs(left, right);
			if(left.ty.kind == Tref)
				left.ty = usetype(mktype(t.src.start, t.src.stop, Tref, t, nil));
			else
				left.ty = t;
		}else if(!argcompat(n, t.ids, right))
			allok = 0;
	Odot =>
		t = left.ty;
		if(t.kind == Tref)
			t = t.tof;
		case t.kind{
		Tadt or
		Tadtpick or
		Ttuple =>
			id = namedot(t.ids, right.decl.sym);
			if(id == nil){
				id = namedot(t.tags, right.decl.sym);
				if(id != nil && !valistype(left)){
					nerror(n, expconv(left)+" is not a type");
					return (0, 0);
				}
			}
			if(id == nil && t.kind == Tadtpick)
				id = namedot(t.decl.dot.ty.ids, right.decl.sym);
			if(id == nil){
				for(tg = t.tags; tg != nil; tg = tg.next){
					id = namedot(tg.ty.ids, right.decl.sym);
					if(id != nil)
						break;
				}
				if(id != nil){
					nerror(n, "cannot yet index field "+right.decl.sym.name+" of "+etconv(left));
					return (0, 0);
				}
			}
			if(id == nil)
				break;
			if(id.store == Dfield && valistype(left)){
				nerror(n, expconv(left)+" is not a value");
				return (0, 0);
			}
			id.ty = validtype(id.ty, t.decl);
			id.ty = usetype(id.ty);
			break;
		* =>
			nerror(left, etconv(left)+" cannot be qualified with .");
			return (0, 0);
		}
		if(id == nil){
			nerror(n, expconv(right)+" is not a member of "+etconv(left));
			return (0, 0);
		}
		if(id.ty == tunknown){
			nerror(n, "illegal forward reference to "+expconv(n));
			return (0, 0);
		}

		id.refs++;
		right.decl = id;
		n.ty = id.ty;
		if((id.store == Dconst || id.store == Dtag) && hasside(left))
			nwarn(left, "result of expression "+etconv(left)+" ignored");
	Omdot =>
		t = left.ty;
		if(t.kind != Tmodule){
			nerror(left, etconv(left)+" cannot be qualified with ->");
			return (0, 0);
		}
		id = nil;
		if(right.op == Oname){
			id = namedot(t.ids, right.decl.sym);
		}else if(right.op == Odot){
			(ok, kidsok) = echeck(right, 0, isglobal);
			allok &= kidsok;
			if(!ok)
				return (0, 0);
			tt = right.left.ty;
			if(tt.kind == Tref)
				tt = tt.tof;
			if(right.ty.kind == Tfn
			&& tt.kind == Tadt
			&& tt.decl.dot == t.decl)
				id = right.right.decl;
		}
		if(id == nil){
			nerror(n, expconv(right)+" is not a member of "+etconv(left));
			return (0, 0);
		}
		if(id.store != Dconst && id.store != Dtype && id.store != Dtag){
			if(valistype(left)){
				nerror(n, expconv(left)+" is not a value");
				return (0, 0);
			}
		}else if(hasside(left))
			nwarn(left, "result of expression "+etconv(left)+" ignored");
		if(!typeok && id.store == Dtype){
			nerror(n, expconv(n)+" is a type, not a value");
			return (0, 0);
		}
		if(id.ty == tunknown){
			nerror(n, "illegal forward reference to "+expconv(n));
			return (0, 0);
		}
		id.refs++;
		right.decl = id;
		n.ty = id.ty = usetype(id.ty);
		if(id.store == Dglobal)
			modrefable(id.ty);
	Otagof =>
		n.ty = tint;
		t = left.ty;
		if(t.kind == Tref)
			t = t.tof;
		id = nil;
		case left.op{
		Oname =>
			id = left.decl;
		Odot =>
			id = left.right.decl;
		Omdot =>
			if(left.right.op == Odot)
				id = left.right.right.decl;
		}
		if(id != nil && id.store == Dtag
		|| id != nil && id.store == Dtype && t.kind == Tadt && t.tags != nil)
			n.decl = id;
		else if(t.kind == Tadt && t.tags != nil || t.kind == Tadtpick)
			n.decl = nil;
		else{
			nerror(n, "cannot get the tag value for "+etconv(left));
			return (1, 0);
		}
	Oind =>
		t = left.ty;
		if(t.kind != Tref || (t.tof.kind != Tadt && t.tof.kind != Tadtpick && t.tof.kind != Ttuple)){
			nerror(n, "cannot * "+etconv(left));
			return (0, 0);
		}
		n.ty = t.tof;
		for(tg = t.tof.tags; tg != nil; tg = tg.next)
			tg.ty.tof = usetype(tg.ty.tof);
	Oindex =>
		t = left.ty;
		(nil, kidsok) = echeck(right, 0, isglobal);
		if(t.kind != Tarray && t != tstring){
			nerror(n, "cannot index "+etconv(left));
			return (0, 0);
		}
		if(t == tstring){
			n.op = Oinds;
			n.ty = tint;
		}else{
			n.ty = t.tof;
		}
		if(!kidsok){
			allok = 0;
			break;
		}
		if(right.ty != tint){
			nerror(n, "cannot index "+etconv(left)+" with "+etconv(right));
			allok = 0;
			break;
		}
	Oslice =>
		t = n.ty = left.ty;
		if(t.kind != Tarray && t != tstring){
			nerror(n, "cannot slice "+etconv(left)+" with '"+subexpconv(right.left)+":"+subexpconv(right.right)+"'");
			return (0, 0);
		}
		if(right.left.ty != tint && right.left.op != Onothing
		|| right.right.ty != tint && right.right.op != Onothing){
			nerror(n, "cannot slice "+etconv(left)+" with '"+subexpconv(right.left)+":"+subexpconv(right.right)+"'");
			return (1, 0);
		}
	Olen =>
		t = left.ty;
		n.ty = tint;
		if(t.kind != Tarray && t.kind != Tlist && t != tstring){
			nerror(n, "len requires an array, string, or list in "+etconv(left));
			return (1, 0);
		}
	Ocomp or
	Onot or
	Oneg =>
		n.ty = left.ty;
usedty(n.ty);
		case left.ty.kind{
		Tint =>
			return (1, allok);
		Treal =>
			if(n.op == Oneg)
				return (1, allok);
		Tbig or
		Tbyte =>
			if(n.op == Oneg || n.op == Ocomp)
				return (1, allok);
		}
		nerror(n, "cannot apply "+opconv(n.op)+" to "+etconv(left));
		return (0, 0);
	Oinc or
	Odec or
	Opreinc or
	Opredec =>
		n.ty = left.ty;
		case left.ty.kind{
		Tint or
		Tbig or
		Tbyte or
		Treal =>
			break;
		* =>
			nerror(n, "cannot apply "+opconv(n.op)+" to "+etconv(left));
			return (0, 0);
		}
		if(islval(left))
			break;
		return(0, 0);
	Oadd or
	Odiv or
	Omul or
	Osub =>
		if(mathchk(n, 1))
			break;
		return (0, 0);
	Olsh or
	Orsh =>
		if(shiftchk(n))
			break;
		return (0, 0);
	Oandand or
	Ooror =>
		if(left.ty != tint){
			nerror(n, opconv(n.op)+"'s left operand is not an int: "+etconv(left));
			allok = 0;
		}
		if(right.ty != tint){
			nerror(n, opconv(n.op)+"'s right operand is not an int: "+etconv(right));
			allok = 0;
		}
		n.ty = tint;
	Oand or
	Omod or
	Oor or
	Oxor =>
		if(mathchk(n, 0))
			break;
		return (0, 0);
	Oaddas or
	Odivas or
	Omulas or
	Osubas =>
		if(mathchk(n, 1) && islval(left))
			break;
		return (0, 0);
	Olshas or
	Orshas =>
		if(shiftchk(n) && islval(left))
			break;
		return (0, 0);
	Oandas or
	Omodas or
	Oxoras or
	Ooras =>
		if(mathchk(n, 0) && islval(left))
			break;
		return (0, 0);
	Olt or
	Oleq or
	Ogt or
	Ogeq =>
		if(!mathchk(n, 1))
			return (0, 0);
		n.ty = tint;
	Oeq or
	Oneq =>
		case left.ty.kind{
		Tint or
		Tbig or
		Tbyte or
		Treal or
		Tstring or
		Tref or
		Tlist or
		Tarray or
		Tchan or
		Tany or
		Tmodule =>
			if(!tcompat(left.ty, right.ty, 0) && !tcompat(right.ty, left.ty, 0))
				break;
			t = left.ty;
			if(t == tany)
				t = right.ty;
			if(t == tany)
				t = tint;
			if(left.ty == tany)
				left.ty = t;
			if(right.ty == tany)
				right.ty = t;
			n.ty = tint;
usedty(n.ty);
			return (1, allok);
		}
		nerror(n, "cannot compare "+etconv(left)+" to "+etconv(right));
		return (0, 0);
	* =>
		fatal("unknown op in typecheck: "+opconv(n.op));
	}
usedty(n.ty);
	return (1, allok);
}

#
# n is syntactically a call, but n.left is not a fn
# check if it's the contructor for an adt
#
callcast(n: ref Node, kidsok, allok: int): (int, int)
{
	id: ref Decl;

	left := n.left;
	right := n.right;
	id = nil;
	case left.op{
	Oname =>
		id = left.decl;
	Omdot =>
		if(left.right.op == Odot)
			id = left.right.right.decl;
		else
			id = left.right.decl;
	Odot =>
		id = left.right.decl;
	}
	if(id == nil || (id.store != Dtype && id.store != Dtag)){
		nerror(left, expconv(left)+" is not a function or type name");
		return (0, 0);
	}
	if(id.store == Dtag)
		return tagcast(n, left, right, id, kidsok, allok);
	t := left.ty;
	n.ty = t;
	if(!kidsok)
		return (1, 0);

	if(t.kind == Tref)
		t = t.tof;
	tt := mktype(n.src.start, n.src.stop, Ttuple, nil, tuplefields(right));
	if(t.kind == Tadt && tcompat(t, tt, 1))
		return (1, allok);

	nerror(left, "cannot make a "+expconv(left)+" from '("+subexpconv(right)+")'");
	return (0, 0);
}

tagcast(n, left, right: ref Node, id: ref Decl, kidsok, allok: int): (int, int)
{
	left.ty = id.ty;
	if(left.op == Omdot)
		left.right.ty = id.ty;
	n.ty = id.ty;
	if(!kidsok)
		return (1, 0);
	id.ty.tof = usetype(id.ty.tof);
	if(right != nil)
		right.ty = id.ty.tof;
	tt := mktype(n.src.start, n.src.stop, Ttuple, nil, mkids(nosrc, nil, tint, tuplefields(right)));
	tt.ids.store = Dfield;
	if(tcompat(id.ty.tof, tt, 1))
		return (1, allok);

	nerror(left, "cannot make a "+expconv(left)+" from '("+subexpconv(right)+")'");
	return (0, 0);
}

valistype(n: ref Node): int
{
	case n.op{
	Oname =>
		if(n.decl.store == Dtype)
			return 1;
	Omdot =>
		return valistype(n.right);
	}
	return 0;
}

islval(n: ref Node): int
{
	s := marklval(n);
	if(s == 1)
		return 1;
	if(s == 0)
		nerror(n, "cannot assign to "+expconv(n));
	else
		circlval(n, n);
	return 0;
}

#
# check to see if n is an lval
#
marklval(n: ref Node): int
{
	if(n == nil)
		return 0;
	case n.op{
	Oname =>
		return storespace[n.decl.store];	#ZZZZ && n.decl.tagged == nil;
	Odot =>
		if(n.right.decl.store != Dfield)
			return 0;
		if(n.right.decl.cycle != byte 0 && n.right.decl.cyc == byte 0)
			return -1;
		if(n.left.ty.kind != Tref && marklval(n.left) == 0)
			nwarn(n, "assignment to "+etconv(n)+" ignored");
		return 1;
	Omdot =>
		if(n.right.decl.store == Dglobal)
			return 1;
		return 0;
	Oind =>
		for(id := n.ty.ids; id != nil; id = id.next)
			if(id.cycle != byte 0 && id.cyc == byte 0)
				return -1;
		return 1;
	Oslice =>
		if(n.right.right.op != Onothing || n.ty == tstring)
			return 0;
		return 1;
	Oinds =>
		#
		# make sure we don't change a string constant
		#
		case n.left.op{
		Oconst =>
			return 0;
		Oname =>
			return storespace[n.left.decl.store];
		Odot or
		Omdot =>
			if(n.left.right.decl != nil)
				return storespace[n.left.right.decl.store];
		}
		return 1;
	Oindex or
	Oindx =>
		return 1;
	Otuple =>
		for(nn := n.left; nn != nil; nn = nn.right){
			s := marklval(nn.left);
			if(s != 1)
				return s;
		}
		return 1;
	* =>
		return 0;
	}
	return 0;
}

#
# n has a circular field assignment.
# find it and print an error message.
#
circlval(n, lval: ref Node): int
{
	if(n == nil)
		return 0;
	case n.op{
	Oname =>
		break;
	Odot =>
		if(n.right.decl.cycle != byte 0 && n.right.decl.cyc == byte 0){
			nerror(lval, "cannot assign to "+expconv(lval)+" because field '"+n.right.decl.sym.name
					+"' of "+expconv(n.left)+" could complete a cycle to "+expconv(n.left));
			return -1;
		}
		return 1;
	Oind =>
		for(id := n.ty.ids; id != nil; id = id.next){
			if(id.cycle != byte 0 && id.cyc == byte 0){
				nerror(lval, "cannot assign to "+expconv(lval)+" because field '"+id.sym.name
					+"' of "+expconv(n)+" could complete a cycle to "+expconv(n));
				return -1;
			}
		}
		return 1;
	Oslice =>
		if(n.right.right.op != Onothing || n.ty == tstring)
			return 0;
		return 1;
	Oindex or
	Oinds or
	Oindx =>
		return 1;
	Otuple =>
		for(nn := n.left; nn != nil; nn = nn.right){
			s := circlval(nn.left, lval);
			if(s != 1)
				return s;
		}
		return 1;
	* =>
		return 0;
	}
	return 0;
}

mathchk(n: ref Node, realok: int): int
{
	lt := n.left.ty;
	rt := n.right.ty;
	if(rt != lt){
		nerror(n, "type clash in "+etconv(n.left)+" "+opconv(n.op)+" "+etconv(n.right));
		return 0;
	}
	n.ty = rt;
	case rt.kind{
	Tint or
	Tbig or
	Tbyte =>
		return 1;
	Tstring =>
		case n.op{
		Oadd or
		Oaddas or
		Ogt or
		Ogeq or
		Olt or
		Oleq =>
			return 1;
		}
	Treal =>
		if(realok)
			return 1;
	}
	nerror(n, "cannot "+opconv(n.op)+" "+etconv(n.left)+" and "+etconv(n.right));
	return 0;
}

shiftchk(n: ref Node): int
{
	right := n.right;
	left := n.left;
	n.ty = left.ty;
	case n.ty.kind{
	Tint or
	Tbyte or
	Tbig =>
		if(right.ty.kind != Tint){
			nerror(n, "shift "+etconv(right)+" is not an int");
			return 0;
		}
		return 1;
	}
	nerror(n, "cannot "+opconv(n.op)+" "+etconv(left)+" by "+etconv(right));
	return 0;
}

#
# check for any tany's in t
#
specific(t: ref Type): int
{
	if(t == nil)
		return 0;
	case t.kind{
	Terror or
	Tnone or
	Tint or
	Tbig or
	Tstring or
	Tbyte or
	Treal or
	Tfn or
	Tadt or
	Tadtpick or
	Tmodule =>
		return 1;
	Tany =>
		return 0;
	Tref or
	Tlist or
	Tarray or
	Tchan =>
		return specific(t.tof);
	Ttuple =>
		for(d := t.ids; d != nil; d = d.next)
			if(!specific(d.ty))
				return 0;
		return 1;
	}
	fatal("unknown type in specific: "+typeconv(t));
	return 0;
}

#
# infer the type of all variable in n from t
# n is the left-hand exp of a := exp
#
declasinfer(n: ref Node, t: ref Type): int
{
	case n.op{
	Otuple =>
		if(t.kind != Ttuple && t.kind != Tadt && t.kind != Tadtpick)
			return 0;
		ok := 1;
		n.ty = t;
		n = n.left;
		ids := t.ids;
		if(t.kind == Tadtpick)
			ids = t.tof.ids.next;
		for(; n != nil && ids != nil; ids = ids.next){
			if(ids.store != Dfield)
				continue;
			ok &= declasinfer(n.left, ids.ty);
			n = n.right;
		}
		for(; ids != nil; ids = ids.next)
			if(ids.store == Dfield)
				break;
		if(n != nil || ids != nil)
			return 0;
		return ok;
	Oname =>
		topvartype(t, n.decl, 0);
		if(n.decl == nildecl)
			return 1;
		n.decl.ty = t;
		n.ty = t;
		return 1;
	}
	fatal("unknown op in declasinfer: "+nodeconv(n));
	return 0;
}

#
# an error occured in declaring n;
# set all decl identifiers to Dwundef
# so further errors are squashed.
#
declaserr(n: ref Node)
{
	case n.op{
	Otuple =>
		for(n = n.left; n != nil; n = n.right)
			declaserr(n.left);
		return;
	Oname =>
		if(n.decl != nildecl)
			n.decl.store = Dwundef;
		return;
	}
	fatal("unknown op in declaserr: "+nodeconv(n));
}

argcompat(n: ref Node, f: ref Decl, a: ref Node): int
{
	for(; a != nil; a = a.right){
		if(f == nil){
			nerror(n, expconv(n.left)+": too many function arguments");
			return 0;
		}
		if(!tcompat(f.ty, a.left.ty, 0)){
			nerror(n, expconv(n.left)+": argument type mismatch: expected "+typeconv(f.ty)+" saw "+etconv(a.left));
			return 0;
		}
		if(a.left.ty == tany)
			a.left.ty = f.ty;
		f = f.next;
	}
	if(f != nil){
		nerror(n, expconv(n.left)+": too few function arguments");
		return 0;
	}
	return 1;
}

#
# fn is Odot(adt, methid)
# pass adt implicitly if needed
# if not, any side effect of adt will be ingored
#
passimplicit(fname, args: ref Node): ref Node
{
	t := fname.ty;
	if(t.ids == nil || t.ids.implicit == byte 0){
		if(hasside(fname.left))
			nwarn(fname, "result of expression "+expconv(fname.left)+" ignored");
		return args;
	}
	n := fname.left;
	if(n.op == Oname && n.decl.store == Dtype){
		nerror(n, expconv(n)+" is a type and cannot be a self argument");
		n = mkn(Onothing, nil, nil);
		n.src = fname.src;
		n.ty = t.ids.ty;
	}
	args = mkn(Oseq, n, args);
	args.src = n.src;
	return args;
}

#
# check the types for a function with a variable number of arguments
# last typed argument must be a constant string, and must use the
# print format for describing arguments.
#
mkvarargs(n, args: ref Node): ref Type
{
	last: ref Decl;

	nt := copytypeids(n.ty);
	n.ty = nt;
	f := n.ty.ids;
	last = nil;
	if(f == nil){
		nerror(n, expconv(n)+"'s type is illegal");
		return nt;
	}
	s := args;
	for(a := args; a != nil; a = a.right){
		if(f == nil)
			break;
		if(!tcompat(f.ty, a.left.ty, 0)){
			nerror(n, expconv(n)+": argument type mismatch: expected "+typeconv(f.ty)+" saw "+etconv(a.left));
			return nt;
		}
		if(a.left.ty == tany)
			a.left.ty = f.ty;
		last = f;
		f = f.next;
		s = a;
	}
	if(f != nil){
		nerror(n, expconv(n)+": too few function arguments");
		return nt;
	}
	s.left = fold(s.left);
	s = s.left;
	if(s.ty != tstring || s.op != Oconst){
		nerror(args, expconv(n)+": format argument "+etconv(s)+" is not a string constant");
		return nt;
	}
	fmtcheck(n, s, a);
	va := tuplefields(a);
	if(last == nil)
		nt.ids = va;
	else
		last.next = va;
	return nt;
}

#
# check that a print style format string matches it's arguments
#
fmtcheck(f, fmtarg, va: ref Node)
{
	fmt := fmtarg.decl.sym;
	s := fmt.name;
	ns := 0;
	while(ns < len s){
		c := s[ns++];
		if(c != '%')
			continue;

		verb := -1;
		n1 := 0;
		n2 := 0;
		dot := 0;
		flag := 0;
		flags := "";
		fmtstart := ns - 1;
		while(ns < len s && verb < 0){
			c = s[ns++];
			case c{
			* =>
				nerror(f, expconv(f)+": invalid character "+s[ns-1:ns]+" in format '"+s[fmtstart:ns]+"'");
				return;
			'.' =>
				if(dot){
					nerror(f, expconv(f)+": invalid format '"+s[fmtstart:ns]+"'");
					return;
				}
				n1 = 1;
				dot = 1;
				continue;
			'*' =>
				if(!n1)
					n1 = 1;
				else if(!n2 && dot)
					n2 = 1;
				else{
					nerror(f, expconv(f)+": invalid format '"+s[fmtstart:ns]+"'");
					return;
				}
				if(va == nil){
					nerror(f, expconv(f)+": too few arguments for format '"+s[fmtstart:ns]+"'");
					return;
				}
				if(va.left.ty.kind != Tint){
					nerror(f, expconv(f)+": format '"+s[fmtstart:ns]+"' incompatible with argument "+etconv(va.left));
					return;
				}
				va = va.right;
			'0' to '9' =>
				while(ns < len s && s[ns] >= '0' && s[ns] <= '9')
					ns++;
				if(!n1)
					n1 = 1;
				else if(!n2 && dot)
					n2 = 1;
				else{
					nerror(f, expconv(f)+": invalid format '"+s[fmtstart:ns]+"'");
					return;
				}
			'+' or
			'-' or
			'#' or
			'b' or
			'u' =>
				for(i := 0; i < flag; i++){
					if(flags[i] == c){
						nerror(f, expconv(f)+": duplicate flag "+s[ns-1:ns]+" in format '"+s[fmtstart:ns]+"'");
						return;
					}
				}
				flags[flag++] = c;
			'%' or
			'r' =>
				verb = Tnone;
			'H' =>
				verb = Tany;
			'c' =>
				verb = Tint;
			'd' or
			'o' or
			'x' or
			'X' =>
				verb = Tint;
				for(i := 0; i < flag; i++){
					if(flags[i] == 'b'){
						verb = Tbig;
						break;
					}
				}
			'e' or
			'f' or
			'g' or
			'E' or
			'G' =>
				verb = Treal;
			's' =>
				verb = Tstring;
			}
		}
		if(verb != Tnone){
			if(verb < 0){
				nerror(f, expconv(f)+": incomplete format '"+s[fmtstart:ns]+"'");
				return;
			}
			if(va == nil){
				nerror(f, expconv(f)+": too few arguments for format '"+s[fmtstart:ns]+"'");
				return;
			}
			case verb{
			Tint =>
				case va.left.ty.kind{
				Tstring or
				Tarray or
				Tref or
				Tchan or
				Tlist or
				Tmodule =>
					if(c == 'x' || c == 'X')
						verb = va.left.ty.kind;
				}
			Tany =>
				if(tattr[va.left.ty.kind].isptr)
					verb = va.left.ty.kind;
			}
			if(verb != va.left.ty.kind){
				nerror(f, expconv(f)+": format '"+s[fmtstart:ns]+"' incompatible with argument "+etconv(va.left));
				return;
			}
			va = va.right;
		}
	}
	if(va != nil)
		nerror(f, expconv(f)+": more arguments than formats");
}

tuplefields(n: ref Node): ref Decl
{
	h, last: ref Decl;

	for(; n != nil; n = n.right){
		d := mkdecl(n.left.src, Dfield, n.left.ty);
		if(h == nil)
			h = d;
		else
			last.next = d;
		last = d;
	}
	return h;
}

#
# make explicit indices for every element in an array initializer
# return the maximum index
# sort the indices and check for duplicates
#
assignindices(ar: ref Node): int
{
	wild, off, q: ref Node;

	amax := 16r7fffffff;
	size := dupn(0, nosrc, ar.left);
	if(size.ty == tint){
		size = fold(size);
		if(size.op == Oconst)
			amax = int size.c.val;
	}

	inits := ar.right;
	max := -1;
	last := -1;
	t := inits.left.ty;
	wild = nil;
	nlab := 0;
	ok := 1;
	for(n := inits; n != nil; n = n.right){
		if(!tcompat(t,  n.left.ty, 0)){
			t = tparent(t, n.left.ty);
			if(!tcompat(t, n.left.ty, 0)){
				nerror(n.left, "inconsistent types "+typeconv(t)+" and "+typeconv(n.left.ty)+" in array initializer");
				return -1;
			}
			else
				inits.left.ty = t;
		}
		if(t == tany)
			t = n.left.ty;

		#
		# make up an index if there isn't one
		#
		if(n.left.left == nil)
			n.left.left = mkn(Oseq, mkconst(n.left.right.src, big(last + 1)), nil);

		for(q = n.left.left; q != nil; q = q.right){
			off = q.left;
			if(off.ty != tint){
				nerror(off, "array index "+etconv(off)+" is not an int");
				ok = 0;
				continue;
			}
			off = fold(off);
			case off.op{
			Owild =>
				if(wild != nil)
					nerror(off, "array index * duplicated on line "+lineconv(wild.src.start));
				wild = off;
				continue;
			Orange =>
				if(off.left.op != Oconst || off.right.op != Oconst){
					nerror(off, "range "+expconv(off)+" is not constant");
					off = nil;
				}else if(off.left.c.val < big 0 || off.right.c.val >= big amax){
					nerror(off, "array index "+expconv(off)+" out of bounds");
					off = nil;
				}else
					last = int off.right.c.val;
			Oconst =>
				last = int off.c.val;
				if(off.c.val < big 0 || off.c.val >= big amax){
					nerror(off, "array index "+expconv(off)+" out of bounds");
					off = nil;
				}
			Onothing =>
				# get here from a syntax error
				off = nil;
			* =>
				nerror(off, "array index "+expconv(off)+" is not constant");
				off = nil;
			}

			nlab++;
			if(off == nil){
				off = mkconst(n.left.right.src, big(last));
				ok = 0;
			}
			if(last > max)
				max = last;
			q.left = off;
		}
	}

	#
	# fix up types of nil elements
	#
	for(n = inits; n != nil; n = n.right)
		if(n.left.ty == tany)
			n.left.ty = t;

	if(!ok)
		return -1;

	c := checklabels(inits, tint, nlab, "array index");
	t = mktype(inits.src.start, inits.src.stop, Tainit, nil, nil);
	inits.ty = t;
	t.cse = c;

	return max + 1;
}

#
# check the labels of a case statment
#
casecheck(cn: ref Node, ret: ref Type)
{
	wild: ref Node;

	(rok, nil) := echeck(cn.left, 0, 0);
	cn.right = scheck(cn.right, ret, Sother);
	if(!rok)
		return;
	arg := cn.left;

	t := arg.ty;
	if(t != tint && t != tstring){
		nerror(cn, "case argument "+etconv(arg)+" is not an int or string");
		return;
	}

	wild = nil;
	nlab := 0;
	ok := 1;
	for(n := cn.right; n != nil; n = n.right){
		q := n.left.left;
		if(n.left.right.right == nil)
			nwarn(q, "no body for case qualifier "+expconv(q));
		for(; q != nil; q = q.right){
			left := fold(q.left);
			q.left = left;
			case left.op{
			Owild =>
				if(wild != nil)
					nerror(left, "case qualifier * duplicated on line "+lineconv(wild.src.start));
				wild = left;
			Orange =>
				if(left.ty != t)
					nerror(left, "case qualifier "+etconv(left)+" clashes with "+etconv(arg));
				else if(left.left.op != Oconst || left.right.op != Oconst){
					nerror(left, "case range "+expconv(left)+" is not constant");
					ok = 0;
				}
				nlab++;
			* =>
				if(left.ty != t){
					nerror(left, "case qualifier "+etconv(left)+" clashes with "+etconv(arg));
					ok = 0;
				}else if(left.op != Oconst){
					nerror(left, "case qualifier "+expconv(left)+" is not constant");
					ok = 0;
				}
				nlab++;
			}
		}
	}

	if(!ok)
		return;

	c := checklabels(cn.right, t, nlab, "case qualifier");
	op := Tcase;
	if(t == tstring)
		op = Tcasec;
	t = mktype(cn.src.start, cn.src.stop, op, nil, nil);
	cn.ty = t;
	t.cse = c;
}

#
# check the labels and bodies of a pick statment
#
pickcheck(n: ref Node, ret: ref Type)
{
	qs, q, w: ref Node;

	arg := n.left.right;
	(nil, allok) := echeck(arg, 0, 0);
	if(!allok)
		return;
	t := arg.ty;
	if(t.kind == Tref)
		t = t.tof;
	if(arg.ty.kind != Tref || t.kind != Tadt || t.tags == nil){
		nerror(arg, "pick argument "+etconv(arg)+" is not a ref adt with pick tags");
		return;
	}
	argty := usetype(mktype(arg.ty.src.start, arg.ty.src.stop, Tref, t, nil));

	arg = n.left.left;
	pushscope(nil, Sother);
	dasdecl(arg);
	arg.decl.ty = argty;
	arg.ty = argty;

	tags := array[t.decl.tag] of ref Node;
	w = nil;
	ok := 1;
	nlab := 0;
	for(qs = n.right; qs != nil; qs = qs.right){
		qt : ref Node = nil;
		for(q = qs.left.left; q != nil; q = q.right){
			left := q.left;
			case left.op{
			Owild =>
				left.ty = tnone;
				if(w != nil)
					nerror(left, "pick qualifier * duplicated on line "+lineconv(w.src.start));
				w = left;
			Oname =>
				id := namedot(t.tags, left.decl.sym);
				if(id == nil){
					nerror(left, "pick qualifier "+expconv(left)+" is not a member of "+etconv(arg));
					ok = 0;
					continue;
				}

				left.decl = id;
				left.ty = id.ty;

				if(tags[id.tag] != nil){
					nerror(left, "pick qualifier "+expconv(left)+" duplicated on line "+lineconv(tags[id.tag].src.start));
					ok = 0;
				}
				tags[id.tag] = left;
				nlab++;
			* =>
				fatal("pickcheck can't handle "+nodeconv(q));
			}

			if(qt == nil)
				qt = left;
			else if(!tequal(qt.ty, left.ty))
				nerror(left, "type clash in pick qualifiers "+etconv(qt)+" and "+etconv(left));
		}

		argty.tof = t;
		if(qt != nil)
			argty.tof = qt.ty;
		qs.left.right = scheck(qs.left.right, ret, Sother);
		if(qs.left.right == nil)
			nwarn(qs.left.left, "no body for pick qualifier "+expconv(qs.left.left));
	}
	argty.tof = t;
	for(qs = n.right; qs != nil; qs = qs.right)
		for(q = qs.left.left; q != nil; q = q.right)
			q.left = fold(q.left);

	d := popscope();
	d.refs++;
	if(d.next != nil)
		fatal("pickcheck: installing more than one id");
	fndecls = appdecls(fndecls, d);

	if(!ok)
		return;

	c := checklabels(n.right, tint, nlab, "pick qualifier");
	t = mktype(n.src.start, n.src.stop, Tcase, nil, nil);
	n.ty = t;
	t.cse = c;
}

#
# check array and case labels for validity
#
checklabels(inits: ref Node, ctype: ref Type, nlab: int, title: string): ref Case
{
	n, q, wild: ref Node;

	labs := array[nlab] of Label;
	i := 0;
	wild = nil;
	for(n = inits; n != nil; n = n.right){
		for(q = n.left.left; q != nil; q = q.right){
			case q.left.op{
			Oconst =>
				labs[i].start = q.left;
				labs[i].stop = q.left;
				labs[i++].node = n.left;
			Orange =>
				labs[i].start = q.left.left;
				labs[i].stop = q.left.right;
				labs[i++].node = n.left;
			Owild =>
				wild = n.left;
			* =>
				fatal("bogus index in checklabels");
			}
		}
	}

	if(i != nlab)
		fatal("bad label count: "+string nlab+" then "+string i);

	casesort(ctype, array[nlab] of Label, labs, 0, nlab);
	for(i = 0; i < nlab; i++){
		p := labs[i].stop;
		if(casecmp(ctype, labs[i].start, p) > 0)
			nerror(labs[i].start, "unmatchable "+title+" "+expconv(labs[i].node));
		for(e := i + 1; e < nlab; e++){
			if(casecmp(ctype, labs[e].start, p) <= 0)
				nerror(labs[e].start, title+" '"+eprintlist(labs[e].node.left, " or ")
					+"' overlaps with '"+eprintlist(labs[e-1].node.left, " or ")+"' on line "
					+lineconv(p.src.start));

			#
			# check for merging case labels
			#
			if(ctype != tint
			|| labs[e].start.c.val != p.c.val+big 1
			|| labs[e].node != labs[i].node)
				break;
			p = labs[e].stop;
		}
		if(e != i + 1){
			labs[i].stop = p;
			labs[i+1:] = labs[e:nlab];
			nlab -= e - (i + 1);
		}
	}

	c := ref Case;
	c.nlab = nlab;
	c.nsnd = 0;
	c.labs = labs;
	c.wild = wild;

	return c;
}

casecmp(ty: ref Type, a, b: ref Node): int
{
	if(ty == tint){
		if(a.c.val < b.c.val)
			return -1;
		if(a.c.val > b.c.val)
			return 1;
		return 0;
	}

	s := a.decl.sym;
	t := b.decl.sym;

	if(s.name < t.name)
		return -1;
	if(s.name > t.name)
		return 1;
	return 0;
}

casesort(t: ref Type, aux, labs: array of Label, start, stop: int)
{
	n := stop - start;
	if(n <= 1)
		return;
	top := mid := start + n / 2;

	casesort(t, aux, labs, start, top);
	casesort(t, aux, labs, mid, stop);

	#
	# merge together two sorted label arrays, yielding a sorted array
	#
	n = 0;
	base := start;
	while(base < top && mid < stop){
		if(casecmp(t, labs[base].start, labs[mid].start) <= 0)
			aux[n++] = labs[base++];
		else
			aux[n++] = labs[mid++];
	}
	if(base < top)
		aux[n:] = labs[base:top];
	else if(mid < stop)
		aux[n:] = labs[mid:stop];
	labs[start:] = aux[:stop-start];
}

#
# binary search for the label corresponding to a given value
#
findlab(ty: ref Type, v: ref Node, labs: array of Label, nlab: int): int
{
	if(nlab <= 1)
		return 0;
	m : int;
	l := 1;
	r := nlab - 1;
	while(l <= r){
		m = (r + l) / 2;
		if(casecmp(ty, labs[m].start, v) <= 0)
			l = m + 1;
		else
			r = m - 1;
	}
	m = l - 1;
	if(casecmp(ty, labs[m].start, v) > 0
	|| casecmp(ty, labs[m].stop, v) < 0)
		fatal("findlab out of range");
	return m;
}

altcheck(an: ref Node, ret: ref Type)
{
	n, q, left, op, wild: ref Node;

	an.left = scheck(an.left, ret, Sother);

	ok := 1;
	nsnd := 0;
	nrcv := 0;
	wild = nil;
	for(n = an.left; n != nil; n = n.right){
		q = n.left.right.left;
		if(n.left.right.right == nil)
			nwarn(q, "no body for alt guard "+expconv(q));
		for(; q != nil; q = q.right){
			left = q.left;
			case left.op{
			Owild =>
				if(wild != nil)
					nerror(left, "alt guard * duplicated on line "+lineconv(wild.src.start));
				wild = left;
			Orange =>
				nerror(left, "alt guard "+expconv(left)+" is illegal");
				ok = 0;
			* =>
				op = hascomm(left);
				if(op == nil){
					nerror(left, "alt guard "+expconv(left)+" has no communication");
					ok = 0;
					break;
				}
				if(op.op == Osnd)
					nsnd++;
				else
					nrcv++;
			}
		}
	}

	if(!ok)
		return;

	c := ref Case;
	c.nlab = nsnd + nrcv;
	c.nsnd = nsnd;
	c.wild = wild;

	an.ty = mktalt(c);
}

hascomm(n: ref Node): ref Node
{
	if(n == nil)
		return nil;
	if(n.op == Osnd || n.op == Orcv)
		return n;
	r := hascomm(n.left);
	if(r != nil)
		return r;
	return hascomm(n.right);
}
