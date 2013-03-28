#!/usr/bin/perl -w

$ZFS_SHARE = "share/Movies";
$ZFS_SHARE_ADDITIONAL = "share/TV_Series";
$TV_SERIES_MATCH = 'TV_Series';

# --------------------------------------------
# 0: file	/share/Movies/Action/Lord Of The Rings/Lord Of The Rings 1 - Fellowship of The Ring - CD1.avi
# 1: name	Lord Of The Rings 1 - Fellowship of The Ring
# 2: title	Lord Of The Rings 1 - Fellowship of The Ring
# 3: url	http://www.imdb.com/title/tt0120737/
# 4: year	2001
# 5: genres	Action, Adventure, Fantasy
# 6: casts	Elijah Wood, Ian McKellen, Orlando Bloom
# 7: directors	Peter Jackson
# 8: plot	An innocent hobbit of The Shire journeys with eight companions to the<br>fires of Mount Doom to destroy the One Ring and the dark lord Sauron<br>forever.<br>

%CASTS = (); %GENRES = (); %YEARS = (); %DIRECTORS = ();

# ------------------------------------------
sub get_size() {
    my $dir = shift;
    my $format;

    my $origsize=`du -sh "$dir/"`;
    chomp($origsize);

    my $size =  $origsize;
    $size =~ s/	.*//;

    $size =~ s/,/\./;
    if($size =~ /K$/) {
	$size =~ s/K$//;
	$format = 'K';
    } elsif($size =~ /M$/) {
	$size =~ s/M$//;
	$format = 'M';
    } elsif($size =~ /G$/) {
	$size =~ s/G$//;
	$format = 'G';
    } elsif($size =~ /T$/) {
	$size =~ s/T$//;
	$format = 'T';
    } else {
	$format = ' ';
    }

    $size = $size.$format;

    # ----

    if(-e "$dir/.complete") {
	$complete = "*";
    } elsif(-e "$dir/.verified") {
	$complete = "+";
    } else {
	$complete = " ";
    }

    return(($size, $complete));
}

# --------------------------------------------
sub update_list() {
    my($string) = @_;
    my($line);

    my $name_out = (split(';', $string))[1];

    open(LIST, "> .mkmovielist.list.new")
	|| die("Can't create new/temp list of movies, $!\n");

    for my $line (sort keys %MOVIES) {
	my $name_in = (split(';', $line))[1];

	if($name_in eq $name_out) {
	    # Print new line
	    print LIST "$string\n";
	} else {
	    print LIST "$line\n";
	}
    }

    close(LIST);
}

# --------------------------------------------
sub translate_string() {
    my($string) = @_;

    $string =~ s/&#27;//i;
    $string =~ s/&#x27//i;

    $string =~ s/&#39;/\'/i;
    $string =~ s/&#x39/\'/i;

    $string =~ s/\&eacute;/e/i;
    $string =~ s/\&aacute;/a/i;
    $string =~ s/\&iacute;/i/i;
    $string =~ s/\&oacute;/o/i;
    $string =~ s/\&ntilde;/n/i;
    $string =~ s/\&nbsp;/ /i;
    $string =~ s/\&raquo;/r/i;
    $string =~ s/\&ouml;/o/i;
    $string =~ s/\&euml;/e/i;
    $string =~ s/\&auml;/a/i;
    $string =~ s/\&uuml;/u/i;
    $string =~ s/\&aring;/a/i;
    $string =~ s/\&oring;/o/i;
    $string =~ s/\&oslash;/?/i;

    $string =~ s/([^\x20-\x7E])/sprintf("&#x%X;", ord($1))/eg;

#    my $fixed = "";
#    my @chars = split //, $string;
#    foreach my $char (@chars) {
#	if (ord($char) > 0x7f) {
#            # This is where we handle all non 7-bit ascii
#            $fixed .= sprintf "&#%02x;", ord($char);
#        } else {
#            $fixed .= $char;
#        }
#    }
#    $string = $fixed if($fixed);

    return($string);
}

# --------------------------------------------
sub imdb_lookup() {
    my($title, $cnt) = @_;
    my($line, $imdb_title, $data, $year, $genres, $casts, $directors, $plot, $url);

    $cnt = 0 if(!$cnt);
    return '' if($cnt >= 2);

    print "lookup {$title} ";

    open(IMDB, "/usr/local/bin/imdb-mf -t \"$title\" |")
	|| die("Can't fetch from IMDB, $!\n");
    while(! eof(IMDB)) {
	$line = <IMDB>;
	chomp($line);

	$data =  $line;
	$data =~ s/.* ://;
	$data =~ s/^ //;
	$data = &translate_string($data);

	if($line =~ /^Title .*:/) {
	    $imdb_title = $data;
	    $imdb_title =~ s/([a-z]): /$1 - /;
	} elsif($line =~ /^Year .*:/) {
	    if($title =~ /^[0-9][0-9][0-9][0-9] /) {
		# Special case - bug in imdb-mf: Actual year is on next line
		$line = <IMDB>;
		chomp($line);

		$data = $line;
	    }
	    $year = $data;

	    $YEARS{$year} = $year;
	} elsif($line =~ /^Cast .*:/) {
	    $data =~ s/ and /, /;
	    $data =~ s/ $//;

	    $casts = $data;

	    @casts = split(', ', $casts);
	    for my $cast (@casts) {
		$CASTS{$cast} = $cast;
	    }
	} elsif($line =~ /^Genres .*:/) {
	    $data =~ s/ and /, /;
	    $data =~ s/ $//;

	    $genres = $data;

	    @genres = split(', ', $genres);
	    for my $genre (@genres) {
		$GENRES{$genre} = $genre;
	    }
	} elsif($line =~ /^Director .*:/) {
	    $data =~ s/ and /, /;
	    $data =~ s/   .*//;
	    $data =~ s/ $//;

	    $directors = $data;

	    @directors = split(', ', $directors);
	    for my $director (@directors) {
		$DIRECTORS{$director} = $director;
	    }
	} elsif($line =~ /^Plot .*:/) {
	    $line = <IMDB>;

	    $data = '';
	    while(($line = <IMDB>) !~ /^$/) {
		chomp($line);

		$data .= $line; #."<br>";
	    }

	    $plot = $data;
	} elsif($line =~ /^IMDB movie URL/) {
	    $url =  $data;
	    last;
	}
    }
    close(IMDB);

    if($url !~ /^http:/) {
	# Try again, with slightly modified title...
	$title =~ s/.*\ -\ //;
	($imdb_title, $year, $genres, $casts, $directors, $url, $plot) = &imdb_lookup($title, $cnt+1);
    }

    # Just so we don't return NULL
    $url       = '' if(!$url);
    $year      = '' if(!$year);
    $genres    = '' if(!$genres);
    $casts     = '' if(!$casts);
    $directors = '' if(!$directors);
    $plot      = '' if(!$plot);

    $plot = "$imdb_title: $plot" if($imdb_title && $plot);

#    if($url) {
#	if($imdb_title =~ /$title/) {
	    return(($imdb_title, $year, $genres, $casts, $directors, $url, $plot));
#	} else {
#	    # Oups, wrong one!
#	    print "WRONG";
#	    return((0, 0, 0, 0, 0, 0, 0));
#	}
#    } else {
#	return((0, 0, 0, 0, 0, 0, 0));
#    }
}

# --------------------------------------------
# Overwrite ZFS_SHARE and ZFS_SHARE_ADDITIONAL
if($#ARGV >= 0) {
    $ZFS_SHARE = $ARGV[0];
    $ZFS_SHARE_ADDITIONAL = "";
}
$ZFS_SHARE_ADDITIONAL = $ARGV[0] if($#ARGV >= 1);

# --------------------------------------------
if(open(LIST, ".mkmovielist.list")) {
    while(! eof(LIST)) {
	my $line = <LIST>;
	chomp($line);
	
	my $name = (split(';', $line))[1];
	$MOVIES{"$name"} = $line;
    }
    close(LIST);
} else {
    %MOVIES = ();
}

# --------------------------------------------
$movie_nr = 1;

open(FS, "zfs list -H -r '$ZFS_SHARE' '$ZFS_SHARE_ADDITIONAL' -o mountpoint 2> /dev/null | sort |")
    || die("Can't open ZFS shares list, $!\n");
while(! eof(FS)) {
    my $fs = <FS>;
    chomp($fs);

    if($fs =~ /$TV_SERIES_MATCH/) {
	$type = 'd';
	$wild = '/*';
    } else {
	$type = 'f';
	$wild = '';
    }

    open(FIND, "find \"$fs\"$wild -maxdepth 1 -type $type | ")
	|| die("Can't run find, $!\n");
    while(! eof(FIND)) {
	my $file = <FIND>;
	chomp($file);

	# Remove crap we're not interested in anyway.
	next if(($file =~ /\.zfs$/i) ||
		($file =~ /\.srt$/i) ||
		($file =~ /\.idx$/i) ||
		($file =~ /\.sub$/i) ||
		($file =~ /\.jpg$/i) ||
		($file =~ /\.txt$/i) ||
		($file =~ /\.rar$/i) ||
		($file =~ /\.log$/i) ||
		($file =~ /\.sfv$/i) ||
		($file =~ /\.mp4$/i) ||
		($file =~ /\.ifo$/i) ||
		($file =~ /\.mss$/i) ||
		($file =~ /\.bup$/i) ||
		($file =~ /\.mpg$/i) ||

		($file =~ / - [2-9]\./) ||
		($file =~ / - CD[2-9]\./) ||
		($file =~ /lrc-natm\.r5/) ||
		($file =~ /Store/) ||
		($file =~ /cnid2/) ||
		($file =~ /\/_.*/) ||
		($file =~ /Clips/i) ||
		($file =~ /\.Apple/) ||

		($file =~ /Commercials/) ||
		($file =~ /Parent/) ||
		($file =~ /volinfo/) ||
		($file =~ /Subtitles/) ||
		($file =~ /Extras/) ||
		($file =~ /Season /i) ||
		($file =~ /VTS/) ||
		($file =~ /Pixar Short Films Collection/) ||
		($file =~ /Spinoffs\//i) ||
		($file =~ /Making Of/i) ||
		($file =~ /Walt Disney\'s Fables/) ||
		($file =~ /Network Trash Folder/) ||
		($file =~ /Temporary Items/));

	# Catch container dirs
	if(-d "$file") {
	    $cnt = `find "$file" -maxdepth 1 -type f 2> /dev/null | wc -l`;
	    chomp($cnt);

	    next if(!$cnt);
	}

	# --------------------------------------------
	my $name = $file;
	$name =~ s/.*\///;
	$name =~ s/ - 1[xX][0-9][0-9]//;
	$name =~ s/ - [0-9]\./\./;
	$name =~ s/ - CD.*//;

	$name =~ s/\.avi//;
	$name =~ s/\.mpg//;
	$name =~ s/\.flv//;
	$name =~ s/\.mkv//;
	$name =~ s/\.iso/ (ISO)/;
	$name =~ s/\.img/ (ISO)/;
	$name =~ s/\.dmg/ (ISO)/;

	# --------------------------------------------
	my $title = $name;
	$title =~ s/ \(Cam\)//i;
	$title =~ s/ \(ISO\)//i;
	$title =~ s/ \(TS\)//i;
	$title =~ s/ \(R[0-9]\)//i;
	$title =~ s/ \(SweSub\)//i;
	$title =~ s/ \(Scr\)//i;
	$title =~ s/ \(DVDScr\)//i;
	$title =~ s/ \(DVDRip\)//i;
	$title =~ s/ \(MultiSubs\)//i;
	$title =~ s/ \(PAL\)//i;
	$title =~ s/ \(Bonus Disc\)//i;
	$title =~ s/ \(Extended\)//i;
	$title =~ s/ \(SvensktTal\)//i;
	$title =~ s/ \(MultiSubs-PAL\)//i;
	$title =~ s/ \(Unrated\)//i;

	$title =~ s/Disney\'s //;
	$title =~ s/ ([12][90][0-9][0-9])/ \($1\)/;
	$title =~ s/\ -$//;

	printf("%4d: $file -> $name: ", $movie_nr);

	my($DO_IMDB, $DO_SIZE, $UPDATE_LIST) = (1, 1, 0);
	if($MOVIES{"$name"}) {
	    ($dummy, $dummy, $dummy, $url, $year, $genres, $casts, $directors, $plot) =
		split(';', $MOVIES{"$name"});

	    # Re-read from IMDB. Might be missing something (added value in file/script?)
	    if(!$url) {
		# We're missing a value - force a new IMDB search for this title.
		# NOTE: We really only care about the URL!
		$DO_IMDB = 1;

#		$UPDATE_LIST = 1;
#		undef($MOVIES{"$name"});
	    } else {
		# We have what we need - no point in doing a IMDB search.
		$DO_IMDB = 0;
	    }
	}

	if($DO_IMDB) {
	    ($dummy, $year, $genres, $casts, $directors, $url, $plot) = &imdb_lookup($title);

	    $genres = "TV Series, $genres"
		if($genres &&
		   ($file =~ /$TV_SERIES_MATCH/) &&
		   ($genres !~ /^TV Series/));

	    if($url) {
		if(!$MOVIES{"$name"}) {
		    if($UPDATE_LIST) {
			print "FOUND:UPDATE";

			&update_list("$file;$name;$title;$url;$year;$genres;$casts;$directors;$plot");
		    } else {
			print "FOUND:NEW";

			open(LIST, ">> .mkmovielist.list")
			    || die("Can't append to existing list of movies, $!\n");
			print LIST "$file;$name;$title;$url;$year;$genres;$casts;$directors;$plot\n";
			close(LIST);
		    }
		} else {
		    print "FOUND:MISSING";
		}
	    }
	} else {
	    print "EXISTING";

	    $genres = "TV Series, $genres"
		if($genres &&
		   ($file =~ /$TV_SERIES_MATCH/) &&
		   ($genres !~ /^TV Series/));
	}

	$ENTRIES{"$name"} = "$file;$name;$title;$url;$year;$genres;$casts;$directors;$plot";

	if($DO_SIZE && -d "$file") {
	    my ($size, $complete) = &get_size($file);

	    my $dir = $file;
	    $dir =~ s/\/$ZFS_SHARE\///;
	    $dir =~ s/\/$ZFS_SHARE_ADDITIONAL\///;

	    $SIZE{$dir} = "$size:$complete";

	    if($complete eq '*') {
		push(@CHECKED, $dir);
	    } elsif($complete eq '+') {
		push(@VERIFIED, $dir);
	    } else {
		push(@REST, $dir);
	    }
	}

	if($url) {
	    $ENTRIES{"$name"} .= ";$url";
	} else {
	    print "NOT FOUND";
	}

	print "\n";

	$movie_nr++;
    }
    close(FIND);
}
close(FS);

# --------------------------------------------
open(HTML, "> /$ZFS_SHARE.html")
    || die("Can't open output html file '/$ZFS_SHARE.html', $!\n");

open(TEXT, "> /$ZFS_SHARE.txt")
    || die("Can't open output text file '/$ZFS_SHARE.txt', $!\n");

open(RSS, "> /$ZFS_SHARE.xml")
    || die("Can't open output RSS file '/$ZFS_SHARE.xml', $!\n");

open(SIZE, "> /$ZFS_SHARE.sizes")
    || die("Can't open output size file '/$ZFS_SHARE.sizes', $!\n");

$ENV{'LANG'} = "C";
$cur_date = `date`;
chomp($cur_date);

# ----- HTML header
print HTML "<html>
  <head>
    <title>The Movie Data Base</title>
    <style type=\"text/css\">
      tr.c1, td.c1  { background: #e7e7e7; }
      tr.c2, td.c2  { background: #ffffff; }
    </style>
  </head>

  <body>
    <h1>Number of entries: ".keys(%ENTRIES)."</h1>
    <font size=\"2\">Last updated: <i>$cur_date</i></font>
    <table border=\"1\">
      <tr>
        <th align=\"left\"><u><font size=\"5\" color=\"red\">Title/URL</font></u></th>
        <th align=\"center\"><u><font size=\"5\" color=\"red\">Year</font></u></th>
        <th align=\"left\"><u><font size=\"5\" color=\"red\">Genre(s)</font></u></th>
        <th align=\"left\"><u><font size=\"5\" color=\"red\">Cast(s)</font></u></th>
        <!-- <th align=\"left\"><u><font size=\"5\" color=\"red\">Director(s)</font></u></th> -->
      </tr>
";

# ----- RSS header
print RSS "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<rss version=\"2.0\" xmlns:atom=\"http://www.w3.org/2005/Atom\">
  <channel>
    <title>TV/Movie List</title>
    <link>http://www.bayour.com/misc/Movies.xml</link>
    <atom:link href=\"http://bayour.com/misc/Movies.xml\" rel=\"self\" type=\"application/rss+xml\" />
    <description>Movies and TV Series</description>
    <language>en-us</language>
    <docs>http://blogs.law.harvard.edu/tech/rss</docs>
    <generator>Emacs and Scripting by Turbo</generator>
";

my $cnt = 1;
my %URLS;

$class = "c1";

for my $entry (sort keys %ENTRIES) {
    my($file, $name, $title, $url, $year, $genres, $casts, $directors, $plot) =
	split(';', $ENTRIES{"$entry"});

    $name  =~ s/^The (.*)/$1, The/;
    $name  =~ s/ \& / and /g;
    $name  =  &translate_string($name);

    $name  =~ s/&#xC3;&#x96;/ö/;
    $name  =~ s/&#xC3;&#xB6;/ö/;
    $name  =~ s/&#xCC;&#x88;/ä/;

    $casts =~ s/ \| See full cast and crew//i;

    $plot  =~ s/([^\x20-\x7E])/sprintf("&#x%X;", ord($1))/eg;
    $plot  =~ s/&#x27//g;
    $plot  =~ s/\"/\'/g;
    $plot  =~ s/\<br\>/ /g;
    $plot  =~ s/ \& / and /g;
    $plot  =~ s/ See full synopsis.*//;

    $url_plot  = "$file&#10;&#13;".$plot;

    # ----- TEXT entry
    print TEXT "$name\n";

    # ----- HTML entry
    print HTML "\n      <tr align=\"left\" class=\"$class\">\n";
    if($url) {
	print HTML "        <th width=\"40%\"><a href=\"$url\" title=\"$url_plot\">$name</a></th>\n";
    } else {
	print HTML "        <th width=\"40%\">$name</th>\n";
    }
    print HTML "        <th width=\"100\"><center>$year</center></th>\n";
    print HTML "        <th>$genres</th>\n";
    print HTML "        <th>$casts</th>\n";
    print HTML "        <!-- <th>$directors</th> -->\n";
    print HTML "      </tr>\n";

    if($class eq "c1") {
	$class = "c2";
    } else {
	$class = "c1";
    }

    # ----- RSS entry
    print RSS "\n    <item>\n";
    if($genres =~ /^TV Series/) {
	print RSS "      <title>Serie: $name</title>\n";
    } else {
	print RSS "      <title>Movie: $name</title>\n";
    }
    print RSS "      <description>$plot</description>\n";
    if($url) {
	print RSS "      <link>$url</link>\n";

	if($URLS{$url}) {
	    print RSS "      <guid>$url#$cnt</guid>\n";
	    $cnt++;
	} else {
	    print RSS "      <guid>$url</guid>\n";
	    $URLS{$url} = 1;
	}
    } else {
	print RSS "      <guid isPermaLink=\"false\">none #$cnt</guid>\n";
	    $cnt++;
    }
    print RSS "    </item>\n";
}

# ----- HTML tail
print HTML "    </table>
  </body>
</html>
";

# ----- RSS tail
print RSS "  </channel>
</rss>
";

close(HTML);
close(RSS);

# ----- SIZE
foreach $dir (sort keys %SIZE) {
    ($size, $complete) = split(':', $SIZE{$dir});
    $complete = " " if(!$complete);

    printf(SIZE "%s %7s	%s\n", $complete, $size, $dir);
}

printf(SIZE "\n");
printf(SIZE "* => Complete series (%d series, %d including verified).\n", $#CHECKED, $#CHECKED + $#VERIFIED);
printf(SIZE "+ => Complete, checked and verified series (%d series).\n", $#VERIFIED);
printf(SIZE "     Total number of TV series: %d\n\n", $#CHECKED + $#VERIFIED + $#REST);
printf(SIZE "List created %s\n", `date -R`);

close(SIZE);

