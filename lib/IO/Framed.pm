package IO::Framed;

use strict;
use warnings;

use IO::Framed::X ();

=encoding utf-8

=head1 NAME

IO::Framed - Convenience wrapper for frame-based I/O

=head1 SYNOPSIS

    my $blocking = IO::Framed::Blocking->new( $in_fh, $out_fh );

    #This returns empty-string if the $in_fh doesn’t have at least the
    #the given number (5 in this case) of bytes to read.
    $frame = $blocking->read(5);

    $blocking->write('hoohoo');

    #----------------------------------------------------------------------

    my $nblocking = IO::Framed::NonBlocking->new( $in_fh, $out_fh );

    #Same pattern as above. On EINTR, the read will be repeated.
    #Any other failure, normally including EAGAIN, will cause an
    #appropriate exception to be thrown.
    #
    #An empty read without an error
    #also prompts an exception, since this means there will not be
    #anything further to read from the stream.

    $frame = $nblocking->read(5);

    {
        #While this special $allower object exists, $nblocking
        #will treat EAGAIN as a non-fatal empty read.
        my $allower = $nblocking->get_EAGAIN_allower();

        $frame = $nblocking->read(5);
    }

    #The second parameter is executed immediately after the final
    #byte of the payload is written.
    $nblocking->enqueue_write('hoohoo', sub { warn 'I’m written!' } );

    if ( $nblocking->get_write_size_queue() > 0 ) {

        #Returns 1 if the queue is empty on return; 0 otherwise.
        #(This will also throw on EAGAIN!)
        $nblocking->flush_write_queue();
    }

=head1 DESCRIPTION

While writing L<Net::WAMP> I noticed that I was reimplementing some of the
same patterns I’d used in L<Net::WebSocket> to parse frames from a stream:

=over

=item * Continuance when a partial frame is delivered

=item * Blocking and non-blocking I/O

=item * Write queue with callbacks for non-blocking I/O

=item * Signal resilience: resume read/write after Perl receives a trapped
signal rather than throwing/giving EINTR. (cf. L<IO::SigGuard>)

=back

These are now made available in this distribution.

=head1 ABOUT READS

The premise here is that you expect a given number of bytes at a given time
and that a partial read should be continued once it is sensible to do so.

As a result, C<read()> will throw an exception if the number of bytes given
for a continuance is not the same number as were originally requested.

Example:

    #This reads only 2 bytes, so read() will return empty-string.
    $framed->read(10);

    #… wait for readiness if non-blocking …

    #XXX This die()s because we’re in the middle of trying to read
    #10 bytes, not 4.
    $framed->read(4);

    #If this completes the read (i.e., takes in 8 bytes), then it’ll
    #return the full 10 bytes; otherwise, it’ll return empty-string again.
    $framed->read(10);

=head1 ABOUT WRITES

Blocking writes are straightforward: the system will always send the entire
buffer.

Non-blocking writes are trickier. Since we can’t know that the output
filehandle is ready right when we want it, we have to queue up our writes
then write them once we know (e.g., through C<select()>) that the filehandle
is ready.

Since it’s often useful to know when a payload has been sent,
C<enqueue_write()> accepts a callback that will be executed immediately
after the last byte of the payload is written to the output filehandle.

=head1 EXCEPTIONS THROWN

All exceptions subclass L<X::Tiny::Base>.

=head2 IO::Frame::X::ReadError

=head2 IO::Frame::X::WriteError

These both have an C<OS_ERROR> property.

=head2 IO::Frame::X::EmptyRead

No properties. If this is thrown, your peer has probably closed the connection.

=cut

sub new {
    my ( $class, $in_fh, $out_fh, $initial_buffer ) = @_;

    if ( !defined $initial_buffer ) {
        $initial_buffer = q<>;
    }

    my $self = {
        _in_fh         => $in_fh,
        _out_fh        => $out_fh,
        _read_buffer   => $initial_buffer,
        _bytes_to_read => 0,
    };

    return bless $self, $class;
}

#It is by design that these are not exposed.
#sub get_input_fh { return $_[0]->{'_in_fh'} }
#sub get_output_fh { return $_[0]->{'_out_fh'} }

#----------------------------------------------------------------------
# IO subclass interface

my $buf_len;

#We assume here that whatever read may be incomplete at first
#will eventually be repeated so that we can complete it. e.g.:
#
#   - read 4 bytes, receive 1, cache it - return q<>
#   - select()
#   - read 4 bytes again; since we already have 1 byte, only read 3
#       … and now we get the remaining 3, so return the buffer.
#
sub read {
    my ( $self, $bytes ) = @_;

    die "I refuse to read zero!" if !$bytes;

    if ( $buf_len = length $self->{'_read_buffer'} ) {
        if ( $buf_len + $self->{'_bytes_to_read'} != $bytes ) {
            my $should_be = $buf_len + $self->{'_bytes_to_read'};
            die "Continuation: should want “$should_be” bytes, not $bytes!";
        }
    }

    if ( $bytes > $buf_len ) {
        $bytes -= $buf_len;

        local $!;

        $bytes -= IO::SigGuard::sysread( $self->{'_in_fh'}, $self->{'_read_buffer'}, $bytes, $buf_len ) || do {
            if ($!) {

                #                if ( !$self->{'_allow_EAGAIN'} || !$!{'EAGAIN'} ) {
                if ( !$!{'EAGAIN'} ) {
                    die IO::Framed::X->create( 'ReadError', OS_ERROR => $! );
                }
            }
            else {
                die IO::Framed::X->create('EmptyRead');
            }
        };
    }

    $self->{'_bytes_to_read'} = $bytes;

    if ($bytes) {
        return q<>;
    }

    return substr( $self->{'_read_buffer'}, 0, length($self->{'_read_buffer'}), q<> );
}

sub get_EAGAIN_allower {
    my ($self) = @_;

    return IO::Framed::_EAGAIN_Allower->new($self);
}

#----------------------------------------------------------------------

#package IO::Framed::_EAGAIN_Allower;
#
#sub {
#    my ( $class, $framed_obj ) = @_;
#
#    $framed_obj->{'_allow_EAGAIN'}++;
#
#    return bless \$framed_obj, $class;
#  }
#
#  sub DESTROY {
#    my ($self) = @_;
#
#    ($$self)->{'_allow_EAGAIN'}--;
#
#    return;
#}

#----------------------------------------------------------------------

=head1 REPOSITORY

L<https://github.com/FGasper/p5-IO-Framed>

=head1 AUTHOR

Felipe Gasper (FELIPE)

=head1 COPYRIGHT

Copyright 2017 by L<Gasper Software Consulting, LLC|http://gaspersoftware.com>

=head1 LICENSE

This distribution is released under the same license as Perl.

=cut

1;
