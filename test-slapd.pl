#!/usr/bin/perl

# $Id: test-slapd.pl,v 1.1 2003-10-20 19:38:23 turbo Exp $

# Test for LDAP daemon on %HOST%
#
# => If 'no',  restart daemon

use Net::Telnet;

$slapd_stop  = "/etc/init.d/slapd stop";
$slapd_start = "/etc/init.d/slapd start";

# Check for running daemon
sub check_slapd {
    my($ps);

    $ps = `/bin/ps axwww | egrep 'slapd.*:389/' | grep -v grep`;
    if($ps ne "") {
	return 1;
    } else {
	return 0;
    }
}

# -----------------------------------
if(! &check_slapd()) {
    # No LDAP server running
    
    print "LDAP server on on %HOST% is down - restarting.\n";
    system($slapd_stop); system($slapd_start);
}
