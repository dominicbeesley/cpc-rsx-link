AS=asz80
ASFLAGS=-olsvb
BUILD=./build/
TARGETS=RSX.BIN RSX-CMP.bin
OBJS=rsx.rel rsx2.rel
OBJS2=$(addprefix $(BUILD),$(OBJS))
SCRIPTS=../../scripts
RSXLINK=perl $(SCRIPTS)/rsxlink.pl
DSKFILES=$(addprefix $(BUILD), RSX.bin RSX.asc)


DEPS=

X:=$(shell mkdir -p $(BUILD))

#asz80 is an ashat and creates a file when there's an error and pisses around
#with the filename so you can't bloody rename it easily
.DELETE_ON_ERROR:
.PRECIOUS: $(BUILD)%.rel

all:: $(addprefix $(BUILD),$(TARGETS))

dsk:: simple.dsk

$(BUILD)%.rel: %.asm $(DEPS)
	$(AS) $(ASFLAGS) $(basename $@) $<

$(BUILD)RSX.bin: $(OBJS2)
	$(RSXLINK) $@ $(basename $@).asc $^

$(BUILD)%.ihx: $(OBJS2)
	aslink -m1 -j -u -i $@ $^

$(BUILD)RSX-CMP.bin: $(BUILD)%.ihx
	hex2bin 0x0 $< $@

simple.dsk: $(DSKFILES)
	iDSK $@ -n
	iDSK $@ -i $(BUILD)RSX.asc -t 0 
	iDSK $@ -i $(BUILD)RSX.bin -e 0xC000 -c 0xC000 -t 1

clean:
	-rm $(BUILD)*.s19
	-rm $(BUILD)*.ihx
	-rm $(BUILD)*.lst
	-rm $(BUILD)*.rel
	-rm $(BUILD)*.sym
	-rm $(BUILD)*.noi
	-rm $(BUILD)*.bin
	-rm $(BUILD)*.map
	-rm $(BUILD)*.hlr
	-rm $(BUILD)*.inf
	-rm $(BUILD)*.rst
	-rm $(BUILD)*.rsx

.PHONY: all clean
	

