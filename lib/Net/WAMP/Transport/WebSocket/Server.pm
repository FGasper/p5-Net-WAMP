package Net::WAMP::Transport::WebSocket::Server;

use strict;
use warnings;
use autodie;

use parent 'Net::WAMP::Transport::WebSocket';

use Net::WebSocket::Endpoint::Server ();
use Net::WebSocket::Mask ();
use Net::WebSocket::Parser ();
use Net::WebSocket::Handshake::Server ();

use constant CRLF => "\x0d\x0a";

use constant FRAME_MASK_ARGS => ();

use HTTP::Request ();

sub handshake {
    my ($self) = @_;

    $self->_verify_handshake_not_done();

    my $was_blocking = $self->{'_in_fh'}->blocking(0);

    #A sufficiently large read size that it should accommodate
    #any WebSocket header set.
print STDERR "reading\n";
    $self->_read_now(65536);
print STDERR "done _read_now\n";

    $self->{'_in_fh'}->blocking(1) if $was_blocking;

    my $buf_sr = $self->_read_buffer_sr();

    my $hdrs_end_idx = index($$buf_sr, CRLF . CRLF);
print STDERR "buf($hdrs_end_idx): [$$buf_sr]\n";

    if (-1 != $hdrs_end_idx) {
print STDERR "can parse headesr\n";
        my $rqt = HTTP::Request->parse( substr( $$buf_sr, 0, 4 + $hdrs_end_idx, q<> ) );

        #validate headers … TODO

        my $serialization;

        for my $subproto ( $rqt->header('Sec-WebSocket-Protocol') ) {
            next if 0 != index( $subproto, $self->SUBPROTOCOL_BASE() );
            $serialization = substr( $subproto, length $self->SUBPROTOCOL_BASE() );
            last;
        }

        if (!defined $serialization) {
            die "No serialization!";    #XXX
        }
        #XXX TODO verify serialization

        my $hshk = Net::WebSocket::Handshake::Server->new(
            key => $rqt->header('Sec-WebSocket-Key'),
            subprotocols => [ $self->SUBPROTOCOL_BASE() . $serialization ],
        );

        $self->_write_bytes(
            $hshk->create_header_text() . CRLF,
            sub {

                $self->{'_reader'} = Net::WebSocket::Parser->new( $self->{'_in_fh'}, $$buf_sr );

                $self->_set_serialization_format($serialization);

                $self->{'_endpoint'} = Net::WebSocket::Endpoint::Server->new(
                    parser => $self->{'_reader'},
                    out => $self->{'_out_fh'},
                );

                $self->_set_handshake_done();
            },
        );
    }

    return;
}

1;
