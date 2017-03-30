package Net::WAMP::Transport::RawSocket::Client;

use strict;
use warnings;

use parent 'Net::WAMP::Transport::RawSocket';

use Net::WAMP::Transport::RawSocket::Constants ();
use Net::WAMP::X ();

sub handshake {
    my ($self, %opts) = @_;

    #Possible states when this function is called:
    # a) Never called
    # b) Called, hasn’t written or read
    # c) Called, has partially written
    # d) Called, has fully written, nothing read
    # e) Called, has fully written, partially read

    #Breaking normal form in negative-if to have chronological order.

    #State A
    if (!$self->_serialization_is_set()) {
        $self->{'_max_input_size'} = $opts{'max_message_length'} || Net::WAMP::Transport::RawSocket::Constants::MAX_MESSAGE_LENGTH();

        my $serialization = $opts{'serialization'} || Net::WAMP::Transport::RawSocket::Constants::DEFAULT_SERIALIZATION();
        $self->_set_serialization_format($serialization);

        $self->{'_rs_serialization_code'} = Net::WAMP::Transport::RawSocket::Constants::get_serialization_code($serialization);

        $self->_write_bytes(
            _create_client_handshake(
                $self->{'_max_input_size'},
                $serialization,
            ),
            sub {
                $self->{'_sent_handshake'} = 1;
            },
        );
    }

    #States B and C end here

    #States D and E
    if ($self->{'_sent_handshake'}) {
        my ($octet2, $ser_name, $resp_serializer_code) = $self->_get_and_unpack_handshake_header();

        #States D and E exit here; only continue if got the full header.
        if (defined $octet2) {
            if ( !$resp_serializer_code ) {
                my $err_code = $octet2 >> 4;
                my $err_str = $self->can("HANDSHAKE_ERR_$err_code");
                $err_str = $err_str ? '[' . $err_str->() . ']' : q<>;

                die "Handshake error: [$err_code]$err_str\n"
            }

            #I wonder why the client and router have to use the same serializer??
            if ( $resp_serializer_code != $self->{'_rs_serialization_code'} ) {
                die "Protocol error: response serializer ($resp_serializer_code) != sent ($self->{'_rs_serialization_code'})\n";
            }

            $self->_set_handshake_done();
        }
    }

    return;
}

#static
sub _create_client_handshake {
    my ($max_len, $serialization) = @_;

    my $max_len_code = Net::WAMP::Transport::RawSocket::Constants::get_max_length_code($max_len);

    my $serialization_code = Net::WAMP::Transport::RawSocket::Constants::get_serialization_code($serialization);

    return pack(
        'C*',
        Net::WAMP::Transport::RawSocket::Constants::MAGIC_FIRST_OCTET(),
        ($max_len_code << 4) + $serialization_code,
        0, 0,   #reserved
    );
}

1;
