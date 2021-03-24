implement Iobuf;

include "sys.m";
	sys: Sys;

include "iobuf.m";

chatty: con 0;

devices:	list of ref Device;

NIOB:	con 100;	# for starters
HIOB:	con 127;	# prime

hiob := array[HIOB] of list of ref Block;	# hash buckets
iohead:	ref Block;
iotail:	ref Block;
bufsize := 0;

init(bsize: int)
{
	sys = load Sys Sys->PATH;
	bufsize = bsize;
	for(i:=0; i<NIOB; i++)
		newblock();
}

newblock(): ref Block
{
	p := ref Block;
	p.busy = 0;
	p.addr = -1;
	p.dev = nil;
	p.data = array[bufsize] of byte;
	p.next = iohead;
	if(iohead != nil)
		iohead.prev = p;
	iohead = p;
	if(iotail == nil)
		iotail = p;
	return p;
}

Block.get(dev: ref Device, addr: int): ref Block
{
	p: ref Block;

	dh := hiob[addr%HIOB:];
	for(l := dh[0]; l != nil; l = tl l) {
		p = hd l;
		if(p.addr == addr && p.dev == dev) {
			p.busy++;
			return p;
		}
	}
	# Find a non-busy buffer from the tail
	for(p = iotail; p != nil && p.busy; p = p.prev)
		;
	if(p == nil)
		p = newblock();

	# Delete from hash chain
	if(p.addr >= 0) {
		hp := hiob[p.addr%HIOB:];
		l = nil;
		for(f := hp[0]; f != nil; f = tl f)
			if(hd f != p)
				l = (hd f) :: l;
		hp[0] = l;
	}

	# Hash and fill
	p.addr = addr;
	p.dev = dev;
	p.busy++;
	sys->seek(dev.fd, addr*dev.sectorsize, 0);
	if(sys->read(dev.fd, p.data, dev.sectorsize) != dev.sectorsize){
		if(chatty)
			sys->print("read error: block %d: %r\n", addr);
		p.addr = -1;	# stop caching
		p.put();
		purge(dev);
		return nil;
	}
	dh[0] = p :: dh[0];
	if(chatty)
		sys->print("read %d\n", p.addr);
	return p;
}

Block.put(p: self ref Block)
{
	p.busy--;
	if(p.busy < 0)
		panic("Block.put");

	if(p == iohead)
		return;

	# Link onto head for lru
	if(p.prev != nil) 
		p.prev.next = p.next;
	else
		iohead = p.next;

	if(p.next != nil)
		p.next.prev = p.prev;
	else
		iotail = p.prev;

	p.prev = nil;
	p.next = iohead;
	iohead.prev = p;
	iohead = p;
}

purge(dev: ref Device)
{
	for(i := 0; i < HIOB; i++){
		l := hiob[i];
		hiob[i] = nil;
		for(; l != nil; l = tl l){	# reverses bucket's list, but never mind
			p := hd l;
			if(p.dev == dev)
				p.busy = 0;
			else
				hiob[i] = p :: hiob[i];
		}
	}
}

attach(name: string, mode: int, sectorsize: int): (ref Device, string)
{
	if(sectorsize > bufsize)
		return (nil, "sector size too big");
	fd := sys->open(name, mode);
	if(fd == nil)
		return(nil, sys->sprint("%s: can't open: %r", name));
	(rc, dir) := sys->fstat(fd);
	if(rc < 0)
		return (nil, sys->sprint("%r"));
	for(dl := devices; dl != nil; dl = tl dl){
		d := hd dl;
		if(d.qid.path != dir.qid.path || d.qid.vers != dir.qid.vers)
			continue;
		if(d.dtype != dir.dtype || d.dev != dir.dev)
			continue;
		d.inuse++;
		if(chatty)
			sys->print("inuse=%d, \"%s\", dev=%H...\n", d.inuse, d.name, d.fd);
		return (d, nil);
	}
	if(chatty)
		sys->print("alloc \"%s\", dev=%H...\n", name, fd);
	d := ref Device;
	d.inuse = 1;
	d.name = name;
	d.qid = dir.qid;
	d.dtype = dir.dtype;
	d.dev = dir.dev;
	d.fd = fd;
	d.sectorsize = sectorsize;
	devices = d :: devices;
	return (d, nil);
}

Device.detach(d: self ref Device)
{
	d.inuse--;
	if(d.inuse < 0)
		panic("putxdata");
	if(chatty)
		sys->print("decref=%d, \"%s\", dev=%H...\n", d.inuse, d.name, d.fd);
	if(d.inuse == 0){
		if(chatty)
			sys->print("purge...\n");
		purge(d);
		dl := devices;
		devices = nil;
		for(; dl != nil; dl = tl dl)
			if((hd dl) != d)
				devices = (hd dl) :: devices;
	}
}

panic(s: string)
{
	sys->print("panic: %s\n", s);
	a: array of byte;
	a[5] = byte 0; # trap
}
