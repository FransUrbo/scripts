#!/usr/bin/perl -w

$ZFS_SHARE = "share/Movies";

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

    $string =~ s/\&eacute/e/i;
    $string =~ s/\&aacute/a/i;
    $string =~ s/\&iacute;/i/i;
    $string =~ s/\&oacute;/o/i;
    $string =~ s/\&ntilde;/n/i;
    $string =~ s/\&\#39;/\'/i;
    $string =~ s/\&nbsp;/ /i;
    $string =~ s/\&raquo;/r/i;
    $string =~ s/\&ouml;/o/i;
    $string =~ s/\&euml;/e/i;
    $string =~ s/\&auml;/a/i;
    $string =~ s/\&uuml;/u/i;
    $string =~ s/\&aring;/a/i;
    $string =~ s/\&oring;/o/i;
    $string =~ s/\&oslash;/?/i;

    return($string);
}

# --------------------------------------------
sub imdb_lookup() {
    my($title, $cnt) = @_;
    my($line, $data, $year, $genres, $casts, $directors, $plot, $url);

    $cnt = 0 if(!$cnt);
    return '' if($cnt >= 2);

    print STDERR "lookup {$title} ";

    open(IMDB, "/usr/local/bin/imdb-mf -t \"$title\" |")
	|| die("Can't fetch from IMDB, $!\n");
    while(! eof(IMDB)) {
	$line = <IMDB>;
	chomp($line);

	$data =  $line;
	$data =~ s/.* : //;
	$data = &translate_string($data);

	if($line =~ /^Year .*:/) {
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

		$data .= $line."<br>";
	    }

	    $plot = $data;
	} elsif($line =~ /^IMDB movie URL/) {
	    $url =  $data;
	}
    }
    close(IMDB);

    if($url !~ /^http:/) {
	$title =~ s/.*\ -\ //;
	($year, $genres, $casts, $directors, $url, $plot) = &imdb_lookup($title, $cnt+1);
    }

    $url       = '' if(!$url);
    $year      = '' if(!$year);
    $genres    = '' if(!$genres);
    $casts     = '' if(!$casts);
    $directors = '' if(!$directors);
    $plot      = '' if(!$plot);

    return(($year, $genres, $casts, $directors, $url, $plot));
}

# --------------------------------------------
if(open(LIST, ".mkmovielist.list")) {
    while(! eof(LIST)) {
	my $line = <LIST>;
	chomp($line);
	
	my $name = (split(';', $line))[1];
	$MOVIES{"$name"} = $line;
    }
    close(LIST);
#} else {
#    %MOVIES = {};
}

# --------------------------------------------
$movie_nr = 1;

open(FS, "zfs list -H -r \"$ZFS_SHARE\" -o mountpoint | sort | ")
    || die("Can't open ZFS shares list, $!\n");
while(! eof(FS)) {
    my $fs = <FS>;
    chomp($fs);

    open(FIND, "find \"$fs\" -maxdepth 1 -type f | ")
	|| die("Can't run find, $!\n");
    while(! eof(FIND)) {
	my $file = <FIND>;
	chomp($file);

	# --------------------------------------------
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
		($file =~ /__db/) ||
		($file =~ /Parent/) ||
		($file =~ /volinfo/) ||
		($file =~ /VTS/) ||
		($file =~ /Pixar Short Films Collection/) ||
		($file =~ /Walt Disney\'s Fables/));

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
	$title =~ s/ \(.*\)//;
	$title =~ s/Disney\'s //;
	$title =~ s/ [12][90][0-9][0-9]//;
	$title =~ s/\ -$//;

	printf(STDERR "%4d: $file -> $name: ", $movie_nr);

	my $DO_IMDB = 1; my $existing_url = ""; my $UPDATE_LIST = 0;
	if($MOVIES{"$name"}) {
	    ($dummy, $dummy, $dummy, $url, $year, $genres, $casts, $directors, $plot) =
		split(';', $MOVIES{"$name"});

	    $DO_IMDB = 0 if($url);

	    # Re-read from IMDB. Might be missing something (added value in file/script?)
	    if(!$year || !$genres || !$casts || !$directors || !$plot) {
		$DO_IMDB = 1;
#		$UPDATE_LIST = 1;
#		undef($MOVIES{"$name"});
	    }
	}

	if($DO_IMDB) {
	    ($year, $genres, $casts, $directors, $url, $plot) = &imdb_lookup($title);

	    if($url && !$MOVIES{"$name"}) {
		if($UPDATE_LIST) {
		    print STDERR "FOUND:UPDATE";
		    &update_list("$file;$name;$title;$url;$year;$genres;$casts;$directors;$plot");
		} else {
		    print STDERR "FOUND:NEW";

		    open(LIST, ">> .mkmovielist.list")
			|| die("Can't append to existing list of movies, $!\n");
		    print LIST "$file;$name;$title;$url;$year;$genres;$casts;$directors;$plot\n";
		    close(LIST);
		}
	    }
	} else {
	    print STDERR "EXISTING";
	}

	$year      = '' if(!$year);
	$genres    = '' if(!$genres);
	$casts     = '' if(!$casts);
	$directors = '' if(!$directors);
	$plot      = '' if(!$plot);

	$ENTRIES{"$name"} = "$file;$name;$title;$url;$year;$genres;$casts;$directors;$plot";

	if($url) {
	    $ENTRIES{"$name"} .= ";$url";
	} else {
	    print STDERR "NOT FOUND";
	}

	print STDERR "\n";

	$movie_nr++;
    }
    close(FIND);
}
close(FS);

# --------------------------------------------
open(HTML, "> /$ZFS_SHARE.html")
    || die("Can't open output html file, $!\n");

open(TEXT, "> /$ZFS_SHARE.txt")
    || die("Can't open output text file, $!\n");

print HTML "<html>
  <head>
    <title>The Movie Data Base</title>
    <style type=\"text/css\">
      tr.c1, td.c1  { background: #e7e7e7; }
      tr.c2, td.c2  { background: #ffffff; }
    </style>
  </head>

  <body>
    <table border=\"1\">
      <tr>
        <th align=\"left\"><u><font size=\"5\" color=\"red\">Title/URL</font></u></th>
        <th align=\"center\"><u><font size=\"5\" color=\"red\">Year</font></u></th>
        <th align=\"left\"><u><font size=\"5\" color=\"red\">Genre(s)</font></u></th>
        <th align=\"left\"><u><font size=\"5\" color=\"red\">Cast(s)</font></u></th>
        <!-- <th align=\"left\"><u><font size=\"5\" color=\"red\">Director(s)</font></u></th> -->
      </tr>
";

$class = "c1";
for my $entry (sort keys %ENTRIES) {
    my($file, $name, $title, $url, $year, $genres, $casts, $directors, $plot) =
	split(';', $ENTRIES{"$entry"});

    $name      =~ s/^The (.*)/$1, The/;
    $name      = &translate_string($name);

    $year      = '' if(!$year);
    $genres    = '' if(!$genres);
    $casts     = '' if(!$casts);
    $directors = '' if(!$genres);
    $url       = '' if(!$url);

    if(!$plot) {
	$plot  = '';
    } else {
	$plot  =~ s/\"/\'/g;
	$plot  =~ s/<br>/&#10;&#13;/g;
    }

    print TEXT "$name\n";

    print HTML "\n      <tr align=\"left\" class=\"$class\">\n";
    if($url) {
	print HTML "        <th width=\"40%\"><a href=\"$url\" title=\"$plot\">$name</a></th>\n";
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
}

print HTML "    </table>
  </body>
</html>
";

close(HTML);
