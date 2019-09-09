#!/usr/bin/env perl

use strict;
use warnings;

use Perl::Build;
use Time::Moment;
use Path::Tiny;

my $randid = join('', map {chr(65+rand()*26)} 1..5);
my $baseid = sprintf "blead-%s-%s", Time::Moment->now->strftime("%Y-%m-%d"), $randid;

for my $thread (qw/0 1/) {
  # TODO timeout
  my $dst = path( '/home/perlbot/perl5/custom/'. $baseid . ($thread ? '-threads' : '') );


  Perl::Build->install(
    src_path => '/home/perlbot/build/perl5',
    dst_path => $dst,
    configure_options => [
      '-de',
      '-Dusedevel',
      '-Accflags="-fpie -fPIC -mtune=native -fstack-protector-all -pie -D_FORTIFY_SOURCE=2 -ggdb  -DPERL_EMERGENCY_SBRK"',
      '-Aldflags="-Wl,-z,now -Wl,-zrelro -Wl,-z,noexecstack"',
      '-Duseshrplib',
      '-Dusemymalloc=y',
      ($thread ? '-Dusethreads' : ()),
    ],
    test => 1,
    jons => 4
  );

  $dst->child('.tested')->touch();
}
