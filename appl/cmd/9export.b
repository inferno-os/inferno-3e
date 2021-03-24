implement P9export;

include "sys.m";
	sys: Sys;
	sprint: import sys;

include "draw.m";

include "styx.m";
	NAMELEN, DIRLEN, ERRLEN: import Styx;

P9export: module {
	init:	fn(cTot: ref Draw->Context, argv: list of string);
};

# 9P message types
Tnop, Rnop, Tosession, Rosession, Terror, Rerror, Tflush, Rflush,
Toattach, Roattach, Tclone, Rclone, Twalk, Rwalk, Topen, Ropen,
Tcreate, Rcreate, Tread, Rread, Twrite, Rwrite, Tclunk, Rclunk,
Tremove, Rremove, Tstat, Rstat, Twstat, Rwstat, Tclwalk, Rclwalk,
Toauth, Roauth, Tsession, Rsession, Tattach, Rattach:
	con iota + 50;

# sizes of various message components
T:	con 1;
TAG:	con 2;
FID:	con 2;
QID:	con 8;
MODE:	con 1;
PERM:	con 4;
OFF:	con 8;
COUNT:	con 2;
PAD:	con 1;
CHAL:	con 8;
TICK:	con 72;
AUTH:	con 13;
DOMAIN:	con 48;
MAXMSG:	con 160;
FDATA:	con 8*1024;

Conv: adt {
	msgtype:	int;		# Styx or 9P message type byte
	size:		int;		# in bytes of fixed part of message
	resize:		int;		# necessary adjustment in bytes
	countpos:	int;		# if non-zero, position of count field
};

conv := array[256] of {
* =>		Conv(0,		0,				0,			0),

# 9P to Styx T messages
Tnop =>		(Styx->Tnop,	T+TAG,				0,			0),
Tflush =>	(Styx->Tflush,	T+2*TAG,			0,			0),
Tclone =>	(Styx->Tclone,	T+TAG+2*FID,			0,			0),
Twalk =>	(Styx->Twalk,	T+TAG+FID+NAMELEN,		0,			0),
Topen =>	(Styx->Topen,	T+TAG+FID+MODE,			0,			0),
Tcreate =>	(Styx->Tcreate,	T+TAG+FID+NAMELEN+PERM+MODE,	0,			0),
Tread =>	(Styx->Tread,	T+TAG+FID+OFF+COUNT,		0,			0),
Twrite =>	(Styx->Twrite,	T+TAG+FID+OFF+COUNT+PAD,	0,			T+TAG+FID+OFF),
Tclunk =>	(Styx->Tclunk,	T+TAG+FID,			0,			0),
Tremove =>	(Styx->Tremove,	T+TAG+FID,			0,			0),
Tstat =>	(Styx->Tstat,	T+TAG+FID,			0,			0),
Twstat =>	(Styx->Twstat,	T+TAG+FID+DIRLEN,		0,			0),
Tattach =>	(Styx->Tattach,	T+TAG+FID+2*NAMELEN+TICK+AUTH,	-TICK-AUTH,		0),
Tclwalk =>	(Rerror,	T+TAG+2*FID+NAMELEN,		-2*FID-NAMELEN+ERRLEN,	0),
Tsession =>	(Rsession,	T+TAG+CHAL,			+NAMELEN+DOMAIN,	0),

# Styx to 9P R messages
Styx->Rnop =>	(Rnop,		T+TAG,				0,			0),
Styx->Rerror =>	(Rerror,	T+TAG+ERRLEN,			0,			0),
Styx->Rflush =>	(Rflush,	T+TAG,				0,			0),
Styx->Rclone =>	(Rclone,	T+TAG+FID,			0,			0),
Styx->Rwalk =>	(Rwalk,		T+TAG+FID+QID,			0,			0),
Styx->Ropen =>	(Ropen,		T+TAG+FID+QID,			0,			0),
Styx->Rcreate=>	(Rcreate,	T+TAG+FID+QID,			0,			0),
Styx->Rread =>	(Rread,		T+TAG+FID+COUNT+PAD,		0,			T+TAG+FID),
Styx->Rwrite =>	(Rwrite,	T+TAG+FID+COUNT,		0,			0),
Styx->Rclunk =>	(Rclunk,	T+TAG+FID,			0,			0),
Styx->Rremove=>	(Rremove,	T+TAG+FID,			0,			0),
Styx->Rstat =>	(Rstat,		T+TAG+FID+DIRLEN,		0,			0),
Styx->Rwstat =>	(Rwstat,	T+TAG+FID,			0,			0),
Styx->Rattach=>	(Rattach,	T+TAG+FID+QID,			+AUTH,			0),
};

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	if (len argv != 2) {
		sys->fprint(sys->fildes(2), "usage: 9export dir\n");
		sys->raise("fail:usage");
	}
	sys->pctl(Sys->NEWPGRP, nil);
	pfd := array[2] of ref Sys->FD;
	if (sys->pipe(pfd) < 0)
		hangup(sprint("pipe: %r"));
	if (sys->exportdir(pfd[0], hd tl argv, Sys->EXPASYNC) < 0)
		hangup(sprint("exportdir %s: %r", hd tl argv));
	spawn io(pfd[1], sys->fildes(1));
	spawn io(sys->fildes(0), pfd[1]);
}

io(rfd, wfd: ref Sys->FD)
{
	buf := array[MAXMSG+FDATA] of byte;
	have := 0;
	while ((n := sys->read(rfd, buf[have:], len buf - have)) > 0) {
		# see if we have a complete message yet
		have += n;
		size := msgsize(buf[:have]);
		if (have < size)
			continue;

		# set msg to possibly resized original message
		msg := buf[:size];
		resize := conv[int msg[0]].resize;
		if (resize > 0)
			msg = (array[size+resize] of {* => byte 0})[:] = msg;
		else
			msg = msg[:size+resize];

		# handle special cases where reply is immediate
		fd := wfd;
		case int msg[0] {
		Tclwalk =>
			msg[T+TAG:] = array of byte "clwalk not implemented";
			fd = rfd;
		Tsession =>
			fd = rfd;
		}

		# alter and send; shift any remaining bytes down
		msg[0] = byte conv[int msg[0]].msgtype;
		if (sys->write(fd, msg, len msg) != len msg)
			hangup(sprint("write: %r"));
		if (size < have)
			buf[:] = buf[size:have];
		have -= size;
	}
	if (n < 0)
		hangup(sprint("read: %r"));
	else
		hangup("read: eof");
}

# return size of message in buffer, including variable data
msgsize(buf: array of byte): int
{
	size := conv[int buf[0]].size;
	if (size == 0)
		hangup(sprint("unknown message type: %d", int buf[0]));
	pos := conv[int buf[0]].countpos;
	if (pos != 0 && len buf >= size) {
		count := int buf[pos] | (int buf[pos+1] << 8);
		if (count > FDATA)
			hangup(sprint("count out of bounds: %d", count));
		size += count;
	}
	return size;
}

hangup(err: string)
{
	sys->fprint(sys->fildes(2), "9export: %s\n", err);
	ctl := sys->open("#p/"+string sys->pctl(0, nil)+"/ctl", Sys->OWRITE);
	sys->fprint(ctl, "killgrp");
	exit;
}
