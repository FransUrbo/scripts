#!/usr/bin/perl

# $Id: test-smtp.pl,v 1.1 2002-11-21 10:26:38 turbo Exp $

# 1. Check for undelivered mails in /var/qmail/queue
# 2. Test for SMTP connection
#
# => If 'yes' on both, restart qmail     ('full delivery mode')
# => If 'no' on the first, restart qmail ('smtpd mode')

use Net::Telnet;

$qmail_stop  = "/etc/init.d/qmail stop";
$qmail_smtp  = "/etc/init.d/qmail smtpd";
$qmail_start = "/etc/init.d/qmail start";

# Check to see if the SMTP port's open
sub check_smtp {
    my($obj, $ok);

    $obj = new Net::Telnet(Errmode => "return");
    $ok  = $obj->open(Host    => "papadoc.bayour.com",
		      Port    => 25,
		      Timeout => 10);
    if($ok) {
	$ok = $obj->close;
    }

    return $ok;
}

# Check for mails in queue
sub check_queue {
    chdir("/var/qmail/queue/mess") || die "Can't change to queue dir, $!\n";
    $mails = `find -type f -name '[0-9]*' | wc -l | sed 's\@ \@\@g'`;
    chomp($mails);

    return $mails;
}

# Check for running qmail-rspawn
sub check_qmail {
    my($ps);

    $ps = `ps | grep qmail-rspawn | grep -v grep`;
    if($ps ne "") {
	return 1;
    } else {
	return 0;
    }
}

# -----------------------------------
if(&check_queue()) {
    # Mail's in queue
    if(&check_smtp()) {
	# SMTP works
	print "Got mail's ($mails) in queue, and smtp works.\n";

	if(&check_qmail()) {
	    # No qmail-rspawn running
	    print "Restarting qmail in DELIVERY mode.\n";
	    exec($qmail_stop); exec($qmail_start);
	}
    } else {
	# SMTP down
	print "Got mail's ($mails) in queue, but SMTP on papadoc is down!\n";

	if(! &check_qmail()) {
	    print "Restarting qmail in SMTP mode.\n";
	    exec($qmail_stop); exec($qmail_smtp);
	}
    }
} else {
    # No mail in queue
    if(! &check_qmail()) {
	print "Restarting qmail in SMTP mode ($mails mails).\n";
	exec($qmail_stop); exec($qmail_smtp);
    }
}

