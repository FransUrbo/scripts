#!/usr/bin/perl -w

#$DATE_CONVERTER="/usr/local/bin/tailocal";
$DATE_CONVERTER="/usr/bin/tai64nlocal";

sub get_msg_nr {
    my($line, $place) = @_;
    my($msgnr);

    # Get the msg number
    if($line =~ /^20[0-9][0-9]-.*/) {
	# Human readable
	$msgnr = (split(' ', $line))[$place+1];
    } else {
	# Unix std time
	$msgnr = (split(' ', $line))[$place];
    }
	
    $msgnr =~ s/:$//;
    return($msgnr);
}

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
	$emails=1 if(($arg eq '--emails') || ($arg eq '--all'));
	$quiet=1 if($arg eq '--quiet');

	if($arg eq '--help') {
	    print "Usage: `basename $0` [options]\n";
	    print "       --all                  Show information of each deliver (start, end, recipient etc)\n";
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

$i = $bounce = $remote = 0; %bounce = %remote = %delivery = ();
while(! eof(STDIN) ) {
    $line = <STDIN>; chomp($line);

    if($line =~ / starting delivery .*:.* to local /) {
	$msgnr = &get_msg_nr($line, 3);
	next if(!$msgnr);

	# Get the time
	$begin{$msgnr} = &get_time($line);

	# Get recipient
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
	#	phpqladmin-index.123_456
	#	phpqladmin-unsubscribe-kaarnale-phpqladmin=majorus.fi
	# (ezmlm mailinglist moderation request etc)
	if(($recip =~ /.*-accept-.*/) || ($recip =~ /.*-[us]c\.[0-9].*=/) ||
	   ($recip =~ /.*-request\@.*/) || ($recip =~ /.*-subscribe.*/) ||
	   ($recip =~ /.*-faq\@.*/) || ($recip =~ /.*-help.*\@.*/) || 
	   ($recip =~ /.*-return.*\@.*/) || ($recip =~ /.*-info\@.*/) ||
	   ($recip =~ /.*-index.*/) | ($recip =~ /.*-unsubscribe-.*/))
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
	    ($time1, $time2) = split(' ', $line);
	    $time2 = (split('\.', $time2))[0];
	    $first = "$time1 $time2";
	}

	$deliveries{'LOCAL'}++;
    } elsif($line =~ / starting delivery .*:.* to remote /) {
	$msgnr = &get_msg_nr($line, 3);
	next if(!$msgnr);

	$deliveries{'REMOTE'}++;
#    } elsif($line =~ / info msg .*: bytes .* from .* qp .* uid .*/) {
#	if($line =~ /^20[0-9][0-9]-.*/) {
#	    # Human readable
#	    $from =  (split(' ', $line))[8];
#	} else {
#	    # Unix std time
#	    $from =  (split(' ', $line))[7];
#	}
#	$from =~ s/\<//;
#	$from =~ s/\>//;
#
#	$from_domain = (split('\@', $from))[1];
    } elsif($line =~ / delivery .*: success: /) {
	$msgnr = &get_msg_nr($line, 2);
	next if(!$msgnr);

	# Get the time
	$end{$msgnr} = &get_time($line);
    } elsif($line =~ / delivery .*: failure: /) {
	# Failed delivery
	$deliveries{'FAILED'}++;
    } elsif($line =~ / delivery .*: deferral: /) {
	# Failed remote delivery
	$deliveries{'FAILED'}++;
    }

    $i++;
}
exit(0) if(!$msgnr); # We have no statistics - exit

LOOP:
    # Remember the last entry
    ($time1, $time2) = split(' ', $line);
    $time2 = (split('\.', $time2))[0];
    $last  = "$time1 $time2";

    $high = $avg = 0;
    foreach $nr (sort { $begin{$a} <=> $begin{$b} } keys(%begin)) {
	# Get start and end time of delivery
	if($begin{$nr} =~ /\./) {
	    $time1 = `echo $begin{$nr} | $DATE_CONVERTER`;
	    chomp($time1);
	}

	if($end{$nr}) {
	    if($end{$nr} =~ /\./) {
		$time2 = `echo $end{$nr}   | $DATE_CONVERTER`;
	    }
	    chomp($time2);
	}
	
	# How long did the delivery take?
	$time3 = $end{$nr} - $begin{$nr} if($end{$nr});

	# Calculate some statistics
	if($time3) {
	    $high  = $time3 if($time3 > $high);
	    $avg   = $avg + $time3;
	
	    printf("%5d: $time1 - $time2 (%3d sec) -> $dest{$nr}\n",
		   $nr, $time3) if($allstats && !$quiet);
	} else {
	    # We have not been able to figure out when the message
	    # was delivered successfully.
	    printf("%5d: $time1 - ???????? (%3s sec) -> $dest{$nr}\n",
		   $nr, "?") if($allstats && !$quiet);
	}
    }

    # Output the statistics
    if(!$quiet && !$DOMAIN) {
	print "\n" if($allstats);
	print "Status between '$first' and '$last'.\n";
	printf("Highest time of delivery:                         %5d\n", $high);
	printf("Average delivery time:                            %5d\n", $avg/($deliveries{'LOCAL'}+$deliveries{'REMOTE'}));
	print "\n";

	printf("Number of (successfull) deliveries:\n");
	printf("  %-47s %5d\n", 'Local:', $deliveries{'LOCAL'});
	printf("  %-47s %5d\n", 'Remote:', $deliveries{'REMOTE'});
	printf("  %-47s %5d\n", 'Bounces or failed deliveries:', $deliveries{'FAILED'});
	print "\n";
    }

    if($emails) {
	if($DOMAIN) {
	    if($quiet) {
		# in out bounce
		print "$delivery{$DOMAIN}->{'TOP'} $deliveries{'REMOTE'} $deliveries{'FAILED'}";
	    } else {
		printf("Domain: %-27s               %5d\n", $DOMAIN, $delivery{$DOMAIN}->{'TOP'});
		
		# Dereference the two-dimensional array.
		foreach $recip (sort keys(%{ $delivery{$DOMAIN} })) {
		    if($recip ne 'TOP') {
			printf("        %-27s               %5d\n", $recip, $delivery{$DOMAIN}->{$recip});
		    }
		}
		
		print "\n";
	    }
	} else {
	    if(!$quiet) {
		foreach $domain (sort keys(%delivery)) {
		    printf("Domain: %-27s               %5d\n", $domain, $delivery{$domain}->{'TOP'});
		    
		    # Dereference the two-dimensional array.
		    foreach $recip (sort keys(%{ $delivery{$domain} })) {
			if($recip ne 'TOP') {
			    printf("        %-27s               %5d\n", $recip, $delivery{$domain}->{$recip});
			}
		    }
		    
		    print "\n";
		}
	    }
	}
    }
