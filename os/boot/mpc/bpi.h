typedef struct BPChan BPChan;
struct BPChan
{
	Dir d;
	int	(*open)(BPChan*, int mode);	/* OREAD, OWRITE, etc */
	void	(*clunk)(BPChan*);	
	int	(*read)(BPChan*, uchar *buf, long count, long offset);
	int	(*write)(BPChan*, uchar *buf, long count, long offset);
	void *aux;

	char *err;		/* points to error string if an error occurs */
	BPChan *link;
};

enum {
	BPCHAN_BLOCKED = -2
};
