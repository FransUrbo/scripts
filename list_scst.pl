#!/usr/bin/perl

$SYSFS = "/sys/kernel/scst_tgt";

sub get_dir {
    my ($dir) = shift;
    my (@ENTRIES);
    my ($d);

    opendir(DIR, "$dir") || die "Can't open '$dir', $!\n";
    while($d = readdir(DIR)) {
        next if($d =~ /^\./);
        next if($d eq 'mgmt');
        next if($d eq 'type');

        push(@ENTRIES, $d);
    }
    closedir(DIR);

    return @ENTRIES;
}

sub get_value {
    my ($file) = shift;
    my ($line);

    open(FILE, "$file") || die "Can't open '$file', $!\n";
    $line = <FILE>;
    close(FILE);

    chomp($line);
    return $line;
}

# ---------------------------

if(! -e "$SYSFS") {
    print "SCST don't seem to be loaded/started.\n";
    exit 1;
}

# Handlers
@HANDLERS = get_dir("$SYSFS/handlers");

# Drivers
@DRIVERS = get_dir("$SYSFS/targets");

# Devices
foreach my $handler (@HANDLERS) {
    my @DEVs = get_dir("$SYSFS/handlers/$handler");
    foreach my $device (@DEVs) {
        next if(! -f "$SYSFS/devices/$device/filename");

        my $fsdev      = get_value("$SYSFS/devices/$device/filename");
        my $size_block = get_value("$SYSFS/devices/$device/blocksize");
        my $size_dev   = get_value("$SYSFS/devices/$device/size_mb");

        $DEVICES{$device} = "$fsdev;$handler;$size_block;$size_dev";
    }
}

# Targets
foreach my $driver (@DRIVERS) {
    opendir(DIR, "$SYSFS/targets/$driver")
        || die "Can't open dir '$SYSFS/targets/$driver'";
    while(my $iqn = readdir(DIR)) {
        next if($iqn !~ /^iqn\./);
        next if(! -f "$SYSFS/targets/$driver/$iqn/enabled");

        my $stat = get_value("$SYSFS/targets/$driver/$iqn/enabled");
        my $tid  = get_value("$SYSFS/targets/$driver/$iqn/tid");

        my $device;
        opendir(DIR2, "$SYSFS/targets/$driver/$iqn/luns")
            || die "Can't open luns dir '$SYSFS/targets/$driver/$iqn/luns', $!\n";
        while(my $lun = readdir(DIR2)) {
            next if($lun =~ /^\./);
            next if($lun eq 'mgmt');
            next if(! -l "$SYSFS/targets/$driver/$iqn/luns/$lun/device");

            $device = `/bin/ls -l "$SYSFS/targets/$driver/$iqn/luns/$lun/device"`;
            chomp($device);
            $device =~ s/.*\///;

            last;
        }
        closedir(DIR2);

        $TARGETS{$tid} = "$iqn;$device;$stat";
    }
    closedir(DIR);
}

# ---------------------------

if(@ARGV) {
    print "Drivers: ";
    for(my $i = 0; $DRIVERS[$i]; $i++) {
        print $DRIVERS[$i];
        print ", " if($DRIVERS[$i+1]);
    }
    print "\n";

    print "Handlers: ";
    for(my $i = 0; $HANDLERS[$i]; $i++) {
        print $HANDLERS[$i];
        print ", " if($HANDLERS[$i+1]);
    }
    print "\n";

    print "Targets:\n";
    printf("  %4s  %-80s %-70s %-7s %4s %s\n", "TID", "IQN", "DEVICE", "SIZE", "BS", "HANDLER");
}

foreach my $tid (sort { $a <=> $b } keys(%TARGETS) ){
    my ($iqn, $device, $stat) = split(';', $TARGETS{$tid});
    my ($fsdev, $handler, $size_block, $size_dev) = split(';', $DEVICES{$device});

    if(!@ARGV) {
        $size = $size_dev / 1000;
        $size =~ s/\..*//;
        $size .= "GB";
    } else {
        $size = $size_dev."MB";
    }

    printf("  %4s: %-80s %-70s %7s %4d %s\n", $tid, $iqn, $fsdev, $size, $size_block, $handler);
}
