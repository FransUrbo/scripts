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

    $update = 1;
    $new_files_opened = 0;

    # Make sure the 'mini' directory exists...
    printf("Minidir: '$DIR.mini'\n") if( $DEBUG );
    if(! -e "\"$DIR.mini\"" ) {
	# Nope, create it...
	mkdir("$DIR.mini", 0755);
    }

    # Make sure the thumnail directory exists...
    if( -e "$DIR/.xvpics" ) {
	open(FIND, "cd \"$DIR\"; /usr/bin/find -name .xvpics \| /usr/bin/xargs /usr/bin/find |")
	    || die "Could not find..., $!\n";

	if( open(NEWFILES, ">/tmp/view_new_files.sh") ) {
	    $new_files_opened = 1;
	    chmod( 0755, "/tmp/view_new_files.sh" );
	    printf(NEWFILES "#!/bin/sh\n\n");
	}

	print NEWFILES "\ncd \"$DIR\"\nxv ";

	while(! eof(FIND) ) {
	    $LINE = <FIND>;

	    if( $LINE ) {
		chomp($LINE);

		if( $LINE ) {
		    # Get the filename from the list...
		    ($dir, $file) = split(' ', &basename($LINE));

		    $dir =~ s/$DIR//;
		    $dir =~ s/^\///;
		    $dir =~ s@./@@;

		    # Remove the extension...
		    $FILE = $file;
		    ($file, $ext) = split('\.', $FILE);

		    next if(! $file);
		    next if(! $ext);

		    $ext = lc($ext);
		    if( $ext eq 'jpg' || $ext eq 'gif' ) {
			$check = "$DIR.mini/$dir/$file.$ext";

			# Does the thumbnail exists?
			printf("Checking file '$check'\n") if( $DEBUG );
			if(! -e "$check" ) {
			    printf("Creating:   $check\n");
			    print NEWFILES "\"$dir/$file.$ext\" ";

			    # Create the shell script...
			    open(TEMP_FILE, ">/tmp/file.sh");
			    print TEMP_FILE <<EOF;
#!/bin/sh

TMPFILE=`mktemp -q /tmp/thumnail.XXXXXX`

# Create a PPM file...
#cat \"$DIR/$dir/.xvpics/$FILE\" | xvpictoppm > \$TMPFILE.ppm
cat \"$DIR/$dir/.xvpics/$FILE\" | xvminitoppm > \$TMPFILE.ppm

mkdir -p \"$DIR.mini/$dir\"

# Create a progressive JPEG file...
convert -interlace Plane \$TMPFILE.ppm \"$check\"

# Clean up..
rm -f \$TMPFILE.ppm \$TMPFILE
EOF
    ;
			    close(TEMP_FILE);
			
			    # Make the shell script executable...
			    chmod( 0755, "/tmp/file.sh" );

			    # Convert the file...
			    system("/tmp/file.sh");

			    # Remove the shell script...
			    unlink("/tmp/file.sh") if( !$DEBUG );
			} else {
			    # Does the thumbnail exists, but not the original?
			    printf("Checking file '$DIR/$dir/$file.$ext'\n") if( $DEBUG );
			    if(! -e "$DIR/$dir/$file.$ext" ) {
				print STDERR "Thumbnail $check exists,\n  but not original ($DIR/$dir/$file.$ext).\n\n";
				system("rm -i \"$check\"");
			    } else {
				printf("File $file.$ext exists...\n") if( $DEBUG );
			    }
			}
		    } elsif( $ext eq 'avi' || $ext eq 'mov' || $ext eq 'mpg' || $ext eq 'viv' || $ext eq 'qt' || $ext eq 'rm' ) {
			$check = "$DIR.mini/$dir/$file.$ext";

			if(! -e $check ) {
			    # Movies, default icon...
			    printf("File:   $check\n") if( $DEBUG );
			    system("mkdir -p \"$DIR.mini/$dir\"");
			    system("cp ~/.movie.jpg $check");
			}
		    }
		}
	    }
	}
    } else {
	# Does not exists...
	&header();

    print <<EOF;
<PRE>
  <CENTER>
There are no thumnails in the directory $DIR
Please run the xv-visual schnauzer to create some...
  </CENTER>
</PRE>
</BODY>
</HTML>
EOF
    ;
    }
}

sub index {
    local($DIR) = @_;
    my($LINE, @TMP, %DIRS, $i, $top_dir, $dir);

    # Check to see if the directory exists...
    if( -e $DIR ) {
	print "Finding in dir: $DIR\n";

	# Open the directory...
	open(LIST, "/usr/bin/find $DIR -mindepth 1 -type d |") 
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
    my(@path, $dir, $i, $file);

#    print "LINE: $line\n";
    @path = split('/', $line);

    for( $i = 0; $path[$i+1]; $i++ ) {
	$dir .= $path[$i];

	if( $path[$i+1] ) {
	    $dir .= "/";
	}
    }
    $file = $path[$i];

    # Remove the '/.xvpics/' at the end...
    $dir =~ s/\/\.xvpics\/$// if($update);

    # We have path and a file name...
#    print "$dir : $file\n";

    return( "$dir $file" );
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


