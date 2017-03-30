package Net::WAMP::Transport::WebSocket::Client;

use strict;
use warnings;

use parent 'Net::WAMP::Transport::WebSocket';

use Net::WebSocket::Endpoint::Client ();
use Net::WebSocket::Frame::text ();
use Net::WebSocket::Mask ();
use Net::WebSocket::Parser ();
use Net::WebSocket::Handshake::Client ();

use HTTP::Response ();

use constant {
    FIRST_LINE_HEADER => 'HTTP/1.1 101',
    ENDPOINT_CLASS => 'Net::WebSocket::Endpoint::Client',
};

sub FRAME_MASK_ARGS {
    return( mask => Net::WebSocket::Mask::create() );
}

sub handshake {
    my ($self, $uri, $serialization ) = @_;

    $self->_verify_handshake_not_done();

    if (!$self->{'_sent_handshake'}) {
        $self->{'_recv_handshake'} = q<>;

        $self->_set_serialization_format($serialization);

        my $hshk = Net::WebSocket::Handshake::Client->new(
            uri => $uri,
            subprotocols => [ $self->SUBPROTOCOL_BASE . $serialization ],
            #origin => 'http://crossbar.io', #XXX
        );
        $self->{'_handshake_obj'} = $hshk;

        my $hdr_txt = $hshk->create_header_text();

        $self->_write_bytes(
            "$hdr_txt\x0d\x0a",
            sub { $self->{'_sent_handshake'} = 1 },
        );
    }

    else {
        my $was_blocking = $self->{'_in_fh'}->blocking(0);
        $self->_read_now(32768);
        $self->{'_in_fh'}->blocking(1) if $was_blocking;

        my $buf_sr = $self->_read_buffer_sr();

        my $crlf2x_idx = index($$buf_sr, "\x0d\x0a\x0d\x0a");

        if ( $crlf2x_idx == -1 ) {
            if (length($$buf_sr) >= length(FIRST_LINE_HEADER)) {
                if (substr( $$buf_sr, 0, length(FIRST_LINE_HEADER) ) ne FIRST_LINE_HEADER) {
                    print STDERR $$buf_sr;

                    die "HTTP failure";
                }
            }
        }
        else {
            my $resp = HTTP::Response->parse(
                substr( $$buf_sr, 0, 4 + $crlf2x_idx, q<> ),
            );

            #XXX convert to normal response
            $self->{'_handshake_obj'}->validate_accept_or_die(
                $resp->header('Sec-WebSocket-Accept'),
            );

            $self->{'_reader'} = Net::WebSocket::Parser->new( $self->{'_in_fh'}, $$buf_sr );

            $self->{'_endpoint'} = Net::WebSocket::Endpoint::Client->new(
                parser => $self->{'_reader'},
                out => $self->{'_out_fh'},
            );

            $self->{'_handshake_done'} = 1;
        }
    }

    return $self;
}

1;
