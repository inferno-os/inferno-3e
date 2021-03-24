implement Gameclient;
include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;
	Point, Rect, Display, Image: import draw;
include "tk.m";
	tk: Tk;
include "wmlib.m";
	wmlib: Wmlib;
include "gameclient.m";
include "keyring.m";
	keyring: Keyring;
include "security.m";
	login: Login;
	auth: Auth;
include "sh.m";
include "commandline.m";
	commandline: Commandline;
	Cmdline: import commandline;
include "dividers.m";
	dividers: Dividers;
	Divider: import dividers;
include "readdir.m";
	readdir: Readdir;
include "popup.m";
	popup: Popup;
include "arg.m";

Gameclient: module {
	init:   fn(ctxt: ref Draw->Context, argv: list of string);
};

selfid := -1;
selfname: string;

Client: adt {
	id: int;
	name: string;
};

Player: adt {
	id: int;
	gameid: int;
	client: ref Client;
};

Game: adt {
	id: int;
	name: string;
	client: list of string;
};

Context: adt {
	win: ref Tk->Toplevel;
	chat: ref Commandline->Cmdline;
};

algorithms := array[] of {
	"none", "sha", "md4", "md5",
	"rc4", "rc4_40", "rc4_128", "rc4_256",
	"des_56_cbc", "des_56_ecb", "ideacbc", "ideaecb"
};

CLIENTS: con "/dis/games/clients";
GAMESRVPATH: con "/dis/games/gamesrv.dis";

GAMEPORT: con "3242";
GAMEDIR: con "/n/remote";
DEFAULTADDR: con "$GAMES";
PASSWORD: con "gameserver";

clients: array of ref Client;
games: array of ref Game;

username: string;
finished := 0;

defaultuser := "";
defaultsrv := DEFAULTADDR;
defaultsigner := DEFAULTADDR;
localaddr := "tcp!*!" + GAMEPORT;

configcmds := array[] of {
"frame .top",
"menubutton .top.m -text {New game} -menu .top.m.menu",
"menu .top.m.menu",
"frame .g",
"frame .main",
"frame .c",
"scrollbar .c.scroll -orient vertical -command {.c.clients yview}",
"listbox .c.clients -yscrollcommand {.c.scroll set} -width 12w",
"frame .x",
"pack .top.m -side left",
"pack .top -in .main -side top -fill x",
"pack .g -in .main -side top -fill x",
"pack .c.scroll -side left -fill y",
"pack .c.clients -side top -fill both -expand 1",
"pack .main .c -in .x -side left -expand 1 -fill both",
};

stderr(): ref Sys->FD
{
	return sys->fildes(2);
}

procname(s: string)
{
#	sys->procname(sys->procname(nil) + " " + s);
}

badmodule(p: string)
{
	sys->fprint(stderr(), "gameclient: cannot load %s: %r\n", p);
	sys->raise("fail:bad module");
}

usage()
{
	sys->fprint(stderr(), "usage: gameclient [-l] [-u user] [-s srvaddr]\n");
	sys->raise("fail:usage");
}

init(ctxt: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	tk = load Tk Tk->PATH;
	keyring = load Keyring Keyring->PATH;
	wmlib = load Wmlib Wmlib->PATH;
	if (wmlib == nil)
		badmodule(Wmlib->PATH);
	auth = load Auth Auth->PATH;
	if (auth == nil)
		badmodule(Auth->PATH);
	commandline = load Commandline Commandline->PATH;
	if (commandline == nil)
		badmodule(Commandline->PATH);
	dividers = load Dividers Dividers->PATH;
	if (dividers == nil)
		badmodule(Dividers->PATH);
	readdir = load Readdir Readdir->PATH;
	if (readdir == nil)
		badmodule(Readdir->PATH);
	popup = load Popup Popup->PATH;
	if (popup == nil)
		badmodule(Popup->PATH);
	arg := load Arg Arg->PATH;
	if (arg == nil)
		badmodule(Arg->PATH);

	local := 0;
	arg->init(argv);
	while ((opt := arg->opt()) != 0) {
		case opt {
		'l' =>
			local = 1;
		's' =>
			defaultsrv = arg->arg();
		'u' =>
			defaultuser = arg->arg();
		* =>
			usage();
		}
	}

	wmlib->init();
	auth->init();
	commandline->init();
	dividers->init();
	popup->init();
	sys->pctl(Sys->NEWPGRP|Sys->FORKNS, nil);
	gameclient(ctxt, local);
}

gameclient(ctxt: ref Draw->Context, local: int)
{
	fd := sys->open(GAMEDIR + "/players", Sys->ORDWR);
	if (fd == nil) {
		mountgame(ctxt, local);
		fd = sys->open(GAMEDIR + "/players", Sys->ORDWR);
	}
	if (fd == nil) {
		sys->fprint(stderr(), "gameclient: game server not available\n");
		sys->raise("fail:errors");
	}

	updatech := chan of string;
	spawn readplayers(fd, updatech);

	(win, winctl) := wmlib->titlebar(ctxt.screen, nil,
		"Games", Wmlib->Appl);
	ucmd := chan of string;
	tk->namechan(win, ucmd, "ucmd");
	srvcmd := chan of string;
	for (i := 0; i < len configcmds; i++)
		cmd(win, configcmds[i]);
	(chat, chatch) := Cmdline.new(win, ".chat", nil);
	cmd(win, ".chat.t configure -width 50w");
	(div, divctl) := Divider.new(win, ".div", ".x" :: ".chat" :: nil, Dividers->NS);
	tk->namechan(win, divctl, "divctl");
	cmd(win, "bind . <Configure> {send divctl config}");
	cmd(win, "pack .div -side top -fill both -expand 1");
	cmd(win, "pack propagate . 0");
	fittoscreen(win);
	cmd(win, "update");
	lctxt := ref Context(win, chat);

	for (;;) alt {
	c := <-ucmd =>
		(n, toks) := sys->tokenize(c, " ");
		case hd toks {
		"new" =>
			name := hd tl toks;
			newgame(win, "new", "create " + concat(tl tl toks), ctxt, name :: nil);
		"join" =>
			# join gameid
			game := games[int hd tl toks];
			newgame(win, string game.id, nil, ctxt, game.client);
		}
	c := <-divctl =>
		if (c == "config") {
			cmd(win, ".div configure -width [.div cget -actwidth] -height [.div cget -actheight]");
			cmd(win, "update");
		} else
			div.event(c);
	c := <-winctl =>
		if (c == "exit") {
			finished = 1;
			# tell server we're finished, as on some systems we're unable to
			# kill readplayers()
			sys->write(fd, array[0] of byte, 0);
			fd = nil;
#			sys->unmount(nil, "/n/remote");
		}
		wmlib->titlectl(win, c);
	upd := <-updatech =>
		if (upd == nil)
			exit;
		update(lctxt, upd);
		cmd(win, "update");
	e := <-chatch =>
		for (m := chat.event(e); m != nil; m = tl m)
			sys->fprint(fd, "%s\n", hd m);
	}
}

newgame(win: ref Tk->Toplevel, f, inits: string, ctxt: ref Draw->Context, args: list of string)
{
	# XXX security: eliminate slashes...
	path := CLIENTS + "/" + hd args + ".dis";
	mod := load Clientmod path;
	if (mod == nil) {
		notice(win, sys->sprint("cannot find client module %s: %r", path));
		return;
	}
	fd := sys->open(GAMEDIR + "/" + f, Sys->ORDWR);
	if (fd == nil) {
		notice(win, sys->sprint("cannot open %s/%s: %r", GAMEDIR, f));
		return;
	}
	if (inits != nil && sys->fprint(fd, "%s\n", inits) == -1) {
		notice(win, sys->sprint("failed to write initialisation: %r"));
		return;
	}
	sync := chan of int;
	spawn clientmod(mod, fd, ctxt, args, sync);
	<-sync;
}

clientmod(mod: Clientmod, fd: ref Sys->FD,
		ctxt: ref Draw->Context, args: list of string, sync: chan of int)
{
	sys->pctl(Sys->FORKFD|Sys->FORKNS|Sys->NEWPGRP, nil);
	sync <-= 1;
	sys->chdir("clients");
	sys->dup(fd.fd, 0);
	fd = nil;
	wfd := sys->open("/prog/" + string sys->pctl(0, nil) + "/wait", Sys->OREAD);
	spawn runclient(mod, ctxt, args, selfid);
	buf := array[Sys->ATOMICIO] of byte;
	n := sys->read(wfd, buf, len buf);
	sys->print("game process '%s' exited: %s\n", hd args, string buf[0:n]);
}

runclient(mod: Clientmod, ctxt: ref Draw->Context, args: list of string, selfid: int)
{
	procname(hd args);
	mod->client(ctxt, args, selfid);
}

update(ctxt: ref Context, s: string)
{
	(win, chat) := *ctxt;
	(n, toks) := sys->tokenize(s, " ");
	if (toks == nil)
		return;
	sys->print("got update '%s'\n", s);
	ucmd := hd toks;
	toks = tl toks;
	case ucmd {
	"chat" =>
		clientid := int hd toks;
		msg := s[5 + len hd toks + 1:];		# "chat 9 ...."
		chat.addtext(clients[clientid].name + " says: " + msg + "\n");
	"clientid" or
	"join" =>
		# clientid clientid name
		# join clientid name
		clientid := int hd toks;
		name := hd tl toks;
		if (clientid >= len clients) {
			newclients := array[clientid + 1] of ref Client;
			newclients[0:] = clients;
			clients = newclients;
		}
		clients[clientid] = ref Client(clientid, name);
		if (ucmd == "clientid")
			(selfid, selfname) = (clientid, name);
		showclients(win);
	"leave" =>
		# leave clientid
		clients[int hd toks] = nil;
		showclients(win);
	"joingame" =>
		# joingame gameid clientid playerid
		(gameid, clientid, playerid) := (int hd toks, int hd tl toks, int hd tl tl toks);
		w := playerw(gameid, playerid);
		cmd(win, "label " + w + " -text '    " + clients[clientid].name + " " + string playerid);
		cmd(win, "pack " + w + " -side top -anchor w");
	"leavegame" =>
		# leavegame gameid playerid
		gameid := int hd toks;
		playerid := int hd tl toks;
		cmd(win, "destroy " + playerw(gameid, playerid));
	"creategame" =>
		# creategame gameid name client...
		gameid := int hd toks;
		name := hd tl toks;
		client := tl tl toks;
		if (gameid >= len games) {
			newgames := array[gameid + 1] of ref Game;
			newgames[0:] = games;
			games = newgames;
		}
		g := games[gameid] = ref Game(gameid, name, client);
		w := gamew(gameid);
		cmd(win, "frame " + w + " -relief sunken -bd 5");
		cmd(win, "frame " + w + ".f");
		cmd(win, "label " + w + ".f.l -text '" + string g.id + ". " + g.name);
		cmd(win, "button " + w + ".f.b -text Join -command {send ucmd join " + string g.id + "}");
		cmd(win, "pack "+w+".f.l "+w+".f.b -side left");
		cmd(win, "pack "+w+".f -side top -anchor w");
		cmd(win, "pack "+w+" -side top -anchor w -fill x");
	"delgame" =>
		# delgame gameid
		gameid := int hd toks;
		cmd(win, "destroy " + gamew(gameid));

		games[gameid] = nil;
	"gametype" =>
		# gametype client arg...
		(ok, nil) := sys->stat(CLIENTS + "/" + hd toks + ".dis");
		if (ok == -1) {
#			sys->fprint(stderr(), "gameclient: cannot find client of type '%s'\n", hd toks);
		} else
			cmd(win, ".top.m.menu add command -label " + wmlib->tkquote(concat(tl toks)) +
				" -command {send ucmd new " + concat(toks) + "}");
	}
}

showclients(win: ref Tk->Toplevel)
{
	cmd(win, ".c.clients delete 0 end");
	for (i := 0; i < len clients; i++)
		if (clients[i] != nil)
			cmd(win, ".c.clients insert end '" + string i + ". " + clients[i].name);
}

gamew(gameid: int): string
{
	return ".g." + string gameid;
}

playerw(gameid, playerid: int): string
{
	return gamew(gameid) + "." + string playerid;
}

readplayers(fd: ref Sys->FD, updatech: chan of string)
{
	procname("readplayers");
	buf := array[Sys->ATOMICIO] of byte;
	while ((n := sys->read(fd, buf, len buf)) > 0) {
		(nil, lines) := sys->tokenize(string buf[0:n], "\n");
		for (; lines != nil; lines = tl lines)
			updatech <-= hd lines;
	}
	if (n < 0) {
		sys->fprint(stderr(), "gameclient: error reading players (fd %d): %r\n", fd.fd);
		sys->raise("panic");
	}
	if (!finished)
		updatech <-= nil;
}

Hashalg: con "sha";
Cryptalg: con "rc4_40";
Defaulthash: con 1;
Defaultcrypt: con 0;

wUSER, wSERVER, wHASH, wCRYPT, wSTATUS,
wNEWUSER, wSIGNER, wSRVUSER, wSRVADDRESS,
wSRVUSERFRAME, wUSERFRAME,
wNUMW: con iota;
w := array[wNUMW] of string;

connectcmds := array[] of {
"[ .con",			# connect
	"frame $",
	"[ .m",
		"frame $",
		string wHASH + " $.hash",
		string wCRYPT + " $.crypt",
		"checkbutton $.hash -text {Tamperproof} -variable hash",
		"checkbutton $.crypt -text {Encrypt} -variable crypt",
		"pack $.hash $.crypt -side left",
	"]",
	"[ .user",
		"frame $",
		string wUSERFRAME + " $.e",
		"label $.l -text {Username:}",
		"frame $.e",
		"pack $.l -side left",
		"pack $.e -side left -fill x -expand 1",
	"]",
	"[ .srv",
		"frame $",
		string wSERVER + " $.e",
		"label $.l -text {Server:}",
		"entry $.e -width 12w",
		"bind $.e <Key-\n> {send ucmd con}",
		"pack $.l -side left",
		"pack $.e -side left -fill x -expand 1",
	"]",
	"[ .buts",
		"frame $",
		string wSTATUS + " $.status",
		"label $.status",
		"button $.b2 -text {Connect} -command {send ucmd con} -bd 4",
		"pack $.b2 -side right",
		"pack $.status -side left -expand 1",
	"]",
	"pack $.m $.user $.srv -side top -fill x",
	"pack $.buts -side bottom -fill x",
"]",
"[ .new",		# new user
	"frame $",
	"[ .u",
		string wNEWUSER + " $.e",
		"frame $",
		"label $.l -text {New username:}",
		"entry $.e -width 12w",
		"bind $.e <Key-\n> {send ucmd new}",
		"pack $.l -side left",
		"pack $.e -side left -fill x -expand 1",
	"]",
	"[ .s",
		string wSIGNER + " $.e",
		"frame $",
		"label $.l -text {Signer:}",
		"entry $.e -width 12w",
		"bind $.e <Key-\n> {send ucmd new}",
		"pack $.l -side left",
		"pack $.e -side left -fill x -expand 1",
	"]",
	"[ .buts",
		"frame $",
		"button $.b2 -text {Make new user} -command {send ucmd new} -bd 4",
		"pack $.b2 -side right",
	"]",
	"pack $.u $.s -side top -fill x",
	"pack $.buts -side bottom -fill x",
"]",
"[ .srv",		# start server
	"frame $",
	"[ .u",
		string wSRVUSERFRAME + " $.e",
		"frame $",
		"label $.l -text {Server username:}",
		"frame $.e",
		"pack $.l -side left",
		"pack $.e -side left -fill x -expand 1",
	"]",
	"[ .s",
		string wSRVADDRESS + " $.e",
		"frame $",
		"label $.l -text {Server address:}",
		"entry $.e -width 12w",
		"bind $.e <Key-\n> {send ucmd srv}",
		"pack $.l -side left",
		"pack $.e -side left -fill x -expand 1",
	"]",
	"[ .buts",
		"frame $",
		"button $.b2 -text {Start server} -command {send ucmd srv} -bd 4",
		"pack $.b2 -side right",
	"]",
	"pack $.u $.s -side top -fill x",
	"pack $.buts -side bottom -fill x",
"]",
};

CONNECT, NEWUSER, STARTSRV: con iota;

tabs := array[] of {
	CONNECT => ("Connect", ".tabs.con"),
	NEWUSER => ("New user", ".tabs.new"),
	STARTSRV => ("Start server", ".tabs.srv"),
};

fieldval(win: ref Tk->Toplevel, w: string): string
{
	return cmd(win, w + " get");
}

setfield(win: ref Tk->Toplevel, w: string, val: string)
{
	cmd(win, w + " delete 0 end");
	cmd(win, w + " insert 0 '" + val);
}

mountgame(ctxt: ref Draw->Context, local: int)
{
	if (local) {
		startserver(ctxt, 1, nil);
		return;
	}
	(win, winctl) := wmlib->titlebar(ctxt.screen, "-font /fonts/lucidasans/unicode.7.font", "Connect to game server",
			Wmlib->Appl);

	ucmd := chan of string;
	tk->namechan(win, ucmd, "ucmd");

	usernames := l2a(getdir("/usr/" + user() + "/keyring/games"));

	cmd(win, "frame .tabs");
	docmds(win, connectcmds, ".tabs", w);
	w[wSRVUSER] = w[wSRVUSERFRAME] + ".b";
	w[wUSER] = w[wUSERFRAME] + ".b";

	srvuserch := popup->mkbutton(win, w[wSRVUSER], usernames, 0);
	cmd(win, "pack " + w[wSRVUSER] + " -side left");

	userch := popup->mkbutton(win, w[wUSER], usernames, 0);
	cmd(win, "pack " + w[wUSER] + " -side left");

	setfield(win, w[wSERVER], defaultsrv);
	if (Defaulthash)
		cmd(win, w[wHASH] + " select");
	if (Defaultcrypt)
		cmd(win, w[wCRYPT] + " select");
	setfield(win, w[wSIGNER], defaultsigner);
	setfield(win, w[wSRVADDRESS], localaddr);

	if (defaultuser != nil) {
		n: int;
		(usernames, n) = popup->add(usernames, defaultuser);
		popup->changebutton(win, w[wSRVUSER], usernames, n);
		popup->changebutton(win, w[wUSER], usernames, n);
	} else if (len usernames == 0) {
		defaultuser = user();
		setfield(win, w[wNEWUSER], defaultuser);
	} else
		defaultuser = usernames[0];

	currid := 0;
	seltab(win, currid);
	tabch := wmlib->mktabs(win, ".t", tabs, currid);
	cmd(win, "pack .t");
	cmd(win, "pack propagate . 0");

	if (usernames == nil || !s_in_a(defaultuser, usernames)) {
		currid = wmlib->tabsctl(win, ".t", tabs, currid, string NEWUSER);
		seltab(win, currid);
	}
	
	cmd(win, "update");
	hash, crypt: string;
	for (;;) alt {
	c := <-tabch =>
		currid = wmlib->tabsctl(win, ".t", tabs, currid, c);
		seltab(win, currid);
		cmd(win, "update");
	c := <-winctl =>
		wmlib->titlectl(win, c);
	c := <-srvuserch =>
		popup->event(win, c, usernames);
		cmd(win, "update");
	c := <-userch =>
		popup->event(win, c, usernames);
		cmd(win, "update");
	c := <-ucmd =>
		(n, toks) := sys->tokenize(c, " ");
		arg := "";
		if (tl toks != nil)
			arg = hd tl toks;
		err := "";
		case hd toks {
		"new" =>
			u := fieldval(win, w[wNEWUSER]);
			err = newuser(u, fieldval(win, w[wSIGNER]));
			if (err == nil) {
				n: int;
				(usernames, n) = popup->add(usernames, u);
				popup->changebutton(win, w[wUSER], usernames, n);
				popup->changebutton(win, w[wSRVUSER], usernames, n);
				setfield(win, w[wSRVADDRESS], fieldval(win, w[wSIGNER]));
				currid = wmlib->tabsctl(win, ".t", tabs, currid, string CONNECT);
				seltab(win, currid);
			}
		"srv" =>
			err = startserver(ctxt, 0, cmd(win, w[wSRVADDRESS] + " get"));
			if (err == nil) {
				currid = wmlib->tabsctl(win, ".t", tabs, currid, string CONNECT);
				seltab(win, currid);
			}
		"con" =>
			hash := crypt := "";
			if (int cmd(win, "variable hash"))
				hash = Hashalg;
			if (int cmd(win, "variable crypt"))
				crypt = Cryptalg;
			statusch := chan of string;
			cmd(win, "cursor -bitmap cursor.wait");
			spawn statusproc(win, winctl, statusch);
			err = connect(cmd(win, w[wSERVER] + " get"),
					cmd(win, w[wUSER] + " cget -text"), hash, crypt, statusch);
			statusch <-= nil;
			cmd(win, "cursor -default");
			if (err == nil)
				return;
		}
		cmd(win, "update");
		if (err != nil)
			notice(win, err);
	}
}

l2a(l: list of string): array of string
{
	a := array[len l] of string;
	for (i := 0; i < len a; i++)
		(a[i], l) = (hd l, tl l);
	return a;
}

s_in_a(s: string, a: array of string): int
{
	for (i := 0; i < len a; i++)
		if (s == a[i])
			return 1;
	return 0;
}

seltab(win: ref Tk->Toplevel, t: int)
{
	case t {
	NEWUSER =>
		cmd(win, w[wNEWUSER] + " selection range 0 end");
		cmd(win, "focus " + w[wNEWUSER]);
	}
}

statusproc(win: ref Tk->Toplevel, winctl, statusch: chan of string)
{
	for (;;) alt {
		s := <-statusch =>
			cmd(win, w[wSTATUS] + " configure -text '" + s);
			cmd(win, "update");
			if (s == nil)
				return;
		c := <-winctl =>
			wmlib->titlectl(win, c);
	}
}

keyfile(uid: string): string
{
	return "/usr/" + user() + "/keyring/games/" + uid;
}

newuser(uid, signer: string): string
{
	login := load Login Login->PATH;
	if (login == nil)
		return sys->sprint("cannot load %s: %r", Login->PATH);
	signer = netmkaddr(signer, "net", "6660");
	(err, cert) := login->login(uid, PASSWORD, signer);
	if (err != nil)
		return "login: " + err;
#	sys->print("server public key:");
#	sys->print("%s\nend server public key\n", keyring->pktostr(cert.spk));
#	if (keyring->pktostr(cert.spk) != signerpk)
#		return "server public key does not match";
	certd := array of byte keyring->certtostr(cert.cert);
	# XXX make keyring dir?
	sys->create("/usr/" + user() + "/keyring/games", Sys->OREAD, Sys->CHDIR|8r700);
	kf := keyfile(uid);
	if (keyring->writeauthinfo(kf, cert) == -1)
		return sys->sprint("cannot create %s: %r\n", kf);
	return nil;
}

connect(addr, uid, hash, crypt: string, statusch: chan of string): string
{
	# XXX change to use auth directly, so we know
	# the identity of the user at the other end.
	# we could check for special identity "server" to
	# make sure we were actually connected to the server program.

	alg := "";
	if (hash != nil && crypt != nil)
		alg = hash + " " + crypt;		# XXX " " should be "/" but auth->server is broke.
	else
		alg = hash + crypt;
	addr = netmkaddr(addr, "tcp", GAMEPORT);
	cert := keyring->readauthinfo("/usr/" + user() + "/keyring/games/" + uid);
	if (cert == nil)
		return sys->sprint("cannot read certificate: %r");
	statusch <-= "dialling";
	(ok, c) := sys->dial(addr, nil);
	if (ok == -1)
		return sys->sprint("cannot connect to %s: %r", addr);
	statusch <-= "authenticating";
	(fd, err) := auth->client(alg, cert, c.dfd);
	if (fd == nil)
		return "authentication failed: " + err;
	statusch <-= "remote user is " + err  + "; mounting";
	if (sys->mount(fd, "/n/remote", Sys->MREPL, nil) == -1)
		return sys->sprint("mount failed: %r\n");
	return nil;
}

getdir(path: string): list of string
{
	(d, n) := readdir->init(path, Readdir->DESCENDING|Readdir->COMPACT);
	if (n == -1) {
		sys->fprint(stderr(), "gameclient: cannot read %s: %r\n", path);
		return nil;
	}
	e: list of string;
	for (i := 0; i < n; i++)
		if ((d[i].mode & Sys->CHDIR) == 0)
			e = d[i].name :: e;
	return e;
}

# XXX should take a username argument too.
startserver(ctxt: ref Draw->Context, local: int, addr: string): string
{
	sh := load Sh Sh->PATH;
	if (sh == nil)
		return sys->sprint("cannot load %s: %r", Sh->PATH);

	args: list of string;
	if (local)
		args = "-l" :: GAMEDIR :: nil;
	else {
		args = addr :: nil;
		for (i := 0; i < len algorithms; i++)
			args = "-a" :: algorithms[i] :: args;
	}
	args = "{$* >[2=1] | {wm/logwindow -eg 'game server'&}}" :: GAMESRVPATH :: args;
	if (sh->run(ctxt, args) != nil)
		return "cannot start server";
	return nil;
}

netmkaddr(addr, net, svc: string): string
{
	if(net == nil)
		net = "net";
	(n, l) := sys->tokenize(addr, "!");
	if(n <= 1){
		if(svc== nil)
			return sys->sprint("%s!%s", net, addr);
		return sys->sprint("%s!%s!%s", net, addr, svc);
	}
	if(svc == nil || n > 2)
		return addr;
	return sys->sprint("%s!%s", addr, svc);
}

user(): string
{
	if (username != nil)
		return username;
	if ((fd := sys->open("/dev/user", sys->OREAD)) == nil)
		return "nobody";
	buf := array[128] of byte;
	if ((n := sys->read(fd, buf, len buf)) <= 0)
		return "nobody";
	username = string buf[0:n];
	return username;
}

expand(c: string, curr: string): string
{
	# XXX add possibility for literal '$'
	s := "";
	for (i := 0; i < len c; i++) {
		if (c[i] == '$')
			s += curr;
		else
			s[len s] = c[i];
	}
	return s;
}

docmds(win: ref Tk->Toplevel, cmds: array of string, curr: string, w: array of string)
{
	pushed: list of string;
	for (i := 0; i < len cmds; i++) {
		c := cmds[i];
		case c[0] {
		'[' =>
			pushed = curr :: pushed;
			curr += c[2:];
		']' =>
			(curr, pushed) = (hd pushed, tl pushed);
		'0' to '9' =>
			for (j := 0; j < len c; j++)
				if (c[j] == ' ')
					break;
			w[int c] = expand(c[j + 1:], curr);
		* =>
			cmd(win, expand(c, curr));
		}
	}
}

concat(v: list of string): string
{
	if (v == nil)
		return nil;
	s := hd v;
	for (v = tl v; v != nil; v = tl v)
		s += " " + hd v;
	return s;
}

notice(win: ref Tk->Toplevel, e: string)
{
	wmlib->dialog(win, nil, "Notice", e, 0, "Ok" :: nil);
}


panic(s: string)
{
	sys->fprint(stderr(), "cards: panic: %s\n", s);
	sys->raise("panic");
}

showtk := 0;
cmd(top: ref Tk->Toplevel, s: string): string
{
	if (showtk)
		sys->print("%s\n", s);
	e := tk->cmd(top, s);
	if (e != nil && e[0] == '!')
		sys->fprint(stderr(), "tk error %s on '%s'\n", e, s);
	return e;
}

fittoscreen(win: ref Tk->Toplevel)
{
	Point: import draw;
	if (win.image == nil || win.image.screen == nil)
		return;
	r := win.image.screen.image.r;
	scrsize := Point((r.max.x - r.min.x), (r.max.y - r.min.y));
	bd := int cmd(win, ". cget -bd");
	winsize := Point(int cmd(win, ". cget -actwidth") + bd * 2, int cmd(win, ". cget -actheight") + bd * 2);
	if (winsize.x > scrsize.x)
		cmd(win, ". configure -width " + string (scrsize.x - bd * 2));
	if (winsize.y > scrsize.y)
		cmd(win, ". configure -height " + string (scrsize.y - bd * 2));
	actr: Rect;
	actr.min = Point(int cmd(win, ". cget -actx"), int cmd(win, ". cget -acty"));
	actr.max = actr.min.add((int cmd(win, ". cget -actwidth") + bd*2,
				int cmd(win, ". cget -actheight") + bd*2));
	(dx, dy) := (actr.dx(), actr.dy());
	if (actr.max.x > r.max.x)
		(actr.min.x, actr.max.x) = (r.min.x - dx, r.max.x - dx);
	if (actr.max.y > r.max.y)
		(actr.min.y, actr.max.y) = (r.min.y - dy, r.max.y - dy);
	if (actr.min.x < r.min.x)
		(actr.min.x, actr.max.x) = (r.min.x, r.min.x + dx);
	if (actr.min.y < r.min.y)
		(actr.min.y, actr.max.y) = (r.min.y, r.min.y + dy);
	cmd(win, ". configure -x " + string actr.min.x + " -y " + string actr.min.y);
}
