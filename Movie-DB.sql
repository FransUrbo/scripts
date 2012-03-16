use movies;
set table_type=myisam;

create table movies (
  movieid int unsigned not NULL AUTO_INCREMENT,
  title char(64) not NULL,
  year smallint not NULL,
  rating decimal,
  plot blob default '',
  downloaded int unsigned not NULL,
  url char(64),

  primary key (movieid),
  unique index (title)
);

create table directors (
  directorid int unsigned not NULL AUTO_INCREMENT,
  director char(64) not NULL,

  primary key (directorid),
  unique index (director)
);

create table genres (
  genreid int unsigned not NULL AUTO_INCREMENT,
  genre char(64) not NULL,

  primary key (genreid),
  unique index (genre)
);

create table actors (
  actorid int unsigned not NULL AUTO_INCREMENT,
  actor char(64) not NULL,

  primary key (actorid),
  unique index (actor)
);

-- -------

create table director_data (
  movieid int unsigned not NULL,
  directorid int unsigned not NULL
);

create table genre_data (
  movieid int unsigned not NULL,
  genreid int unsigned not NULL
);

create table actor_data (
  movieid int unsigned not NULL,
  actorid int unsigned not NULL
);

