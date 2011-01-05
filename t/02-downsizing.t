use Test::More;
use AnyEvent 5;
use AnyEvent::Util qw(guard);

BEGIN { use_ok('AnyEvent::Worker::DynamicPool') }
my $pool;
$pool = AnyEvent::Worker::DynamicPool->new(
	workers => 0,
  max_workers => 10,
  max_spare_workers => 0,
	worker_args => [ sub { my $length = shift; sleep $length; return $length } ],
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
    guard { $cv->end; };
    is $@, '', 'no error';
    is $_[0], 1, 'slept for 1 seconds';
});
$cv->recv;

$cv = AE::cv;

$cv->begin;
$pool->do(1, sub {
    shift;
    guard { $cv->end; };
    is $@, '', 'no error';
    is $_[0], 1, 'slept for 1 second';
});

$cv->recv;

is_deeply \%calls, { _add_worker => 2, _reap_worker => 2}, 'all calls made as expected';

clear_call_log();

$pool = AnyEvent::Worker::DynamicPool->new(
	workers => 0,
  max_workers => 10,
  max_spare_workers => 5,
	worker_args => [ sub { my $length = shift || 1; sleep $length; return $length } ],
);
is $pool->num_available_workers, 0, 'no workers to start with';

$cv = AE::cv;
$cv->begin, $pool->do(1, sub { $cv->end }) for 1..5;
$cv->recv;
is $calls{_add_worker}, 5, '5 workers added';
is $pool->most_active_workers, 5, '5 workers active at most';

clear_call_log();

$pool = AnyEvent::Worker::DynamicPool->new(
	workers => 0,
  max_workers => 10,
  max_spare_workers => 5,
	worker_args => [ sub { my $length = shift || 1; sleep $length; return $length } ],
);

$cv = AE::cv;
$cv->begin, $pool->do(1, sub { $cv->end }) for 1..15;
$cv->recv;
is $calls{_add_worker}, 10, 'all 10 workers added';
is $calls{_reap_worker}, 5, '5 workers reaped to satisfy max_spare_workers';
is $pool->{total_workers}, 5, 'only 5 workers remain';
is $pool->most_active_workers, 10, '10 workers active at most';

done_testing;


sub clear_call_log {
  %calls = ();
}
