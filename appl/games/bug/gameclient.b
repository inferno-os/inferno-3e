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
GAMESRVPATH: con "./gamesrv.dis";

GAMEPORT: con "3242";
GAMEDIR: con "/n/remote";
DEFAULTSRV: con "forza.vitanuova.com";
DEFAULTLOCALSRV: con "tcp!*!" + GAMEPORT;
PASSWORD: con "gameserver";
SIGNER: con "tcp!" + DEFAULTSRV + "!6660";

usernames: array of string;

clients: array of ref Client;
games: array of ref Game;

username: string;
finished := 0;

configcmds := array[] of {
"frame .top",
"menubutton .top.m -text {New game} -menu .top.m.menu",
"menu .top.m.menu",
"frame .g",
"frame .main",
"frame .c",
"scrollbar .c.scroll -orient vertical -command {.c.clients yview}",
"listbox .c.clients -yscrollcommand {.c.scroll set} -width 15w",
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

	local := 0;
	if (argv != nil && tl argv != nil && (hd tl argv)[0] == '-') {
		if (hd tl argv == "-l")
			local = 1;
		else {
			sys->fprint(stderr(), "usage: gameclient [-l]\n");
			sys->raise("fail:usage");
		}
	}

	wmlib->init();
	auth->init();
	commandline->init();
	dividers->init();
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
	cmd(win, "update");
	lctxt := ref Context(win, chat);

	for (;;) alt {
	c := <-ucmd =>
		(n, toks) := sys->tokenize(c, " ");
		case hd toks {
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
			sys->unmount(nil, "/n/remote");
			sys->print("killgrp\n");
			sys->fprint(sys->open("/prog/" + string sys->pctl(0, nil) + "/ctl", Sys->OWRITE), "killgrp");
			sys->print("done kill\n");
			exit;
			sys->print("exited\n");
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
		if (ok == -1)
			sys->fprint(stderr(), "gameclient: cannot find client of type '%s'\n", hd toks);
	}
}

notice(win: ref Tk->Toplevel, s: string)
{
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

mountgame(ctxt: ref Draw->Context, local: int)
{
	startserver(chan of int, ctxt, 1, nil);
}

startserver(sync: chan of int, ctxt: ref Draw->Context, local: int, addr: string)
{
#	sys->pctl(Sys->NEWFD, 0::1::2::nil);
	srv := load Command GAMESRVPATH;
	srv->init(nil, GAMESRVPATH :: "-l" :: GAMEDIR :: nil);
}

panic(s: string)
{
	sys->fprint(stderr(), "cards: panic: %s\n", s);
	sys->raise("panic");
}

showtk := 0;
cmd(top: ref Tk->Toplevel, s: string): string
{
	return nil;
	if (showtk)
		sys->print("%s\n", s);
	e := tk->cmd(top, s);
	if (e != nil && e[0] == '!')
		sys->fprint(stderr(), "tk error %s on '%s'\n", e, s);
	return e;
}
