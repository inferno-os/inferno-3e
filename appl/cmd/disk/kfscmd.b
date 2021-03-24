implement Kfscmd;

#
#	Module:		kfscmd
#	Author:		Eric Van Hensbergen (ericvh@lucent.com)
#	Purpose:	Easy interface to #Kcons/kfscons
#		
#	Usage:		kfscmd [-n<fsname>] <cmd>
#

include "sys.m";
	sys:	Sys;

include "draw.m";
include "arg.m";
	arg: Arg;

Kfscmd: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

kfscons: con "#Kcons/kfscons";
	stderr:	ref Sys->FD;

usage()
{
	sys->fprint(stderr,"\tkfscmd: usage:\n");
	sys->fprint(stderr,"\t\tkfscmd [-n<fsname>] <cmd>\n");
	exit;
}

init(nil: ref Draw->Context, argv: list of string)
{
	cfs: string;

	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);

	arg = load Arg Arg->PATH;
	if (arg == nil)
		sys->fprint(stderr, "kfscmd: can't load %s: %r", Arg->PATH);

	arg->init(argv);
	while((c := arg->opt()) != 0)
		case c {
		'n' =>
			cfs = arg->arg();
			if(cfs == nil)
				usage();
		* =>
			usage();
		}
	argv = arg->argv();
	if(len argv != 1) 
		usage();

	dfd := sys->open(kfscons,Sys->OWRITE);
	if(dfd == nil){
		sys->fprint(stderr,"kfscmd: can't open %s: %r\n", kfscons);
		exit;
	}
	if (cfs != nil && sys->fprint(dfd, "cfs %s\n", cfs) < 0){
		sys->fprint(stderr, "kfscmd: can't cfs to %s: %r\n", cfs);
		exit;
	}
	if(sys->fprint(dfd, "%s\n", hd argv) < 0)
		sys->fprint(stderr, "kfscmd: %s: %r\n", hd argv);
}
