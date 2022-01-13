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
	    $prefix = "$arg - ";
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

open(LIST, "find . -maxdepth 1 -type f \| sort |");
while(! eof(LIST) ) {
    $path = <LIST>;
    chomp($path);
    @entry = split(/\//, $path);

    # Get filename...
    $file = $entry[length(@entry)];

    # Get the extension...
    @TMP = split('\.', $file);
    $len = scalar(@TMP);
    $EXT = $TMP[$len-1];
    $EXT = lc($EXT);

    $EXT = 'jpg' if($EXT =~ /jpeg/);

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
    print "         Moves all files to <destination>/[prefix] - [startno].extension\n\n";

    print "example: renumber.pl /tmp/files Pictures 001\n";
    print "         The first file will be called:  /tmp/files/Pictures - 001.extension\n";
    print "         The second file will be called: /tmp/files/Pictures - 002.extension\n";
    print "         etcetera...\n";
    exit( 0 );
}
