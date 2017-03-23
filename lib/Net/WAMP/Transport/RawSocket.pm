package Net::WAMP::Transport::RawSocket;

use strict;
use warnings;

use parent qw(
    Net::WAMP::Transport
    Net::WAMP::Transport::Base::Handshaker
);

use Net::WAMP::Transport::RawSocket::Constants ();
use Net::WAMP::X ();

sub new {
    my ($class, @args) = @_;

    my $self = $class->SUPER::new(@args);

    @{$self}{ '_rbuf', '_max_output_size' } = q<>;

    return $self;
}

sub max_output_size {
    my ($self) = @_;

    return $self->{'_max_output_size'};
}

sub _serialized_wamp_to_transport_bytes {
use Data::Dumper;
print STDERR Dumper(@_);
    if (length($_[1]) > $_[0]{'_max_output_size'}) {
        die sprintf('Attempt to send %d-byte message to a WAMP RawSocket peer that only accepts up to %d bytes per message.', length($_[1]), $_[0]{'_max_output_length'});
    }

    return pack('N', length $_[1]) . $_[1];
}

use Carp::Always;
my $msg_type_code;

sub _read_transport_message {
    my ($self) = @_;

    if ($self->{'_pending_bytes'}) {
        $self->_read( $self->{'_pending_bytes'} ) and return;
        $msg_type_code = delete $self->{'_pending_msg_type_code'};
    }
    else {
        my $hdr = $self->_read_header() or return;

        if ( ($msg_type_code = ord(substr $hdr, 0, 1)) < 3) {
            $self->_read( unpack 'N', $hdr ) and do {
                $self->{'_pending_msg_type_code'} = $msg_type_code;
                return;
            };
        }
        else {
            die sprintf("Unrecognized lead byte: %02x", $msg_type_code);
        }
    }

    if ($msg_type_code == 0) {
        return substr( $self->{'_rbuf'}, 0, length($self->{'_rbuf'}), q<> );
    }
    elsif ($msg_type_code == 1) {   #ping
        #TODO: send ping
    }
    else {
        #TODO: send pong
    }

    return;
}

sub _read {
    my ($self, $bytes) = @_;

    local $!;

  READ: {
        $bytes -= sysread( $self->{'_in_fh'}, $self->{'_rbuf'}, $bytes, length $self->{'_rbuf'} ) || do {
            if ($!) {
                redo if $!{'EINTR'};
                die Net::WAMP::X->create('ReadError', OS_ERROR => $!);
            }

            die Net::WAMP::X->create('EmptyRead');
        };
    }

    return $self->{'_pending_bytes'} = $bytes;
}

sub _read_header {
    my ($self) = @_;

    $self->_read(Net::WAMP::Transport::RawSocket::Constants::HEADER_LENGTH()) and return;

    return substr( $self->{'_rbuf'}, 0, 4, q<> );
}

sub _get_and_unpack_handshake_header {
    my ($self) = @_;

    my $recv_hdr = $self->_read_header() or return;

    my ($octet1, $octet2, $reserved) = unpack 'CCa2', $recv_hdr;

    if ($reserved ne "\0\0") {
        die sprintf("Unsupported feature (reserved = %v.02x)", $reserved);
    }

    if ($octet1 ne Net::WAMP::Transport::RawSocket::Constants::MAGIC_FIRST_OCTET()) {
        die "Invalid first octet ($octet1)!";
    }

print STDERR "before _get_max_length_value\n";
    $self->{'_max_output_size'} = Net::WAMP::Transport::RawSocket::Constants::get_max_length_value($octet2 >> 4);

    my $recv_serializer_code = ($octet2 & 0xf);
    my $ser_name = Net::WAMP::Transport::RawSocket::Constants::get_serialization_name($recv_serializer_code);

    return( $octet2, $ser_name, $recv_serializer_code );
}

1;
