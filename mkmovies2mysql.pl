#!/usr/bin/perl -w

# ---------------
sub mysql_drop() {
    print "DROP TABLE Media;
DROP TABLE Data;
DROP TABLE Genres;
DROP TABLE Casts;
DROP TABLE Directors;
DROP TABLE Types;
DROP TABLE ISOs;
DROP TABLE Years;
";
}

# ---------------
sub mysql_create() {
print "CREATE TABLE Media
(
  Name varchar(128) PRIMARY KEY,
  Title varchar(64),
  Year int,
  Plot varchar(256)
 );

CREATE TABLE Data
(
  Name varchar(128),
  URL varchar(64),
  File varchar(128)
 );

CREATE TABLE Genres
(
  Name varchar(128),
  Genre varchar(64)
);

CREATE TABLE Casts
(
  Name varchar(128),
  Cast varchar(64)
);

CREATE TABLE Directors
(
  Name varchar(128),
  Director varchar(64)
);

CREATE TABLE Types
(
  Type varchar(64) PRIMARY KEY
);

CREATE TABLE ISOs
(
  Title varchar(64) PRIMARY KEY
);

CREATE TABLE Years
(
  Year int PRIMARY KEY
);

";
}

# ---------------
sub mysql_insert() {
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

	print "INSERT INTO Media     VALUES (\"$name\", \"$title\", $year, \"$plot\");\n";
	print "INSERT INTO Data      VALUES (\"$name\", \"$url\", \"$file\");\n";

	if(($file =~ /\/ISOs\//) || ($title =~ /ISO/i)) {
	    if(! defined($ISOs{lc($title)})) {
		$ISOs{lc($title)} = $title;
		print "INSERT INTO ISOs      VALUES (\"$title\");\n";
	    }
	}

	if(($year > 0) && (! defined($YEARS{$year}))) {
	    $YEARS{$year} = $year;
	    print "INSERT INTO Years     VALUES (\"$year\");\n";
	}

	@genres = split(', ', $genres);
	for $genre (@genres) {
	    print "INSERT INTO Genres    VALUES (\"$name\", \"$genre\");\n";

	    if(! defined($GENRES{lc($genre)})) {
		$GENRES{lc($genre)} = $genre;
		print "INSERT INTO Types     VALUES (\"$genre\");\n";
	    }
	}

	@casts = split(', ', $casts);
	for $cast (@casts) {
	    $cast =~ s/^\ //;
	    $cast =~ s/\|.*//;

	    if(($cast !~ /^$/) &&
	       ($cast !~ /&#x/) &&
	       ($cast !~ /\| See full cast/i) &&
	       ($cast !~ /crew/))
	    {
		print "INSERT INTO Casts     VALUES (\"$name\", \"$cast\");\n";
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
		print "INSERT INTO Directors VALUES (\"$name\", \"$director\");\n";
	    }
	}

	print "\n";
    }
}

# ---------------
&mysql_drop();
&mysql_create();

open(LIST, "/share/.Torrents/Unsorted/.list")
    || die("Can't open file, $!\n");
while(! eof(LIST)) {
    $line = <LIST>;
    chomp($line);

    ($file, $name, $title, $url, $year, $genres, $casts, $directors, $plot)
	= split(';', $line);

    &mysql_insert($file, $name, $title, $url, $year, $genres, $casts, $directors, $plot);
}
close(LIST);
