#!/usr/bin/perl -w

use Mysql;

# MySQL CONFIG VARIABLES
$host = "localhost";
$database = "movies";
$user = "turbo";
$pw = "Hemligt";

$connect = Mysql->connect($host, $database, $user, $pw);
$connect->selectdb($database);


sub run_sql() {
    $sql = shift;

    # EXECUTE THE QUERY FUNCTION
    $execute = $connect->query($sql);

    # AFFECTED ROWS
    $affectedrows = $execute->affectedrows($sql);

    # ID OF LAST INSERT
    $lastid = $execute->insertid($myquery);

    print "lastid: '$lastid'\n";
#    print "$sql;\n";
}

open(MOVIES, "/share/Movies.txt")
    || die("Can't open movies, $!\n");
while(! eof(MOVIES)) {
    $title = <MOVIES>;
    chomp($title);
    $title =~ s/\(.*//;

    # ---------------------------
    open(IMDB, "/usr/local/bin/imdb-mf -t \"$title\" |")
	|| die("Can't call imdb-mf, $!\n");
    while(! eof(IMDB)) {
	$line = <IMDB>;
	chomp($line);

	($key, $data) = split(' : ', $line);
	if($key =~ /^Title/) {
	    $MOVIE{'title'} = $data;
	    print "Movie title: $data\n";
	} elsif($key =~ /^Year/) {	$MOVIE{'year'}      = $data; }
	elsif($key =~ /^Rating/) {
	    $data =~ s/\/.*//;
	    $MOVIE{'rating'} = $data;
	} elsif($key =~ /^Director/) {	$MOVIE{'directors'} = $data; }
	elsif($key =~ /^Genres/) {	$MOVIE{'genres'}    = $data; }
	elsif($key =~ /^Cast/) {
	    if($data =~ / and /i) {
		$data =~ s/ and /, /gi;
	    }
	    $MOVIE{'casts'}     = $data;
	} elsif($key =~ /^IMDB/) {
	    $MOVIE{'url'} = $data;
	    last;
	} elsif($key =~ /^Plot/) {
	    $MOVIE{'plot'} = '';
	    $line = <IMDB>; $line = <IMDB>;

	    while($line !~ /^$/) {
		$MOVIE{'plot'} .= $line;

		$line = <IMDB>;
	    }
	    chomp($MOVIE{'plot'});
	}
    }
    close(IMDB);

    # ---------------------------
    foreach $key (sort keys %MOVIE) {
#	if($MOVIE{$key} =~ /, /) {
#	    @vals = split(', ', $MOVIE{$key});
#	    foreach $val (@vals) {
#		print "$key ; $val\n";
#	    }
#	} else {
#	    printf("$key ; %s\n", $MOVIE{$key});
#	}

	if($MOVIE{$key} =~ /\'/) {
	    $MOVIE{$key} =~ s/\'/\\\'/;
	}
    }

    # ---------------------------
    $sql  = "INSERT INTO movies(title, year, rating, plot, url) ";
    $sql .= "VALUES('".$MOVIE{'title'}."', '".$MOVIE{'year'}."', ";
    $sql .= "'".$MOVIE{'rating'}."', '".$MOVIE{'plot'}."', ";
    $sql .= "'".$MOVIE{'url'}."')";
    &run_sql($sql);
#    &run_sql("SELECT movieid FROM movies WHERE title='".$MOVIE{'title'}."'");

    # ---------------------------
    if($MOVIE{'directors'} =~ /,/) {
	@directors = split(',', $MOVIE{'directors'});
	foreach $director (@directors) {
	    $director =~ s/^ //; $director =~ s/ $//;

	    $sql = "INSERT INTO directors(director) VALUES('$director')";
	    &run_sql($sql);

#	    &run_sql("SELECT directorid FROM directors WHERE director='$director'");
	}
    } else {
	$sql = "INSERT INTO directors(director) VALUES('".$MOVIE{'directors'}."')";
	&run_sql($sql);

#	&run_sql("SELECT directorid FROM directors WHERE director='".$MOVIE{'directors'}."'");
    }

    # ---------------------------
    if($MOVIE{'genres'} =~ /,/) {
	@genres = split(',', $MOVIE{'genres'});
	foreach $genre (@genres) {
	    $genre =~ s/^ //; $genre =~ s/ $//;

	    $sql = "INSERT INTO genres(genre) VALUES('$genre')";
	    &run_sql($sql);

#	    &run_sql("SELECT genreid FROM genres WHERE genre='$genre'");
	}
    } else {
	$sql = "INSERT INTO genres(genre) VALUES('".$MOVIE{'genres'}."')";
	&run_sql($sql);

#	&run_sql("SELECT genreid FROM genres WHERE genre='".$MOVIE{'genres'}."'");
    }

    # ---------------------------
    if($MOVIE{'casts'} =~ /,/) {
	@actors = split(',', $MOVIE{'casts'});
	foreach $actor (@actors) {
	    $actor =~ s/^ //; $actor =~ s/ $//;

	    $sql = "INSERT INTO actors(actor) VALUES('$actor')";
	    &run_sql($sql);

#	    &run_sql("SELECT actorid FROM actors WHERE actor='$actor'");
	}
    } else {
	$sql = "INSERT INTO actors(actor) VALUES('".$MOVIE{'casts'}."')";
	&run_sql($sql);

#	&run_sql("SELECT actorid FROM actors WHERE actor='".$MOVIE{'casts'}."'");
    }

    # ---------------------------

    exit(1);
    print "\n";
}
close(MOVIES);
