#!/usr/bin/perl -w

$AFSSERVER="papadoc.bayour.com";

#[papadoc.pts/8]$ df -h | grep ' /vice'
#Filesystem            Size  Used Avail Use% Mounted on
#/dev/sdb7              89M  732k   88M   1% /vicepa
#/dev/sdf1              24G  328M   22G   2% /vicepc
#/dev/sdc1             8.4G  624M  7.7G   8% /vicepd
#/dev/sdd1              17G   16G  1.2G  93% /vicepe
#/dev/sda1             5.8G   33M  5.7G   1% /vicepf

print "                                                        {    A F S    }\n";
print "Filesystem            Size  Used Avail Use% Mounted on  Size Used Avail\n";

open(DF, "df -h \| grep ' /vice' |") || die("Can't df, $!\n");
while(!eof(DF)) {
    $line = <DF>; chomp($line);
    print $line;

    $part = (split(' ', $line))[5];

    #[papadoc.pts/8]$ vos partinfo papadoc /vicepa
    #Free space on partition /vicepa: 90824 K blocks out of total 91556
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
