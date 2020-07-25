package InstallModules;

use v5.24;

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
use Data::Dumper;
use Logger;
use Capture::Tiny qw/capture/;

our %depcache;

async sub resolve_deps {
  my ($loop, $module, $perlid, $base_path) = @_;

  state $function = do {
    my $func = IO::Async::Function->new(
      code => sub {
        my ($module, $perlid, $base_path) = @_;
        my $perl_bin = $base_path->child($perlid)->child("bin");
        my ($cpanm) = $perl_bin->children(qr/^cpanm$/);

        $logger->debug("cpanm_resolve_deps", $perlid, {line => "Command is [$cpanm --quiet --showdeps $module]"});
        my $output = capture {
          system($cpanm, "--quiet","--showdeps", $module);
        };

        my $deps = [map {s/~.*//r} split(/\n/, $output)];
        $logger->debug("cpanm_resolve_deps", $perlid, {line => "Found deps ($?): ".Dumper($deps)});
        $depcache{$module} = $deps;
        return $deps;
    });

    $loop->add($func);

    $func;
  };

  $logger->info("cpanm_resolve_deps", $perlid, {line => "Finding deps for $module"});

  if (exists $depcache{$module}) {
    return $depcache{$module};
  }

  return $function->call(args => [$module, $perlid, $base_path])->get();
}

async sub install_cpanm {
  my ($loop, $base_path, $perlid) = @_;

  state $function = do {
    my $func = IO::Async::Function->new(
      code => sub {
      my $perl_bin = $base_path->child($perlid)->child("bin");
      my ($perl_exe) = $perl_bin->children(qr/^perl5/);

      my $output = capture {
        system("/bin/sh", "-c", 'curl -L https://cpanmin.us | '.$perl_exe.' - App::cpanminus');
      };
      # TODO check errors
      $logger->info("cpanm_install", $perlid, {line => "Installed cpanm"});
      $logger->debug("cpanm_install", $perlid, {line => "cpanm install output: $output"})
    });

    $loop->add($func);

    $func;
  };


  $logger->info("cpanm_install", $perlid, {line => "Installing cpanm"});

  return $function->call(args => [])->get();
}

async sub install_module {
  my ($loop, $module, $perlid, $base_path) = @_;

    state $function = do {
    my $func = IO::Async::Function->new(
      code => sub {
        my ($module, $perlid, $base_path) = @_;

        my $perl_bin = $base_path->child($perlid)->child("bin");
        my ($cpanm) = $perl_bin->children(qr/^cpanm$/);

        $logger->debug("cpanm_install_module", $perlid, {line => "Command is [$cpanm --verbose $module]"});
        my $output = capture {
          system($cpanm, "--verbose", $module);
        };

        $logger->debug("cpanm_install_module", $perlid, {line => "output for $module:  $output"});

        return 1;
    });

    $loop->add($func);

    $func;
  };

  $logger->info("cpanm_install_module", $perlid, {line => "Installing $module"});

  return $function->call(args => [$module, $perlid, $base_path])->get();
}

async sub read_cpanfile {
  my ($loop, $cpanfile, $perlid, $base_path) = @_;
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

  my @realreqs;
  my @queue = @requires;
  my %checked_req;

  while (my $req = shift @queue) {
    $logger->info("cpanfile", $perlid, {line => "Fetching meta about $req"});
    next if ($checked_req{$req});
    my $deps = await resolve_deps($loop, $req, $perlid, $base_path);
    $checked_req{$req} = 1;
    push @realreqs, $deps->@*;
    push @queue, $deps->@*;
  }

  return [uniq @realreqs];
}

async sub make_dep_list {
  my ($loop, @mod_list) = @_;

}

async sub install_modules {
  my ($loop, $perlid, $base_path) = @_;
  print "installing modules\n";
  await install_cpanm($loop, $base_path, $perlid);

  # Install a few random modules needed for the rest to be smooth
  await install_module($loop, "Module::Build", $perlid, $base_path);
  await install_module($loop, "Module::Install", $perlid, $base_path);
  await install_module($loop, "ExtUtils::MakeMaker", $perlid, $base_path);

  my $deplist = await read_cpanfile($loop, "/home/perlbot/perlbuut/cpanfile", $perlid, $base_path);
  print Dumper($deplist);
  # TODO log deplist
#  my $results = await install_modules($loop, $perl_path, $deplist);
}

# TODO uniq

#print Dumper(\@prereqs);




1;
