#!/usr/bin/perl -w

# $Id: extract_dbstats.pl,v 1.2 2004-10-15 09:11:53 turbo Exp $

$DB_DIR = "/var/lib/ldap";
$MEM    = 0;

open(FIND, "find $DB_DIR -type f -name '*.bdb' |")
    || die("Can't find, $!\n");
while(!eof(FIND)) {
    $file = <FIND>; chomp($file);
    print "File: $file\n";

    open(STAT, "db4.2_stat -h $DB_DIR -d $file |")
	|| die("Can't stat, $!\n");
    while(!eof(STAT)) {
	$line = <STAT>; chomp($line);

	if($line =~ /Underlying database page size/i) {
	    print "  $line\n";
	    $size = (split(' ', $line))[0];
	} elsif($line =~ /Number of tree internal pages/i) {
	    print "  $line\n";
	    $internal = (split(' ', $line))[0];
	} elsif($line =~ /Number of tree leaf pages/i) {
	    print "  $line\n";
	    $external = (split(' ', $line))[0];
	}
    }
    close(STAT);

    $cache_size = (($internal+1)*$size);
    $MEM = $MEM + $cache_size;
    
    print "  => (($internal+1)*$size) => $cache_size\n\n";
}
close(FIND);

print "Total memory cache you should use: $MEM bytes.\n";
