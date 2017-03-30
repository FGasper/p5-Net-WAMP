package Net::WAMP::RawSocket::Base::IO;

use strict;
use warnings;

use constant {
    OPCODE_CLASS_0 => 'Net::WAMP::RawSocket::Message::Regular',
    OPCODE_CLASS_1 => 'Net::WAMP::RawSocket::Message::Ping',
    OPCODE_CLASS_2 => 'Net::WAMP::RawSocket::Message::Pong',
}

1;
