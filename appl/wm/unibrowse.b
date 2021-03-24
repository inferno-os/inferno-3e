implement Unibrowse;

# unicode browser for inferno.
# roger peppe (rog@ohm.york.ac.uk)

include "sys.m";
	sys: Sys;
	stderr: ref Sys->FD;
include "draw.m";
	draw: Draw;
include "tk.m";
	tk: Tk;
include "wmlib.m";
	wmlib: Wmlib;
include "string.m";
	str: String;
include "bufio.m";
	bio: Bufio;

Unibrowse: module
{
	init: fn(ctxt: ref Draw->Context, nil: list of string);
};

Widgetstack: adt {
	stk: list of string;	# list of widget names; bottom of list is left-most widget
	name: string;

	# init returns the widget name for the widgetstack;
	# wn is the name of the frame holding the widget stack
	new: fn(wn: string): ref Widgetstack;

	push: fn(ws: self ref Widgetstack, w: string);
	pop: fn(ws: self ref Widgetstack): string;
	top: fn(ws: self ref Widgetstack): string;
};

Defaultwidth: con 30;
Defaultheight: con 1;

Tablerows: con 3;
Tablecols: con 8;

Element: adt {
	name: string;
	cmd: chan of string;
	cmdname: string;
	config: array of string;
	doneinit: int;
};

# columns in unidata file
ud_VAL, ud_CHARNAME, ud_CATEG, ud_COMBINE, ud_BIDIRECT,
ud_DECOMP, ud_DECDIGIT, ud_DIGIT, ud_NUMERICVAL, ud_MIRRORED,
ud_OLDNAME, ud_COMMENT, ud_UPCASE, ud_LOWCASE, ud_TITLECASE: con iota;

# default font configurations within the application
DEFAULTFONT:	con "";
UNICODEFONT:	con "lucm/unicode.9";
TITLEFONT:	con "misc/latin1.8x13";
DATAFONT:	con "misc/latin1.8x13";
BUTTONFONT:	con "misc/latin1.8x13";

currfont := "/fonts/" + UNICODEFONT + ".font";

MAINMENU, BYSEARCH, BYNUMBER, BYCATEGORY, BYFONT, TABLE: con iota;
elements := array[] of {
MAINMENU => Element(".main", nil, "maincmd", array[] of {
	"frame .main",
	"$listbox data .main.menu -height 6h",
	"$button button .main.insp -text {Inspector} -command {send maincmd inspect}",
	"$button button .main.font -text {Font} -command {send maincmd font}",
	"$label unicode .fontlabel",	# .fontlabel's font is currently chosen font
	"pack .main.menu -side top",
	"pack .main.insp .main.font -side left",
	"bind .main.menu <ButtonRelease-1> +{send maincmd newselect}"
	}, 0),
BYNUMBER => Element(".numfield", nil, "numcmd", array[] of {
	"frame .numfield",
	"$entry data .numfield.f -width 8w",
	"bind .numfield.f <Key-\n> {send numcmd shownum}",
	"$label title .numfield.l -text 'Hex unicode value",
	"pack .numfield.l .numfield.f -side left"
	}, 0),
TABLE => Element(".tbl", nil, "tblcmd", array[] of {
	"frame .tbl",
	"frame .tbl.tf",
	"frame .tbl.buts",
	"$button button .tbl.buts.forw -text {Next} -command {send tblcmd forw}",
	"$button button .tbl.buts.backw -text {Prev} -command {send tblcmd backw}",
	"pack .tbl.buts.forw .tbl.buts.backw -side left",
	"pack .tbl.tf -side top",
	"pack .tbl.buts -side left"
	}, 0),
BYCATEGORY => Element(".cat", nil, "catcmd", array[] of {
	"frame .cat",
	"$listbox data .cat.menu -width 43w -height 130 -yscrollcommand {.cat.yscroll set}",
	"scrollbar .cat.yscroll -width 18 -command {.cat.menu yview}",
	"pack .cat.yscroll .cat.menu -side left -fill y", 
	"bind .cat.menu <ButtonRelease-1> +{send catcmd newselect}"
	}, 0),
BYSEARCH => Element(".srch", nil, "searchcmd", array[] of {
	"frame .srch",
	"$listbox data .srch.menu -width 43w -height 130 -yscrollcommand {.srch.yscroll set}",
	"scrollbar .srch.yscroll -width 18 -command {.srch.menu yview}",
	"pack .srch.yscroll .srch.menu -side left -fill y", 
	"bind .srch.menu <ButtonRelease-1> +{send searchcmd search}"
	}, 0),
BYFONT => Element(".font", nil, "fontcmd", array[] of {
	"frame .font",
	"$listbox data .font.menu -width 43w -height 130 -yscrollcommand {.font.yscroll set}",
	"scrollbar .font.yscroll -width 18 -command {.font.menu yview}",
	"pack .font.yscroll .font.menu -side left -fill y", 
	"bind .font.menu <ButtonRelease-1> +{send fontcmd newselect}"
	}, 0),
};

entries := array[] of {
("By Category", BYCATEGORY),
("By number", BYNUMBER),
("Symbol wordsearch", BYSEARCH),
("Font information", BYFONT)
};

toplevelconfig := array[] of {
"pack .Wm_t .display -side top -fill x",
"image create bitmap waiting -file cursor.wait"
};

wmchan:		chan of string;	# from main window
inspchan:	chan of string;	# to inspector

displ:		ref Widgetstack;
top:		ref Tk->Toplevel;
unidata:	ref bio->Iobuf;

UNIDATA:	con "/lib/unidata/unidata2.txt";
UNIINDEX:	con "/lib/unidata/index2.txt";
UNIBLOCKS:	con "/lib/unidata/blocks.txt";

notice(msg: string)
{
	wmlib->dialog(top, "bomb.bit", "Notice", msg, 0, "OK"::nil);
}

init(ctxt: ref Draw->Context, nil: list of string)
{
	entrychan := chan of string;

	config(ctxt);
	if ((unidata = bio->open(UNIDATA, bio->OREAD)) == nil) {
		notice("Couldn't open unicode data file");
		inspchan <-= "exit";
		exit;
	}

	push(MAINMENU);
	update(top);
	currpos := 0;

	for (;;) alt {
	c := <-wmchan =>
		wmlib->titlectl(top, c);
	c := <-elements[MAINMENU].cmd =>
		case c {
		"font" =>
			font := choosefont(ctxt);
			if (font != nil) {
				currfont = font;
				updatefont();
				update(top);
			}
		"newselect" =>
			sel := int tk->cmd(top, ".main.menu curselection");
			(nil, el) := entries[sel];
			if (el == BYSEARCH) {
				spawn sendentry(top, "Enter search string", entrychan);
				break;
			}
			pop(MAINMENU);
			push(el);
			update(top);

		"inspect" =>
			inspchan <-= "raise";
		}
	c := <-entrychan =>
		if (c != nil) {
			pop(MAINMENU);
			push(BYSEARCH);
			update(top);
			keywordsearch(c);
		}

	c := <-elements[BYNUMBER].cmd =>
		txt := tk->cmd(top, ".numfield.f get");
		(n, nil) := str->toint(txt, 16);

		pop(BYNUMBER);
		push(TABLE);
		setchar(n);
		currpos = filltable(n);
		update(top);

	c := <-elements[BYCATEGORY].cmd =>
		sel := tk->cmd(top, ".cat.menu curselection");
		(currpos, nil) = str->toint(tk->cmd(top, ".cat.menu get "+sel), 16);
		pop(BYCATEGORY);
		push(TABLE);
		currpos = filltable(currpos);
		update(top);

	c := <-elements[TABLE].cmd =>
		case c {
		"forw" =>	currpos = filltable(currpos + Tablerows * Tablecols);
				update(top);

		"backw" =>	currpos = filltable(currpos - Tablerows * Tablecols);
				update(top);

		* =>		# must be set <col> <row>
				(nil, args) := sys->tokenize(c, " ");
				setchar(currpos + int hd tl args
						+ int hd tl tl args * Tablecols);
		}

	c := <-elements[BYSEARCH].cmd =>
		sel := tk->cmd(top, ".srch.menu curselection");
		(n, nil) := str->toint(tk->cmd(top, ".srch.menu get "+sel), 16);

		pop(BYSEARCH);
		push(TABLE);
		setchar(n);
		currpos = filltable(n);
		update(top);

	c := <-elements[BYFONT].cmd =>
		sel := tk->cmd(top, ".font.menu curselection");
		(currpos, nil) = str->toint(tk->cmd(top, ".font.menu get "+sel), 16);
		pop(BYFONT);
		push(TABLE);
		currpos = filltable(currpos);
		update(top);
	}
	inspchan <-= "exit";
}

sendentry(t: ref Tk->Toplevel, msg: string, where: chan of string)
{
	where <-= wmlib->getstring(t, msg);
	exit;
}

setchar(c: int)
{
	s := ""; s[0] = c;
	inspchan <-= s;
}


charconfig := array[] of {
"frame .chdata -borderwidth 5 -relief ridge",
"frame .chdata.f1",
"frame .chdata.f2",
"frame .chdata.chf -borderwidth 4 -relief raised",
"frame .chdata.chcf -borderwidth 3 -relief ridge",
"$label title .chdata.chf.title -text 'Glyph: ",
"$label unicode .chdata.ch",
"$label data .chdata.val -anchor e",
"$label title .chdata.name -anchor w",
"$label data .chdata.cat -anchor w",
"$label data .chdata.comm -anchor w",
"$button button .chdata.snarfbut -text {Snarf} -command {send charcmd snarf}",
"$button button .chdata.pastebut -text {Paste} -command {send charcmd paste}",
"pack .chdata.chf.title .chdata.chcf -in .chdata.chf -side left",
"pack .chdata.ch -in .chdata.chcf",
"pack .chdata.chf -in .chdata.f1 -side left -padx 1 -pady 1",
"pack .chdata.val -in .chdata.f1 -side right",
"pack .chdata.snarfbut .chdata.pastebut -in .chdata.f2 -side right",
"pack .chdata.f1 .chdata.name .chdata.cat .chdata.comm .chdata.f2 -fill x -side top",
"pack .Wm_t .chdata -side top -fill x",
};

inspector(ctxt: ref Draw->Context, cmd: chan of string)
{
	chtop: ref Tk->Toplevel;
	charcmd := chan of string;
	currc := 'A';
	iwmchan := chan of string;

	for (;;) alt {
	c := <-iwmchan =>
		if (c != "exit")
			wmlib->titlectl(chtop, c);
		else
			chtop = nil;
	c := <-cmd =>
		case c {
		"raise" =>
			if (chtop != nil) {
				tk->cmd(chtop, "raise .");
				break;
			}
			org := winorg(top);
			org.y += int tk->cmd(top, ". cget -actheight");
			t := wmlib->titlebar(ctxt.screen,
					"-x "+string org.x+" -y "+string org.y,
					"Character inspector", 0);
			(chtop, iwmchan) = t;
			t = (nil, nil);
			tk->namechan(chtop, charcmd, "charcmd");

			runconfig(chtop, charconfig);
			inspector_setchar(chtop, currc);
		"font" =>
			if (chtop != nil) {
				tk->cmd(chtop, ".chdata.ch configure -font "+currfont);
				update(chtop);
			}
		"exit" =>
			exit;
		* =>
			if (len c == 1) {
				currc = c[0];
				inspector_setchar(chtop, currc);
			} else {
				sys->fprint(stderr, "unknown inspector cmd: '%s'\n", c);
			}
		}
	c := <-charcmd =>
		case c {
		"snarf" =>
			wmlib->snarfput(tk->cmd(chtop, ".chdata.ch cget -text"));
		"paste" =>
			buf := wmlib->snarfget();
			if (len buf > 0)
				inspector_setchar(chtop, buf[0]);
		}
	}
}

inspector_setchar(t: ref Tk->Toplevel, c: int)
{
	line := look(unidata, ';', sys->sprint("%4.4X", c));
	labelset(t, ".chdata.ch", sys->sprint("%c", c));
	labelset(t, ".chdata.val", sys->sprint("%4.4X", c));
	if (line == nil) {
		labelset(t, ".chdata.name", "No entry found in unicode table");
		labelset(t, ".chdata.cat", "");
		labelset(t, ".chdata.comm", "");
	} else {
		flds := fields(line, ';');
		labelset(t, ".chdata.name", fieldindex(flds, ud_CHARNAME));
		labelset(t, ".chdata.cat", categname(fieldindex(flds, ud_CATEG)));
		labelset(t, ".chdata.comm", fieldindex(flds, ud_OLDNAME));
	}
	update(t);
}

keywordsearch(key: string): int
{

	data := bio->open(UNIINDEX, Sys->OREAD);

	key = str->tolower(key);
	
	busy();
	tk->cmd(top, ".srch.menu delete 0 end");
	count := 0;
	while ((l := bio->data.gets('\n')) != nil) {
		l = str->tolower(l);
		if (str->prefix(key, l)) {
			if (len l > 1 && l[len l - 2] == '\r')
				l = l[0:len l - 2];
			else
				l = l[0:len l - 1];
			flds := fields(l, '\t');
			tk->cmd(top, ".srch.menu insert end '"
				+fieldindex(flds, 1)+": "+fieldindex(flds, 0));
			update(top);
			count++;
		}
	}
	notbusy();
	if (count == 0) {
		notice("No match");
		return 0;
	}
	return 1;
}

nomodule(s: string)
{
	sys->fprint(stderr, "couldn't load modules %s: %r\n", s);
	sys->raise("could not load modules");
}

config(ctxt: ref Draw->Context)
{
	sys = load Sys Sys->PATH;
	sys->pctl(Sys->NEWPGRP, nil);
	stderr = sys->fildes(2);

	draw = load Draw Draw->PATH;
	if (draw == nil) nomodule(Draw->PATH);

	tk = load Tk Tk->PATH;
	if (tk == nil) nomodule(Tk->PATH);

	wmlib = load Wmlib Wmlib->PATH;
	if (wmlib == nil) nomodule(Wmlib->PATH);

	str = load String String->PATH;
	if (str == nil) nomodule(String->PATH);

	bio = load Bufio Bufio->PATH;
	if (bio == nil) nomodule(Bufio->PATH);

	wmlib->init();

	(top, wmchan) = wmlib->titlebar(ctxt.screen, nil, "Unicode browser", Wmlib->Hide);

	displ = Widgetstack.new(".display");
	tk->cmd(top, "pack .display");

	for (i := 0; i < len elements; i++) {
		elements[i].cmd = tkchan(elements[i].cmdname);
		runconfig(top, elements[i].config);
	}

	runconfig(top, toplevelconfig);

	inspchan = chan of string;
	spawn inspector(ctxt, inspchan);
}

runconfig(top: ref Tk->Toplevel, cmds: array of string)
{
	for (i := 0; i < len cmds; i++) {
		ent := tkexpand(cmds[i]);
		if (ent != nil) {
			err := tk->cmd(top, ent);
			if (len err > 0 && err[0] == '!')
				sys->fprint(stderr, "config err: %s on '%s'\n", err, ent);
		}
	}
	checkerror(top, "config");
}

checkerror(t: ref Tk->Toplevel, s: string)
{
	if (t != nil) {
		err := tk->cmd(t, "variable lasterror");
		if (err != nil)
			sys->fprint(stderr, "%s: error: %s\n", s, err);
	}
}

update(top: ref Tk->Toplevel)
{ tk->cmd(top, "update"); }

busy()
{ tk->cmd(top, "cursor -image waiting"); }

notbusy()
{ tk->cmd(top, "cursor -default"); }

initelement(el: int): int
# returns non-zero on success
{
	if (!elements[el].doneinit) {
		elements[el].doneinit = 1;
		case el {
		MAINMENU =>
			for (e := entries; len e > 0; e = e[1:]) {
				(text, nil) := e[0];
				tk->cmd(top, ".main.menu insert end '" + text);
			}

		BYCATEGORY =>
			cats := getcategories();
			if (cats == nil) {
				notice("No categories found");
				elements[el].doneinit = 0;
				return 0;
			}
			while (cats != nil) {
				tk->cmd(top, ".cat.menu insert 0 '" + hd cats);
				cats = tl cats;
			}
		BYFONT =>
			elements[el].doneinit = 0;	# do it each time
			fonts := getfonts(currfont);
			if (fonts == nil) {
				notice("Can't find font information file");
				return 0;
			}

			tk->cmd(top, ".font.menu delete 0 end");
			while (fonts != nil) {
				tk->cmd(top, ".font.menu insert 0 '" + hd fonts);
				fonts = tl fonts;
			}
		TABLE =>
			inittable();
		}

	}
	checkerror(top, "initelement");
	return 1;
}

tablecharpath(col, row: int): string
{
	return ".tbl.tf.row"+string row+".c"+string col;
}

inittable()
{
	i: int;
	for (i = 0; i < Tablerows; i++) {
		rowname := ".tbl.tf.row" + string i;
		tk->cmd(top, "frame "+rowname);
		# >>> could put entry here
		tk->cmd(top, tkexpand("$label title "+rowname+".num"));
		tk->cmd(top, "pack "+rowname+".num -side left -fill y");
		for (j := 0; j < Tablecols; j++) {
			cname := rowname+".c"+string j;
			tk->cmd(top, tkexpand("$label unicode "+cname
					+" -borderwidth 1 -relief raised"));
			checkerror(top, "label "+cname); 
			tk->cmd(top, "bind "+cname+" <ButtonRelease-1>"
					+" {send tblcmd set "+string j+" "+string i+"}");
			tk->cmd(top, "pack "+cname+" -side left -expand 1");
		}
		tk->cmd(top, "pack "+rowname+" -side top -fill x");
	}
}

filltable(n: int): int
# fill table starting at n.
# return actual starting value.
{
	if (n < 0)
		n = 0;
	if (n + Tablerows * Tablecols > 16rffff)
		n = 16rffff - Tablerows * Tablecols;
	n -= n % Tablecols;
	for (i := 0; i < Tablerows; i++) {
		rowname := ".tbl.tf.row" + string i;
		tk->cmd(top, rowname+".num configure -text '"
				+ sys->sprint("%4.4X",n+i*Tablecols));
		for (j := 0; j < Tablecols; j++) {
			cname := rowname+".c"+string j;
			tk->cmd(top, cname + " configure -text '"
					+sys->sprint("%c", n + i * Tablecols + j));
		}
	}
	return n;
}

cnumtoint(s: string): int
{
	if (len s == 0)
		return 0;
	if (s[0] == '0' && len s > 1) {
		n: int;
		if (s[1] == 'x' || s[1] == 'X') {
			if (len s < 3)
				return 0;
			(n, nil) = str->toint(s[2:], 16);
		} else
			(n, nil) = str->toint(s, 8);
		return n;
	}
	return int s;
}

getfonts(font: string): list of string
{
	f := bio->open(font, bio->OREAD);
	if (f == nil)
		return nil;

	# ignore header
	if (bio->f.gets('\n') == nil)
		return nil;

	ret: list of string;
	while ((s := bio->f.gets('\n')) != nil) {
		(count, wds) := sys->tokenize(s, " \t");
		if (count < 3 || count > 4)
			continue;	# ignore malformed lines
		first := cnumtoint(hd wds);
		wds = tl wds;
		last := cnumtoint(hd wds);
		if (tl wds != nil) 	# if optional third field exists
			wds = tl wds;	# ignore it
		name := hd wds;
		if (name != "" && name[len name - 1] == '\n')
				name = name[0:len name - 1];
		ret = sys->sprint("%.4X-%.4X: %s", first, last, name) :: ret;
	}
	return ret;
}

getcategories(): list of string
{
	f := bio->open(UNIBLOCKS, bio->OREAD);
	if (f == nil)
		return nil;

	ret: list of string;
	while ((s := bio->f.gets('\n')) != nil) {
		if (s[0] == '#')
			continue;
		(s, nil) = str->splitr(s, "^\n\r");
		if (len s > 0) {
			start, end: string;
			(start, s) = str->splitl(s, ";");
			s = str->drop(s, "; ");
			(end, s) = str->splitl(s, ";");
			s = str->drop(s, "; ");

			ret = start+"-"+end+": "+s :: ret;
		}
	}
	return ret;
}


tkexpand(s: string): string
{
	if (len s == 0 || s[0] != '$')
		return s;

	cmd, tp, name: string;
	(cmd, s) = str->splitl(s, " \t");
	cmd = cmd[1:];

	s = str->drop(s, " \t");
	(tp, s) = str->splitl(s, " \t");
	s = str->drop(s, " \t");

	(name, s) = str->splitl(s, " \t");
	s = str->drop(s, " \t");

	font := "";
	case tp {
		"deflt" =>	font = DEFAULTFONT;
		"title" =>	font = TITLEFONT;
		"data" =>	font = DATAFONT;
		"button" =>	font = BUTTONFONT;
		"unicode" =>	font = currfont;
	}
	if (font != nil) {
		if (font[0] != '/')
			font = "/fonts/"+font+".font";
		font = "-font "+font;
	}


	ret := cmd+" "+name+" "+font+" "+s;
	return ret;
}

categname(s: string): string
{
	r := "Unknown category";
	case s {
	"Mn" => r = "Mark, Non-Spacing ";
	"Mc" => r = "Mark, Combining";
	"Nd" => r = "Number, Decimal Digit";
	"No" => r = "Number, Other";
	"Zs" => r = "Separator, Space";
	"Zl" => r = "Separator, Line";
	"Zp" => r = "Separator, Paragraph";
	"Cc" => r = "Other, Control or Format";
	"Co" => r = "Other, Private Use";
	"Cn" => r = "Other, Not Assigned";
	"Lu" => r = "Letter, Uppercase";
	"Ll" => r = "Letter, Lowercase";
	"Lt" => r = "Letter, Titlecase ";
	"Lm" => r = "Letter, Modifier";
	"Lo" => r = "Letter, Other ";
	"Pd" => r = "Punctuation, Dash";
	"Ps" => r = "Punctuation, Open";
	"Pe" => r = "Punctuation, Close";
	"Po" => r = "Punctuation, Other";
	"Sm" => r = "Symbol, Math";
	"Sc" => r = "Symbol, Currency";
	"So" => r = "Symbol, Other";
	}
	return r;
}


fields(s: string, sep: int): list of string
# seperator can't be '^' (see string(2))
{
	cl := ""; cl[0] = sep;
	ret: list of string;
	do {
		(l, r) := str->splitr(s, cl);
		ret = r :: ret;
		if (len l > 0)
			s = l[0:len l - 1];
		else
			s = nil;
	} while (s != nil);
	return ret;
}

fieldindex(sl: list of string, n: int): string
{
	for (; sl != nil; sl = tl sl) {
		if (n == 0)
			return hd sl;
		n--;
	}
	return nil;
}

push(el: int)
{
	if (initelement(el)) {
		displ.push(elements[el].name);
	}
}

pop(el: int)
# pop elements until we encounter one matching el.
{
	while (displ.top() != elements[el].name)
		displ.pop();
}

tkchan(nm: string): chan of string
{
	c := chan of string;
	tk->namechan(top, c, nm);
	return c;
}

labelset(t: ref Tk->Toplevel, name: string, val: string)
{
	tk->cmd(t, name+" configure -text '"+val);
}


choosefont(ctxt: ref Draw->Context): string
{
	font := wmlib->filename(ctxt.screen, top, "Select a font", "*.font" :: nil, "/fonts");
	if (font != nil) { 
		ret := tk->cmd(top, ".fontlabel configure"+" -font "+font);
		if (len ret > 0 && ret[0] == '!') {
			font = nil;
			notice("Bad font: "+ret[1:]);
		}
	}
	return font;
}

updatefont()
{
	for (i := 0; i < Tablerows; i++)
		for (j := 0; j < Tablecols; j++)
			tk->cmd(top, tablecharpath(j, i) + " configure -font "+currfont);
	# update the font display table if it's being displayed
	for (el := displ.stk; el != nil; el = tl el) {
		if (hd el == elements[BYFONT].name) {
			initelement(BYFONT);
		}
	}
	checkerror(top, "updatefont");
	inspchan <-= "font";
}


winorg(t: ref Tk->Toplevel): Draw->Point
{
	return Draw->Point(int tk->cmd(t, ". cget -x"), int tk->cmd(t, ". cget -y"));
}
	
Widgetstack.new(wn: string): ref Widgetstack
{
	tk->cmd(top, "frame "+wn+" -borderwidth 4 -relief ridge");

	return ref Widgetstack(nil, wn);
}

Widgetstack.push(ws: self ref Widgetstack, w: string)
{
	if (w == nil)
		return;
	opts: con " -fill y -side left";

	if (ws.stk == nil) {
		tk->cmd(top, "pack "+w+" -in "+ws.name+" "+opts);
	} else {
		tk->cmd(top, "pack "+w+" -after "+hd ws.stk+" "+opts);
	}

	ws.stk = w :: ws.stk;
}

Widgetstack.pop(ws: self ref Widgetstack): string
{
	if (ws.stk == nil) {
		sys->fprint(stderr, "widget stack underflow!\n");
		exit;
	}
	old := hd ws.stk;
	ws.stk = tl ws.stk;
	tk->cmd(top, "pack forget "+old);
	return old;
}

Widgetstack.top(ws: self ref Widgetstack): string
{
	if (ws.stk == nil)
		return nil;
	return hd ws.stk;
}

# binary search for key in f.
# code converted from bsd source without permission.
look(f: ref bio->Iobuf, sep: int, key: string): string
{
	bot := mid := 0;
	top := bio->f.seek(0, Sys->SEEKEND);
	key = canon(key, sep);

	for (;;) {
		mid = (top + bot) / 2;
		bio->f.seek(mid, Sys->SEEKSTART);
		c: int;
		do {
			c = bio->f.getb();
			mid++;
		} while (c != bio->EOF && c != bio->ERROR && c != '\n');
		(entry, eof) := getword(f);
		if (entry == nil && eof)
			break;
		entry = canon(entry, sep);
		case comparewords(key, entry) {
		-2 or -1 or 0 =>
			if (top <= mid)
				break;
			top = mid;
			continue;
		1 or 2 =>
			bot = mid;
			continue;
		}
		break;
	}
	bio->f.seek(bot, Sys->SEEKSTART);
	while (bio->f.seek(0, Sys->SEEKRELA) < top) {
		(entry, eof) := getword(f);
		if (entry == nil && eof)
			return nil;
		word := canon(entry, sep);
		case comparewords(key, word) {
		-2 =>
			return nil;
		-1 or 0 =>
			return entry;
		1 or 2 =>
			continue;
		}
		break;
	}
	for (;;) {
		(entry, eof) := getword(f);
		if (entry == nil && eof)
			return nil;
		word := canon(entry, sep);
		case comparewords(key, word) {
		-1 or 0 =>
			return entry;
		}
		break;
	}
	return nil;
}

comparewords(s, t: string): int
{
	if (s == t)
		return 0;
	i := 0;
	for (; i < len s && i < len t && s[i] == t[i]; i++)
		;
	if (i >= len s)
		return -1;
	if (i >= len t)
		return 1;
	if (s[i] < t[i])
		return -2;
	return 2;
}

getword(f: ref bio->Iobuf): (string, int)
{
	ret := "";
	for (;;) {
		c := bio->f.getc();
		if (c == bio->EOF || c == bio->ERROR)
			return (ret, 0);
		if (c == '\n')
			break;
		ret[len ret] = c;
	}
	return (ret, 1);
}

canon(s: string, sep: int): string
{
	if (sep < 0)
		return s;
	i := 0;
	for (; i < len s; i++)
		if (s[i] == sep)
			break;
	return s[0:i];
}
