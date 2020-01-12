#!/usr/bin/perl
use strict;
use warnings;
use Fcntl ('SEEK_SET', 'SEEK_CUR', 'SEEK_END');
use Encode qw/encode decode/;

#Script created by Roger Pepitone.

#Some usage notes from HigurashiArchive: 
#* The script needs to be run in binary mode, so it won't work on a Windows machine out of the box. There is a way to get it to work on Windows but it's easier and faster to throw it on a Linux machine instead because Linux opens files in binmode by default.
#* I have not really tested the functionality of the --update or --list options. In theory you could use --update to create mods, but the game is impossible to run on modern computers anyway.
#* --extract requires either two or three args (input .dat file, output destination location, and optionally a pattern). The two-arg version doesn't seem to work as intended, because it will fail to deobfuscate certain files, in particular .x models of some of the characters. Using the regex pattern [.]* for the pattern seems to make the missing items decrypt as intended, but I have no way of knowing this 100% for sure. There may actually be something missing. I checked the size of the DAT file with the output directory and they were within a few hundred kb of each other, so I felt fairly confident about its output.

sub decrypt_file_table_block {
    my ($index, $str) = @_;
    
    $index = $index & 0x1ff;

    #my ($in_index, $str) = @_;
    #
    #$index = $index & 0x1ff;
    #my $index = $in_index & 0x1ff;
    my $ctr = (100 + $index*77) & 0xff;
    my $key = (100*($index+1) + (0xff&($index*($index-1)/2))*77) & 0xff;
    #my $ctr = 100; my $key = 100;

    my $rv = '';
    for (my $i = 0; $i < length ($str); ++ $i) {
	#if (($in_index + $i) % 268 == 0) { print "index = ", ($in_index + $i), ", ctr = $ctr, key = $key\n"; }
	$rv .= chr (ord (substr ($str, $i, 1)) ^ $key);
	$key = ($key + $ctr) & 0xff;
	$ctr = ($ctr + 77) & 0xff;
    }
    #print "\n";
    #print "$index $rv\n";
    return $rv;
}

sub get_table_data {
    my ($IFH) = @_;

    seek ($IFH, 0, SEEK_SET) or die "Error seeking to start of file: $!";

    my $data;
    read ($IFH, $data, 2) == 2 or die "Error reading table length: $!";
    my $n_files = unpack ('v', $data);

    read ($IFH, $data, 268 * $n_files) == 268*$n_files or die "Error reading in table: $!";

    #my ($data2, $key, $ctr) = ('', 100, 100);
    #
    #for (my $i = 0; $i < 268 * $n_files; ++ $i) {
    #	$data2 .= chr (ord (substr ($data, $i, 1)) ^ $key);
    #	$key = ($key + $ctr) & 0xff;
    #	$ctr = ($ctr + 77) & 0xff;
    #}
    #my $data2 = '';
    #for (my $i = 0; $i < $n_files; ++ $i) {
    #	$data2 .= decrypt_file_table_block (268 * $i, substr ($data, 268*$i, 268));
    #}
    my $data2 = decrypt_file_table_block (0, $data);

    my @table = ();
    my %table = ();

    for (my $i = 0; $i < $n_files; ++ $i) {
	my ($fname, $len, $offset) = unpack ('a260VV', substr ($data2, $i*268, 268));
	#$fname =~ s/\0.*//;
	my $j = 0;
	while ($j < length ($fname) && substr ($fname, $j, 1) ne "\0") {++$j;}

	$fname = decode ("shift_jis", substr ($fname, 0, $j));
	my $tmp = { index => $i, offset => $offset, length => $len, name => $fname };
	#push @table, [ $fname, $offset, $len ];
	#$table{$fname} = { index => $i, offset => $offset, length => $len };
	push @table, $tmp;
	$table{$fname} = $tmp;
    }
    return (\%table, \@table);
}

sub show_file_table {
    binmode STDOUT, ":utf8";
    my ($fname) = @_;
    my $FH;
    open ($FH, '<', $fname) or die "Unable to open file: $!";
    my ($hash, $list) = get_table_data ($FH);

    print "HASH:\n";
    foreach (keys %$hash) {
	print "  $_ -> ", join (", ", %{$hash->{$_}}), "\n";
    }

    print "\nLIST:\n";
    foreach (@$list) {
	print "  ", join (", ", %$_), "\n";
    }
}

sub list_bundle {
    my ($bundle_path, $extract_path) = @_;

    die "$bundle_path does not exist" if (! -f $bundle_path);

    binmode STDOUT, ":utf8";

    my $IFH;
    open $IFH, "<", $bundle_path or die "Unable to open $bundle_path";

    my ($hash, $list) = get_table_data ($IFH);
    my ($str, $str2, $k);

    foreach my $h (@$list) {
	print "  ", join (", ", %$h), "\n";
    }
}

sub extract_bundle {
    my ($bundle_path, $extract_path, $pattern) = @_;

    die "$bundle_path does not exist" if (! -f $bundle_path);

    binmode STDOUT, ":utf8";

    my $IFH;
    open $IFH, "<", $bundle_path or die "Unable to open $bundle_path";

    my ($hash, $list) = get_table_data ($IFH);
    my ($str, $str2, $k);

    foreach my $h (@$list) {
	#if ($h->{name} =~ /$pattern/) {
	#    print "$h->{name} MATCHES  $pattern\n";
	#} else {
	#    #print "$h->{name} no match $pattern\n";
	#}
	#next;

	next if ($h->{name} !~ /$pattern/);
	print "  ", join (", ", %$h), "\n";
	seek ($IFH, $h->{offset}, SEEK_SET);
	read ($IFH, $str, $h->{length}) == $h->{length} or die "Error extracting from bundle";
	my $key = get_file_key ($h->{offset});
	for (my $i = 0; $i < $h->{length}; ++ $i) {
	    $str2 .= chr (ord (substr ($str, $i, 1)) ^ $key);
	}
	$str = '';

	my $out_name = $extract_path . '/' . $h->{name};

	if ($out_name =~ /\.cnv$/) {
	    $key = ord (substr ($str2, 0, 1));

	    if ($key == 1) {
		convert_wav (\$str2);
		$out_name =~ s/cnv$/wav/;
	    } elsif ($key == 24 || $key == 32) {
		convert_image (\$str2);
		$out_name =~ s/cnv$/tga/;
	    } else {
		print "Bad data key ($key) in $out_name\n";
	    }
	}
	for (my $i = 0; $i < length ($out_name); ++ $i) {
	    if (substr ($out_name, $i, 1) eq '/' &&
		! -d substr ($out_name, 0, $i)) {
		mkdir (substr ($out_name, 0, $i));
	    }
	}
	my $OFH;
	open $OFH, ">", $out_name or die "Unable to open $out_name";
	print $OFH $str2;
	$str2 = '';
    }
}

sub convert_image { #cnv2tga
    my ($rstr) = @_;
    
    my ($bpp, $width, $height, $width2, $zero) = unpack ("CVVVV", substr ($$rstr, 0, 17));
    
    #if ($width != $width2) { die "Two width values disagree: $width $width2"; }
    if ($width != $width2) { print " *** Warning ----: Two width values disagree: $width $width2\n"; }
    
    if ($bpp != 24 && $bpp != 32) { die "BPP must be 24 or 32, not $bpp"; }
    
    if ($width2 * $height * 4 + 17 != length ($$rstr)) { die "Data lengths disagree: ". ($width2 * $height * 4 + 17)." vs ".length ($$rstr); }
    
    if ($zero != 0) { die "Nonzero value in final header block"; }

    my $outdat = '';
    $outdat .= pack ('ccc'.'vvc'.'vvvvcc', 0,0,2,    0,0,0, 
                     0,0,$width,$height, 32, 0x08);
    for (my $r = $height - 1; $r >= 0; $r --) {
        for (my $c = 0; $c < $width2; ++ $c) {
            $outdat .= substr ($$rstr, 17 + 4 * ($r * $width2 + $c), 4);
        }
    }
    
    $$rstr = $outdat;
}

sub convert_wav { #cnv2wav
    my ($rstr) = @_;

    my ($audio_fmt, $n_channels, $sample_rate, $byte_rate, 
        $block_align, $bits_per_sample, $extra_param_size, $subchunk_2_size) 
        = unpack ("vvVV"."vvvV", substr ($$rstr, 0, 22));

    if ($subchunk_2_size != length($$rstr) - 22) {
        print " *** Warning ----: Size mismatch: $subchunk_2_size vs. ", length($$rstr)-22, ".\n";
        #die "Size mismatch: $subchunk_2_size vs. ", length($$rstr)-22, ".";
    }

    if ($byte_rate != ($sample_rate * $n_channels * ($bits_per_sample/8))) {
        die "Byte rate mismatch: $byte_rate vs. ".
            ($sample_rate * $n_channels * ($bits_per_sample/8));
    }
    if ($block_align != $n_channels * ($bits_per_sample/8)) {
        die "Block align mismatch: $block_align vs. ".
            $n_channels * ($bits_per_sample/8);
    }

    $$rstr = pack ('a4V'.'a4a4VvvVVvv'.'a4Va*', 
		   ('RIFF', $subchunk_2_size + 36), 
		   ('WAVE', 'fmt ', 16, $audio_fmt, $n_channels, $sample_rate,
		    $byte_rate, $block_align, $bits_per_sample), 
		   ('data', $subchunk_2_size, substr ($$rstr, 22)));
}

sub rpatch_dir {
    my ($OFH, $full_path, $local_path, $h_table, $bundle_mtime) = @_;

    #print "rpatch_dir ($full_path  $local_path)\n";

    my $DIR;
    opendir ($DIR, $full_path);
    my @flist = (readdir ($DIR));
    closedir ($DIR);

    foreach my $fn (@flist) {
	next if ($fn eq '.' || $fn eq '..');
	my $full_name = $full_path.'/'.$fn;
	my $local_name = $local_path.$fn;
	my $in_name = $local_name;
	$in_name =~ s/\.wav$/\.cnv/;
	$in_name =~ s/\.tga$/\.cnv/;

	if ( -d "$full_path/$fn" ) {
	    rpatch_dir ($OFH, $full_name, $local_name.'/', $h_table, $bundle_mtime);
	} elsif (defined $h_table->{$in_name}) {
	    print " **** PATCH FILE  $local_name **** \n";
	    if ($bundle_mtime < -M "$full_path/$fn") {
		print "File is older; skipping\n";
		next;
	    }
	    undef $@;
	    eval {
		patch_file ($OFH, $full_name, $h_table->{$in_name});
	    };
	    print "Error: $@\n" if $@;
	} else {
	    print "Ignoring file $local_name\n";
	}
    }
}

sub get_file_key {
    my $offset = shift;
    return (($offset >> 1) & 0xff) | 0x08;
}
	
sub read_file_in {
    my ($fn) = @_;

    my $IFH;
    open $IFH, "<", $fn;
    local $/;
    my $in_dat = <$IFH>;

    if ($fn =~ /\.wav$/) {
	print "Converting wav to cnv\n";
	my ($chunk_id, $chunk_size, $format,
	    ($sub_1_id, $sub_1_size, $aud_fmt, $n_channels, $s_rate, 
	     $byte_rate, $block_align, $bits_per_sample),
	    $sub_2_id, $sub_2_size) =
		unpack ('a4Va4'.'a4VvvVVvv'.'a4V', substr ($in_dat, 0, 44));
	if ($chunk_id ne 'RIFF' || $format ne 'WAVE' ||
	    $sub_1_id ne 'fmt ' || $sub_1_size != 16 || 
	    $sub_2_id ne 'data' || $chunk_size != $sub_2_size + 36) {
	    die "Bad headers on .wav";
	}
	if ($sub_2_size != length($in_dat) - 44) {
	    print " *** Warning $fn: Size mismatch: $sub_2_size vs. ", length($in_dat)-44, ".\n";
	    #die "Size mismatch: $subchunk_2_size vs. ", length($$rstr)-44, ".";
	}
	die "Can only use 44100 bps wavs, not $s_rate" if ($s_rate != 44100); 
	if ($byte_rate != ($s_rate * $n_channels * ($bits_per_sample/8))) {
	    die "Byte rate mismatch: $byte_rate vs. ".
		($s_rate * $n_channels * ($bits_per_sample/8));
	}
	if ($block_align != $n_channels * ($bits_per_sample/8)) {
	    die "Block align mismatch: $block_align vs. ".
		$n_channels * ($bits_per_sample/8);
	}
	return \ (pack ("vvVV"."vvvV", 
		       $aud_fmt, $n_channels, $s_rate, $byte_rate, 
		       $block_align, $bits_per_sample, 0, $sub_2_size).
		  substr ($in_dat, 44));
    } elsif ($fn =~ /\.tga$/) { # tga2cnv
	print "Converting tga to cnv\n";
	my ($arg_1, $arg_2, $arg_3,  $arg_4, $arg_5, $arg_6,
	    $arg_7, $arg_8,  $width, $height, $bpp, $trans) = 
		unpack ('cccvvc'.'vvvvcc', substr ($in_dat, 0, 18));
	if ($arg_1 != 0 || $arg_2 != 0 || $arg_3 != 2 || 
	    $arg_4 != 0 || $arg_5 != 0 || $arg_6 != 0 || 
	    $arg_7 != 0 || $arg_8 != 0) {
	    die "Bad headers on .tga";
	}
	die ".tga not 32 bpp" if ($bpp != 32);
	die ".tga has wrong transparency" if ($trans != 0x08);

	my $out_dat = pack ('CVVVV', $bpp, $width, $height, $width, 0);
	for (my $r = $height - 1; $r >= 0; -- $r) {
	    for (my $c = 0; $c < $width; ++ $c) {
		$out_dat .= substr ($in_dat, 18 + 4 * ($r * $width + $c), 4);
	    }
	}
	return \$out_dat;
    } else {
	print "Not converting\n";
	return \$in_dat;
    }
}

sub hexify_str {
    return join (' ', map { sprintf ("%02x", $_) } unpack ('C*', $_[0]));
}

sub patch_file {
    my ($OFH, $in_file_name, $ftable) = @_;

    print "Updating file ", join (" ", %$ftable), ".\n";

    my $r_data = read_file_in ($in_file_name);
    my $dat_len = length ($$r_data);

    if ($dat_len <= $ftable->{length}) {
	print "Seeking to ", $ftable->{offset}, ".\n";
	seek ($OFH, $ftable->{offset}, SEEK_SET) or die "Unable to seek: $!";
    } else {
	print "Seeking to end\n";
	seek ($OFH, 0, SEEK_END) or die "Unable to seek: $!";
    }
    my $new_offset = tell ($OFH);
    print "Updating at $new_offset\n";

    my $key = get_file_key ($new_offset);
    my $out_data = '';
    for (my $i = 0; $i < $dat_len; ++ $i) {
	$out_data .= chr (ord (substr ($$r_data, $i, 1)) ^ $key);
    }
    my $c_printed = print $OFH $out_data;
    #$c_printed == $dat_len or print "Write size mismatch: $dat_len to print, $c_printed printed\n";
    $c_printed or die "Error writing output data (c_printed = $c_printed): $!";

    if ($dat_len != $ftable->{length} || $new_offset != $ftable->{offset}) {
	my $f_index = 268*$ftable->{index} + 260 + 2;
	seek ($OFH, $f_index, SEEK_SET) or die "Unable to seek: $!";
	print "Updating file_table from ", $ftable->{length}, ", ", $ftable->{offset}, "  to  $dat_len, $new_offset\n";
	my $old_block;
	read ($OFH, $old_block, 8);
	#print "old was (", join (" ", unpack ('c8', $old_block)), ")\n";
	#print "old was (", join (' ', map { sprintf ("%02x", abs($_)) } unpack ('c8', $old_block)), ")\n";
	print "old was (", hexify_str ($old_block), ")\n";

	my $i = print $OFH decrypt_file_table_block ($f_index-2, pack ('VV', $dat_len, $new_offset));

	$old_block = decrypt_file_table_block ($f_index-2, pack ('VV', $ftable->{length}, $ftable->{offset}));
	#print "old shld(", join (' ', map { sprintf ("%02x", abs($_)) } unpack ('c8', $old_block)), ")\n";
	print "old shld(", hexify_str ($old_block), ")\n";

	#print "old decr(", hexify_str (pack ('VV', $ftable->{length}, $ftable->{offset}));

	$old_block = decrypt_file_table_block ($f_index-2, pack ('VV', $dat_len, $new_offset));
	#print "new is  (", join (" ", unpack ('c8', $old_block)), ")\n";
	print "new is  (", hexify_str ($old_block), ")\n";
	#print "new is  (", join (' ', map { sprintf ("%02x", abs($_)) } unpack ('c8', $old_block)), ")\n";
	#print "new decr(", hexify_str (pack ('VV', $ftable->{length}, $ftable->{offset}));

	$ftable->{offset} = $new_offset;
	$ftable->{length} = $dat_len;
	#$i == 1 or die "Error updating file table: $!";
    }
}
	
sub patch_bundle {
    my ($orig_bundle, $new_bundle, $root) = @_;

    my ($IFH, $OFH);
    
    #system ('cp', $orig_bundle, $new_bundle) && die "Unable to copy bundle";
    #my $i = system ('cp', $orig_bundle, $new_bundle);
    #print "copy -> $i\n";

    #open ($IFH, "<", $orig_bundle) or die "Unable to open $orig_bundle for patching";
    my $mtime = -M $new_bundle;
    open ($OFH, "+<", $new_bundle) or die "Unable to open $new_bundle for writing: $!";

    my ($h_table, $l_table) = get_table_data ($OFH);

    #show_file_table ($orig_bundle);

    rpatch_dir ($OFH, $root, '', $h_table,   $mtime);
}

#patch_bundle ('../Daybreak/daybreak01.dat', 'alt-bundle', 'new_01');
#patch_bundle ('../Daybreak/daybreak00.dat', 'alt-bundle', 'new_00');
#eval { patch_bundle ('../Daybreak/backup_daybreak00.dat', 'daybreak00.dat', 'new_00'); };

my $action = shift @ARGV;

if ($action eq '--update') {
    eval { patch_bundle ('../Daybreak/backup_daybreak00.dat', 'daybreak00.dat', 'new_00'); };
} elsif ($action eq '--update1') {
    eval { patch_bundle ('/media/sdb1/Program Files/07th Expansion/daybreak/orig.daybreak00.dat', '/media/sdb1/Program Files/07th Expansion/daybreak/daybreak00.dat', '/media/sdb1/Program Files/07th Expansion/daybreak/new_00'); };
} elsif ($action eq '--extract') {
    if (@ARGV < 2 || @ARGV > 3) {
	die "Usage: perl bundle-tools --extract <bundle> <destination> <files>";
    }
    my $bundle_name = shift @ARGV;
    my $dest_dir = shift @ARGV;
    my $pattern = '';
    if (@ARGV) { $pattern = shift @ARGV; }
    eval { extract_bundle ($bundle_name, $dest_dir, $pattern); }
} elsif ($action eq '--list') {
    eval { list_bundle ($ARGV[0], $ARGV[1]); }
} else {
    $@ = "Bad action: $action\n";
}

print "Error: $@" if $@;

#show_file_table ('../Daybreak/daybreak00.dat');
    
