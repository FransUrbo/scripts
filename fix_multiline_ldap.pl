#!/usr/bin/perl -w

use MIME::Base64;

# Load the whole LDIF
$count = 0;
while(! eof(STDIN)) {
    $line = <STDIN>; chomp($line);
    next if(($line =~ /^\#/) && ($line !~ /refldap:\/\//));

    push(@FILE, $line);
    $count++;
}

# --------------------------------------------------

# Go through the LDIF, modify it according to the new
# OpenLDAP v2.2.x standards (with ACI's etc).
$first = 0;
for($i=0; $i < $count; $i++) {
    if($FILE[$i]) {
	# Catch multi lines (regenerate a NEW line).
	# --------------------------------------
	if($FILE[$i+1] =~ /^ /) {
	    $line = $FILE[$i];
	    while($FILE[$i+1] =~ /^ /) {
		$next  = $FILE[$i+1];
		$next =~ s/^\ //;
		$line .= $next;
		$i++;
	    }
	} else {
	    $line = $FILE[$i];
	}

	if($first) {
	    print "\n" if(($line =~ /^dn: /) || ($line =~ /^dn:: /));
	}

	if($line =~ /^dn:: /) {
	    $dn = (split('dn:: ', $line))[1];
	    print "# dn: ".decode_base64("$dn")."\n";
	}
	print "$line\n";
	$first = 1;
    }
}

