This is a new recreation of my old daily build system for blead
I'm rewriting it to take advantage of things I've learned and some
changes in the setup for everything to be more robust and nicer to
work on.  The original is at ... and was mostly written as some bash
scripts.  This version will be almost entirely in perl and directly
depend on App::EvalServerAdvanced to be running to perform the
testing and fuzzing functionality.  This will enable the tests
to run in parallel and also better handle some patholigical timeout
cases that I've run into issues with.  I'll also be doing the builds
via Perl::Build instead of perlbrew, to enable more fine grained
control over things, and enable testing the unthreaded version of
perl while the threaded is being built.  This will also enable
me to do better reporting than just a dump from cron.

Tasks:
1) Move Perl::Build code into library utilizing Future
2) Use IO::Async::Function or ::Routine to enable doing tasks in parallel
3) Use Email::Stuffer to report failures to mailing list
4) Report on CPAN module installs and failures individually
5) Run filesystem shrinking script after all is said and done
6) Keep logs in compressed form (zstd) available on webserver
7) Automatic cleanup of logs after 30 days
8) Automatic cleanup of perls, keep last 5 successful builds of threaded and unthreaded
9) Use secondary evalserver, configured for batch mode scheduling so that it can't overload the system
10) Allow for specific commits/tags/branches of perl to be built and tested
