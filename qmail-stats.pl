#!/usr/bin/perl -w

sub get_time {
    my($line) = @_;

    $time = (split(' ', $line))[0];
    if($time =~ /\./) {
	# UNIX std time
	$time = (split('\.', $time))[0];
    } else {
	# Human readable - convert back to UNIX std time
	($time1, $time2) = split(' ', $line);
	$time2 = (split('\.', $time2))[0];

	$time = `date -d "$time1 $time2" "+%s"`;
	chomp($time);
    }

    return($time);
}

# Get options to command
if($ARGV[0]) {
    foreach $arg (@ARGV) {
	$allstats=1 if($arg eq '--all');
	$DEBUG=1 if($arg eq '--debug');
	$emails=1 if(($arg eq '--emails') || ($arg eq '--all'));
	if($arg eq '--help') {
	    print "Usage: `basename $0` [options]\n";
	    print "       --all      Show information of each deliver (start, end, recipient etc)\n";
	    print "       --debug    Only do the first 100 lines in the file\n";
	    print "       --emails   Show number of deliveries to each email address\n";
	    exit(0);
	}
    }
}

$hostname = `hostname`;
chomp($hostname);

$i=0;
while(! eof(STDIN) ) {
    $line = <STDIN>; chomp($line);

# ----------------
#2002-09-17 06:35:15.334422 starting delivery 1: msg 16799625 to local turbo@bayour.com
#2002-09-17 06:35:23.327073 delivery 1: success: did_1+0+0/
#
#1032237315.334422 starting delivery 1: msg 16799625 to local turbo@bayour.com
#1032237323.327073 delivery 1: success: did_1+0+0/
# ----------------

    if($line =~ / starting delivery .*:.* to local /) {
	# Get the msg number
	if($line =~ /^20[0-9][0-9]-.*/) {
	    # Human readable
	    $msgnr =  (split(' ', $line))[4];
	} else {
	    # Unix std time
	    $msgnr =  (split(' ', $line))[3];
	}
	$msgnr =~ s/:$//;

	# Get the time
	$begin{$msgnr} = &get_time($line);

	if($line =~ /^20[0-9][0-9]-.*/) {
	    # Human readable
	    $recip = (split(' ', $line))[9];
	} else {
	    # Unix std time
	    $recip = (split(' ', $line))[8];
	}

	# Take care of addresses that look like:
	#	cvs-phpqladmin-accept-1039674204.20422.dcchhkffaapngloidhkm@bayour.com
	#	phpqladmin-sc.1043669747.agifmnfgpjpbaiklmfpl-jjo-phpqladmin=mendoza.gov.ar@bayour.com
	#	phpqladmin-request@bayour.com
	#	phpqladmin-return-6-@bayour.com
	#	phpqladmin-subscibe@bayour.com
	#	phpqladmin-subscribe-ehults=paydata.com@bayour.com
	# (ezmlm mailinglist moderation request etc)
	if(($recip =~ /.*-accept-.*/) || ($recip =~ /.*-sc\.[0-9].*=/) ||
	   ($recip =~ /.*-request\@.*/) || ($recip =~ /.*-return-[0-9]-.*/) ||
	   ($recip =~ /.*-subscribe.*/) || ($recip =~ //))
	{
	    $recip =~ s!-.*\@!\@!;
	}

	# Strip the hostname
	if($recip =~ $hostname) {
	    $recip =~ s!$hostname\.!!;
	}

	# Lowercase recipient
	$recip = lc($recip);

	$dest{$msgnr} = $recip;
	$delivery{$recip}++;

	# If this is the first delivery, we need to
	# remember the date and time for this
	if(! $first) {
	    $first = `echo $begin{$msgnr} | tailocal`;
	    chomp($first);
	}
    } elsif($line =~ / delivery .*: success: did/) {
	# Get the msg number
	if($line =~ /^20[0-9][0-9]-.*/) {
	    # Human readable
	    $msgnr   = (split(' ', $line))[3];
	} else {
	    # Unix std time
	    $msgnr   = (split(' ', $line))[2];
	}
	$msgnr =~ s/:$//;

	# Get the time
	$end{$msgnr} = &get_time($line);
    }

    if($i >= 100) {
	if(($begin{$msgnr} && !$end{$msgnr}) && $DEBUG) {
	    # Just make sure we get the end time/date for the
	    # last delivery (so the stats isn't cut of with
	    # a start delivery, but we don't get the END of
	    # the delivery).
	    $i=99;
	} else {
	    goto LOOP;
	}
    }
    $i++ if($DEBUG);
}

LOOP:
    # Remember the last entry
    $last = `echo $end{$msgnr} | tailocal`;
    chomp($last);

    $high = 0; $i = 0; $avg = 0;

    foreach $nr (sort { $begin{$a} <=> $begin{$b} } keys(%begin)) {
	# Get start and end time of delivery
	$time1 = `echo $begin{$nr} | tailocal`;
	$time2 = `echo $end{$nr}   | tailocal` if($end{$nr});
	chomp($time1); chomp($time2);
	
	# How long did the delivery take?
	$time3 = $end{$nr} - $begin{$nr} if($end{$nr});

	# Calculate some statistics
	$high  = $time3 if($time3 > $high);
	$avg   = $avg + $time3;
	
	printf("%5d: $time1 - $time2 (%3d sec) -> $dest{$nr}\n", $nr, $time3)
	    if($allstats);
	$i++;
    }

    # Output the statistics
    print "\n" if($allstats);
    print "Status between '$first' and '$last'\n";
    printf("Highest time of delivery:             %5d\n", $high);
    printf("Average delivery time:                %5d\n", $avg/$i);
    printf("Number of deliveries:                 %5d\n", $i);

    if($emails) {
	foreach $recip (sort keys(%delivery)) {
	    printf("  %-35s  %4d\n", $recip, $delivery{$recip});
	}
    }
