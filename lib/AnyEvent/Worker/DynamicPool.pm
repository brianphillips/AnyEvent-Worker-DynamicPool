package AnyEvent::Worker::DynamicPool;

use strict;
use warnings;
use base 'AnyEvent::Worker::Pool';
use Carp qw(croak carp);
use Scalar::Util qw(looks_like_number);

sub new {
  my $class = shift;
  my $args;
  if(ref($_[0]) eq 'HASH'){
    $args = shift;
  } elsif( looks_like_number( $_[0] ) ){
    $args->{workers} = shift;
    $args->{worker_args} = [@_];
  } elsif(@_ % 2 == 0){
    $args = { @_ };
  } else {
    croak "invalid args @_";
  }
  $args->{workers} ||= 0;
  $args->{worker_args} ||= [];
  $args->{min_spare_workers} ||= 0;
  $args->{max_spare_workers} ||= $args->{workers} || 0;
  if($args->{workers} > $args->{max_spare_workers}){
    carp "adjusting max_spare_workers to reflect number of workers requested: $args->{workers} (previously $args->{max_spare_workers})";
    $args->{max_spare_workers} = $args->{workers};
  }
  if($args->{min_spare_workers} > $args->{workers}){
    carp "adjusting min_spare_workers to reflect number of workers requested: $args->{workers} (previously $args->{min_spare_workers})";
    $args->{min_spare_workers} = $args->{workers};
  }
  $args->{max_workers} ||= $args->{workers} || 1;

  my $self = $class->SUPER::new($args->{workers}, @{ $args->{worker_args} });
  $args->{most_active_workers} = $args->{total_workers} = $self->num_available_workers;
  @$self{keys %$args} = values %$args;
  return $self;
}

sub _add_worker {
  my $self = shift;
  push @{ $self->{pool} }, AnyEvent::Worker->new(@{ $self->{worker_args} });
  $self->{total_workers}++;
  $self->{most_active_workers} = $self->{total_workers} if $self->{total_workers} > $self->{most_active_workers};
  return $self;
}

sub _reap_worker {
  my $self = shift;
  my $w = shift @{ $self->{pool} };
  $w->kill_child;
  $self->{total_workers}--;
  return $self;
}

sub most_active_workers {
  my $self = shift;
  return $self->{most_active_workers};
}

sub num_available_workers {
  return scalar(@{ shift->{pool} });
}

sub can_expand {
  my $self = shift;
  return $self->{total_workers} < $self->{max_workers};
}

sub needs_more {
  my $self = shift;
  my $available = $self->num_available_workers;
  return !$available || $available < $self->{min_spare_workers};
}
sub needs_less {
  my $self = shift;
  my $available = $self->num_available_workers;
  return $available && $available > $self->{max_spare_workers};
}

sub take_worker {
  my $self = shift;

  $self->_add_worker if($self->can_expand && $self->needs_more);
  $self->SUPER::take_worker(@_);

  return;
}

sub ret_worker {
  my $self = shift;
	my $worker = shift;
	if(my $cb = $worker->{on_error} and my $e = $@){
		$worker->{on_error}->($worker, $e, 1);
	}
  $self->SUPER::ret_worker($worker);
  $self->_reap_worker if($self->needs_less);
  return;
}

1;
