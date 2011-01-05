use Test::More;
use AnyEvent 5;
use AnyEvent::Util qw(guard);

use_ok('AnyEvent::Worker::DynamicPool');
my $pool;
$pool = AnyEvent::Worker::DynamicPool->new(0, sub { my $avail = $pool->num_available_workers; sleep 1; return($avail, $pool->most_active_workers) } );

my %calls;
foreach my $m(qw(_add_worker _reap_worker)){
	my $full_name = "AnyEvent::Worker::DynamicPool::$m";
	no strict 'refs';
	my $original = \&{$full_name};
	*{$full_name} = sub { $calls{$m}++; goto &$original };
}

my $cv = AE::cv;

$SIG{ALRM} = sub { fail("Alarm clock, timeout!"); $cv->send };
alarm 3;

$cv->begin;
$pool->do(abc => "123", sub {
    shift;
    guard { $cv->end; };
    is $@, '', 'no error';
	is $_[0], 0, 'no spare workers while in job';
});
$pool->do(abc => "123", sub {
    shift;
    guard { $cv->end; };
    is $@, '', 'no error';
	diag "@_";
	is $_[0], 0, 'no spare workers while in job';
});

$cv->recv;
is $pool->num_available_workers, 0, 'no workers in pool';
is $pool->most_active_workers, 1, 'one active worker at any point in time';
is $calls{_add_worker}, 1, 'one worker is added';
is $calls{_reap_worker} || 0, 0, 'no workers were reaped';

done_testing;
