#!/usr/bin/perl -w

# $Id: afsdb.pl,v 1.2 2003-10-11 08:24:01 turbo Exp $

$AFSSERVER="papadoc.bayour.com";

print "                                                        {    A F S    }\n";
print "Filesystem            Size  Used Avail Use% Mounted on  Size Used Avail\n";

open(DF, "df -h \| grep ' /vice' |") || die("Can't df, $!\n");
while(!eof(DF)) {
    $line = <DF>; chomp($line);
    print $line;

    $part = (split(' ', $line))[5];

    open(VOS, "vos partinfo $AFSSERVER $part |")
	|| die("Can't vos, $!\n");
    $line = <VOS>; chomp($line);
    close(VOS);

    $size  = (split(' ', $line))[11];
    $used  = (split(' ', $line))[5];
    $avail = $size - $used;

    if($size >= 1000000) {
	$size = $size / 1000000;
	$size_suffix = "G";
    } elsif($size >= 1000) {
	$size = $size / 1000;
	$size_suffix = "M";
    } else {
	$size_suffix = "k";
    }

    if($used >= 1000000) {
	$used = $used / 1000000;
	$used_suffix = "G";
    } elsif($used >= 1000) {
	$used = $used / 1000;
	$used_suffix = "M";
    } else {
	$used_suffix = "k";
    }

    if($avail >= 1000000) {
	$avail = $avail / 1000000;
	$avail_suffix = "G";
    } elsif($avail >= 1000) {
	$avail = $avail / 1000;
	$avail_suffix = "M";
    } else {
	$avail_suffix = "k";
    }

    printf("  %6d$size_suffix%4d$used_suffix%5d$avail_suffix\n", $size, $used, $avail);
}
close(DF);
