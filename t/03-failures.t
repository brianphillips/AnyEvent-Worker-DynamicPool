use Test::More;
use AnyEvent 5;
use AnyEvent::Util qw(guard);

BEGIN { use_ok('AnyEvent::Worker::DynamicPool') }
my %calls;
my $pool;
$pool = AnyEvent::Worker::DynamicPool->new(
  workers     => 0,
  max_workers => 5,
  worker_args => [ sub { die "Ha!\n" if $_[0]; return 1 }, on_error => sub { $calls{on_error}++ } ],
);

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
    is $@, 'Ha!', 'exception propogated';
    is @_, 0, 'no return value';
});
$cv->begin;
$pool->do(0, sub {
    shift;
    guard { $cv->end; };
    is $@, '', 'no exception propogated';
    is $_[0], 1, 'return value';
});
$cv->recv;
is $calls{on_error}, 1, 'one error callback executed';
done_testing;


sub clear_call_log {
  %calls = ();
}

