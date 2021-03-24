implement Server2;

# a file server that serves one append-only file
# handling styx messages directly using styxlib,
# rather than using file2chan.

include "sys.m";
	sys: Sys;
include "draw.m";
include "styxlib.m";
	styx: Styxlib;
	Styxserver, Dirtab, Rmsg, Tmsg, Chan,
	Eperm, Ebadfid : import styx;
include "arg.m";

Server2: module {
	init: fn(nil: ref Draw->Context, argv: list of string);
};

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	stderr := sys->fildes(2);
	styx = load Styxlib Styxlib->PATH;
	arg := load Arg Arg->PATH;
	arg->init(argv);
	mntflag := Sys->MREPL;
	cflag := 0;
	# file servers conventionally take the same flags as mount(1)
	while ((c := arg->opt()) != 0) {
		case c {
		'a' =>
			mntflag = Sys->MAFTER;
		'b' =>
			mntflag = Sys->MBEFORE;
		'r' =>
			mntflag = Sys->MREPL;
		'c' =>
			cflag = Sys->MCREATE;
		* =>
			sys->fprint(stderr, "usage: server2 [-abc] mountpoint\n");
			sys->raise("fail:usage");
		}
	}
	argv = arg->argv();
	arg = nil;
	if (argv == nil) {
		sys->fprint(stderr, "usage: server2 [-abc] mountpoint\n");
		sys->raise("fail:usage");
	}
	mountpt := hd argv;

	sys->pctl(Sys->FORKFD, nil);

	# create a pipe for mounting. one end of the pipe we serve styx messages
	# on, and the other is given to the kernel to mount.
	# this technique makes the served files immediately visible
	# in the namespace. alternatively, we could start the file server
	# on a network connection, or the standard input, and assume
	# that the other end is mounted in some remote namespace.
	fds := array[2] of ref Sys->FD;
	sys->pipe(fds);
	(tchan, srv) := Styxserver.new(fds[0]);
	fds[0] = nil;

	# the sync channel is to ensure that the namespace
	# fork has happened before we actually do the mount.
	sync := chan of int;
	spawn serveloop(tchan, srv, sync);
	<-sync;
	if(sys->mount(fds[1], mountpt, mntflag | cflag, nil) == -1) {
		sys->fprint(stderr, "dbfs: mount failed: %r\n");
		sys->raise("bad mount");
	}
}

Qfile: con 1;
# for this simple server, we use a static array of the
# files we will serve. in a more complex (e.g. multilevel)
# server, the directory entries would probably be generated
# dynamically.
dirtab := array[] of {
	Dirtab("srvfile", (Qfile, 0), big 0, 8r600)
};

serveloop(tchan: chan of ref Tmsg, srv: ref Styxserver, sync: chan of int)
{
	devgen := styx->dirgenmodule();
	sys->pctl(Sys->FORKNS, nil);
	sync <-= 1;
	stderr := sys->fildes(2);
	contents := "";
	# loop until we get EOF on the pipe, reading
	# T-messages (requests) and replying to them
	# as appropriate.
	for (;;) {
		gm := <-tchan;
		if (gm == nil)
			exit;

		pick m := gm {
		Readerror =>
			sys->fprint(stderr, "server2: fatal read error: %s\n", m.error);
			exit;
		Nop =>
			srv.reply(ref Rmsg.Nop(m.tag));
		Flush =>
			srv.devflush(m);
		Clone =>
			srv.devclone(m);
		Walk =>
			srv.devwalk(m, devgen, dirtab);
		Open =>
			srv.devopen(m, devgen, dirtab);
		Create =>
			srv.reply(ref Rmsg.Error(m.tag, Eperm));
		Read =>
			c := srv.fidtochan(m.fid);
			if (c == nil) {
				srv.reply(ref Rmsg.Error(m.tag, Ebadfid));
				break;
			}
			if (c.isdir()){
				srv.devdirread(m, devgen, dirtab);
				break;
			}
			d := array of byte contents;
			(offset, count) := (int m.offset, m.count);
			if (offset > len d)
				offset = len d;
			if (offset + count > len d)
				count = len d - offset;

			# reply to the read request with requested data.
			srv.reply(ref Rmsg.Read(m.tag, m.fid, d[offset:offset + count]));
		Write =>
			c := srv.fidtochan(m.fid);
			if(c == nil || !c.open){
				srv.reply(ref Rmsg.Error(m.tag, Ebadfid));
				break;
			}
			if(c.qid.path != Qfile){
				srv.reply(ref Rmsg.Error(m.tag, Eperm));
				break;
			}
			contents += string m.data;
			srv.reply(ref Rmsg.Write(m.tag, m.fid, len m.data));
		Clunk =>
			srv.devclunk(m);
		Stat =>
			srv.devstat(m, devgen, dirtab);
		Remove =>
			srv.reply(ref Rmsg.Error(m.tag, Eperm));
		Wstat =>
			srv.reply(ref Rmsg.Error(m.tag, Eperm));
		Attach =>
			srv.devattach(m);
		}
	}
}
