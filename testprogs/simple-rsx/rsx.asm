
	

	.area CODE(CON,REL)


REDEFME == 23
REDEFME2 == 01

	.globl SOMMAT
START::
	ld	HL,SOMETHING
	ld	HL,SOMETHINGELESE
	
	ld	HL,SOMMAT

	ld	A,(HL)
HERE::	jp	START

	.area DATA(CON,REL)
SOMETHING::
	.asciz	"something"
SOMETHINGELESE::