#!/usr/bin/perl -w

# $Id: convert_openldap_db.pl,v 1.1 2003-12-18 14:09:34 turbo Exp $
# This script is the basis for converting a
# OpenLDAP 2.0 database (LDIF format on STDIN)
# to a OpenLDAP 2.1 database (LDIF format on STDOUT).

while(! eof(STDIN)) {
    $line = <STDIN>; chomp($line);

    next if($line =~ /^creatorsName/i);
    next if($line =~ /^createTimestamp/i);
    next if($line =~ /^modifiersName/i);
    next if($line =~ /^modifyTimestamp/i);

    next if($line =~ /^givenName/i);
    next if($line =~ /^clearTextPassword/i);

    next if($line =~ /^objectClass: inetOrgPerson/i);
    next if($line =~ /^objectClass: extraPosixAccount/i);
    next if($line =~ /^objectClass: organizationalPerson/i);

    next if($line =~ /^\#/);

    if($line =~ /dn: nsLIProfileName/i) {
	# None of this object should be added
	$true = 1;
	while($true) {
	    $line = <STDIN>; chomp($line);
	    if($line =~ /^$/) {
		$true = 0;
		undef($line);
	    }
	}
    } else {
    	print "$line\n";
    }
}
