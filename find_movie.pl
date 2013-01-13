#!/usr/bin/perl

#egrep -i "$*" /share/.Torrents/Unsorted/.list | sed 's@;.*@@'

for($i=0; $ARGV[$i]; $i++) {
    open(LIST, "/share/.Torrents/Unsorted/.list")
	|| die("Can't open list file, $!\n");
    while(! eof(LIST)) {
	$line = <LIST>;
	chomp($line);
	
	@opts = split(';', $line);
	    
	if($opts[1] =~ /$ARGV[$i]/i) {
	    $subj =  $opts[8];
	    $subj =~ s/.*: //;
	    $subj =~ s/\<br\>$//;
	    $subj =~ s/\<br\>/\n    /g;
	    
	    printf("%s\n  %s\n  %s\n\n", $opts[1], $opts[0], $subj);
	}
    }
    close(LIST);
}
