package Logger;
use strict;
use warnings;
use Function::Parameters;

use parent 'Exporter';
our @EXPORT=qw/$logger init_logger/;
our $logger;

# TODO make this 

sub init_logger {
  $logger = bless {}, 'Logger';
  return $logger;
}

BEGIN {
  for my $level (qw/info debug error warn fatal/) {
    eval q<sub >.$level.q< {
      my ($id, $phase, $data) = @_;
      printf("%s: %s (%s): %s\n", ">.$level.q[", uc($phase), $id, $data->{line});
    }];
  }
}


1;