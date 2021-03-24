implement WmSh;

include "sys.m";
	sys: Sys;
	FileIO: import sys;

include "draw.m";
	draw: Draw;
	Context, Rect: import draw;

include "tk.m";
	tk: Tk;

include "wmlib.m";
	wmlib: Wmlib;

include	"plumbmsg.m";
	plumbmsg: Plumbmsg;
	Msg: import plumbmsg;

include "workdir.m";

include "string.m";
	str: String;

include "arg.m";

WmSh: module
{
	init:	fn(ctxt: ref Draw->Context, args: list of string);
};

Command: type WmSh;

BSW:		con 23;		# ^w bacspace word
BSL:		con 21;		# ^u backspace line
EOT:		con 4;		# ^d end of file
ESC:		con 27;		# hold mode

HIWAT:	con 2000;	# maximum number of lines in transcript
LOWAT:	con 1500;	# amount to reduce to after high water

Name:	con "Shell";

Rdreq: adt
{
	off:	int;
	nbytes:	int;
	fid:	int;
	rc:	chan of (array of byte, string);
};

shwin_cfg := array[] of {
	"menu .m",
	".m add command -text Cut -command {send edit cut}",
	".m add command -text Paste -command {send edit paste}",
	".m add command -text Snarf -command {send edit snarf}",
	".m add command -text Send -command {send edit send}",
	"frame .b -bd 1 -relief ridge",
	"frame .ft -bd 0",
	"scrollbar .ft.scroll -width 14 -bd 2 -relief ridge -command {.ft.t yview}",
	"text .ft.t -bd 1 -relief flat -yscrollcommand {.ft.scroll set}",
	".ft.t tag configure sel -relief flat",
	"pack .ft.scroll -side left -fill y",
	"pack .ft.t -fill both -expand 1",
	"pack .Wm_t -fill x",
	"pack .b -anchor w -fill x",
	"pack .ft -fill both -expand 1",
	"pack propagate . 0",
	"focus .ft.t",
	"bind .ft.t <Key> {send keys {%A}}",
	"bind .ft.t <Control-d> {send keys {%A}}",
	"bind .ft.t <Control-h> {send keys {%A}}",
	"bind .ft.t <Control-w> {send keys {%A}}",
	"bind .ft.t <Control-u> {send keys {%A}}",
	"bind .ft.t <Button-1> +{grab set .ft.t; send but1 pressed}",
	"bind .ft.t <Double-Button-1> +{grab set .ft.t; send but1 pressed}",
	"bind .ft.t <ButtonRelease-1> +{grab release .ft.t; send but1 released}",
	"bind .ft.t <ButtonPress-2> {send but2 %X %Y}",
	"bind .ft.t <Motion-Button-2-Button-1> {}",
	"bind .ft.t <Motion-ButtonPress-2> {}",
	"bind .ft.t <ButtonPress-3> {send but3 pressed}",
	"bind .ft.t <ButtonRelease-3> {send but3 released %x %y}",
	"bind .ft.t <Motion-Button-3> {}",
	"bind .ft.t <Motion-Button-3-Button-1> {}",
	"bind .ft.t <Double-Button-3> {}",
	"bind .ft.t <Double-ButtonRelease-3> {}",
	"bind .m <ButtonRelease> {.m tkMenuButtonUp %x %y}",
};

rdreq: list of Rdreq;
menuindex := "0";
holding := 0;
plumbed := 0;
rawon := 0;
rawinput := "";
cwd := "";
width, height, font: string;
history := array[1024] of byte;
nhistory := 0;

events: list of string;
evrdreq: list of Rdreq;
winname: string;

badmod(p: string)
{
	sys->print("wm/sh: cannot load %s: %r\n", p);
	sys->raise("fail:bad module");
}

init(ctxt: ref Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	tk = load Tk Tk->PATH;

	wmlib = load Wmlib Wmlib->PATH;
	if (wmlib == nil)
		badmod(Wmlib->PATH);

	str = load String String->PATH;
	if (str == nil)
		badmod(String->PATH);

	arg := load Arg Arg->PATH;
	if (arg == nil)
		badmod(Arg->PATH);
	arg->init(argv);

	plumbmsg = load Plumbmsg Plumbmsg->PATH;

	sys->pctl(Sys->FORKNS | Sys->NEWPGRP | Sys->FORKENV, nil);

	wmlib->init();

	if(plumbmsg != nil && plumbmsg->init(1, nil, 0) >= 0){
		plumbed = 1;
		workdir := load Workdir Workdir->PATH;
		cwd = workdir->init();
	}

	shargs: list of string;
	while ((opt := arg->opt()) != 0) {
		case opt {
		'w' =>
			width = arg->arg();
		'h' =>
			height = arg->arg();
		'f' =>
			font = arg->arg();
		'c' =>
			a := arg->arg();
			if (a == nil) {
				sys->print("usage: wm/sh [-ilxvn] [-w width] [-h height] [-f font] [-c command] [file [args...]\n");
				sys->raise("fail:usage");
			}
			shargs = a :: "-c" :: shargs;
		'i' or 'l' or 'x' or 'v' or 'n' =>
			shargs = sys->sprint("-%c", opt) :: shargs;
		}
	}
	argv = arg->argv();
	for (; shargs != nil; shargs = tl shargs)
		argv = hd shargs :: argv;

	winname = Name + " " + cwd;

	spawn main(ctxt, argv);
}

main(ctxt: ref Draw->Context, argv: list of string)
{
	(t, titlectl) := wmlib->titlebar(ctxt.screen, "", winname, Wmlib->Appl);

	if(width == nil || height == nil){
		(dw, dh) := defaultsize(t, ctxt.screen);
		if(width == nil)
			width = dw;
		if(height == nil)
			height = dh;
	}

	edit := chan of string;
	tk->namechan(t, edit, "edit");

	for (i := 0; i < len shwin_cfg; i++)
		cmd(t, shwin_cfg[i]);
	if (font != nil) {
		if (font[0] != '/' && (len font == 1 || font[0:2] != "./"))
			font = "/fonts/" + font;
		cmd(t, ".ft.t configure -font " + font);
	}
	cmd(t, ". configure -width " + width + " -height "+height);
	cmd(t, "update");

	ioc := chan of (int, ref FileIO, ref FileIO, string, ref FileIO, ref FileIO);
	spawn newsh(ctxt, ioc, argv);

	(pid, file, filectl, consfile, shctl, hist) := <-ioc;
	if(file == nil || filectl == nil || shctl == nil) {
		sys->print("newsh: shell cons creation failed\n");
		return;
	}

	keys := chan of string;
	tk->namechan(t, keys, "keys");

	butcmd := chan of string;
	tk->namechan(t, butcmd, "button");

	event := chan of string;
	tk->namechan(t, event, "action");

	but1 := chan of string;
	tk->namechan(t, but1, "but1");
	but2 := chan of string;
	tk->namechan(t, but2, "but2");
	but3 := chan of string;
	tk->namechan(t, but3, "but3");
	button1 := 0;
	button3 := 0;

	rdrpc: Rdreq;

	# outpoint is place in text to insert characters printed by programs
	cmd(t, ".ft.t mark set outpoint end; .ft.t mark gravity outpoint left");

	for(;;) alt {
	menu := <-titlectl =>
		if(menu == "exit") {
			kill(pid);
			return;
		}
		if (menu == "task")
			spawn wmlib->titlectl(t, menu);
		else
			wmlib->titlectl(t, menu);
		cmd(t, "focus .ft.t");

	ecmd := <-edit =>
		editor(t, ecmd);
		sendinput(t);
		cmd(t, "focus .ft.t");

	c := <-keys =>
		cut(t, 1);
		char := c[1];
		if(char == '\\')
			char = c[2];
		if(rawon) {
			rawinput[len rawinput] = char;
			rawinput = sendraw(rawinput);
			break;
		}
		update := ";.ft.t see insert;update";
		case char {
		* =>
			cmd(t, ".ft.t insert insert "+c+update);
		'\n' or EOT =>
			cmd(t, ".ft.t insert insert "+c+update);
			sendinput(t);
		'\b' =>
			cmd(t, ".ft.t tkTextDelIns -c"+update);
		BSL =>
			cmd(t, ".ft.t tkTextDelIns -l"+update);
		BSW =>
			cmd(t, ".ft.t tkTextDelIns -w"+update);
		ESC =>
			holding ^= 1;
			color := "blue";
			if(!holding){
				color = "black";
				wmlib->taskbar(t, winname);
				sendinput(t);
			}else
				wmlib->taskbar(t, winname+" (holding)");
			cmd(t, ".ft.t configure -foreground "+color+update);
		}

	c := <-but1 =>
		button1 = (c == "pressed");
		button3 = 0;	# abort any pending button 3 action

	c := <-but2 =>
		if(button1){
			cut(t, 1);
			cmd(t, "update");
			break;
		}
		(nil, l) := sys->tokenize(c, " ");
		x := int hd l - 50;
		y := int hd tl l - int cmd(t, ".m yposition "+menuindex) - 10;
		cmd(t, ".m activate "+menuindex+"; .m post "+string x+" "+string y+
			"; grab set .m; update");
		button3 = 0;	# abort any pending button 3 action

	c := <-but3 =>
		if(c == "pressed"){
			button3 = 1;
			if(button1){
				paste(t);
				cmd(t, "update");
			}
			break;
		}
		if(plumbed == 0 || button3 == 0 || button1 != 0)
			break;
		button3 = 0;
		# plumb message triggered by release of button 3
		(nil, l) := sys->tokenize(c, " ");
		x := int hd tl l;
		y := int hd tl tl l;
		index := cmd(t, ".ft.t index @"+string x+","+string y);
		selindex := cmd(t, ".ft.t tag ranges sel");
		if(selindex != "")
			insel := cmd(t, ".ft.t compare sel.first <= "+index)=="1" &&
				cmd(t, ".ft.t compare sel.last >= "+index)=="1";
		else
			insel = 0;
		attr := "";
		if(insel)
			text := cmd(t, ".ft.t get sel.first sel.last");
		else{
			# have line with text in it
			# now extract whitespace-bounded string around click
			(nil, w) := sys->tokenize(index, ".");
			charno := int hd tl w;
			left := cmd(t, ".ft.t index {"+index+" linestart}");
			right := cmd(t, ".ft.t index {"+index+" lineend}");
			line := cmd(t, ".ft.t get "+left+" "+right);
			for(i:=charno; i>0; --i)
				if(line[i-1]==' ' || line[i-1]=='\t')
					break;
			for(j:=charno; j<len line; j++)
				if(line[j]==' ' || line[j]=='\t')
					break;
			text = line[i:j];
			attr = "click="+string (charno-i);
		}
		msg := ref Msg(
			"WmSh",
			"",
			cwd,
			"text",
			attr,
			array of byte text);
		if(msg.send() < 0)
			sys->fprint(sys->fildes(2), "sh: plumbing write error: %r\n");
	c := <-butcmd =>
		simulatetype(t, tkunquote(c));
		sendinput(t);
		cmd(t, "update");
	c := <-event =>
		events = str->append(tkunquote(c), events);
		if (evrdreq != nil) {
			readreply((hd evrdreq).rc, array of byte hd events, nil);
			evrdreq = tl evrdreq;
			events = tl events;
		}
	rdrpc = <-shctl.read =>
		if(rdrpc.rc == nil)
			continue;
		if (events != nil) {
			readreply(rdrpc.rc, array of byte hd events, nil);
			events = tl events;
		} else
			evrdreq = rdrpc :: evrdreq;
	(nil, data, nil, wc) := <-shctl.write =>
		if (wc == nil)
			break;
		if ((err := shctlcmd(t, string data)) != nil)
			writereply(wc, 0, err);
		else
			writereply(wc, len data, nil);
	(off, nbytes, nil, rc) := <-hist.read =>
		if (rc == nil)
			break;
		if (off > nhistory)
			off = nhistory;
		if (off + nbytes > nhistory)
			nbytes = nhistory - off;
		readreply(rc, history[off:off + nbytes], nil);
	(nil, data, nil, wc) := <-hist.write =>
		if (wc != nil)
			wc <-= (0, "cannot write");
	rdrpc = <-filectl.read =>
		if(rdrpc.rc == nil)
			continue;
		readreply(rdrpc.rc, nil, "not allowed");
	(nil, data, nil, wc) := <-filectl.write =>
		if(wc == nil) {
			# consctl closed - revert to cooked mode
			# XXX should revert only on *last* close?
			rawon = 0;
			continue;
		}
		(nc, cmdlst) := sys->tokenize(string data, " \n");
		if(nc == 1) {
			case hd cmdlst {
			"rawon" =>
				rawon = 1;
				rawinput = "";
				# discard previous input
				advance := string (len tk->cmd(t, ".ft.t get outpoint end") +1);
				cmd(t, ".ft.t mark set outpoint outpoint+" + advance + "chars");
			"rawoff" =>
				rawon = 0;
			* =>
				writereply(wc, 0, "unknown consctl request");
				continue;
			}
			writereply(wc, len data, nil);
			continue;
		}
		writereply(wc, 0, "unknown consctl request");

	rdrpc = <-file.read =>
		if(rdrpc.rc == nil) {
			(ok, nil) := sys->stat(consfile);
			if (ok < 0)
				return;
			continue;
		}
		append(rdrpc);
		sendinput(t);

	(off, data, fid, wc) := <-file.write =>
		if(wc == nil) {
			(ok, nil) := sys->stat(consfile);
			if (ok < 0)
				return;
			continue;
		}
		cdata := cursorcontrol(t, string data);
		ncdata := string len cdata + "chars;";
		moveins := insat(t, "outpoint");
		cmd(t, ".ft.t insert outpoint '"+ cdata);
		writereply(wc, len data, nil);
		data = nil;
		s := ".ft.t mark set outpoint outpoint+" + ncdata;
		s += ".ft.t see outpoint;";
		if(moveins)
			s += ".ft.t mark set insert insert+" + ncdata;
		s += "update";
		cmd(t, s);
		nlines := int cmd(t, ".ft.t index end");
		if(nlines > HIWAT){
			s = ".ft.t delete 1.0 "+ string (nlines-LOWAT) +".0;update";
			cmd(t, s);
		}
	}
}

tkunquote(s: string): string
{
	if (s == nil)
		return nil;
	t: string;
	if (s[0] != '{' || s[len s - 1] != '}')
		return s;
	for (i := 1; i < len s - 1; i++) {
		if (s[i] == '\\')
			i++;
		t[len t] = s[i];
	}
	return t;
}
	
writereply(wc: Sys->Rwrite, n: int, e: string)
{
	alt {
	wc <-= (n, e) =>;
	* =>;
	}
}

readreply(rc: Sys->Rread, data: array of byte, e: string)
{
	alt {
	rc <-= (data, e) =>;
	* =>;
	}
}

buttonid := 0;
shctlcmd(win: ref Tk->Toplevel, c: string): string
{
	toks := str->unquoted(c);
	if (toks == nil)
		return "null command";
	n := len toks;
	case hd toks {
	"button" or
	"action"=>
		# (button|action) title sendtext
		if (n != 3)
			return "bad usage";
		id := ".b.b" + string buttonid++;
		cmd(win, "button " + id + " -text " + wmlib->tkquote(hd tl toks) +
				" -command 'send " + hd toks + " " + wmlib->tkquote(hd tl tl toks));
		cmd(win, "pack " + id + " -side left");
		cmd(win, "pack propagate .b 0");
	"clear" =>
		for (i := 0; i < buttonid; i++)
			cmd(win, "destroy .b.b" + string i);
		buttonid = 0;
	"cwd" =>
		if (n != 2)
			return "bad usage";
		cwd = hd tl toks;
		winname = Name + " " + cwd;
		wmlib->taskbar(win, winname);
	* =>
		return "bad command";
	}
	cmd(win, "update");
	return nil;
}


RPCread: type (int, int, int, chan of (array of byte, string));

append(r: RPCread)
{
	t := r :: nil;
	while(rdreq != nil) {
		t = hd rdreq :: t;
		rdreq = tl rdreq;
	}
	rdreq = t;
}

insat(t: ref Tk->Toplevel, mark: string): int
{
	return cmd(t, ".ft.t compare insert == "+mark) == "1";
}

insininput(t: ref Tk->Toplevel): int
{
	if(cmd(t, ".ft.t compare insert >= outpoint") != "1")
		return 0;
	return cmd(t, ".ft.t compare {insert linestart} == {outpoint linestart}") == "1";
}

isalnum(s: string): int
{
	if(s == "")
		return 0;
	c := s[0];
	if('a' <= c && c <= 'z')
		return 1;
	if('A' <= c && c <= 'Z')
		return 1;
	if('0' <= c && c <= '9')
		return 1;
	if(c == '_')
		return 1;
	if(c > 16rA0)
		return 1;
	return 0;
}

cursorcontrol(t: ref Tk->Toplevel, s: string): string
{
	l := len s;
	for(i := 0; i < l; i++) {
		case s[i] {
		    '\b' =>
			pre := "";
			rem := "";
			if(i + 1 < l)
				rem = s[i+1:];
			if(i == 0) {	# erase existing character in line
				if(cmd(t, ".ft.t get " +
					"{outpoint linestart} outpoint") != "")
				    cmd(t, ".ft.t delete outpoint-1char");
			} else {
				if(s[i-1] != '\n')	# don't erase newlines
					i--;
				if(i)
					pre = s[:i];
			}
			s = pre + rem;
			l = len s;
			i = len pre - 1;
		    '\r' =>
			s[i] = '\n';
			if(i + 1 < l && s[i+1] == '\n')	# \r\n
				s = s[:i] + s[i+1:];
			else if(i > 0 && s[i-1] == '\n')	# \n\r
				s = s[:i-1] + s[i:];
			l = len s;
		}
	}
	return s;
}

editor(t: ref Tk->Toplevel, ecmd: string)
{
	s, snarf: string;

	case ecmd {
	"cut" =>
		menuindex = "0";
		cut(t, 1);
	
	"paste" =>
		menuindex = "1";
		paste(t);

	"snarf" =>
		menuindex = "2";
		if(cmd(t, ".ft.t tag ranges sel") == "")
			break;
		snarf = cmd(t, ".ft.t get sel.first sel.last");
		wmlib->snarfput(snarf);

	"send" =>
		menuindex = "3";
		if(cmd(t, ".ft.t tag ranges sel") != ""){
			snarf = cmd(t, ".ft.t get sel.first sel.last");
			wmlib->snarfput(snarf);
		}else
			snarf = wmlib->snarfget();
		if(snarf != "")
			s = snarf;
		else
			return;
		if(s[len s-1] != '\n' && s[len s-1] != EOT)
			s[len s] = '\n';
		simulatetype(t, s);
	}
	cmd(t, "update");
}

simulatetype(t: ref Tk->Toplevel, s: string)
{
	appendhist(s);
	cmd(t, ".ft.t see end; .ft.t insert end '"+s);
	cmd(t, ".ft.t mark set insert end");
	tk->cmd(t, ".ft.t tag remove sel sel.first sel.last");
}

cut(t: ref Tk->Toplevel, snarfit: int)
{
	if(cmd(t, ".ft.t tag ranges sel") == "")
		return;
	if(snarfit)
		wmlib->snarfput(cmd(t, ".ft.t get sel.first sel.last"));
	cmd(t, ".ft.t delete sel.first sel.last");
}

paste(t: ref Tk->Toplevel)
{
	snarf := wmlib->snarfget();
	if(snarf == "")
		return;
	cut(t, 0);
	cmd(t, ".ft.t insert insert '"+snarf);
	cmd(t, ".ft.t tag add sel insert-"+string len snarf+"chars insert");
	sendinput(t);
}

sendinput(t: ref Tk->Toplevel)
{
	if(holding)
		return;
	input := tk->cmd(t, ".ft.t get outpoint end");
	slen := len input;
	if(slen == 0 || rdreq == nil)
		return;

	r := hd rdreq;
	for(i := 0; i < slen; i++)
		if(input[i] == '\n' || input[i] == EOT)
			break;

	if(i >= slen && slen < r.nbytes)
		return;

	if(i >= r.nbytes)
		i = r.nbytes-1;
	advance := string (i+1);
	if(input[i] == EOT)
		input = input[0:i];
	else
		input = input[0:i+1];

	rdreq = tl rdreq;
	appendhist(input);

	alt {
	r.rc <-= (array of byte input, "") =>
		cmd(t, ".ft.t mark set outpoint outpoint+" + advance + "chars");
	* =>
		# requester has disappeared; ignore his request and try again
		sendinput(t);
	}
}

appendhist(s: string)
{
	d := array of byte s;
	if (len d + nhistory > len history) {
		newhistory := array[(len d + nhistory) * 3 / 2] of byte;
		newhistory[0:] = history[0:nhistory];
		history = newhistory;
	}
	history[nhistory:] = d;
	nhistory += len d;
}

sendraw(input : string) : string
{
	i := len input;
	if(i == 0 || rdreq == nil)
		return input;

	r := hd rdreq;
	rdreq = tl rdreq;

	if(i > r.nbytes)
		i = r.nbytes;

	alt {
	r.rc <-= (array of byte input[0:i], "") =>
		input = input[i:];
	* =>
		;# requester has disappeared; ignore his request and try again
	}
	return input;
}

newsh(ctxt: ref Context, ioc: chan of (int, ref FileIO, ref FileIO, string, ref FileIO, ref FileIO),
			args: list of string)
{
	pid := sys->pctl(sys->NEWFD, nil);

	sh := load Command "/dis/sh.dis";
	if(sh == nil) {
		ioc <-= (0, nil, nil, nil, nil, nil);
		return;
	}

	tty := "cons."+string pid;

	sys->bind("#s","/chan",sys->MBEFORE);
	fio := sys->file2chan("/chan", tty);
	fioctl := sys->file2chan("/chan", tty + "ctl");
	shctl := sys->file2chan("/chan", "shctl");
	hist := sys->file2chan("/chan", "history");
	ioc <-= (pid, fio, fioctl, "/chan/"+tty, shctl, hist);
	if(fio == nil || fioctl == nil || shctl == nil)
		return;

	sys->bind("/chan/"+tty, "/dev/cons", sys->MREPL);
	sys->bind("/chan/"+tty+"ctl", "/dev/consctl", sys->MREPL);

	fd0 := sys->open("/dev/cons", sys->OREAD|sys->ORCLOSE);
	fd1 := sys->open("/dev/cons", sys->OWRITE);
	fd2 := sys->open("/dev/cons", sys->OWRITE);

	e := ref Sys->Exception;
	if (sys->rescue("fail:*", nil) == Sys->EXCEPTION)
		exit;
	sh->init(ctxt, "sh" :: "-n" :: args);
}

kill(pid: int)
{
	fd := sys->open("#p/"+string pid+"/ctl", sys->OWRITE);
	if(fd != nil)
		sys->fprint(fd, "killgrp");
}

cmd(top: ref Tk->Toplevel, c: string): string
{
	s:= tk->cmd(top, c);
#	sys->print("* %s\n", c);
	if (s != nil && s[0] == '!')
		sys->fprint(sys->fildes(2), "wmsh: tk error on '%s': %s\n", c, s);
	return s;
}

defaultsize(top: ref Tk->Toplevel, screen: ref Draw->Screen): (string, string)
{
	r := screen.image.r;
	(ox, oy) := (int tk->cmd(top, ". cget -actx"), int tk->cmd(top, ". cget -acty"));
	(w, h) := (r.dx(), r.dy());
	if(w > 600 && h > 400){
		(w, h) = (80*w/100, 60*h/100);
		if(ox+w > r.max.x)
			w = r.max.x-ox;
		if(oy+h > r.max.y)
			h = r.max.y-oy;
		if(w > 700)
			w = 80*w/100;
		if(h > 700)
			h = 80*h/100;
	}else
		h -= 20;
	return (string w, string h);
}
