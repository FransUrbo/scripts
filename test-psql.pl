#!/usr/bin/perl

# $Id: test-psql.pl,v 1.1 2003-10-21 05:56:40 turbo Exp $

# Test for PostgreSQL daemon on papadoc
#
# => If 'no',  restart PostgreSQL

use Net::Telnet;

$psql_stop  = "/etc/init.d/postgresql stop";
$psql_start = "/etc/init.d/postgresql start";

# Check for running Postmaster
sub check_psql {
    my($ps);

    $ps = `/bin/ps axwww | grep postmaster | grep -v grep`;
    if($ps ne "") {
	return 1;
    } else {
	return 0;
    }
}

# -----------------------------------
if(! &check_psql()) {
    # No postmaster running
    
    print "PostgreSQL on papadoc is down - restarting.\n";
    system($psql_stop); system($psql_start);
}
