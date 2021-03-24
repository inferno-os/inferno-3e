implement Styxaux;

include "sys.m";
	sys: Sys;
include "styx.m";
include "styxaux.m";

Tmsg : import Styx;

init()
{
}

fid(m: ref Tmsg): int
{
	pick fc := m {
		Nop =>		return 0;
		Readerror =>	return 0;
		Flush =>		return 0;
		Clone =>		return fc.fid;
		Walk =>		return fc.fid;
		Open =>		return fc.fid;
		Create =>		return fc.fid;
		Read =>		return fc.fid;
		Write =>		return fc.fid;
		Clunk =>		return fc.fid;
		Remove =>	return fc.fid;
		Stat =>		return fc.fid;
		Wstat =>		return fc.fid;
		Attach =>		return fc.fid;
	}
	error("bad styx fid");
	return 0;
}

uname(m: ref Tmsg): string
{
	pick fc := m {
		Attach =>		return fc.uname;
	}
	error("bad styx uname");
	return nil;
}

aname(m: ref Tmsg): string
{
	pick fc := m {
		Attach =>		return fc.aname;
	}
	error("bad styx aname");
	return nil;
}

newfid(m: ref Tmsg): int
{
	pick fc := m {
		Clone =>		return fc.newfid;
	}
	error("bad styx newfd");
	return 0;
}

name(m: ref Tmsg): string
{
	pick fc := m {
		Walk =>		return fc.name;
		Create =>		return fc.name;
	}
	error("bad styx name");
	return nil;
}

mode(m: ref Tmsg): int
{
	pick fc := m {
		Open =>		return fc.mode;
	}
	error("bad styx mode");
	return 0;
}

setmode(m: ref Tmsg, mode: int)
{
	pick fc := m {
		Open =>		fc.mode = mode;
		* =>			error("bad styx setmode");
	}
}

offset(m: ref Tmsg): big
{
	pick fc := m {
		Read =>		return fc.offset;
		Write =>		return fc.offset;
	}
	error("bad styx offset");
	return big 0;
}

count(m: ref Tmsg): int
{
	pick fc := m {
		Read =>		return fc.count;
		Write =>		return len fc.data;
	}
	error("bad styx count");
	return 0;
}

setcount(m: ref Tmsg, count: int)
{
	pick fc := m {
		Read =>		fc.count = count;
		* =>			error("bad styx setcount");
	}
}

oldtag(m: ref Tmsg): int
{
	pick fc := m {
		Flush =>		return fc.oldtag;
	}
	error("bad styx oldtag");
	return 0;
}

data(m: ref Tmsg): array of byte
{
	pick fc := m {
		Write =>		return fc.data;
	}
	error("bad styx data");
	return nil;
}

setdata(m: ref Tmsg, data: array of byte)
{
	pick fc := m {
		Write =>		fc.data = data;
		* =>			error("bad styx setdata");
	}
}

error(s: string)
{
	if(sys == nil)
		sys = load Sys Sys->PATH;
	sys->fprint(sys->fildes(2), "%s\n", s);
}
