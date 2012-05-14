#!/usr/bin/perl -w

$DEBUG = 1;
printf("  %-8s %-4s %-30s%-40s%-10s%-10s%-10s%-10s\n\n",
       "Host", "Name", "Model", "Device by ID", "Rev", "MD", "VG", "ZFS");

# -------------------------
# DEBUG: Dump the whole %HOSTS array recursivly
sub dump_data() {
    print "\n-----------------\n\n" if($DEBUG);

    foreach my $bus (sort keys %PCI) {
        print "PCI ID: '$bus'\n";

        if($HOSTS{$bus}) {
            my %tmp1 = %{$HOSTS{$bus}};
            foreach my $type (sort keys %tmp1) {
                my %tmp2 = %{$HOSTS{$bus}{$type}};

                foreach my $nr (sort keys %tmp2) {
                    print "  HOSTS{$bus}{$type}{$nr}: ".$HOSTS{$bus}{$type}{$nr}."\n";
                }
            }
        }
    }
}

# -------------------------
# Get all disks by ID
open(DID, "ls -l /dev/disk/by-id/{ata,scsi}-* |") ||
    die("Can't run ls on by-id, $!\n");
while(! eof(DID)) {
    $line = <DID>;
    chomp($line);
    next if($line =~ /-part[0-9]/);
    next if($line =~ /^total/);
    print "DID: $line\n" if($DEBUG);

    # lrwxrwxrwx 1 root root  9 2011-10-27 17:55 scsi-SATA_VBOX_HARDDISK_VB05eeb659-6c29050f -> ../../sdk
    $line =~ s/.*by-id\/([a-z].*[a-z])-([A-Z].*) -> .*\/(.*)/$1:$2:$3/;

    # 'ata':'VBOX_HARDDISK_VB05eeb659-6c29050f':'sdk'
    # 'scsi':'SATA_VBOX_HARDDISK_VB05eeb659-6c29050f':'sdk'
    ($type, $name, $dev) = split(':', $line);
    print "  DID{$type}{$dev} = $name\n" if($DEBUG);

    $DID{$type}{$dev} = $name;
}
close(DID);

# -------------------------
# Get MD devs
if(-f "/proc/mdstat") {
    open(MD, "/proc/mdstat") ||
        die("Can't open mdstat, $!\n");
    while(! eof(MD)) {
        $line = <MD>;
        chomp($line);

        next if($line !~ /^md/);

        print "MD: $line\n" if($DEBUG);
        push(@MDs, $line);
    }
    close(MD);
} else {
    $MDs = ();
}

# -------------------------
# Get the PCI bus list
open(PCI, "lspci -D |") ||
    die("Can't list PCI bus, $!\n");
while(! eof(PCI)) {
    $line = <PCI>;
    chomp($line);
    print "PCI: $line\n" if($DEBUG);

    if(($line =~ /SATA/) || ($line =~ /SCSI/) || ($line =~ /IDE/)) {
        $bus   =  $line;
        $bus   =~ s/ .*//;
        $PCI{$bus} = $bus;
        print "  PCI{$bus} = $bus\n" if($DEBUG);

        # Get all disks for this controller
        # ERROR: Does not work in kernel 3.x !
        open(FIND, "find /sys/bus/pci/devices/$bus/{host*,ide*} -name 'block*' 2> /dev/null |") ||
            die("Can't find disk hosts, $!\n");
        while(! eof(FIND)) {
            $path =  <FIND>;
            chomp($path);
            print "  path: $path\n" if($DEBUG);

            # -----
            $host_path =  $path;
            $host_path =~ s/\/target.*//;
            $host_path =~ s/\/block.*//;

            $hostnr = $host_path;
            if($hostnr =~ s/.*\/host//) {
                # /sys/bus/pci/devices/0000:02:00.0/host1
                # => '1'

                $host   = sprintf("host%s", $hostnr); # host1
                $hostnr = sprintf("host%0.2d", $hostnr); # host01
            } elsif($hostnr =~ s/.*\/ide//) {
                # /sys/bus/pci/devices/0000:00:14.1/ide1/1.0
                # => '1/1.0'

                $hostnr =~ s/.*\///;
                $hostnr =  sprintf("ide%s", $hostnr); # ide1.0

                $host   =  $hostnr; # => ide1.0
                $host   =~ s/\.0/M/; # Master
                $host   =~ s/\.1/S/; # Slave
            }

            # -----
            $dev =  $path;
            $dev =~ s/.*://;

            for($i=0; $i < $#MDs; $i++) {
                print "($i) $dev => '".$MDs[$i]."'";

                if($dev =~ /$MDs[$i]/) {
                    print "  <=";
                    $md =  $MDs[$i];
                    $md =~ s/ :.*//;

                    $HOSTS{$bus}{'mdmember'}{$hostnr} = $md;
                }

                print "\n";
            }

            # -----
            $HOSTS{$bus}{'path'}{$hostnr} = $host_path; # Path to host
            $HOSTS{$bus}{'host'}{$hostnr} = $host;
            $HOSTS{$bus}{'dev'}{$hostnr}  = $dev;
            print "  HOSTS{$bus}{???}{$hostnr} = ???\n" if($DEBUG);

            # -----
            $name = $model = $rev = '';
            open(BLOCK, "find $path -name 'block*' 2> /dev/null |") ||
                die("Can't find sys block, $!\n");
            $block_path = <BLOCK>;
            close(BLOCK);
            if(defined($block_path)) {
                chomp($block_path);

                $block_path =~ s/\/block.*//;
                if(-f "$block_path/model") {
                    open(MODEL, "$block_path/model") ||
                        die("Can't open sys block model file ($block_path/model), $!\n");
                    $model = <MODEL>;
                    chomp($model);
                    close(MODEL);
                }

                if(-f "$block_path/rev") {
                    open(REV, "$block_path/rev") ||
                        die("Can't open sys block rev file ($block_path/rev), $!\n");
                    $rev = <REV>;
                    chomp($rev);
                    close(REV);
                }
            }

            $HOSTS{$bus}{'model'}{$hostnr} = (defined($model)) ? $model : 'n/a';
            $HOSTS{$bus}{'rev'}{$hostnr}   = (defined($rev))   ? $rev   : 'n/a';

            # -----

            foreach $did (sort keys %DID) {
                foreach $dev (sort keys %{$DID{$did}}) {
                    if($dev eq $name) {
                        $HOSTS{$bus}{'type'}{$hostnr} = $did;
                    }
                }
            }
        }

        close(FIND);
    } # if $line =~ SATA|SCSI|IDE
}
close(PCI);

# -------------------------
# Get zpools
$cmd=`which zpool`; chomp($cmd);
if(-x "$cmd") {
    open(ZPOOL, "zpool status |") ||
	die("Can't run 'zpool status', $!\n");
    while(! eof(ZPOOL)) {
	$line = <ZPOOL>;
	chomp($line);

        print "ZPOOL: $line\n" if($DEBUG);
	push(@ZPOOL, $line);
    }
    close(ZPOOL);
} else {
    $ZPOOL = ();
}

# -------------------------
# Get LVM pvs
$cmd=`which pvscan`; chomp($cmd);
if(-x "$cmd") {
    open(PVS, "pvscan |") ||
	die("Can't run pvscan, $!\n");
    while(! eof(PVS)) {
	$line = <PVS>;
	chomp($line);
        print "PVS: $line\n" if($DEBUG);

	next if($line !~ /PV /);

	# PV /dev/md2   VG movies   lvm2 [1,36 TB / 0    free]
	@line = split(' ', $line);

	$PVS{$line[1]} = $line[3];
        print " PVS{".$line[1]."} = ".$line[3]."\n" if($DEBUG);
    }
    close(PVS);
}

&dump_data();
exit(0);

# -------------------------
# M A I N  L O O P
foreach $bus (sort keys %PCI) {
    printf("$bus\n");

    if($PCI[$i] =~ /SATA/i) {
	$type = "scsi";
    } else {
	$type = "ata";
    }

    # ----------------------
    # Get MD device
    foreach $hostnr (sort keys %{$HOSTS{'path'}}) {
	$dev = $HOSTS{'dev'}{$hostnr};

	foreach $md (@MDs) {
            print "$md =~ /$dev/\n";
	    if($md =~ /$dev/) {
		# $md = 'md3 : active raid1 sdg1[0] sdb1[1]'
		$md =~ s/ :.*//;
                last;
	    }
	}

	$md = 'n/a' if(!defined($md));
    }

    # ----------------------
    # Get device name (Disk by ID)
    if(defined($DID{$type}{$dev})) {
        $DID = $DID{$type}{$dev};
    } else {
        $DID = 'n/a';
    }

    # ----------------------
    # Get ZFS pool data for this disk ID
    for($j=0; $j <= $#ZPOOL; $j++) {
        if($ZPOOL[$j] =~ /pool: /) {
            $zfs_name =  $ZPOOL[$j];
            $zfs_name =~ s/.*: //;
        } elsif($ZPOOL[$j] =~ /state: /) {
            $zfs_state =  $ZPOOL[$j];
            $zfs_state =~ s/.*: //;
        } elsif(($ZPOOL[$j] =~ /raid/)  || ($ZPOOL[$j] =~ /mirror/) ||
                ($ZPOOL[$j] =~ /cache/) || ($ZPOOL[$j] =~ /spare/   ))
        {
            $zfs_vdev = (split(' ', $ZPOOL[$j]))[0];
        } elsif(($ZPOOL[$j] =~ /$DID/) || ($ZPOOL[$j] =~ /$dev/)) {
            $offline = ' ';
            if(($ZPOOL[$j] !~ /ONLINE/) && ($ZPOOL[$j] !~ /AVAIL/)) {
                $offline = '!';

                if($ZPOOL[$j] =~ /OFFLINE/) {
                    $offline = $offline."OFFLINE";
                } elsif($ZPOOL[$j] =~ /UNAVAIL/) {
                    $offline = $offline."UNAVAIL";
                } elsif($ZPOOL[$j] =~ /FAULTED/) {
                    $offline = $offline."FAULTED";
                }
            }

            if(defined($zfs_name) && defined($zfs_vdev)) {
                $zfs = sprintf("%-17s$offline", "$zfs_name / $zfs_vdev");
            }
        }
    }
    $zfs = 'n/a' if(!defined($zfs));

    # ----------------------
    # Get Virtual Group
    if($PVS{"/dev/$md"}) {
        $vg = $PVS{"/dev/$md"};
    } else {
        $vg = 'n/a';
    }

    # ----------------------
    # Output information
    printf("  %-8s %-4s %-30s%-40s%-10s%-10s%-10s%-10s\n",
           $HOSTS{'host'}{$hostnr}, $HOSTS{'dev'}{$hostnr},
           "$model", "$DID", $HOSTS{'rev'}{$hostnr}, $md, $vg, "$zfs");
}
