#!/usr/bin/perl -w

@LIST = ('a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l',
	 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x',
	 'y', 'z');

# ------------------------------------
sub scsi_target() {
    my($dev) = @_;

    $controller = (split('/', $dev))[3];
    $controller =~ s/host//;

    $id = (split('/', $dev))[5];
    $id =~ s/target//;
    $id = sprintf("%0.2d", $id);

    return($controller, $id);
}

# ------------------------------------
if(open(MDSTAT, "/proc/mdstat")) {
    while(! eof(MDSTAT)) {
	$line = <MDSTAT>; chomp($line);
	if($line =~ /^md/) {
	    $dev_md = (split(' ', $line))[0];
	    open(MDADM, "mdadm -D /dev/$dev_md |") || die "Can't mdadm /dev/$dev_md, $!\n";
	    while(! eof(MDADM)) {
		$line = <MDADM>; chomp($line);
		undef($dev_raid); undef($dev_type);
		
		if($line =~ /active sync/) {
		    $dev_raid = (split(' ', $line))[6];
		    $dev_type = '';
# Not really intresting - all are active, unless they aren't something
# else - such as 'spare' :)
#		    $dev_type = '/active';
		} elsif($line =~ /spare/) {
		    $dev_raid = (split(' ', $line))[5];
		    $dev_type = '/spare';
#		} elsif($line =~ /removed$/) {
#       8       0        0       -1      removed
#		    $dev_raid = (split(' ', $line))[5];
		}
		
		if($dev_raid) {
		    ($ctrl, $id) = &scsi_target($dev_raid);
		    $MD{$ctrl}{$id} = $dev_md;
		    $MD_TYPE{$ctrl}{$id} = $dev_type;
		}
	    }
	    close(MDADM);
	}
    }
    close(MDSTAT);
}

# ------------------------------------
$scsi_number = 0;
open(SCSI, "/proc/scsi/scsi") || die "Can't open /proc/scsi/scsi, $!\n";
$line[0] = <SCSI>;

printf(STDERR "%4s %-2s %-9s %-18s %-5s %5s %4s\n", "Host", "Id", "Vendor", "Model", "Rev", "Size", "RAID");
printf(STDERR "===========================================================\n");
while(! eof(SCSI)) {
    for($i=0; $i < 3; $i++) {
	#Host: scsi0 Channel: 00 Id: 00 Lun: 00
	#  Vendor: SEAGATE  Model: ST336704FSUN36G  Rev: 042D
	#  Type:   Direct-Access                    ANSI SCSI revision: 03
	$line[$i] = <SCSI>;
	chomp($line[$i]);
    }

    @tmp = split(' ', $line[0]);
    $ctrl = $tmp[1]; $ctrl =~ s/scsi//;
    $chan = $tmp[3]; $chan =~ s/^0//;
    $id = $tmp[5]; $ID = $id; $id =~ s/^0//;
    $lun = $tmp[7]; $lun =~ s/^0//;

    @tmp = split(' ', $line[1]);
    $vend = $tmp[1];
    $model = $tmp[3];
    if($tmp[5] =~ /Rev/) {
	$rev = $tmp[6];
    } else {
	$rev = $tmp[5];
    }

    # Get scsi controller and disk ID
    $dev1 = "/dev/scsi/host$ctrl/bus0/target$id/lun$lun/disc";
    $dev2 = $LIST[$scsi_number];

    if(-e "$dev1") {
	$dev = $dev1;
        $grp = '';
    } elsif(-e "/dev/sd$dev2") {
	$dev = "/dev/sd$dev2";
        $grp = '|/sd'.$dev2.'3';
    }

    # Get the size of the disc
    open(FDISK, "fdisk -l $dev 2>&1 | egrep '/disc3$grp|^Disk.*contain a valid' |")
        || die("Can't read from fdisk, $!\n");
    $fdisk = <FDISK>;
    close(FDISK);

    if($fdisk) {
	chomp($fdisk);

	# Disk /dev/scsi/host4/bus0/target10/lun0/disc doesn't contain a valid partition table
	if($fdisk =~ /^Disk.*doesn.*contain a valid/) {
	    $size = "";
	} else {
	    # Parse fdisk output - we want the total size field (#4)
	    $size = (split(' ', $fdisk))[3] / (1024*1024);
	    $size =~ s/\..*//;
	    $size .= "Gb";
	}
    } else {
	$size = "";
    }

    if($MD{$ctrl}->{$ID}) {
	printf("%4s %-2s %-9s %-18s ", $ctrl, $ID, $vend, $model);
	printf("%-5s ", $rev);
	#printf(STDERR "%-5s ", $rev);
	printf("%5s %4s%s\n", $size, $MD{$ctrl}->{$ID}, $MD_TYPE{$ctrl}->{$ID});
    } else {
	printf(STDERR "%4s %-2s %-9s %-18s %-5s %5s\n",
	       $ctrl, $ID, $vend, $model, $rev, $size);
    }

    $scsi_number++;
}
