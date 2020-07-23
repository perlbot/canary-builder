package InstallModules;

use strict;
use warnings;

use Future::Utils;
use Future::AsyncAwait;
use Future;
use IO::Async::Function;
use Runner;
use Module::CPANfile;
use List::Util qw/uniq/;
use Syntax::Keyword::Try;

async sub resolve_deps {
  my ($loop, $module, $perl_path, $cpanm_path) = @_;

}

async sub install_cpanm {
  my ($loop, $perl_path) = @_;
  # TODO
  return Future->new()->done("foo");
}

async sub read_cpanfile {
  my ($loop, $cpanfile, $perl_path, $base_id) = @_;
  my $file = Module::CPANfile->load($cpanfile);
  my $prereqs = $file->prereqs;

  my @phases = $prereqs->phases;
  my @requires;
  my @recommends;

  for my $phase (@phases) {
    # TODO try/catch and check other types
    push @requires, $prereqs->requirements_for($phase, 'requires')->required_modules;
    push @recommends, $prereqs->requirements_for($phase, 'recommends')->required_modules;
  }

  # @prereqs now contains the base set of modules to do
  
  my $cpanm_path = await install_cpanm($loop, $perl_path);

  my @realreqs;

  for my $req (@requires) {
    my $deps = await resolve_deps($loop, $req, $base_id, $cpanm_path);
    push @realreqs, $deps->@*;
  }
}

sub make_dep_list {
  my ($loop, @mod_list) = @_;

}



# TODO uniq

#print Dumper(\@prereqs);




1;
