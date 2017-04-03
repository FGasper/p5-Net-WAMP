package Net::WAMP::RawSocket;

use strict;
use warnings;

use Net::WAMP::RawSocket::Constants ();
use Net::WAMP::RawSocket::PingStore ();

use Net::WAMP::RawSocket::Message::Regular ();
use Net::WAMP::RawSocket::Message::Ping ();
use Net::WAMP::RawSocket::Message::Pong ();

use constant {
    MSG_TYPE_REGULAR => 0,
    MSG_TYPE_PING => 1,
    MSG_TYPE_PONG => 2,

    DEFAULT_MAX_PINGS => 10,
};

use constant REQUIRED_CONSTRUCTOR_OPTS => ('io');

use constant OTHER_CONSTRUCTOR_OPTS => (
    'max_pings',
    'max_receive_length',
);

sub new {
    my ($class, %opts) = @_;

    my @missing = grep { !exists $opts{$_} } $class->REQUIRED_CONSTRUCTOR_OPTS();
    die "Need [@missing]!" if @missing;

    my $self = {
        _max_pings => $class->DEFAULT_MAX_PINGS,
        _max_receive_length => Net::WAMP::RawSocket::Constants::MAX_MESSAGE_LENGTH(),

        (
            map { exists($opts{$_}) ? ("_$_" => $opts{$_}) : () }
            $class->REQUIRED_CONSTRUCTOR_OPTS(),
            $class->OTHER_CONSTRUCTOR_OPTS(),
        ),

        _ping_store => Net::WAMP::RawSocket::PingStore->new(),
    };

    return bless $self, $class;
}

sub send_message {
    my ($self) = @_;

    die 'Handshake not completed!' if !$self->{'_handshake_ok'};

    if (length($_[1]) > $self->{'_max_send_length'}) {
        die "Too long!";    #XXX
    }

    $self->_send_frame(MSG_TYPE_REGULAR, @_[ 1 .. $#_ ]);

    return;
}

my ($msg_type_code, $msg_class_cr, $msg_size, $len1, $len2, $msg_body_r);

sub get_next_message {
    my ($self) = @_;

  MESSAGE: {

        #i.e., we were in the middle of reading:
        if ($self->{'_msg_size'}) {
            ($msg_class_cr, $msg_type_code, $msg_size) = @{$self}{ '_msg_class_cr', '_msg_type_code', '_msg_size' };
        }
        else {
            my $hdr = $self->_read_header() or return undef;

            ( $msg_type_code, $len1, $len2 ) = unpack 'CCn', $hdr;

            $msg_size = ($len1 << 16) | $len2;  #“|” is much faster than +

            if ($msg_size > $self->{'_max_receive_length'}) {
                die Net::WAMP::X->create('RawSocket::ReceivedTooBig');  #XXX
            }
        }

        $msg_body_r = \$self->{'_io'}->read($msg_size);

        #print STDERR "received-rs/$$ $$msg_body_r\n";

        if ($msg_type_code == MSG_TYPE_REGULAR()) {

            #Partial reads should (?) be very rare, so not
            #bothering to optimize for now.
            if (!$msg_size || length $$msg_body_r) {
                $self->{'_msg_size'} = 0;

                #It’s a bit less-than-tidy to commingle the “endpoint”
                #behavior (e.g., ping/pong) with the message parsing,
                #but it can be refactored later if that’s an issue.

                return bless $msg_body_r, 'Net::WAMP::RawSocket::Message::Regular';
            }
            else {
                @{$self}{ '_msg_class_cr', '_msg_type_code', '_msg_size' } = (
                    $msg_class_cr,
                    $msg_type_code,
                    $msg_size,
                );
            }

            return undef;
        }
        elsif ($msg_type_code == MSG_TYPE_PING()) {
            $self->_send_frame(MSG_TYPE_PONG, $$msg_body_r);
            redo MESSAGE;
        }
        elsif ($msg_type_code == MSG_TYPE_PONG()) {
            $self->{'_ping_store'}->remove($$msg_body_r);
            redo MESSAGE;
        }
        else {
            die "Huh?? Unknown message type: [$msg_type_code]";
        }
    }

    #Empty message …
    return bless \do { my $v = q<> }, 'Net::WAMP::RawSocket::Message::Regular';
}

sub check_heartbeat {
    my ($self) = @_;

    my $ping_counter = $self->{'_ping_store'}->get_count();
    if ( $ping_counter == $self->{'_max_pings'} ) {
        $self->shutdown();
        return 0;
    }

    my $text = $self->{'_ping_store'}->add();

    $self->_send_frame(MSG_TYPE_PING, $text);

    return 1;
}

sub get_serialization {
    return $_[0]->{'_serialization'};
}

sub get_max_send_length {
    return $_[0]->{'_max_send_length'};
}

sub get_max_receive_length {
    return $_[0]->{'_max_receive_length'};
}

#----------------------------------------------------------------------

sub _set_handshake_done {
    $_[0]->{'_handshake_ok'} = 1;

    return;
}

sub _send_frame {
    my ($self, $type_num) = @_;

    #print STDERR "rs-write/$$: $_[2]\n";

    _prefix_header( $type_num, $_[2] );

    $self->_send_bytes( @_[ 2 .. $#_ ] );

    return;
}

sub _read_header {
    my ($self) = @_;

    return $self->{'_io'}->read(
        Net::WAMP::RawSocket::Constants::HEADER_LENGTH(),
    );
}

sub _send_bytes {
    my ($self) = @_;    #bytes, callback

    $self->{'_io'}->write(@_[1 .. $#_]);

    return;
}

sub _get_and_unpack_handshake_header {
    my ($self) = @_;

    my $recv_hdr = $self->_read_header();

    if ($recv_hdr) {
        my ($octet1, $octet2, $reserved) = unpack 'CCa2', $recv_hdr;

        if ($octet1 ne Net::WAMP::RawSocket::Constants::MAGIC_FIRST_OCTET()) {
            die sprintf("Invalid first octet (header = %v.02x)!", $recv_hdr);
        }

        if ($reserved ne "\0\0") {
            die sprintf("Unsupported feature (reserved = %v.02x)", $reserved);
        }

        $self->{'_max_send_length'} = Net::WAMP::RawSocket::Constants::get_max_length_value($octet2 >> 4);

        my $recv_serializer_code = ($octet2 & 0xf);
        my $ser_name = Net::WAMP::RawSocket::Constants::get_serialization_name($recv_serializer_code);

        return( $octet2, $ser_name, $recv_serializer_code );
    }

    return undef;
}

#----------------------------------------------------------------------

#In the interest of saving memory, this alters the passed-in string.
#TODO: Deduplicate
sub _prefix_header {
    my ($type_code) = @_;    #bytes is the third parameter

    substr(
        $_[1],
        0, 0,
        pack(
            'CCn',
            $type_code,
            (length($_[1]) >> 16),
            (length($_[1]) & 0xffff),
        ),
    );

    return;
}

1;
