package Logger;
use strict;
use warnings;
use Data::Dumper;
use Path::Tiny;

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


sub cpan_log {
  my ($self, $perlid, $module, $data) = @_;

  # TODO make this path configurable
  my $logpath = path("/home/perlbot/logs/")->child($perlid)->child("cpan");
  $logpath->mkpath();

  # TODO make this do something
  # $self->info($data)

  my $filename = sprintf "%s.log", $module=~s{(::|')}{-}gr;

  $logpath->child($filename)->spew_utf8($data);
}

sub perl_build_log {
  my ($self, $perlid, $data) = @_;

  # TODO make this path configurable
  my $logpath = path("/home/perlbot/logs/")->child($perlid);
  $logpath->mkpath();

  # TODO make this do something
  # $self->info($data);

  $logpath->child("build.log")->spew_utf8;
}
1;