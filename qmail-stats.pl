#!/usr/bin/perl -w

# -------------------------------------------------------------------------------------------------------------------
# Successfull remote delivery:
# 1054189746.123136 new msg 161214
# 1054189746.123151 info msg 161214: bytes 830 from <turbo@bayour.com> qp 6190 uid 1000
# 1054189746.123958 starting delivery 119: msg 161214 to remote turbo@tripnet.se
# 1054189746.123980 status: local 0/10 remote 1/20
# 1054189746.373645 delivery 119: success: 195.100.21.7_accepted_message./Remote_host_said:_250_OK_id=19LGuQ-0003OJ-00/
# 1054189746.374171 status: local 0/10 remote 0/20
# 1054189746.374332 end msg 161214
# 
# Successfull local delivery:
# 1054189750.812151 new msg 161214
# 1054189750.812169 info msg 161214: bytes 1676 from <turbo@bayour.com> qp 6206 uid 64014
# 1054189750.812192 starting delivery 120: msg 161214 to local turbo@bayour.com
# 1054189750.812212 status: local 1/10 remote 0/20
# 1054189754.376563 delivery 120: success: did_0+0+1/
# 1054189754.377277 status: local 0/10 remote 0/20
# 1054189754.377470 end msg 161214
#
# Failed remote delivery 1:
# 1054194593.322882 new msg 161214
# 1054194593.322896 info msg 161214: bytes 869 from <turbo@bayour.com> qp 24150 uid 1000
# 1054194593.322921 starting delivery 183: msg 161214 to remote fjkdasljf@nocrew.org
# 1054194593.322944 status: local 0/10 remote 1/20
# 1054194596.057500 delivery 183: failure: 213.242.147.30_does_not_like_recipient./Remote_host_said:_550_Unknown_local_part_fjkdasljf_in_<fjkdasljf@nocrew.org>/Giving_up_on_213.242.147.30./
# 1054194596.058353 status: local 0/10 remote 0/20
# 1054194596.081499 bounce msg 161214 qp 24162
# 1054194596.081517 end msg 161214
#
# Failed local delivery:
# 1054189045.549445 new msg 161214
# 1054189045.549570 info msg 161214: bytes 7308 from <baby3@3333.3utilities.com> qp 976 uid 64014
# 1054189045.549657 starting delivery 108: msg 161214 to local 87smtjy4le.fsf@papadoc.bayour.com
# 1054189045.549681 status: local 1/10 remote 0/20
# 1054189046.239668 delivery 108: failure: Sorry,_no_mailbox_here_by_that_name._(#5.1.1)/
# 1054189046.240474 status: local 0/10 remote 0/20
# 1054189046.260176 bounce msg 161214 qp 981
# 1054189046.260452 end msg 161214
# -------------------------------------------------------------------------------------------------------------------

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
	    $first = `echo $begin{$msgnr} | /usr/local/bin/tailocal`;
	    chomp($first);
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
    $last = `echo $end{$msgnr} | /usr/local/bin/tailocal`;
    chomp($last);

    $high = $avg = 0;
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
