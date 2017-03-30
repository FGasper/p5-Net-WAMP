package Net::WAMP::RawSocket::Parser;

use strict;
use warnings;

use Net::WAMP::RawSocket::Message::Regular ();
use Net::WAMP::RawSocket::Message::Ping ();
use Net::WAMP::RawSocket::Message::Pong ();

use constant {
    OPCODE_CLASS_0 => 'Net::WAMP::RawSocket::Message::Regular',
    OPCODE_CLASS_1 => 'Net::WAMP::RawSocket::Message::Ping',
    OPCODE_CLASS_2 => 'Net::WAMP::RawSocket::Message::Pong',
};

use Net::WAMP::X ();

sub new {
    my ($class, $io, $max_msg_size) = @_;

    my $self = {
        _io => $io,
        _max_msg_size => $max_msg_size,
    };

    return bless $self, $class;
}



#my ($this_read, $buf_len);

sub _read_now {
    return $_[0]->{'_io'}->read($_[1]);
#    my ($self, $bytes) = @_;
#
#    $buf_len = length $self->{'_buf'};
#
#    if ($bytes > $buf_len) {
#        $this_read = $self->{'_io'}->read( $bytes - $buf_len );
#
#        if (length $this_read) {
#            substr( $this_read, 0, 0, substr( $self->{'_buf'}, 0, $buf_len, q<> ) );
#        }
#
#        return $this_read;
#    }
#
#    return substr( $self->{'_buf'}, 0, $bytes, q<> );
}

1;
