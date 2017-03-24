package Net::WAMP::Transport::RawSocket;

#----------------------------------------------------------------------
# This could be refactored into just a RawSocket module, and another
# module to interface with Net::WAMP. But since RawSocket as WAMP defines
# it is explicitly only for use in WAMP, there seems little point to that.
#----------------------------------------------------------------------

use strict;
use warnings;

use parent qw(
    Net::WAMP::Transport
    Net::WAMP::Transport::Base::Handshaker
);

use Net::WAMP::Transport::RawSocket::Constants ();
use Net::WAMP::Transport::RawSocket::PingStore ();
use Net::WAMP::X ();

use constant {
    MSG_TYPE_REGULAR => 0,
    MSG_TYPE_PING => 1,
    MSG_TYPE_PONG => 2,

    DEFAULT_MAX_PINGS => 10,
};

use constant CONSTRUCTOR_OPTS => ('max_pings');

sub new {
    my ($class, @args) = @_;

    my $self = $class->SUPER::new(@args);

    $self->{'_ping_store'} = Net::WAMP::Transport::RawSocket::PingStore->new();
    $self->{'_max_pings'} ||= DEFAULT_MAX_PINGS;

    return $self;
}

sub max_output_size {
    my ($self) = @_;

    return $self->{'_max_output_size'};
}

sub _serialized_wamp_to_transport_bytes {
    if (length($_[1]) > $_[0]{'_max_output_size'}) {
        die sprintf('Attempt to send %d-byte message to a WAMP RawSocket peer that only accepts up to %d bytes per message.', length($_[1]), $_[0]{'_max_output_length'});
    }

    return pack('N', length $_[1]) . $_[1];
}

my ($msg_type_code, $msg_size);

sub _read_transport_message {
    my ($self) = @_;

    #i.e., we were in the middle of reading:
    if ($self->{'_msg_size'}) {
        ($msg_type_code, $msg_size) = @{$self}{ '_msg_type_code', '_msg_size' };
    }
    else {
        my $hdr = $self->_read_header();
        return if !length $hdr;

        my ($mt_code, $len1, $len2) = unpack 'CCn', $hdr;

        if ($mt_code > MSG_TYPE_PONG) {
            die sprintf("Unparsable RawSocket header (unrecognized lead byte): %v.02x", $hdr);
        }
        else {
            $msg_type_code = $mt_code;
            $msg_size = ($len1 << 16) + $len2;
        }
    }

    my $body = $self->_read_now($msg_size);

    #I’m guessing that partial reads will be very rare, so not
    #bothering to optimize for now.
    if (!length $body) {
        @{$self}{ '_msg_type_code', '_msg_size' } = (
            $msg_type_code,
            $msg_size,
        );
        return;
    }

    if ($msg_type_code == MSG_TYPE_REGULAR) {
        return $body;
    }
    elsif ($msg_type_code == MSG_TYPE_PING) {
        $self->_send_frame(MSG_TYPE_PONG, $body);
    }
    elsif ($msg_type_code == MSG_TYPE_PONG) {
        $self->{'_ping_store'}->remove($body);
    }

    return;
}

sub check_heartbeat {
    my ($self) = @_;

    my $ping_counter = $self->{'_ping_store'}->get_count();
    if ( $ping_counter == $self->{'_max_pings'} ) {
        $self->_set_shutdown();
        return 0;
    }

    $self->_send_frame( MSG_TYPE_PING, $self->{'_ping_store'}->add() );

    return 1;
}

sub shutdown {
    my ($self) = @_;
    $self->_set_shutdown();
    return 1;
}

sub _send_frame {
    my ($self, $type_code) = @_;    #$_[2] = body

    substr(
        $_[2],
        0, 0,
        pack(
            'CCn',
            $type_code,
            (length($_[2]) >> 16),
            (length($_[2]) & 0xffff),
        ),
    );

    return $self->_write_bytes($_[2]);
}

sub _read_header {
    my ($self) = @_;

    return $self->_read_now(
        Net::WAMP::Transport::RawSocket::Constants::HEADER_LENGTH(),
    );
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

    $self->{'_max_output_size'} = Net::WAMP::Transport::RawSocket::Constants::get_max_length_value($octet2 >> 4);

    my $recv_serializer_code = ($octet2 & 0xf);
    my $ser_name = Net::WAMP::Transport::RawSocket::Constants::get_serialization_name($recv_serializer_code);

    return( $octet2, $ser_name, $recv_serializer_code );
}

1;
