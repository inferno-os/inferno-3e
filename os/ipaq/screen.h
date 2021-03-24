#define CURSWID	16
#define CURSHGT	16

typedef struct Cursor {
	Point	offset;
	uchar	clr[CURSWID/BI2BY*CURSHGT];
	uchar	set[CURSWID/BI2BY*CURSHGT];
} Cursor;

struct Vmode {
	int	wid;	/* 0 -> default or any match for all fields */
	int	hgt;
	uchar	d;
	uchar	hz;
};

typedef struct Vdisplay {
	uchar*	fb;		/* frame buffer */
	ulong	colormap[256][3];
	int	bwid;
	long	brightness;
	long	contrast;
	Lock;
	Vmode; 
} Vdisplay;

typedef struct {
	uchar	pbs;
	uchar	dual;
	uchar	mono;
	uchar	active;
	uchar	hsync_wid;
	uchar	sol_wait;
	uchar	eol_wait;
	uchar	vsync_hgt;
	uchar	sof_wait;
	uchar	eof_wait;
	uchar	lines_per_int;
	uchar	palette_delay;
	uchar	acbias_lines;
	uchar	obits;
	uchar	vsynclow;
	uchar	hsynclow;
} LCDparam;

typedef struct {
	Vmode;
	LCDparam;
} LCDmode;

int	archlcdmode(LCDmode*);

Vdisplay	*lcd_init(LCDmode*);
void	lcd_setcolor(ulong, ulong, ulong, ulong);
void	lcd_flush(void);

#define MAX_VCONTRAST		0xffff
#define MAX_VBRIGHTNESS		0xffff

int	getcontrast(void);
int	getbrightness(void);
void	setcontrast(int);
void	setbrightness(int);
