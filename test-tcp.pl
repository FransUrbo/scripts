#!/usr/bin/perl

# $Id: test-tcp.pl,v 1.1 2006-04-28 11:30:07 turbo Exp $

# Need package 'libnet-telnet-perl' for this!
use Net::Telnet;

# Do we have any arguments?
if($ARGV[0] && $ARGV[1] ) {
    # Ohh yes.... Process it...
    $HOST = $ARGV[0];
    $PORT = $ARGV[1];
} else {
    print "Usage: `basename $0` <host>\n"
}

# Check to see if the SMTP port's open
my $obj = new Net::Telnet(Errmode => "return");
my $ok  = $obj->open(Host    => $HOST,
		     Port    => $PORT,
		     Timeout => 10);
if($ok) {
    $obj->close;
    $ok = 0;
} else {
    $ok = 1;
}

exit $ok;
