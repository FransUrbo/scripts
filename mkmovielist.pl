#!/usr/bin/perl -w

# --------------------------------------------
sub imdb_lookup() {
    my($title, $cnt) = @_;
    my($line, $data, $year, $genres, $url);

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

	if($line =~ /^Year/) {
	    $year = $data;

	    $YEARS{$year} = $year;
	} elsif($line =~ /^Cast/) {
	    $data =~ s/ and /, /;
	    $casts = $data;

	    @casts = split(', ', $casts);
	    for $cast (@casts) {
		$CASTS{$cast} = $cast;
	    }
	} elsif($line =~ /^Genres/) {
	    $data =~ s/ and /, /;
	    $genres = $data;

	    @genres = split(', ', $genres);
	    for $genre (@genres) {
		$GENRES{$genre} = $genre;
	    }
	} elsif($line =~ /^IMDB movie URL/) {
	    $url =  $data;
	}
    }
    close(IMDB);

    if($url !~ /^http:/) {
	$title =~ s/.*\ -\ //;
	($year, $genres, $url) = &imdb_lookup($title, $cnt+1);
    }

    $year = 0 if(!$year);
    $genres = 0 if(!$genres);
    $url = 0 if(!$url);

    return(($year, $genres, $url));
}

# --------------------------------------------
if(open(LIST, ".mkmovielist.list")) {
    while(! eof(LIST)) {
	$line = <LIST>;
	chomp($line);
	
	$name = (split(';', $line))[1];
	$MOVIES{"$name"} = $line;
    }
    close(LIST);
#} else {
#    %MOVIES = {};
}

# --------------------------------------------
open(FS, "zfs list -H -r share/Movies -o mountpoint | sort | ")
    || die("Can't open ZFS shares list, $!\n");
while(! eof(FS)) {
    $fs = <FS>;
    chomp($fs);

    open(FIND, "find \"$fs\" -maxdepth 1 -type f | ")
	|| die("Can't run find, $!\n");
    while(! eof(FIND)) {
	$file = <FIND>;
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
	$name =  $file;
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
	$title =  $name;
	$title =~ s/ \(.*\)//;
	$title =~ s/Disney\'s //;
	$title =~ s/ [12][90][0-9][0-9]//;
	$title =~ s/\ -$//;

	print STDERR "$file -> $name: ";

	$DO_IMDB = 1; $existing_url = "";
	if($MOVIES{"$name"}) {
	    $existing_url = (split(';', $MOVIES{"$name"}))[3];
	    $DO_IMDB = 0 if($existing_url);
	}

	if($DO_IMDB) {
	    ($year, $genres, $url) = &imdb_lookup($title);

	    if($url && !$MOVIES{"$name"}) {
		open(LIST, ">> .mkmovielist.list")
		    || die("Can't append to existing list of movies, $!\n");
		print LIST "$file;$name;$title;$url;$year;$genres;$casts\n";
		close(LIST);
	    }
	} elsif($existing_url) {
	    $url = $existing_url;
	}

	$name =~ s/^The (.*)/$1, The/;
	$ENTRIES{"$name"} = "$file;$name;$title;$year;$genres;$casts";

	if($url) {
	    $ENTRIES{"$name"} .= ";$url";
	    print STDERR "FOUND";
	} else {
	    print STDERR "NOT FOUND";
	}

	print STDERR "\n";
    }
    close(FIND);
}
close(FS);

# --------------------------------------------
open(HTML, "> /share/Movies.html")
    || die("Can't open output html file, $!\n");

open(TEXT, "> /share/Movies.txt")
    || die("Can't open output text file, $!\n");

print HTML "<html>
  <body>
    <table border=\"1\">
";

for $entry (sort keys %ENTRIES) {
    ($file, $name, $title, $url, $year, $genres, $casts) =
	split(';', $ENTRIES{"$entry"});

    print TEXT "$name\n";

    print HTML "      <tr>\n";
    if($url) {
	print HTML "      <th><a href=\"$url\">$name</a></th>\n";
    } else {
	print HTML "      <th>$name</th>\n";
    }
    if($year) {
	print HTML "      <th>$year</th>\n";
    }
    if($genres) {
	print HTML "      <th>$genres</th>\n";
    }
    if($casts) {
	print HTML "      <th>$casts</th>\n";
    }
    print HTML "      </tr>\n";
}

print HTML "    </table>
  </body>
</html>
";

close(HTML);
