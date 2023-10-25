package Logger;

use strict;
use warnings;

use Data::Dumper;
use JSON::MaybeXS qw/encode_json decode_json/;

use Log::Log4perl;
use Function::Parameters qw/:std/;
use Moo;

has _logger => (is => 'ro', default => sub {Log::Log4perl->init('./logger.conf')});

# record the perl -V of a build
method log_perl_dashV($perlid, $jobid, $log, $exitcode) {
  $self->_logger->...;
}

# log the full cpanm setup, no need to be live for this
method log_cpanm_setup($perlid, $jobid, $log, $exitcode) {
  $self->_logger->...;
}

# live logging method for output of a perl build
method log_build_line($perlid, $jobid, $line) {
  $self->_logger->...;
}

# live logging method for output of a module, mostly useful for showing to the web ui
method log_module_line($perlid, $jobid, $module, $line) {

}

# log the final status of the module, for my own benefit
method log_module_status($perlid, $jobid, $module, $status) {
  # TBD what $status es?
}

method debug($perlid, $jobid, $context, $line) {

}

method info($perlid, $jobid, $context, $line) {

}

method error($perlid, $jobid, $context, $line) {

}

method fatal($perlid, $jobid, $context, $line) {

}

method warn($perlid, $jobid, $context, $line) {

}