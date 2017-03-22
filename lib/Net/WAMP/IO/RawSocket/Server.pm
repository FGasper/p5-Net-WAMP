package Net::WAMP::IO::RawSocket::Server;

use strict;
use warnings;

use parent 'Net::WAMP::IO::RawSocket';

use Net::WAMP::IO::RawSocket::Constants ();

sub handshake {
    my ($self, %opts) = @_;

    $self->{'_max_input_size'} ||= $opts{'max_message_length'} || Net::WAMP::IO::RawSocket::Constants::MAX_MESSAGE_LENGTH();

print STDERR "hs1\n";
    if (!$self->_serialization_is_set()) {
print STDERR "hs2\n";
        my ($octet2, $ser_name, $serializer_code) = $self->_get_and_unpack_handshake_header();

        if (defined $octet2) {
print STDERR "hs3\n";
            $self->_set_serialization_format($ser_name);

            my $max_len_code = Net::WAMP::IO::RawSocket::Constants::get_max_length_code($self->{'_max_input_size'});

            $self->_enqueue_write(
                pack(
                    'C*',
                    Net::WAMP::IO::RawSocket::Constants::MAGIC_FIRST_OCTET(),
                    ($max_len_code << 4) + $serializer_code,
                    0, 0,   #reserved
                ),
                sub {
print STDERR "handshake DONE\n";
                    $self->_set_handshake_done();
                },
            );

            #This function shouldn’t be called anymore unless the client
            #for some reason sends more data to be read before we get a
            #chance to write.
        }
    }

    return;
}

1;
