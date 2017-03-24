package Net::WAMP::Serialization::json;

use JSON ();

use constant {
    serialization => 'json',
    websocket_message_type => 'text',
};

my $_JSON;

#*stringify = *JSON::encode_json;
#*parse = *JSON::decode_json;

sub stringify {
    return ($_JSON ||= JSON->new()->utf8(0))->encode($_[0]);
}

sub parse {
    return ($_JSON ||= JSON->new()->utf8(0))->decode($_[0]);
}

1;
