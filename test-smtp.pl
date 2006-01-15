#!/usr/bin/perl

# $Id: test-smtp.pl,v 1.7 2006-01-15 21:40:07 turbo Exp $

# Test for SMTP answer on $ARGV[0]

# Need package 'libnet-telnet-perl' for this!
use Net::Telnet;

# Do we have any arguments?
if( $ARGV[0] ) {
    # Ohh yes.... Process it...
    $HOST = $ARGV[0];
} else {
    print "Usage: `basename $0` <host>\n"
}

# Check to see if the SMTP port's open
my $obj = new Net::Telnet(Errmode => "return");
my $ok  = $obj->open(Host    => $HOST,
		     Port    => 25,
		     Timeout => 10);
if($ok) {
    $obj->close;
    $ok = 0;
} else {
    $ok = 1;
}

exit $ok;
