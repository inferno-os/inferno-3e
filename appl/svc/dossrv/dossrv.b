implement XfsSrv;

include "draw.m";

include "sys.m";
	sys : Sys;

include "styx.m";

include "iotrack.m";

include "dossubs.m";

include "dosfs.m";
	dosfs : Dosfs;

XfsSrv: module
{
        init:   fn(ctxt: ref Draw->Context, argv: list of string);
        system:   fn(ctxt: ref Draw->Context, argv: list of string) : string;
};

usage(argv0: string, iscmd: int)
{
	sys->print("usage: %s [-v] [-S] [-F] [-c] [-s secpertrack] [-f devicefile] [-m mountpoint]\n", argv0);
	if (iscmd)
		exit;
}

init2(nil: ref Draw->Context, argv: list of string, iscmd: int): int
{
	sys = load Sys Sys->PATH;

	dosfs = load Dosfs Dosfs->PATH;
	if(dosfs == nil) {
		sys->print("failed to load %s: %r\n", Dosfs->PATH);
		return -1;
	}

	pipefd := array[2] of ref Sys->FD;
	argv0 := hd argv;
	argv = tl argv;
	chatty := 0;

	logfile := "";
	srvfile := "/n/dos"; 
	deffile := "";	# no default, for safety
	sect2trk := 0;

	while (argv!=nil) {
		case (hd argv) {
		"-v" =>
			chatty |= DosSubs->VERBOSE;
		"-S" =>
			chatty |= DosSubs->STYX_MESS;
		"-F" =>
			chatty |= DosSubs->FAT_INFO;
		"-c" =>
			chatty |= DosSubs->CLUSTER_INFO;
		"-s" =>
			if(tl argv != nil && (s := hd tl argv)[0] >= '0' && s[0] <= '9') {
				sect2trk = int s;
				argv = tl argv;
			} else {
				usage(argv0, iscmd);
				return -1;
			}
		"-l" =>
			if(tl argv != nil)
				logfile = hd tl argv;
			else {
				usage(argv0, iscmd);
				return -1;
			}
		"-f" =>
			if(tl argv !=nil) {
				deffile = hd tl argv;
				argv = tl argv;
			}
			else {
				usage(argv0, iscmd);
				return -1;
			}
		"-m" =>
			if(tl argv != nil) {
				srvfile= hd tl argv;
				argv = tl argv;
			}
			else {
				usage(argv0, iscmd);
				return -1;
			}
		* =>
			usage(argv0, iscmd);
			return -1;
		}
		argv = tl argv;
	}

	if(deffile == "" || srvfile == "") {
		usage(argv0, iscmd);
		return -1;
	}

	err := dosfs->init(deffile, logfile, chatty, sect2trk);
	if(err != nil){
		sys->fprint(sys->fildes(2), "dossrv: can't initialise dosfs module: %s\n", err);
		return -1;
	}

	if(sys->pipe(pipefd) < 0) {
		sys->fprint(sys->fildes(2), "dossrv: can't create pipe: %r\n");
		return -1;
	}

	dosfs->setup();

	spawn dosfs->dossrv(pipefd[1]);

	n := sys->mount(pipefd[0], srvfile, sys->MREPL|sys->MCREATE, deffile);
	if(n == -1) {
		sys->fprint(sys->fildes(2), "dossrv: mount %s: %r\n", srvfile);
		return -1;
	}

	sys->fprint(sys->fildes(2), "%s : mounted %s at %s\n", argv0, deffile, srvfile);

	return 0;
}

init(nil: ref Draw->Context, argv: list of string)
{
	init2(nil, argv, 0);
}

system(nil: ref Draw->Context, argv: list of string): string
{
	if (init2(nil, argv, 1) < 0)
		return "failed";
	return nil;
}
