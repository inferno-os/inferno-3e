#
#	initially generated by c2l
#


varsub(s: array of byte): (ref Word, array of byte)
{
	b: ref Bufblock;
	w: ref Word;

	if(s[0] == byte '{')	#  either ${name} or ${name: A%B==C%D}
		return expandvar(s);
	(b, s) = varname(s);
	if(b == nil)
		return (nil, s);
	(w, s) = varmatch(b.start, s);
	freebuf(b);
	return (w, s);
}

# 
#  *	extract a variable name
#  
varname(s: array of byte): (ref Bufblock, array of byte)
{
	b: ref Bufblock;
	cp: array of byte;
	r: int;
	n: int;

	b = newbuf();
	cp = s;
	for(;;){
		(r, n, nil) = sys->byte2char(cp, 0);
		if(!(r > ' ' && libc0->strchr(libc0->s2ab("!\"#$%&'()*+,-./:;<=>?@[\\]^`{|}~"), r) == nil))
			break;
		rinsert(b, r);
		cp = cp[n: ];
	}
	if(b.current == 0){
		if(-1 >= 0)
			sys->fprint(sys->fildes(2), "mk: %s:%d: syntax error; ", libc0->ab2s(infile), -1);
		else
			sys->fprint(sys->fildes(2), "mk: %s:%d: syntax error; ", libc0->ab2s(infile), mkinline);
		sys->fprint(sys->fildes(2), "missing variable name <%s>\n", libc0->ab2s(s));
		freebuf(b);
		return (nil, s);
	}
	s = cp;
	insert(b, 0);
	return (b, s);
}

varmatch(name: array of byte, s: array of byte): (ref Word, array of byte)
{
	w: ref Word;
	sym: ref Symtab;
	cp: array of byte;

	sym = symlooki(name, S_VAR, 0);
	if(sym != nil){
		#  check for at least one non-NULL value 
		for(w = sym.wvalue; w != nil; w = w.next)
			if(w.s != nil && int w.s[0])
				return (wdup(w), s);
	}
	for(cp = s; cp[0] == byte ' ' || cp[0] == byte '\t'; cp = cp[1: ])	#  skip trailing whitespace 
		;
	s = cp;
	return (nil, s);
}

expandvar(s: array of byte): (ref Word, array of byte)
{
	w: ref Word;
	buf: ref Bufblock;
	sym: ref Symtab;
	cp, begin, end: array of byte;

	begin = s;
	s = s[1: ];	#  skip the '{' 
	(buf, s) = varname(s);
	if(buf == nil)
		return (nil, s);
	cp = s;
	if(cp[0] == byte '}'){	#  ${name} variant
		s[0]++;	#  skip the '}' 
		(w, s) = varmatch(buf.start, s);
		freebuf(buf);
		return (w, s);
	}
	if(cp[0] != byte ':'){
		if(-1 >= 0)
			sys->fprint(sys->fildes(2), "mk: %s:%d: syntax error; ", libc0->ab2s(infile), -1);
		else
			sys->fprint(sys->fildes(2), "mk: %s:%d: syntax error; ", libc0->ab2s(infile), mkinline);
		sys->fprint(sys->fildes(2), "bad variable name <%s>\n", libc0->ab2s(buf.start));
		freebuf(buf);
		return (nil, s);
	}
	cp = cp[1: ];
	end = charin(cp, libc0->s2ab("}"));
	if(end == nil){
		if(-1 >= 0)
			sys->fprint(sys->fildes(2), "mk: %s:%d: syntax error; ", libc0->ab2s(infile), -1);
		else
			sys->fprint(sys->fildes(2), "mk: %s:%d: syntax error; ", libc0->ab2s(infile), mkinline);
		sys->fprint(sys->fildes(2), "missing '}': %s\n", libc0->ab2s(begin));
		Exit();
	}
	end[0] = byte 0;
	s = end[1: ];
	sym = symlooki(buf.start, S_VAR, 0);
	if(sym == nil || !symval(sym))
		w = newword(buf.start);
	else
		w = subsub(sym.wvalue, cp, end);
	freebuf(buf);
	return (w, s);
}

extractpat(s: array of byte, r: array of byte, term: array of byte, end: array of byte): (ref Word, array of byte)
{
	save: int;
	cp: array of byte;
	w: ref Word;

	cp = charin(s, term);
	if(cp != nil){
		r = cp;
		if(cp == s)
			return (nil, r);
		save = int cp[0];
		cp[0] = byte 0;
		w = stow(s);
		cp[0] = byte save;
	}
	else{
		r = end;
		w = stow(s);
	}
	return (w, r);
}

subsub(v: ref Word, s: array of byte, end: array of byte): ref Word
{
	nmid, ok: int;
	head, tail, w, h, a, b, c, d: ref Word;
	buf: ref Bufblock;
	cp, enda: array of byte;

	(a, cp) = extractpat(s, cp, libc0->s2ab("=%&"), end);
	b = c = d = nil;
	if(cp[0] == byte '%' || cp[0] == byte '&')
		(b, cp) = extractpat(cp[1: ], cp, libc0->s2ab("="), end);
	if(cp[0] == byte '=')
		(c, cp) = extractpat(cp[1: ], cp, libc0->s2ab("&%"), end);
	if(cp[0] == byte '%' || cp[0] == byte '&')
		d = stow(cp[1: ]);
	else if(int cp[0])
		d = stow(cp);
	head = tail = nil;
	buf = newbuf();
	for(; v != nil; v = v.next){
		h = w = nil;
		(ok, nmid, enda) = submatch(v.s, a, b, nmid, enda);
		if(ok){
			#  enda points to end of A match in source;
			# 			 * nmid = number of chars between end of A and start of B
			# 			 
			if(c != nil){
				h = w = wdup(c);
				while(w.next != nil)
					w = w.next;
			}
			if((cp[0] == byte '%' || cp[0] == byte '&') && nmid > 0){
				if(w != nil){
					bufcpy(buf, w.s, libc0->strlen(w.s));
					bufcpy(buf, enda, nmid);
					insert(buf, 0);
					w.s = nil;
					w.s = libc0->strdup(buf.start);
				}
				else{
					bufcpy(buf, enda, nmid);
					insert(buf, 0);
					h = w = newword(buf.start);
				}
				buf.current = 0;
			}
			if(d != nil && int d.s[0]){
				if(w != nil){
					bufcpy(buf, w.s, libc0->strlen(w.s));
					bufcpy(buf, d.s, libc0->strlen(d.s));
					insert(buf, 0);
					w.s = nil;
					w.s = libc0->strdup(buf.start);
					w.next = wdup(d.next);
					while(w.next != nil)
						w = w.next;
					buf.current = 0;
				}
				else
					h = w = wdup(d);
			}
		}
		if(w == nil)
			h = w = newword(v.s);
		if(head == nil)
			head = h;
		else
			tail.next = h;
		tail = w;
	}
	freebuf(buf);
	delword(a);
	delword(b);
	delword(c);
	delword(d);
	return head;
}

submatch(s: array of byte, a: ref Word, b: ref Word, nmid: int, enda: array of byte): (int, int, array of byte)
{
	w: ref Word;
	n: int;
	end: array of byte;

	n = 0;
	for(w = a; w != nil; w = w.next){
		n = libc0->strlen(w.s);
		if(libc0->strncmp(s, w.s, n) == 0)
			break;
	}
	if(a != nil && w == nil)	#   a == NULL matches everything
		return (0, nmid, enda);
	enda = s[n: ];	#  pointer to end a A part match 
	nmid = libc0->strlen(s)-n;	#  size of remainder of source 
	end = enda[nmid: ];
	onmid := nmid;
	for(w = b; w != nil; w = w.next){
		n = libc0->strlen(w.s);
		if(libc0->strcmp(w.s, enda[onmid-n: ]) == 0){	# end-n
			nmid -= n;
			break;
		}
	}
	if(b != nil && w == nil)	#  b == NULL matches everything 
		return (0, nmid, enda);
	return (1, nmid, enda);
}

