typedef struct Global	Global;
typedef struct Fid	Fid;
typedef struct Blocked	Blocked;

enum
{
	NFID =	20,
};

struct Fid
{
	int		fid;
	int		open;
	BPChan	*node;
};

struct Blocked
{
	uchar		type;
	short		fid;
	ushort		tag;
	Qid		qid;
	long		offset;
	long		count;
};

struct Global					// because we're in ROM
{
	ulong		nextqid;
	int		nfids;
	int		msgpos;
	int		inpin;
	int		inpout;
	int		bps;
	int		bootsize;

	int		cmd;
	ulong		val;

	BPChan		*head;
	BPChan		*tail;

	Fcall		fc;
	BPChan		rootdir;
	BPChan		conschan;
	BPChan		ctlchan;
	BPChan		memchan;
	BPChan		bootchan;

	Fid		fidpool[NFID];
	Blocked		blocked[32];
	uchar		buf[8192+16+512]; // 512 is extra safety padding
	char		inpbuf[1024];
	char		msgbuf[4096];	// note: this *must* be last
};

#define	G	((Global*)0x20)

 // I/O
void	putc(int);
// void	puts(char *str);
// void	putn(ulong val, int radix);
// void	puthex(ulong val);
// void	putdec(ulong val);

 // debugging routines
void	dump(ulong *addr, int n);

 // protocol stuff
int	send(void *buf, int nbytes);
int	recv(void *buf, int nbytes);

// misc
int	segflush(void *addr, ulong len);

int	fcall(uchar*, Fcall*);
int	unblock(uchar*);

int	rootdirread(BPChan*, uchar *buf, long n, long offset);

void	rerror(uchar *buf, Fcall*, char *err, int elen);

ulong	glong(uchar *);
void	plong(uchar *, ulong);
void	pvlong(uchar *, ulong);

void	firstattach(int);
void	lastclunk(void);

