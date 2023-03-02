
	

	.area CODE(CON,REL)

REDEFME == 23
REDEFME2 == 1

	.globl SOMETHING
	.globl START
SOMMAT::
	ld	HL,SOMETHING

HERE:
	jp	HERE
	jp	THERE
	jp	.+3

	ld	A,<HERE
	ld	B,>HERE

	.area DATA(CON,REL)
SOMETHING2::
	.dw	SOMETHING
	.db	>HERE
	.db	<THERE
	.db	<START
	.db	>START


	.area CODE(CON,REL)
THERE:
	ld	A,(SOMETHING)
