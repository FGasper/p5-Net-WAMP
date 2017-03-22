package Net::WAMP::IO::RawSocket;

use strict;
use warnings;

use parent qw(
    Net::WAMP::IO::Base::Streamer
    Net::WAMP::IO::Base::Handshaker
);

use Net::WAMP::IO::RawSocket::Constants ();
use Net::WAMP::X ();

sub new {
    my ($class, @args) = @_;

    my $self = $class::SUPER->new(@args);

    $self->{'_rbuf'} = q<>;

    return $self;
}

#sub _read_header_blocked {
#    my ($self) = @_;
#
#    my $hdr;
#
#    my $was_blocking = $self->{'_in_fh'}->blocking(1);
#
#    $hdr = $self->_read_header() while !$hdr;
#
#    $self->{'_in_fh'}->blocking(0) if !$was_blocking;
#
#    return $hdr;
#}

sub _read_header {
    my ($self) = @_;

    local $!;

    sysread(
        $self->{'_in_fh'},
        $self->{'_rbuf'},
        Net::WAMP::IO::RawSocket::Constants::HEADER_LENGTH() - $resp_hdr,
        length $self->{'_rbuf'},
    ) or do {
        if (!$!{'EINTR'}) {
            die Net::WAMP::X->create('ReadError', OS_ERROR => $!);
        }
    };

    if (Net::WAMP::IO::RawSocket::Constants::HEADER_LENGTH() == length $self->{'_rbuf'}) {
        return substr( $self->{'_rbuf'}, 0, 4 );
    }

    return undef;
}

sub _get_and_unpack_handshake_header {
    my ($self) = @_;

    my $recv_hdr = $self->_read_header() or return;

    my ($octet1, $octet2, $reserved) = unpack 'CCa2', $resp_hdr;

    if ($reserved ne "\0\0") {
        die sprintf("Unsupported feature (reserved = %v.02x)", $reserved);
    }

    if ($octet1 ne MAGIC_FIRST_OCTET()) {
        die "Invalid first octet ($octet1)!";
    }

    $self->{'_max_output_size'} = $self->_get_max_length_value($octet2 >> 4);

    my $recv_serializer_code = ($octet2 & 0xf);
    my $ser_name = Net::WAMP::IO::RawSocket::Constants::get_serialization_name($recv_serializer_code);

    return( $octet2, $ser_name, $recv_serializer_code );
}

1;
