#!/usr/bin/perl -w

#print "$#ARGV\n";     #Number of arguments-1

$prefix = "";
$start  = "001";

# Do we have any arguments?
if( $#ARGV >= 0 ) {
    # Ohh yes.... Process it...

    foreach $arg (@ARGV) {
	if( $arg eq '--help' || $arg eq '-h' || $arg eq '?' ) {
	    &help();
	} elsif( $arg =~ /^[a-zA-Z]/ ) {
	    $prefix = "$arg\_";
	} elsif( $arg =~ /^[0-9]/ ) {
	    $start = $arg;
	} elsif( $arg =~ /^\// | $arg =~ /^\./ ) {
	    $DEST = $arg;
	}
    }
} else {
    &help();
}

exit(1) if(! $DEST);

# -------------------------

open(LIST, "find -type f -maxdepth 1 |");
while(! eof(LIST) ) {
    $file = <LIST>;
    chomp($file);
    @entry = split(/\//, $file);

    # Get the extension...
    $EXT = (split('\.', $entry[1]))[1];
    $EXT = lc($EXT);

    &find_free_number() if(! $found_free_number);

    next if( $file =~ /^$DEST\/$prefix/ );
    next if( $file =~ /www_not_browsable/ );

    $DESTINATION = "$DEST/$prefix$start.$EXT";

    &move_file($entry[1], $DESTINATION);

    $start++;
}
close(LIST);

sub move_file {
    local($source, $destination) = @_;

    printf( "Moving file: %-20s to %-5s\n",$source, $destination);
    system( '/bin/mv', "-i", "$source", $destination );
}

sub find_free_number {
    while( -f "$DEST/$prefix$start.$EXT" ) {
	$start++;
    }

    $found_free_number = 1;
}

# -------------------------

sub help {
    print "usage:   renumber.pl <destination> [prefix] [start_no]\n";
    print "         Moves all files to <destination>/[prefix]_[startno].extension\n\n";

    print "example: renumber.pl /tmp/files Pictures 001\n";
    print "         The first file will be called:  /tmp/files/Pictures_001(extension)\n";
    print "         The second file will be called: /tmp/files/Pictures_002(extension)\n";
    print "         etcetera...\n";
    exit( 0 );
}
