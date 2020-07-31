package CpanmTasks;

use warnings;
use strict;
use v5.28;

use MyMinion;
use Runner;
use List::Util qw/uniq/;
use Future;
use IO::Async::Function;
use IO::Async::Loop;
use Module::CPANfile;
use Data::Dumper;
use Path::Tiny;
use Syntax::Keyword::Try;

$minion->add_task(install_cpanm => sub {
  my ($job, $perlid, $basepath) = @_;

  # TODO use a local copy of this, not a big deal now but will be later

  my $perlbin = path($basepath)->child($perlid)->child("bin");
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
    logger => sub {print "$perlid-cpanm: ".$_[0]->{line}; },
  );

  if ($result->{exit_code}) {
    $job->fail("Failed to install cpanm: ".$result->{exit_code}." ".$result->{error});
  } else {
    $job->finish("Cpanm installed");
  }
});

$minion->add_task(install_module => sub {
  my ($job, $perlid, $basepath, $module)=@_;

  my $perlbin = path($basepath)->child($perlid)->child("bin");
  my ($cpanm) = $perlbin->children(qr/^cpanm$/);

  my $result = Runner::run_code(
    code => sub {
      exec($cpanm, "--verbose", $module);
    },
    timeout => 600,
    cgroup => "module-install-$perlid-$module", # TODO make this use :: -> _
    stdin => "", 
    logger => sub {print "$perlid-module-$module: ".$_[0]->{line}; },
  );

 # if ($result->{exit_code}) {
 #   $job->fail("Failed to install module: ".Dumper($result));
 # } else {
    $job->finish($result->{buffer});
 # }
});

 sub read_cpanfile {
  my ($perlid, $basepath, $cpanfile) = @_;

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
  my %depcache;
  my %handled_modules; # uses Futures for job_ids
  my %circular_breaks;

  # We're going to use IO::Async::Loop to do this in parallel
  my $loop = IO::Async::Loop->new();
  my $func = IO::Async::Function->new(code => sub {
    my ($perlid, $basepath, $module) = @_;
    my $perlbin = path($basepath)->child($perlid)->child("bin");
    my ($cpanm) = $perlbin->children(qr/^cpanm$/);

    die "Failed to find cpanm for $perlid $basepath with $module" unless $cpanm;

    #$logger->debug("cpanm_resolve_deps", $perlid, {line => "Command is [$cpanm --quiet --showdeps $module]"});
    my $result = Runner::run_code(
      code => sub {
        exec($cpanm, "--quiet","--showdeps", $module);
      },
      timeout => 600,
      cgroup => "module-dep-$perlid-$module", # TODO make this use :: -> _
      stdin => "", 
      #logger => sub {print "$perlid-depsearch-$module: ".$_[0]->{line}; },
    );
    
    unless ($result->{exit_code}) {
      my $deps = [grep {$_ !~ /^!/} map {s/~.*//r} split(/\n/, $result->{buffer})];
      #$logger->debug("cpanm_resolve_deps", $perlid, {line => "Found deps ($?): ".Dumper($deps)});
      $depcache{$module} = $deps;
      return $deps;
    } else {
      die "Failed to get deps for $module: ".Dumper($result);
    }

  });

  $loop->add($func);

  my sub resolve_module {
    my ($module) = @_;

    my $recurse = __SUB__;
    # TODO make logger
    print "$perlid: Resolving deps for $module\n";
    $handled_modules{$module} = $func->call(args => [$perlid, $basepath, $module])->then(sub {
      my ($deps) = @_;

      my @parent_futures;

      for my $dep (@$deps) {
        next if $dep eq 'perl'; # ignore this dep
        next if $handled_modules{$dep} || $circular_breaks{$dep}; # skip this if we are already processing it elsewhere, logs end up weird bug fuck-em if they have a circular dep
        $circular_breaks{$dep} = 1;

        unless ($handled_modules{$dep}) {
          # get the dependencies and setup %handled_modules for them
          #print "RECURSING FOR $dep\n";
          $recurse->($dep);
        }

        die "Resolve_module failed for $dep: ".Dumper([keys %handled_modules]) unless $handled_modules{$dep};

        push @parent_futures, $handled_modules{$dep};
      }

      #print "Got deps for $module [@{$deps}]\n";

      return $loop->new_future->wait_all(@parent_futures);       
    })->then(sub {
      # Success path
      my @parents;

      for my $pfut (@_) {
        my @parent_futs = $pfut->get();
        push @parents, map {ref $_ ? $_->get() : $_} @parent_futs;
      }

      print "Got jobs for $module: ".Dumper(0+@_, \@parents);

      my $job_id = $minion->enqueue(install_module => [$perlid, $basepath, $module] => {notes => $basenotes, parents => [@$parent_ids, @parents]});

      print "Setting job_id $job_id for $module\n";

      return Future->done($job_id);
    }, sub {
      # Failure path
      print "Failed deps for $module ".Dumper(\@_)."\n";
      die ("Failed to install $module\n");
    });
  }


  # TODO handle recommends too, but in a non-threatening manner
  for my $dep ($deplist->{requires}->@*) {
    resolve_module($dep);
  }

  # TODO wait on all futures
  my $result_fut = $loop->new_future->wait_all(values %handled_modules)->then(sub {
    my $fut = shift;
    print "Finished all futures\n";
    my @job_futs = $fut->get();

    print Dumper(\@job_futs);

    # ignore any failed ones for this, TODO figure out what I should do for this
    push @joblist, $_ for (grep {$_} @job_futs);

    my $retfut = $loop->new_future();
    $retfut->done();
    return $fut;
  });


  print "Waiting on result future\n";
  $result_fut->get(); # wait on it to fill the joblist
  print "Finished waiting\n";

  #undef $loop;

  return @joblist;
}

$minion->add_task(schedule_cpanm => sub {
  my ($job, $perlid, $basepath) = @_;
  my $build_parents = $job->info->{parents};
  my $install_id = $minion->enqueue(install_cpanm => [$perlid, $basepath] => {notes => $job->info->{notes}, parents => $build_parents});

  my @jobs = map {
    $minion->enqueue(install_module => [$perlid, $basepath, $_] => {notes => $job->info->{notes}, parents => [$install_id]});
  } qw/Module::Build ExtUtils::MakeMaker Module::Install/;
  # Force update and install these three modules for later use of cpanm --showdeps to go smoothly, right now we need both calls due to some circular dep stuff I need to fix

  $minion->foreground($_) for ($install_id, @jobs);

  try {
    #my $deplist = read_cpanfile($perlid, $basepath, "/home/perlbot/perlbuut/cpanfile");
    my $deplist = read_cpanfile($perlid, $basepath, "/home/perlbot/workspace/blead-canary/tests/testcpanfile");

    resolve_dependencies([$install_id, @jobs], $perlid, $basepath, $job->info->{notes}, $deplist);
  } catch {
    print "WTF: $@\n\n\n";
    die $@;

  }
  # TODO log deplist
#  my $results = await install_modules($loop, $perl_path, $deplist);
});

1;