use Test::More;
use AnyEvent 5;
use AnyEvent::Util qw(guard);

BEGIN { use_ok('AnyEvent::Worker::DynamicPool') }
my $pool;
$pool = AnyEvent::Worker::DynamicPool->new(
	workers => 1,
  max_workers => 5,
	worker_args => [ sub { print "# $$ in child\n"; die "$$ Ha!"; }, on_error => sub { print STDERR "$$ died $@!\n";} ],
);

my %calls;
BEGIN {
  foreach my $m(qw(_add_worker _reap_worker)){
    my $full_name = "AnyEvent::Worker::DynamicPool::$m";
    no strict 'refs';
    my $original = \&{$full_name};
    *{$full_name} = sub { $calls{$m}++; goto &$original };
  }
}

my $cv = AE::cv;

$cv->begin;
$pool->do(1, sub {
    shift;
    print STDERR "$$\n";
    guard { $cv->end; };
    is $@, 'Ha!', 'exception propogated';
    is $_[0], 1, 'slept for 1 seconds';
});
$cv->recv;

diag explain \%calls;
done_testing;


sub clear_call_log {
  %calls = ();
}

