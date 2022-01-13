#!/usr/bin/perl -w

# Perl script by 'Turbo Fredriksson' <turbo@tripnet.se>
# Use at your own risk...

# Make sure we flush the buffers...
use FileHandle;
STDOUT->autoflush(1);

$DEBUG = 0;

# Do we have any arguments?
if( $ARGV[0] ) {
    # Ohh yes.... Process it...

    foreach $arg (@ARGV) {
	if( $arg eq '--help' || $arg eq '-h' || $arg eq '?' ) {
	    &help();
	} elsif( $arg eq '--index' || $arg eq '-i' ) {
	    exit 1 if(! $ARGV[1] );
	    $DIR = $ARGV[1];

	    &index($DIR);
	    exit 0;
	} elsif( $arg eq '--debug' || $arg eq '-d' ) {
	    $DEBUG = 1;
	} elsif( $arg =~ /^\// ) {
	    $DIR = $ARGV[0];

	    &main($DIR);
	    exit 0;
	} else {
	    &help()
	}
    }
} else {
    &help();
}

sub main {
    local($DIR) = @_;

    # Make sure the 'mini' directory exists...
    printf("Minidir: '$DIR.mini'\n") if( $DEBUG );
    if(! -e "\"$DIR.mini\"" ) {
	# Nope, create it...
	mkdir("$DIR.mini", 0755);
    }

    open(LIST, "find '$DIR' -maxdepth 1 -type f \| sort |");
    while(! eof(LIST) ) {
	$path = <LIST>;
	chomp($path);

	($dir, $file) = &basename($path);

	printf "Creating thumbnail '$DIR.mini/$file': ";
	&convert("$dir/$file", "$DIR.mini/$file");
	printf "done.\n";
    }
}

sub convert {
    local($source, $dest) = @_;

    # Convert the file...
    system("convert -auto-orient -thumbnail 200x200 '$source' '$dest'");
}

sub index {
    local($DIR) = @_;
    my($LINE, @TMP, %DIRS, $i, $top_dir, $dir);

    # Check to see if the directory exists...
    if( -e $DIR ) {
	print "Finding in dir: $DIR\n";

	# Open the directory...
	open(LIST, "/usr/bin/find '$DIR' -mindepth 1 -type d |") 
	    || die "Could not find, $!\n";
	while(! eof(LIST) ) {
	    $LINE = <LIST>;
	    chomp($LINE);

	    next if( $LINE =~ /xvpics/ );

	    push(@TMP, $LINE);
	}
	close(LIST);
    }

    # Prepare a sort of the list...
    for($i = 0; $TMP[$i]; $i++ ) {
	$DIRS{$TMP[$i]} = $TMP[$i];
    }
    undef @TMP;
    undef $i;

    $top_dir = $DIR;

    # ------------------------------------------------------

    # Create the left side frame...
    printf("Creating LEFT frame... ");
    open(LEFT, "> $DIR/left.html" )
	|| die "Could not open $DIR/left.html, $!\n";
    foreach $dir (sort(keys %DIRS)) {
	$dir =~ s/\.mini//g;
	$dir =~ s/$top_dir\///g;

	print LEFT <<EOF;
<LI><A HREF="/cgi-bin/list-pics_2.pl?$top_dir?$dir"
onMouseOver="window.status='$dir' ;return true"
onMouseOut="window.status='';return true"
TARGET=main>$dir</A></LI>
EOF
    ;
    }
    printf("done.\n");
}

sub basename {
    my($line) = @_;
    my(@path, @result, $dir, $i, $file);

#    print "LINE: $line\n";
    @path = split('/', $line);

    for($i = 0; $path[$i+1]; $i++) {
#	print "path[$i]: '$path[$i]'\n";
	$dir .= $path[$i];

	if( $path[$i+2] ) {
	    $dir .= "/";
	}
    }
#    print "path[$i]: '$path[$i]'\n";
    $file = $path[$i];

    # We have path and a file name...
#    print "$dir : $file\n";

    push @result, $dir;
    push @result, $file;

    return(@result);
}

sub header {
    print <<EOF;
Content-type: text/html

<HTML>
  <HEAD>
    <TITLE>Pics in $DIR</TITLE>
    <META NAME="Author" CONTENT="CGI-BIN by Turbo Fredriksson">
  </HEAD>
EOF
    ;
}

sub help {
    print "\nUsage: $0 <picdir>\n";
    print "   or: $0 --index To create the frames page.\n\n";
    print "   directory is the exact path to where the pictures reside.\n";
    exit 0;
}


