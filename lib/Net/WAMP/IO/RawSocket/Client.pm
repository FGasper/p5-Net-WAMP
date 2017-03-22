package Net::WAMP::IO::RawSocket::Client;

use strict;
use warnings;

use parent 'Net::WAMP::IO::RawSocket';

use Net::WAMP::IO::RawSocket::Constants ();
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
        $self->{'_max_input_size'} = $opts{'max_message_length'} || $self->MAX_MESSAGE_LENGTH();

        my $serialization = $opts{'serialization'} || $self->DEFAULT_SERIALIZATION();
        $self->_set_serialization_format($serialization);

        my $max_len_code = Net::WAMP::IO::RawSocket::Constants::get_max_length_code($self->{'_max_input_size'});

        $self->{'_rs_serialization_code'} = Net::WAMP::IO::RawSocket::Constants::get_serialization_code($serialization);

        $self->_enqueue_write(
            pack(
                'C*',
                MAGIC_FIRST_OCTET(),
                ($max_len_code << 4) + $self->{'_rs_serialization_code'},
                0, 0,   #reserved
            ),
            sub {
                $self->{'_sent_handshake'} = 1;
            },
        );
    }

    #States B and C end here

    #States D and E
    elsif ($self->{'_sent_handshake'}) {
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
                die "Protocol error: response serializer ($resp_serializer_code) != sent ($serializer_code)\n";
            }

            $self->_set_handshake_done();
        }
    }

    return;
}

1;
