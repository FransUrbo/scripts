#!/usr/bin/perl

# $Id: test-smtp.pl,v 1.3 2002-11-21 10:40:34 turbo Exp $

# Test for SMTP connection on papadoc
#
# => If 'yes', restart qmail ('full delivery mode')
# => If 'no',  restart qmail ('smtpd mode')

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

# Check for running qmail-rspawn
sub check_qmail {
    my($ps);

    $ps = `/bin/ps axwww | grep qmail-rspawn | grep -v grep`;
    if($ps ne "") {
	return 1;
    } else {
	return 0;
    }
}

# -----------------------------------
if(&check_smtp()) {
    # SMTP works
    print "SMTP on papadoc is up";
    
    if(! &check_qmail()) {
	# No qmail-rspawn running

	print " - Restarting qmail in DELIVERY mode.\n";
	system($qmail_stop); system($qmail_start);
    } else {
	print ".\n";
} else {
    # SMTP down
    print "SMTP on papadoc is down";
    
    if(&check_qmail()) {
	# qmail-rspawn running

	print "- Restarting qmail in SMTP mode.\n";
	system($qmail_stop); system($qmail_smtp);
    } else {
	print ".\n";
    }
}

