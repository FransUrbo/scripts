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
    for($i=0; $ARGV[$i]; $i++) {
	$arg = $ARGV[$i];

	$allstats=1 if($arg eq '--all');
	$DEBUG=1 if($arg eq '--debug');
	$emails=1 if(($arg eq '--emails') || ($arg eq '--all'));
	$quiet=1 if($arg eq '--quiet');

	if($arg eq '--help') {
	    print "Usage: `basename $0` [options]\n";
	    print "       --all                  Show information of each deliver (start, end, recipient etc)\n";
	    print "       --debug                Only do the first 100 lines in the file\n";
	    print "       --emails               Show number of deliveries to each email address\n";
	    print "       --domain [domain.tld]  Output statistics for domain.tld only\n";
	    print "       --quiet                Output one line with 'received sent bounce' values\n";
	    exit(0);
	}

	if($arg eq '--domain') {
	    $i++; $DOMAIN = $ARGV[$i]; 
	}
    }
}

$hostname = `hostname`;
chomp($hostname);

$i = $bounce = $remote = 0; 
while(! eof(STDIN) ) {
    $line = <STDIN>; chomp($line);

    if($line =~ / starting delivery .*:.* to local /) {
	# 1032237315.334422 starting delivery 1: msg 16799625 to local turbo@bayour.com
	#
	# 2002-09-17 06:35:15.334422 starting delivery 1: msg 16799625 to local turbo@bayour.com

	# Get the msg number
	if($line =~ /^20[0-9][0-9]-.*/) {
	    # Human readable
	    $msgnr =  (split(' ', $line))[4];
	} else {
	    # Unix std time
	    $msgnr =  (split(' ', $line))[3];
	}
	$msgnr =~ s/:$//;
	next if(!$msgnr);

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
	#	phpqladmin-return*-@bayour.com
	#	phpqladmin-subscibe@bayour.com
	#	phpqladmin-subscribe-ehults=paydata.com@bayour.com
	#	phpqladmin-faq@bayour.com
	#	phpqladmin-help@bayour.com
	#	phpqladmin-info@bayour.com
	# (ezmlm mailinglist moderation request etc)
	if(($recip =~ /.*-accept-.*/) || ($recip =~ /.*-[us]c\.[0-9].*=/) ||
	   ($recip =~ /.*-request\@.*/) || ($recip =~ /.*-subscribe.*/) ||
	   ($recip =~ /.*-faq\@.*/) || ($recip =~ /.*-help.*\@.*/) || 
	   ($recip =~ /.*-return.*\@.*/) || ($recip =~ /.*-info\@.*/))
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
	$domain = (split('\@', $recip))[1];

	$tmp = (split('\@', $recip))[0];
	$delivery{$domain}{$tmp}++;
	$delivery{$domain}{'TOP'}++;

	# If this is the first delivery, we need to
	# remember the date and time for this
	if(! $first) {
	    $first = `echo $begin{$msgnr} | /usr/local/bin/tailocal`;
	    chomp($first);
	}
    } elsif($line =~ / starting delivery .*:.* to remote /) {
	# 2003-05-28 00:19:39.449583 starting delivery 2478: msg 161215 to remote baby6@3333.3utilities.com
	#
	# 1054100604.173939 starting delivery 100: msg 161212 to remote 9l2zrhnxlifz@loyus.com
	# Get the msg number
	if($line =~ /^20[0-9][0-9]-.*/) {
	    # Human readable
	    $msgnr =  (split(' ', $line))[4];
	} else {
	    # Unix std time
	    $msgnr =  (split(' ', $line))[3];
	}
	$msgnr =~ s/:$//;
	next if(!$msgnr);

	$remote{'TOP'}++; $remote{$domain}++ if($domain);
    } elsif($line =~ / delivery .*: deferral: /) {
	# 2003-05-28 00:37:24.417470 delivery 2518: deferral: Sorry,_I_couldn't_find_any_host_by_that_name._(#4.1.2)/
	# Failed delivery

	$remote{'TOP'}--; $remote{$domain}-- if($domain);
	$bounce{'TOP'}++; $bounce{$domain}++ if($domain);
    } elsif($line =~ / delivery .*: success: did/) {
	# 1054096268.233525 delivery 2: success: did_0+0+1/
	#
	# 2003-05-28 00:20:28.052708 delivery 2479: success: did_0+0+1/

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
exit(0) if(!$msgnr); # We have no statistics - exit

LOOP:
    # Remember the last entry
    $last = `echo $end{$msgnr} | /usr/local/bin/tailocal`;
    chomp($last);

    $high = 0; $i = 0; $avg = 0;

    foreach $nr (sort { $begin{$a} <=> $begin{$b} } keys(%begin)) {
	# Get start and end time of delivery
	$time1 = `echo $begin{$nr} | /usr/local/bin/tailocal`;
	$time2 = `echo $end{$nr}   | /usr/local/bin/tailocal` if($end{$nr});
	chomp($time1); chomp($time2);
	
	# How long did the delivery take?
	$time3 = $end{$nr} - $begin{$nr} if($end{$nr});

	# Calculate some statistics
	$high  = $time3 if($time3 > $high);
	$avg   = $avg + $time3;
	
	printf("%5d: $time1 - $time2 (%3d sec) -> $dest{$nr}\n", $nr, $time3)
	    if($allstats && !$quiet);
	$i++;
    }

    # Output the statistics
    if(!$quiet) {
	print "\n" if($allstats);
	print "Status between '$first' and '$last'\n";
	printf("Highest time of delivery:           %5d\n", $high);
	printf("Average delivery time:              %5d\n", $avg/$i);
	print "\n";

	if(!$DOMAIN) {
	    printf("Number of LOCAL deliveries:         %5d\n", $i);
	    printf("Number of REMOTE deliveries:        %5d\n", $remote{'TOP'});
	    printf("Bounces or failed deliveries:       %5d\n", $bounce{'TOP'});
	} else {
	    printf("Number of LOCAL deliveries:         %5d\n", $delivery{$DOMAIN}->{'TOP'});
	    printf("Number of REMOTE deliveries:        %5d\n", $remote{$DOMAIN});
	    printf("Bounces or failed deliveries:       %5d\n", $bounce{$DOMAIN});
	}
	print "\n";
    }

    if($emails) {
	if($DOMAIN) {
	    if($quiet) {
		# in out bounce
		print "$delivery{$DOMAIN}->{'TOP'} $remote{$DOMAIN} $bounce{$DOMAIN}";
	    } else {
		printf("Domain: %-27s %5d\n", $DOMAIN, $delivery{$DOMAIN}->{'TOP'});
		
		# Dereference the two-dimensional array.
		foreach $recip (sort keys(%{ $delivery{$DOMAIN} })) {
		    if($recip ne 'TOP') {
			printf("        %-27s %5d\n", $recip, $delivery{$DOMAIN}->{$recip});
		    }
		}
		
		print "\n";
	    }
	} else {
	    if(!$quiet) {
		foreach $domain (sort keys(%delivery)) {
		    printf("Domain: %-27s %5d\n", $domain, $delivery{$domain}->{'TOP'});
		    
		    # Dereference the two-dimensional array.
		    foreach $recip (sort keys(%{ $delivery{$domain} })) {
			if($recip ne 'TOP') {
			    printf("        %-27s %5d\n", $recip, $delivery{$domain}->{$recip});
			}
		    }
		    
		    print "\n";
		}
	    }
	}
    }
