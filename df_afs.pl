#!/usr/bin/perl -w

# $Id: df_afs.pl,v 1.3 2004-09-18 09:00:32 turbo Exp $

$AFSSERVER="aurora.bayour.com";

print "                                                        {    A F S    }\n";
print "Filesystem            Size  Used Avail Use% Mounted on  Size Used Avail\n";

sub resize {
    my($value) = @_;

    if($value >= 1000000) {
	$value  = $value / 1000000;
	$suffix = "G";
    } elsif($value >= 1000) {
	$value  = $value / 1000;
	$suffix = "M";
    } else {
	$suffix = "k";
    }

    return($value, $suffix);
}

open(DF, "df -h \| grep ' /vice' |") || die("Can't df, $!\n");
while(!eof(DF)) {
    $line = <DF>; chomp($line);
    print $line;

    $part = (split(' ', $line))[5];

    # Free space on partition /vicepf: 6033088 K blocks out of total 6065968
    open(VOS, "vos partinfo $AFSSERVER $part |")
	|| die("Can't vos, $!\n");
    $line = <VOS>; chomp($line);
    close(VOS);

    $size  = (split(' ', $line))[11];
    $avail = (split(' ', $line))[5];
    $used  = $size - $avail;

    ($size,  $size_suffix)  = &resize($size);
    ($used,  $used_suffix)  = &resize($used);
    ($avail, $avail_suffix) = &resize($avail);

    printf("  %6d$size_suffix%4d$used_suffix%5d$avail_suffix\n", $size, $used, $avail);
}
close(DF);
