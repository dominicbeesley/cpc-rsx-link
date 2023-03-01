# cpc-rsx-link
A linker and BASIC loader for relocatable CPC RSX modules

The linker perl script takes a set of asz80/aslink .rel object files and links them to produce a file linked to load and run at adress 0

The script also produces a BASIC program (.asc file) to load the binary at HIMEM and relocate the program to run from HIMEM.

