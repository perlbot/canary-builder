package Logger;
use strict;
use warnings;
use Data::Dumper;

use parent 'Exporter';
our @EXPORT=qw/$logger init_logger/;
our $logger;

# TODO make this 

sub init_logger {
  $logger = bless {}, 'Logger';
  return $logger;
}

sub _log {
  my ($self, $level, $phase, $id, $data) = @_;
  printf("%s: %s (%s): %s\n", $level, uc($phase), $id, $data->{line});
}
sub info {my $self = shift; $self->_log("INFO", @_)}
sub warn {my $self = shift; $self->_log("WARN", @_)}
sub debug {my $self = shift; $self->_log("DEBUG", @_)}
sub fatal {my $self = shift; $self->_log("FATAL", @_)}
sub error {my $self = shift; $self->_log("ERROR", @_)}

1;