#!/usr/bin/perl

# MIT License
# 
# Copyright (c) 2023 dominicbeesley
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.



# Reads in ASZ80/ASLINK .rel files and creates an RSX
# this assumes that areas are presented in the order in which they 
# are to be linked and that the entry point/initialisation routine
# is at the start of the first area.

use strict;
use Data::Dumper;

my $fn_out = shift or UsageDie("missing output filename");
my $fn_asc_out = shift or UsageDie("missing output BASIC (.asc) filename");
my @fnlst_in = @ARGV;

my @files = ();

my $verbose = 999;

foreach my $fn_in (@fnlst_in) {
	push @files, read_rel($fn_in);
}

my @area_global = ();	# keep track of order areas declared in

# calculate global area sizes and orders
foreach my $f (@files) {
	foreach my $a (@{$f->{areas}}) {
		my $a_name = $a->{name};
		my ($ga) = grep { $_->{name} eq $a_name } @area_global;
		if ($ga) {
			$a->{global_offset} = $ga->{size};
			$ga->{size} += $a->{size};
		} else {
			$a->{global_offset} = 0;
			$ga = {
				name => $a->{name},
				idx => scalar @area_global,
				size => $a->{size}
			};
			push @area_global, $ga;
		}
	}
}

#calculate global area bases
my $total_size = 0;
foreach my $ga (@area_global) {
	$ga->{base} = $total_size;
	my $s = $ga->{size};
	$total_size += $s;
	my @mem = (map { 0xFF } 1..$s);
	@{$ga->{mem}} = @mem;
}

#make a global symbol table
my %symbol_global = ();
foreach my $f (@files) {
	foreach my $s (@{$f->{symbols}}) {
		if ($s->{refdef} eq "def") {
			my $s_name = $s->{name};

			my $gs = $symbol_global{$s_name};

			if ($gs) {
				(!$gs->{area} and !$s->{area}) or die "Symbol $s_name redefined";
				$gs->{value} == $s->{value} or die "Global symbol $s_name redifined with different values $gs->{value} != $s->{value}";
			} else  {
				my $s_area = $s->{area};
				if ($s_area) {
					my ($a) = grep { $_->{name} eq $s_area } @{$f->{areas}};
					$a or die "Area $s_area does not exist in file ${$f->{name}}";
					my ($ga) = grep { $_->{name} eq $s_area } @area_global;
					$ga or die "Area $s_area does not exist in global table";

					$symbol_global{$s_name} = {
						name => $s_name,
						value => $a->{global_offset} + $ga->{base} + $s->{value},
						type => "reloc"
					};

				} else {
					$symbol_global{$s_name} = {
						name => $s_name,
						value => $s->{value},
						type => "abs"
					};
				}
			}
		}
	}
}


my @basrelocs = ();

#build store for each area
foreach my $f (@files) {
	foreach my $a (@{$f->{areas}}) {
		my ($ga) = grep { $_->{name} eq $a->{name} } @area_global;

		my @mem = (0xFF) x $a->{size};

		my $area_base = $a->{global_offset} + $ga->{base};

		foreach my $dd (@{$a->{datas}}) {
			my @d = @{$dd->{data}};

			my $d_base = $area_base + $dd->{data_offs};

			foreach my $rr (@{$dd->{relocs}}) {
				
				if ($rr->{is_sym}) {
					print "REL:SYM:$rr->{ref}\n";
					my $gs = $symbol_global{$rr->{ref}};
					$gs or die "Unexpected missing symbol $rr->{ref}";
					do_reloc(\@d, $d_base, $rr->{data_offset}, $rr->{size}, $rr->{fmt}, $gs->{value});
				} else {
					print "REL:AREA:$rr->{ref}\n";
					my ($la) = grep {$_->{name} eq $rr->{ref}} @{$f->{areas}};
					$la or die "Can't find area $rr->{ref} in file $f->{name}";
					my ($ga) = grep {$_->{name} eq $rr->{ref}} @area_global;
					$ga or die "Can't find global area $rr->{ref}";
					do_reloc(\@d, $d_base, $rr->{data_offset}, $rr->{size}, $rr->{fmt}, $ga->{base} + $la->{global_offset});
				}

			}

			splice(@mem, $dd->{data_offs}, scalar @d, @d);
		}

		splice(@{$ga->{mem}}, $a->{global_offset}, $a->{size}, @mem);
	}
}



print "SIZE:$total_size\n";
if ($verbose > 10) {
	print "GA:" . Dumper(@area_global) . "\n";
	print "FIL:" . Dumper(@files) . "\n";
	print "SYM:" . Dumper(%symbol_global) . "\n";
}


#output binary

open (my $fh_out, ">:raw", $fn_out) or die "Cannot open $fn_out for output : $!";
open (my $fh_asc_out, ">:raw", $fn_asc_out) or die "Cannot open $fn_asc_out for output : $!";

my $total_size = 0;
foreach my $ga (@area_global) {
	print $fh_out pack("C*", @{$ga->{mem}}[0 .. $ga->{size}-1]);
	$total_size += $ga->{size};
}

print "RELOCS:";
print Dumper(@basrelocs) . "\n";

# Construct basic loader

print $fh_asc_out "10REM > rsx loader\r\n";
printf $fh_asc_out "20H=1+HIMEM-&%04X:MEMORY H-1\r\n", $total_size;
printf $fh_asc_out "30LOAD\"rsx.bin\",H\r\n";
printf $fh_asc_out "40WHILE 1:READ A\r\n";
printf $fh_asc_out "50IF A=-1 THEN CALL H:END\r\n";
printf $fh_asc_out "60IF A=>&8000 THEN GOSUB 100 ELSE GOSUB 200\r\n";
printf $fh_asc_out "70WEND\r\n";
printf $fh_asc_out "80:\r\n";
printf $fh_asc_out "100A=A-&8000:READ B:IF B>=256THEN POKE H+A,H+PEEK(H+A) ELSE POKE H+A,((H+B)/256)+PEEK(H+A)\r\n";
printf $fh_asc_out "110RETURN\r\n";
printf $fh_asc_out "120:\r\n";
printf $fh_asc_out "200B=H+PEEK(H+A)+256*PEEK(H+A+1):POKE H+A,B:POKE H+A+1,B/256\r\n";
printf $fh_asc_out "210RETURN\r\n";
printf $fh_asc_out "220:\r\n";

my $dl="";
my $l = 1000;
foreach my $r (@basrelocs) {

	if ($dl) {
		$dl .= ",";
	}

	if ($r->{type} eq "normal") {
		if ($r->{size}) {
			$dl .= sprintf("&%04X", $r->{addr});
		} else {
			$dl .= sprintf("&%04X", $r->{addr} | 0x8000);
			$dl .= sprintf(",&%02X", 0x100);
		}
	} elsif ($r->{type} eq "msb") {
		$dl .= sprintf("&%04X", $r->{addr} | 0x8000);
		$dl .= sprintf(",&%02X", $r->{lsb});
	}

	if (length($dl) > 200)
	{
		printf $fh_asc_out "%d DATA $dl\r\n", $l++;
		$dl = "";
	}
}
if ($dl) {
	$dl .= ",";
}
$dl .= "-1";
printf $fh_asc_out "%d DATA $dl\r\n", $l++;


close $fh_out;
close $fh_asc_out;

sub do_reloc(@$$$$$) {
	my ($mem, $area_base, $offs, $sz, $fmt, $val) = @_;

	print "MEM:@{$mem}\n";

	my @b = @{$mem}[$offs .. $offs + 1];

	my ($v) = unpack("S", pack("C*", @b));

	if ($fmt eq "normal") {
		@b = unpack("C*", pack("S", $v + $val));
		splice(@{$mem}, $offs, 2, @b[0 .. $sz]);
		push @basrelocs, {
			type => "normal",
			addr => $area_base + $offs,
			size => $sz
		};
	} elsif ($fmt eq "msb") {
		print "MSB\n";
		@b = unpack("C*", pack("S", $v + $val));
		splice(@{$mem}, $offs, 2, @b[1]);
		push @basrelocs, {
			type => "msb",
			addr => $area_base + $offs,
			lsb => @b[0]
		};
	} else {
		die "unknown reloc format $fmt"
	}
	



}

sub read_rel($) {
	my ($fn_in) = @_;

	my @areas = ();

	open(my $fh_in, "<", $fn_in) or die "Cannot open $fn_in : $!";

	(my $fmt = <$fh_in>) or die "Missing module format line";
	$fmt =~ s/[\n\r]+$//;
	$fmt eq "XL2" or die "Unsupported module format [$fmt]";
	
	my $cur_area;
	my $area_ctr = 0;
	my $cur_t_line;

	my @symbols = ();

	while (my $l = <$fh_in>) {
		$l =~ s/[\r\n]+$//;
	
		if ($l =~ /^A\s+(\w+)\s+size\s+([0-9A-F]+)\s+flags\s+([0-9A-F]+)(\s+bank\s+([0-9A-F]+))?\s*$/i) {
			#area definition
			my ($area_name, $area_size, $area_flags, $area_bank) = ($1, hex($2), hex($3), hex($4));

			$cur_area = {
				name => $area_name,
				size => $area_size,
				flags => $area_flags,		
				local_order => $area_ctr++,
				datas => \()	
			};

			push @areas, $cur_area;
		} elsif ($l =~ /^S\s+([\.\w]+)\s+(Ref|Def)([0-9A-F]+)\s*$/i) {
			#symbol reference
			my ($sym_name, $sym_refdef, $sym_value) = ($1, $2, hex($3));

			push @symbols, {
				area => ($cur_area)?$cur_area->{name}:"",
				name => $sym_name,
				refdef => lc($sym_refdef),
				value => $sym_value
			};
		} elsif ($l =~ /^T((\s+[0-9A-F]+)+)\s*$/i) {
			#data line
			my $x = $1;
			$x =~ s/^\s*//;
			my @a = map { hex($_) } (split(/\s+/, $x));
			
			scalar @a >= 2 or die "Unexpectedly short T line: $l";

			my @ao = splice(@a, 0, 2);	

			$cur_t_line = {
				offset => @ao[0] + 256 * @ao[1],
				data => \@a
			}
		} elsif ($l =~ /^R((\s+[0-9A-F]+)+)\s*$/i) {
			#reloc line
			my $x = $1;
			$x =~ s/^\s*//;
			my @a = map { hex($_) } (split(/\s+/, $x));
			
			scalar @a >= 4 or die "Unexpectedly short R line: $l";

			@a[0] == 0 and @a[1] == 0 or die "Bad R line: $l";

			my $area_idx = @a[2] + @a[3] * 256;

			$area_idx <= $#areas or die "Bad area index $area_idx: $l > $#areas";

			$cur_area = @areas[$area_idx];

			defined($cur_t_line) or die "R line without T line";

			splice(@a, 0, 4);

			my @relocs = ();

			while (my @rr = splice(@a, 0, 4)) {
				my ($n1, $n2, $xx) = (@rr[0], @rr[1], @rr[2] + 256 * @rr[3]);

				my $reloc_size = $n1 & 0x3;
				my $reloc_type;
				if (($n1 & 0x0C) == 0) {
					$reloc_type = "normal";
				} elsif (($n1 & 0x0C) == 0x4) {
					$reloc_type = "signed";
				} elsif (($n1 & 0x0C) == 0x8) {
					$reloc_type = "unsigned";
				} elsif (($n1 & 0x0C) == 0xC) {
					$reloc_type = "msb";
				} else {
					die "Unrecognised reloc type";
				}

				my $page_type;
				if (($n1 & 0x30) == 0) {
					$page_type = "normal";
				} elsif (($n1 & 0x30) == 0x10) {
					$page_type = "page0";
				} elsif (($n1 & 0x30) == 0x20) {
					$page_type = "pageN";
				} elsif (($n1 & 0x30) == 0x30) {
					$page_type = "pageX";
				} else {
					die "Unrecognised reloc page type";
				}

				$page_type eq "normal" or die "Don't know how to handle reloc page type : $page_type";

				my $data_offset = $n2 & 0xF;

				($n2 & 0xF0) == 0 or die "Don't know how to handle merge mode > 0 in reloc";

				push @relocs, {
					size => $reloc_size,
					fmt => $reloc_type,
					page => $page_type,
					data_offset => $data_offset - 2,
					is_pc_rel => ($n1 & 0x40)?1:0,
					is_sym => ($n1 & 0x80)?1:0,
					xx => $xx,
					ref => ($n1 & 0x80)?@symbols[$xx]->{name}:@areas[$xx]->{name}
				};
			}

			my $reloc = {
				area => $cur_area->{name},
				data_offs => $cur_t_line->{offset},
				data => $cur_t_line->{data},
				relocs => \@relocs
			};

			push @{$cur_area->{datas}}, $reloc;

			$cur_t_line=undef;
		}
	}

	defined($cur_t_line) and die "T line without R line";

	close $fh_in;

	return {
		name => $fn_in,
		areas => \@areas,
		symbols => \@symbols
	};
}

sub Usage($) {
	my ($fh) = @_;

	print $fh "USAGE: rsxlink.pl <output.bin> <output.asc> [<input.rel>...]
Links the given .rel files to construct a binary file that is linked to load
at 0x0000 and produces a loader program that relocates it to load above HIMEM
";
}

sub UsageDie($) {
	
	my ($msg) = @_;

	Usage(\*STDERR);

	print STDERR "\n\n";
	die $msg;
}