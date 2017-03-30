package IO::Framed::NonBlocking;

use strict;
use warnings;

=encoding utf-8

=head1 NAME

IO::Framed::NonBlocking

=head1 SYNOPSIS

    my $io = IO::Framed::NonBlocking->new(
        $in_fh,
        $out_fh,

        #Optional, whatever “overbite” we might have read
        #from, e.g., a protocol handshake.
        $initial_buffer,
    );

    #returns the number of messages queued to be written
    $io->get_write_queue_size();

    $io->process_write_queue();

=head1 DESCRIPTION

A non-blocking I/O object. Use this if you’re doing your own
I/O multiplexing rather than using an event loop.

Whenever C<get_write_queue_size()> returns a positive number,
you’ll need to wire the output filehandle into whatever select/poll/etc.
that you’re running, then C<process_write_queue()> when the filehandle
is ready to accept data. You can also, as a shortcut, run
C<process_write_queue()> at the end of every read loop, but as it’s not
guaranteed to be able to flush the entire write queue, you’ll still need
to check C<get_write_queue_size()> before the select/poll/etc.

=cut

use parent qw(
    IO::Framed
);

use IO::SigGuard ();

use Net::WAMP::X ();

use constant blocking => 0;

#----------------------------------------------------------------------

sub new {
    my $self = $_[0]->SUPER::new( @_[ 1 .. $#_ ] );

    $self->{'_write_queue'} = [];

    return $self;
}

sub enqueue_write {
    my $self = shift;

    push @{ $self->{'_write_queue'} }, \@_;

    return;
}

sub flush_write_queue {
    my ($self) = @_;

    local $self->{'_tolerate_EAGAIN'};

    while ( my $qi = $self->{'_write_queue'}[0] ) {
        return 0 if !$self->_write_now_then_callback( @$qi );

        shift @{ $self->{'_write_queue'} };
        $self->{'_tolerate_EAGAIN'} = 1;
    }

    return 1;
}

sub get_write_queue_size {
    my ($self) = @_;

    return 0 + @{ $self->{'_write_queue'} };
}

#----------------------------------------------------------------------

#$self, $buffer, $callback_cr (optional)
sub _write_now_then_callback {
    local $!;

    my $wrote = IO::SigGuard::syswrite( $_[0]->{'_out_fh'}, $_[1] ) || do {

        if ($! && (!$_[0]->{'_allow_EAGAIN'} || !$!{'EAGAIN'})) {
            die IO::Framed::X->create('WriteError', OS_ERROR => $!);
        }

        return undef;
    };

    if ($wrote == length $_[1]) {
        $_[0]->{'_write_queue_partial'} = 0;
        $_[2]->() if $_[2];
        return 1;
    }

    #Trim the bytes that we did send.
    substr( $_[1], 0, $wrote ) = q<>;

    #This seems useful to track … ??
    $_[0]->{'_write_queue_partial'} = 1;

    return 0;
}

1;
