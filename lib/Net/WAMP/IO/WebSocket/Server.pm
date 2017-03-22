package Net::WAMP::IO::WebSocket::Server;

use strict;
use warnings;
use autodie;

use parent 'Net::WAMP::IO::WebSocket';

use lib '/Users/Felipe/code/p5-Net-WebSocket/lib';

use Net::WebSocket::Endpoint::Server ();
use Net::WebSocket::Mask ();
use Net::WebSocket::Parser ();
use Net::WebSocket::Handshake::Server ();
use Net::WebSocket::X ();

use constant CRLF => "\x0d\x0a";

use constant FRAME_MASK_ARGS => ();

use HTTP::Request ();

sub handshake {
    my ($self) = @_;

    $self->_verify_handshake_not_done();

    my $buf = delete $self->{'_fd_handshake_buffer'};

    if ( !defined $buf ) {
        $buf = q<>;
    }

    local $!;

printf "read from fd %d\n", fileno( $self->{'_in_fh'} );
use Carp::Always;
    sysread( $self->{'_in_fh'}, $buf, 32768, length $buf ) or do {
        die "read err: $!" if $! && !$!{'EINTR'}; #XXX
        return;
    };
print "did read\n";

    my $hdrs_end_idx = index($buf, CRLF . CRLF);

    if (-1 eq $hdrs_end_idx ) {
        $self->{'_fd_handshake_buffer'} = $buf;
    }
    else {
        my $rqt = HTTP::Request->parse( substr( $buf, 0, 4 + $hdrs_end_idx, q<> ) );

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

print "enqueuing handshake send\n";
        $self->_enqueue_write(
            $hshk->create_header_text() . CRLF,
            sub {
print "done sending handshake\n";

                $self->{'_reader'} = Net::WebSocket::Parser->new( $self->{'_in_fh'}, $buf );

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
