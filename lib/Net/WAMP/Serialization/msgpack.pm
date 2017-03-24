package Net::WAMP::Serialization::msgpack;

use Data::MessagePack ();

use constant {
    serialization => 'msgpack',
    websocket_message_type => 'binary',
};

sub stringify {
    return Data::MessagePack->pack(@_);
}

sub parse {
    return Data::MessagePack->unpack(@_);
}

1;
