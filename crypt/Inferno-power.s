TEXT	umult(SB), $-4

	MOVW	4(FP), R4
	MULHWU	R4, R3, R5
	MOVW	8(FP), R6
	MULLW	R4, R3
	MOVW	R5, (R6)
	RETURN
