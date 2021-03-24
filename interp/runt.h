#pragma hjdicks x4
typedef struct Sys_Exception Sys_Exception;
typedef struct Sys_Qid Sys_Qid;
typedef struct Sys_Dir Sys_Dir;
typedef struct Sys_FD Sys_FD;
typedef struct Sys_Connection Sys_Connection;
typedef struct Sys_FileIO Sys_FileIO;
typedef struct Draw_Point Draw_Point;
typedef struct Draw_Rect Draw_Rect;
typedef struct Draw_Image Draw_Image;
typedef struct Draw_Display Draw_Display;
typedef struct Draw_Font Draw_Font;
typedef struct Draw_Screen Draw_Screen;
typedef struct Draw_Pointer Draw_Pointer;
typedef struct Draw_Context Draw_Context;
typedef struct Prefab_Style Prefab_Style;
typedef struct Prefab_Environ Prefab_Environ;
typedef struct Prefab_Layout Prefab_Layout;
typedef struct Prefab_Element Prefab_Element;
typedef struct Prefab_Compound Prefab_Compound;
typedef struct Tk_Toplevel Tk_Toplevel;
typedef struct Keyring_IPint Keyring_IPint;
typedef struct Keyring_SigAlg Keyring_SigAlg;
typedef struct Keyring_PK Keyring_PK;
typedef struct Keyring_SK Keyring_SK;
typedef struct Keyring_Certificate Keyring_Certificate;
typedef struct Keyring_DigestState Keyring_DigestState;
typedef struct Keyring_DESstate Keyring_DESstate;
typedef struct Keyring_IDEAstate Keyring_IDEAstate;
typedef struct Keyring_Authinfo Keyring_Authinfo;
typedef struct Loader_Inst Loader_Inst;
typedef struct Loader_Typedesc Loader_Typedesc;
typedef struct Loader_Link Loader_Link;
typedef struct Loader_Niladt Loader_Niladt;
struct Sys_Exception
{
	String*	name;
	String*	mod;
	WORD	pc;
};
#define Sys_Exception_size 12
#define Sys_Exception_map {0xc0,}
struct Sys_Qid
{
	WORD	path;
	WORD	vers;
};
#define Sys_Qid_size 8
#define Sys_Qid_map {0}
struct Sys_Dir
{
	String*	name;
	String*	uid;
	String*	gid;
	Sys_Qid	qid;
	WORD	mode;
	WORD	atime;
	WORD	mtime;
	WORD	length;
	WORD	dtype;
	WORD	dev;
};
#define Sys_Dir_size 44
#define Sys_Dir_map {0xe0,}
struct Sys_FD
{
	WORD	fd;
};
#define Sys_FD_size 4
#define Sys_FD_map {0}
struct Sys_Connection
{
	Sys_FD*	dfd;
	Sys_FD*	cfd;
	String*	dir;
};
#define Sys_Connection_size 12
#define Sys_Connection_map {0xe0,}
typedef struct{ Array* t0; String* t1; } Sys_Rread;
#define Sys_Rread_size 8
#define Sys_Rread_map {0xc0,}
typedef struct{ WORD t0; String* t1; } Sys_Rwrite;
#define Sys_Rwrite_size 8
#define Sys_Rwrite_map {0x40,}
struct Sys_FileIO
{
	Channel*	read;
	Channel*	write;
};
typedef struct{ WORD t0; WORD t1; WORD t2; Channel* t3; } Sys_FileIO_read;
#define Sys_FileIO_read_size 16
#define Sys_FileIO_read_map {0x10,}
typedef struct{ WORD t0; Array* t1; WORD t2; Channel* t3; } Sys_FileIO_write;
#define Sys_FileIO_write_size 16
#define Sys_FileIO_write_map {0x50,}
#define Sys_FileIO_size 8
#define Sys_FileIO_map {0xc0,}
struct Draw_Point
{
	WORD	x;
	WORD	y;
};
#define Draw_Point_size 8
#define Draw_Point_map {0}
struct Draw_Rect
{
	Draw_Point	min;
	Draw_Point	max;
};
#define Draw_Rect_size 16
#define Draw_Rect_map {0}
struct Draw_Image
{
	Draw_Rect	r;
	Draw_Rect	clipr;
	WORD	ldepth;
	WORD	repl;
	Draw_Display*	display;
	Draw_Screen*	screen;
};
#define Draw_Image_size 48
#define Draw_Image_map {0x0,0x30,}
struct Draw_Display
{
	Draw_Image*	image;
	Draw_Image*	ones;
	Draw_Image*	zeros;
};
#define Draw_Display_size 12
#define Draw_Display_map {0xe0,}
struct Draw_Font
{
	String*	name;
	WORD	height;
	WORD	ascent;
	Draw_Display*	display;
};
#define Draw_Font_size 16
#define Draw_Font_map {0x90,}
struct Draw_Screen
{
	WORD	id;
	Draw_Image*	image;
	Draw_Image*	fill;
	Draw_Display*	display;
};
#define Draw_Screen_size 16
#define Draw_Screen_map {0x70,}
struct Draw_Pointer
{
	WORD	buttons;
	Draw_Point	xy;
};
#define Draw_Pointer_size 12
#define Draw_Pointer_map {0}
struct Draw_Context
{
	Draw_Screen*	screen;
	Draw_Display*	display;
	Channel*	cir;
	Channel*	ckbd;
	Channel*	cptr;
	Channel*	ctoappl;
	Channel*	ctomux;
};
typedef WORD Draw_Context_cir;
#define Draw_Context_cir_size 4
#define Draw_Context_cir_map {0}
typedef WORD Draw_Context_ckbd;
#define Draw_Context_ckbd_size 4
#define Draw_Context_ckbd_map {0}
typedef Draw_Pointer* Draw_Context_cptr;
#define Draw_Context_cptr_size 4
#define Draw_Context_cptr_map {0x80,}
typedef WORD Draw_Context_ctoappl;
#define Draw_Context_ctoappl_size 4
#define Draw_Context_ctoappl_map {0}
typedef WORD Draw_Context_ctomux;
#define Draw_Context_ctomux_size 4
#define Draw_Context_ctomux_map {0}
#define Draw_Context_size 28
#define Draw_Context_map {0xfe,}
struct Prefab_Style
{
	Draw_Font*	titlefont;
	Draw_Font*	textfont;
	Draw_Image*	elemcolor;
	Draw_Image*	edgecolor;
	Draw_Image*	titlecolor;
	Draw_Image*	textcolor;
	Draw_Image*	highlightcolor;
};
#define Prefab_Style_size 28
#define Prefab_Style_map {0xfe,}
struct Prefab_Environ
{
	Draw_Screen*	screen;
	Prefab_Style*	style;
};
#define Prefab_Environ_size 8
#define Prefab_Environ_map {0xc0,}
struct Prefab_Layout
{
	Draw_Font*	font;
	Draw_Image*	color;
	String*	text;
	Draw_Image*	icon;
	Draw_Image*	mask;
	String*	tag;
};
#define Prefab_Layout_size 24
#define Prefab_Layout_map {0xfc,}
struct Prefab_Element
{
	WORD	kind;
	Draw_Rect	r;
	Prefab_Environ*	environ;
	String*	tag;
	List*	kids;
	String*	str;
	Draw_Image*	mask;
	Draw_Image*	image;
	Draw_Font*	font;
};
#define Prefab_Element_size 48
#define Prefab_Element_map {0x7,0xf0,}
struct Prefab_Compound
{
	Draw_Image*	image;
	Prefab_Environ*	environ;
	Draw_Rect	r;
	Prefab_Element*	title;
	Prefab_Element*	contents;
};
#define Prefab_Compound_size 32
#define Prefab_Compound_map {0xc3,}
struct Tk_Toplevel
{
	WORD	id;
	Draw_Image*	image;
};
#define Tk_Toplevel_size 8
#define Tk_Toplevel_map {0x40,}
struct Keyring_IPint
{
	WORD	x;
};
#define Keyring_IPint_size 4
#define Keyring_IPint_map {0}
struct Keyring_SigAlg
{
	String*	name;
};
#define Keyring_SigAlg_size 4
#define Keyring_SigAlg_map {0x80,}
struct Keyring_PK
{
	Keyring_SigAlg*	sa;
	String*	owner;
};
#define Keyring_PK_size 8
#define Keyring_PK_map {0xc0,}
struct Keyring_SK
{
	Keyring_SigAlg*	sa;
	String*	owner;
};
#define Keyring_SK_size 8
#define Keyring_SK_map {0xc0,}
struct Keyring_Certificate
{
	Keyring_SigAlg*	sa;
	String*	ha;
	String*	signer;
	WORD	exp;
};
#define Keyring_Certificate_size 16
#define Keyring_Certificate_map {0xe0,}
struct Keyring_DigestState
{
	WORD	x;
};
#define Keyring_DigestState_size 4
#define Keyring_DigestState_map {0}
struct Keyring_DESstate
{
	WORD	x;
};
#define Keyring_DESstate_size 4
#define Keyring_DESstate_map {0}
struct Keyring_IDEAstate
{
	WORD	x;
};
#define Keyring_IDEAstate_size 4
#define Keyring_IDEAstate_map {0}
struct Keyring_Authinfo
{
	Keyring_SK*	mysk;
	Keyring_PK*	mypk;
	Keyring_Certificate*	cert;
	Keyring_PK*	spk;
	Keyring_IPint*	alpha;
	Keyring_IPint*	p;
};
#define Keyring_Authinfo_size 24
#define Keyring_Authinfo_map {0xfc,}
struct Loader_Inst
{
	BYTE	op;
	BYTE	addr;
	uchar	_pad2[2];
	WORD	src;
	WORD	mid;
	WORD	dst;
};
#define Loader_Inst_size 16
#define Loader_Inst_map {0}
struct Loader_Typedesc
{
	WORD	size;
	Array*	map;
};
#define Loader_Typedesc_size 8
#define Loader_Typedesc_map {0x40,}
struct Loader_Link
{
	String*	name;
	WORD	sig;
	WORD	pc;
	WORD	tdesc;
};
#define Loader_Link_size 16
#define Loader_Link_map {0x80,}
struct Loader_Niladt
{
	char	dummy[1];
	uchar	_pad1[3];
};
#define Loader_Niladt_size 4
#define Loader_Niladt_map {0}
void Sys_announce(void*);
typedef struct F_Sys_announce F_Sys_announce;
struct F_Sys_announce
{
	WORD	regs[NREG-1];
	struct{ WORD t0; Sys_Connection t1; }*	ret;
	uchar	temps[12];
	String*	addr;
};
void Sys_aprint(void*);
typedef struct F_Sys_aprint F_Sys_aprint;
struct F_Sys_aprint
{
	WORD	regs[NREG-1];
	Array**	ret;
	uchar	temps[12];
	String*	s;
	WORD	vargs;
};
void Sys_bind(void*);
typedef struct F_Sys_bind F_Sys_bind;
struct F_Sys_bind
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	String*	s;
	String*	on;
	WORD	flags;
};
void Sys_byte2char(void*);
typedef struct F_Sys_byte2char F_Sys_byte2char;
struct F_Sys_byte2char
{
	WORD	regs[NREG-1];
	struct{ WORD t0; WORD t1; WORD t2; }*	ret;
	uchar	temps[12];
	Array*	buf;
	WORD	n;
};
void Sys_char2byte(void*);
typedef struct F_Sys_char2byte F_Sys_char2byte;
struct F_Sys_char2byte
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	WORD	c;
	Array*	buf;
	WORD	n;
};
void Sys_chdir(void*);
typedef struct F_Sys_chdir F_Sys_chdir;
struct F_Sys_chdir
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	String*	path;
};
void Sys_create(void*);
typedef struct F_Sys_create F_Sys_create;
struct F_Sys_create
{
	WORD	regs[NREG-1];
	Sys_FD**	ret;
	uchar	temps[12];
	String*	s;
	WORD	mode;
	WORD	perm;
};
void Sys_dial(void*);
typedef struct F_Sys_dial F_Sys_dial;
struct F_Sys_dial
{
	WORD	regs[NREG-1];
	struct{ WORD t0; Sys_Connection t1; }*	ret;
	uchar	temps[12];
	String*	addr;
	String*	local;
};
void Sys_dirread(void*);
typedef struct F_Sys_dirread F_Sys_dirread;
struct F_Sys_dirread
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Sys_FD*	fd;
	Array*	dir;
};
void Sys_dup(void*);
typedef struct F_Sys_dup F_Sys_dup;
struct F_Sys_dup
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	WORD	old;
	WORD	new;
};
void Sys_export(void*);
typedef struct F_Sys_export F_Sys_export;
struct F_Sys_export
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Sys_FD*	c;
	WORD	flag;
};
void Sys_exportdir(void*);
typedef struct F_Sys_exportdir F_Sys_exportdir;
struct F_Sys_exportdir
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Sys_FD*	c;
	String*	dir;
	WORD	flag;
};
void Sys_fildes(void*);
typedef struct F_Sys_fildes F_Sys_fildes;
struct F_Sys_fildes
{
	WORD	regs[NREG-1];
	Sys_FD**	ret;
	uchar	temps[12];
	WORD	fd;
};
void Sys_file2chan(void*);
typedef struct F_Sys_file2chan F_Sys_file2chan;
struct F_Sys_file2chan
{
	WORD	regs[NREG-1];
	Sys_FileIO**	ret;
	uchar	temps[12];
	String*	dir;
	String*	file;
};
void Sys_fprint(void*);
typedef struct F_Sys_fprint F_Sys_fprint;
struct F_Sys_fprint
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Sys_FD*	fd;
	String*	s;
	WORD	vargs;
};
void Sys_fstat(void*);
typedef struct F_Sys_fstat F_Sys_fstat;
struct F_Sys_fstat
{
	WORD	regs[NREG-1];
	struct{ WORD t0; Sys_Dir t1; }*	ret;
	uchar	temps[12];
	Sys_FD*	fd;
};
void Sys_fwstat(void*);
typedef struct F_Sys_fwstat F_Sys_fwstat;
struct F_Sys_fwstat
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Sys_FD*	fd;
	Sys_Dir	d;
};
void Sys_listen(void*);
typedef struct F_Sys_listen F_Sys_listen;
struct F_Sys_listen
{
	WORD	regs[NREG-1];
	struct{ WORD t0; Sys_Connection t1; }*	ret;
	uchar	temps[12];
	Sys_Connection	c;
};
void Sys_millisec(void*);
typedef struct F_Sys_millisec F_Sys_millisec;
struct F_Sys_millisec
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
};
void Sys_mount(void*);
typedef struct F_Sys_mount F_Sys_mount;
struct F_Sys_mount
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Sys_FD*	fd;
	String*	on;
	WORD	flags;
	String*	spec;
};
void Sys_open(void*);
typedef struct F_Sys_open F_Sys_open;
struct F_Sys_open
{
	WORD	regs[NREG-1];
	Sys_FD**	ret;
	uchar	temps[12];
	String*	s;
	WORD	mode;
};
void Sys_pctl(void*);
typedef struct F_Sys_pctl F_Sys_pctl;
struct F_Sys_pctl
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	WORD	flags;
	List*	movefd;
};
void Sys_pipe(void*);
typedef struct F_Sys_pipe F_Sys_pipe;
struct F_Sys_pipe
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Array*	fds;
};
void Sys_print(void*);
typedef struct F_Sys_print F_Sys_print;
struct F_Sys_print
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	String*	s;
	WORD	vargs;
};
void Sys_raise(void*);
typedef struct F_Sys_raise F_Sys_raise;
struct F_Sys_raise
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[12];
	String*	s;
};
void Sys_read(void*);
typedef struct F_Sys_read F_Sys_read;
struct F_Sys_read
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Sys_FD*	fd;
	Array*	buf;
	WORD	n;
};
void Sys_remove(void*);
typedef struct F_Sys_remove F_Sys_remove;
struct F_Sys_remove
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	String*	s;
};
void Sys_rescue(void*);
typedef struct F_Sys_rescue F_Sys_rescue;
struct F_Sys_rescue
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	String*	s;
	Sys_Exception*	e;
};
void Sys_rescued(void*);
typedef struct F_Sys_rescued F_Sys_rescued;
struct F_Sys_rescued
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	WORD	flag;
	String*	s;
};
void Sys_seek(void*);
typedef struct F_Sys_seek F_Sys_seek;
struct F_Sys_seek
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Sys_FD*	fd;
	WORD	off;
	WORD	start;
};
void Sys_sleep(void*);
typedef struct F_Sys_sleep F_Sys_sleep;
struct F_Sys_sleep
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	WORD	period;
};
void Sys_sprint(void*);
typedef struct F_Sys_sprint F_Sys_sprint;
struct F_Sys_sprint
{
	WORD	regs[NREG-1];
	String**	ret;
	uchar	temps[12];
	String*	s;
	WORD	vargs;
};
void Sys_stat(void*);
typedef struct F_Sys_stat F_Sys_stat;
struct F_Sys_stat
{
	WORD	regs[NREG-1];
	struct{ WORD t0; Sys_Dir t1; }*	ret;
	uchar	temps[12];
	String*	s;
};
void Sys_stream(void*);
typedef struct F_Sys_stream F_Sys_stream;
struct F_Sys_stream
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Sys_FD*	src;
	Sys_FD*	dst;
	WORD	bufsiz;
};
void Sys_tokenize(void*);
typedef struct F_Sys_tokenize F_Sys_tokenize;
struct F_Sys_tokenize
{
	WORD	regs[NREG-1];
	struct{ WORD t0; List* t1; }*	ret;
	uchar	temps[12];
	String*	s;
	String*	delim;
};
void Sys_unmount(void*);
typedef struct F_Sys_unmount F_Sys_unmount;
struct F_Sys_unmount
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	String*	s1;
	String*	s2;
};
void Sys_unrescue(void*);
typedef struct F_Sys_unrescue F_Sys_unrescue;
struct F_Sys_unrescue
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[12];
};
void Sys_utfbytes(void*);
typedef struct F_Sys_utfbytes F_Sys_utfbytes;
struct F_Sys_utfbytes
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Array*	buf;
	WORD	n;
};
void Sys_write(void*);
typedef struct F_Sys_write F_Sys_write;
struct F_Sys_write
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Sys_FD*	fd;
	Array*	buf;
	WORD	n;
};
void Sys_wstat(void*);
typedef struct F_Sys_wstat F_Sys_wstat;
struct F_Sys_wstat
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	String*	s;
	Sys_Dir	d;
};
#define Sys_PATH "$Sys"
#define Sys_HANDLER 0
#define Sys_EXCEPTION 1
#define Sys_ACTIVE 2
#define Sys_RAISE 3
#define Sys_EXIT 4
#define Sys_ONCE 5
#define Sys_ATOMICIO 8192
#define Sys_NAMELEN 28
#define Sys_SEEKSTART 0
#define Sys_SEEKRELA 1
#define Sys_SEEKEND 2
#define Sys_ERRLEN 64
#define Sys_WAITLEN 64
#define Sys_OREAD 0
#define Sys_OWRITE 1
#define Sys_ORDWR 2
#define Sys_OTRUNC 16
#define Sys_ORCLOSE 64
#define Sys_CHDIR -2147483648
#define Sys_DMDIR -2147483648
#define Sys_DMAPPEND 1073741824
#define Sys_DMEXCL 536870912
#define Sys_DMAUTH 134217728
#define Sys_MREPL 0
#define Sys_MBEFORE 1
#define Sys_MAFTER 2
#define Sys_MCREATE 4
#define Sys_NEWFD 1
#define Sys_FORKFD 2
#define Sys_NEWNS 4
#define Sys_FORKNS 8
#define Sys_NEWPGRP 16
#define Sys_NODEVS 32
#define Sys_NEWENV 64
#define Sys_FORKENV 128
#define Sys_EXPWAIT 0
#define Sys_EXPASYNC 1
#define Sys_UTFmax 3
#define Sys_UTFerror 128
void Rect_Xrect(void*);
typedef struct F_Rect_Xrect F_Rect_Xrect;
struct F_Rect_Xrect
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Draw_Rect	r;
	Draw_Rect	s;
};
void Point_add(void*);
typedef struct F_Point_add F_Point_add;
struct F_Point_add
{
	WORD	regs[NREG-1];
	Draw_Point*	ret;
	uchar	temps[12];
	Draw_Point	p;
	Draw_Point	q;
};
void Rect_addpt(void*);
typedef struct F_Rect_addpt F_Rect_addpt;
struct F_Rect_addpt
{
	WORD	regs[NREG-1];
	Draw_Rect*	ret;
	uchar	temps[12];
	Draw_Rect	r;
	Draw_Point	p;
};
void Display_allocate(void*);
typedef struct F_Display_allocate F_Display_allocate;
struct F_Display_allocate
{
	WORD	regs[NREG-1];
	Draw_Display**	ret;
	uchar	temps[12];
	String*	dev;
};
void Screen_allocate(void*);
typedef struct F_Screen_allocate F_Screen_allocate;
struct F_Screen_allocate
{
	WORD	regs[NREG-1];
	Draw_Screen**	ret;
	uchar	temps[12];
	Draw_Image*	image;
	Draw_Image*	fill;
	WORD	public;
};
void Image_arc(void*);
typedef struct F_Image_arc F_Image_arc;
struct F_Image_arc
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[12];
	Draw_Image*	dst;
	Draw_Point	c;
	WORD	a;
	WORD	b;
	WORD	thick;
	Draw_Image*	src;
	Draw_Point	sp;
	WORD	alpha;
	WORD	phi;
};
void Image_arrow(void*);
typedef struct F_Image_arrow F_Image_arrow;
struct F_Image_arrow
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	WORD	a;
	WORD	b;
	WORD	c;
};
void Font_bbox(void*);
typedef struct F_Font_bbox F_Font_bbox;
struct F_Font_bbox
{
	WORD	regs[NREG-1];
	Draw_Rect*	ret;
	uchar	temps[12];
	Draw_Font*	f;
	String*	str;
};
void Image_bezier(void*);
typedef struct F_Image_bezier F_Image_bezier;
struct F_Image_bezier
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[12];
	Draw_Image*	dst;
	Draw_Point	a;
	Draw_Point	b;
	Draw_Point	c;
	Draw_Point	d;
	WORD	end0;
	WORD	end1;
	WORD	radius;
	Draw_Image*	src;
	Draw_Point	sp;
};
void Image_bezspline(void*);
typedef struct F_Image_bezspline F_Image_bezspline;
struct F_Image_bezspline
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[12];
	Draw_Image*	dst;
	Array*	p;
	WORD	end0;
	WORD	end1;
	WORD	radius;
	Draw_Image*	src;
	Draw_Point	sp;
};
void Image_bottom(void*);
typedef struct F_Image_bottom F_Image_bottom;
struct F_Image_bottom
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[12];
	Draw_Image*	win;
};
void Font_build(void*);
typedef struct F_Font_build F_Font_build;
struct F_Font_build
{
	WORD	regs[NREG-1];
	Draw_Font**	ret;
	uchar	temps[12];
	Draw_Display*	d;
	String*	name;
	String*	desc;
};
void Rect_canon(void*);
typedef struct F_Rect_canon F_Rect_canon;
struct F_Rect_canon
{
	WORD	regs[NREG-1];
	Draw_Rect*	ret;
	uchar	temps[12];
	Draw_Rect	r;
};
void Rect_clip(void*);
typedef struct F_Rect_clip F_Rect_clip;
struct F_Rect_clip
{
	WORD	regs[NREG-1];
	struct{ Draw_Rect t0; WORD t1; }*	ret;
	uchar	temps[12];
	Draw_Rect	r;
	Draw_Rect	s;
};
void Display_cmap2rgb(void*);
typedef struct F_Display_cmap2rgb F_Display_cmap2rgb;
struct F_Display_cmap2rgb
{
	WORD	regs[NREG-1];
	struct{ WORD t0; WORD t1; WORD t2; }*	ret;
	uchar	temps[12];
	Draw_Display*	d;
	WORD	c;
};
void Display_color(void*);
typedef struct F_Display_color F_Display_color;
struct F_Display_color
{
	WORD	regs[NREG-1];
	Draw_Image**	ret;
	uchar	temps[12];
	Draw_Display*	d;
	WORD	color;
};
void Rect_combine(void*);
typedef struct F_Rect_combine F_Rect_combine;
struct F_Rect_combine
{
	WORD	regs[NREG-1];
	Draw_Rect*	ret;
	uchar	temps[12];
	Draw_Rect	r;
	Draw_Rect	s;
};
void Rect_contains(void*);
typedef struct F_Rect_contains F_Rect_contains;
struct F_Rect_contains
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Draw_Rect	r;
	Draw_Point	p;
};
void Display_cursor(void*);
typedef struct F_Display_cursor F_Display_cursor;
struct F_Display_cursor
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Draw_Display*	d;
	Draw_Image*	i;
	Draw_Point*	p;
};
void Display_cursorset(void*);
typedef struct F_Display_cursorset F_Display_cursorset;
struct F_Display_cursorset
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[12];
	Draw_Display*	d;
	Draw_Point	p;
};
void Point_div(void*);
typedef struct F_Point_div F_Point_div;
struct F_Point_div
{
	WORD	regs[NREG-1];
	Draw_Point*	ret;
	uchar	temps[12];
	Draw_Point	p;
	WORD	i;
};
void Image_draw(void*);
typedef struct F_Image_draw F_Image_draw;
struct F_Image_draw
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[12];
	Draw_Image*	dst;
	Draw_Rect	r;
	Draw_Image*	src;
	Draw_Image*	mask;
	Draw_Point	p;
};
void Rect_dx(void*);
typedef struct F_Rect_dx F_Rect_dx;
struct F_Rect_dx
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Draw_Rect	r;
};
void Rect_dy(void*);
typedef struct F_Rect_dy F_Rect_dy;
struct F_Rect_dy
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Draw_Rect	r;
};
void Image_ellipse(void*);
typedef struct F_Image_ellipse F_Image_ellipse;
struct F_Image_ellipse
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[12];
	Draw_Image*	dst;
	Draw_Point	c;
	WORD	a;
	WORD	b;
	WORD	thick;
	Draw_Image*	src;
	Draw_Point	sp;
};
void Point_eq(void*);
typedef struct F_Point_eq F_Point_eq;
struct F_Point_eq
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Draw_Point	p;
	Draw_Point	q;
};
void Rect_eq(void*);
typedef struct F_Rect_eq F_Rect_eq;
struct F_Rect_eq
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Draw_Rect	r;
	Draw_Rect	s;
};
void Image_fillarc(void*);
typedef struct F_Image_fillarc F_Image_fillarc;
struct F_Image_fillarc
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[12];
	Draw_Image*	dst;
	Draw_Point	c;
	WORD	a;
	WORD	b;
	Draw_Image*	src;
	Draw_Point	sp;
	WORD	alpha;
	WORD	phi;
};
void Image_fillbezier(void*);
typedef struct F_Image_fillbezier F_Image_fillbezier;
struct F_Image_fillbezier
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[12];
	Draw_Image*	dst;
	Draw_Point	a;
	Draw_Point	b;
	Draw_Point	c;
	Draw_Point	d;
	WORD	wind;
	Draw_Image*	src;
	Draw_Point	sp;
};
void Image_fillbezspline(void*);
typedef struct F_Image_fillbezspline F_Image_fillbezspline;
struct F_Image_fillbezspline
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[12];
	Draw_Image*	dst;
	Array*	p;
	WORD	wind;
	Draw_Image*	src;
	Draw_Point	sp;
};
void Image_fillellipse(void*);
typedef struct F_Image_fillellipse F_Image_fillellipse;
struct F_Image_fillellipse
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[12];
	Draw_Image*	dst;
	Draw_Point	c;
	WORD	a;
	WORD	b;
	Draw_Image*	src;
	Draw_Point	sp;
};
void Image_fillpoly(void*);
typedef struct F_Image_fillpoly F_Image_fillpoly;
struct F_Image_fillpoly
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[12];
	Draw_Image*	dst;
	Array*	p;
	WORD	wind;
	Draw_Image*	src;
	Draw_Point	sp;
};
void Image_flush(void*);
typedef struct F_Image_flush F_Image_flush;
struct F_Image_flush
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[12];
	Draw_Image*	win;
	WORD	func;
};
void Image_gendraw(void*);
typedef struct F_Image_gendraw F_Image_gendraw;
struct F_Image_gendraw
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[12];
	Draw_Image*	dst;
	Draw_Rect	r;
	Draw_Image*	src;
	Draw_Point	p0;
	Draw_Image*	mask;
	Draw_Point	p1;
};
void Point_in(void*);
typedef struct F_Point_in F_Point_in;
struct F_Point_in
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Draw_Point	p;
	Draw_Rect	r;
};
void Rect_inrect(void*);
typedef struct F_Rect_inrect F_Rect_inrect;
struct F_Rect_inrect
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Draw_Rect	r;
	Draw_Rect	s;
};
void Rect_inset(void*);
typedef struct F_Rect_inset F_Rect_inset;
struct F_Rect_inset
{
	WORD	regs[NREG-1];
	Draw_Rect*	ret;
	uchar	temps[12];
	Draw_Rect	r;
	WORD	n;
};
void Image_line(void*);
typedef struct F_Image_line F_Image_line;
struct F_Image_line
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[12];
	Draw_Image*	dst;
	Draw_Point	p0;
	Draw_Point	p1;
	WORD	end0;
	WORD	end1;
	WORD	radius;
	Draw_Image*	src;
	Draw_Point	sp;
};
void Point_mul(void*);
typedef struct F_Point_mul F_Point_mul;
struct F_Point_mul
{
	WORD	regs[NREG-1];
	Draw_Point*	ret;
	uchar	temps[12];
	Draw_Point	p;
	WORD	i;
};
void Display_newimage(void*);
typedef struct F_Display_newimage F_Display_newimage;
struct F_Display_newimage
{
	WORD	regs[NREG-1];
	Draw_Image**	ret;
	uchar	temps[12];
	Draw_Display*	d;
	Draw_Rect	r;
	WORD	ldepth;
	WORD	repl;
	WORD	color;
};
void Screen_newwindow(void*);
typedef struct F_Screen_newwindow F_Screen_newwindow;
struct F_Screen_newwindow
{
	WORD	regs[NREG-1];
	Draw_Image**	ret;
	uchar	temps[12];
	Draw_Screen*	screen;
	Draw_Rect	r;
	WORD	color;
};
void Display_open(void*);
typedef struct F_Display_open F_Display_open;
struct F_Display_open
{
	WORD	regs[NREG-1];
	Draw_Image**	ret;
	uchar	temps[12];
	Draw_Display*	d;
	String*	name;
};
void Font_open(void*);
typedef struct F_Font_open F_Font_open;
struct F_Font_open
{
	WORD	regs[NREG-1];
	Draw_Font**	ret;
	uchar	temps[12];
	Draw_Display*	d;
	String*	name;
};
void Image_origin(void*);
typedef struct F_Image_origin F_Image_origin;
struct F_Image_origin
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Draw_Image*	win;
	Draw_Point	log;
	Draw_Point	scr;
};
void Image_poly(void*);
typedef struct F_Image_poly F_Image_poly;
struct F_Image_poly
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[12];
	Draw_Image*	dst;
	Array*	p;
	WORD	end0;
	WORD	end1;
	WORD	radius;
	Draw_Image*	src;
	Draw_Point	sp;
};
void Display_publicscreen(void*);
typedef struct F_Display_publicscreen F_Display_publicscreen;
struct F_Display_publicscreen
{
	WORD	regs[NREG-1];
	Draw_Screen**	ret;
	uchar	temps[12];
	Draw_Display*	d;
	WORD	id;
};
void Display_readimage(void*);
typedef struct F_Display_readimage F_Display_readimage;
struct F_Display_readimage
{
	WORD	regs[NREG-1];
	Draw_Image**	ret;
	uchar	temps[12];
	Draw_Display*	d;
	Sys_FD*	fd;
};
void Image_readpixels(void*);
typedef struct F_Image_readpixels F_Image_readpixels;
struct F_Image_readpixels
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Draw_Image*	src;
	Draw_Rect	r;
	Array*	data;
};
void Display_rgb(void*);
typedef struct F_Display_rgb F_Display_rgb;
struct F_Display_rgb
{
	WORD	regs[NREG-1];
	Draw_Image**	ret;
	uchar	temps[12];
	Draw_Display*	d;
	WORD	r;
	WORD	g;
	WORD	b;
};
void Display_rgb2cmap(void*);
typedef struct F_Display_rgb2cmap F_Display_rgb2cmap;
struct F_Display_rgb2cmap
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Draw_Display*	d;
	WORD	r;
	WORD	g;
	WORD	b;
};
void Display_startrefresh(void*);
typedef struct F_Display_startrefresh F_Display_startrefresh;
struct F_Display_startrefresh
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[12];
	Draw_Display*	d;
};
void Point_sub(void*);
typedef struct F_Point_sub F_Point_sub;
struct F_Point_sub
{
	WORD	regs[NREG-1];
	Draw_Point*	ret;
	uchar	temps[12];
	Draw_Point	p;
	Draw_Point	q;
};
void Rect_subpt(void*);
typedef struct F_Rect_subpt F_Rect_subpt;
struct F_Rect_subpt
{
	WORD	regs[NREG-1];
	Draw_Rect*	ret;
	uchar	temps[12];
	Draw_Rect	r;
	Draw_Point	p;
};
void Image_text(void*);
typedef struct F_Image_text F_Image_text;
struct F_Image_text
{
	WORD	regs[NREG-1];
	Draw_Point*	ret;
	uchar	temps[12];
	Draw_Image*	dst;
	Draw_Point	p;
	Draw_Image*	src;
	Draw_Point	sp;
	Draw_Font*	font;
	String*	str;
};
void Image_top(void*);
typedef struct F_Image_top F_Image_top;
struct F_Image_top
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[12];
	Draw_Image*	win;
};
void Screen_top(void*);
typedef struct F_Screen_top F_Screen_top;
struct F_Screen_top
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[12];
	Draw_Screen*	screen;
	Array*	wins;
};
void Font_width(void*);
typedef struct F_Font_width F_Font_width;
struct F_Font_width
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Draw_Font*	f;
	String*	str;
};
void Display_writeimage(void*);
typedef struct F_Display_writeimage F_Display_writeimage;
struct F_Display_writeimage
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Draw_Display*	d;
	Sys_FD*	fd;
	Draw_Image*	i;
};
void Image_writepixels(void*);
typedef struct F_Image_writepixels F_Image_writepixels;
struct F_Image_writepixels
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Draw_Image*	dst;
	Draw_Rect	r;
	Array*	data;
};
#define Draw_PATH "$Draw"
#define Draw_Black 255
#define Draw_Blue 201
#define Draw_Red 15
#define Draw_Yellow 3
#define Draw_Green 192
#define Draw_White 0
#define Draw_Endsquare 0
#define Draw_Enddisc 1
#define Draw_Endarrow 2
#define Draw_Flushoff 0
#define Draw_Flushon 1
#define Draw_Flushnow 2
#define Draw_AMexit 10
#define Draw_AMstartir 11
#define Draw_AMstartkbd 12
#define Draw_AMstartptr 13
#define Draw_AMnewpin 14
#define Draw_MAtop 20
void Element_adjust(void*);
typedef struct F_Element_adjust F_Element_adjust;
struct F_Element_adjust
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[12];
	Prefab_Element*	elem;
	WORD	equal;
	WORD	dir;
};
void Element_append(void*);
typedef struct F_Element_append F_Element_append;
struct F_Element_append
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Prefab_Element*	elist;
	Prefab_Element*	elem;
};
void Compound_box(void*);
typedef struct F_Compound_box F_Compound_box;
struct F_Compound_box
{
	WORD	regs[NREG-1];
	Prefab_Compound**	ret;
	uchar	temps[12];
	Prefab_Environ*	env;
	Draw_Point	p;
	Prefab_Element*	title;
	Prefab_Element*	elist;
};
void Element_clip(void*);
typedef struct F_Element_clip F_Element_clip;
struct F_Element_clip
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[12];
	Prefab_Element*	elem;
	Draw_Rect	r;
};
void Compound_draw(void*);
typedef struct F_Compound_draw F_Compound_draw;
struct F_Compound_draw
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[12];
	Prefab_Compound*	comp;
};
void Element_elist(void*);
typedef struct F_Element_elist F_Element_elist;
struct F_Element_elist
{
	WORD	regs[NREG-1];
	Prefab_Element**	ret;
	uchar	temps[12];
	Prefab_Environ*	env;
	Prefab_Element*	elem;
	WORD	kind;
};
void Compound_highlight(void*);
typedef struct F_Compound_highlight F_Compound_highlight;
struct F_Compound_highlight
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[12];
	Prefab_Compound*	comp;
	Prefab_Element*	elem;
	WORD	on;
};
void Element_icon(void*);
typedef struct F_Element_icon F_Element_icon;
struct F_Element_icon
{
	WORD	regs[NREG-1];
	Prefab_Element**	ret;
	uchar	temps[12];
	Prefab_Environ*	env;
	Draw_Rect	r;
	Draw_Image*	icon;
	Draw_Image*	mask;
};
void Compound_iconbox(void*);
typedef struct F_Compound_iconbox F_Compound_iconbox;
struct F_Compound_iconbox
{
	WORD	regs[NREG-1];
	Prefab_Compound**	ret;
	uchar	temps[12];
	Prefab_Environ*	env;
	Draw_Point	p;
	String*	title;
	Draw_Image*	icon;
	Draw_Image*	mask;
};
void Element_layout(void*);
typedef struct F_Element_layout F_Element_layout;
struct F_Element_layout
{
	WORD	regs[NREG-1];
	Prefab_Element**	ret;
	uchar	temps[12];
	Prefab_Environ*	env;
	List*	lay;
	Draw_Rect	r;
	WORD	kind;
};
void Compound_layoutbox(void*);
typedef struct F_Compound_layoutbox F_Compound_layoutbox;
struct F_Compound_layoutbox
{
	WORD	regs[NREG-1];
	Prefab_Compound**	ret;
	uchar	temps[12];
	Prefab_Environ*	env;
	Draw_Rect	r;
	String*	title;
	List*	lay;
};
void Compound_redraw(void*);
typedef struct F_Compound_redraw F_Compound_redraw;
struct F_Compound_redraw
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[12];
	Prefab_Compound*	comp;
	Draw_Rect	r;
};
void Element_scroll(void*);
typedef struct F_Element_scroll F_Element_scroll;
struct F_Element_scroll
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[12];
	Prefab_Element*	elem;
	Draw_Point	d;
};
void Compound_scroll(void*);
typedef struct F_Compound_scroll F_Compound_scroll;
struct F_Compound_scroll
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[12];
	Prefab_Compound*	comp;
	Prefab_Element*	elem;
	Draw_Point	d;
};
void Compound_select(void*);
typedef struct F_Compound_select F_Compound_select;
struct F_Compound_select
{
	WORD	regs[NREG-1];
	struct{ WORD t0; WORD t1; Prefab_Element* t2; }*	ret;
	uchar	temps[12];
	Prefab_Compound*	comp;
	Prefab_Element*	elem;
	WORD	i;
	Channel*	c;
};
void Element_separator(void*);
typedef struct F_Element_separator F_Element_separator;
struct F_Element_separator
{
	WORD	regs[NREG-1];
	Prefab_Element**	ret;
	uchar	temps[12];
	Prefab_Environ*	env;
	Draw_Rect	r;
	Draw_Image*	icon;
	Draw_Image*	mask;
};
void Element_show(void*);
typedef struct F_Element_show F_Element_show;
struct F_Element_show
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Prefab_Element*	elist;
	Prefab_Element*	elem;
};
void Compound_show(void*);
typedef struct F_Compound_show F_Compound_show;
struct F_Compound_show
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Prefab_Compound*	comp;
	Prefab_Element*	elem;
};
void Compound_tagselect(void*);
typedef struct F_Compound_tagselect F_Compound_tagselect;
struct F_Compound_tagselect
{
	WORD	regs[NREG-1];
	struct{ WORD t0; WORD t1; Prefab_Element* t2; }*	ret;
	uchar	temps[12];
	Prefab_Compound*	comp;
	Prefab_Element*	elem;
	WORD	i;
	Channel*	c;
};
void Element_text(void*);
typedef struct F_Element_text F_Element_text;
struct F_Element_text
{
	WORD	regs[NREG-1];
	Prefab_Element**	ret;
	uchar	temps[12];
	Prefab_Environ*	env;
	String*	text;
	Draw_Rect	r;
	WORD	kind;
};
void Compound_textbox(void*);
typedef struct F_Compound_textbox F_Compound_textbox;
struct F_Compound_textbox
{
	WORD	regs[NREG-1];
	Prefab_Compound**	ret;
	uchar	temps[12];
	Prefab_Environ*	env;
	Draw_Rect	r;
	String*	title;
	String*	text;
};
void Element_translate(void*);
typedef struct F_Element_translate F_Element_translate;
struct F_Element_translate
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[12];
	Prefab_Element*	elem;
	Draw_Point	d;
};
#define Prefab_PATH "$Prefab"
#define Prefab_EIcon 0
#define Prefab_EText 1
#define Prefab_ETitle 2
#define Prefab_EHorizontal 3
#define Prefab_EVertical 4
#define Prefab_ESeparator 5
#define Prefab_Adjpack 10
#define Prefab_Adjequal 11
#define Prefab_Adjfill 12
#define Prefab_Adjleft 20
#define Prefab_Adjup 20
#define Prefab_Adjcenter 21
#define Prefab_Adjright 22
#define Prefab_Adjdown 22
void Tk_cmd(void*);
typedef struct F_Tk_cmd F_Tk_cmd;
struct F_Tk_cmd
{
	WORD	regs[NREG-1];
	String**	ret;
	uchar	temps[12];
	Tk_Toplevel*	t;
	String*	arg;
};
void Tk_imageget(void*);
typedef struct F_Tk_imageget F_Tk_imageget;
struct F_Tk_imageget
{
	WORD	regs[NREG-1];
	struct{ Draw_Image* t0; Draw_Image* t1; String* t2; }*	ret;
	uchar	temps[12];
	Tk_Toplevel*	t;
	String*	name;
};
void Tk_imageput(void*);
typedef struct F_Tk_imageput F_Tk_imageput;
struct F_Tk_imageput
{
	WORD	regs[NREG-1];
	String**	ret;
	uchar	temps[12];
	Tk_Toplevel*	t;
	String*	name;
	Draw_Image*	i;
	Draw_Image*	m;
};
void Tk_intop(void*);
typedef struct F_Tk_intop F_Tk_intop;
struct F_Tk_intop
{
	WORD	regs[NREG-1];
	Tk_Toplevel**	ret;
	uchar	temps[12];
	Draw_Screen*	screen;
	WORD	x;
	WORD	y;
};
void Tk_keyboard(void*);
typedef struct F_Tk_keyboard F_Tk_keyboard;
struct F_Tk_keyboard
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[12];
	Draw_Screen*	screen;
	WORD	key;
};
void Tk_mouse(void*);
typedef struct F_Tk_mouse F_Tk_mouse;
struct F_Tk_mouse
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[12];
	Draw_Screen*	screen;
	WORD	x;
	WORD	y;
	WORD	button;
};
void Tk_namechan(void*);
typedef struct F_Tk_namechan F_Tk_namechan;
struct F_Tk_namechan
{
	WORD	regs[NREG-1];
	String**	ret;
	uchar	temps[12];
	Tk_Toplevel*	t;
	Channel*	c;
	String*	n;
};
void Tk_toplevel(void*);
typedef struct F_Tk_toplevel F_Tk_toplevel;
struct F_Tk_toplevel
{
	WORD	regs[NREG-1];
	Tk_Toplevel**	ret;
	uchar	temps[12];
	Draw_Screen*	screen;
	String*	arg;
};
void Tk_windows(void*);
typedef struct F_Tk_windows F_Tk_windows;
struct F_Tk_windows
{
	WORD	regs[NREG-1];
	List**	ret;
	uchar	temps[12];
	Draw_Screen*	screen;
};
#define Tk_PATH "$Tk"
void Math_FPcontrol(void*);
typedef struct F_Math_FPcontrol F_Math_FPcontrol;
struct F_Math_FPcontrol
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	WORD	r;
	WORD	mask;
};
void Math_FPstatus(void*);
typedef struct F_Math_FPstatus F_Math_FPstatus;
struct F_Math_FPstatus
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	WORD	r;
	WORD	mask;
};
void Math_acos(void*);
typedef struct F_Math_acos F_Math_acos;
struct F_Math_acos
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
};
void Math_acosh(void*);
typedef struct F_Math_acosh F_Math_acosh;
struct F_Math_acosh
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
};
void Math_asin(void*);
typedef struct F_Math_asin F_Math_asin;
struct F_Math_asin
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
};
void Math_asinh(void*);
typedef struct F_Math_asinh F_Math_asinh;
struct F_Math_asinh
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
};
void Math_atan(void*);
typedef struct F_Math_atan F_Math_atan;
struct F_Math_atan
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
};
void Math_atan2(void*);
typedef struct F_Math_atan2 F_Math_atan2;
struct F_Math_atan2
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	y;
	REAL	x;
};
void Math_atanh(void*);
typedef struct F_Math_atanh F_Math_atanh;
struct F_Math_atanh
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
};
void Math_bits32real(void*);
typedef struct F_Math_bits32real F_Math_bits32real;
struct F_Math_bits32real
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	WORD	b;
};
void Math_bits64real(void*);
typedef struct F_Math_bits64real F_Math_bits64real;
struct F_Math_bits64real
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	LONG	b;
};
void Math_cbrt(void*);
typedef struct F_Math_cbrt F_Math_cbrt;
struct F_Math_cbrt
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
};
void Math_ceil(void*);
typedef struct F_Math_ceil F_Math_ceil;
struct F_Math_ceil
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
};
void Math_copysign(void*);
typedef struct F_Math_copysign F_Math_copysign;
struct F_Math_copysign
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
	REAL	s;
};
void Math_cos(void*);
typedef struct F_Math_cos F_Math_cos;
struct F_Math_cos
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
};
void Math_cosh(void*);
typedef struct F_Math_cosh F_Math_cosh;
struct F_Math_cosh
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
};
void Math_dot(void*);
typedef struct F_Math_dot F_Math_dot;
struct F_Math_dot
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	Array*	x;
	Array*	y;
};
void Math_erf(void*);
typedef struct F_Math_erf F_Math_erf;
struct F_Math_erf
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
};
void Math_erfc(void*);
typedef struct F_Math_erfc F_Math_erfc;
struct F_Math_erfc
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
};
void Math_exp(void*);
typedef struct F_Math_exp F_Math_exp;
struct F_Math_exp
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
};
void Math_expm1(void*);
typedef struct F_Math_expm1 F_Math_expm1;
struct F_Math_expm1
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
};
void Math_export_int(void*);
typedef struct F_Math_export_int F_Math_export_int;
struct F_Math_export_int
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[12];
	Array*	b;
	Array*	x;
};
void Math_export_real(void*);
typedef struct F_Math_export_real F_Math_export_real;
struct F_Math_export_real
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[12];
	Array*	b;
	Array*	x;
};
void Math_export_real32(void*);
typedef struct F_Math_export_real32 F_Math_export_real32;
struct F_Math_export_real32
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[12];
	Array*	b;
	Array*	x;
};
void Math_fabs(void*);
typedef struct F_Math_fabs F_Math_fabs;
struct F_Math_fabs
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
};
void Math_fdim(void*);
typedef struct F_Math_fdim F_Math_fdim;
struct F_Math_fdim
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
	REAL	y;
};
void Math_finite(void*);
typedef struct F_Math_finite F_Math_finite;
struct F_Math_finite
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	REAL	x;
};
void Math_floor(void*);
typedef struct F_Math_floor F_Math_floor;
struct F_Math_floor
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
};
void Math_fmax(void*);
typedef struct F_Math_fmax F_Math_fmax;
struct F_Math_fmax
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
	REAL	y;
};
void Math_fmin(void*);
typedef struct F_Math_fmin F_Math_fmin;
struct F_Math_fmin
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
	REAL	y;
};
void Math_fmod(void*);
typedef struct F_Math_fmod F_Math_fmod;
struct F_Math_fmod
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
	REAL	y;
};
void Math_gemm(void*);
typedef struct F_Math_gemm F_Math_gemm;
struct F_Math_gemm
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[12];
	WORD	transa;
	WORD	transb;
	WORD	m;
	WORD	n;
	WORD	k;
	uchar	_pad52[4];
	REAL	alpha;
	Array*	a;
	WORD	lda;
	Array*	b;
	WORD	ldb;
	REAL	beta;
	Array*	c;
	WORD	ldc;
};
void Math_getFPcontrol(void*);
typedef struct F_Math_getFPcontrol F_Math_getFPcontrol;
struct F_Math_getFPcontrol
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
};
void Math_getFPstatus(void*);
typedef struct F_Math_getFPstatus F_Math_getFPstatus;
struct F_Math_getFPstatus
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
};
void Math_hypot(void*);
typedef struct F_Math_hypot F_Math_hypot;
struct F_Math_hypot
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
	REAL	y;
};
void Math_iamax(void*);
typedef struct F_Math_iamax F_Math_iamax;
struct F_Math_iamax
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Array*	x;
};
void Math_ilogb(void*);
typedef struct F_Math_ilogb F_Math_ilogb;
struct F_Math_ilogb
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	REAL	x;
};
void Math_import_int(void*);
typedef struct F_Math_import_int F_Math_import_int;
struct F_Math_import_int
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[12];
	Array*	b;
	Array*	x;
};
void Math_import_real(void*);
typedef struct F_Math_import_real F_Math_import_real;
struct F_Math_import_real
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[12];
	Array*	b;
	Array*	x;
};
void Math_import_real32(void*);
typedef struct F_Math_import_real32 F_Math_import_real32;
struct F_Math_import_real32
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[12];
	Array*	b;
	Array*	x;
};
void Math_isnan(void*);
typedef struct F_Math_isnan F_Math_isnan;
struct F_Math_isnan
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	REAL	x;
};
void Math_j0(void*);
typedef struct F_Math_j0 F_Math_j0;
struct F_Math_j0
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
};
void Math_j1(void*);
typedef struct F_Math_j1 F_Math_j1;
struct F_Math_j1
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
};
void Math_jn(void*);
typedef struct F_Math_jn F_Math_jn;
struct F_Math_jn
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	WORD	n;
	uchar	_pad36[4];
	REAL	x;
};
void Math_lgamma(void*);
typedef struct F_Math_lgamma F_Math_lgamma;
struct F_Math_lgamma
{
	WORD	regs[NREG-1];
	struct{ WORD t0; uchar	_pad4[4]; REAL t1; }*	ret;
	uchar	temps[12];
	REAL	x;
};
void Math_log(void*);
typedef struct F_Math_log F_Math_log;
struct F_Math_log
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
};
void Math_log10(void*);
typedef struct F_Math_log10 F_Math_log10;
struct F_Math_log10
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
};
void Math_log1p(void*);
typedef struct F_Math_log1p F_Math_log1p;
struct F_Math_log1p
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
};
void Math_modf(void*);
typedef struct F_Math_modf F_Math_modf;
struct F_Math_modf
{
	WORD	regs[NREG-1];
	struct{ WORD t0; uchar	_pad4[4]; REAL t1; }*	ret;
	uchar	temps[12];
	REAL	x;
};
void Math_nextafter(void*);
typedef struct F_Math_nextafter F_Math_nextafter;
struct F_Math_nextafter
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
	REAL	y;
};
void Math_norm1(void*);
typedef struct F_Math_norm1 F_Math_norm1;
struct F_Math_norm1
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	Array*	x;
};
void Math_norm2(void*);
typedef struct F_Math_norm2 F_Math_norm2;
struct F_Math_norm2
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	Array*	x;
};
void Math_pow(void*);
typedef struct F_Math_pow F_Math_pow;
struct F_Math_pow
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
	REAL	y;
};
void Math_pow10(void*);
typedef struct F_Math_pow10 F_Math_pow10;
struct F_Math_pow10
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	WORD	p;
};
void Math_realbits32(void*);
typedef struct F_Math_realbits32 F_Math_realbits32;
struct F_Math_realbits32
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	REAL	x;
};
void Math_realbits64(void*);
typedef struct F_Math_realbits64 F_Math_realbits64;
struct F_Math_realbits64
{
	WORD	regs[NREG-1];
	LONG*	ret;
	uchar	temps[12];
	REAL	x;
};
void Math_remainder(void*);
typedef struct F_Math_remainder F_Math_remainder;
struct F_Math_remainder
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
	REAL	p;
};
void Math_rint(void*);
typedef struct F_Math_rint F_Math_rint;
struct F_Math_rint
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
};
void Math_scalbn(void*);
typedef struct F_Math_scalbn F_Math_scalbn;
struct F_Math_scalbn
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
	WORD	n;
};
void Math_sin(void*);
typedef struct F_Math_sin F_Math_sin;
struct F_Math_sin
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
};
void Math_sinh(void*);
typedef struct F_Math_sinh F_Math_sinh;
struct F_Math_sinh
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
};
void Math_sort(void*);
typedef struct F_Math_sort F_Math_sort;
struct F_Math_sort
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[12];
	Array*	x;
	Array*	pi;
};
void Math_sqrt(void*);
typedef struct F_Math_sqrt F_Math_sqrt;
struct F_Math_sqrt
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
};
void Math_tan(void*);
typedef struct F_Math_tan F_Math_tan;
struct F_Math_tan
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
};
void Math_tanh(void*);
typedef struct F_Math_tanh F_Math_tanh;
struct F_Math_tanh
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
};
void Math_y0(void*);
typedef struct F_Math_y0 F_Math_y0;
struct F_Math_y0
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
};
void Math_y1(void*);
typedef struct F_Math_y1 F_Math_y1;
struct F_Math_y1
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
};
void Math_yn(void*);
typedef struct F_Math_yn F_Math_yn;
struct F_Math_yn
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	WORD	n;
	uchar	_pad36[4];
	REAL	x;
};
#define Math_PATH "$Math"
#define Math_Infinity Infinity
#define Math_NaN NaN
#define Math_MachEps 2.220446049250313e-16
#define Math_Pi 3.141592653589793
#define Math_Degree .017453292519943295
#define Math_INVAL 1
#define Math_ZDIV 2
#define Math_OVFL 4
#define Math_UNFL 8
#define Math_INEX 16
#define Math_RND_NR 0
#define Math_RND_NINF 256
#define Math_RND_PINF 512
#define Math_RND_Z 768
#define Math_RND_MASK 768
void IPint_add(void*);
typedef struct F_IPint_add F_IPint_add;
struct F_IPint_add
{
	WORD	regs[NREG-1];
	Keyring_IPint**	ret;
	uchar	temps[12];
	Keyring_IPint*	i1;
	Keyring_IPint*	i2;
};
void Keyring_auth(void*);
typedef struct F_Keyring_auth F_Keyring_auth;
struct F_Keyring_auth
{
	WORD	regs[NREG-1];
	struct{ String* t0; Array* t1; }*	ret;
	uchar	temps[12];
	Sys_FD*	fd;
	Keyring_Authinfo*	info;
	WORD	setid;
};
void IPint_b64toip(void*);
typedef struct F_IPint_b64toip F_IPint_b64toip;
struct F_IPint_b64toip
{
	WORD	regs[NREG-1];
	Keyring_IPint**	ret;
	uchar	temps[12];
	String*	str;
};
void IPint_bebytestoip(void*);
typedef struct F_IPint_bebytestoip F_IPint_bebytestoip;
struct F_IPint_bebytestoip
{
	WORD	regs[NREG-1];
	Keyring_IPint**	ret;
	uchar	temps[12];
	Array*	mag;
};
void IPint_bits(void*);
typedef struct F_IPint_bits F_IPint_bits;
struct F_IPint_bits
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Keyring_IPint*	i;
};
void IPint_bytestoip(void*);
typedef struct F_IPint_bytestoip F_IPint_bytestoip;
struct F_IPint_bytestoip
{
	WORD	regs[NREG-1];
	Keyring_IPint**	ret;
	uchar	temps[12];
	Array*	buf;
};
void Keyring_certtostr(void*);
typedef struct F_Keyring_certtostr F_Keyring_certtostr;
struct F_Keyring_certtostr
{
	WORD	regs[NREG-1];
	String**	ret;
	uchar	temps[12];
	Keyring_Certificate*	c;
};
void Keyring_cloneDigestState(void*);
typedef struct F_Keyring_cloneDigestState F_Keyring_cloneDigestState;
struct F_Keyring_cloneDigestState
{
	WORD	regs[NREG-1];
	Keyring_DigestState**	ret;
	uchar	temps[12];
	Keyring_DigestState*	state;
};
void IPint_cmp(void*);
typedef struct F_IPint_cmp F_IPint_cmp;
struct F_IPint_cmp
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Keyring_IPint*	i1;
	Keyring_IPint*	i2;
};
void Keyring_descbc(void*);
typedef struct F_Keyring_descbc F_Keyring_descbc;
struct F_Keyring_descbc
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[12];
	Keyring_DESstate*	state;
	Array*	buf;
	WORD	n;
	WORD	direction;
};
void Keyring_desecb(void*);
typedef struct F_Keyring_desecb F_Keyring_desecb;
struct F_Keyring_desecb
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[12];
	Keyring_DESstate*	state;
	Array*	buf;
	WORD	n;
	WORD	direction;
};
void Keyring_dessetup(void*);
typedef struct F_Keyring_dessetup F_Keyring_dessetup;
struct F_Keyring_dessetup
{
	WORD	regs[NREG-1];
	Keyring_DESstate**	ret;
	uchar	temps[12];
	Array*	key;
	Array*	ivec;
};
void Keyring_dhparams(void*);
typedef struct F_Keyring_dhparams F_Keyring_dhparams;
struct F_Keyring_dhparams
{
	WORD	regs[NREG-1];
	struct{ Keyring_IPint* t0; Keyring_IPint* t1; }*	ret;
	uchar	temps[12];
	WORD	nbits;
};
void IPint_div(void*);
typedef struct F_IPint_div F_IPint_div;
struct F_IPint_div
{
	WORD	regs[NREG-1];
	struct{ Keyring_IPint* t0; Keyring_IPint* t1; }*	ret;
	uchar	temps[12];
	Keyring_IPint*	i1;
	Keyring_IPint*	i2;
};
void IPint_eq(void*);
typedef struct F_IPint_eq F_IPint_eq;
struct F_IPint_eq
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Keyring_IPint*	i1;
	Keyring_IPint*	i2;
};
void IPint_expmod(void*);
typedef struct F_IPint_expmod F_IPint_expmod;
struct F_IPint_expmod
{
	WORD	regs[NREG-1];
	Keyring_IPint**	ret;
	uchar	temps[12];
	Keyring_IPint*	base;
	Keyring_IPint*	exp;
	Keyring_IPint*	mod;
};
void Keyring_genSK(void*);
typedef struct F_Keyring_genSK F_Keyring_genSK;
struct F_Keyring_genSK
{
	WORD	regs[NREG-1];
	Keyring_SK**	ret;
	uchar	temps[12];
	String*	algname;
	String*	owner;
	WORD	length;
};
void Keyring_genSKfromPK(void*);
typedef struct F_Keyring_genSKfromPK F_Keyring_genSKfromPK;
struct F_Keyring_genSKfromPK
{
	WORD	regs[NREG-1];
	Keyring_SK**	ret;
	uchar	temps[12];
	Keyring_PK*	pk;
	String*	owner;
};
void Keyring_getbytearray(void*);
typedef struct F_Keyring_getbytearray F_Keyring_getbytearray;
struct F_Keyring_getbytearray
{
	WORD	regs[NREG-1];
	struct{ Array* t0; String* t1; }*	ret;
	uchar	temps[12];
	Sys_FD*	fd;
};
void Keyring_getmsg(void*);
typedef struct F_Keyring_getmsg F_Keyring_getmsg;
struct F_Keyring_getmsg
{
	WORD	regs[NREG-1];
	Array**	ret;
	uchar	temps[12];
	Sys_FD*	fd;
};
void Keyring_getstring(void*);
typedef struct F_Keyring_getstring F_Keyring_getstring;
struct F_Keyring_getstring
{
	WORD	regs[NREG-1];
	struct{ String* t0; String* t1; }*	ret;
	uchar	temps[12];
	Sys_FD*	fd;
};
void Keyring_hmac_md5(void*);
typedef struct F_Keyring_hmac_md5 F_Keyring_hmac_md5;
struct F_Keyring_hmac_md5
{
	WORD	regs[NREG-1];
	Keyring_DigestState**	ret;
	uchar	temps[12];
	Array*	data;
	WORD	n;
	Array*	key;
	Array*	digest;
	Keyring_DigestState*	state;
};
void Keyring_hmac_sha1(void*);
typedef struct F_Keyring_hmac_sha1 F_Keyring_hmac_sha1;
struct F_Keyring_hmac_sha1
{
	WORD	regs[NREG-1];
	Keyring_DigestState**	ret;
	uchar	temps[12];
	Array*	data;
	WORD	n;
	Array*	key;
	Array*	digest;
	Keyring_DigestState*	state;
};
void Keyring_ideacbc(void*);
typedef struct F_Keyring_ideacbc F_Keyring_ideacbc;
struct F_Keyring_ideacbc
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[12];
	Keyring_IDEAstate*	state;
	Array*	buf;
	WORD	n;
	WORD	direction;
};
void Keyring_ideaecb(void*);
typedef struct F_Keyring_ideaecb F_Keyring_ideaecb;
struct F_Keyring_ideaecb
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[12];
	Keyring_IDEAstate*	state;
	Array*	buf;
	WORD	n;
	WORD	direction;
};
void Keyring_ideasetup(void*);
typedef struct F_Keyring_ideasetup F_Keyring_ideasetup;
struct F_Keyring_ideasetup
{
	WORD	regs[NREG-1];
	Keyring_IDEAstate**	ret;
	uchar	temps[12];
	Array*	key;
	Array*	ivec;
};
void IPint_inttoip(void*);
typedef struct F_IPint_inttoip F_IPint_inttoip;
struct F_IPint_inttoip
{
	WORD	regs[NREG-1];
	Keyring_IPint**	ret;
	uchar	temps[12];
	WORD	i;
};
void IPint_iptob64(void*);
typedef struct F_IPint_iptob64 F_IPint_iptob64;
struct F_IPint_iptob64
{
	WORD	regs[NREG-1];
	String**	ret;
	uchar	temps[12];
	Keyring_IPint*	i;
};
void IPint_iptobebytes(void*);
typedef struct F_IPint_iptobebytes F_IPint_iptobebytes;
struct F_IPint_iptobebytes
{
	WORD	regs[NREG-1];
	Array**	ret;
	uchar	temps[12];
	Keyring_IPint*	i;
};
void IPint_iptobytes(void*);
typedef struct F_IPint_iptobytes F_IPint_iptobytes;
struct F_IPint_iptobytes
{
	WORD	regs[NREG-1];
	Array**	ret;
	uchar	temps[12];
	Keyring_IPint*	i;
};
void IPint_iptoint(void*);
typedef struct F_IPint_iptoint F_IPint_iptoint;
struct F_IPint_iptoint
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Keyring_IPint*	i;
};
void IPint_iptostr(void*);
typedef struct F_IPint_iptostr F_IPint_iptostr;
struct F_IPint_iptostr
{
	WORD	regs[NREG-1];
	String**	ret;
	uchar	temps[12];
	Keyring_IPint*	i;
	WORD	base;
};
void Keyring_md4(void*);
typedef struct F_Keyring_md4 F_Keyring_md4;
struct F_Keyring_md4
{
	WORD	regs[NREG-1];
	Keyring_DigestState**	ret;
	uchar	temps[12];
	Array*	buf;
	WORD	n;
	Array*	digest;
	Keyring_DigestState*	state;
};
void Keyring_md5(void*);
typedef struct F_Keyring_md5 F_Keyring_md5;
struct F_Keyring_md5
{
	WORD	regs[NREG-1];
	Keyring_DigestState**	ret;
	uchar	temps[12];
	Array*	buf;
	WORD	n;
	Array*	digest;
	Keyring_DigestState*	state;
};
void IPint_mul(void*);
typedef struct F_IPint_mul F_IPint_mul;
struct F_IPint_mul
{
	WORD	regs[NREG-1];
	Keyring_IPint**	ret;
	uchar	temps[12];
	Keyring_IPint*	i1;
	Keyring_IPint*	i2;
};
void IPint_neg(void*);
typedef struct F_IPint_neg F_IPint_neg;
struct F_IPint_neg
{
	WORD	regs[NREG-1];
	Keyring_IPint**	ret;
	uchar	temps[12];
	Keyring_IPint*	i;
};
void Keyring_pktostr(void*);
typedef struct F_Keyring_pktostr F_Keyring_pktostr;
struct F_Keyring_pktostr
{
	WORD	regs[NREG-1];
	String**	ret;
	uchar	temps[12];
	Keyring_PK*	pk;
};
void Keyring_putbytearray(void*);
typedef struct F_Keyring_putbytearray F_Keyring_putbytearray;
struct F_Keyring_putbytearray
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Sys_FD*	fd;
	Array*	a;
	WORD	n;
};
void Keyring_puterror(void*);
typedef struct F_Keyring_puterror F_Keyring_puterror;
struct F_Keyring_puterror
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Sys_FD*	fd;
	String*	s;
};
void Keyring_putstring(void*);
typedef struct F_Keyring_putstring F_Keyring_putstring;
struct F_Keyring_putstring
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Sys_FD*	fd;
	String*	s;
};
void IPint_random(void*);
typedef struct F_IPint_random F_IPint_random;
struct F_IPint_random
{
	WORD	regs[NREG-1];
	Keyring_IPint**	ret;
	uchar	temps[12];
	WORD	minbits;
	WORD	maxbits;
};
void Keyring_readauthinfo(void*);
typedef struct F_Keyring_readauthinfo F_Keyring_readauthinfo;
struct F_Keyring_readauthinfo
{
	WORD	regs[NREG-1];
	Keyring_Authinfo**	ret;
	uchar	temps[12];
	String*	filename;
};
void Keyring_sendmsg(void*);
typedef struct F_Keyring_sendmsg F_Keyring_sendmsg;
struct F_Keyring_sendmsg
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Sys_FD*	fd;
	Array*	buf;
	WORD	n;
};
void Keyring_sha(void*);
typedef struct F_Keyring_sha F_Keyring_sha;
struct F_Keyring_sha
{
	WORD	regs[NREG-1];
	Keyring_DigestState**	ret;
	uchar	temps[12];
	Array*	buf;
	WORD	n;
	Array*	digest;
	Keyring_DigestState*	state;
};
void Keyring_sha1(void*);
typedef struct F_Keyring_sha1 F_Keyring_sha1;
struct F_Keyring_sha1
{
	WORD	regs[NREG-1];
	Keyring_DigestState**	ret;
	uchar	temps[12];
	Array*	buf;
	WORD	n;
	Array*	digest;
	Keyring_DigestState*	state;
};
void Keyring_sign(void*);
typedef struct F_Keyring_sign F_Keyring_sign;
struct F_Keyring_sign
{
	WORD	regs[NREG-1];
	Keyring_Certificate**	ret;
	uchar	temps[12];
	Keyring_SK*	sk;
	WORD	exp;
	Keyring_DigestState*	state;
	String*	ha;
};
void Keyring_sktopk(void*);
typedef struct F_Keyring_sktopk F_Keyring_sktopk;
struct F_Keyring_sktopk
{
	WORD	regs[NREG-1];
	Keyring_PK**	ret;
	uchar	temps[12];
	Keyring_SK*	sk;
};
void Keyring_sktostr(void*);
typedef struct F_Keyring_sktostr F_Keyring_sktostr;
struct F_Keyring_sktostr
{
	WORD	regs[NREG-1];
	String**	ret;
	uchar	temps[12];
	Keyring_SK*	sk;
};
void Keyring_strtocert(void*);
typedef struct F_Keyring_strtocert F_Keyring_strtocert;
struct F_Keyring_strtocert
{
	WORD	regs[NREG-1];
	Keyring_Certificate**	ret;
	uchar	temps[12];
	String*	s;
};
void IPint_strtoip(void*);
typedef struct F_IPint_strtoip F_IPint_strtoip;
struct F_IPint_strtoip
{
	WORD	regs[NREG-1];
	Keyring_IPint**	ret;
	uchar	temps[12];
	String*	str;
	WORD	base;
};
void Keyring_strtopk(void*);
typedef struct F_Keyring_strtopk F_Keyring_strtopk;
struct F_Keyring_strtopk
{
	WORD	regs[NREG-1];
	Keyring_PK**	ret;
	uchar	temps[12];
	String*	s;
};
void Keyring_strtosk(void*);
typedef struct F_Keyring_strtosk F_Keyring_strtosk;
struct F_Keyring_strtosk
{
	WORD	regs[NREG-1];
	Keyring_SK**	ret;
	uchar	temps[12];
	String*	s;
};
void IPint_sub(void*);
typedef struct F_IPint_sub F_IPint_sub;
struct F_IPint_sub
{
	WORD	regs[NREG-1];
	Keyring_IPint**	ret;
	uchar	temps[12];
	Keyring_IPint*	i1;
	Keyring_IPint*	i2;
};
void Keyring_verify(void*);
typedef struct F_Keyring_verify F_Keyring_verify;
struct F_Keyring_verify
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Keyring_PK*	pk;
	Keyring_Certificate*	cert;
	Keyring_DigestState*	state;
};
void Keyring_writeauthinfo(void*);
typedef struct F_Keyring_writeauthinfo F_Keyring_writeauthinfo;
struct F_Keyring_writeauthinfo
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	String*	filename;
	Keyring_Authinfo*	info;
};
#define Keyring_PATH "$Keyring"
#define Keyring_Encrypt 0
#define Keyring_Decrypt 1
#define Keyring_DEScbc 0
#define Keyring_DESecb 1
#define Keyring_SHA 2
#define Keyring_MD5 3
#define Keyring_MD4 4
#define Keyring_IDEAcbc 5
#define Keyring_IDEAecb 6
#define Keyring_SHAdlen 20
#define Keyring_SHA1dlen 20
#define Keyring_MD5dlen 16
#define Keyring_MD4dlen 16
void Loader_compile(void*);
typedef struct F_Loader_compile F_Loader_compile;
struct F_Loader_compile
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Modlink*	mp;
	WORD	flag;
};
void Loader_dnew(void*);
typedef struct F_Loader_dnew F_Loader_dnew;
struct F_Loader_dnew
{
	WORD	regs[NREG-1];
	Loader_Niladt**	ret;
	uchar	temps[12];
	WORD	size;
	Array*	map;
};
void Loader_ext(void*);
typedef struct F_Loader_ext F_Loader_ext;
struct F_Loader_ext
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Modlink*	mp;
	WORD	idx;
	WORD	pc;
	WORD	tdesc;
};
void Loader_ifetch(void*);
typedef struct F_Loader_ifetch F_Loader_ifetch;
struct F_Loader_ifetch
{
	WORD	regs[NREG-1];
	Array**	ret;
	uchar	temps[12];
	Modlink*	mp;
};
void Loader_link(void*);
typedef struct F_Loader_link F_Loader_link;
struct F_Loader_link
{
	WORD	regs[NREG-1];
	Array**	ret;
	uchar	temps[12];
	Modlink*	mp;
};
void Loader_newmod(void*);
typedef struct F_Loader_newmod F_Loader_newmod;
struct F_Loader_newmod
{
	WORD	regs[NREG-1];
	Modlink**	ret;
	uchar	temps[12];
	String*	name;
	WORD	ss;
	WORD	nlink;
	Array*	inst;
	Loader_Niladt*	data;
};
void Loader_tdesc(void*);
typedef struct F_Loader_tdesc F_Loader_tdesc;
struct F_Loader_tdesc
{
	WORD	regs[NREG-1];
	Array**	ret;
	uchar	temps[12];
	Modlink*	mp;
};
void Loader_tnew(void*);
typedef struct F_Loader_tnew F_Loader_tnew;
struct F_Loader_tnew
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Modlink*	mp;
	WORD	size;
	Array*	map;
};
#define Loader_PATH "$Loader"
#pragma hjdicks off
