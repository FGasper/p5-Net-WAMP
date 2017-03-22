package Net::WAMP::IO::WebSocket::Client;

use strict;
use warnings;

use parent 'Net::WAMP::IO::WebSocket';

use lib '/Users/Felipe/code/p5-Net-WebSocket/lib';

use Net::WebSocket::Endpoint::Client ();
use Net::WebSocket::Frame::text ();
use Net::WebSocket::Mask ();
use Net::WebSocket::Parser ();
use Net::WebSocket::Handshake::Client ();

sub FRAME_MASK_ARGS {
    return( mask => Net::WebSocket::Mask::create() );
}

sub handshake {
    my ($self, $uri, $serialization ) = @_;

    $self->_verify_handshake_not_done();

    my $hshk = Net::WebSocket::Handshake::Client->new(
        uri => $uri,
        subprotocols => [ $self->SUBPROTOCOL_BASE . $serialization ],
        #origin => 'http://crossbar.io', #XXX
    );

    my $hdr_txt = $hshk->create_header_text();
    $hdr_txt .= join( "\x0d\x0a",
        #'User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_12_3) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/56.0.2924.87 Safari/537.36',
        #'Cookie: _ga=GA1.2.299028825.1487716663; cbdemo=nLk7U1Q5ExP55EFtuKSzixyL',
        q<>,
    );

    local $!;

    print STDERR "hdr:\n$hdr_txt\n";

    syswrite( $self->{'_out_fh'}, "$hdr_txt\x0d\x0a" );

    #----------------------------------------------------------------------
    #XXX Cheat for now, and just assume that the headers we receive are valid.

    my $was_blocking = $self->{'_in_fh'}->blocking(1);

    my $buf = q<>;
    while ($buf !~ s<\A.+\x0a\x0d?\x0a><>s) {
        sysread( $self->{'_in_fh'}, $buf, 1024, length $buf );

        if ($buf =~ m<\n>) {
            if ($buf !~ m<\AHTTP/1.1 101>) {
                print STDERR $buf;
                while (sysread $self->{'_in_fh'}, $buf, 1024 ) {
                    print STDERR $buf;
                }

                die "HTTP failure";
            }
        }
    }

    $self->{'_in_fh'}->blocking(0) if !$was_blocking;

    #----------------------------------------------------------------------

    $self->{'_reader'} = Net::WebSocket::Parser->new( $self->{'_in_fh'}, $buf );

    $self->_set_serialization_format($serialization);

    $self->{'_endpoint'} = Net::WebSocket::Endpoint::Client->new(
        parser => $self->{'_reader'},
        out => $self->{'_out_fh'},
    );

    $self->{'_handshake_done'} = 1;
print STDERR "done WebSocket handshake\n";

    return $self;
}

1;
