package CpanmTasks;

use warnings;
use strict;

use MyMinion;
use Runner;
use List::Util qw/uniq/;
use Future;
use IO::Async::Function;
use IO::Async::Loop;
use Module::CPANfile;
use Data::Dumper;

$minion->add_task(install_cpanm => sub {
  my ($job, $perlid, $basepath) = @_;

  # TODO use a local copy of this, not a big deal now but will be later

  my $perlbin = $basepath->child($perlid)->child("bin");
  my ($perlexe) = $perlbin->children(qr/^perl5/);


  # TODO check the output of this
  my $result = Runner::run_code(
    code => sub {
      system("/bin/sh", "-c", 'curl -L https://cpanmin.us | '.$perlexe.' - App::cpanminus');
      exit($?);
    }, 
    timeout => 240,
    cgroup => "cpanminstall-$perlid",
    stdin => "", 
  );

  if ($result->{exit_code}) {
    $job->fail("Failed to install cpanm: ".$result->{exit_code}." ".$result->{error});
  } else {
    $job->finish("Cpanm installed");
  }
});

$minion->add_task(install_module => sub {
  my ($job, $perlid, $basepath, $module)=@_;

  my $perlbin = $basepath->child($perlid)->child("bin");
  my ($cpanm) = $perlbin->children(qr/^cpanm$/);

  my $result = Runner::run_code(
    code => sub {
      system($cpanm, "--verbose", $module);
      exit($?);
    },
    timeout => 600,
    cgroup => "module-install-$perlid-$module", # TODO make this use :: -> _
    stdin => "", 
  );

  if ($result->{exit_code}) {
    $job->fail("Failed to install module: ".$result->{exit_code}." ".$result->{error});
  } else {
    $job->finish($result->{buffer});
  }
});

 sub read_cpanfile {
  my ($job, $perlid, $basepath, $cpanfile) = @_;

  
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

#  while (my $req = shift @queue) {

  return {requires => [uniq @requires], recommends => [uniq @recommends]};
};

sub resolve_dependencies {
  my ($parent_ids, $perlid, $basepath, $basenotes, $deplist) = @_;

  my @joblist;
  my @futures;
  my %depcache;
  my %handled_modules; # uses Futures for job_ids
  my %circular_breaks;

  # We're going to use IO::Async::Loop to do this in parallel
  my $loop = IO::Async::Loop->new();
  my $func = IO::Async::Function->new(code => sub {
    my ($perlid, $basepath, $module) = @_;
    my $perlbin = $basepath->child($perlid)->child("bin");
    my ($cpanm) = $perlbin->children(qr/^cpanm$/);

    #$logger->debug("cpanm_resolve_deps", $perlid, {line => "Command is [$cpanm --quiet --showdeps $module]"});
    my $result = Runner::run_code(
      code => sub {
        system($cpanm, "--quiet","--showdeps", $module);
        exit($?);
      },
      timeout => 600,
      cgroup => "module-dep-$perlid-$module", # TODO make this use :: -> _
      stdin => "", 
    );
        
    
    unless ($result->{exit_code}) {
      my $deps = [map {s/~.*//r} split(/\n/, $result->{buffer})];
      #$logger->debug("cpanm_resolve_deps", $perlid, {line => "Found deps ($?): ".Dumper($deps)});
      $depcache{$module} = $deps;
      return $deps;
    } else {
      die "Failed to get deps for $module: ".$result->{error};
    }

  });

  $loop->add($func);

  my sub resolve_module {
    my ($module) = @_;

    # TODO make logger
    print "$perlid: Resolving deps for $module\n";
    $handled_modules{$module} = Future->new();
    my $future = $func->call(args => [$perlid, $basepath, $module]);

    $future = $future->on_done(sub {
      my ($deps) = @_;

      my @parent_futures;

      for my $dep (@$deps) {
        next if $circular_breaks{$dep}; # skip this if we are already processing it elsewhere, logs end up weird bug fuck-em if they have a circular dep
        $circular_breaks{$dep} = 1;

        unless ($handled_modules{$dep}) {
          # get the dependencies and setup %handled_modules for them
          resolve_module($dep);
        }

        die "Resolve_module failed for $dep" unless $handled_modules{$dep};

        push @parent_futures, $handled_modules{$dep};
      }

      return Future->needs_all(@parent_futures);
    })->on_ready(sub {
      # Success path
      my $infut = shift;
      my @parent_futs = $infut->get();
      my @parents = map {$_->get()} @parent_futs;

      my $job_id = $minion->enqueue(install_module => [] => {notes => $basenotes, parents => [@$parent_ids, @parents]});

      $handled_modules{$module}->done($job_id);
      return $job_id;
    }, sub {
      # Failure path
      $handled_modules{$module}->fail();
    });

    push @futures, $future;
    return $future;
  }


  # TODO handle recommends too, but in a non-threatening manner
  for my $dep ($deplist->{requires}->@*) {
    resolve_module($dep);
  }

  # TODO wait on all futures
  my $result_fut = Future->wait_all(@futures)->on_done(sub {
    my $fut = shift;
    my @job_futs = $fut->get();

    # ignore any failed ones for this, TODO figure out what I should do for this
    push @joblist, $_->get() for (grep {$_->is_done()} @job_futs);
  });

  $result_fut->get(); # wait on it to fill the joblist

  undef $loop;

  return @joblist;
}

$minion->add_task(schedule_cpanm => sub {
  my ($job, $perlid, $basepath) = @_;
  my $build_parents = $job->info->{parents};
  my $install_id = $minion->enqueue(install_cpanm => [$basepath, $perlid] => {notes => $job->info->{notes}, parents => $build_parents});

  my @jobs = map {
    $minion->enqueue(install_module => [$perlid, $basepath, $_] => {notes => $job->info->{notes}, parents => [$install_id]});
  } qw/Module::Build ExtUtils::MakeMaker Module::Install/;
  # Force update and install these three modules for later use of cpanm --showdeps to go smoothly, right now we need both calls due to some circular dep stuff I need to fix

  my $deplist = read_cpanfile($perlid, $basepath, "/home/perlbot/perlbuut/cpanfile");

  resolve_dependencies([$install_id, @jobs], $perlid, $basepath, $job->info->{notes}, $deplist);
  # TODO log deplist
#  my $results = await install_modules($loop, $perl_path, $deplist);
});

1;