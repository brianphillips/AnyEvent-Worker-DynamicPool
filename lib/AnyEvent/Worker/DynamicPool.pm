#
# This file is part of AnyEvent-Worker-DynamicPool
#
# This software is copyright (c) 2011 by Brian Phillips.
#
# This is free software; you can redistribute it and/or modify it under
# the same terms as the Perl 5 programming language system itself.
#
package AnyEvent::Worker::DynamicPool;
BEGIN {
  $AnyEvent::Worker::DynamicPool::VERSION = '0.001';
}

# ABSTRACT: Auto-resizing worker pool for AnyEvent

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
  if($args->{workers} > $args->{max_workers}){
    carp "adjusting max_workers to reflect number of workers requested: $args->{workers} (previously $args->{max_workers})";
    $args->{max_workers} = $args->{workers};
  }
  if($args->{min_spare_workers} > $args->{workers}){
    carp "adjusting min_spare_workers to reflect number of workers requested: $args->{workers} (previously $args->{min_spare_workers})";
    $args->{min_spare_workers} = $args->{workers};
  }
  $args->{max_workers} ||= $args->{workers} || 1;

  my $self = $class->SUPER::new($args->{workers}, @{ $args->{worker_args} });
  $args->{most_workers_in_pool} = $args->{total_workers} = $self->num_available_workers;
  @$self{keys %$args} = values %$args;
  return $self;
}

sub _add_worker {
  my $self = shift;
  push @{ $self->{pool} }, AnyEvent::Worker->new(@{ $self->{worker_args} });
  $self->{total_workers}++;
  $self->{most_workers_in_pool} = $self->{total_workers} if $self->{total_workers} > $self->{most_workers_in_pool};
  return $self;
}

sub _reap_worker {
  my $self = shift;
  my $w = shift @{ $self->{pool} };
  $w->kill_child;
  $self->{total_workers}--;
  return $self;
}


sub most_workers_in_pool {
  my $self = shift;
  return $self->{most_workers_in_pool};
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



=pod

=head1 NAME

AnyEvent::Worker::DynamicPool - Auto-resizing worker pool for AnyEvent

=head1 VERSION

version 0.001

=head1 SYNOPSIS

	# identical interface and behavior to AnyEvent::Worker::Pool
	$pool = AnyEvent::Worker::DynamicPool->new( 5, sub { ... } );
	$pool->do(@args, sub { ... });

	# alternate constructor arguments enable additional behavior
    $pool = AnyEvent::Worker::DynamicPool->new(
        workers => 5,
        worker_args => [ sub { ... } ],
        min_spare_workers => 2,
				max_spare_workers => 5,

    );

=head1 METHODS

=head2 new

Creates a new pool of workers.  This module extends
L<AnyEvent::Worker::Pool> and adds dynamic resizing of the pool based on
the workload and the settings specified when the pool was created. The
settings for this module are inspired by Apache's pre-forking HTTP server
settings controlling how child processes are managed (L<corresponding
Apache documentation|http://httpd.apache.org/docs/2.0/mod/prefork.html>).

Available settings:

=over 4

=item *

workers

number of workers to create on initialization

=item *

worker_args

arguments to pass to L<AnyEvent::Worker> to create the worker

=item *

max_workers

hard limit on the maximum size of the pool, will be adjusted to match C<workers> setting if it is not specified or if the value specified is less than the initial number of workers requested.

=item *

min_spare_workers

instructs the pool to always have this number of idle workers waiting for new jobs, will be set to C<0> if it is not specified or to match the C<workers> setting if it is greater than the initial number of workers requested.

=item *

max_spare_workers

instructs the pool to reap any idle workers above this amount, will be adjusted to match C<workers> setting if it is not specified or is less than the initial number of workers requested

=back

=head2 most_workers_in_pool

Returns the maximum size of this pool.  Will always be less than or
equal to the C<max_workers> setting.

=head2 num_available_workers

=head2 can_expand

Compares the total number of workers with the C<max_workers> setting.

=head2 needs_more

Compares the number of available workers with the C<min_spare_workers> setting.

=head2 needs_less

Compares the number of available workers with the C<max_spare_workers> setting.

=head2 take_worker

Overrides L<AnyEvent::Worker::DynamicPool>'s C<take_worker> method.
Extra workers will be created if there are no spares and the total
number of workers is not greater than the C<max_workers> setting.
The C<min_spare_workers> setting will also be considered and additional
workers will be created if the number of available workers is too low.

=head2 ret_worker

Overrides L<AnyEvent::Worker::DynamicPool>'s C<ret_worker> method.
Extra workers will be reaped after they finish a job if the number of
available workers exceeds the C<max_spare_workers> setting.

=head1 SEE ALSO

=over 4

=item *

L<AnyEvent::Worker::Pool>

=item *

L<AnyEvent::Worker>

=item *

L<AnyEvent>

=back

=head1 AUTHOR

Brian Phillips <bphillips@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2011 by Brian Phillips.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut


__END__

