implement SimpleFS;
include "sys.m";
	sys: Sys;
include "styx.m";
include "styxservers.m";
	Treeop: import Styxservers;
	Enotfound, Eexists: import Styxservers;
include "simplefs.m";

Fholder: adt {
	parentqid:	Qidpath;
	d:		Sys->Dir;
	child:	cyclic ref Fholder;
	sibling:	cyclic ref Fholder;
	hash:	cyclic ref Fholder;
};

init()
{
	sys = load Sys Sys->PATH;
}

start(): (ref Fs, chan of ref Styxservers->Treeop)
{
	fs := ref Fs(chan of ref Fsop, chan of string);
	c := chan of ref Styxservers->Treeop;
	spawn fsproc(c, fs.c);
	return (fs, c);
}

Fs.quit(t: self ref Fs)
{
	t.c <-= nil;
}

Fs.create(t: self ref Fs, parentq: Qidpath, d: Sys->Dir): string
{
	t.c <-= ref Fsop.Create(t.reply, parentq, d);
	return <-t.reply;
}

Fs.remove(t: self ref Fs, q: Qidpath): string
{
	t.c <-= ref Fsop.Remove(t.reply, q);
	return <-t.reply;
}

fsproc(c: chan of ref Treeop, fsc: chan of ref Fsop)
{
	tab := array[23] of ref Fholder;
	starttime := 0;

	for (;;) alt {
	grq := <-c =>
		if (grq == nil)
			exit;
		(q, reply) := (grq.q, grq.reply);
		fh := findfile(tab, q);
		if (fh == nil) {
			reply <-= (nil, Enotfound);
			continue;
		}
		pick rq := grq {
		Find =>
			reply <-= (ref fh.d, nil);
		Walk =>
			d := fswalk(tab, fh, rq.name);
			if (d == nil)
				reply <-= (nil, Enotfound);
			else
				reply <-= (d, nil);
		Readdir =>
			(start, end) := (rq.offset, rq.offset + rq.count);
			fh = fh.child;
			for (i := 0; i < end && fh != nil; i++) {
				if (i >= start)
					reply <-= (ref fh.d, nil);
				fh = fh.sibling;
			}
			reply <-= (nil, nil);
		* =>
			panic(sys->sprint("unknown op %d\n", tagof(grq)));
		}
	grq := <-fsc =>
		if (grq == nil)
			exit;
		(q, reply) := (grq.q, grq.reply);
		pick rq := grq {
		Create =>
			reply <-= fscreate(tab, q, rq.d);
		Remove =>
			reply <-= fsremove(tab, q);
		Wstat =>
			reply <-= fswstat(tab, q, rq.d);
		* =>
			panic(sys->sprint("unknown fs op %d\n", tagof(grq)));
		}
	}
}

hashfn(q: Qidpath, n: int): int
{
	h := q % n;
	if (h < 0)
		h += n;
	return h;
}

findfile(tab: array of ref Fholder, q: Qidpath): ref Fholder
{
	for (fh := tab[hashfn(q, len tab)]; fh != nil; fh = fh.hash)
		if (fh.d.qid.path == q)
			return fh;
	return nil;
}

fswalk(tab: array of ref Fholder, fh: ref Fholder, name: string): ref Sys->Dir
{
	if (name == "..")
		return ref findfile(tab, fh.parentqid).d;
	for (fh = fh.child; fh != nil; fh = fh.sibling)
		if (fh.d.name == name)
			return ref fh.d;
	return nil;
}

fsremove(tab: array of ref Fholder, q: Qidpath): string
{
	prev: ref Fholder;

	# remove from hash table
	slot := hashfn(q, len tab);
	for (fh := tab[slot]; fh != nil; fh = fh.hash) {
		if (fh.d.qid.path == q)
			break;
		prev = fh;
	}
	if (fh == nil)
		return Enotfound;
	if (prev == nil)
		tab[slot] = fh.hash;
	else
		prev.hash = fh.hash;
	fh.hash = nil;

	# remove from parent's children
	parent := findfile(tab, fh.parentqid);
	if (parent != nil) {
		prev = nil;
		for (sfh := parent.child; sfh != nil; sfh = sfh.sibling) {
			if (sfh == fh)
				break;
			prev = sfh;
		}
		if (sfh == nil)
			panic("child not found in parent");
		if (prev == nil)
			parent.child = fh.sibling;
		else
			prev.sibling = fh.sibling;
	}
	fh.sibling = nil;

	# now remove any descendents
	sibling: ref Fholder;
	for (sfh := fh.child; sfh != nil; sfh = sibling) {
		sibling = sfh.sibling;
		sfh.parentqid = sfh.d.qid.path;		# make sure it doesn't disrupt things.
		fsremove(tab, sfh.d.qid.path);
	}
	return nil;
}

fscreate(tab: array of ref Fholder, q: Qidpath, d: Sys->Dir): string
{
	parent := findfile(tab, q);
	if (findfile(tab, d.qid.path) != nil)
		return Eexists;
	# allow creation of a root directory only if its parent is itself
	if (parent == nil && d.qid.path != q)
		return Enotfound;
	fh: ref Fholder;
	if (parent == nil)
		fh = ref Fholder(q, d, nil, nil, nil);
	else {
		if (fswalk(tab, parent, d.name) != nil)
			return Eexists;
		fh = ref Fholder(parent.d.qid.path, d, nil, nil, nil);
		fh.sibling = parent.child;
		parent.child = fh;
	}
	slot := hashfn(d.qid.path, len tab);
	fh.hash = tab[slot];
	tab[slot] = fh;
	return nil;
}

fswstat(tab: array of ref Fholder, q: Qidpath, d: Sys->Dir): string
{
	fh := findfile(tab, q);
	if (fh == nil)
		return Enotfound;

	# if renaming a file, check for duplicates
	if (d.name != fh.d.name) {
		parent := findfile(tab, fh.parentqid);
		if (parent != nil && parent != fh && fswalk(tab, parent, d.name) != nil)
			return Eexists;
	}
	fh.d = d;
	fh.d.qid.path = q;		# ensure the qid can't be changed
	return nil;
}

panic(s: string)
{
	sys->fprint(sys->fildes(2), "panic: %s\n", s);
	sys->raise("panic");
}
