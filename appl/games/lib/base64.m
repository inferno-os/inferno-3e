Base64: module {
	PATH : con "/dis/games/lib/base64.dis";
	encode : fn(b : array of byte) : string;
	decode : fn(s : string) : array of byte;
};
