# ---------------
sub mysql_insert() {
    $fh = shift;
    $file = shift;
    $name = shift;
    $title = shift;
    $url = shift;
    $year = shift;
    $genres = shift;
    $casts = shift;
    $directors = shift;
    $plot = shift;

    $year = 0 if(!$year);
    $title =~ s/ \(.*//;
    $title =~ s/ - $//;
    $title =~ s/ \(ISO\)//;
    $plot =~ s/.*: //;
    $plot =~ s/\"/\'/g;
    $plot =~ s/\<br\>$//i;
    $casts =~ s/,  /, /g;
    $casts =~ s/  /, /g;

    if(! defined($DATA{lc($name)})) {
	$DATA{lc($name)} = "$file;$name;$title;$url;$year;$genres;$casts;$directors;$plot";

	print $fh "INSERT IGNORE INTO Media(Name,Title)              VALUES (\"$name\", \"$title\");\n";
	print $fh "INSERT IGNORE INTO Data(Name,URL,File,Year,Plot)  VALUES (\"$name\", \"$url\", \"$file\", $year, \"$plot\");\n";

	if(($file =~ /\/ISOs\//) || ($title =~ /ISO/i) || ($name =~ /ISO/i)) {
	    if($genres) {
		$genres .= ", ISO";
	    } else {
		$genres  = "ISO";
	    }
	}

	if(($year > 0) && (! defined($YEARS{$year}))) {
	    $YEARS{$year} = $year;
	    print $fh "INSERT IGNORE INTO Years(Year)                    VALUES (\"$year\");\n";
	}

	if($genres) {
	    @genres = split(', ', $genres);
	    for $genre (@genres) {
		print $fh "INSERT IGNORE INTO Genres                         VALUES (\"$name\", \"$genre\");\n";

		if(! defined($GENRES{lc($genre)})) {
		    $GENRES{lc($genre)} = $genre;
		    print $fh "INSERT IGNORE INTO Types(Type)                    VALUES (\"$genre\");\n";
		}
	    }
	}

	if($casts) {
	    @casts = split(', ', $casts);
	    for $cast (@casts) {
		$cast =~ s/^\ //;
		$cast =~ s/\|.*//;
		$cast =~ s/"/'/g;

		if(($cast !~ /^$/) &&
		   ($cast !~ /&#x/) &&
	           ($cast !~ /\| See full cast/i) &&
	           ($cast !~ /crew/))
	        {
		   print $fh "INSERT IGNORE INTO Casts                          VALUES (\"$name\", \"$cast\");\n";
	        }
	    }
        }

	@directors = split(', ', $directors);
	for $director (@directors) {
	    if(($director !~ /^$/) &&
	       ($director ne '1') &&
	       ($director !~ /more credit/) &&
	       ($director !~ /See full technical specs/i) &&
	       ($director !~ /^&#x/))
	    {
		print $fh "INSERT IGNORE INTO Directors                      VALUES (\"$name\", \"$director\");\n";
	    }
	}
    }
}

1;
