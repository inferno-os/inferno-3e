extern	long	kclose(int);
extern	int	kdial(char*, char*, char*, int*);
extern	void	kerrstr(char*);
extern	void	kgerrstr(char*);
extern	long	kopen(char*, int);
extern	long	kread(int, void*, long);
extern	long	kseek(int, vlong, int);
extern	long	kwrite(int, void*, long);
extern	void	kwerrstr(char *, ...);

extern	char*	strdup(char*);
extern	char*	strrchr(char*, int);
extern	char*	strstr(char*, char*);

