#!/usr/bin/perl -w

# $Id: change_openldap_db_layout.pl,v 1.1 2003-12-19 08:08:48 turbo Exp $
# This script is the basis of converting a
# OpenLDAP database in domain layout (dc=XXX
# as base etc) to a location based layout (c=XX
# as base and o=YYY as trees etc)

@ROOT   = ('dc=com'		=> 'c=SE');
@CHANGE = ('dc=sundqvist'	=> 'o=Familjen Sundqvist',
	   'dc=winas'		=> 'o=Familjen Winas',
	   'dc=intelligence-5'	=> 'o=Jonathan Buhay',
	   'dc=gamestudio'	=> 'o=The GameStudio',
	   'dc=fredriksson'	=> 'o=Familjen Fredriksson',
	   'dc=agby'		=> 'o=Familjen Agby',
	   'dc=bortheiry'	=> 'o=Data-Akut',
	   'dc=sahlen'		=> 'o=Familjen Sahlen',
	   'dc=vger'		=> 'o=Jerry Lundstrom',
	   'dc=henriksson'	=> 'o=Familjen Henriksson',
	   'dc=bayour'		=> 'o=Misc Users');

$count = 0;
while(! eof(STDIN)) {
    $tmp = <STDIN>; chomp($tmp);

    if($tmp =~ /^ /) {
	$tmp =~ s/^ //;
	$line[$count-1] .= $tmp;
	$count--;
    } else {
	$line[$count] = $tmp;
    }

    $count++;
}

for($j = 0; $j < $count; $j++) {
    $tmp = $line[$j];

    if($tmp =~ /^dn: /) {
	$dn = $tmp;
    }

    # Do the replacements
    $tmp =~ s/$ROOT[0]$/$ROOT[1]/;
    for($i=0; $CHANGE[$i];) {
	$tmp =~ s/$CHANGE[$i],$ROOT[1]$/$CHANGE[$i+1],$ROOT[1]/;
	
	# ----------------- Replace the 'dc' attribute with the 'o' ditto
	# dn: dc=sundqvist,dc=com
	# dc: sundqvist
	# ->
	# dn: o=Familjen Sundqvist,c=SE
	# o: Familjen Sundqvist
	$dc_old = (split('=', $CHANGE[$i]))[1];
	$dc_new = (split('=', $CHANGE[$i+1]))[1];
	if(($tmp =~ /^dc: $dc_old$/) && ($dn =~ /^dn: $CHANGE[$i],$ROOT[0]$/i)) {
	    $tmp = "O: $dc_new";
	}

	# ----------------- Replace the domain objectClass for organization
	# dn: dc=sundqvist,dc=com
	# objectClass: domain
	# ->
	# dn: o=Familjen Sundqvist,c=SE
	# objectClass: organization
	if(($tmp =~ /^objectClass: domain/i) && ($dn =~ /^dn: $CHANGE[$i],$ROOT[0]$/i)) {
	    $tmp = "objectClass: organization";
	}

	$i = $i+2;
    }


    # ----------------- Fix the root DN. It isn't catched above
    if(($dn =~ /^dn: $ROOT[0]$/) && ($tmp =~ /^dc: /i)) {
	# 'dc: com' -> 'c: SE'
	
	$c = (split('=', $ROOT[1]))[1];
	print "c: $c\n";
    } elsif(($dn =~ /^dn: $ROOT[0]$/) && ($tmp =~ /^objectClass: domain/i)) {
	# objectClass: domain
	print "objectClass: country\n";
    } else {
	print "$tmp\n";
    }
}
