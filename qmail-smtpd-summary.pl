#!/usr/bin/perl -w

# by Ted Zlatanov <tzz@bwh.harvard.edu>
# GPL license

use strict;
use Data::Dumper;

my %messages;

while (<>)
{
 if (m/(.*?) qmail-smtpd (\d+): (.*)/)
 {
  my $id = $2;
  my $line = $3;
  $messages{$id}->{date} = $1;

  if ($line =~ m/mail from: (\S+)/)
  {
   $messages{$id}->{from} = $1;
  }
  elsif ($line =~ m/rcpt to: (\S+)/)
  {
   push @{$messages{$id}->{to}}, $1;
  }
  elsif ($line =~ m/size (\d+) bytes/)
  {
   $messages{$id}->{size} = $1;
  }
 }
}

printf "ID         date               from\n";

foreach my $id (sort { $a <=> $b } keys %messages)
{
 next unless exists $messages{$id}->{from};
 next unless exists $messages{$id}->{to};
 next unless exists $messages{$id}->{date};
 next unless exists $messages{$id}->{size};

 printf "%-10d %s %10s %30s\n\t%s\n",
  $id,
   $messages{$id}->{date},
  human($messages{$id}->{size}),
  $messages{$id}->{from},
   join ("\n\t", map { "to: $_" } @{$messages{$id}->{to}})
}

# get a human-readable size
sub human
{
 my $i = shift @_;
 my @sizes = qw/k m g/;
 my $size = '';

 do
 {
  $i /= 1024;
  $size = shift @sizes;
 }
 while ($i > 1024 && @sizes);

 return sprintf '%.2f%s', $i, $size;
}
